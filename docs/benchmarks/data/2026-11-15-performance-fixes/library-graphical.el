;;; library-graphical.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(load (expand-file-name "../2026-11-15-performance-audit/bootstrap.el" (file-name-directory load-file-name)) nil t)
(setq debug-on-error nil debug-on-quit nil)
(let ((profile (expand-file-name "private-profile/" audit-out)))
  (setq user-emacs-directory profile custom-file (expand-file-name "custom.el" profile)
        user-init-file custom-file emacsvox-user-directory (expand-file-name "data/" profile))
  (make-directory emacsvox-user-directory t))
(require 'plain-voices)
(when-let* ((path (getenv "EMACSVOX_AUDIT_VERTICO"))) (add-to-list 'load-path path))
(require 'emacsvox-sound-library-tests)
(load (expand-file-name "lisp/ui/emacsvox-sound-library.elc" audit-root) nil t t)
(require 'emacsvox-table-reader-tests)
(advice-add 'emacsvox-sounds-play-concrete-cue :override #'ignore)
(advice-add 'message :after
            (lambda (fmt &rest args)
              (when fmt
                (with-temp-buffer
                  (insert (apply #'format-message fmt args) "\n")
                  (write-region (point-min) (point-max)
                                (expand-file-name "library-graphical.log" audit-out) t 'silent)))))
(condition-case err
    (progn
      (unless (display-graphic-p) (error "A graphical frame is required"))
      (message "Library: %s; Vertico: %s; Emacs %s"
               (symbol-file 'emacsvox-sound-library--scan) (locate-library "vertico") emacs-version)
      (let ((stats (ert-run-tests-batch '(or "^emacsvox-sound-library-" "^emacsvox-table-reader-"))))
        (kill-emacs (if (and (zerop (ert-stats-completed-unexpected stats))
                            (zerop (ert-stats-skipped stats))) 0 1))))
  (error (message "Runner failure: %S" err) (kill-emacs 2)))

;;; library-graphical.el ends here
