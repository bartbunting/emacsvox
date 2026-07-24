;;; emacsvox-nxml-tests.el --- NXML advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated NXML advice.

;;; Code:

(require 'ert)
(require 'nxml-mode)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-nxml.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--nxml-after-targets
  '(nxml-insert-xml-declaration
    nxml-backward-up-element
    nxml-forward-balanced-item
    nxml-up-element
    nxml-forward-paragraph
    nxml-backward-paragraph
    nxml-forward-element
    nxml-backward-element
    nxml-balanced-close-start-tag-block
    nxml-finish-element
    nxml-balanced-close-start-tag-inline
    nxml-hide-all-text-content
    nxml-hide-direct-text-content
    nxml-hide-other
    nxml-hide-subheadings
    nxml-hide-text-content
    nxml-show
    nxml-show-all
    nxml-show-direct-subheadings
    nxml-show-direct-text-content
    nxml-show-subheadings)
  "Current Emacs 31 NXML targets using direct after advice.")

(ert-deftest emacsvox-nxml-advice-is-directly-registered ()
  "NXML advice is attached directly to current Emacs 31 commands."
  (dolist (target emacsvox-test--nxml-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist
      (entry
       '((nxml-electric-slash
          emacsvox--advice-nxml-electric-slash-around)
         (nxml-complete emacsvox--advice-nxml-complete-around)))
    (pcase-let ((`(,target ,function) entry))
      (should (commandp target))
      (should (advice-member-p function target))))
  (should-not (commandp 'nxml-backward-single-paragraph))
  (should-not (commandp 'nxml-backward-single-balanced-item)))

(ert-deftest emacsvox-nxml-electric-slash-calls-original-once ()
  "Electric slash speaks text inserted by exactly one original call."
  (with-temp-buffer
    (insert "<tag")
    (let ((ems--interactive-fn-name 'nxml-electric-slash)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push
                    (list 'region start end
                          (buffer-substring start end))
                    events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          'result
          (emacsvox--advice-nxml-electric-slash-around
           (lambda (arg)
             (setq calls (1+ calls))
             (should (= arg 1))
             (insert "/>")
             'result)
           1))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((region 5 7 "/>") (icon close-object)))))))

(ert-deftest emacsvox-nxml-completion-calls-original-once ()
  "Interactive NXML completion speaks the text from one original call."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'nxml-complete)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (buffer-substring start end) events))))
        (should
         (eq
          'result
          (emacsvox--advice-nxml-complete-around
           (lambda ()
             (setq calls (1+ calls))
             (insert "element")
             'result)))))
      (should (= calls 1))
      (should (equal events '("element"))))))

(ert-deftest emacsvox-nxml-programmatic-completion-runs-once-quietly ()
  "Programmatic NXML completion invokes the original once without feedback."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-region)
               (lambda (&rest arguments) (push arguments events))))
      (should
       (eq
        'result
        (emacsvox--advice-nxml-complete-around
         (lambda ()
           (setq calls (1+ calls))
           'result)))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-nxml-navigation-feedback-is-target-aware ()
  "Only feedback for the matching NXML movement command is emitted."
  (let ((ems--interactive-fn-name 'nxml-forward-element)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-nxml-backward-element-after)
      (emacsvox--advice-nxml-forward-element-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-nxml-close-feedback-names-element ()
  "Closing an NXML element announces its qualified name."
  (let ((ems--interactive-fn-name 'nxml-finish-element)
        events)
    (cl-letf (((symbol-function 'xmltok-start-tag-qname)
               (lambda () "section"))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-nxml-finish-element-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) (speak "Closed section"))))))

(ert-deftest emacsvox-nxml-outline-feedback-is-target-aware ()
  "Hide and show commands retain distinct target-aware feedback."
  (let ((ems--interactive-fn-name 'nxml-show-all)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-nxml-hide-all-text-content-after)
      (emacsvox--advice-nxml-show-all-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) line)))))

(provide 'emacsvox-nxml-tests)
;;; emacsvox-nxml-tests.el ends here
