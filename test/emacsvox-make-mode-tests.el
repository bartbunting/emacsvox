;;; emacsvox-make-mode-tests.el --- Make Mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Make Mode advice.

;;; Code:

(require 'ert)
(require 'make-mode)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-make-mode.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--make-mode-advice
  '((makefile-next-dependency :after
                              emacsvox--advice-makefile-next-dependency-after)
    (makefile-browser-next-line :after
                                emacsvox--advice-makefile-browser-next-line-after)
    (makefile-browser-previous-line
     :after emacsvox--advice-makefile-browser-previous-line-after)
    (makefile-previous-dependency
     :after emacsvox--advice-makefile-previous-dependency-after)
    (makefile-backslash-region
     :after emacsvox--advice-makefile-backslash-region-after)
    (makefile-browser-quit
     :after emacsvox--advice-makefile-browser-quit-after)
    (makefile-switch-to-browser
     :after emacsvox--advice-makefile-switch-to-browser-after)
    (makefile-browser-toggle
     :around emacsvox--advice-makefile-browser-toggle-around)
    (makefile-browser-insert-selection
     :after emacsvox--advice-makefile-browser-insert-selection-after))
  "Current callable Emacs 31 Make Mode targets and their native advice.")

(ert-deftest emacsvox-make-mode-advice-is-directly-registered ()
  "Make Mode advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--make-mode-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers))))
  (should-not (fboundp 'makefile-complete))
  (should
   (eq
    (lookup-key makefile-mode-map (kbd "C-M-i"))
    'completion-at-point)))

(ert-deftest emacsvox-make-mode-navigation-is-target-aware ()
  "Only the matching Make Mode movement command produces feedback."
  (let ((ems--interactive-fn-name 'makefile-previous-dependency)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda ()
                 (push (list 'line emacsvox-show-point) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-makefile-next-dependency-after)
      (emacsvox--advice-makefile-previous-dependency-after))
    (should
     (equal
      (nreverse events)
      '((line t) (icon large-movement))))))

(ert-deftest emacsvox-make-mode-backslash-uses-native-region ()
  "Backslash feedback counts the explicit FROM and TO arguments."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'makefile-backslash-region)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-makefile-backslash-region-after
         (point-min) (point-max) nil))
      (should
       (equal
        (nreverse events)
        '("Backslashed region containing 3 lines"
          (icon select-object)))))))

(ert-deftest emacsvox-make-mode-browser-toggle-calls-original-once ()
  "Browser toggle reports state after one original call."
  (with-temp-buffer
    (insert "one\ntwo\n")
    (goto-char (point-max))
    (forward-line -1)
    (let ((ems--interactive-fn-name 'makefile-browser-toggle)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'makefile-browser-get-state-for-line)
                 (lambda (line)
                   (push (list 'state line) events)
                   t))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push 'line events))))
        (should
         (eq
          'result
          (emacsvox--advice-makefile-browser-toggle-around
           (lambda ()
             (setq calls (1+ calls))
             (push 'original events)
             'result)))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(original (state 1) (icon on) line))))))

(ert-deftest emacsvox-make-mode-programmatic-toggle-runs-once ()
  "Programmatic browser toggle is quiet and invokes the original once."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (should
       (eq
        'result
        (emacsvox--advice-makefile-browser-toggle-around
         (lambda ()
           (setq calls (1+ calls))
           'result)))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-make-mode-tests)
;;; emacsvox-make-mode-tests.el ends here
