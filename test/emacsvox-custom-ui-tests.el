;;; emacsvox-custom-ui-tests.el --- Customize UI advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Customize UI advice.

;;; Code:

(require 'ert)
(require 'cus-edit)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-custom.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--custom-ui-after-targets
  '(Custom-reset-current
    Custom-reset-saved
    Custom-reset-standard
    Custom-set
    Custom-buffer-done
    customize-save-customized
    custom-save-all
    customize-group
    customize-browse
    customize-option
    customize-variable
    customize-apropos
    Custom-goto-parent
    Custom-newline)
  "Current Emacs 31 Customize UI targets using direct after advice.")

(ert-deftest emacsvox-custom-ui-advice-is-directly-registered ()
  "Customize UI advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--custom-ui-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox-custom--advice-customize-after
    'customize))
  (should-not
   (advice-member-p
    #'emacsvox--advice-customize-after
    'customize))
  (dolist
      (entry
       '((Custom-save emacsvox--advice-Custom-save-around)
         (customize-save-customized
          emacsvox--advice-customize-save-customized-around)))
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-custom-ui-removed-custom-set-remains-absent ()
  "Customize support does not recreate the removed `custom-set' command."
  (should-not (fboundp 'custom-set))
  (should-not (fboundp 'emacsvox--advice-custom-set-after)))

(ert-deftest emacsvox-custom-ui-customize-replaces-generic-feedback ()
  "The feature-specific Customize feedback supersedes the core version."
  (let ((ems--interactive-fn-name 'customize)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-custom-goto-group)
               (lambda () (push 'group events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox-custom--advice-customize-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) group line)))))

(ert-deftest emacsvox-custom-ui-save-calls-original-once ()
  "A Customize buffer save preserves its result and reports afterward."
  (let ((ems--interactive-fn-name 'Custom-save)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speech text) events))))
      (should
       (eq
        'saved
        (emacsvox--advice-Custom-save-around
         (lambda (&rest arguments)
           (setq calls (1+ calls))
           (should (equal arguments '(button)))
           (push 'original events)
           'saved)
         'button))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '(original (icon save-object) (speech "Set and saved"))))))

(ert-deftest emacsvox-custom-ui-session-save-is-silenced-once ()
  "Saving session customizations runs once with speech silenced."
  (let ((dtk-quiet nil)
        (calls 0)
        observed)
    (should
     (eq
      'saved
      (emacsvox--advice-customize-save-customized-around
       (lambda (&rest arguments)
         (setq calls (1+ calls)
               observed (list arguments dtk-quiet))
         'saved)
       'argument)))
    (should (= calls 1))
    (should (equal observed '((argument) t)))
    (should-not dtk-quiet)))

(ert-deftest emacsvox-custom-ui-option-uses-native-symbol-argument ()
  "Option feedback searches for the option passed by Emacs."
  (with-temp-buffer
    (insert "prefix\nNeedle setting\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'customize-option)
          events)
      (cl-letf (((symbol-function 'custom-unlispify-tag-name)
                 (lambda (symbol)
                   (push (list 'symbol symbol) events)
                   "Needle"))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push 'line events))))
        (emacsvox--advice-customize-variable-after 'wrong-option)
        (emacsvox--advice-customize-option-after 'right-option))
      (should
       (equal
        (nreverse events)
        '((icon open-object) (symbol right-option) line)))
      (should (= (line-number-at-pos) 2)))))

(provide 'emacsvox-custom-ui-tests)
;;; emacsvox-custom-ui-tests.el ends here
