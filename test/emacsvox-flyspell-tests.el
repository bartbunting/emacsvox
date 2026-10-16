;;; emacsvox-flyspell-tests.el --- Flyspell advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)
(require 'package)
(package-initialize)
(require 'flyspell)
(require 'message)
(load
 (expand-file-name "../lisp/emacsvox-flyspell.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-flyspell-defaults-to-native-completion ()
  "Flyspell correction uses the active standard completion frontend by default."
  (should (eq emacsvox-flyspell-correct 'flyspell-correct))
  (should (featurep 'flyspell-correct))
  (should
   (eq flyspell-correct-interface
       #'emacsvox-flyspell-correct-completing-read)))

(ert-deftest emacsvox-flyspell-native-interface-publishes-suggestion-count ()
  "The native correction interface exposes its bounded candidate context."
  (let (observed)
    (cl-letf (((symbol-function 'flyspell-correct-completing-read)
               (lambda (candidates word)
                 (setq observed
                       (list candidates word
                             emacsvox-flyspell--suggestion-count))
                 "corrected")))
      (should
       (equal
        (emacsvox-flyspell-correct-completing-read
         '("first" "second") "incorect") ; codespell:ignore incorect
        "corrected")))
    (should
     (equal observed '(("first" "second") "incorect" 2))))) ; codespell:ignore incorect

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
        (flyspell-correct-interface #'flyspell-correct-ido)
        (vertico-mode t)
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

(ert-deftest emacsvox-flyspell-native-completion-does-not-repeat-acceptance ()
  "Vertico-owned correction acceptance is not spoken again by Flyspell."
  (let ((ems--interactive-fn-name 'flyspell-correct-at-point)
        (flyspell-correct-interface
         #'emacsvox-flyspell-correct-completing-read)
        (vertico-mode t)
        events)
    (cl-letf (((symbol-function 'flyspell-get-word)
               (lambda (&rest _) '("corrected")))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-flyspell-correct-at-point-after))
    (should-not events)))

(ert-deftest emacsvox-flyspell-alternate-interface-keeps-fallback-feedback ()
  "An explicitly selected alternate correction interface retains feedback."
  (let ((ems--interactive-fn-name 'flyspell-correct-at-point)
        (flyspell-correct-interface #'flyspell-correct-ido)
        (vertico-mode t)
        events)
    (cl-letf (((symbol-function 'flyspell-get-word)
               (lambda (&rest _) '("corrected")))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-flyspell-correct-at-point-after))
    (should (equal events '((speak "corrected"))))))

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

(ert-deftest emacsvox-flyspell-typing-past-highlight-does-not-leak-voice ()
  "Completing a highlighted word leaves no voice on its newly typed suffix."
  (with-temp-buffer
    (insert "I'm presu")
    (let ((overlay (make-flyspell-overlay
                    5 (point-max) 'flyspell-incorrect 'highlight)))
      (should (eq (get-text-property 5 'personality) 'voice-bolden))
      ;; Ordinary typing inherits text properties, while Flyspell's overlay
      ;; deliberately excludes text inserted at its end.
      (insert-and-inherit "ming all ")
      (should (= (overlay-end overlay) 10))
      (flyspell-unhighlight-at 5)
      (should (equal (buffer-string) "I'm presuming all "))
      (should-not (overlays-in (point-min) (point-max)))
      (should-not (text-property-not-all
                   (point-min) (point-max) 'personality nil)))))

(ert-deftest emacsvox-flyspell-defers-optional-correction-advice ()
  (dolist (target emacsvox-flyspell--correct-targets)
    (should
     (fboundp (intern (format "emacsvox--advice-%s-after" target))))
    (when
        (and
         (featurep 'flyspell-correct)
         (fboundp target))
      (should
       (advice-member-p
        (intern (format "emacsvox--advice-%s-after" target))
        target)))))

(ert-deftest emacsvox-flyspell-correction-targets-cover-public-workflows ()
  "Direct, directional, DWIM, and region correction paths receive feedback."
  (should
   (equal
    emacsvox-flyspell--correct-targets
    '(flyspell-correct-next
      flyspell-correct-previous
      flyspell-correct-at-point
      flyspell-correct-wrapper
      flyspell-correct-region))))

(ert-deftest emacsvox-flyspell-hunspell-en-au-detects-known-error ()
  "The configured real spell checker marks a known Australian English error."
  (skip-unless (executable-find "hunspell"))
  (skip-unless
   (or (file-exists-p "/usr/share/hunspell/en_AU.dic")
       (file-exists-p "/usr/share/myspell/en_AU.dic")))
  (let ((ispell-program-name "hunspell")
        (ispell-dictionary "en_AU")
        (ispell-process nil))
    (unwind-protect
        (with-temp-buffer
          (text-mode)
          (insert "This is mispeled text.")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (flyspell-mode 1)
            (flyspell-buffer))
          (should
           (seq-some
            (lambda (overlay)
              (and
               (flyspell-overlay-p overlay)
               (equal
                (buffer-substring-no-properties
                 (overlay-start overlay) (overlay-end overlay))
                "mispeled")))
            (overlays-in (point-min) (point-max)))))
      (when (process-live-p ispell-process)
        (delete-process ispell-process)))))

(ert-deftest emacsvox-flyspell-reply-setup-marks-errors-without-cues ()
  "Notmuch reply construction stays quiet without disabling spell checking."
  (skip-unless (executable-find "hunspell"))
  (skip-unless (file-exists-p "/usr/share/hunspell/en_AU.dic"))
  (skip-unless (require 'notmuch-mua nil t))
  (let ((ispell-program-name "hunspell")
        (ispell-dictionary "en_AU")
        (ispell-process nil)
        (text-mode-hook (list (lambda () (flyspell-mode 1))))
        (message-mode-hook nil)
        (message-signature nil)
        (message-directory (make-temp-file "emacsvox-spelling-mail-" t))
        (notmuch-mua-user-agent-function nil)
        (notmuch-show-process-crypto nil)
        (notmuch-message-replied-tags nil)
        (flyspell-pre-buffer nil)
        (this-command 'notmuch-show-reply)
        icons)
    (unwind-protect
        (with-temp-buffer
          (cl-letf (((symbol-function 'emacsvox-icon)
                     (lambda (icon) (push icon icons)))
                    ((symbol-function 'notmuch-call-notmuch-sexp)
                     (lambda (&rest _)
                       '(:reply-headers
                         (:From "Tester <test@example.invalid>"
                          :To "Qzxv Qzxq <sender@example.invalid>"
                          :Subject "Re: I start to like Emacsvox")
                         :original
                         (:headers
                          (:From "Qzxv Qzxq <sender@example.invalid>"
                           :Date "Thu, 15 Oct 2026 12:42:28 +0200")))))
                    ((symbol-function 'notmuch-mua-pop-to-buffer)
                     (lambda (&rest _) (notmuch-message-mode)))
                    ((symbol-function 'notmuch-address-setup) #'ignore)
                    ((symbol-function 'notmuch-fcc-header-setup) #'ignore)
                    ((symbol-function 'notmuch-mua-maybe-set-window-dedicated)
                     #'ignore)
                    ((symbol-function 'notmuch-show-insert-body)
                     (lambda (&rest _)
                       (insert "Hello,\nEmacsvox helps me read mail.\n"))))
            (notmuch-mua-reply "synthetic-message")
            (should flyspell-mode)
            (should flyspell-changes)
            (should-not (memq 'help icons))
            (setq icons nil)
            (let ((text (buffer-string))
                  (position (point)))
              (flyspell-post-command-hook)
              (should-not icons)
              (should-not flyspell-changes)
              (should (= (point) position))
              (should (equal (buffer-substring-no-properties
                              (point-min) (point-max))
                             (substring-no-properties text)))
              (should (seq-some #'flyspell-overlay-p
                                (overlays-in (point-min) (point-max)))))))
      (when (process-live-p ispell-process) (delete-process ispell-process))
      (delete-directory message-directory t))))

(ert-deftest emacsvox-flyspell-editing-keeps-spelling-cues ()
  "Typing errors still cues in ordinary text and mail composition buffers."
  (skip-unless (executable-find "hunspell"))
  (skip-unless (file-exists-p "/usr/share/hunspell/en_AU.dic"))
  (let ((ispell-program-name "hunspell")
        (ispell-dictionary "en_AU")
        (ispell-process nil)
        (text-mode-hook nil)
        (message-mode-hook nil))
    (unwind-protect
        (dolist (mode '(text-mode message-mode))
          (with-temp-buffer
            (funcall mode)
            (when (eq mode 'message-mode)
              (insert "To: test@example.invalid\nSubject: Test\n"
                      mail-header-separator "\n\n"))
            (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
              (flyspell-mode 1))
            (should flyspell-mode)
            (let ((start (point))
                  (this-command 'newline)
                  (flyspell-incorrect-hook
                   (list #'emacsvox-flyspell--incorrect))
                  icons)
              (insert "mispeled")
              (flyspell-pre-command-hook)
              (insert "\n")
              ;; Multiple edits can queue the same word more than once.
              (setq flyspell-changes (make-list 4 (cons start (point))))
              (cl-letf (((symbol-function 'emacsvox-icon)
                         (lambda (icon) (push icon icons))))
                (flyspell-post-command-hook)
                (ert-info ((format "%s: initial edit" mode))
                  (should (equal icons '(help))))
                (should (seq-some #'flyspell-overlay-p
                                  (overlays-in start (point))))
                ;; A later edit must still announce a misspelling.
                (setq icons nil)
                (goto-char start)
                (delete-region start (point-max))
                (insert "mispeledx")
                (flyspell-pre-command-hook)
                (insert "\n")
                (flyspell-post-command-hook)
                (ert-info ((format "%s: subsequent edit" mode))
                  (should (equal icons '(help))))))))
      (when (process-live-p ispell-process) (delete-process ispell-process)))))

(ert-deftest emacsvox-flyspell-repeated-changes-cue-once-per-word ()
  "Interleaved checks of two errors give two cues, not one per queued change."
  (skip-unless (executable-find "hunspell"))
  (skip-unless (file-exists-p "/usr/share/hunspell/en_AU.dic"))
  (let ((ispell-program-name "hunspell")
        (ispell-dictionary "en_AU")
        (ispell-process nil)
        (text-mode-hook nil))
    (unwind-protect
        (with-temp-buffer
          (text-mode)
          (insert "mispeled qzxq\n")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (flyspell-mode 1))
          (let ((this-command 'newline)
                (flyspell-pre-point nil)
                icons)
            (cl-letf (((symbol-function 'emacsvox-icon)
                       (lambda (icon) (push icon icons))))
              (dotimes (_ 2)
                (setq icons nil
                      flyspell-changes '((1 . 9) (10 . 14) (1 . 9) (10 . 14)))
                (flyspell-post-command-hook)
                (should (equal icons '(help help)))))))
      (when (process-live-p ispell-process) (delete-process ispell-process)))))

(ert-deftest emacsvox-flyspell-reading-owns-post-command-cue ()
  "Reading a flagged word prevents a later cue from the real automatic checker."
  (skip-unless (executable-find "hunspell"))
  (skip-unless (file-exists-p "/usr/share/hunspell/en_AU.dic"))
  (let ((ispell-program-name "hunspell") (ispell-dictionary "en_AU")
        (ispell-process nil) (text-mode-hook nil) (message-mode-hook nil))
    (unwind-protect
        (with-temp-buffer
          (message-mode)
          (insert "To: test@example.invalid\nSubject: Test\n" mail-header-separator
                  "\n\nParham Doustdar <parham90@gmail.com> writes:\n> Hi Bart,\n")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (flyspell-mode 1)
            (flyspell-buffer))
          (goto-char (point-min))
          (search-forward "> Hi Bart,")
          (beginning-of-line)
          (setq flyspell-changes nil)
          (let ((this-command 'previous-line) icons)
            (flyspell-pre-command-hook)
            (forward-line -1)
            (let ((text (emacsvox-flyspell--annotate
                         (emacsvox-aural-source-substring
                          (line-beginning-position) (line-end-position)))))
              (should (get-text-property 0 emacsvox-aural-positioned-facts-property text)))
            (cl-letf (((symbol-function 'emacsvox-icon) (lambda (icon) (push icon icons))))
              (flyspell-post-command-hook))
            (should-not icons)))
      (when (process-live-p ispell-process) (delete-process ispell-process)))))

(ert-deftest emacsvox-flyspell-navigation-does-not-repeat-known-error ()
  "Leaving an unchanged flagged word keeps highlighting without an edit cue."
  (skip-unless (executable-find "hunspell"))
  (skip-unless (file-exists-p "/usr/share/hunspell/en_AU.dic"))
  (let ((ispell-program-name "hunspell") (ispell-dictionary "en_AU")
        (ispell-process nil) (text-mode-hook nil)
        (emacsvox-use-icons t) (emacsvox-flyspell-use-tone t)
        (emacsvox-flyspell-use-earcon nil))
    (unwind-protect
        (with-temp-buffer
          (text-mode)
          (insert "This is mispeled.\n\n")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (flyspell-mode 1)
            (flyspell-buffer))
          (let ((this-command 'next-line) cues checked)
            (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
                       (lambda (&rest args) (push args cues))))
              ;; Invalidate Flyspell's single-word cache by checking elsewhere.
              (goto-char (point-min))
              (flyspell-word)
              (setq flyspell-changes nil)
              (goto-char 13)
              (flyspell-pre-command-hook)
              (forward-line 1)
              (emacsvox-flyspell--clear-read-errors)
              (let ((flyspell-incorrect-hook
                     (cons (lambda (start end _)
                             (push (cons start end) checked) nil)
                           flyspell-incorrect-hook)))
                (flyspell-post-command-hook))
              (should checked)
              (should-not cues)
              (should (bolp))
              (should (eolp))
              (should (seq-some #'flyspell-overlay-p (overlays-at 13)))
              ;; Reading the flagged word still carries its positioned tone.
              (let ((text (emacsvox-flyspell--annotate
                           (emacsvox-aural-source-substring 9 17))))
                (should (plist-get
                         (car (get-text-property
                               0 emacsvox-aural-positioned-facts-property text))
                         :spelling-tone)))
              ;; A new edit to that word must still produce detection feedback.
              (emacsvox-flyspell--clear-read-errors)
              (goto-char 16)
              (flyspell-pre-command-hook)
              (insert "x")
              (let ((this-command 'self-insert-command)
                    (flyspell-delay 0))
                (flyspell-post-command-hook))
              (should (= 1 (length cues)))
              (should (eq (plist-get (car cues) :occasion) 'edit))
              ;; A first detection during navigation remains useful feedback.
              (setq cues nil)
              (flyspell-delete-all-overlays)
              (goto-char (point-min))
              (flyspell-word)
              (setq flyspell-changes nil)
              (goto-char 13)
              (flyspell-pre-command-hook)
              (forward-line 1)
              (flyspell-post-command-hook)
              (should (= 1 (length cues))))))
      (when (process-live-p ispell-process) (delete-process ispell-process)))))

(ert-deftest emacsvox-flyspell-character-cues-follow-word-entry ()
  "Character movement cues the entered word, never its following space."
  (skip-unless (executable-find "hunspell"))
  (skip-unless (file-exists-p "/usr/share/hunspell/en_AU.dic"))
  (let ((ispell-program-name "hunspell") (ispell-dictionary "en_AU")
        (ispell-process nil) (text-mode-hook nil) (emacsvox-use-icons t))
    (unwind-protect
        (with-temp-buffer
          (text-mode)
          (insert "a mispeled z\n")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (flyspell-mode 1)
            (flyspell-buffer))
          (dolist (tone '(t nil))
            (let ((emacsvox-flyspell-use-tone tone)
                  (emacsvox-flyspell-use-earcon (not tone)) cues)
              (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
                         (lambda (&rest _) (push (point) cues)))
                        ((symbol-function 'emacsvox-icon)
                         (lambda (icon) (when (eq icon 'help) (push (point) cues))))
                        ((symbol-function 'tts-letter) #'ignore)
                        ((symbol-function 'tts-speak) #'ignore)
                        ((symbol-function 'tts-stop) #'ignore))
                (dolist (step '((2 forward-char 3 t) (3 forward-char 4 nil)
                                (10 forward-char 11 nil) (12 backward-char 11 nil)
                                (11 backward-char 10 t) (10 backward-char 9 nil)
                                (3 backward-char 2 nil) (2 right-char 3 t)
                                (12 left-char 11 nil) (11 left-char 10 t)))
                  ;; Make the checker revisit the word instead of using its cache.
                  (goto-char 12)
                  (flyspell-word)
                  (setq cues nil flyspell-changes nil)
                  (goto-char (nth 0 step))
                  (let ((this-command (nth 1 step)))
                    (emacsvox-flyspell--clear-read-errors)
                    (flyspell-pre-command-hook)
                    (call-interactively this-command)
                    (flyspell-post-command-hook))
                  (ert-info ((format "tone %S, step %S" tone step))
                    (should (= (point) (nth 2 step)))
                    (should (equal cues (when (nth 3 step) (list (nth 2 step))))))))))
          (should (equal (buffer-substring-no-properties (point-min) (point-max))
                         "a mispeled z\n")))
      (when (process-live-p ispell-process) (delete-process ispell-process)))))

(provide 'emacsvox-flyspell-tests)
