;;; emacsvox-register-tests.el --- Register advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated register advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--register-direct-advice
  '((copy-to-register :after
     emacsvox--advice-copy-to-register-after)
    (window-configuration-to-register :after
     emacsvox--advice-window-configuration-to-register-after)
    (frameset-to-register :after
     emacsvox--advice-frameset-to-register-after)
    (frame-configuration-to-register :after
     emacsvox--advice-frame-configuration-to-register-after))
  "Register commands using individually named native advice.")

(ert-deftest emacsvox-register-advice-is-directly-registered ()
  "Migrated register advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--register-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-copy-to-register-uses-explicit-range ()
  "An interactive multi-line copy reports its native range and register."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'copy-to-register)
          notifications)
      (cl-letf (((symbol-function 'dtk-notify)
                 (lambda (text &rest _)
                   (push text notifications))))
        (emacsvox--advice-copy-to-register-after
         ?r (point-min) (point-max)))
      (should
       (equal notifications
              '("Copied 3 lines to register r"))))))

(ert-deftest emacsvox-window-configuration-register-uses-explicit-register ()
  "Window configuration feedback reports its native register argument."
  (let ((ems--interactive-fn-name 'window-configuration-to-register)
        messages)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (apply #'format format-string arguments)
                  messages))))
      (emacsvox--advice-window-configuration-to-register-after ?w))
    (should
     (equal messages
            '("Copied window configuration to register w")))))

(ert-deftest emacsvox-frame-register-feedback-is-target-aware ()
  "Only the matching frame configuration command announces its register."
  (let ((ems--interactive-fn-name 'frameset-to-register)
        messages)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (apply #'format format-string arguments)
                  messages))))
      (emacsvox--advice-frame-configuration-to-register-after ?f)
      (emacsvox--advice-frameset-to-register-after ?s))
    (should
     (equal messages
            '("Copied frame  configuration to register s")))))

(provide 'emacsvox-register-tests)
;;; emacsvox-register-tests.el ends here
