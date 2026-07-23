;;; emacsvox-completion-tests.el --- Completion advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and native-registration coverage for migrated completion advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'dabbrev)
(require 'emacsvox-advice)

(defconst emacsvox-test--completion-after-targets
  '(minibuffer-complete-history
    next-history-element previous-history-element
    next-line-or-history-element previous-line-or-history-element
    previous-matching-history-element next-matching-history-element
    minibuffer-next-completion minibuffer-previous-completion
    minibuffer-next-line-completion minibuffer-previous-line-completion
    dabbrev-expand dabbrev-completion
    next-line-completion previous-line-completion
    next-completion previous-completion)
  "Completion navigation commands using generated native after advice.")

(defconst emacsvox-test--completion-around-targets
  '(hippie-expand complete
    minibuffer-complete-word minibuffer-complete
    crm-complete-word crm-complete crm-complete-and-exit
    crm-minibuffer-complete crm-minibuffer-complete-and-exit
    lisp-complete-symbol complete-symbol widget-complete)
  "Completion commands using generated native around advice.")

(defconst emacsvox-test--completion-direct-advice
  '((pcomplete-list :after emacsvox--advice-pcomplete-list-after)
    (pcomplete-show-completions :around
     emacsvox--advice-pcomplete-show-completions-around)
    (pcomplete :around emacsvox--advice-pcomplete-around)
    (completion-at-point :around
     emacsvox--advice-completion-at-point-around)
    (minibuffer-choose-completion :around
     emacsvox--advice-minibuffer-choose-completion-around)
    (minibuffer-choose-completion-or-exit :after
     emacsvox--advice-minibuffer-choose-completion-or-exit-after)
    (switch-to-completions :after
     emacsvox--advice-switch-to-completions-after)
    (choose-completion :before emacsvox--advice-choose-completion-before)
    (tmm-goto-completions :after
     emacsvox--advice-tmm-goto-completions-after)
    (tmm-menubar :before emacsvox--advice-tmm-menubar-before)
    (tmm-shortcut :after emacsvox--advice-tmm-shortcut-after))
  "Completion commands migrated to directly registered native advice.")

(ert-deftest emacsvox-completion-advice-is-directly-registered ()
  "Migrated completion advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--completion-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-test--completion-around-targets)
    (let ((function (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :around function) ems--modern-advice-wrappers))))
  (dolist (entry emacsvox-test--completion-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-completion-at-point-calls-original-once ()
  "Interactive completion calls once, preserves its result, then speaks."
  (with-temp-buffer
    (insert "prefix foo")
    (let ((ems--interactive-fn-name 'completion-at-point)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          (emacsvox--advice-completion-at-point-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (list 'original arguments) events)
             (insert "bar")
             'completion-result)
           'argument)
          'completion-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original (argument))
          (speak "foobar")
          (icon complete)))))))

(ert-deftest emacsvox-pcomplete-preserves-region-feedback ()
  "Interactive PComplete speaks the completed region after one call."
  (with-temp-buffer
    (insert "prefix foo")
    (let ((ems--interactive-fn-name 'pcomplete)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push
                    (list 'speak-region start end
                          (buffer-substring start end))
                    events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          (emacsvox--advice-pcomplete-around
           (lambda (&rest _)
             (cl-incf calls)
             (push 'original events)
             (insert "bar")
             'pcomplete-result))
          'pcomplete-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(original
          (speak-region 8 14 "foobar")
          (icon complete)))))))

(ert-deftest emacsvox-completion-advice-is-quiet-programmatically ()
  "Programmatic completion calls once without speech feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-minibuffer-choose-completion-around
         (lambda (&rest _)
           (cl-incf calls)
           'completion-result))
        'completion-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-pcomplete-list-preserves-icon-order ()
  "Interactive completion listings emit help then completion icons."
  (let ((ems--interactive-fn-name 'pcomplete-list)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-pcomplete-list-after))
    (should (equal (nreverse events) '(help complete)))))

(ert-deftest emacsvox-minibuffer-history-advice-preserves-feedback ()
  "History navigation emits its selection icon and inserted contents."
  (let ((ems--interactive-fn-name 'next-history-element)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'minibuffer-contents)
               (lambda () "history entry"))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-next-history-element-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (speak "history entry"))))))

(ert-deftest emacsvox-completion-navigation-speaks-selection ()
  "Completion-list navigation speaks the newly selected completion."
  (let ((ems--interactive-fn-name 'next-completion)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-get-current-completion)
               (lambda () "selected item"))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-next-completion-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (speak "selected item"))))))

(ert-deftest emacsvox-switch-to-completions-preserves-unconditional-feedback ()
  "Switching to completions announces the selection for every call."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-get-current-completion)
               (lambda () "first completion"))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-switch-to-completions-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (speak "first completion"))))))

