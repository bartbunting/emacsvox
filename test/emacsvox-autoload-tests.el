;;; emacsvox-autoload-tests.el --- Autoload generation tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify the Emacs 31 loaddefs generation path.

;;; Code:

(require 'cl-lib)
(require 'ert)

(load
 (expand-file-name
  "../lisp/emacsvox-autoload.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(defvar emacsvox-auto-autoloads-file)
(defvar emacsvox-lisp-directory)

(defconst emacsvox-autoload-tests--root
  (expand-file-name
   "../" (file-name-directory (or load-file-name buffer-file-name))))

(ert-deftest emacsvox-autoload-generation-uses-loaddefs-gen ()
  "Autoload generation calls the supported Emacs 31 API directly."
  (let ((emacsvox-lisp-directory "/tmp/emacsvox-lisp")
        (emacsvox-auto-autoloads-file "/tmp/emacsvox-loaddefs.el")
        observed)
    (cl-letf (((symbol-function 'loaddefs-generate)
               (lambda (&rest arguments)
                 (setq observed arguments)
                 'generated))
              ((symbol-function 'locate-library)
               (lambda (&rest _)
                 (error "Legacy loaddefs probe invoked")))
              ((symbol-function 'update-directory-autoloads)
               (lambda (&rest _)
                 (error "Legacy autoload generator invoked"))))
      (should (eq (emacsvox-auto-generate-autoloads) 'generated)))
    (should
     (equal
      observed
      '("/tmp/emacsvox-lisp" "/tmp/emacsvox-loaddefs.el")))))

(ert-deftest emacsvox-portable-configure-generates-loaddefs ()
  "The Emacs-only first-run command works without Make or the current directory."
  (let* ((root (make-temp-file "emacsvox-configure-" t))
         (etc-directory (expand-file-name "etc" root))
         (lisp-directory (expand-file-name "lisp" root))
         (emacs (expand-file-name invocation-name invocation-directory))
         (output (generate-new-buffer " *emacsvox-configure-output*")))
    (unwind-protect
        (progn
          (make-directory etc-directory)
          (make-directory lisp-directory)
          (copy-file
           (expand-file-name
            "etc/configure-emacsvox.el" emacsvox-autoload-tests--root)
           (expand-file-name "configure-emacsvox.el" etc-directory))
          (copy-file
           (expand-file-name
            "lisp/emacsvox-autoload.el" emacsvox-autoload-tests--root)
           (expand-file-name "emacsvox-autoload.el" lisp-directory))
          (with-temp-file (expand-file-name "example.el" lisp-directory)
            (insert
             (concat
              ";;; example.el --- Portable configuration fixture "
              "-*- lexical-binding: t; -*-\n")
             ";;;###autoload\n"
             "(defun emacsvox-test-configured-command () (interactive))\n"))
          (let ((default-directory temporary-file-directory))
            (let ((status
                   (call-process
                    emacs nil output nil "-Q" "--batch" "-l"
                    (expand-file-name
                     "configure-emacsvox.el" etc-directory))))
              (unless (zerop status)
                (ert-fail
                 (format
                  "Portable configuration exited %s: %s"
                  status
                  (with-current-buffer output (buffer-string)))))))
          (should
           (file-readable-p
            (expand-file-name "emacsvox-loaddefs.el" lisp-directory)))
          (with-current-buffer output
            (should (string-search "Configured Emacsvox in" (buffer-string)))))
      (kill-buffer output)
      (delete-directory root t))))

(provide 'emacsvox-autoload-tests)
;;; emacsvox-autoload-tests.el ends here
