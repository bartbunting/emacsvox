;;; emacsvox-core-migration-tests.el --- Core advice migration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Native-registration coverage for migrated core movement and editing advice.
;; `emacsvox-mail-tests' loads the core advice source before this file.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'button)
(require 'emacsvox-advice)

(defconst emacsvox-test--core-after-targets
  '(next-line previous-line
    beginning-of-visual-line end-of-visual-line
    next-logical-line previous-logical-line
    delete-indentation back-to-indentation
    lisp-indent-line goto-line goto-line-relative
    left-char right-char backward-char forward-char
    forward-word right-word backward-word left-word
    beginning-of-buffer end-of-buffer
    tab-to-tab-stop indent-for-tab-command reindent-then-newline-and-indent
    indent-sexp indent-pp-sexp indent-region indent-relative
    backward-sentence forward-sentence
    forward-paragraph backward-paragraph
    forward-list backward-list up-list backward-up-list down-list
    forward-page backward-page
    newline newline-and-indent electric-newline-and-maybe-indent)
  "Core commands migrated with generated native after advice.")

(defconst emacsvox-test--core-direct-advice
  '((delete-forward-char :around emacsvox--advice-delete-forward-char-around)
    (delete-char :around emacsvox--advice-delete-char-around)
    (forward-button :around emacsvox--advice-forward-button-around)
    (backward-button :around emacsvox--advice-backward-button-around)
    (forward-sexp :around emacsvox--advice-forward-sexp-around)
    (backward-sexp :around emacsvox--advice-backward-sexp-around)
    (beginning-of-defun :around emacsvox--advice-beginning-of-defun-around)
    (end-of-defun :around emacsvox--advice-end-of-defun-around)
    (kill-word :before emacsvox--advice-kill-word-before)
    (kill-ring-save :after emacsvox--advice-kill-ring-save-after))
  "Core commands migrated with individually defined native advice.")

(ert-deftest emacsvox-core-migrated-after-advice-is-directly-registered ()
  "Generated movement and newline advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--core-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-core-migrated-direct-advice-bypasses-bridge ()
  "Individually migrated editing advice is native and inspectable."
  (dolist (entry emacsvox-test--core-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-core-delete-advice-calls-original-exactly-once ()
  "Forward deletion preserves feedback order, arguments, and return value."
  (let ((ems--interactive-fn-name 'delete-forward-char)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'dtk-tone-deletion)
               (lambda () (push 'tone events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest arguments)
                 (push (cons 'speak-char arguments) events))))
      (should
       (equal
        (emacsvox--advice-delete-forward-char-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (cons 'original arguments) events)
           'deleted)
         2 'killflag)
        'deleted)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '(tone (speak-char t) (original 2 killflag))))))

(ert-deftest emacsvox-core-delete-advice-is-quiet-programmatically ()
  "Programmatic deletion calls the original without speech feedback."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'dtk-tone-deletion)
               (lambda () (push 'tone events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest _) (push 'speech events))))
      (should
       (eq
        (emacsvox--advice-delete-forward-char-around
         (lambda (&rest _) 'deleted) 1)
        'deleted)))
    (should-not events)))

(ert-deftest emacsvox-core-indent-advice-preserves-feedback-order ()
  "Indentation advice emits its icon before speaking the current column."
  (let ((ems--interactive-fn-name 'indent-for-tab-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-current-column)
               (lambda () (push 'speak-current-column events))))
      (emacsvox--advice-indent-for-tab-command-after)
      ;; The interactive marker was consumed by the first invocation.
      (emacsvox--advice-indent-for-tab-command-after))
    (should
     (equal
      (nreverse events) '((icon fill-object) speak-current-column)))))

(ert-deftest emacsvox-core-button-advice-preserves-context-and-result ()
  "Button movement is silenced, spoken after moving, and returns its result."
  (with-temp-buffer
    (insert "start target")
    (make-text-button 7 13)
    (goto-char 1)
    (let ((ems--interactive-fn-name 'forward-button)
          (emacsvox-speak-messages t)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          (emacsvox--advice-forward-button-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push
              (list 'original arguments inhibit-message
                    emacsvox-speak-messages)
              events)
             (goto-char 7)
             'button-result)
           1 nil t)
          'button-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original (1 nil t) t nil)
          (speak "target")
          (icon large-movement)))))))

(ert-deftest emacsvox-core-sexp-advice-calls-original-once-before-feedback ()
  "Sexp movement preserves return value and speaks the traversed region."
  (with-temp-buffer
    (insert "(one) (two)")
    (goto-char 1)
    (let ((ems--interactive-fn-name 'forward-sexp)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push
                    (list 'speak-region start end emacsvox-show-point)
                    events))))
        (should
         (eq
          (emacsvox--advice-forward-sexp-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (list 'original arguments) events)
             (goto-char 6)
             'sexp-result)
           1)
          'sexp-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original (1))
          (icon large-movement)
          (speak-region 1 6 t)))))))

(provide 'emacsvox-core-migration-tests)
;;; emacsvox-core-migration-tests.el ends here