(ert-deftest emacsvox-hippie-expand-advice-calls-original-once ()
  "Interactive expansion calls once, preserves its result, then speaks."
  (with-temp-buffer
    (insert "foo")
    (let ((ems--interactive-fn-name 'hippie-expand)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-hippie-expand-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (list 'original arguments) events)
             (insert "bar")
             'hippie-result)
           'argument)
          'hippie-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original (argument))
          (icon complete)
          (speak "foobar")))))))

(ert-deftest emacsvox-hippie-expand-advice-is-quiet-programmatically ()
  "Programmatic expansion calls once without completion feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'dtk-speak)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-hippie-expand-around
         (lambda (&rest _)
           (cl-incf calls)
           'hippie-result))
        'hippie-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-minibuffer-completion-speaks-inserted-text ()
  "Interactive minibuffer completion speaks inserted text after one call."
  (with-temp-buffer
    (insert "foo")
    (let ((ems--interactive-fn-name 'minibuffer-complete)
          (dtk-punctuation-mode 'all)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-kill-buffer-carefully)
                 (lambda (buffer)
                   (push (list 'kill-buffer buffer) events)))
                ((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-minibuffer-complete-around
           (lambda (&rest _)
             (cl-incf calls)
             (push 'original events)
             (insert "bar")
             'minibuffer-result))
          'minibuffer-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((kill-buffer "*Completions*")
          original
          (speak "bar")))))))

(ert-deftest emacsvox-minibuffer-completion-preserves-fallback-feedback ()
  "Completion without inserted text speaks the available completions."
  (with-temp-buffer
    (insert "foo")
    (let ((ems--interactive-fn-name 'minibuffer-complete)
          events)
      (cl-letf (((symbol-function 'emacsvox-kill-buffer-carefully)
                 #'ignore)
                ((symbol-function 'emacsvox-speak-completions-if-available)
                 (lambda () (push 'speak-completions events))))
        (emacsvox--advice-minibuffer-complete-around
         (lambda (&rest _) 'minibuffer-result)))
      (should (equal events '(speak-completions))))))

(ert-deftest emacsvox-symbol-completion-preserves-unconditional-feedback ()
  "Symbol completion speaks inserted text even when called programmatically."
  (with-temp-buffer
    (insert "foo")
    (let ((ems--interactive-fn-name nil)
          (dtk-punctuation-mode 'all)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-complete-symbol-around
           (lambda (&rest _)
             (cl-incf calls)
             (push 'original events)
             (insert "bar")
             'symbol-result))
          'symbol-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(original (speak "foobar")))))))

(ert-deftest emacsvox-dabbrev-advice-preserves-feedback-order ()
  "Interactive dabbrev feedback waits for output before speaking expansion."
  (let ((ems--interactive-fn-name 'dabbrev-expand)
        (dabbrev--last-expansion "expanded")
        (dtk-punctuation-mode 'all)
        events)
    (cl-letf (((symbol-function 'accept-process-output)
               (lambda (&rest _) (push 'accept-output events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-dabbrev-expand-after))
    (should
     (equal
      (nreverse events)
      '(accept-output (speak "expanded"))))))

(provide 'emacsvox-completion-tests)
;;; emacsvox-completion-tests.el ends here
