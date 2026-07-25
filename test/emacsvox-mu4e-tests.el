;;; emacsvox-mu4e-tests.el --- Mu4e advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'seq)

(defconst emacsvox-mu4e-test--available (require 'mu4e nil t)
  "Non-nil when the optional Mu4e system package is installed.")

(load (expand-file-name "../lisp/emacsvox-message.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)
(load (expand-file-name "../lisp/emacsvox-mu4e.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-mu4e-uses-generic-message-send-feedback ()
  "Mu4e relies on Message's low-level send feedback without duplication."
  (should
   (advice-member-p
    #'emacsvox--advice-message-send-around
    'message-send))
  (should-not
   (seq-find
    (lambda (entry)
      (eq (car entry) 'message-send-and-exit))
    emacsvox-mu4e--advice)))

(ert-deftest emacsvox-mu4e-advice-is-current-and-direct ()
  "Current Mu4e targets use native advice directly."
  (skip-unless emacsvox-mu4e-test--available)
  (mapc #'require '(mu4e-compose mu4e-headers mu4e-mark mu4e-search
                    mu4e-update mu4e-view))
  (emacsvox-mu4e--install-advice)
  (dolist (entry emacsvox-mu4e--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-mu4e-tests)
;;; emacsvox-mu4e-tests.el ends here
