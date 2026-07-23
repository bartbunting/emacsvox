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
    delete-horizontal-space
    tab-to-tab-stop indent-for-tab-command reindent-then-newline-and-indent
    indent-sexp indent-pp-sexp indent-region indent-relative
    backward-sentence forward-sentence
    forward-paragraph backward-paragraph
    forward-list backward-list up-list backward-up-list down-list
    forward-page backward-page
    scroll-other-window scroll-other-window-up scroll-other-window-down
    scroll-up scroll-down scroll-up-command scroll-down-command
    kill-buffer kill-current-buffer quit-window
    other-frame other-window
    next-window-any-frame previous-window-any-frame
    switch-to-prev-buffer switch-to-next-buffer
    switch-to-buffer switch-to-buffer-other-window bury-buffer
    next-buffer previous-buffer switch-to-buffer-other-frame
    newline newline-and-indent electric-newline-and-maybe-indent)
  "Core commands migrated with generated native after advice.")

(defconst emacsvox-test--core-before-targets
  '(kill-visual-line kill-line kill-whole-line)
  "Core commands migrated with generated native before advice.")

(defconst emacsvox-test--core-direct-advice
  '((delete-forward-char :around emacsvox--advice-delete-forward-char-around)
    (delete-char :around emacsvox--advice-delete-char-around)
    (backward-delete-char :around emacsvox--advice-backward-delete-char-around)
    (backward-delete-char-untabify :around
     emacsvox--advice-backward-delete-char-untabify-around)
    (delete-backward-char :around emacsvox--advice-delete-backward-char-around)
    (upcase-word :around emacsvox--advice-upcase-word-around)
    (downcase-word :around emacsvox--advice-downcase-word-around)
    (capitalize-word :around emacsvox--advice-capitalize-word-around)
    (forward-button :around emacsvox--advice-forward-button-around)
    (backward-button :around emacsvox--advice-backward-button-around)
    (forward-sexp :around emacsvox--advice-forward-sexp-around)
    (backward-sexp :around emacsvox--advice-backward-sexp-around)
    (beginning-of-defun :around emacsvox--advice-beginning-of-defun-around)
    (end-of-defun :around emacsvox--advice-end-of-defun-around)
    (insert-char :after emacsvox--advice-insert-char-after)
    (kill-word :before emacsvox--advice-kill-word-before)
    (backward-kill-word :before emacsvox--advice-backward-kill-word-before)
    (kill-sexp :before emacsvox--advice-kill-sexp-before)
    (kill-sentence :before emacsvox--advice-kill-sentence-before)
    (delete-blank-lines :before emacsvox--advice-delete-blank-lines-before)
    (kill-ring-save :after emacsvox--advice-kill-ring-save-after)
    (untabify :after emacsvox--advice-untabify-after)
    (pop-to-buffer :after emacsvox--advice-pop-to-buffer-after)
    (scratch-buffer :after emacsvox--advice-scratch-buffer-after)
    (display-buffer :after emacsvox--advice-display-buffer-after)
    (rename-buffer :after emacsvox--advice-rename-buffer-after)
    (rename-uniquely :after emacsvox--advice-rename-uniquely-after))
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

