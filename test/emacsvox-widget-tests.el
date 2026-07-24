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

(provide 'emacsvox-widget-tests)
;;; emacsvox-widget-tests.el ends here
