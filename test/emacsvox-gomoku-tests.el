;;; emacsvox-gomoku-tests.el --- Gomoku advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'gomoku)
(defvar emacsvox-last-message)
(load
 (expand-file-name "../lisp/emacsvox-gomoku.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(defconst emacsvox-test--gomoku-navigation-targets
  '(gomoku-beginning-of-line gomoku-end-of-line
    gomoku-move-down gomoku-move-up gomoku-move-left gomoku-move-right
    gomoku-move-ne gomoku-move-nw gomoku-move-se gomoku-move-sw))

(ert-deftest emacsvox-gomoku-advice-is-directly-registered ()
  (dolist (target emacsvox-test--gomoku-navigation-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))))
  (dolist
      (entry
       '((gomoku-emacs-plays :after emacsvox--advice-gomoku-emacs-plays-after)
         (gomoku-terminate-game
          :around emacsvox--advice-gomoku-terminate-game-around)
         (gomoku :after emacsvox--advice-gomoku-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-gomoku-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'gomoku-move-ne) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-gomoku-speak-square)
               (lambda () (push 'square events))))
      (emacsvox--advice-gomoku-move-nw-after)
      (emacsvox--advice-gomoku-move-ne-after))
    (should (equal (nreverse events) '(select-object square)))))

(ert-deftest emacsvox-gomoku-terminate-game-runs-once ()
  (let ((gomoku-number-of-moves 17)
        (emacsvox-last-message "game over")
        (calls 0) events)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (push text events)))
              ((symbol-function 'sit-for) (lambda (&rest _) nil)))
      (should
       (eq 'return
           (emacsvox--advice-gomoku-terminate-game-around
            (lambda (result)
              (setq calls (1+ calls))
              (should (eq result 'human-won))
              'return)
            'human-won))))
    (should (= calls 1))
    (should
     (equal events '("human-won in 17 moves  game over ")))))

(ert-deftest emacsvox-gomoku-emacs-move-feedback-is-unconditional ()
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-gomoku-speak-square)
               (lambda () (push 'square events))))
      (emacsvox--advice-gomoku-emacs-plays-after))
    (should (equal (nreverse events) '(mark-object square)))))

(ert-deftest emacsvox-gomoku-programmatic-launch-is-quiet ()
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-gomoku-setup-keys)
               (lambda () (push 'setup events))))
      (emacsvox--advice-gomoku-after))
    (should-not events)))

(provide 'emacsvox-gomoku-tests)
