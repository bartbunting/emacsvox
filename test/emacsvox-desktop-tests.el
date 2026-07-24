;;; emacsvox-desktop-tests.el --- Desktop advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'desktop)
(require 'ert)
(load
 (expand-file-name "../lisp/emacsvox-desktop.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-desktop-advice-is-directly-registered ()
  (dolist
      (entry
       '((desktop-clear :after emacsvox--advice-desktop-clear-after)
         (desktop-save :after emacsvox--advice-desktop-save-after)
         (desktop-lazy-create-buffer
          :around emacsvox--advice-desktop-lazy-create-buffer-around)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-desktop-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'desktop-save) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push text events))))
      (emacsvox--advice-desktop-clear-after)
      (emacsvox--advice-desktop-save-after))
    (should (equal events '(save-object)))))

(ert-deftest emacsvox-desktop-lazy-buffer-runs-once ()
  (let ((calls 0))
    (should
     (eq 'result
         (emacsvox--advice-desktop-lazy-create-buffer-around
          (lambda (&rest args)
            (setq calls (1+ calls))
            (should (equal args '(one two)))
            'result)
          'one 'two)))
    (should (= calls 1))))

(provide 'emacsvox-desktop-tests)
