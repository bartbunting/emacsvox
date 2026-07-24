;;; emacsvox-chess-tests.el --- Chess advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'chess-display)
(load (expand-file-name "../lisp/emacsvox-chess.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-chess-advice-is-current-and-direct ()
  "Current Chess targets use native advice directly."
  (dolist (entry emacsvox-chess--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-chess-movement-calls-original-once ()
  "Movement advice preserves the result without repeating the command."
  (let ((ems--interactive-fn-name 'chess-display-move-forward)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-chess-state-speaker)
               (lambda () (push 'state events))))
      (should
       (eq 'moved
           (emacsvox--advice-chess-display-move-forward-around
            (lambda (&rest _)
              (cl-incf calls)
              'moved))))
      (should (= calls 1))
      (should (equal (nreverse events) '(right state))))))

(ert-deftest emacsvox-chess-selection-calls-original-once ()
  "Piece selection advice does not toggle the selection a second time."
  (with-temp-buffer
    (insert (propertize "square" 'chess-coord 0))
    (let ((ems--interactive-fn-name 'chess-display-select-piece)
          (chess-display-last-selected nil)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events)))
                ((symbol-function 'emacsvox-chess-describe-square)
                 (lambda (_square) '("a1" "rook")))
                ((symbol-function 'tts-speak-list)
                 (lambda (description &rest _)
                   (push description events))))
        (should
         (eq 'selected
             (emacsvox--advice-chess-display-select-piece-around
              (lambda (&rest _)
                (cl-incf calls)
                (setq chess-display-last-selected (cons (point) 0))
                'selected))))
        (should (= calls 1))
        (should
         (equal (nreverse events)
                '(("a1" "rook") select-object)))))))

(provide 'emacsvox-chess-tests)
;;; emacsvox-chess-tests.el ends here
