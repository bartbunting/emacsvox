;;; emacsvox-hydra-tests.el --- Hydra advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'lv)

(load
 (expand-file-name
  "../lisp/emacsvox-hydra.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-hydra-current-lv-target-contracts ()
  "LV advice targets have their current package arguments."
  (should
   (equal
    (help-function-arglist 'lv-message t)
    '(format-string &rest args)))
  (should (equal (help-function-arglist 'lv-delete-window t) nil)))

(ert-deftest emacsvox-hydra-advice-is-directly-registered ()
  "Hydra's LV advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-hydra--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function)
                ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-hydra-delete-window-feedback-is-unconditional ()
  "LV window deletion retains its unconditional stop and icon cues."
  (let (events)
    (cl-letf (((symbol-function 'dtk-stop)
               (lambda (scope) (push (list 'stop scope) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-lv-delete-window-after))
    (should
     (equal
      (nreverse events)
      '((stop all) (icon delete-object))))))

(provide 'emacsvox-hydra-tests)
;;; emacsvox-hydra-tests.el ends here
