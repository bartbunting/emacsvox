;;; emacsvox-aural-recording.el --- Bounded delivery reproduction -*- lexical-binding: t; -*-

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
;; Explicitly capture one outer delivery, using only resolved assembly values.
;; Export is separate.  Offline reconstruction never sends the resulting wire.
;; The JSON format uses tagged arrays for Lisp values, without Lisp reading,
;; arbitrary symbol interning, function lookup or executable input.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emacsvox-aural-transport)

(defconst emacsvox-aural-recording--limit 65536)
(defconst emacsvox-aural-recording--operation-limit 4096)
(defconst emacsvox-aural-recording--depth-limit 128)
(defconst emacsvox-aural-recording--construction-version 1
  "Increment when assembly or framing semantics cease to reproduce old inputs.")
(defvar emacsvox-aural-recording--state nil)
(defvar emacsvox-aural-recording--timer nil)
(defvar emacsvox-aural-recording--budget 0)
(defvar emacsvox-aural-recording--nodes 0)

(cl-defstruct (emacsvox-aural-recording--capture
               (:constructor emacsvox-aural-recording--make))
  lane phase result assembly layered operations facts (bytes 4096) (count 0)
  reason document-hash semantics-hash wire-hash outcome)

(defun emacsvox-aural-recording--json (value)
  "Encode VALUE as UTF-8 JSON bytes."
  (encode-coding-string (json-serialize value) 'utf-8 t))

(defun emacsvox-aural-recording--charge (amount depth)
  "Charge AMOUNT before copying, rejecting excessive DEPTH or node count."
  (when (or (> depth emacsvox-aural-recording--depth-limit)
            (< (cl-decf emacsvox-aural-recording--budget amount) 0)
            (> (cl-incf emacsvox-aural-recording--nodes) 16384))
    (error "Recording data limit exceeded")))

(defun emacsvox-aural-recording--encode (value &optional depth)
  "Snapshot plain VALUE as tagged JSON arrays, with bounded DEPTH.
Unknown objects and cycles are rejected by the type and traversal bounds."
  (let ((depth (or depth 0)))
    (emacsvox-aural-recording--charge 4 depth)
    (cond
     ((stringp value)
      (emacsvox-aural-recording--charge (string-bytes value) depth)
      (vector "string" (substring-no-properties value)))
     ((symbolp value)
      (when (> (length (symbol-name value)) 256) (error "Oversized symbol"))
      (emacsvox-aural-recording--charge (length (symbol-name value)) depth)
      (vector "symbol" (symbol-name value)))
     ((numberp value)
      ;; JSON rejects NaN and infinity; keep integers and floats distinct.
      (vector (if (integerp value) "integer" "float") value))
     ((functionp value) (error "Recording cannot retain a callback"))
     ((consp value)
      (vector "cons" (emacsvox-aural-recording--encode (car value) (1+ depth))
              (emacsvox-aural-recording--encode (cdr value) (1+ depth))))
     ((vectorp value)
      (emacsvox-aural-recording--charge (length value) depth)
      (vector "vector" (vconcat (mapcar (lambda (item)
                                         (emacsvox-aural-recording--encode item (1+ depth))) value))))
     ((hash-table-p value)
      (unless (memq (hash-table-test value) '(eq eql equal)) (error "Unsupported hash table"))
      (emacsvox-aural-recording--charge (hash-table-count value) depth)
      (let (pairs)
        (maphash (lambda (key item)
                   (push (vector (emacsvox-aural-recording--encode key (1+ depth))
                                 (emacsvox-aural-recording--encode item (1+ depth))) pairs)) value)
        (vector "hash" (symbol-name (hash-table-test value)) (vconcat (nreverse pairs)))))
     (t (error "Recording accepts only plain data")))))

(defun emacsvox-aural-recording--snapshot (value)
  "Copy VALUE with no more than the recording's total allowance."
  (let ((emacsvox-aural-recording--budget emacsvox-aural-recording--limit)
        (emacsvox-aural-recording--nodes 0))
    (emacsvox-aural-recording--encode value)))

(defun emacsvox-aural-recording--decode (value &optional depth)
  "Validate and decode tagged VALUE at DEPTH without evaluating input."
  (let ((depth (or depth 0)))
    (emacsvox-aural-recording--charge 1 depth)
    (unless (and (vectorp value) (> (length value) 0) (stringp (aref value 0)))
      (error "Invalid recorded value"))
    (pcase value
      (`["string" ,text] (unless (stringp text) (error "Invalid string")) text)
      (`["symbol" ,name]
       (unless (and (stringp name) (<= (length name) 256)) (error "Invalid symbol"))
       ;; Unknown data symbols remain uninterned and can never name a call.
       (if (equal name "nil") nil (or (intern-soft name) (make-symbol name))))
      (`["integer" ,number] (unless (integerp number) (error "Invalid integer")) number)
      (`["float" ,number] (unless (floatp number) (error "Invalid float")) number)
      (`["cons" ,head ,tail]
       (cons (emacsvox-aural-recording--decode head (1+ depth))
             (emacsvox-aural-recording--decode tail (1+ depth))))
      (`["vector" ,items]
       (unless (vectorp items) (error "Invalid vector"))
       (vconcat (mapcar (lambda (item) (emacsvox-aural-recording--decode item (1+ depth))) items)))
      (`["hash" ,test ,pairs]
       (unless (and (member test '("eq" "eql" "equal")) (vectorp pairs)) (error "Invalid hash"))
       (let ((table (make-hash-table :test (pcase test ("eq" 'eq) ("eql" 'eql) (_ 'equal))))
             (missing (make-symbol "missing")))
         (mapc (lambda (pair)
                 (unless (and (vectorp pair) (= (length pair) 2)) (error "Invalid pair"))
                 (let* ((key (emacsvox-aural-recording--decode (aref pair 0) (1+ depth)))
                        (item (emacsvox-aural-recording--decode (aref pair 1) (1+ depth))))
                   (unless (eq (gethash key table missing) missing) (error "Duplicate hash key"))
                   (puthash key item table))) pairs)
         table))
      (_ (error "Unknown recorded value type")))))

(defun emacsvox-aural-recording--cancel-timer ()
  "Retire the arming timer."
  (when (timerp emacsvox-aural-recording--timer) (cancel-timer emacsvox-aural-recording--timer))
  (setq emacsvox-aural-recording--timer nil))

(defun emacsvox-aural-recording--clear ()
  "Release all recording state without affecting speech."
  (emacsvox-aural-recording--cancel-timer)
  (setq emacsvox-aural-recording--state nil emacsvox-aural--recording-observer nil
        emacsvox-aural--recording-error nil))

(defun emacsvox-aural-recording--incomplete (reason)
  "Discard detailed inputs and keep only a bounded REASON."
  (let ((state emacsvox-aural-recording--state))
    (setf (emacsvox-aural-recording--capture-reason state) reason
          (emacsvox-aural-recording--capture-operations state) nil
          (emacsvox-aural-recording--capture-facts state) nil
          (emacsvox-aural-recording--capture-assembly state) nil
          (emacsvox-aural-recording--capture-document-hash state) nil
          (emacsvox-aural-recording--capture-semantics-hash state) nil
          (emacsvox-aural-recording--capture-wire-hash state) nil
          (emacsvox-aural-recording--capture-bytes state) 4096)))

(defun emacsvox-aural-recording--append (name arguments &optional fact)
  "Retain bounded NAME and ARGUMENTS; FACT selects observations over operations."
  (let* ((state emacsvox-aural-recording--state)
         (emacsvox-aural-recording--budget
          (- emacsvox-aural-recording--limit (emacsvox-aural-recording--capture-bytes state)))
         (emacsvox-aural-recording--nodes 0))
    (condition-case nil
        (let* ((entry (vector name (emacsvox-aural-recording--encode arguments)))
               (bytes (1+ (length (emacsvox-aural-recording--json entry)))))
          (when (or (> (cl-incf (emacsvox-aural-recording--capture-count state))
                       emacsvox-aural-recording--operation-limit)
                    (> (cl-incf (emacsvox-aural-recording--capture-bytes state) bytes)
                       emacsvox-aural-recording--limit))
            (error "Recording limit"))
          (if fact (push entry (emacsvox-aural-recording--capture-facts state))
            (push entry (emacsvox-aural-recording--capture-operations state))))
      (error (emacsvox-aural-recording--incomplete "input-limit-or-unsupported-data")))))

(defun emacsvox-aural-recording--event (event &rest values)
  "Observe a private transport EVENT with resolved VALUES."
  (let ((state emacsvox-aural-recording--state))
    (when state
      (when (and (eq event 'begin)
                 (eq (emacsvox-aural-recording--capture-phase state) 'armed)
                 (eq (car values) (emacsvox-aural-recording--capture-lane state))
                 (not (memq this-command '(emacsvox-aural-record-next-delivery
                                           emacsvox-aural-recording-status
                                           emacsvox-aural-export-recording
                                           emacsvox-aural-cancel-recording))))
        (emacsvox-aural-recording--cancel-timer)
        (setf (emacsvox-aural-recording--capture-phase state) 'capturing
              (emacsvox-aural-recording--capture-result state) emacsvox-aural--delivery-result))
      (when (and emacsvox-aural--delivery-result
                 (eq emacsvox-aural--delivery-result (emacsvox-aural-recording--capture-result state)))
        (if (eq event 'outcome)
            (progn
              (when (and (emacsvox-aural-recording--capture-operations state)
                         (not (emacsvox-aural-recording--capture-wire-hash state)))
                (emacsvox-aural-recording--incomplete "construction-did-not-finish"))
              (condition-case nil
                  (let ((outcome (emacsvox-aural-recording--snapshot emacsvox-aural--delivery-result)))
                    (when (> (length (emacsvox-aural-recording--json outcome)) 2048)
                      (error "Outcome limit"))
                    (setf (emacsvox-aural-recording--capture-outcome state) outcome))
                (error
                 (setf (emacsvox-aural-recording--capture-outcome state) nil)
                 (emacsvox-aural-recording--incomplete "outcome-limit")))
              (setf (emacsvox-aural-recording--capture-phase state) 'ready
                    (emacsvox-aural-recording--capture-assembly state) nil)
              ;; A scheduled result may still change before explicit export.
              (unless (eq (plist-get emacsvox-aural--delivery-result :disposition) 'scheduled)
                (setq emacsvox-aural--recording-observer nil)))
          (unless (emacsvox-aural-recording--capture-reason state)
            (pcase event
              ('assembly
               (when (emacsvox-aural-recording--capture-assembly state)
                 (error "More than one assembly in a delivery"))
               (setf (emacsvox-aural-recording--capture-assembly state) (car values)
                     (emacsvox-aural-recording--capture-layered state) (cadr values)))
              ('operation
               (when (eq (car values) (emacsvox-aural-recording--capture-assembly state))
                 (emacsvox-aural-recording--append (cadr values) (nth 2 values))))
              ('frame (emacsvox-aural-recording--append "frame" values))
              ('constructed
               (setf (emacsvox-aural-recording--capture-document-hash state)
                     (secure-hash 'sha256 (emacsvox-aural-recording--json (car values)))
                     (emacsvox-aural-recording--capture-semantics-hash state)
                     (secure-hash 'sha256 (emacsvox-aural-recording--json
                                          (emacsvox-aural-recording--snapshot (cdr values))))))
              ('wire
               (unless (emacsvox-aural-recording--capture-document-hash state)
                 ;; A timeline without spans can legitimately lower to commands.
                 (setf (emacsvox-aural-recording--capture-operations state) nil)
                 (emacsvox-aural-recording--append "commands" (car values)))
               (unless (emacsvox-aural-recording--capture-reason state)
                 (setf (emacsvox-aural-recording--capture-wire-hash state)
                       (secure-hash 'sha256 (encode-coding-string (apply #'concat (car values)) 'utf-8 t)))))
              ((or 'capability 'omitted-action)
               (emacsvox-aural-recording--append (symbol-name event) values t)))))))))

(defun emacsvox-aural-recording--bundle ()
  "Return the current complete, bounded export object."
  (let ((state emacsvox-aural-recording--state))
    (unless state (user-error "No delivery recording"))
    (when emacsvox-aural--recording-error
      (emacsvox-aural-recording--cancel-timer)
      (emacsvox-aural-recording--incomplete "recorder-error")
      (setf (emacsvox-aural-recording--capture-phase state) 'ready))
    (unless (eq (emacsvox-aural-recording--capture-phase state) 'ready)
      (user-error "Recording is %s" (emacsvox-aural-recording--capture-phase state)))
    (let* ((reason (emacsvox-aural-recording--capture-reason state))
           (object (make-hash-table :test #'equal)))
      (cl-loop for (key value) on
               (list "format" 1 "construction" emacsvox-aural-recording--construction-version
                     "source" emacsvox-git-revision "emacs" emacs-version
                     "lane" (symbol-name (emacsvox-aural-recording--capture-lane state))
                     "complete" (if reason :false t) "reason" (or reason :null)
                     "layered" (if (emacsvox-aural-recording--capture-layered state) t :false)
                     "outcome" (or (emacsvox-aural-recording--capture-outcome state) ["symbol" "nil"])
                     "facts" (vconcat (reverse (emacsvox-aural-recording--capture-facts state)))
                     "operations" (vconcat (reverse (emacsvox-aural-recording--capture-operations state)))
                     "document_hash" (or (emacsvox-aural-recording--capture-document-hash state) :null)
                     "semantics_hash" (or (emacsvox-aural-recording--capture-semantics-hash state) :null)
                     "wire_hash" (or (emacsvox-aural-recording--capture-wire-hash state) :null))
               by #'cddr do (puthash key value object))
      (when (> (length (emacsvox-aural-recording--json object)) emacsvox-aural-recording--limit)
        (emacsvox-aural-recording--incomplete "export-limit")
        (setf (emacsvox-aural-recording--capture-outcome state) nil)
        (setq object (emacsvox-aural-recording--bundle)))
      object)))

(defun emacsvox-aural-recording--disposition (bundle)
  "Return BUNDLE's client outcome for a concise status announcement."
  (let ((emacsvox-aural-recording--budget emacsvox-aural-recording--limit)
        (emacsvox-aural-recording--nodes 0))
    (or (plist-get (emacsvox-aural-recording--decode (gethash "outcome" bundle)) :disposition) 'unknown)))

;;;###autoload
(defun emacsvox-aural-record-next-delivery (lane)
  "Record the next outer delivery on LANE, main or notification.
Arming expires after 60 seconds.  One delivery disarms recording.  Captured
speech text and resource paths stay in memory until explicit export or cancel;
input above 64 KiB is discarded with an incomplete summary.  This records
client construction, not audio or server success.  Existing logs are unchanged."
  (interactive (list (intern (completing-read "Record next delivery on lane: " '("main" "notification") nil t nil nil "main"))))
  (unless (memq lane '(main notification)) (user-error "Choose main or notification"))
  (when emacsvox-aural-recording--state (user-error "Export or cancel the existing recording first"))
  (message "Recording the next %s delivery; expires in 60 seconds" lane)
  (setq emacsvox-aural-recording--state (emacsvox-aural-recording--make :lane lane :phase 'armed)
        emacsvox-aural--recording-error nil
        emacsvox-aural--recording-observer #'emacsvox-aural-recording--event)
  (let ((state emacsvox-aural-recording--state))
    (setq emacsvox-aural-recording--timer
          (run-at-time 60 nil
                       (lambda ()
                         (when (and (eq state emacsvox-aural-recording--state)
                                    (eq (emacsvox-aural-recording--capture-phase state) 'armed))
                           (emacsvox-aural-recording--clear)
                           (message "Delivery recording expired")))))))

;;;###autoload
(defun emacsvox-aural-cancel-recording ()
  "Disarm delivery recording and discard its retained inputs.
This does not stop speech or remove an already exported file."
  (interactive)
  (emacsvox-aural-recording--clear)
  (message "Delivery recording cleared"))

;;;###autoload
(defun emacsvox-aural-recording-status ()
  "Report the recording's lane, capture state and encoded size."
  (interactive)
  (if (not emacsvox-aural-recording--state) (message "No delivery recording")
    (let* ((state emacsvox-aural-recording--state)
           (ready (or emacsvox-aural--recording-error
                      (eq (emacsvox-aural-recording--capture-phase state) 'ready)))
           (bundle (and ready (emacsvox-aural-recording--bundle))))
      (message "%s delivery recording: %s%s"
               (emacsvox-aural-recording--capture-lane state)
               (if ready (if (eq (gethash "complete" bundle) t) "captured" "incomplete")
                 (emacsvox-aural-recording--capture-phase state))
               (if bundle (format ", client %s, %d bytes; export or cancel"
                                  (emacsvox-aural-recording--disposition bundle)
                                  (length (emacsvox-aural-recording--json bundle))) "")))))

;;;###autoload
(defun emacsvox-aural-export-recording (file)
  "Explicitly save the captured delivery as private JSON in local FILE.
The file can contain speech text and resource paths.  Existing files require
normal overwrite confirmation.  Success clears memory; a failed save retains
it.  No data is uploaded and no speech is replayed."
  (interactive
   (let ((bundle (emacsvox-aural-recording--bundle)))
     (list (read-file-name
            (format "Export %s %s delivery (client %s, %d bytes; includes text and paths): "
                    (gethash "lane" bundle) (if (eq (gethash "complete" bundle) t) "captured" "incomplete")
                    (emacsvox-aural-recording--disposition bundle)
                    (length (emacsvox-aural-recording--json bundle)))
            nil nil nil "emacsvox-delivery.json"))))
  (let* ((bundle (emacsvox-aural-recording--bundle))
         (file (expand-file-name file))
         (bytes (emacsvox-aural-recording--json bundle)) temporary)
    (when (file-remote-p file) (user-error "Export to a local file"))
    (when (file-directory-p file) (user-error "Choose a file, not a directory"))
    (when (and (file-exists-p file) (not (yes-or-no-p (format "Overwrite %s? " file))))
      (user-error "Export cancelled; recording retained"))
    (unwind-protect
        (progn
          (setq temporary (make-temp-file (expand-file-name ".emacsvox-delivery-" (file-name-directory file))))
          (set-file-modes temporary #o600)
          (let ((coding-system-for-write 'no-conversion)) (write-region bytes nil temporary nil 'silent))
          (rename-file temporary file t)
          (setq temporary nil)
          (emacsvox-aural-recording--clear)
          (message "Saved delivery recording to %s" file))
      (when temporary (delete-file temporary)))
    file))

(defun emacsvox-aural-recording--parse (bytes)
  "Read bounded JSON BYTES, rejecting deep arrays and duplicate object keys."
  (when (> (string-bytes bytes) emacsvox-aural-recording--limit) (error "Recording exceeds 64 KiB"))
  (let* ((text (decode-coding-string bytes 'utf-8 t))
         (index 0) (depth 0) keys)
    (unless (equal bytes (encode-coding-string text 'utf-8 t)) (error "Invalid UTF-8"))
    ;; The schema has one root object; all nested data uses tagged arrays.
    ;; Scan depth before asking the JSON parser to allocate nested objects.
    (while (< index (length text))
      (let ((character (aref text index)))
        (cond
         ((= character ?\")
          (let ((start index))
            (cl-incf index)
            (while (and (< index (length text)) (/= (aref text index) ?\"))
              (when (= (aref text index) ?\\) (cl-incf index))
              (cl-incf index))
            (when (>= index (length text)) (error "Unterminated JSON string"))
            (let ((end (1+ index)))
              (while (and (< end (length text)) (memq (aref text end) '(?\s ?\t ?\r ?\n))) (cl-incf end))
              (when (and (= depth 1) (< end (length text)) (= (aref text end) ?:))
                (let ((key (json-parse-string (substring text start (1+ index)))))
                  (when (member key keys) (error "Duplicate recording field"))
                  (push key keys))))))
         ((memq character '(?{ ?\[))
          (when (and (= character ?{) (/= depth 0)) (error "Unexpected nested JSON object"))
          (when (> (cl-incf depth) (+ 8 (* 2 emacsvox-aural-recording--depth-limit))) (error "Recording nesting limit")))
         ((memq character '(?} ?\])) (cl-decf depth))))
      (cl-incf index))
    (json-parse-string text :object-type 'hash-table :array-type 'array
                       :null-object :null :false-object :false)))

(defun emacsvox-aural-recording--strings-p (value)
  "Whether VALUE is a proper list of command strings."
  (and (proper-list-p value) (cl-every #'stringp value)))

(defun emacsvox-aural-recording--plist-p (value)
  "Whether VALUE is a proper plist with distinct keyword keys."
  (and (proper-list-p value) (cl-evenp (length value))
       (let (seen valid)
         (setq valid t)
         (while value
           (let ((key (pop value)))
             (unless (and (keywordp key) (not (memq key seen))) (setq valid nil))
             (push key seen) (pop value)))
         valid)))

(defun emacsvox-aural-recording--map-p (value)
  "Whether VALUE has a plain property-map representation."
  (or (hash-table-p value) (emacsvox-aural-recording--plist-p value)))

(defun emacsvox-aural-recording--operation (entry)
  "Validate ENTRY entirely before any assembly operation is invoked."
  (unless (and (vectorp entry) (= (length entry) 2) (stringp (aref entry 0)))
    (error "Invalid recording operation"))
  (let ((name (aref entry 0)) (args (emacsvox-aural-recording--decode (aref entry 1))))
    (unless (proper-list-p args) (error "Invalid operation arguments"))
    (unless
        (pcase name
          ("id" (and (= (length args) 1) (member (car args) '("action" "semantic" "pause"))))
          ("span" (and (= (length args) 7) (stringp (car args))
                       (or (null (nth 1 args)) (stringp (nth 1 args)))
                       (or (null (nth 2 args))
                           (and (proper-list-p (nth 2 args)) (= (length (nth 2 args)) 2)
                                (cl-every #'emacsvox-aural-recording--plist-p (nth 2 args))))
                       (emacsvox-aural-recording--map-p (nth 3 args))
                       (emacsvox-aural-recording--map-p (nth 4 args))
                       (proper-list-p (nth 6 args))
                       (or (null (nth 5 args)) (and (integerp (nth 5 args)) (<= -20 (nth 5 args) 20)))))
          ("action" (and (= (length args) 5) (stringp (car args))
                         (emacsvox-aural-recording--plist-p (nth 1 args))
                         (stringp (nth 2 args)) (emacsvox-aural-recording--plist-p (nth 3 args))
                         (emacsvox-aural-recording--plist-p (nth 4 args))))
          ("finish" (and (= (length args) 2) (emacsvox-aural-recording--plist-p (car args))
                         (emacsvox-aural-recording--plist-p (cadr args))
                         (memq (plist-get (car args) :protocol_version) '(3 4 5 6 7))
                         (cl-every (lambda (key)
                                     (let ((value (plist-get (car args) key))) (and (integerp value) (< 0 value))))
                                   '(:generation :dispatch_id))))
          ("frame" (and (= (length args) 5) (integerp (car args)) (< 0 (car args))
                        (memq (nth 1 args) '(nil t))
                        (integerp (nth 2 args)) (<= 1 (nth 2 args) emacsvox-aural--timeline-frame-max-bytes)
                        (integerp (nth 3 args)) (<= 4 (nth 3 args) emacsvox-aural--timeline-encoded-fragment-max-bytes)
                        (emacsvox-aural-recording--strings-p (nth 4 args))))
          ("commands" (emacsvox-aural-recording--strings-p args))
          (_ nil))
      (error "Invalid or unknown recording operation"))
    (cons name args)))

(defun emacsvox-aural-recording--reconstruct (object)
  "Validate OBJECT and reconstruct client data, without live delivery."
  (let ((fields '("format" "construction" "source" "emacs" "lane" "complete" "reason" "layered"
                  "outcome" "facts" "operations" "document_hash" "semantics_hash" "wire_hash")))
    (unless (and (hash-table-p object) (= (hash-table-count object) (length fields))
                 (cl-every (lambda (field) (gethash field object)) fields)
                 (eql (gethash "format" object) 1)
                 (eql (gethash "construction" object) emacsvox-aural-recording--construction-version)
                 (stringp (gethash "source" object)) (stringp (gethash "emacs" object))
                 (member (gethash "lane" object) '("main" "notification"))
                 (memq (gethash "complete" object) '(t :false))
                 (memq (gethash "layered" object) '(t :false))
                 (or (eq (gethash "reason" object) :null) (stringp (gethash "reason" object)))
                 (vectorp (gethash "operations" object)) (vectorp (gethash "facts" object))
                 (<= (+ (length (gethash "operations" object)) (length (gethash "facts" object)))
                     emacsvox-aural-recording--operation-limit))
      (error "Invalid or incompatible recording schema")))
  (dolist (field '("document_hash" "semantics_hash" "wire_hash"))
    (let ((value (gethash field object)))
      (unless (or (eq value :null) (and (stringp value) (string-match-p "\\`[a-f0-9]\\{64\\}\\'" value)))
        (error "Invalid recorded hash"))))
  (let* ((emacsvox-aural-recording--budget emacsvox-aural-recording--limit)
         (emacsvox-aural-recording--nodes 0)
         (outcome (emacsvox-aural-recording--decode (gethash "outcome" object)))
         (operations (mapcar #'emacsvox-aural-recording--operation (gethash "operations" object)))
         (emacsvox-aural--recording-observer nil)
         built wire)
    (unless (emacsvox-aural-recording--plist-p outcome) (error "Invalid delivery outcome"))
    (mapc (lambda (fact)
            (unless (and (vectorp fact) (= (length fact) 2)
                         (member (aref fact 0) '("capability" "omitted-action")))
              (error "Unknown recording observation"))
            (emacsvox-aural-recording--decode (aref fact 1))) (gethash "facts" object))
    ;; Validate order before assembly, including late malformed operations.
    (let ((phase 'assembly))
      (dolist (operation operations)
        (pcase (car operation)
          ((or "id" "span" "action") (unless (eq phase 'assembly) (error "Operation after finish")))
          ("finish" (unless (eq phase 'assembly) (error "Repeated finish")) (setq phase 'finished))
          ("frame" (unless (eq phase 'finished) (error "Frame without finish")) (setq phase 'framed))
          ("commands" (unless (and (eq phase 'assembly) (= (length operations) 1)) (error "Mixed compatibility operations"))
           (setq phase 'commands)))))
    (if (eq (gethash "complete" object) :false)
        (list :status 'incomplete :reason (gethash "reason" object) :outcome outcome)
      (let ((assembly (emacsvox-aural--make-assembly
                       :span-contexts (and (eq (gethash "layered" object) t) (make-hash-table :test #'eql)))))
        (dolist (operation operations)
          (let ((args (cdr operation)))
            (pcase (car operation)
              ("id" (apply #'emacsvox-aural--assembly-id assembly args))
              ("span" (apply #'emacsvox-aural--assembly-span assembly args))
              ("action" (apply #'emacsvox-aural--assembly-action assembly args))
              ("finish" (setq built (apply #'emacsvox-aural--assembly-finish assembly args)))
              ("frame"
               (unless built (error "No document to frame"))
               (setf (plist-get (car built) :dispatch_id) (car args))
               (let ((emacsvox-aural--isolated-letter (nth 1 args))
                     (emacsvox-aural--timeline-frame-max-bytes (nth 2 args))
                     (emacsvox-aural--timeline-encoded-fragment-max-bytes (nth 3 args)))
                 (setq wire (append (nth 4 args) (emacsvox-aural--frame-structured-timeline (car built))))))
              ("commands" (setq wire args))))))
      (let ((document-hash (if built (secure-hash 'sha256 (emacsvox-aural-recording--json (car built))) :null))
            (semantics-hash (if built (secure-hash 'sha256 (emacsvox-aural-recording--json
                                                          (emacsvox-aural-recording--snapshot (cdr built)))) :null))
            (wire-hash (if wire (secure-hash 'sha256 (encode-coding-string (apply #'concat wire) 'utf-8 t)) :null)))
        (list :status (if (and (equal document-hash (gethash "document_hash" object))
                              (equal semantics-hash (gethash "semantics_hash" object))
                              (equal wire-hash (gethash "wire_hash" object))) 'matching 'mismatch)
              :coverage (cond (built 'structured-assembly) (wire 'compatibility-bytes) (t 'no-output))
              :outcome outcome :document (car built) :bindings (cadr built) :span-index (nth 2 built) :wire wire)))))

;;;###autoload
(defun emacsvox-aural-reproduce-delivery (file)
  "Reconstruct client data from local recording FILE without speaking it.
Validate size, depth, format, operation names and types before reconstruction.
Report matching hashes, mismatch or incomplete capture.  Matching confirms
client construction only; it does not establish server admission or audio.
Return a plist containing reconstructed data for programmatic inspection."
  (interactive "fDelivery recording: ")
  (when (file-remote-p file) (user-error "Read a local recording file"))
  (let* ((file-name-handler-alist nil)
         (bytes (with-temp-buffer
                  (unless (file-regular-p file) (user-error "Choose a regular recording file"))
                  (set-buffer-multibyte nil)
                  (insert-file-contents-literally file nil 0 (1+ emacsvox-aural-recording--limit))
                  (buffer-string)))
         (result (emacsvox-aural-recording--reconstruct (emacsvox-aural-recording--parse bytes))))
    (when (called-interactively-p 'interactive)
      (message "Delivery reproduction: %s%s; no speech sent"
               (plist-get result :status)
               (if (plist-get result :coverage) (format ", %s" (plist-get result :coverage)) "")))
    result))

(provide 'emacsvox-aural-recording)
;;; emacsvox-aural-recording.el ends here
