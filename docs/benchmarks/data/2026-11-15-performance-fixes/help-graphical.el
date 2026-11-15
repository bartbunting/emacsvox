;;; help-graphical.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(load (expand-file-name "../2026-11-15-performance-audit/bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'emacsvox-manual-workflow-tests)
(condition-case err
    (progn
      (unless (display-graphic-p) (error "A graphical frame is required"))
      (let ((stats (ert-run-tests-batch 'emacsvox-manual-help-selects-help-without-killing-work)))
        (with-temp-file (expand-file-name "help-graphical.eld" audit-out)
          (prin1 (list :emacs emacs-version :graphical (display-graphic-p)
                       :implementation (symbol-file 'emacsvox-speak-help)
                       :tests (ert-stats-total stats) :unexpected (ert-stats-completed-unexpected stats)
                       :skipped (ert-stats-skipped stats)) (current-buffer)))
        (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))
  (error (with-temp-file (expand-file-name "help-error.txt" audit-out) (prin1 err (current-buffer)))
         (kill-emacs 2)))

;;; help-graphical.el ends here
