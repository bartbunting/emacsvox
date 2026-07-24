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
     emacsvox--advice-describe-keymap-filter-return)
    (apropos-follow :after
     emacsvox--advice-apropos-follow-after)
    (help-with-tutorial :after
     emacsvox--advice-help-with-tutorial-after)
    (view-emacs-news :after
     emacsvox--advice-view-emacs-news-after)
    (view-echo-area-messages :after
     emacsvox--advice-view-echo-area-messages-after)
    (help-form-show :after
     emacsvox--advice-help-form-show-after))
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

(defconst emacsvox-test--apropos-targets
  '(apropos apropos-char apropos-library
    apropos-unicode apropos-user-option apropos-value apropos-variable
    apropos-command apropos-documentation)
  "Apropos commands using generated native after advice.")

(ert-deftest emacsvox-help-advice-is-directly-registered ()
  "Migrated Help advice uses native advice directly."
  (dolist (entry emacsvox-test--help-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--help-description-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--apropos-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

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

(ert-deftest emacsvox-apropos-feedback-is-target-aware ()
  "Only the matching Apropos command cues and announces its result window."
  (let ((ems--interactive-fn-name 'apropos-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-apropos-variable-after "wrong")
      (emacsvox--advice-apropos-command-after "right"))
    (should
     (equal
      (nreverse events)
      '((icon help)
        (message "Displayed apropos in other window."))))))

(ert-deftest emacsvox-apropos-follow-feedback-preserves-order ()
  "Following an Apropos result cues selection before speaking Help."
  (let ((ems--interactive-fn-name 'apropos-follow)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-help)
               (lambda () (push 'speak-help events))))
      (emacsvox--advice-apropos-follow-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-help)))))

(ert-deftest emacsvox-tutorial-feedback-is-target-aware ()
  "Interactive tutorial display configures and speaks its window in order."
  (let ((ems--interactive-fn-name 'help-with-tutorial)
        events)
    (cl-letf (((symbol-function 'tts-set-punctuations)
               (lambda (mode) (push (list 'punctuations mode) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-predefined-window)
               (lambda (window) (push (list 'speak-window window) events))))
      (emacsvox--advice-view-emacs-news-after)
      (emacsvox--advice-help-with-tutorial-after))
    (should
     (equal
      (nreverse events)
      '((punctuations all)
        (icon open-object)
        (speak-window 1))))))

(ert-deftest emacsvox-news-feedback-is-target-aware ()
  "Interactive Emacs news display cues before speaking its mode line."
  (let ((ems--interactive-fn-name 'view-emacs-news)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-view-emacs-news-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-echo-area-feedback-is-target-aware ()
  "Interactive echo-area viewing cues and reports its Messages window."
  (let ((ems--interactive-fn-name 'view-echo-area-messages)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-view-echo-area-messages-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (message "Displayed messages in other window."))))))

(ert-deftest emacsvox-help-form-speaks-private-buffer-from-start ()
  "The internal help callback speaks its live private buffer from point-min."
  (let ((help-buffer (get-buffer-create emacsvox--help-char-helpbuf))
        observations)
    (unwind-protect
        (progn
          (with-current-buffer help-buffer
            (erase-buffer)
            (insert "Character help")
            (goto-char (point-max)))
          (cl-letf (((symbol-function 'emacsvox-speak-buffer)
                     (lambda ()
                       (push
                        (list (current-buffer) (point))
                        observations))))
            (emacsvox--advice-help-form-show-after))
          (should
           (equal observations (list (list help-buffer 1)))))
      (kill-buffer help-buffer))))

(provide 'emacsvox-help-tests)
;;; emacsvox-help-tests.el ends here
