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
    (point-to-register :after
     emacsvox--advice-point-to-register-after)
    (view-register :after
     emacsvox--advice-view-register-after)
    (jump-to-register :after
     emacsvox--advice-jump-to-register-after)
    (insert-register :after
     emacsvox--advice-insert-register-after)
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

(ert-deftest emacsvox-point-to-register-feedback-reflects-prefix ()
  "A prefix reports frame storage instead of speaking the current line."
  (let ((ems--interactive-fn-name 'point-to-register)
        (current-prefix-arg '(4))
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'message)
               (lambda (text) (push (list 'message text) events))))
      (emacsvox--advice-point-to-register-after))
    (should
     (equal
      (nreverse events)
      '((icon mark-object)
        (message "Stored current frame configuration"))))))

(ert-deftest emacsvox-view-register-speaks-output-buffer ()
  "Viewing a register speaks its output before the opening cue."
  (let* ((existing-output (get-buffer "*Output*"))
         (output (or existing-output (get-buffer-create "*Output*")))
         (ems--interactive-fn-name 'view-register)
         events)
    (unwind-protect
        (with-current-buffer output
          (let ((inhibit-read-only t)
                (original-text (buffer-string)))
            (unwind-protect
                (progn
                  (erase-buffer)
                  (insert "register contents")
                  (cl-letf (((symbol-function 'dtk-speak)
                             (lambda (text)
                               (push
                                (list 'speak text (current-buffer))
                                events)))
                            ((symbol-function 'emacsvox-icon)
                             (lambda (icon)
                               (push (list 'icon icon) events))))
                    (emacsvox--advice-view-register-after)))
              (erase-buffer)
              (insert original-text))))
      (unless existing-output
        (kill-buffer output)))
    (should
     (equal
      (nreverse events)
      `((speak "register contents" ,output) (icon open-object))))))

(ert-deftest emacsvox-register-movement-enables-show-point ()
  "Register insertion and jumping speak with point highlighting enabled."
  (let ((ems--interactive-fn-name 'insert-register)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda ()
                 (push (list 'speak-line emacsvox-show-point) events))))
      (emacsvox--advice-jump-to-register-after)
      (emacsvox--advice-insert-register-after))
    (should
     (equal
      (nreverse events)
      '((icon yank-object) (speak-line t))))))

(provide 'emacsvox-register-tests)
;;; emacsvox-register-tests.el ends here
