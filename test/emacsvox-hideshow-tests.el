;;; emacsvox-hideshow-tests.el --- Hideshow advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Hideshow advice.

;;; Code:

(require 'ert)
(require 'hideshow)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-hideshow.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--hideshow-after-targets
  '(hs-hide-all
    hs-show-all
    hs-hide-block
    hs-show-block
    hs-hide-level
    hs-toggle-hiding
    hs-hide-initial-comment-block)
  "Current Emacs 31 Hideshow targets using direct after advice.")

(ert-deftest emacsvox-hideshow-advice-is-directly-registered ()
  "Hideshow advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--hideshow-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should-not (fboundp 'hs-show-region)))

(ert-deftest emacsvox-hideshow-block-feedback-is-target-aware ()
  "Only the matching block command announces its result."
  (let ((ems--interactive-fn-name 'hs-show-block)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-hs-hide-block-after)
      (emacsvox--advice-hs-show-block-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) "Exposed current  block.")))))

(ert-deftest emacsvox-hideshow-toggle-reports-hidden-state ()
  "Toggling a block reports its resulting hidden state."
  (let ((ems--interactive-fn-name 'hs-toggle-hiding)
        events)
    (cl-letf (((symbol-function 'hs-already-hidden-p) (lambda () t))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-hs-toggle-hiding-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) "Hid block")))))

(ert-deftest emacsvox-hideshow-level-feedback-is-target-aware ()
  "Only the matching structural hiding command produces feedback."
  (let ((ems--interactive-fn-name 'hs-hide-initial-comment-block)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-hs-hide-level-after)
      (emacsvox--advice-hs-hide-initial-comment-block-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) "Hid initial comment block.")))))

(provide 'emacsvox-hideshow-tests)
;;; emacsvox-hideshow-tests.el ends here
