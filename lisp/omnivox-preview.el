;;; omnivox-preview.el --- Owned Omnivox preview sequences -*- lexical-binding: t; -*-

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
;; Complete and individual samples share process ownership, guarded startup,
;; bounded preparation and unwind-safe control reservations. Draft projection
;; and wire-version-specific normalization remain in omnivox-voices.el.
;;; Code:
(require 'cl-lib)
(require 'tts-queue-state)
(require 'omnivox-choice-codec)

(defvar tts-speaker-process)
(defvar tts-stopped-hook)
(defvar omnivox-voice-preview-timeout)
(defvar omnivox--control-capabilities-property)
(defvar omnivox--control-request-sequence)
(defvar omnivox-control-max-payload-bytes)
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox--preview-complete-request "omnivox-voices" (entry process))
(declare-function omnivox--preview-individual-request "omnivox-voices" (entry process))
(declare-function omnivox--normalize-complete-preview-response "omnivox-voices" (entry response))
(declare-function omnivox--normalize-preview-response "omnivox-voices" (entry response effects-supported rate-supported))
(declare-function omnivox--encode-control-request "omnivox-voices" (request))
(declare-function omnivox--pending-requests "omnivox-voices" (process))
(declare-function omnivox--next-control-request-id "omnivox-voices" ())
(declare-function tts--interrupt-process "tts-speak" (process &optional notifications preserved preview))
(declare-function tts--voice-preview-callback "tts-speak" (callback result))
(declare-function emacsvox-aural--call-independent-callback "emacsvox-aural-transport" (function &rest arguments))
(declare-function emacsvox-aural-cancel-pending-deliveries "emacsvox-aural-transport" (&optional process))

(cl-defstruct (omnivox--preview (:constructor omnivox--preview-create))
  process generation capabilities guard items callback observer timer pending
  response results base-rate disabled busy finished notification interrupt individual)

(defun omnivox--preview-copy (value)
  "Copy bounded preview VALUE including mutable strings, rejecting cycles."
  (let ((nodes 0) (bytes 0) (path (make-hash-table :test #'eq)))
    (cl-labels ((walk (item depth)
                 (when (or (> (cl-incf nodes) 262144) (> depth 256))
                   (error "Preview input is too large or deeply nested"))
                 (cond
                  ((stringp item)
                   (cl-incf bytes (string-bytes item))
                   (when (> bytes (* 16 1024 1024)) (error "Preview input exceeds 16 MiB"))
                   (substring-no-properties item))
                  ((or (consp item) (vectorp item))
                   (when (gethash item path) (error "Preview input contains a cycle"))
                   (puthash item t path)
                   (prog1 (if (consp item)
                              (cons (walk (car item) (1+ depth)) (walk (cdr item) (1+ depth)))
                            (apply #'vector (mapcar (lambda (child) (walk child (1+ depth))) item)))
                     (remhash item path)))
                  ((or (null item) (symbolp item) (numberp item)) item)
                  (t (error "Unsupported preview input")))))
      (walk value 0))))

(defun omnivox--preview-command (request identifier)
  "Encode the complete REQUEST line using reserved IDENTIFIER."
  (format "omnivox_control {%s}\n"
          (omnivox--encode-control-request
           (append (list :protocol_version 1 :request_id identifier) request))))

(defun omnivox--preview-current-p (operation)
  "Whether OPERATION still owns the frozen foreground connection and settings."
  (let ((process (omnivox--preview-process operation)))
    (and (not (omnivox--preview-finished operation))
         (eq operation (process-get process 'omnivox--preview-operation))
         (eq process tts-speaker-process) (process-live-p process)
         (not (process-get process 'tts--speech-process-retiring))
         (equal (omnivox--preview-generation operation)
                (process-get process 'tts--speech-process-generation))
         (equal (omnivox--preview-capabilities operation)
                (process-get process omnivox--control-capabilities-property)))))

(defun omnivox--preview-clear-entry (operation)
  "Detach OPERATION's pending request and timer without invoking user code."
  (let ((inhibit-quit t)
        (timer (omnivox--preview-timer operation))
        (identifier (omnivox--preview-pending operation)))
    (setf (omnivox--preview-timer operation) nil
          (omnivox--preview-pending operation) nil
          (omnivox--preview-response operation) nil)
    (when identifier
      (remhash identifier (omnivox--pending-requests (omnivox--preview-process operation))))
    (when timer (cancel-timer timer))))

(defun omnivox--preview-notify (operation)
  "Complete OPERATION's interrupt before delivering its detached callback."
  (when (and (not (omnivox--preview-busy operation))
             (omnivox--preview-finished operation))
    (let* ((process (omnivox--preview-process operation))
           (owned (eq operation (process-get process 'omnivox--preview-operation)))
           (notification (omnivox--preview-notification operation)))
      (setf (omnivox--preview-notification operation) nil)
      (when owned (process-put process 'omnivox--preview-operation nil))
      (unwind-protect
          (when (and owned (omnivox--preview-interrupt operation)
                     (eq process tts-speaker-process)
                     (tts-queue--guard-valid-p (omnivox--preview-guard operation)))
            (tts--interrupt-process process))
        (when notification
          (emacsvox-aural--call-independent-callback
           #'tts--voice-preview-callback (car notification) (cadr notification)))))))

(defun omnivox--preview-finish (operation status &optional message interrupt abandon)
  "Retire OPERATION exactly once with STATUS and MESSAGE.
INTERRUPT stops owned playback before notification. ABANDON propagates a
nonlocal caller exit without retaining an asynchronous callback."
  (unless (omnivox--preview-finished operation)
    (let ((inhibit-quit t))
      (setf (omnivox--preview-finished operation) t
            (omnivox--preview-interrupt operation) interrupt
            (omnivox--preview-notification operation)
            (unless abandon
              (list (omnivox--preview-callback operation)
                    (list :status status :completion-guarantee 'playback
                          :message message :results (nreverse (omnivox--preview-results operation)))))
            (omnivox--preview-callback operation) nil
            (omnivox--preview-results operation) nil
            (omnivox--preview-items operation) nil)
      (omnivox--preview-clear-entry operation)
      (remove-hook 'tts-stopped-hook (omnivox--preview-observer operation))
      (let ((process (omnivox--preview-process operation)))
        (when (eq (car (process-get process 'tts--interrupt-listener)) operation)
          (process-put process 'tts--interrupt-listener nil)))
      (setf (omnivox--preview-observer operation) nil)))
  (omnivox--preview-notify operation))

(defun omnivox--preview-interrupted (operation)
  "Retire OPERATION before Stop I/O, returning its post-interrupt notification.
No user code runs until the interrupt has left its write and observer stacks."
  (let ((busy (omnivox--preview-busy operation)) (inhibit-quit t))
    (setf (omnivox--preview-busy operation) t)
    (omnivox--preview-finish operation 'cancelled)
    (lambda (completed)
      (unless completed (setf (omnivox--preview-notification operation) nil))
      (setf (omnivox--preview-busy operation) busy)
      (omnivox--preview-notify operation))))

(defun omnivox--preview-receive (operation item identifier process response)
  "Latch RESPONSE for OPERATION's exact ITEM and IDENTIFIER on PROCESS."
  (when (and (eq process (omnivox--preview-process operation))
             (eql identifier (omnivox--preview-pending operation))
             (eq item (car (omnivox--preview-items operation)))
             (not (omnivox--preview-response operation))
             (not (omnivox--preview-finished operation)))
    (let ((result
           (condition-case err
               (if (omnivox--preview-individual operation)
                   (omnivox--normalize-preview-response (car item) response (nth 2 item) (nth 3 item))
                 (omnivox--normalize-complete-preview-response (car item) response))
             (error (list :status 'failed :message (error-message-string err))))))
      (unless (memq (plist-get result :status) '(completed cancelled failed))
        (setq result '(:status failed :message "Invalid preview status")))
      (setf (omnivox--preview-response operation) result))
    (unless (omnivox--preview-busy operation) (omnivox--preview-drive operation))))

(defun omnivox--preview-send (operation item)
  "Reserve and write OPERATION's ITEM once, latching any reentrant response."
  (let* ((process (omnivox--preview-process operation))
         (identifier (omnivox--next-control-request-id))
         (pending (omnivox--pending-requests process))
         (request (copy-tree (cadr item)))
         complete)
    (when (and (not (omnivox--preview-individual operation)) (omnivox--preview-base-rate operation))
      (setq request (plist-put request :expected_base_rate (omnivox--preview-base-rate operation))))
    (unwind-protect
        (progn
          (setf (omnivox--preview-pending operation) identifier)
          (puthash identifier (lambda (owner response)
                                (omnivox--preview-receive operation item identifier owner response)) pending)
          (let ((timer (run-at-time
                        omnivox-voice-preview-timeout nil
                        (lambda ()
                          (when (eql identifier (omnivox--preview-pending operation))
                            (omnivox--preview-finish operation 'failed
                                                     "Voice preview timed out; playback unconfirmed" t))))))
            (if (omnivox--preview-current-p operation)
                (setf (omnivox--preview-timer operation) timer)
              (when timer (cancel-timer timer))))
          (when (omnivox--preview-current-p operation)
            (let ((command (omnivox--preview-command request identifier)))
              (tts-queue--send process command (tts-queue--describe command 'neutral)
                               nil (omnivox--preview-guard operation)))
            (setq complete t)))
      (unless (and complete (omnivox--preview-current-p operation))
        (remhash identifier pending)))))

(defun omnivox--preview-consume (operation)
  "Consume one validated terminal without confusing comparison metadata."
  (let ((result (omnivox--preview-response operation)))
    (omnivox--preview-clear-entry operation)
    (when (and (not (omnivox--preview-individual operation))
               (eq (plist-get result :status) 'completed))
      (let ((rate (plist-get result :base-rate))
            (disabled (sort (copy-sequence (plist-get result :effective-disabled-engine-ids)) #'string-lessp)))
        (if (omnivox--preview-base-rate operation)
            (unless (and (= rate (omnivox--preview-base-rate operation))
                         (equal disabled (omnivox--preview-disabled operation)))
              (setq result (plist-put result :status 'failed))
              (setq result (plist-put result :message "Comparison policy changed; restart comparison")))
          (setf (omnivox--preview-base-rate operation) rate
                (omnivox--preview-disabled operation) disabled))))
    (push result (omnivox--preview-results operation))
    (pop (omnivox--preview-items operation))
    (unless (eq (plist-get result :status) 'completed)
      (omnivox--preview-finish operation (plist-get result :status) (plist-get result :message)))))

(defun omnivox--preview-drive (operation)
  "Advance OPERATION outside actual writes, with one outstanding entry."
  (let (returned failure waiting)
    (setf (omnivox--preview-busy operation) t)
    (unwind-protect
        (progn
          (condition-case err
              (while (and (not waiting) (not (omnivox--preview-finished operation)))
                (cond
                 ((not (omnivox--preview-current-p operation))
                  (omnivox--preview-finish operation 'cancelled "Preview connection or settings changed"))
                 ((not (tts-queue--guard-valid-p (omnivox--preview-guard operation)))
                  (error "Speech input changed during preview; playback unconfirmed"))
                 ((omnivox--preview-response operation) (omnivox--preview-consume operation))
                 ((omnivox--preview-pending operation) (setq waiting t))
                 ((omnivox--preview-items operation)
                  (omnivox--preview-send operation (car (omnivox--preview-items operation))))
                 (t (omnivox--preview-finish operation 'completed))))
            (error (setq failure err)
                   (omnivox--preview-finish operation 'failed (error-message-string err))))
          (setq returned t))
      (unless returned (omnivox--preview-finish operation 'cancelled nil nil t))
      (setf (omnivox--preview-busy operation) nil)
      (omnivox--preview-notify operation))
    (when (and failure (omnivox--preview-individual operation))
      (signal (car failure) (cdr failure)))))

(defun omnivox--preview-sequence (entries callback individual)
  "Preflight ENTRIES, then own their preview until CALLBACK or cancellation.
INDIVIDUAL retains the legacy exact-audition wire and response shape."
  (let* ((process tts-speaker-process)
         (previous (and (processp process) (process-get process 'omnivox--preview-operation)))
         (generation (and (processp process) (process-get process 'tts--speech-process-generation)))
         (epoch (and (processp process) (process-get process 'tts--dispatch-cancellation-epoch)))
         (guard (and (processp process) (tts-queue--startup-guard process)))
         (capabilities (and (processp process)
                            (omnivox--preview-copy (process-get process omnivox--control-capabilities-property))))
         (entries (omnivox--preview-copy entries))
         (bytes 0) items operation returned failure)
    (unless (and (proper-list-p entries) (<= 1 (length entries) 64))
      (user-error "Preview requires between one and 64 entries"))
    (when (> (+ omnivox--control-request-sequence (length entries)) omnivox--choice-u64-max)
      (user-error "Omnivox control request IDs exhausted"))
    (unless (and (numberp omnivox-voice-preview-timeout) (> omnivox-voice-preview-timeout 0)
                 (< omnivox-voice-preview-timeout 1.0e+INF))
      (user-error "Preview timeout must be a positive finite number"))
    (dolist (entry entries)
      (unless (eq (and (plist-member entry :selector) t) (and individual t))
        (user-error "A comparison must use the same preview form for every entry"))
      (let* ((request (if individual (omnivox--preview-individual-request entry process)
                        (omnivox--preview-complete-request entry process)))
             (bounded (copy-tree request)))
        (unless individual (setq bounded (plist-put bounded :expected_base_rate 1.2345678901234567)))
        (let ((command (omnivox--preview-command bounded omnivox--choice-u64-max)))
          ;; Reserve extra numeric spelling space for any finite host rate.
          (when (> (+ 64 (string-bytes (base64-decode-string
                                       (substring command (length "omnivox_control {") -2))))
                   omnivox-control-max-payload-bytes)
            (user-error "Preview envelope leaves no room for comparison metadata"))
          (cl-incf bytes (+ 128 (string-bytes command))))
        (when (> bytes (* 16 1024 1024)) (user-error "Preview sequence exceeds 16 MiB"))
        (push (list entry request
                    (omnivox--process-supports-p process "post_synthesis_effects_v1")
                    (omnivox--process-supports-p process "relative_rate_v1")) items)))
    (unless (and (eq process tts-speaker-process) (process-live-p process)
                 (equal generation (process-get process 'tts--speech-process-generation))
                 (equal epoch (process-get process 'tts--dispatch-cancellation-epoch))
                 (equal capabilities (process-get process omnivox--control-capabilities-property))
                 (eq previous (process-get process 'omnivox--preview-operation)))
      (user-error "Preview connection changed during preflight"))
    (unless (and guard (tts-queue--guard-valid-p guard))
      (user-error "Preview needs an unchanged, proven speech input boundary"))
    (setq operation (omnivox--preview-create
                     :process process :generation generation :capabilities capabilities :guard guard
                     :items (nreverse items) :callback callback :individual individual :busy t))
    (setf (omnivox--preview-observer operation)
          (lambda (owner)
            (when (eq owner process)
              (omnivox--preview-finish operation (if (process-live-p process) 'cancelled 'failed)))))
    (unwind-protect
        (progn
          (process-put process 'omnivox--preview-operation operation)
          (process-put process 'tts--interrupt-listener
                       (list operation (lambda () (omnivox--preview-interrupted operation))))
          (add-hook 'tts-stopped-hook (omnivox--preview-observer operation))
          (when previous (omnivox--preview-finish previous 'cancelled))
          (condition-case err
              (when (omnivox--preview-current-p operation)
                (emacsvox-aural-cancel-pending-deliveries process)
                (when (omnivox--preview-current-p operation)
                  (tts--interrupt-process process nil nil
                                          (list (omnivox--preview-guard operation)
                                                (omnivox--preview-observer operation) operation))))
            (error (setq failure err)
                   (omnivox--preview-finish operation 'failed (error-message-string err))))
          (setq returned t))
      (unless returned (omnivox--preview-finish operation 'cancelled nil nil t))
      (setf (omnivox--preview-busy operation) nil)
      (omnivox--preview-notify operation))
    (unless (omnivox--preview-finished operation) (omnivox--preview-drive operation))
    (when (and failure individual) (signal (car failure) (cdr failure)))))

(provide 'omnivox-preview)
;;; omnivox-preview.el ends here
