;;; emacsvox-mu4e-tests.el --- Mu4e advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)

(defconst emacsvox-mu4e-test--available (require 'mu4e nil t)
  "Non-nil when the optional Mu4e system package is installed.")

(load (expand-file-name "../lisp/emacsvox-message.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)
(load (expand-file-name "../lisp/emacsvox-mu4e.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-mu4e-message-advice-name-is-module-specific ()
  "Mu4e does not replace the generic Message integration's advice helper."
  (should
   (member
    '(message-send-and-exit :after
      emacsvox--advice-mu4e-message-send-and-exit-after)
    emacsvox-mu4e--advice))
  (should
   (fboundp 'emacsvox--advice-mu4e-message-send-and-exit-after))
  (should
   (advice-member-p
    #'emacsvox--advice-message-send-and-exit-after
    'message-send-and-exit))
  (should
   (advice-member-p
    #'emacsvox--advice-mu4e-message-send-and-exit-after
    'message-send-and-exit)))

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
