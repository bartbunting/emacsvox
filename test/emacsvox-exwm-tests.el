;;; emacsvox-exwm-tests.el --- EXWM advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(exwm exwm-floating exwm-input exwm-layout exwm-workspace))
(load (expand-file-name "../lisp/emacsvox-exwm.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-exwm-advice-is-current-and-direct ()
  "Current EXWM targets use native advice directly."
  (dolist (entry emacsvox-exwm--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-exwm-prompt-advice-uses-native-argument ()
  "Workspace prompt advice speaks its explicit PROMPT argument."
  (let (spoken)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-exwm-workspace--prompt-for-workspace-before
       "Workspace: "))
    (should (equal spoken "Workspace: "))))

(ert-deftest emacsvox-exwm-prefix-recovery-preserves-speech-commands ()
  "EXWM offers simulation-key recovery without consuming another command."
  (dolist (prefix '("C-e" "C-c e" "<f12> <f11>"))
    (let ((emacsvox-prefix (kbd prefix))
          (emacsvox-keymap (copy-keymap emacsvox-keymap))
          (exwm-mode-map (make-sparse-keymap)))
      (cl-letf (((symbol-function 'emacsvox-keymap) emacsvox-keymap)
                ((symbol-function 'emacsvox-speak-frame-title) #'ignore))
        (dotimes (_ 2) (emacsvox-exwm-mode-hook))
        (should (eq (lookup-key exwm-mode-map (vconcat emacsvox-prefix "e"))
                    'exwm-input-send-simulation-key))
        (should (eq (lookup-key emacsvox-keymap (kbd "C-c"))
                    'emacsvox-selective-display))
        (unless (equal prefix "C-c e")
          (should (eq (lookup-key exwm-mode-map
                                     (vconcat emacsvox-prefix emacsvox-prefix))
                      'exwm-input-send-simulation-key)))))))

(provide 'emacsvox-exwm-tests)
;;; emacsvox-exwm-tests.el ends here
