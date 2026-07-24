;;; emacsvox-face-symbol-tests.el --- Face symbol tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Guard Emacs 31 face-symbol usage in modules migrated from obsolete
;; face-variable evaluation.

;;; Code:

(require 'cl-lib)
(require 'ert)

(defconst emacsvox-test--face-symbol-root
  (expand-file-name
   "../"
   (file-name-directory (or load-file-name buffer-file-name)))
  "Emacsvox checkout root used by face-symbol tests.")

(defconst emacsvox-test--face-symbol-source-files
  '("lisp/emacsvox-bookshare.el"
    "lisp/emacsvox-webspace.el"
    "lisp/gmaps.el"
    "lisp/ladspa.el"
    "lisp/sox.el")
  "Source files migrated from obsolete face-variable evaluation.")

(defun emacsvox-test--has-unquoted-obsolete-face-p (file)
  "Return non-nil when FILE evaluates an obsolete face variable."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name file emacsvox-test--face-symbol-root))
    (emacs-lisp-mode)
    (goto-char (point-min))
    (catch 'found
      (while
          (re-search-forward
           "\\_<font-lock-\\(?:doc\\|keyword\\|string\\)-face\\_>"
           nil t)
        (let ((start (match-beginning 0)))
          (unless
              (or (save-excursion (nth 8 (syntax-ppss start)))
                  (eq (char-before start) ?'))
            (throw 'found t))))
      nil)))

(ert-deftest emacsvox-face-symbols-are-quoted ()
  "Migrated modules use face names as quoted symbols."
  (should-not
   (cl-remove-if-not
    #'emacsvox-test--has-unquoted-obsolete-face-p
    emacsvox-test--face-symbol-source-files)))

(provide 'emacsvox-face-symbol-tests)
;;; emacsvox-face-symbol-tests.el ends here
