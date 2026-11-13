;;; run-lightweight-reload.el --- Isolated source client experiment -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Requires a disposable configuration/voice root and explicit experimental
;; executable. No live profile is contacted. This is a native integration probe,
;; not a public settings command or a replacement for full candidate capture.
(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (setq load-prefer-newer t)
  (require 'emacsvox-preamble)
  (require 'tts-speak)
  (require 'omnivox-voices)
  (require 'omnivox-library)
  (setq emacsvox-servers-directory (expand-file-name "servers/" root))
  (dolist (symbol '(tts-initialize omnivox-library--owner
                   omnivox--control-process-filter))
    (let ((file (symbol-file symbol 'defun)))
      (unless (and file (string-prefix-p root file)
                   (string-suffix-p ".el" file))
        (error "Unexpected loaded source for %s: %s" symbol file))
      (princ (format "Loaded %s from %s\n" symbol file)))))
(require 'json)
(setq tts-program "omnivox" emacsvox-speak-messages nil
      tts-notification-device "both" debug-on-error t)
(unless (and (getenv "OMNIVOX_PROGRAM")
             (getenv "OMNIVOX_EXPERIMENTAL_RELOAD_TOKEN")
             (getenv "OMNIVOX_CONFIG_DIR") (getenv "OMNIVOX_VOICE_ROOT"))
  (error "Explicit isolated inputs are required"))
(defun lightweight-test--json (text)
  (json-parse-string text :object-type 'hash-table :array-type 'array
                     :null-object :null :false-object :false))
(defun lightweight-test--observe (process output)
  (let ((text (concat (process-get process 'lightweight-tail) output)))
    (when (string-match "__OMNIVOX_LIGHTWEIGHT__ \\(.*\\)\n" text)
      (process-put process 'lightweight-endpoint
                   (lightweight-test--json (match-string 1 text))))
  (process-put process 'lightweight-tail
               (substring output (max 0 (- (length output) 65536))))))
(advice-add 'omnivox--control-process-filter :before #'lightweight-test--observe)
(defun lightweight-test--reload (process)
  (let* ((endpoint (or (process-get process 'lightweight-endpoint)
                       (error "No private endpoint")))
         (state (gethash "state" endpoint))
         (owner (omnivox-library--owner process))
         (startup (with-temp-buffer
                    (insert-file-contents (plist-get owner :startup))
                    (lightweight-test--json (buffer-string))))
         (candidate (gethash "engines" startup))
         (profile (gethash "probe" (gethash "profiles" (gethash "punctuation" candidate))))
         (address (split-string (gethash "address" endpoint) ":"))
         (request (make-hash-table :test #'equal)) result connection)
    ;; Controlled fixture: mutate exactly one punctuation entry in a validated
    ;; retained snapshot. Native Python probes separately exercise full capture.
    (puthash "!" "emacs updated" (gethash "table" profile))
    (dolist (pair `(("token" . ,(getenv "OMNIVOX_EXPERIMENTAL_RELOAD_TOKEN"))
                    ("incarnation" . ,(gethash "incarnation" state))
                    ("expected" . ,(gethash "policy" state)) ("candidate" . ,candidate)))
      (puthash (car pair) (cdr pair) request))
    (unwind-protect
        (progn
          (setq connection
                (make-network-process :name "private-reload-probe" :host (car address)
                                      :service (string-to-number (cadr address))
                                      :coding 'binary :noquery t
                                      :filter (lambda (_process text)
                                                (setq result (concat result text)))))
          (let* ((bytes (encode-coding-string (json-serialize request :null-object :null :false-object :false) 'utf-8))
                 (n (length bytes)))
            (process-send-string connection
                                 (concat (apply #'unibyte-string
                                                (mapcar (lambda (shift) (logand 255 (ash n shift))) '(-24 -16 -8 0)))
                                         bytes)))
          (let ((end (+ (float-time) 5)))
            (while (and (not (string-match-p "\n" (or result ""))) (< (float-time) end))
              (accept-process-output connection .01)))
          (let ((reply (lightweight-test--json result)))
            (unless (equal (gethash "outcome" reply) "applied") (error "Reload failed: %S" reply))
            (princ (format "Applied to %s without replacing process %s\n" (process-name process) (process-id process)))))
      (when connection (delete-process connection)))))
(unwind-protect
    (progn
      (tts-initialize)
      (let ((speaker tts-speaker-process) (notify tts-notify-process))
        (unless (and (process-live-p speaker) (process-live-p notify)) (error "Incomplete pair"))
        (lightweight-test--reload speaker)
        (lightweight-test--reload notify)
        (tts-letter ?A)
        (accept-process-output nil .2)
        (unless (and (eq speaker tts-speaker-process) (eq notify tts-notify-process))
          (error "Reload replaced a worker"))
        (princ "PASS: source Emacsvox startup, independent reload and character submission\n")))
  (dolist (process (list tts-speaker-process tts-notify-process))
    (when (processp process) (tts--retire-process process))))
