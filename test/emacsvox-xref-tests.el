;;; emacsvox-xref-tests.el --- Xref advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Xref advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-xref.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--xref-after-advice
  '((xref-find-definitions emacsvox--advice-xref-find-definitions-after)
    (xref-pop-marker-stack emacsvox--advice-xref-pop-marker-stack-after)
    (pop-tag-mark emacsvox--advice-pop-tag-mark-after)
    (xref-next-line emacsvox--advice-xref-next-line-after)
    (xref-prev-line emacsvox--advice-xref-prev-line-after)
    (xref-go-back emacsvox--advice-xref-go-back-after)
    (xref-find-apropos emacsvox--advice-xref-find-apropos-after)
    (xref-goto-xref emacsvox--advice-xref-goto-xref-after)
    (xref-find-definitions-other-frame
     emacsvox--advice-xref-find-definitions-other-frame-after)
    (xref-find-definitions-other-window
     emacsvox--advice-xref-find-definitions-other-window-after)
    (xref-show-location-at-point
     emacsvox--advice-xref-show-location-at-point-after)
    (xref-find-references emacsvox--advice-xref-find-references-after))
  "Native after-advice registrations in the Xref integration.")

(ert-deftest emacsvox-xref-advice-is-directly-registered ()
  "Xref advice uses current targets and bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--xref-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-xref-movement-feedback-is-target-aware ()
  "Only the matching Xref movement speaks and cues in upstream order."
  (let ((ems--interactive-fn-name 'xref-prev-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-xref-next-line-after)
      (emacsvox--advice-xref-prev-line-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon large-movement))))))

(ert-deftest emacsvox-xref-alias-feedback-is-not-duplicated ()
  "Only the invoked Xref alias consumes its interactive target."
  (let ((ems--interactive-fn-name 'pop-tag-mark)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-xref-go-back-after)
      (emacsvox--advice-pop-tag-mark-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon large-movement))))))

(ert-deftest emacsvox-xref-display-feedback-preserves-order ()
  "Displaying an Xref announces the result before its selection cue."
  (let ((ems--interactive-fn-name 'xref-show-location-at-point)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (&rest _) (push 'message events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-xref-show-location-at-point-after))
    (should
     (equal
      (nreverse events)
      '(message (icon select-object))))))

(provide 'emacsvox-xref-tests)
;;; emacsvox-xref-tests.el ends here
