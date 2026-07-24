;;; emacsvox-ebuku-tests.el --- Ebuku advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'ebuku)
(load (expand-file-name "../lisp/emacsvox-ebuku.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ebuku-advice-is-current-and-direct ()
  "Current Ebuku targets use native advice directly."
  (dolist (entry emacsvox-ebuku--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ebuku-search-helper-disables-exclude-prompt ()
  "The argument filter supplies an empty exclude term."
  (should
   (equal
    (emacsvox--advice-ebuku--search-helper-filter-args
     '("--sany" "Keyword? "))
    '("--sany" "Keyword? " nil "")))
  (should
   (equal
    (emacsvox--advice-ebuku--search-helper-filter-args
     '("--sany" "Keyword? " "term" "old"))
    '("--sany" "Keyword? " "term" ""))))

(ert-deftest emacsvox-ebuku-movement-feedback-is-target-aware ()
  "Only the matching interactive Ebuku movement command speaks."
  (let ((ems--interactive-fn-name 'ebuku-next-bookmark)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-read-previous-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-ebuku-previous-bookmark-after)
      (emacsvox--advice-ebuku-next-bookmark-after))
    (should (equal (nreverse events) '(select-object line)))))

(provide 'emacsvox-ebuku-tests)
;;; emacsvox-ebuku-tests.el ends here
