;;; emacsvox-solitaire-tests.el --- Solitaire advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Solitaire advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'solitaire)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-solitaire.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--solitaire-after-targets
  '(solitaire-left
    solitaire-right
    solitaire-up
    solitaire-down
    solitaire-center-point
    solitaire-move)
  "Current Solitaire commands using direct after advice.")

(ert-deftest emacsvox-solitaire-advice-is-directly-registered ()
  "Solitaire advice is attached directly to current Emacs 31 commands."
  (dolist (target emacsvox-test--solitaire-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-solitaire-omits-removed-quit-command ()
  "The integration does not recreate the removed Solitaire quit command."
  (should-not (fboundp 'solitaire-quit))
  (should-not
   (fboundp 'emacsvox--advice-solitaire-quit-after))
  (should
   (eq (lookup-key solitaire-mode-map "q") 'quit-window)))

(ert-deftest emacsvox-solitaire-horizontal-feedback-is-target-aware ()
  "Horizontal movement optionally announces the current column."
  (let ((ems--interactive-fn-name 'solitaire-right)
        (emacsvox-solitaire-autoshow t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-solitaire-show-column)
               (lambda () (push 'column events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda () (push 'coordinates events))))
      (emacsvox--advice-solitaire-left-after)
      (emacsvox--advice-solitaire-right-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) column coordinates)))))

(ert-deftest emacsvox-solitaire-vertical-feedback-is-target-aware ()
  "Vertical movement optionally announces the current row."
  (let ((ems--interactive-fn-name 'solitaire-up)
        (emacsvox-solitaire-autoshow t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-solitaire-show-row)
               (lambda () (push 'row events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda () (push 'coordinates events))))
      (emacsvox--advice-solitaire-up-after)
      (emacsvox--advice-solitaire-down-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) row coordinates)))))

(ert-deftest emacsvox-solitaire-autoshow-can-be-disabled ()
  "Normal navigation still announces coordinates without autoshow."
  (let ((ems--interactive-fn-name 'solitaire-left)
        (emacsvox-solitaire-autoshow nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-solitaire-show-column)
               (lambda () (push 'column events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda () (push 'coordinates events))))
      (emacsvox--advice-solitaire-left-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) coordinates)))))

(ert-deftest emacsvox-solitaire-center-feedback-is-target-aware ()
  "Center movement has distinct large-movement feedback."
  (let ((ems--interactive-fn-name 'solitaire-center-point)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda () (push 'coordinates events))))
      (emacsvox--advice-solitaire-center-point-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) coordinates)))))

(ert-deftest emacsvox-solitaire-stone-move-always-announces-result ()
  "A completed move retains its unconditional legacy feedback."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda () (push 'coordinates events))))
      (emacsvox--advice-solitaire-move-after))
    (should
     (equal
      (nreverse events)
      '((icon item) coordinates)))))

(ert-deftest emacsvox-solitaire-programmatic-navigation-is-quiet ()
  "Cursor navigation emits no feedback outside interactive dispatch."
  (let ((emacsvox-solitaire-autoshow t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest arguments) (push arguments events)))
              ((symbol-function 'emacsvox-solitaire-show-column)
               (lambda () (push 'column events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda () (push 'coordinates events))))
      (emacsvox--advice-solitaire-left-after)
      (emacsvox--advice-solitaire-center-point-after))
    (should-not events)))

(provide 'emacsvox-solitaire-tests)
;;; emacsvox-solitaire-tests.el ends here
