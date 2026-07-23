;;; emacsvox-mark-tests.el --- Mark advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated mark advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--mark-direct-advice
  '((push-mark :around emacsvox--advice-push-mark-around)
    (set-mark-command :after
     emacsvox--advice-set-mark-command-after)
    (pop-to-mark-command :after
     emacsvox--advice-pop-to-mark-command-after)
    (pop-global-mark :after
     emacsvox--advice-pop-global-mark-after)
    (mark-defun :after emacsvox--advice-mark-defun-after)
    (mark-whole-buffer :after
     emacsvox--advice-mark-whole-buffer-after)
    (mark-paragraph :after
     emacsvox--advice-mark-paragraph-after)
    (mark-page :after emacsvox--advice-mark-page-after)
    (mark-word :after emacsvox--advice-mark-word-after)
    (mark-sexp :after emacsvox--advice-mark-sexp-after)
    (mark-end-of-sentence :after
     emacsvox--advice-mark-end-of-sentence-after))
  "Mark commands using individually named native advice.")

(ert-deftest emacsvox-mark-advice-is-directly-registered ()
  "Migrated mark advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--mark-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-push-mark-remains-silenced ()
  "Push-mark calls its original once with messages silenced."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        observed-state)
    (should
     (eq
      (emacsvox--advice-push-mark-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (setq observed-state
               (list arguments emacsvox-speak-messages inhibit-message))
         'push-result)
       4 t nil)
      'push-result))
    (should (= calls 1))
    (should (equal observed-state '((4 t nil) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-mark-ring-feedback-is-target-aware ()
  "Only the matching mark-ring command cues and speaks with point shown."
  (let ((ems--interactive-fn-name 'pop-to-mark-command)
        (emacsvox-show-point nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda ()
                 (push
                  (list 'speak-line emacsvox-show-point)
                  events))))
      (emacsvox--advice-set-mark-command-after 1)
      (emacsvox--advice-pop-to-mark-command-after))
    (should-not emacsvox-show-point)
    (should
     (equal
      (nreverse events)
      '((icon mark-object) (speak-line t))))))

(ert-deftest emacsvox-global-mark-feedback-preserves-order ()
  "Popping the global mark speaks point before notifying the buffer name."
  (with-temp-buffer
    (rename-buffer "mark destination" t)
    (let ((ems--interactive-fn-name 'pop-global-mark)
          (emacsvox-show-point nil)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-line)
                 (lambda ()
                   (push
                    (list 'speak-line emacsvox-show-point)
                    events)))
                ((symbol-function 'dtk-notify)
                 (lambda (text) (push (list 'notify text) events))))
        (emacsvox--advice-pop-global-mark-after))
      (should-not emacsvox-show-point)
      (should
       (equal
        (nreverse events)
        '((speak-line t) (notify "mark destination")))))))

(ert-deftest emacsvox-marked-lines-feedback-is-target-aware ()
  "Only the matching object-mark command reports its marked line count."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (goto-char 1)
    (set-mark 9)
    (let ((ems--interactive-fn-name 'mark-paragraph)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (emacsvox--advice-mark-defun-after)
        (emacsvox--advice-mark-paragraph-after))
      (should
       (equal
        (nreverse events)
        '((icon mark-object)
          (message "Marked paragraph containing 2 lines")))))))

(ert-deftest emacsvox-mark-word-announces-post-command-range ()
  "Interactive word marking reports the text between point and mark."
  (with-temp-buffer
    (insert "hello")
    (goto-char 1)
    (set-mark 6)
    (let ((ems--interactive-fn-name 'mark-word)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (emacsvox--advice-mark-word-after))
      (should
       (equal
        (nreverse events)
        '((icon mark-object) (message "Word hello marked")))))))

(ert-deftest emacsvox-mark-sexp-announces-character-count ()
  "A single-line marked S-expression reports its character count."
  (with-temp-buffer
    (insert "abc")
    (goto-char 1)
    (set-mark 4)
    (let ((ems--interactive-fn-name 'mark-sexp)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (text &rest _)
                   (push (list 'message text) events))))
        (emacsvox--advice-mark-sexp-after))
      (should
       (equal
        (nreverse events)
        '((icon mark-object)
          (message "marked S expression containing 3 characters")))))))

(provide 'emacsvox-mark-tests)
;;; emacsvox-mark-tests.el ends here
