;;; emacsvox-formatting-tests.el --- Formatting advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated formatting advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--formatting-direct-advice
  '((center-line :after emacsvox--advice-center-line-after)
    (center-region :after emacsvox--advice-center-region-after)
    (center-paragraph :after
     emacsvox--advice-center-paragraph-after)
    (fill-paragraph :after emacsvox--advice-fill-paragraph-after)
    (lisp-fill-paragraph :after
     emacsvox--advice-lisp-fill-paragraph-after)
    (fill-region :after emacsvox--advice-fill-region-after)
    (cycle-spacing :after emacsvox--advice-cycle-spacing-after)
    (just-one-space :after emacsvox--advice-just-one-space-after))
  "Formatting commands using individually named native advice.")

(ert-deftest emacsvox-formatting-advice-is-directly-registered ()
  "Migrated formatting advice uses native advice directly."
  (dolist (entry emacsvox-test--formatting-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-center-line-feedback-is-target-aware ()
  "Only an interactive `center-line' invocation announces completion."
  (let ((ems--interactive-fn-name 'center-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-center-paragraph-after)
      (emacsvox--advice-center-line-after))
    (should
     (equal
      (nreverse events)
      '((icon center) (message "Centered current line"))))))

(ert-deftest emacsvox-center-region-uses-explicit-range ()
  "Region-centering feedback counts the range passed to the command."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'center-region)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (emacsvox--advice-center-region-after
         (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((icon center)
          (message "Centered current region containing 3 lines")))))))

(ert-deftest emacsvox-fill-paragraph-feedback-is-target-aware ()
  "Paragraph filling announces only the matching interactive command."
  (let ((ems--interactive-fn-name 'lisp-fill-paragraph)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-fill-paragraph-after)
      (emacsvox--advice-lisp-fill-paragraph-after))
    (should
     (equal
      (nreverse events)
      '((icon fill-object)
        (message "Filled current paragraph"))))))

(ert-deftest emacsvox-fill-region-uses-explicit-range ()
  "Region-filling feedback counts the range passed to the command."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'fill-region)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (emacsvox--advice-fill-region-after
         (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((icon fill-object)
          (message "Filled current region containing 3 lines")))))))

(ert-deftest emacsvox-spacing-feedback-is-target-aware ()
  "Only the matching spacing command speaks the line and then whitespace."
  (let ((ems--interactive-fn-name 'just-one-space)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-speak-spaces)
               (lambda () (push 'speak-spaces events))))
      (emacsvox--advice-cycle-spacing-after)
      (emacsvox--advice-just-one-space-after))
    (should
     (equal
      (nreverse events)
      '(speak-line speak-spaces)))))

(provide 'emacsvox-formatting-tests)
;;; emacsvox-formatting-tests.el ends here
