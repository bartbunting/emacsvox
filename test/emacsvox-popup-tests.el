;;; emacsvox-popup-tests.el --- Popup advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'popup)
(load (expand-file-name "../lisp/emacsvox-popup.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-popup-advice-is-current-and-direct ()
  "Current Popup targets use native advice directly."
  (dolist (entry emacsvox-popup--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-popup-event-loop-preserves-result ()
  "Popup event-loop advice calls its original once and returns its value."
  (let ((calls 0))
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'emacsvox-popup-speak-item) #'ignore))
      (should
       (eq 'selected
           (emacsvox--advice-popup-menu-event-loop-around
            (lambda (&rest _)
              (cl-incf calls)
              'selected)
            'popup 'keymap 'fallback)))
      (should (= calls 1)))))

(ert-deftest emacsvox-popup-prompt-uses-native-argument ()
  "Popup prompt advice speaks its explicit PROMPT argument."
  (let (spoken)
    (cl-letf (((symbol-function 'sit-for) (lambda (&rest _) t))
              ((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-popup-menu-read-key-sequence-before
       'keymap "Choose: " 2))
    (should (equal spoken "Choose: "))))

(provide 'emacsvox-popup-tests)
;;; emacsvox-popup-tests.el ends here
