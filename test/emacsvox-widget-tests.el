;;; emacsvox-widget-tests.el --- Widget advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Widget advice.

;;; Code:

(require 'ert)
(require 'wid-edit)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-widget.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--widget-target-arglists
  '((widget-echo-help (pos))
    (widget-beginning-of-line (&optional n))
    (widget-end-of-line nil)
    (widget-forward (arg &optional suppress-echo))
    (widget-backward (arg &optional suppress-echo))
    (widget-kill-line nil)
    (widget-button-press (pos &optional event))
    (widget-convert-text
     (type from to &optional button-from button-to &rest args))
    (widget-setup nil))
  "Current Emacs 31 Widget targets and their native arguments.")

(defconst emacsvox-test--widget-motion-advice
  '((widget-echo-help
     :around emacsvox--advice-widget-echo-help-around)
    (widget-beginning-of-line
     :after emacsvox--advice-widget-beginning-of-line-after)
    (widget-end-of-line
     :after emacsvox--advice-widget-end-of-line-after)
    (widget-forward :after emacsvox--advice-widget-forward-after)
    (widget-backward :after emacsvox--advice-widget-backward-after)
    (widget-kill-line :after emacsvox--advice-widget-kill-line-after)
    (widget-setup :after emacsvox--advice-widget-setup-after))
  "Directly migrated Widget motion and setup advice.")