(ert-deftest emacsvox-core-migrated-before-advice-is-directly-registered ()
  "Generated deletion feedback is native and inspectable."
  (dolist (target emacsvox-test--core-before-targets)
    (let ((function (intern (format "emacsvox--advice-%s-before" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :before function) ems--modern-advice-wrappers)))))

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

(ert-deftest emacsvox-core-scroll-other-window-speaks-target-window ()
  "Other-window scrolling speaks there and restores the selected window."
  (let* ((original-window (selected-window))
         (target-buffer (generate-new-buffer " *emacsvox-scroll-test*"))
         (target-window (split-window-right))
         (ems--interactive-fn-name 'scroll-other-window)
         spoken-window
         spoken-buffer)
    (unwind-protect
        (progn
          (set-window-buffer target-window target-buffer)
          (cl-letf (((symbol-function 'other-window-for-scrolling)
                     (lambda () target-window))
                    ((symbol-function 'emacsvox-speak-windowful)
                     (lambda ()
                       (setq spoken-window (selected-window)
                             spoken-buffer (current-buffer)))))
            (emacsvox--advice-scroll-other-window-after))
          (should (eq spoken-window target-window))
          (should (eq spoken-buffer target-buffer))
          (should (eq (selected-window) original-window)))
      (when (window-live-p target-window)
        (delete-window target-window))
      (when (buffer-live-p target-buffer)
        (kill-buffer target-buffer)))))

(ert-deftest emacsvox-core-scroll-advice-preserves-semantic-feedback ()
  "Current-window scrolling emits its icon, contents, and percentage."
  (let ((ems--interactive-fn-name 'scroll-up-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-get-window-contents)
               (lambda () "visible text"))
              ((symbol-function 'emacsvox-get-current-percentage-into-buffer)
               (lambda () "50%"))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'dtk-notify)
               (lambda (text)
                 (push
                  (list 'notify (substring-no-properties text)
                        (get-text-property 0 'personality text))
                  events))))
      (emacsvox--advice-scroll-up-command-after))
    (should
     (equal
      (nreverse events)
      `((icon scroll)
        (speak "visible text")
        (notify "50% " ,voice-smoothen))))))

(ert-deftest emacsvox-core-untabify-advice-uses-explicit-region-arguments ()
  "Untabify cleanup replaces nonbreaking spaces inside its advised region."
  (with-temp-buffer
    (insert "a" (string 160) "b" (string 160) "c")
    (emacsvox--advice-untabify-after 1 4)
    (should (equal (buffer-string) (concat "a b" (string 160) "c")))))

(ert-deftest emacsvox-core-case-word-advice-calls-original-once-interactively ()
  "Interactive case changes play a tone, call once, then speak ahead."
  (with-temp-buffer
    (insert "alpha beta gamma")
    (goto-char 1)
    (let ((ems--interactive-fn-name 'upcase-word)
          (current-prefix-arg nil)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-tone-upcase)
                 (lambda () (push 'tone events)))
                ((symbol-function 'emacsvox-speak-word)
                 (lambda (&rest _)
                   (push (list 'speak-word (point)) events))))
        (should
         (eq
          (emacsvox--advice-upcase-word-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (list 'original arguments) events)
             (goto-char 6)
             'case-result)
           1)
          'case-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(tone (original (1)) (speak-word 7)))))))

(ert-deftest emacsvox-core-case-word-advice-calls-original-once-programmatically ()
  "Programmatic case changes call once without speech feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'dtk-tone-downcase)
               (lambda () (setq feedback t)))
              ((symbol-function 'emacsvox-speak-word)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-downcase-word-around
         (lambda (&rest _)
           (cl-incf calls)
           'case-result)
         1)
        'case-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-core-buffer-close-advice-preserves-feedback-order ()
  "Interactive buffer closing emits its icon, stop, and mode line once."
  (let ((ems--interactive-fn-name 'kill-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-stop)
               (lambda (stream) (push (list 'stop stream) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-kill-buffer-after)
      ;; The explicit interactive marker is consumed after one response.
      (emacsvox--advice-kill-buffer-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) (stop all) speak-mode-line)))))

(ert-deftest emacsvox-core-buffer-selection-advice-is-interactive-only ()
  "Buffer selection feedback is emitted only for its interactive command."
  (let ((ems--interactive-fn-name 'switch-to-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-other-window-after)
      (emacsvox--advice-switch-to-buffer-after)
      (emacsvox--advice-switch-to-buffer-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-mode-line)))))

(ert-deftest emacsvox-core-display-buffer-advice-uses-explicit-argument ()
  "Display feedback names its argument without compatibility bridge state."
  (let ((ems--interactive-fn-name 'display-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (apply #'format format-string arguments)
                  events))))
      (emacsvox--advice-display-buffer-after
       "notes" 'display-action 'frame))
    (should
     (equal
      (nreverse events)
      '((icon open-object) "Displayed notes")))))

(ert-deftest emacsvox-core-display-buffer-advice-is-quiet-programmatically ()
  "Programmatic display calls do not produce speech feedback."
  (let ((ems--interactive-fn-name nil)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'message)
               (lambda (&rest _) (setq feedback t))))
      (emacsvox--advice-display-buffer-after "notes"))
    (should-not feedback)))

(provide 'emacsvox-core-migration-tests)
;;; emacsvox-core-migration-tests.el ends here
