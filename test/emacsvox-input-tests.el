;;; emacsvox-input-tests.el --- Input advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Argument handling and native-registration coverage for input prompt advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(defvar read-passwd--password-hidden)
(defvar read-passwd--hide-password)
(require 'emacsvox-advice)

(defconst emacsvox-test--input-before-targets
  '(read-key read-key-sequence read-key-sequence-vector
    read-char read-char-exclusive)
  "Input readers migrated with generated native prompt advice.")

(defconst emacsvox-test--input-direct-advice
  '((quoted-insert :after emacsvox--advice-quoted-insert-after)
    (read-event :before emacsvox--advice-read-event-before)
    (read-multiple-choice :around
     emacsvox--advice-read-multiple-choice-around)
    (read-event :around emacsvox--advice-choice-read-around)
    (read-key :around emacsvox--advice-choice-read-around)
    (read-passwd--hide-password :after
     emacsvox--advice-read-passwd--hide-password-after)
    (read-passwd-toggle-visibility :after
     emacsvox--advice-read-passwd-toggle-visibility-after)
    (read-char-choice :before emacsvox--advice-read-char-choice-before)
    (yes-or-no-p :around emacsvox--advice-yes-or-no-p-around)
    (y-or-n-p :around emacsvox--advice-y-or-n-p-around)
    (ask-user-about-lock-help :after
     emacsvox--advice-ask-user-about-lock-help-after))
  "Input readers migrated with individually defined native advice.")

