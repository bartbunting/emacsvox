;;; emacsvox-flyspell-tests.el --- Flyspell advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'flyspell)
(load
 (expand-file-name "../lisp/emacsvox-flyspell.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-flyspell-advice-is-directly-registered ()
  (dolist
      (entry
       '((flyspell-buffer :around emacsvox--advice-flyspell-buffer-around)
         (flyspell-region :around emacsvox--advice-flyspell-region-around)
         (flyspell-auto-correct-word
          :around emacsvox--advice-flyspell-auto-correct-word-around)
         (flyspell-unhighlight-at
          :before emacsvox--advice-flyspell-unhighlight-at-before)
         (flyspell-goto-next-error
          :after emacsvox--advice-flyspell-goto-next-error-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-flyspell-silences-icons-once ()
  (let ((calls 0))
    (should
     (eq 'result
         (emacsvox--advice-flyspell-region-around
          (lambda (&rest args)
            (setq calls (1+ calls))
            (should (equal args '(2 9)))
            (should-not emacsvox-use-icons)
            'result)
          2 9)))
    (should (= calls 1))))

(ert-deftest emacsvox-flyspell-auto-correct-runs-once ()
  (let ((ems--interactive-fn-name 'flyspell-auto-correct-word)
        (calls 0) events)
    (cl-letf (((symbol-function 'flyspell-get-word)
               (lambda (&rest _) '("corrected")))
              ((symbol-function 'sit-for) (lambda (&rest _) nil))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq 'result
           (emacsvox--advice-flyspell-auto-correct-word-around
            (lambda () (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should
     (equal (nreverse events)
            '((speak "corrected") (icon select-object))))))

(ert-deftest emacsvox-flyspell-programmatic-auto-correct-runs-once-quietly ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-flyspell-auto-correct-word-around
            (lambda () (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-flyspell-unhighlight-uses-native-position ()
  (with-temp-buffer
    (insert "word")
    (put-text-property 1 5 'personality 'voice-bolden)
    (let ((overlay (make-overlay 1 5)))
      (cl-letf (((symbol-function 'flyspell-overlay-p)
                 (lambda (candidate) (eq candidate overlay))))
        (emacsvox--advice-flyspell-unhighlight-at-before 2))
      (should-not (text-property-any 1 5 'personality 'voice-bolden)))))

(ert-deftest emacsvox-flyspell-defers-optional-correction-advice ()
  (dolist (target emacsvox-flyspell--correct-targets)
    (should-not (fboundp target))
    (should
     (fboundp (intern (format "emacsvox--advice-%s-after" target))))))

(provide 'emacsvox-flyspell-tests)
