;;; emacsvox-entertain-tests.el --- Entertainment advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(load
 (expand-file-name "../lisp/emacsvox-entertain.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-entertain-builtins-defer-and-register-directly ()
  (unless (featurep 'doctor)
    (should-not (fboundp 'doctor-txtype)))
  (unless (featurep 'dunnet)
    (should-not (fboundp 'dun-parse))
    (should-not (fboundp 'dun-unix-parse)))
  (require 'doctor)
  (require 'dunnet)
  (dolist
      (entry
       '((doctor-txtype :after emacsvox--advice-doctor-txtype-after)
         (dun-parse :around emacsvox--advice-dun-parse-around)
         (dun-unix-parse
          :around emacsvox--advice-dun-unix-parse-around)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function)
                ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-entertain-doctor-uses-native-answer ()
  (let (spoken)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-doctor-txtype-after
       '(please "tell" me more)))
    (should (equal spoken "please tell me more"))))

(ert-deftest emacsvox-entertain-dunnet-runs-once-and-preserves-result ()
  (with-temp-buffer
    (insert "> look")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'dun-parse)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list start end) events))))
        (should
         (eq 'result
             (emacsvox--advice-dun-parse-around
              (lambda (arg)
                (setq calls (1+ calls))
                (should (= arg 1))
                (insert "\nA room")
                'result)
              1))))
      (should (= calls 1))
      (should
       (equal (nreverse events)
              '(mark-object (7 14)))))))

(ert-deftest emacsvox-entertain-dunnet-programmatic-call-is-quiet ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-dun-unix-parse-around
            (lambda (&rest _)
              (setq calls (1+ calls))
              'result)
            1))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-entertain-hangman-defers-optional-targets ()
  (should (fboundp 'emacsvox--advice-hm-self-guess-char-after))
  (should (fboundp 'emacsvox--advice-hangman-after))
  (unless (featurep 'hangman)
    (should-not (fboundp 'hm-self-guess-char))
    (should-not (fboundp 'hangman))))

(ert-deftest emacsvox-entertain-hangman-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'hangman) events)
    (cl-letf (((symbol-function 'emacsvox-hangman-setup-pronunciations)
               (lambda () (push 'pronunciations events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-hm-self-guess-char-after)
      (emacsvox--advice-hangman-after))
    (should
     (equal (nreverse events) '(pronunciations open-object)))))

(ert-deftest emacsvox-entertain-hangman-installs-after-definition ()
  (let ((map (make-sparse-keymap))
        (old-map hm-map))
    (unwind-protect
        (progn
          (setq hm-map map)
          (fset 'hm-self-guess-char (lambda () 'guess))
          (fset 'hangman (lambda () 'game))
          (emacsvox-hangman--install)
          (dolist
              (entry
               '((hm-self-guess-char
                  emacsvox--advice-hm-self-guess-char-after)
                 (hangman emacsvox--advice-hangman-after)))
            (pcase-let ((`(,target ,function) entry))
              (should (advice-member-p function target))
              (should-not
               (gethash (list target :after function)
                        ems--modern-advice-wrappers))))
          (should
           (eq (lookup-key map " ")
               'emacsvox-hangman-speak-guess))
          (should
           (eq (lookup-key map "=")
               'emacsvox-hangman-speak-statistics)))
      (setq hm-map old-map)
      (when (fboundp 'hm-self-guess-char)
        (advice-remove
         'hm-self-guess-char
         #'emacsvox--advice-hm-self-guess-char-after)
        (fmakunbound 'hm-self-guess-char))
      (when (fboundp 'hangman)
        (advice-remove 'hangman #'emacsvox--advice-hangman-after)
        (fmakunbound 'hangman)))))

(provide 'emacsvox-entertain-tests)