(ert-deftest emacsvox-input-advice-is-directly-registered ()
  "Migrated input advice uses native advice directly."
  (dolist (target emacsvox-test--input-before-targets)
    (let ((function (intern (format "emacsvox--advice-%s-before" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-test--input-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-input-prompts-never-use-notification-speech ()
  "Event and key prompts use main speech."
  (let ((emacsvox-speak-messages t)
        (emacsvox-last-message nil)
        (emacsvox-read-char-prompt-cache nil)
        speech)
    (cl-letf (((symbol-function 'tts-notify)
               (lambda (&rest _) (ert-fail "Prompt used notification speech")))
              ((symbol-function 'tts-speak)
               (lambda (text) (push text speech)))
              ((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'ems--log-message) #'ignore)
              ((symbol-function 'sox-tones) #'ignore)
              ((symbol-function 'tts-speak-list) #'ignore))
      (dolist (target (cons 'read-event emacsvox-test--input-before-targets))
        (funcall (intern (format "emacsvox--advice-%s-before" target))
                 "Continue?")))
    (should (equal speech (make-list 6 "Continue?")))))

(ert-deftest emacsvox-reading-unit-prompt-is-spoken-once-on-main ()
  "Reading choices keep their full instructions and return the chosen extent."
  (dolist (unit '("buffer" "line" "paragraph" "page" "word" "sexp"))
    ;; Isolate each unit's echo area, then exercise repeated reading prompts.
    (let ((emacsvox-speak-messages nil)) (message nil))
    (dolist (choice '((?s . -1) (?r . 1) (?x . nil)))
      (let ((unread-command-events (list (car choice)))
            (emacsvox-speak-messages t)
            (emacsvox-last-message nil)
            (emacsvox-read-char-prompt-cache nil)
            speech notifications)
        (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                  ((symbol-function 'tts-speak)
                   (lambda (text) (push text speech)))
                  ((symbol-function 'tts-notify)
                   (lambda (text &rest _) (push text notifications))))
          (should (equal (emacsvox-ask-how-to-speak unit t) (cdr choice))))
        (ert-info ((format "Reading %s with choice %c" unit (car choice)))
          (should-not notifications))
        (should
         (equal speech
                (list (format
                       "Press s to speak start of %s, r for rest of %s. Any key for entire %s "
                       unit unit unit))))
        (should (equal emacsvox-read-char-prompt-cache (car speech)))))))

(ert-deftest emacsvox-reading-unit-quick-choice-preserves-selection ()
  "A quick choice still reads its key without the full instructions."
  (let ((unread-command-events (list ?r))
        (emacsvox-speak-messages nil)
        (emacsvox-last-message nil)
        (emacsvox-read-char-prompt-cache nil))
    (should (= 1 (emacsvox-ask-how-to-speak "paragraph" nil)))
    (should-not emacsvox-read-char-prompt-cache)))

(ert-deftest emacsvox-read-event-advice-uses-explicit-prompt ()
  "Event-reading feedback uses its prompt argument directly."
  (let (speech)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (push text speech))))
      (emacsvox--advice-read-event-before "Press a key")
      (emacsvox--advice-read-event-before nil))
    (should (equal speech '("Press a key")))))

(defun emacsvox-test--choice-interaction (keys &optional show-help long-form)
  "Ask a real question and process KEYS, returning observations.
Pass SHOW-HELP and LONG-FORM to the native reader."
  (require 'emacsvox-keymap)
  (save-window-excursion
    (let ((buffer (generate-new-buffer " *question source*"))
          (use-dialog-box nil)
          (kill-ring nil)
          (emacsvox-speak-messages t)
          (old-global-map (current-global-map))
          (map (copy-keymap (current-global-map)))
          (log-message (symbol-function 'ems--log-message))
          answer failure speech notifications review nested logged)
      (unwind-protect
          (progn
            (switch-to-buffer buffer)
            (insert "Untouched source text")
            (use-global-map map)
            (define-key map (kbd "<f5>")
                        (lambda ()
                          (interactive)
                          (condition-case err
                              (setq answer
                                    (read-multiple-choice
                                     "Continue?" '((?y "yes" "Accept the change")
                                                   (?n "no" "Leave it unchanged"))
                                     "The complete explanation.\nSecond review line."
                                     show-help long-form))
                            ((error quit) (setq failure err)))))
            (define-key map (kbd "<f6>")
                        (lambda ()
                          (interactive)
                          (setq review (list (buffer-name) (point)
                                             (buffer-string)))))
            (define-key map (kbd "<f7>")
                        (lambda ()
                          (interactive)
                          (let ((enable-recursive-minibuffers t))
                            (push (read-string "Nested text: ") nested))))
            (define-key map (kbd "<f8>")
                        (lambda ()
                          (interactive)
                          (condition-case nil
                              (push (read-multiple-choice
                                     "Nested choice?" '((?y "yes") (?n "no"))
                                     "Inner explanation" "*Inner Question Help*")
                                    nested)
                            (quit (push 'cancelled nested)))))
            (cl-letf (((symbol-function 'tts-speak)
                       (lambda (text)
                         (push (list (substring-no-properties text)
                                     (minibuffer-depth)) speech)))
                      ((symbol-function 'tts-notify)
                       (lambda (text &rest _) (push text notifications)))
                      ((symbol-function 'ems--log-message)
                       (lambda (text)
                         (push text logged)
                         (funcall log-message text)))
                      ((symbol-function 'emacsvox-icon) #'ignore))
              (execute-kbd-macro (vconcat (kbd "<f5>") (kbd keys))))
            (should (eq (window-buffer (selected-window)) buffer))
            (should (equal (buffer-string) "Untouched source text"))
            (should-not emacsvox--choice-context)
            (should (zerop (minibuffer-depth)))
            (list :answer answer :failure failure :speech (nreverse speech)
                  :notifications notifications :review review :nested nested :logged logged))
        (use-global-map old-global-map)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-choice-graphical-entry-and-repeat ()
  "Speak one full question when input is ready; repeat survives other messages."
  (skip-unless (display-graphic-p))
  (dolist (modal '(nil t))
    (let* ((read-char-choice-use-read-key modal)
           (result (emacsvox-test--choice-interaction "C-e s C-e a n"))
           (speech (plist-get result :speech)))
      (should-not (plist-get result :failure))
      (should (equal (plist-get result :answer) '(?n "no" "Leave it unchanged")))
      (should (= 2 (length speech)))
      (should (equal (car speech) (cadr speech)))
      (should (= (cadar speech)
                 (if (and (fboundp 'read-multiple-choice--from-minibuffer)
                          (not modal)) 1 0)))
      (should (string-match-p "The complete explanation" (caar speech)))
      (should (string-match-p "n: no. Leave it unchanged" (caar speech)))
      (should (equal (plist-get result :logged) (list (caar speech))))
      (should-not (plist-get result :notifications)))))

(ert-deftest emacsvox-choice-graphical-help-review-and-return ()
  "Review the named question with ordinary navigation, then answer it."
  (skip-unless (display-graphic-p))
  (dolist (modal '(nil t))
    (dolist (name '(nil "*Disabled Command*" "*Custom Question Help*"))
      (let* ((read-char-choice-use-read-key modal)
             (result (emacsvox-test--choice-interaction
                      "C-e h C-n C-e l <f6> q n" name))
             (review (plist-get result :review)))
        (should-not (plist-get result :failure))
        (should (eq (car (plist-get result :answer)) ?n))
        (should (equal (car review) (or name "*Multiple Choice Help*")))
        (should (> (cadr review) 1))
        (should (string-match-p "complete explanation" (nth 2 review)))
        (should (string-match-p "q returns to the question" (nth 2 review)))
        (when (get-buffer (car review))
          (with-current-buffer (car review)
            (should-not (eq (key-binding (kbd "q")) #'emacsvox--choice-return))))))))

(ert-deftest emacsvox-choice-graphical-cancel-from-question-and-help ()
  "C-g cancels both native reader variants, including while reviewing Help."
  (skip-unless (display-graphic-p))
  (dolist (modal '(nil t))
    (dolist (keys (append '("C-g" "C-e h C-g")
                         (when (or modal
                                   (not (fboundp 'read-multiple-choice--from-minibuffer)))
                           '("C-e C-g"))))
      (let* ((read-char-choice-use-read-key modal)
             (result (emacsvox-test--choice-interaction keys)))
        (should-not (plist-get result :answer))
        (should (memq 'quit (get (car (plist-get result :failure))
                                'error-conditions)))))))

(ert-deftest emacsvox-choice-graphical-long-answer ()
  "Long answers retain completion and accept the chosen name after review."
  (skip-unless (display-graphic-p))
  (let ((result (emacsvox-test--choice-interaction "C-e h q n o RET" nil t)))
    (should-not (plist-get result :failure))
    (should (eq (car (plist-get result :answer)) ?n))))

(ert-deftest emacsvox-choice-graphical-nested-prompts ()
  "Nested text and choice prompts restore the outer question on exit."
  (skip-unless (display-graphic-p))
  (dolist (modal '(nil t))
    (dolist (inner '("q n" "C-g"))
      (let* ((read-char-choice-use-read-key modal)
             (result (emacsvox-test--choice-interaction
                      (concat "C-e h <f7> d r a f t RET C-e h <f8> C-e h "
                              inner " C-e h C-e a q n")))
             (speech (mapcar #'car (plist-get result :speech))))
        (should-not (plist-get result :failure))
        (should (eq (car (plist-get result :answer)) ?n))
        (should (equal (plist-get result :nested)
                       (list (if (equal inner "C-g") 'cancelled '(?n "no")) "draft")))
        (should (cl-some (lambda (text) (string-prefix-p "Nested text:" text)) speech))
        (should (cl-some (lambda (text) (string-match-p "Inner explanation" text)) speech))
        (should (string-match-p "complete explanation"
                                (car (last speech (if modal 1 2)))))))))

(ert-deftest emacsvox-choice-repeat-copies-full-question ()
  "Repeat copies the current explanation even after unrelated messages."
  (let ((emacsvox--choice-context (list :depth 0 :text "Question\nFull explanation"))
        (emacsvox-last-message "Unrelated message")
        (kill-ring nil)
        spoken)
    (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
              ((symbol-function 'called-interactively-p) (lambda (&rest _) t)))
      (call-interactively #'emacsvox-speak-message-again))
    (should (equal spoken "Question\nFull explanation"))
    (should (equal (car kill-ring) spoken))))

(ert-deftest emacsvox-choice-graphical-disabled-command ()
  "Review or cancel a real disabled command without enabling it."
  (skip-unless (display-graphic-p))
  (require 'diff-mode)
  (require 'novice)
  (require 'emacsvox-keymap)
  (dolist (modal '(nil t))
    (dolist (keys '("C-e a C-e h C-n C-e l q n" "C-e h C-g" "SPC"))
      (save-window-excursion
        (let ((buffer (generate-new-buffer " *disabled diff test*"))
              (disabled (get 'diff-restrict-view 'disabled))
              (read-char-choice-use-read-key modal)
              (use-dialog-box nil)
              (emacsvox-speak-messages nil)
              speech)
          (unwind-protect
              (progn
                (switch-to-buffer buffer)
                (diff-mode)
                (insert "--- a/test\n+++ b/test\n@@ -1 +1 @@\n-old\n+new\n")
                (goto-char (point-min))
                (search-forward "-old")
                (put 'diff-restrict-view 'disabled t)
                (cl-letf (((symbol-function 'tts-speak)
                           (lambda (text) (push text speech)))
                          ((symbol-function 'tts-notify) #'ignore)
                          ((symbol-function 'emacsvox-icon) #'ignore))
                  (condition-case nil
                      (execute-kbd-macro (vconcat (kbd "C-c C-n") (kbd keys)))
                    (quit nil)))
                (should (eq (get 'diff-restrict-view 'disabled) t))
                (should (eq (buffer-narrowed-p) (equal keys "SPC")))
                (should (zerop (minibuffer-depth)))
                (should-not emacsvox--choice-context)
                (should (cl-some (lambda (text)
                                   (string-match-p "Restrict the view to the current hunk" text))
                                 speech)))
            (put 'diff-restrict-view 'disabled disabled)
            (kill-buffer buffer)))))))

(ert-deftest emacsvox-read-key-advice-caches-and-speaks-prompt ()
  "Key-reader advice preserves prompt caches and spoken feedback."
  (let ((emacsvox-speak-messages t)
        (emacsvox-last-message nil)
        (emacsvox-read-char-prompt-cache nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-read-key-before "Continue?"))
    (should (equal emacsvox-last-message "Continue?"))
    (should (equal emacsvox-read-char-prompt-cache "Continue?"))
    (should
     (equal
      (nreverse events)
      '((icon char) (speak "Continue?"))))))

(ert-deftest emacsvox-read-key-advice-respects-silenced-messages ()
  "A caller can suppress key-reader speech without losing prompt state."
  (let ((emacsvox-speak-messages nil)
        (emacsvox-last-message nil)
        (emacsvox-read-char-prompt-cache nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-read-key-before "Continue?"))
    (should (equal emacsvox-last-message "Continue?"))
    (should (equal emacsvox-read-char-prompt-cache "Continue?"))
    (should-not events)))

(defun emacsvox-test--read-password (keys &optional confirm default)
  "Read a synthetic password using KEYS, CONFIRM and DEFAULT.
Return the reader's result and the speech and stop events in order."
  (require 'auth-source)
  (let ((global-map (copy-keymap global-map))
        (read-passwd-map (copy-keymap read-passwd-map))
        (minibuffer-setup-hook '(emacsvox-minibuffer-setup-hook))
        (minibuffer-exit-hook nil)
        (pre-command-hook nil)
        (post-command-hook nil)
        (emacsvox-minibuffer-dictionary (make-hash-table :test #'equal))
        events result)
    ;; C-e is the Emacsvox prefix in the full test environment.
    (define-key read-passwd-map (kbd "C-a") #'move-beginning-of-line)
    (define-key read-passwd-map (kbd "C-e") #'move-end-of-line)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-stop)
               (lambda (&rest args) (push (cons 'stop args) events)))
              ((symbol-function 'tts-notify)
               (lambda (text &rest _) (push (list 'notify text) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-test--password-command)
               (lambda ()
                 (interactive)
                 (setq result
                       (read-passwd "Password for /sudo:root@localhost: "
                                    confirm default)))))
      (define-key global-map (kbd "C-c p")
                  #'emacsvox-test--password-command)
      (save-window-excursion
        (execute-kbd-macro (vconcat (kbd "C-c p") (kbd keys)))))
    (list result (nreverse events))))

(ert-deftest emacsvox-read-passwd-opening-and-navigation-preserve-prompt ()
  "An empty password prompt survives setup and navigation without dots."
  (pcase-let ((`(,result ,events)
               (emacsvox-test--read-password "C-a C-e RET")))
    (should (equal result ""))
    (should
     (equal (seq-take events 4)
            '((stop all) (icon open-object) (icon pwd)
              (speak "Password for /sudo:root@localhost: "))))
    ;; Ordinary navigation may read the prompt again, but masking must not
    ;; replace it with a dot or stop it after setup.
    (should
     (equal (seq-filter (lambda (event) (memq (car event) '(stop notify)))
                        events)
            '((stop all))))))

(ert-deftest emacsvox-read-passwd-edit-feedback-does-not-repeat-on-navigation ()
  "Typing and deletion produce masked feedback; intervening motion does not."
  (pcase-let ((`(,result ,events)
               (emacsvox-test--read-password "x C-a C-e DEL RET")))
    (should (equal result ""))
    (should
     (equal (seq-filter (lambda (event) (eq (car event) 'notify)) events)
            '((notify "dot") (notify "dot"))))))

(ert-deftest emacsvox-read-passwd-default-is-not-spoken ()
  "A default password is returned without being included in prompt speech."
  (pcase-let ((`(,result ,events)
               (emacsvox-test--read-password "RET" nil "synthetic-secret")))
    (should (equal result "synthetic-secret"))
    (should
     (equal (seq-filter (lambda (event) (memq (car event) '(speak notify)))
                        events)
            '((speak "Password for /sudo:root@localhost: "))))))

(ert-deftest emacsvox-read-passwd-confirmation-announces-each-prompt ()
  "Confirmation uses its own prompt and resets password edit tracking."
  (pcase-let ((`(,result ,events)
               (emacsvox-test--read-password "x RET x RET" t)))
    (should (equal result "x"))
    (should
     (equal (seq-filter (lambda (event) (memq (car event) '(speak notify))) events)
            '((speak "Password for /sudo:root@localhost: ")
              (notify "dot") (speak "Confirm password: ")
              (notify "dot"))))))

(ert-deftest emacsvox-read-passwd-character-feedback-respects-visibility ()
  "Password characters are masked in speech only while hidden."
  (with-temp-buffer
    (let ((last-input-event ?s)
          (this-command 'self-insert-command)
          events)
      (emacsvox--advice-read-passwd--hide-password-after)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-notify)
                 (lambda (text) (push (list 'notify text) events))))
        (let ((read-passwd--password-hidden t))
          (insert "s")
          (emacsvox--advice-read-passwd--hide-password-after))
        (let ((read-passwd--password-hidden nil))
          (insert "s")
          (emacsvox--advice-read-passwd--hide-password-after)))
      (should
       (equal
        (nreverse events)
        '((notify "dot")
          (icon repeat-active)
          (notify "s")
          (icon repeat-active)))))))

(ert-deftest emacsvox-read-passwd-emacs30-visibility-and-unknown-state ()
  "Emacs 30's state keeps hidden characters masked; unknown state stays hidden."
  (cl-progv '(read-passwd--password-hidden) nil
    (makunbound 'read-passwd--password-hidden)
    (dolist (hidden '(t nil))
      (with-temp-buffer
        (let ((read-passwd--hide-password hidden)
              (this-command 'self-insert-command)
              (last-input-event ?x) spoken)
          (emacsvox--advice-read-passwd--hide-password-after)
          (cl-letf (((symbol-function 'tts-notify)
                     (lambda (text) (setq spoken text)))
                    ((symbol-function 'emacsvox-icon) #'ignore))
            (insert "x")
            (emacsvox--advice-read-passwd--hide-password-after))
          (should (equal spoken (if hidden "dot" "x"))))))
    (cl-progv '(read-passwd--hide-password) nil
      (makunbound 'read-passwd--hide-password)
      (should (emacsvox--password-hidden-p)))))

(ert-deftest emacsvox-read-passwd-toggle-announces-visibility ()
  "Interactive password visibility changes announce their resulting state."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (dolist (hidden '(t nil))
        (let ((ems--interactive-fn-name 'read-passwd-toggle-visibility)
              (read-passwd--password-hidden hidden))
          (emacsvox--advice-read-passwd-toggle-visibility-after))))
    (should (equal (nreverse events) '(off on)))))

(ert-deftest emacsvox-long-question-preserves-call-and-positive-result ()
  "A long question cues a positive answer around exactly one call."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        (emacsvox--advice-yes-or-no-p-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'accepted)
         "Continue?")
        'accepted)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon ask-question)
        (original ("Continue?"))
        (icon yes-answer))))))

(ert-deftest emacsvox-short-question-preserves-negative-result ()
  "A short question cues a negative answer around exactly one call."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should-not
       (emacsvox--advice-y-or-n-p-around
        (lambda (&rest arguments)
          (cl-incf calls)
          (push (list 'original arguments) events)
          nil)
        "Continue?")))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon ask-short-question)
        (original ("Continue?"))
        (icon n-answer))))))

(ert-deftest emacsvox-lock-help-cue-remains-unconditional ()
  "Lock-conflict help always plays its help cue."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-ask-user-about-lock-help-after))
    (should (equal events '((icon help))))))

(provide 'emacsvox-input-tests)
;;; emacsvox-input-tests.el ends here
