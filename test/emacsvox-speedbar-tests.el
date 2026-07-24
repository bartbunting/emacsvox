;;; emacsvox-speedbar-tests.el --- Speedbar advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Speedbar advice.

;;; Code:

(require 'ert)
(require 'speedbar)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-speedbar.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--speedbar-advice
  '((dframe-close-frame :around
                        emacsvox--advice-dframe-close-frame-around)
    (speedbar-next :around emacsvox--advice-speedbar-next-around)
    (speedbar-prev :around emacsvox--advice-speedbar-prev-around)
    (speedbar-edit-line :after emacsvox--advice-speedbar-edit-line-after)
    (speedbar-tag-find :after emacsvox--advice-speedbar-tag-find-after)
    (speedbar-find-file :after emacsvox--advice-speedbar-find-file-after)
    (speedbar-expand-line :after emacsvox--advice-speedbar-expand-line-after)
    (speedbar-contract-line :after
                            emacsvox--advice-speedbar-contract-line-after)
    (speedbar-up-directory :around
                           emacsvox--advice-speedbar-up-directory-around)
    (speedbar-restricted-next :after
                              emacsvox--advice-speedbar-restricted-next-after)
    (speedbar-restricted-prev :after
                              emacsvox--advice-speedbar-restricted-prev-after)
    (speedbar-make-button :after
                          emacsvox--advice-speedbar-make-button-after))
  "Current Emacs 31 Speedbar targets and their direct native advice.")

(ert-deftest emacsvox-speedbar-advice-is-directly-registered ()
  "Speedbar advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--speedbar-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should-not (fboundp 'speedbar-close-frame)))

(ert-deftest emacsvox-speedbar-navigation-calls-original-once ()
  "Speedbar movement speaks after exactly one original call."
  (let ((ems--interactive-fn-name 'speedbar-next)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-speedbar-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        'result
        (emacsvox--advice-speedbar-next-around
         (lambda (arg)
           (setq calls (1+ calls))
           (push (list 'original arg emacsvox-speak-messages) events)
           'result)
         3))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original 3 nil) line (icon select-object))))))

(ert-deftest emacsvox-speedbar-programmatic-navigation-runs-once ()
  "Programmatic Speedbar movement is quiet and calls the original once."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-speedbar-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        'result
        (emacsvox--advice-speedbar-prev-around
         (lambda (arg)
           (setq calls (1+ calls))
           (should (= arg 2))
           'result)
         2))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-speedbar-up-directory-calls-original-once ()
  "Directory movement preserves one original call and feedback order."
  (let ((ems--interactive-fn-name 'speedbar-up-directory)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speedbar-speak-line)
               (lambda () (push 'line events))))
      (should
       (eq
        'result
        (emacsvox--advice-speedbar-up-directory-around
         (lambda ()
           (setq calls (1+ calls))
           (push 'original events)
           'result)))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '(original (icon large-movement) line)))))

(ert-deftest emacsvox-speedbar-close-uses-current-dframe-command ()
  "Current Dframe close feedback is limited to a Speedbar invocation."
  (let ((major-mode 'speedbar-mode)
        (ems--interactive-fn-name 'dframe-close-frame)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (should
       (eq
        'result
        (emacsvox--advice-dframe-close-frame-around
         (lambda ()
           (push 'original events)
           (setq major-mode 'fundamental-mode)
           'result)))))
    (should
     (equal
      (nreverse events)
      '(original (icon close-object) mode-line)))))

(ert-deftest emacsvox-speedbar-feedback-is-target-aware ()
  "Only feedback for the matching Speedbar command is emitted."
  (let ((ems--interactive-fn-name 'speedbar-contract-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-speedbar-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-speedbar-expand-line-after)
      (emacsvox--advice-speedbar-contract-line-after))
    (should
     (equal
      (nreverse events)
      '(line (icon close-object))))))

(ert-deftest emacsvox-speedbar-button-uses-native-arguments ()
  "Button voiceification uses the explicit START, END, and FACE arguments."
  (with-temp-buffer
    (insert "button")
    (let ((emacsvox-speedbar-file-personality 'file-voice))
      (emacsvox--advice-speedbar-make-button-after
       (point-min) (point-max) 'speedbar-file-face nil nil nil)
      (should
       (eq
        (get-text-property (point-min) 'personality)
        'file-voice)))))

(provide 'emacsvox-speedbar-tests)
;;; emacsvox-speedbar-tests.el ends here
