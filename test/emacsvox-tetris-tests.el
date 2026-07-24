;;; emacsvox-tetris-tests.el --- Tetris advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tetris advice.

;;; Code:

(require 'ert)
(require 'tetris)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tetris.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tetris-after-targets
  '(tetris-start-game
    tetris-end-game
    tetris-draw-next-shape
    tetris-rotate-next
    tetris-rotate-prev
    tetris-move-left-edge
    tetris-move-right-edge
    tetris-move-to-x-pos
    tetris-move-left
    tetris-move-right
    tetris-move-bottom)
  "Current Emacs 31 Tetris targets using direct after advice.")

(ert-deftest emacsvox-tetris-advice-is-directly-registered ()
  "Tetris advice is attached directly with its native advice classes."
  (dolist (target emacsvox-test--tetris-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist
      (entry
       '((tetris :around emacsvox--advice-tetris-around)
         (tetris-full-row :filter-return
          emacsvox--advice-tetris-full-row-filter-return)
         (tetris-draw-score :override
          emacsvox--advice-tetris-draw-score-override)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-tetris-programmatic-launch-calls-original-once ()
  "A programmatic Tetris launch preserves its result without feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'tts-set-punctuations)
               (lambda (&rest _) (push 'punctuation events)))
              ((symbol-function 'emacsvox-tetris-define-pronunciations)
               (lambda () (push 'pronunciations events)))
              ((symbol-function 'emacsvox-tetris-define-keys)
               (lambda () (push 'keys events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (push 'icon events)))
              ((symbol-function 'emacsvox-tetris-speak-current-shape)
               (lambda () (push 'shape events))))
      (should
       (eq
        'result
        (emacsvox--advice-tetris-around
         (lambda (&rest arguments)
           (setq calls (1+ calls))
           (should (equal arguments '(argument)))
           'result)
         'argument))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-tetris-interactive-launch-preserves-order ()
  "An interactive Tetris launch configures, calls, and reports once."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'tetris)
          (emacsvox-tetris-tick-period 15)
          (emacsvox-tetris-width 10)
          (tetris-height 2)
          (tetris-width 4)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-tetris-blank-row)
                 (lambda ()
                   (push (list 'blank tetris-width) events)
                   "blank"))
                ((symbol-function 'tts-set-punctuations)
                 (lambda (value) (push (list 'punctuation value) events)))
                ((symbol-function 'emacsvox-tetris-define-pronunciations)
                 (lambda () (push 'pronunciations events)))
                ((symbol-function 'emacsvox-tetris-define-keys)
                 (lambda () (push 'keys events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-tetris-speak-current-shape)
                 (lambda () (push 'shape events))))
        (should
         (eq
          'result
          (emacsvox--advice-tetris-around
           (lambda ()
             (setq calls (1+ calls))
             (push
              (list 'original (tetris-get-tick-period) tetris-width)
              events)
             'result)))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((blank 10)
          (original 15 10)
          (punctuation all)
          pronunciations
          keys
          (icon open-object)
          shape)))
      (should (= (line-number-at-pos) 3)))))

(ert-deftest emacsvox-tetris-full-row-filters-return-value ()
  "Full-row feedback preserves both true and false return values."
  (let ((emacsvox-tetris-filled-a-row nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (should-not
       (emacsvox--advice-tetris-full-row-filter-return nil))
      (should
       (emacsvox--advice-tetris-full-row-filter-return 'full)))
    (should emacsvox-tetris-filled-a-row)
    (should (equal events '(item)))))

(ert-deftest emacsvox-tetris-score-drawing-is-explicitly-overridden ()
  "The score override returns nil without needing an original function."
  (should-not (emacsvox--advice-tetris-draw-score-override)))

(provide 'emacsvox-tetris-tests)
;;; emacsvox-tetris-tests.el ends here
