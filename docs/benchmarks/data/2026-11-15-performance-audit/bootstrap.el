;;; bootstrap.el --- Disposable performance investigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off audit reproduction. Use the report's environment and commands.
;; This file is not loaded by Emacsvox.
;;; Code:
(require 'cl-lib)
(require 'json)
(require 'package)
(defconst audit-root (file-name-as-directory (or (getenv "EMACSVOX_AUDIT_ROOT")
  (expand-file-name "../../../../" (file-name-directory load-file-name)))))
(defconst audit-out (file-name-as-directory (or (getenv "EMACSVOX_AUDIT_OUTPUT")
  (make-temp-file "emacsvox-audit-" t))))
(make-directory audit-out t)
(message "Audit output: %s" audit-out)
(defconst audit-deps (file-name-as-directory (or (getenv "EMACSVOX_AUDIT_DEPS")
  (error "Set EMACSVOX_AUDIT_DEPS to the verified dependency directory"))))
(setq package-user-dir audit-deps package-directory-list nil load-prefer-newer nil
      gc-cons-threshold 128000000 gc-cons-percentage 0.1
      ring-bell-function #'ignore emacsvox-play-program nil)
(fset 'ding #'ignore)
(setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" audit-root))
(let ((lock (with-temp-buffer
              (insert-file-contents (expand-file-name "test/integration-dependencies.json" audit-root))
              (json-parse-buffer :object-type 'alist :array-type 'list))))
  (dolist (package (alist-get 'packages lock))
    (let ((name (alist-get 'name package)))
      (add-to-list 'load-path (expand-file-name name audit-deps))
      (load (expand-file-name (format "%s/%s-autoloads.el" name name) audit-deps) nil t t))))
(add-to-list 'load-path (expand-file-name "lisp" audit-root))
(add-to-list 'load-path (expand-file-name "test" audit-root))
(require 'emacsvox-preamble)
(setq-default emacsvox-speak-messages nil)
(defvar audit-results nil)
(defun audit-measure (name dimensions function repetitions)
  (let* ((start (current-time))
         (_ (funcall function))
         (cold (* 1000 (float-time (time-since start)))))
    (dotimes (_ 3) (funcall function))
    (garbage-collect)
    (let ((counts (memory-use-counts)) (gcs gcs-done) (gc-time gc-elapsed) samples)
      (dotimes (_ repetitions)
        (let ((start (current-time)))
          (funcall function)
          (push (* 1000 (float-time (time-since start))) samples)))
      (let* ((samples (nreverse samples))
             (sorted (sort (copy-sequence samples) #'<))
             (result (append (list :case name :cold-ms cold :iterations repetitions
                                   :median-ms (if (cl-oddp repetitions) (nth (/ repetitions 2) sorted)
                        (/ (+ (nth (1- (/ repetitions 2)) sorted)
                              (nth (/ repetitions 2) sorted)) 2.0))
                                   :max-ms (car (last sorted))
                                   :gc-count (- gcs-done gcs) :gc-seconds (- gc-elapsed gc-time)
                                   :allocation-counts (cl-mapcar #'- (memory-use-counts) counts)
                                   :samples-ms samples) dimensions)))
        (when (>= repetitions 20)
          (setq result (append result (list :p95-ms (nth (1- (ceiling (* 0.95 repetitions))) sorted)))))
        (push result audit-results)
        (message "Audit %s %S: median %.3f ms, max %.3f ms" name dimensions (plist-get result :median-ms) (plist-get result :max-ms))
        (princ (format "%S\n" result))
        result))))
(defun audit-save (name &optional extra)
  (with-temp-file (expand-file-name name audit-out)
    (let ((print-length nil) (print-level nil))
      (prin1 (list :emacs emacs-version :source-commit (car (process-lines "git" "-C" audit-root "rev-parse" "HEAD"))
                   :gc-threshold gc-cons-threshold :gc-percentage gc-cons-percentage
                   :extra extra :results (reverse audit-results)) (current-buffer)))))

;;; bootstrap.el ends here