(ert-deftest emacsvox-widget-emacs31-target-contracts ()
  "Every advised Widget target exists with its Emacs 31 arguments."
  (dolist (entry emacsvox-test--widget-target-arglists)
    (pcase-let ((`(,target ,arguments) entry))
      (should (fboundp target))
      (should-not (or (get target 'obsolete)
                      (get target 'byte-obsolete-info)))
      (should (equal (help-function-arglist target t) arguments)))))

(ert-deftest emacsvox-widget-motion-advice-is-directly-registered ()
  "Widget motion and setup advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--widget-motion-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-widget-echo-help-calls-original-once ()
  "Help echo calls once, suppresses its message, and preserves its result."
  (let ((calls 0)
        observed)
    (should
     (eq
      'echo-result
      (emacsvox--advice-widget-echo-help-around
       (lambda (pos)
         (cl-incf calls)
         (setq observed (list pos inhibit-message))
         'echo-result)
       17)))
    (should (= calls 1))
    (should (equal observed '(17 t)))))

(ert-deftest emacsvox-widget-line-feedback-is-target-aware ()
  "Only matching interactive field movement announces its destination."
  (let ((ems--interactive-fn-name 'widget-end-of-line)
        events)
    (cl-letf (((symbol-function 'widget-at)
               (lambda (_pos) 'field-widget))
              ((symbol-function 'widget-value)
               (lambda (_widget) "field value"))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-widget-beginning-of-line-after)
      (emacsvox--advice-widget-end-of-line-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object)
        (message "Moved to end of text field field value"))))))

(ert-deftest emacsvox-widget-navigation-feedback-is-target-aware ()
  "Only matching interactive Widget navigation summarizes the new item."
  (let ((ems--interactive-fn-name 'widget-forward)
        events)
    (cl-letf (((symbol-function 'widget-at)
               (lambda (_pos) 'next-widget))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-widget-summarize)
               (lambda (widget) (push (list 'summary widget) events))))
      (emacsvox--advice-widget-backward-after)
      (emacsvox--advice-widget-forward-after))
    (should
     (equal
      (nreverse events)
      '((icon item) (summary next-widget))))))

(ert-deftest emacsvox-widget-setup-preserves-emacsvox-bindings ()
  "Widget setup restores Emacsvox bindings in both field keymaps."
  (let ((field-map (make-sparse-keymap))
        (text-map (make-sparse-keymap)))
    (cl-progv
        '(widget-field-keymap widget-text-keymap)
        (list field-map text-map)
      (emacsvox--advice-widget-setup-after))
    (dolist (map (list field-map text-map))
      (should (eq (lookup-key map emacsvox-prefix) 'emacsvox-keymap))
      (should
       (eq
        (lookup-key map (concat emacsvox-prefix emacsvox-prefix))
        'widget-end-of-line))
      (should
       (eq (lookup-key map "\350") 'emacsvox-widget-help))
      (should
       (eq
        (lookup-key map "\215")
        'emacsvox-widget-update-from-minibuffer)))))

(ert-deftest emacsvox-widget-button-advice-is-directly-registered ()
  "Widget button advice bypasses the compatibility bridge."
  (should
   (advice-member-p
    #'emacsvox--advice-widget-button-press-around
    'widget-button-press))
  (should-not
   (gethash
    '(widget-button-press
      :around
      emacsvox--advice-widget-button-press-around)
    ems--modern-advice-wrappers)))

(ert-deftest emacsvox-widget-button-press-calls-original-once ()
  "Ordinary button activation calls once, preserves args, and summarizes."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'widget-at)
               (lambda (pos)
                 (when (= pos 7) 'pressed-widget)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-widget-summarize)
               (lambda (widget) (push (list 'summary widget) events))))
      (should
       (eq
        'button-result
        (emacsvox--advice-widget-button-press-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'call arguments) events)
           'button-result)
         7 'mouse-event))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((call (7 mouse-event))
        (icon button)
        (summary pressed-widget))))))

(ert-deftest emacsvox-widget-button-movement-speaks-destination ()
  "Button movement cues a large move and falls back to the current line."
  (with-temp-buffer
    (insert "button destination")
    (goto-char (point-min))
    (let ((calls 0)
          events)
      (cl-letf (((symbol-function 'widget-at)
                 (lambda (pos)
                   (when (= pos 1) 'source-widget)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-widget-summarize)
                 (lambda (widget)
                   (push (list 'summary widget) events)
                   nil))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda (&rest _) (push 'line events))))
        (should
         (eq
          'moved
          (emacsvox--advice-widget-button-press-around
           (lambda (&rest _)
             (cl-incf calls)
             (goto-char 8)
             'moved)
           1))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon large-movement) (summary nil) line))))))

(ert-deftest emacsvox-widget-button-without-widget-runs-quietly-once ()
  "Activation without a widget calls the original once without feedback."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'widget-at)
               (lambda (_pos) nil))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        'plain-result
        (emacsvox--advice-widget-button-press-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'call arguments) events)
           'plain-result)
         4))))
    (should (= calls 1))
    (should (equal events '((call (4)))))))

(ert-deftest emacsvox-widget-button-eww-executor-replaces-original ()
  "EWW custom URL execution skips the original Widget action."
  (let ((major-mode 'eww-mode)
        (calls 0)
        events)
    (cl-progv
        '(emacsvox-we-url-executor)
        (list (lambda (&rest _)))
      (cl-letf (((symbol-function 'widget-at)
                 (lambda (_pos) 'link-widget))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'call-interactively)
                 (lambda (command)
                   (push (list 'execute command) events)
                   'executor-result)))
        (should-not
         (emacsvox--advice-widget-button-press-around
          (lambda (&rest _)
            (cl-incf calls)
            'original-result)
          5))))
    (should (= calls 0))
    (should
     (equal
      (nreverse events)
      '((icon button)
        (execute emacsvox-we-url-expand-and-execute))))))

(ert-deftest emacsvox-widget-convert-text-advice-is-directly-registered ()
  "Widget text conversion advice bypasses the compatibility bridge."
  (should
   (advice-member-p
    #'emacsvox--advice-widget-convert-text-around
    'widget-convert-text))
  (should-not
   (gethash
    '(widget-convert-text
      :around
      emacsvox--advice-widget-convert-text-around)
    ems--modern-advice-wrappers)))

(ert-deftest emacsvox-widget-convert-text-preserves-personality-and-result ()
  "Text conversion calls once, restores personality, and returns its widget."
  (with-temp-buffer
    (insert "abcdef")
    (put-text-property 2 5 'personality 'original-personality)
    (let ((calls 0)
          received)
      (should
       (eq
        'converted-widget
        (emacsvox--advice-widget-convert-text-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (setq received arguments)
           (put-text-property 2 5 'personality 'replacement-personality)
           'converted-widget)
         'item 2 5 2 4 :tag "Value")))
      (should (= calls 1))
      (should
       (equal received '(item 2 5 2 4 :tag "Value")))
      (should
       (eq
        (get-text-property 2 'personality)
        'original-personality)))))

(provide 'emacsvox-widget-tests)
;;; emacsvox-widget-tests.el ends here
