;;; emacsvox-help-tests.el --- Help advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Help advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--help-direct-advice
  '((describe-mode :after emacsvox--advice-describe-mode-after)
    (describe-repeat-maps :after
     emacsvox--advice-describe-repeat-maps-after)
    (describe-bindings :after
     emacsvox--advice-describe-bindings-after)
    (describe-prefix-bindings :after
     emacsvox--advice-describe-prefix-bindings-after)
    (isearch-describe-bindings :after
     emacsvox--advice-isearch-describe-bindings-after)
    (help-do-xref :after emacsvox--advice-help-do-xref-after)
    (help-xref-go-back :after
     emacsvox--advice-help-xref-go-back-after)
    (help-xref-go-forward :after
     emacsvox--advice-help-xref-go-forward-after)
    (help-view-source :after
     emacsvox--advice-help-view-source-after)
    (help-customize :after
     emacsvox--advice-help-customize-after)
    (help-window-display-message :around
     emacsvox--advice-help-window-display-message-around)
    (describe-key :filter-return
     emacsvox--advice-describe-key-filter-return)
    (describe-keymap :filter-return
     emacsvox--advice-describe-keymap-filter-return))
  "Help commands using individually named native advice.")

(defconst emacsvox-test--help-description-targets
  '(describe-function describe-variable describe-symbol
    describe-face describe-font
    describe-text-properties describe-syntax
    describe-package
    describe-char describe-char-after describe-character-set
    describe-chars-in-region
    describe-coding-system describe-current-coding-system
    describe-current-coding-system-briefly
    describe-current-display-table describe-fontset
    describe-help-keys describe-input-method
    describe-language-environment
    describe-minor-mode describe-minor-mode-from-indicator
    describe-minor-mode-from-symbol
    describe-personal-keybindings describe-theme)
  "Description commands using generated native after advice.")

(ert-deftest emacsvox-help-advice-is-directly-registered ()
  "Migrated Help advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--help-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-test--help-description-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-describe-mode-feedback-preserves-order ()
  "Interactive mode help announces its message before the Help icon."
  (let ((ems--interactive-fn-name 'describe-mode)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-describe-repeat-maps-after)
      (emacsvox--advice-describe-mode-after))
    (should
     (equal
      (nreverse events)
      '((message "Displayed mode help") (icon help))))))

(ert-deftest emacsvox-describe-bindings-feedback-is-target-aware ()
  "Only the matching binding-description command announces its Help window."
  (let ((ems--interactive-fn-name 'describe-prefix-bindings)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-describe-bindings-after)
      (emacsvox--advice-describe-prefix-bindings-after))
    (should
     (equal
      (nreverse events)
      '((message "Displayed key bindings in help window")
        (icon help))))))

(ert-deftest emacsvox-help-xref-feedback-remains-unconditional ()
  "Help xref callbacks speak even without an interactive command marker."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-help-do-xref-after)
      (emacsvox--advice-help-xref-go-back-after)
      (emacsvox--advice-help-xref-go-forward-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon item) speak-line speak-line)))))

(ert-deftest emacsvox-help-source-feedback-is-target-aware ()
  "Only interactive source viewing speaks its line before the open icon."
  (let ((ems--interactive-fn-name 'help-view-source)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-help-customize-after)
      (emacsvox--advice-help-view-source-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon open-object))))))

(ert-deftest emacsvox-help-window-message-advice-calls-original-once ()
  "Help window messaging calls once, quietly, and preserves its result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        observed-state)
    (should
     (eq
      (emacsvox--advice-help-window-display-message-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (setq observed-state
               (list arguments emacsvox-speak-messages inhibit-message))
         'help-message-result)
       'argument)
      'help-message-result))
    (should (= calls 1))
    (should (equal observed-state '((argument) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-describe-key-speaks-help-for-nil-result ()
  "Interactive key description speaks Help when its original result is nil."
  (let ((ems--interactive-fn-name 'describe-key)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-help)
               (lambda () (push 'speak-help events))))
      (should-not
       (emacsvox--advice-describe-key-filter-return nil)))
    (should
     (equal
      (nreverse events)
      '((icon help) speak-help)))))

(ert-deftest emacsvox-describe-keymap-preserves-non-nil-result ()
  "Interactive keymap description returns a non-nil result without speech."
  (let ((ems--interactive-fn-name 'describe-keymap)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-help)
               (lambda () (push 'speak-help events))))
      (should
       (eq
        (emacsvox--advice-describe-key-filter-return 'wrong-result)
        'wrong-result))
      (should
       (eq
        (emacsvox--advice-describe-keymap-filter-return 'keymap-result)
        'keymap-result)))
    (should (equal events '((icon help))))))

(ert-deftest emacsvox-description-feedback-is-target-aware ()
  "Only the matching description command cues and speaks its Help buffer."
  (let ((ems--interactive-fn-name 'describe-language-environment)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-help)
               (lambda () (push 'speak-help events))))
      (emacsvox--advice-describe-function-after)
      (emacsvox--advice-describe-language-environment-after))
    (should
     (equal
      (nreverse events)
      '((icon help) speak-help)))))

(provide 'emacsvox-help-tests)
;;; emacsvox-help-tests.el ends here
