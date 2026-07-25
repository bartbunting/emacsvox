;;; emacsvox-make-mode-tests.el --- Make Mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Make Mode advice.

;;; Code:

(require 'ert)
(require 'imenu)
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
    (makefile-previous-dependency
     :after emacsvox--advice-makefile-previous-dependency-after)
    (makefile-backslash-region
     :after emacsvox--advice-makefile-backslash-region-after))
  "Current callable Emacs 31 Make Mode targets and their native advice.")

(ert-deftest emacsvox-make-mode-advice-is-directly-registered ()
  "Make Mode advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--make-mode-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should-not (fboundp 'makefile-complete))
  (should
   (eq
    (lookup-key makefile-mode-map (kbd "C-M-i"))
    'completion-at-point))
  (should
   (eq
    (lookup-key makefile-mode-map (kbd "C-c C-b"))
    'imenu)))

(ert-deftest emacsvox-make-mode-omits-obsolete-browser-advice ()
  "Make Mode leaves the retired target browser unadvised."
  (dolist
      (entry
       '((makefile-browser-next-line
          . emacsvox--advice-makefile-browser-next-line-after)
         (makefile-browser-previous-line
          . emacsvox--advice-makefile-browser-previous-line-after)
         (makefile-browser-quit
          . emacsvox--advice-makefile-browser-quit-after)
         (makefile-switch-to-browser
          . emacsvox--advice-makefile-switch-to-browser-after)
         (makefile-browser-toggle
          . emacsvox--advice-makefile-browser-toggle-around)
         (makefile-browser-insert-selection
          . emacsvox--advice-makefile-browser-insert-selection-after)))
    (should-not (fboundp (cdr entry)))
    (should-not (advice-member-p (cdr entry) (car entry)))))

(ert-deftest emacsvox-make-mode-imenu-indexes-targets ()
  "The supported Imenu replacement exposes Makefile targets."
  (with-temp-buffer
    (insert "all: build\n\t@echo ok\nbuild:\n\t@true\n")
    (makefile-gmake-mode)
    (let ((dependencies
           (assoc "Dependencies" (imenu--make-index-alist t))))
      (should (assoc "all" (cdr dependencies)))
      (should (assoc "build" (cdr dependencies))))))

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

(provide 'emacsvox-make-mode-tests)
;;; emacsvox-make-mode-tests.el ends here
