;;; emacsvox-corfu-tests.el --- Corfu advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'corfu)
(load (expand-file-name "../lisp/emacsvox-corfu.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-corfu-advice-is-current-and-direct ()
  "Current Corfu targets use native advice directly."
  (dolist (entry emacsvox-corfu--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-corfu-navigation-is-target-aware ()
  "Only the matching interactive Corfu navigation command speaks."
  (let ((ems--interactive-fn-name 'corfu-next)
        (calls 0))
    (cl-letf (((symbol-function 'emacsvox-corfu--speak-candidate)
               (lambda () (cl-incf calls))))
      (emacsvox--advice-corfu-previous-after)
      (emacsvox--advice-corfu-next-after))
    (should (= calls 1))))

(ert-deftest emacsvox-corfu-separator-policy-uses-named-tone ()
  "Separator insertion resolves its short confirmation tone by intent."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:events (completion-separator-inserted))
             '(:module corfu :mode text-mode :occasion edit)))
           (action (car (emacsvox-aural-render-plan-before plan))))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(corfu-separator-inserted-tone)))
      (should (eq (emacsvox-aural-action-kind action) 'tone))
      (should
       (eq
        (emacsvox-aural-action-tone action)
        'completion-separator)))))

(ert-deftest emacsvox-corfu-separator-preserves-cue-then-tone-order ()
  "Interactive separator insertion retains its cue before semantic tone."
  (let ((ems--interactive-fn-name 'corfu-insert-separator)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-icon)
          (lambda (icon) (push (list 'icon icon) events)))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push (cons 'submit-actions arguments) events))))
      (emacsvox--advice-corfu-insert-separator-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object)
        (submit-actions
         :facts (:events (completion-separator-inserted))
         :module corfu
         :occasion edit))))))

(ert-deftest emacsvox-corfu-separator-is-quiet-programmatically ()
  "Programmatic separator insertion produces no feedback."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-icon)
          (lambda (&rest _) (push 'icon events)))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest _) (push 'submit-actions events))))
      (emacsvox--advice-corfu-insert-separator-after))
    (should-not events)))

(provide 'emacsvox-corfu-tests)
;;; emacsvox-corfu-tests.el ends here
