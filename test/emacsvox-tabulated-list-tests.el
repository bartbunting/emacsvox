;;; emacsvox-tabulated-list-tests.el --- Tabulated List advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tabulated List advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tabulated-list.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tabulated-list-after-advice
  '((tabulated-list-next-column
     emacsvox--advice-tabulated-list-next-column-after)
    (tabulated-list-previous-column
     emacsvox--advice-tabulated-list-previous-column-after))
  "Native after-advice registrations in the Tabulated List integration.")

(ert-deftest emacsvox-tabulated-list-advice-is-directly-registered ()
  "Tabulated List advice uses native advice directly."
  (dolist (entry emacsvox-test--tabulated-list-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-tabulated-list-empty-field-policy-uses-named-tone ()
  "Empty fields resolve the compatibility tone through aural policy."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:role field :states (empty))
             '(:module tabulated-list
               :mode tabulated-list-mode
               :occasion navigation)))
           (action (car (emacsvox-aural-render-plan-before plan))))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(tabulated-list-empty-field-tone)))
      (should (eq (emacsvox-aural-action-kind action) 'tone))
      (should (eq (emacsvox-aural-action-tone action) 'field-empty)))))

(ert-deftest emacsvox-tabulated-list-empty-cell-preserves-edge-order ()
  "Edge cues share the action-only presentation for an empty cell."
  (with-temp-buffer
    (insert "xy")
    (goto-char 2)
    (let ((tabulated-list-format '(("Only" 10 t)))
          events)
      (cl-letf
          (((symbol-function 'get-text-property)
            (lambda (&rest _) "Only"))
           ((symbol-function 'tabulated-list-get-entry)
            (lambda () [""]))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "An empty programmatic cell submitted text")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (push (cons 'submit-actions arguments) events))))
        (emacsvox-tabulated-list-speak-cell))
      (pcase-let* ((`((submit-actions . ,arguments)) events)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role field :states (empty))))
        (should (eq (plist-get arguments :module) 'tabulated-list))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(left right)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-phase actions)
          '(before before)))))))

(ert-deftest emacsvox-tabulated-list-nonempty-cell-submits-content ()
  "A nonempty cell is submitted once with field semantics."
  (with-temp-buffer
    (insert "xy")
    (goto-char 2)
    (let ((tabulated-list-format
           '(("Left" 10 t) ("Middle" 10 t) ("Right" 10 t)))
          submitted)
      (cl-letf
          (((symbol-function 'get-text-property)
            (lambda (&rest _) "Middle"))
           ((symbol-function 'tabulated-list-get-entry)
            (lambda () ["left" "value" "right"]))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submitted (cons content arguments))))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _)
              (ert-fail "A nonempty cell submitted actions only"))))
        (emacsvox-tabulated-list-speak-cell))
      (should (equal (car submitted) "value"))
      (should
       (equal (plist-get (cdr submitted) :facts) '(:role field)))
      (should (eq (plist-get (cdr submitted) :module) 'tabulated-list))
      (should
       (eq (plist-get (cdr submitted) :occasion) 'navigation)))))

(ert-deftest emacsvox-tabulated-list-preserves-owning-module ()
  "Embedded tables submit under their integration's semantic module."
  (with-temp-buffer
    (setq-local emacsvox-aural-module 'magit)
    (let (arguments)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (_content &rest rest) (setq arguments rest))))
        (emacsvox-tabulated-list--submit-cell
         "repo" '(:role field) 'select-object))
      (should (eq (plist-get arguments :module) 'magit))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get arguments :compatibility-actions))
        '(select-object))))))

(ert-deftest emacsvox-tabulated-list-feedback-is-target-aware ()
  "Only the matching column movement cues and speaks the selected cell."
  (let ((ems--interactive-fn-name 'tabulated-list-next-column)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-tabulated-list-speak-cell)
          (lambda (&optional icon)
            (push (list 'speak-cell icon) events))))
      (emacsvox--advice-tabulated-list-previous-column-after)
      (emacsvox--advice-tabulated-list-next-column-after))
    (should
     (equal
      (nreverse events)
      '((speak-cell select-object))))))

(provide 'emacsvox-tabulated-list-tests)
;;; emacsvox-tabulated-list-tests.el ends here
