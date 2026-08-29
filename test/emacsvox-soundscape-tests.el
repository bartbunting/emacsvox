;;; emacsvox-soundscape-tests.el --- Optional Soundscape tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify that Boodler setup is deferred until the user invokes Soundscape.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-optional-module-test-utils)

(load (expand-file-name
       "../lisp/soundscape.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-soundscape-loads-without-a-catalog ()
  "The Soundscape module should load before Boodler data exists."
  (emacsvox-optional-module-test-load
   "soundscape.el"
   '(progn
      (defun emacsvox-test--missing-soundscape-catalog
          (original filename)
        (if (string-match-p "/soundscapes\\'" filename)
            nil
          (funcall original filename)))
      (advice-add
       'file-exists-p :around #'emacsvox-test--missing-soundscape-catalog))
   '(unless (featurep 'soundscape)
      (error "Soundscape module did not load independently"))))

(ert-deftest emacsvox-soundscape-catalog-error-is-actionable ()
  "Catalog discovery should report its missing path at point of use."
  (let ((soundscape-list "/nonexistent/emacsvox-soundscapes")
        (soundscape--catalog nil))
    (let ((condition (should-error (soundscape-catalog) :type 'user-error)))
      (should
       (string-match-p
        "/nonexistent/emacsvox-soundscapes.*customize soundscape-data"
        (error-message-string condition))))))

(ert-deftest emacsvox-soundscape-init-loads-theme-lazily ()
  "Initialization should load the theme immediately before the listener."
  (let ((soundscape-default-theme '(("()" nil)))
        (minor-mode-alist nil)
        events)
    (cl-letf (((symbol-function 'soundscape-load-theme)
               (lambda (theme) (push (list 'theme theme) events)))
              ((symbol-function 'soundscape-listener)
               (lambda (&optional _) (push 'listener events))))
      (soundscape-init))
    (should
     (equal (nreverse events)
            '((theme (("()" nil))) listener)))))

(ert-deftest emacsvox-soundscape-play-reports-missing-boodler ()
  "Playing a Soundscape should explain a missing Boodler executable."
  (let ((soundscape-player nil)
        (soundscape-processes (make-hash-table :test #'equal)))
    (cl-letf (((symbol-function 'executable-find) #'ignore))
      (let ((condition
             (should-error (soundscape "example/Scape") :type 'user-error)))
        (should
         (string-match-p
          "Install Boodler.*PATH" (error-message-string condition)))))))

(provide 'emacsvox-soundscape-tests)
;;; emacsvox-soundscape-tests.el ends here
