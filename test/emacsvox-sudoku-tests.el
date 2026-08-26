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

(ert-deftest emacsvox-sudoku-entry-uses-automatic-punctuation-policy ()
  "Sudoku entry applies its mode policy without creating an override."
  (with-temp-buffer
    (setq major-mode 'sudoku-mode)
    (let ((ems--interactive-fn-name 'sudoku)
          (tts-speaker-process nil))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-sudoku-speak-current-cell-value)
                 #'ignore))
        (emacsvox--advice-sudoku-after))
      (should (eq tts-punctuation-mode 'some))
      (should-not tts-punctuation-mode-override))))

(provide 'emacsvox-sudoku-tests)
;;; emacsvox-sudoku-tests.el ends here
