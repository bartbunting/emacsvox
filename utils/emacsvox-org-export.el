;;; emacsvox-org-export.el --- Export the maintained Org manual -*- lexical-binding: t; -*-

;;; Commentary:

;; Export the canonical Org manual source to a caller-selected Texinfo file.
;; The root Makefile keeps this authoring operation separate from Emacsvox
;; byte-code and from tracked documentation artifacts.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'ox-texinfo)
(require 'subr-x)

(declare-function org-texinfo-headline "ox-texinfo")

(defun emacsvox-org-export--node-disabled-p (headline)
  "Return non-nil when HEADLINE should not create a Texinfo node."
  (string-equal
   "no"
   (downcase (or (org-element-property :TEXINFO_NODE headline) ""))))

(defun emacsvox-org-export--headline (headline contents info)
  "Export HEADLINE with CONTENTS and INFO, honoring TEXINFO_NODE."
  (let ((rendered (org-texinfo-headline headline contents info)))
    (if (not (emacsvox-org-export--node-disabled-p headline))
        rendered
      (replace-regexp-in-string "\\`@node[^\n]*\n" "" rendered))))

(unless (org-export-get-backend 'emacsvox-texinfo)
  (org-export-define-derived-backend 'emacsvox-texinfo 'texinfo
    :translate-alist '((headline . emacsvox-org-export--headline))))

(defun emacsvox-org-export--required-environment (name)
  "Return the non-empty environment variable NAME."
  (let ((value (getenv name)))
    (when (string-empty-p (or value ""))
      (error "Environment variable %s is required" name))
    value))

(defun emacsvox-org-export (source output &optional body-only)
  "Export Org SOURCE as Texinfo OUTPUT and return OUTPUT.

SOURCE and OUTPUT are expanded before use.  OUTPUT's parent directory is
created when needed.  When BODY-ONLY is non-nil, omit the standalone Texinfo
header and trailer."
  (let* ((source (expand-file-name source))
         (output (expand-file-name output))
         (output-directory (file-name-directory output)))
    (unless (file-regular-p source)
      (error "Org manual source is not a regular file: %s" source))
    (make-directory output-directory t)
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source
            default-directory (file-name-directory source))
      ;; Export is a build operation.  Do not run user or Emacsvox Org-mode
      ;; hooks in this temporary parsing buffer.
      (delay-mode-hooks (org-mode))
      (let ((issues (org-lint)))
        (when issues
          (error "Org manual lint failed:\n%s"
                 (mapconcat #'prin1-to-string issues "\n"))))
      (let ((org-export-time-stamp-file nil)
            (org-export-use-babel nil)
            (org-confirm-babel-evaluate nil)
            (menu-entries (symbol-function 'org-texinfo--menu-entries))
            (get-node (symbol-function 'org-texinfo--get-node)))
        (cl-letf
            (((symbol-function 'org-texinfo--menu-entries)
              (lambda (scope info)
                (cl-remove-if
                 #'emacsvox-org-export--node-disabled-p
                 (funcall menu-entries scope info))))
             ((symbol-function 'org-texinfo--get-node)
              (lambda (datum info)
                (or (and (org-element-type-p datum 'headline)
                         (org-element-property :TEXINFO_NODE_NAME datum))
                    (funcall get-node datum info)))))
          (org-export-to-file 'emacsvox-texinfo output nil nil nil body-only
                              '(:with-broken-links nil)))))
    output))

(defun emacsvox-org-export-batch ()
  "Export the Org manual named by the batch environment."
  (condition-case condition
      (let ((output
             (emacsvox-org-export
              (emacsvox-org-export--required-environment
               "EMACSVOX_ORG_SOURCE")
              (emacsvox-org-export--required-environment
               "EMACSVOX_ORG_OUTPUT")
              (string-equal "1" (getenv "EMACSVOX_ORG_BODY_ONLY")))))
        (message "Exported Org manual to %s" output))
    (error
     (message "Org manual export failed: %s"
              (error-message-string condition))
     (let ((kill-emacs-hook nil)
           (kill-emacs-query-functions nil))
       (kill-emacs 1)))))

(provide 'emacsvox-org-export)
;;; emacsvox-org-export.el ends here
