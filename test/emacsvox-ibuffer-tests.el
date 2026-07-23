;;; emacsvox-ibuffer-tests.el --- Ibuffer advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Ibuffer advice.

;;; Code:

(require 'ert)
(require 'ibuffer)
(require 'ibuf-ext)
(require 'replace)

(defconst emacsvox-test--ibuffer-removed-targets
  '(ibuffer-limit-disable
    ibuffer-occur-display-occurence
    ibuffer-occur-goto-occurence
    ibuffer-quit)
  "Ibuffer commands absent from Emacs 31.")

(ert-deftest emacsvox-ibuffer-obsolete-targets-remain-absent ()
  "The integration must not recreate commands removed before Emacs 31."
  (dolist (target emacsvox-test--ibuffer-removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-ibuffer-emacs31-replacement-targets-exist ()
  "Current filtering, Occur, and quit commands are available."
  (dolist (target
           '(ibuffer-filter-disable
             occur-mode-display-occurrence
             occur-mode-goto-occurrence
             quit-window))
    (should (fboundp target)))
  (with-temp-buffer
    (ibuffer-mode)
    (should (eq (key-binding (kbd "q")) 'quit-window))))

(provide 'emacsvox-ibuffer-tests)
;;; emacsvox-ibuffer-tests.el ends here
