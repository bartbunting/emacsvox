;;; matching-paired.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(let ((source (expand-file-name "test/profile-delivery.el"
                 (or (getenv "EMACSVOX_AUDIT_ROOT")
                     (expand-file-name "../../../../" (file-name-directory load-file-name))))))
 (with-temp-buffer
  (insert-file-contents source)
  (setq-local lexical-binding t)
  (goto-char (point-min))
  (search-forward "\n(let ((fixtures")
  (let ((load-file-name source)) (eval-region (point-min) (match-beginning 0)))))
(defvar audit-cache-enabled t)
(defun audit-match-mode (original &rest args)
 (let ((emacsvox-aural--match-cache (and audit-cache-enabled emacsvox-aural--match-cache)))
  (apply original args)))
(advice-add 'emacsvox-aural--prepared-rule-matches :around #'audit-match-mode)
(let ((fixtures (omnivox-choice-consumer-test--with-speech (delivery-profile--fixtures))))
 (unwind-protect
  (dotimes (round 3)
   (dolist (fixture (if (cl-evenp round) fixtures (reverse fixtures)))
    (let (digests)
     (dolist (method (if (cl-evenp round) '(nil t) '(t nil)))
      (let* ((audit-cache-enabled method) (result (delivery-profile--run fixture)))
       (push (plist-get result :document-sha256) digests)
       (princ (format "Paired: %S\n" (append (list :round round :cache method) result)))))
     (unless (equal (car digests) (cadr digests)) (error "Cache changed document")))))
  (advice-remove 'emacsvox-aural--prepared-rule-matches #'audit-match-mode)
  (dolist (fixture fixtures) (kill-buffer (cadr fixture)))))

;;; matching-paired.el ends here
