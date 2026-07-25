;;; emacsvox-epub-tests.el --- EPUB integration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Focused coverage for EPUB commands outside DOM extraction.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-reading-dom-tests)

(defvar locate-command)
(defvar locate-make-command-line)

(ert-deftest emacsvox-epub-locate-uses-case-insensitive-command ()
  "EPUB Locate searches dynamically install a case-insensitive command."
  (let ((locate-command "plocate")
        observed)
    (cl-letf (((symbol-function 'locate-with-filter)
               (lambda (search-string filter &optional arg)
                 (setq observed
                       (list
                        search-string
                        filter
                        arg
                        (funcall locate-make-command-line search-string)))
                 'locate-result)))
      (should
       (eq
        (emacsvox-epub-locate-epubs "Accessible Emacs")
        'locate-result)))
    (should
     (equal
      observed
      '("Accessible Emacs"
        "\\.epub\\'"
        nil
        ("plocate" "-i" "Accessible Emacs"))))))

(provide 'emacsvox-epub-tests)
;;; emacsvox-epub-tests.el ends here
