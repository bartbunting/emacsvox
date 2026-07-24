;;; emacsvox-sudoku-tests.el --- Sudoku advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'sudoku)
(load (expand-file-name "../lisp/emacsvox-sudoku.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-sudoku-advice-is-current-and-direct ()
  "Current Sudoku targets use native advice directly."
  (dolist (entry emacsvox-sudoku--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-sudoku-tests)
;;; emacsvox-sudoku-tests.el ends here
