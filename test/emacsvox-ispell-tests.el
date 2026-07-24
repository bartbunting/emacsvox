;;; emacsvox-ispell-tests.el --- Ispell advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Ispell advice.

;;; Code:

(require 'ert)
(require 'ispell)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ispell.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ispell-target-arglists
  '((ispell-command-loop (miss guess word start end))
    (ispell-comments-and-strings (&optional start end))
    (ispell-help nil)
    (ispell-buffer nil)
    (ispell-region (reg-start reg-end &optional recheckp shift))
    (ispell-word (&optional following quietly continue region)))
  "Current Emacs 31 Ispell targets and their native arguments.")

(defconst emacsvox-test--ispell-simple-advice
  '((ispell-command-loop
     :before emacsvox--advice-ispell-command-loop-before)
    (ispell-help :before emacsvox--advice-ispell-help-before))
  "Directly migrated simple Ispell advice.")

(defconst emacsvox-test--ispell-session-advice
  '((ispell-comments-and-strings
     :around emacsvox--advice-ispell-comments-and-strings-around)
    (ispell-buffer :around emacsvox--advice-ispell-buffer-around)
    (ispell-region :around emacsvox--advice-ispell-region-around))
  "Directly migrated Ispell session advice.")

(ert-deftest emacsvox-ispell-emacs31-target-contracts ()
  "Every advised Ispell target exists with its Emacs 31 arguments."
  (dolist (entry emacsvox-test--ispell-target-arglists)
    (pcase-let ((`(,target ,arguments) entry))
      (should (fboundp target))
      (should-not (or (get target 'obsolete)
                      (get target 'byte-obsolete-info)))
      (should (equal (help-function-arglist target t) arguments)))))

(ert-deftest emacsvox-ispell-simple-advice-is-directly-registered ()
  "Simple Ispell advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--ispell-simple-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ispell-session-advice-is-directly-registered ()
  "Ispell session advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--ispell-session-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ispell-command-loop-uses-native-arguments ()
  "Correction feedback receives choices and source bounds directly."
  (with-temp-buffer
    (insert "bad line")
    (let (spoken)
      (cl-letf (((symbol-function 'dtk-set-punctuations)
                 (lambda (&rest _)))
                ((symbol-function 'dtk-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox--advice-ispell-command-loop-before
         '("good" "best") nil "bad" 1 4))
      (should
       (equal
        (substring-no-properties spoken)
        "bad line0 good\n1 best\n"))
      (should (eq (get-text-property 0 'personality spoken) voice-bolden))
      (should-not (get-text-property 3 'personality spoken)))))

(ert-deftest emacsvox-ispell-help-feedback-remains-unconditional ()
  "Ispell help continues to speak for internal invocations."
  (let ((ems--interactive-fn-name nil)
        spoken)
    (cl-letf (((symbol-function 'documentation)
               (lambda (_function) "Ispell help"))
              ((symbol-function 'dtk-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-ispell-help-before))
    (should (equal spoken "Ispell help"))))

(ert-deftest emacsvox-ispell-region-runs-once-with-interactive-feedback ()
  "Interactive region checking runs once, silenced, then cues completion."
  (let ((ems--interactive-fn-name 'ispell-region)
        (emacsvox-speak-messages t)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        'region-result
        (emacsvox--advice-ispell-region-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list
             'call arguments inhibit-message emacsvox-speak-messages)
            events)
           'region-result)
         1 9 t 2))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((call (1 9 t 2) t nil) (icon task-done))))))

(ert-deftest emacsvox-ispell-session-programmatic-call-is-quiet ()
  "Programmatic session checking runs once without completion feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        'comments-result
        (emacsvox--advice-ispell-comments-and-strings-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'call arguments) events)
           'comments-result)
         3 12))))
    (should (= calls 1))
    (should (equal events '((call (3 12)))))))

(provide 'emacsvox-ispell-tests)
;;; emacsvox-ispell-tests.el ends here
