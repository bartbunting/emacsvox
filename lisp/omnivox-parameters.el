;;; omnivox-parameters.el --- Asynchronous engine controls -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Read-only discovery on the actual speech connection.  No waits, synthesis,
;; automatic busy retries, worker starts or registry changes.  Views retain a
;; detachable waiter and a current-buffer/draft predicate; callbacks run later.

;;; Code:
(require 'omnivox-parameters-codec)
(require 'tts-queue-state)

(declare-function omnivox--send-control-request "omnivox-voices" (process request callback))
(declare-function omnivox--pending-requests "omnivox-voices" (process))
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function tts--dispatch-copy-data "tts-speak" (value))
(defvar omnivox-voice-configuration-timeout)
(defvar omnivox--control-inventory-property)
(defvar tts-stopped-hook)
(defvar omnivox-parameters--last-error nil
  "Most recent callback error, recorded without notification speech.")

(cl-defstruct (omnivox-parameters--waiter (:constructor omnivox-parameters--make-waiter))
  callback current process epoch operation timer cancelled)
(cl-defstruct (omnivox-parameters--query (:constructor omnivox-parameters--make-query))
  process epoch engine voice waiters pending timer step identity mappings
  parameters cursors finished)

(defun omnivox-parameters--epoch (process)
  "Capture PROCESS's connection and inventory generation."
  (list (process-get process 'tts--speech-process-generation)
        (plist-get (process-get process omnivox--control-inventory-property) :inventory_generation)))

(defun omnivox-parameters--current-p (query)
  "Return non-nil while QUERY still belongs to its speech worker."
  (let ((process (omnivox-parameters--query-process query)))
    (and (process-live-p process)
         (not (process-get process 'tts--speech-process-retiring))
         (equal (omnivox-parameters--query-epoch query) (omnivox-parameters--epoch process)))))

(defun omnivox-parameters--cancel (waiter)
  "Detach WAITER without stopping speech or another view's query."
  (setf (omnivox-parameters--waiter-cancelled waiter) t
        (omnivox-parameters--waiter-callback waiter) nil
        (omnivox-parameters--waiter-current waiter) nil)
  (when (timerp (omnivox-parameters--waiter-timer waiter))
    (cancel-timer (omnivox-parameters--waiter-timer waiter)))
  (when-let* ((query (omnivox-parameters--waiter-operation waiter)))
    (setf (omnivox-parameters--query-waiters query)
          (delq waiter (omnivox-parameters--query-waiters query))))
  (setf (omnivox-parameters--waiter-operation waiter) nil))

(defun omnivox-parameters--deliver (waiter result)
  "Deliver independent RESULT to a still-current WAITER outside the filter."
  (unless (omnivox-parameters--waiter-cancelled waiter)
    (unwind-protect
        (condition-case err
            (when (or (null (omnivox-parameters--waiter-current waiter))
                      (funcall (omnivox-parameters--waiter-current waiter)))
              (when (and (eq (plist-get result :status) 'ready)
                         (let ((process (omnivox-parameters--waiter-process waiter)))
                           (not (and (process-live-p process)
                                     (not (process-get process 'tts--speech-process-retiring))
                                     (equal (omnivox-parameters--waiter-epoch waiter)
                                            (omnivox-parameters--epoch process))))))
                (setq result '(:status stale :message "Speech connection or inventory changed")))
              (funcall (omnivox-parameters--waiter-callback waiter) result))
          (error (setq omnivox-parameters--last-error err)))
      (omnivox-parameters--cancel waiter))))

(defun omnivox-parameters--notify (waiter result)
  "Schedule RESULT for WAITER, including immediate unsupported/busy outcomes."
  (setf (omnivox-parameters--waiter-timer waiter)
        (run-at-time 0 nil #'omnivox-parameters--deliver waiter (tts--dispatch-copy-data result))))

(defun omnivox-parameters--finish (query result)
  "Retire QUERY exactly once and schedule its remaining observers with RESULT."
  (unless (omnivox-parameters--query-finished query)
    (setf (omnivox-parameters--query-finished query) t)
    (dolist (timer (list (omnivox-parameters--query-timer query) (omnivox-parameters--query-step query)))
      (when (timerp timer) (cancel-timer timer)))
    (let ((process (omnivox-parameters--query-process query)))
      (when (omnivox-parameters--query-pending query)
        (let* ((id (omnivox-parameters--query-pending query))
               (retired (cons id (process-get process 'omnivox-parameters--retired))))
          (remhash id (omnivox--pending-requests process))
          ;; A late error belongs to this view, not generic notification output.
          (process-put process 'omnivox-parameters--retired
                       (cl-subseq retired 0 (min 32 (length retired))))))
      (process-put process 'omnivox-parameters--queries
                   (delq query (process-get process 'omnivox-parameters--queries))))
    (dolist (waiter (omnivox-parameters--query-waiters query))
      (setf (omnivox-parameters--waiter-operation waiter) nil)
      (omnivox-parameters--notify waiter result))
    (setf (omnivox-parameters--query-waiters query) nil)))

(defun omnivox-parameters--timeout (query)
  "Finish QUERY at its total deadline, including all catalogue pages."
  (omnivox-parameters--finish query
                             (if (omnivox-parameters--current-p query)
                                 '(:status timeout :message "Engine controls query timed out")
                               '(:status stale :message "Speech connection or inventory changed"))))

(defun omnivox-parameters--stopped (process)
  "Retire PROCESS queries on exit; ordinary navigation Stop leaves them alone."
  (when (and (processp process)
             (or (not (process-live-p process)) (process-get process 'tts--speech-process-retiring)))
    (dolist (query (copy-sequence (process-get process 'omnivox-parameters--queries)))
      (omnivox-parameters--finish query '(:status stale :message "Speech connection closed")))
    (process-put process 'omnivox-parameters--cache nil)))
(add-hook 'tts-stopped-hook #'omnivox-parameters--stopped)

(defun omnivox-parameters--pending-p (process id)
  "Return non-nil when PROCESS's request ID needs strict native JSON decoding."
  (and (integerp id)
       (cl-some (lambda (query) (eql id (omnivox-parameters--query-pending query)))
                (process-get process 'omnivox-parameters--queries))))

(defun omnivox-parameters--discard-retired-reply-p (process id)
  "Consume a late reply for a recently retired catalogue request ID on PROCESS."
  (let ((retired (process-get process 'omnivox-parameters--retired)))
    (when (and (integerp id) (memql id retired))
      (process-put process 'omnivox-parameters--retired (cl-delete id retired :test #'eql))
      t)))

(defun omnivox-parameters--cached (process engine voice)
  "Return last checked ENGINE/VOICE evidence for PROCESS, or nil.
This is display evidence, not a freshness guarantee: requests always recheck
the worker, whose helper may have restarted since the last inventory."
  (when (and (processp process) (process-live-p process)
             (not (process-get process 'tts--speech-process-retiring)))
    (let ((entry (cl-find-if
                  (lambda (item)
                    (and (equal (plist-get item :epoch) (omnivox-parameters--epoch process))
                         (equal (plist-get (plist-get item :catalogue) :engine-id) engine)
                         (equal (plist-get (plist-get item :catalogue) :voice-id) (or voice :null))))
                  (process-get process 'omnivox-parameters--cache))))
      (tts--dispatch-copy-data entry))))

(defun omnivox-parameters--complete (query parameters)
  "Validate cross-page references, cache PARAMETERS, and finish QUERY."
  (let ((ids (mapcar (lambda (descriptor) (plist-get descriptor :id)) parameters)))
    (omnivox-parameters--require (= (length ids) (length (delete-dups (copy-sequence ids)))) "duplicate parameter")
    (dolist (descriptor parameters)
      (mapc (lambda (id) (omnivox-parameters--require (member id ids) "unknown side effect"))
            (plist-get descriptor :side_effects)))
    (mapc (lambda (mapping)
            (mapc (lambda (id) (omnivox-parameters--require (member id ids) "unknown mapping output"))
                  (plist-get mapping :native_outputs))) (omnivox-parameters--query-mappings query)))
  (let* ((process (omnivox-parameters--query-process query))
         (catalogue (list :engine-id (omnivox-parameters--query-engine query)
                          :voice-id (omnivox-parameters--query-voice query)
                          :identity (omnivox-parameters--query-identity query)
                          :parameters (vconcat parameters) :mappings (omnivox-parameters--query-mappings query)))
         (entry (list :epoch (omnivox-parameters--query-epoch query) :checked-at (float-time) :catalogue catalogue))
         (cache (cl-remove-if
                 (lambda (item)
                   (or (not (equal (plist-get item :epoch) (plist-get entry :epoch)))
                       (and (equal (plist-get (plist-get item :catalogue) :engine-id) (plist-get catalogue :engine-id))
                            (equal (plist-get (plist-get item :catalogue) :voice-id) (plist-get catalogue :voice-id)))))
                 (process-get process 'omnivox-parameters--cache))))
    (process-put process 'omnivox-parameters--cache
                 (cl-subseq (cons entry cache) 0 (min 8 (1+ (length cache)))))
    (omnivox-parameters--finish query (append (list :status 'ready) entry))))

(defun omnivox-parameters--receive (query response)
  "Validate a deferred RESPONSE, advancing only the current QUERY."
  (unless (omnivox-parameters--query-finished query)
    (if (not (omnivox-parameters--current-p query))
        (omnivox-parameters--finish query '(:status stale :message "Speech connection or inventory changed"))
      (condition-case err
          (let* ((result (omnivox-parameters--page response (omnivox-parameters--query-engine query)
                                                  (omnivox-parameters--query-voice query)))
                 (identity (plist-get result :identity)))
            (omnivox-parameters--require
             (eql (plist-get response :request_id) (omnivox-parameters--query-pending query)) "request identity")
            (setf (omnivox-parameters--query-pending query) nil)
            (pcase (plist-get result :status)
              ("busy" (omnivox-parameters--finish query (list :status 'busy :retry-after-ms (plist-get result :retry_after_ms))))
              ("unavailable" (omnivox-parameters--finish query (list :status 'unavailable :reason (plist-get result :reason)
                                                                   :message (plist-get result :message))))
              ("ready"
               (when (omnivox-parameters--query-identity query)
                 (omnivox-parameters--require
                  (and (equal identity (omnivox-parameters--query-identity query))
                       (equal (plist-get result :mappings) (omnivox-parameters--query-mappings query))) "changed page identity"))
               (let ((parameters (append (omnivox-parameters--query-parameters query) (append (plist-get result :parameters) nil)))
                     (cursor (plist-get result :next_cursor)))
                 (omnivox-parameters--require (<= (length parameters) 512) "catalogue size")
                 (let ((ids (mapcar (lambda (descriptor) (plist-get descriptor :id)) parameters)))
                   (omnivox-parameters--require
                    (= (length ids) (length (delete-dups ids))) "duplicate parameter"))
                 (omnivox-parameters--require
                  (<= (string-bytes (json-serialize (list :parameters (vconcat parameters) :mappings (plist-get result :mappings))))
                      (* 2 1024 1024)) "catalogue bytes")
                 (omnivox-parameters--require (not (member cursor (omnivox-parameters--query-cursors query))) "repeated cursor")
                 (setf (omnivox-parameters--query-identity query) identity
                       (omnivox-parameters--query-mappings query) (plist-get result :mappings)
                       (omnivox-parameters--query-parameters query) parameters)
                 (if (eq cursor :null) (omnivox-parameters--complete query parameters)
                   (push cursor (omnivox-parameters--query-cursors query))
                   (omnivox-parameters--send query cursor))))))
        (error
         (setq omnivox-parameters--last-error err)
         (omnivox-parameters--finish query '(:status failed :message "Invalid or rejected engine controls reply")))))))

(defun omnivox-parameters--send (query &optional cursor)
  "Submit QUERY's next page using CURSOR without interrupting speech."
  (setf (omnivox-parameters--query-pending query)
        (omnivox--send-control-request
         (omnivox-parameters--query-process query)
         (list :type "get_engine_parameters_v1" :engine_id (omnivox-parameters--query-engine query)
               :voice_id (omnivox-parameters--query-voice query) :cursor (or cursor :null)
               :expected_catalogue_revision (or (plist-get (omnivox-parameters--query-identity query) :catalogue_revision) :null))
         (lambda (_process response)
           (unless (omnivox-parameters--query-finished query)
             (setf (omnivox-parameters--query-step query)
                   (run-at-time 0 nil #'omnivox-parameters--receive query
                                (tts--dispatch-copy-data response))))))))

(defun omnivox-parameters--request (process engine voice callback &optional current)
  "Query ENGINE and optional physical VOICE on PROCESS without waiting.
Return a cancellable waiter.  CALLBACK receives a copied status/catalogue later,
only while CURRENT (a buffer/draft predicate) still holds.  Coalesce matching
requests; different voices on a busy engine report busy without queueing."
  (omnivox-parameters--id engine)
  (when voice (omnivox-parameters--text voice 4096))
  (unless (and (functionp callback) (or (null current) (functionp current))) (error "Invalid catalogue observer"))
  (let ((waiter (omnivox-parameters--make-waiter
                 :callback callback :current current :process process
                 :epoch (and (processp process) (omnivox-parameters--epoch process)))))
    (cond
     ((not (and (processp process) (process-live-p process)
                (not (process-get process 'tts--speech-process-retiring))))
      (omnivox-parameters--notify waiter '(:status stale :message "Speech connection unavailable")))
     ((not (omnivox--process-supports-p process "engine_parameter_catalogue_v1"))
      (omnivox-parameters--notify waiter '(:status unsupported :message "This speech worker cannot describe engine controls")))
     (t
      (let ((query (cl-find engine (process-get process 'omnivox-parameters--queries)
                            :test #'equal :key #'omnivox-parameters--query-engine)))
        (when (and query (not (omnivox-parameters--current-p query)))
          (omnivox-parameters--finish query '(:status stale :message "Speech inventory changed"))
          (setq query nil))
        (cond
         ((and query (equal (or voice :null) (omnivox-parameters--query-voice query))
               (< (length (omnivox-parameters--query-waiters query)) 32))
          (push waiter (omnivox-parameters--query-waiters query))
          (setf (omnivox-parameters--waiter-operation waiter) query))
         ((or query (>= (length (process-get process 'omnivox-parameters--queries)) 8))
          (omnivox-parameters--notify waiter '(:status busy :retry-after-ms 50)))
         (t
          (setq query (omnivox-parameters--make-query
                       :process process :epoch (omnivox-parameters--epoch process)
                       :engine (copy-sequence engine) :voice (if voice (copy-sequence voice) :null) :waiters (list waiter)))
          (setf (omnivox-parameters--waiter-operation waiter) query)
          (process-put process 'omnivox-parameters--queries (cons query (process-get process 'omnivox-parameters--queries)))
          (condition-case err
              (progn
                (setf (omnivox-parameters--query-timer query)
                      (run-at-time (if (and (numberp omnivox-voice-configuration-timeout)
                                           (> omnivox-voice-configuration-timeout 0))
                                      (min 5 omnivox-voice-configuration-timeout) 5)
                                   nil #'omnivox-parameters--timeout query))
                (omnivox-parameters--send query))
            (error
             (setq omnivox-parameters--last-error err)
             (omnivox-parameters--finish query '(:status failed :message "Could not request engine controls")))))))))
    waiter))

(provide 'omnivox-parameters)
;;; omnivox-parameters.el ends here
