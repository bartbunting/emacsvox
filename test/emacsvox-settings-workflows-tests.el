;;; emacsvox-settings-workflows-tests.el --- Linked workflow tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Check real editor return and captured source ownership.
;;; Code:
(require 'emacsvox-settings-tests)
(require 'emacsvox-settings-workflows)
(require 'emacsvox-settings-integrations)
(require 'emacsvox-settings-changes)
(require 'emacsvox-aural-voice-editor-tests)
(require 'emacsvox-aural-change-feedback-tests)

(ert-deftest emacsvox-settings-context-shortcut-and-return ()
  "The real prefix binding captures the current buffer and q closes its menu."
  (require 'emacsvox-keymap)
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "C-q"))
    (should (eq (lookup-key emacsvox-keymap (kbd "S")) 'emacsvox-settings-for-buffer))
    (dolist (mode '(text-mode comint-mode))
      (with-current-buffer source (funcall mode))
      (execute-kbd-macro (kbd "C-e S"))
      (should (eq (oref transient--prefix command)
                  (if (eq mode 'comint-mode) 'emacsvox-settings-integrations--comint
                    'emacsvox-settings-buffer)))
      (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
      (execute-kbd-macro (kbd "q"))
      (should-not transient--prefix)
      (should-not transient--stack)
      (should (eq (current-buffer) source)))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-workflows-feedback-draft-return ()
  "A guided draft previews without saving and returns to its exact menu entry."
  (emacsvox-test--with-settings
    (let* ((facts '(:role heading :content "Example heading"))
           (context '(:mode org-mode :occasion navigation))
           (render (emacsvox-aural-resolve-active facts context))
           (concrete (emacsvox-aural-compile-plan render facts context))
           editor)
      (cl-letf (((symbol-function 'emacsvox-aural-tools--remap-source-input)
                 (lambda (&optional _)
                   (list :source source :facts facts :context context :render render :concrete concrete))))
        (execute-kbd-macro (kbd "f c")))
      (setq editor (current-buffer))
      (unwind-protect
          (progn
            (should (derived-mode-p 'emacsvox-aural-change-feedback-mode))
            (emacsvox-test--guided-choose "Change the content voice" "bolden")
            (should (emacsvox-test--guided-proposed))
            (should-not emacsvox-aural-user-rules)
            (execute-kbd-macro (kbd "q q q"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-feedback))
            (with-selected-window transient--window
              (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                          'emacsvox-settings-workflows--change)))
            (should (buffer-local-value 'emacsvox-aural-change-feedback-render editor))
            (execute-kbd-macro (kbd "q q"))
            (should (eq (current-buffer) source))
            (should (= (point) 3)))
        (when (buffer-live-p editor) (kill-buffer editor))))))

(ert-deftest emacsvox-settings-workflows-reject-replaced-item ()
  "Captured-item editing rejects replaced source content before opening a draft."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "f"))
    (with-current-buffer source (erase-buffer) (insert "replacement"))
    (should-error (emacsvox-settings-workflows--change) :type 'user-error)))
(ert-deftest emacsvox-settings-workflows-rule-scopes-and-return ()
  "Each rule route owns its advertised scope and returns to its exact entry."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "r"))
    (dolist (entry '(("p" personal emacsvox-settings-workflows--personal)
                     ("s" session emacsvox-settings-workflows--session)
                     ("b" buffer emacsvox-settings-workflows--buffer)))
      (execute-kbd-macro (kbd (car entry)))
      (should (derived-mode-p 'emacsvox-aural-scheme-editor-mode))
      (should (eq emacsvox-aural-editor-scope (cadr entry)))
      (should (eq emacsvox-aural-editor-target source))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-presentation))
      (with-selected-window transient--window
        (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                    (nth 2 entry)))))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-workflows-face-save-is-explicit ()
  "Face feedback changes immediately; only the explicit save writes Customize."
  (emacsvox-test--with-settings
    (let ((emacsvox-aural-face-presentation-enabled t))
      (execute-kbd-macro (kbd "r v"))
      (should-not emacsvox-aural-face-presentation-enabled)
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "w"))
      (should (file-exists-p custom-file))
      (with-temp-buffer
        (insert-file-contents custom-file)
        (should (search-forward "emacsvox-aural-face-presentation-enabled nil" nil t))))))

(ert-deftest emacsvox-settings-workflows-setups-return-without-activation ()
  "Opening profile and palette managers changes no setup or persistent data."
  (emacsvox-test--with-settings
    (let ((before (emacsvox-aural-read-user-data)))
      (execute-kbd-macro (kbd "p p"))
      (should (derived-mode-p 'emacsvox-aural-profiles-mode))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-setups))
      (execute-kbd-macro (kbd "v"))
      (should (derived-mode-p 'emacsvox-aural-voice-palettes-mode))
      (should (eq (key-binding (kbd "i")) 'emacsvox-aural-voice-palettes-import))
      (should (eq (key-binding (kbd "w")) 'emacsvox-aural-voice-palettes-export))
      (should (eq (key-binding (kbd "W")) 'emacsvox-aural-voice-palettes-backup))
      (should (eq (key-binding (kbd "R")) 'emacsvox-aural-voice-palettes-reset-entry))
      (execute-kbd-macro (kbd "q"))
      (with-selected-window transient--window
        (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                    'emacsvox-settings-workflows--palettes)))
      (should (equal before (emacsvox-aural-read-user-data)))
      (should-not (file-exists-p custom-file)))))

(ert-deftest emacsvox-settings-workflows-draft-home-return ()
  "The draft route opens the actual Home row and returns to Saved setups."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "p d"))
    (should (derived-mode-p 'emacsvox-aural-home-mode))
    (should (eq (tabulated-list-get-id) 'drafts))
    (should (eq (emacsvox-aural-inspection-source-buffer) source))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-setups))
    (with-selected-window transient--window
      (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                  'emacsvox-settings-workflows--drafts)))))

(ert-deftest emacsvox-settings-integrations-comint-is-local ()
  "The terminal control uses the captured buffer and cannot save a global default."
  (emacsvox-test--with-settings
    (require 'emacsvox-comint)
    (let ((before (default-value 'emacsvox-comint-autospeak)))
      (with-current-buffer source (comint-mode) (setq-local emacsvox-comint-autospeak nil))
      (execute-kbd-macro (kbd "j s"))
      (should (buffer-local-value 'emacsvox-comint-autospeak source))
      (should (eq before (default-value 'emacsvox-comint-autospeak)))
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "q q"))
      (should (eq (current-buffer) source)))))

(ert-deftest emacsvox-settings-integrations-customize-and-context ()
  "Integration discovery uses the actual source and returns from its Custom group."
  (emacsvox-test--with-settings
    (require 'org)
    (with-current-buffer source (org-mode))
    (execute-kbd-macro (kbd ". j"))
    (should (eq (emacsvox-settings-integrations--kind) 'org))
    (execute-kbd-macro (kbd "c"))
    (should (derived-mode-p 'Custom-mode))
    (should (save-excursion (goto-char (point-min))
                           (search-forward "Table After Movement Function" nil t)))
    (execute-kbd-macro (kbd "q q"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-buffer))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-comint-menu-navigation ()
  "Arrows speak current values; Enter changes only the captured shell buffer."
  (emacsvox-test--with-settings
    (require 'emacsvox-comint)
    (let ((autospeak-default (default-value 'emacsvox-comint-autospeak))
          (monitor-default (default-value 'emacsvox-comint-output-monitor))
          (other (generate-new-buffer " *other-comint*"))
          spoken)
      (unwind-protect
          (progn
            (with-current-buffer other
              (comint-mode)
              (setq-local emacsvox-comint-autospeak nil
                          emacsvox-comint-output-monitor nil))
            (with-current-buffer source
              (shell-mode)
              (setq-local emacsvox-comint-autospeak nil
                          emacsvox-comint-output-monitor nil))
            (cl-letf (((symbol-function 'emacsvox-aural-submit)
                       (lambda (text &rest _) (when (stringp text) (push text spoken)))))
              (execute-kbd-macro (kbd ". j c"))
              (should (eq (oref transient--prefix command)
                          'emacsvox-settings-integrations--comint))
              (should (seq-some (lambda (text) (string-match-p "this buffer, temporary" text)) spoken))
              (should-not (buffer-local-value 'emacsvox-comint-autospeak source))
              (with-selected-window transient--window
                (transient--goto-button
                 (transient-suffix-object 'emacsvox-settings-integrations--comint-autospeak)))
              (setq spoken nil)
              (execute-kbd-macro (kbd "<down>"))
              (should (string-match-p "Background monitoring.*off.*b" (car spoken)))
              (should-not (buffer-local-value 'emacsvox-comint-output-monitor source))
              (execute-kbd-macro (kbd "RET"))
              (should (buffer-local-value 'emacsvox-comint-output-monitor source))
              (should-not (buffer-local-value 'emacsvox-comint-autospeak source))
              (execute-kbd-macro (kbd "<up>"))
              (should (string-match-p "Automatic output speech: off.*s" (car spoken)))
              (execute-kbd-macro (kbd "RET"))
              (should (buffer-local-value 'emacsvox-comint-autospeak source))
              (execute-kbd-macro (kbd "<down>"))
              (should (string-match-p "Background monitoring.*on.*b" (car spoken))))
            (should (eq autospeak-default (default-value 'emacsvox-comint-autospeak)))
            (should (eq monitor-default (default-value 'emacsvox-comint-output-monitor)))
            (should-not (buffer-local-value 'emacsvox-comint-autospeak other))
            (should-not (buffer-local-value 'emacsvox-comint-output-monitor other))
            (should-not (file-exists-p custom-file))
            (execute-kbd-macro (kbd "q"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations))
            (with-selected-window transient--window
              (should (equal (oref (button-get (button-at (point)) 'button-data) key) "c")))
            (execute-kbd-macro (kbd "q q q"))
            (should (eq (current-buffer) source))
            (should (= (point) 3)))
        (kill-buffer other)))))

(ert-deftest emacsvox-settings-integrations-comint-chooser-and-cancel ()
  "The chooser preserves the source and returns to its entry, including cancel."
  (emacsvox-test--with-settings
    (require 'emacsvox-comint)
    (with-current-buffer source
      (comint-mode)
      (setq-local emacsvox-comint-autospeak nil emacsvox-comint-output-monitor nil))
    (execute-kbd-macro (kbd "j a S h e l l / c o m i n t RET"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--comint))
    (should-not (buffer-local-value 'emacsvox-comint-output-monitor source))
    (let ((current-prefix-arg '(4))
          (before (default-value 'emacsvox-comint-output-monitor))
          (tts-speaker-process (make-pipe-process :name "comint-menu-test" :noquery t))
          synced)
      (unwind-protect
          (cl-letf (((symbol-function 'tts--protocol-sync)
                     (lambda () (setq synced (current-buffer)))))
            (emacsvox-settings-integrations--comint-monitor)
            (should (eq synced source))
            (should (eq before (default-value 'emacsvox-comint-output-monitor))))
        (delete-process tts-speaker-process)))
    (should (buffer-local-value 'emacsvox-comint-output-monitor source))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations))
    (with-selected-window transient--window
      (should (equal (oref (button-get (button-at (point)) 'button-data) key) "a")))
    (condition-case nil (execute-kbd-macro (kbd "a C-g")) (quit nil))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations))
    (with-selected-window transient--window
      (should (equal (oref (button-get (button-at (point)) 'button-data) key) "a")))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-comint-unavailable ()
  "Discovery outside Comint explains the missing source without changing it."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "j"))
    (should (string-match-p "use a to choose" (emacsvox-settings-integrations--current-label)))
    (execute-kbd-macro (kbd "a S h e l l / c o m i n t RET"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--comint))
    (let ((text (emacsvox-transient--choice-text
                 (transient-suffix-object 'emacsvox-settings-integrations--comint-autospeak))))
      (should (string-match-p "open from a shell or Comint buffer" text))
      (should (string-match-p "Unavailable" text)))
    (should-error (emacsvox-settings-integrations--comint-autospeak) :type 'user-error)
    (should-error (emacsvox-settings-integrations--comint-monitor) :type 'user-error)
    (should-not (local-variable-p 'emacsvox-comint-autospeak source))
    (should-not (local-variable-p 'emacsvox-comint-output-monitor source))
    (execute-kbd-macro (kbd "q q q"))
    (should (eq (current-buffer) source))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-comint-search ()
  "Search selects a shell control without activating it and preserves its source."
  (emacsvox-test--with-settings
    (require 'emacsvox-comint)
    (with-current-buffer source
      (comint-mode)
      (setq-local emacsvox-comint-autospeak nil emacsvox-comint-output-monitor nil))
    (execute-kbd-macro (kbd "/ m o n i t o r i n g RET"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--comint))
    (with-selected-window transient--window
      (should (equal (oref (button-get (button-at (point)) 'button-data) key) "b")))
    (should-not (buffer-local-value 'emacsvox-comint-output-monitor source))
    (execute-kbd-macro (kbd "RET"))
    (should (buffer-local-value 'emacsvox-comint-output-monitor source))
    (should-not (buffer-local-value 'emacsvox-comint-autospeak source))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (with-selected-window transient--window
      (should (equal (oref (button-get (button-at (point)) 'button-data) key) "/")))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-all-and-unavailable-control ()
  "All integrations is usable outside an integration; unrelated controls refuse."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "j"))
    (should-not (emacsvox-settings-integrations--control-p))
    (should-error (emacsvox-settings-integrations--control) :type 'user-error)
    (execute-kbd-macro (kbd "a O r g SPC t a b l e s RET"))
    (should (derived-mode-p 'Custom-mode))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-eat-local-controls ()
  "EAT controls speak their values and preserve local lifecycle and independence."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (emacsvox-test--with-settings
    (with-current-buffer source
      (eat-mode)
      (setq-local emacsvox-eat-autospeak t
                  emacsvox-eat-monitor-background-output nil
                  emacsvox-eat-prompt-feedback 'earcon
                  emacsvox-eat-verbosity 'normal))
    (let ((defaults (mapcar #'default-value emacsvox-settings-integrations--eat-options))
          (discard (symbol-function 'emacsvox-eat--discard-automatic-feedback))
          discarded spoken)
      (cl-letf (((symbol-function 'emacsvox-eat--discard-automatic-feedback)
                 (lambda () (push (current-buffer) discarded) (funcall discard)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (when (stringp text) (push text spoken)))))
        (execute-kbd-macro (kbd ". j c"))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat))
        (should (seq-some (lambda (text) (string-match-p "captured terminal, local changes" text)) spoken))
        (with-selected-window transient--window
          (transient--goto-button
           (transient-suffix-object 'emacsvox-settings-integrations--eat-autospeak)))
        (setq discarded nil)
        (execute-kbd-macro (kbd "RET"))
        (should (memq source discarded))
        (should-not (buffer-local-value 'emacsvox-eat-autospeak source))
        (execute-kbd-macro (kbd "<down>"))
        (should (string-match-p "Background cues and unread count: off.*b" (car spoken)))
        (execute-kbd-macro (kbd "RET"))
        (should (buffer-local-value 'emacsvox-eat-monitor-background-output source))
        (with-current-buffer source (setq emacsvox-eat--unread-output-count 3))
        (execute-kbd-macro (kbd "b"))
        (should (zerop (buffer-local-value 'emacsvox-eat--unread-output-count source)))
        (execute-kbd-macro (kbd "<down>"))
        (should (string-match-p "Prompt feedback.*ready cue.*p" (car spoken)))
        (execute-kbd-macro (kbd "RET"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'text))
        (execute-kbd-macro (kbd "p"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'silent))
        (execute-kbd-macro (kbd "p"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'earcon))
        (execute-kbd-macro (kbd "<down>"))
        (should (string-match-p "Automatic feedback detail: normal.*d" (car spoken)))
        (execute-kbd-macro (kbd "RET"))
        (should (eq (buffer-local-value 'emacsvox-eat-verbosity source) 'verbose)))
      (should (equal defaults (mapcar #'default-value emacsvox-settings-integrations--eat-options)))
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "q"))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "c")))
      (execute-kbd-macro (kbd "q q q"))
      (should (eq (current-buffer) source)))))

(ert-deftest emacsvox-settings-integrations-eat-save-is-explicit ()
  "Only Save persists the terminal's four choices, retaining other local overrides."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (emacsvox-test--with-settings
    (let* ((options emacsvox-settings-integrations--eat-options)
           (defaults (mapcar (lambda (option) (cons option (default-value option))) options))
           (properties (mapcar (lambda (option) (cons option (copy-tree (symbol-plist option)))) options))
           (other (generate-new-buffer " *other-eat-settings*")))
      (unwind-protect
          (progn
            (with-current-buffer source
              (eat-mode)
              (setq-local emacsvox-eat-autospeak nil
                          emacsvox-eat-monitor-background-output t
                          emacsvox-eat-prompt-feedback 'text
                          emacsvox-eat-verbosity 'verbose))
            (with-current-buffer other
              (eat-mode)
              (setq-local emacsvox-eat-autospeak t
                          emacsvox-eat-monitor-background-output nil
                          emacsvox-eat-prompt-feedback 'silent
                          emacsvox-eat-verbosity 'terse))
            (execute-kbd-macro (kbd "j a E A T SPC t e r m i n a l s RET"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat))
            (should-not (file-exists-p custom-file))
            (execute-kbd-macro (kbd "w"))
            (should (equal (mapcar #'default-value options) '(nil t text verbose)))
            (should (equal (mapcar (lambda (option) (buffer-local-value option other)) options)
                           '(t nil silent terse)))
            (should (file-exists-p custom-file))
            ;; Reload the saved defaults after replacing them, as on startup.
            (dolist (entry defaults) (set-default (car entry) (cdr entry)))
            (load custom-file nil t)
            (should (equal (mapcar #'default-value options) '(nil t text verbose)))
            (execute-kbd-macro (kbd "q"))
            (with-selected-window transient--window
              (should (equal (oref (button-get (button-at (point)) 'button-data) key) "a"))))
        (kill-buffer other)
        (dolist (entry defaults) (set-default (car entry) (cdr entry)))
        (dolist (entry properties) (setplist (car entry) (cdr entry)))))))

(ert-deftest emacsvox-settings-integrations-eat-review-and-stale-source ()
  "Frozen review controls the terminal; stale sources cannot change review values."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (emacsvox-test--with-settings
    (let ((terminal (generate-new-buffer " *eat-settings-source*")))
      (unwind-protect
          (progn
            (with-current-buffer terminal
              (eat-mode)
              (setq-local emacsvox-eat-autospeak t
                          emacsvox-eat-prompt-feedback 'earcon))
            (with-current-buffer source
              (emacsvox-eat-review-mode)
              (setq-local emacsvox-eat-review--source-buffer terminal))
            (execute-kbd-macro (kbd "j c s p"))
            (should-not (buffer-local-value 'emacsvox-eat-autospeak terminal))
            (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback terminal) 'text))
            (should-not (local-variable-p 'emacsvox-eat-prompt-feedback source))
            (kill-buffer terminal)
            (should-not (emacsvox-settings-integrations--eat-p))
            (should-error (emacsvox-settings-integrations--eat-prompt) :type 'user-error)
            (should-error (emacsvox-settings-integrations--eat-save) :type 'user-error)
            (execute-kbd-macro (kbd "q q q"))
            (should (eq (current-buffer) source))
            (should-not (file-exists-p custom-file)))
        (when (buffer-live-p terminal) (kill-buffer terminal))))))

(ert-deftest emacsvox-settings-integrations-eat-search-and-advanced ()
  "Search selects without acting; advanced Customize returns to the EAT entry."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (emacsvox-test--with-settings
    (with-current-buffer source
      (eat-mode)
      (setq-local emacsvox-eat-prompt-feedback 'earcon))
    (execute-kbd-macro (kbd "/ E A T SPC p r o m p t RET"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat))
    (with-selected-window transient--window
      (should (equal (oref (button-get (button-at (point)) 'button-data) key) "p")))
    (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'earcon))
    (execute-kbd-macro (kbd "A"))
    (should (derived-mode-p 'Custom-mode))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat))
    (with-selected-window transient--window
      (should (equal (oref (button-get (button-at (point)) 'button-data) key) "A")))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-eat-unavailable ()
  "Outside EAT, local controls and Save explain the required terminal context."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "j a E A T SPC t e r m i n a l s RET"))
    (should-not (emacsvox-settings-integrations--eat-p))
    (let ((text (emacsvox-transient--choice-text
                 (transient-suffix-object 'emacsvox-settings-integrations--eat-autospeak))))
      (should (string-match-p "open from a live EAT terminal or its review" text))
      (should (string-match-p "Unavailable" text)))
    (should-error (emacsvox-settings-integrations--eat-autospeak) :type 'user-error)
    (should-error (emacsvox-settings-integrations--eat-save) :type 'user-error)
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-integrations-eat-embedded-eshell ()
  "An active Eshell EAT terminal gets the same local controls."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (emacsvox-test--with-settings
    (with-current-buffer source
      (setq major-mode 'eshell-mode)
      (setq-local eat-terminal (eat-term-make source (point-min))
                  emacsvox-eat-autospeak t))
    (unwind-protect
        (progn
          (execute-kbd-macro (kbd "j c s"))
          (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat))
          (should-not (buffer-local-value 'emacsvox-eat-autospeak source))
          (with-current-buffer source (eat-term-delete eat-terminal))
          (should-not (emacsvox-settings-integrations--eat-p))
          (should-error (emacsvox-settings-integrations--eat-autospeak) :type 'user-error)
          (should-not (file-exists-p custom-file)))
      (with-current-buffer source
        (when (eat-term-live-p eat-terminal) (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-settings-changes-separates-local-default-saved-and-draft ()
  "The snapshot distinguishes three option values and an unsaved cue without writes."
  (emacsvox-test--with-settings
    (let* ((symbol 'emacsvox-test-changed-setting)
           (old-plist (symbol-plist symbol))
           (emacsvox-line-cues--drafts (make-hash-table :test #'eq))
           before)
      (unwind-protect
          (progn
            (put symbol 'custom-type 'integer)
            (put symbol 'standard-value '(0))
            (customize-save-variable symbol 3)
            (set-default symbol 5)
            (with-current-buffer source (set (make-local-variable symbol) 7))
            (setq before (with-temp-buffer (insert-file-contents custom-file) (buffer-string)))
            (puthash 'boundary '(:initial bundled :value silent) emacsvox-line-cues--drafts)
            (execute-kbd-macro (kbd "d"))
            (should (derived-mode-p 'emacsvox-settings-changes-mode))
            (should (eq emacsvox-settings-changes--source source))
            (let ((row (cadr (assq symbol tabulated-list-entries))))
              (should (equal (aref row 1) "7"))
              (should (equal (aref row 2) "5"))
              (should (equal (aref row 3) "3"))
              (should (string-match-p "Buffer override; default changed" (aref row 4))))
            (should (assoc '(emacsvox-line-cues--drafts boundary) tabulated-list-entries))
            (emacsvox-aural-ui-goto-row symbol)
            (execute-kbd-macro (kbd "g"))
            (should (eq (tabulated-list-get-id) symbol))
            (should (equal before (with-temp-buffer (insert-file-contents custom-file) (buffer-string))))
            (should (eq (plist-get (gethash 'boundary emacsvox-line-cues--drafts) :value) 'silent))
            (execute-kbd-macro (kbd "q"))
            (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
            (with-selected-window transient--window
              (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                          'emacsvox-settings-changes))))
        (with-current-buffer source (kill-local-variable symbol))
        (makunbound symbol)
        (setplist symbol old-plist)))))

(ert-deftest emacsvox-settings-changes-speech-and-saved-nil ()
  "Saved nil is distinct from no save, and row speech names each scope."
  (emacsvox-test--with-settings
    (let* ((symbol (make-symbol "emacsvox-test-saved-nil")) heard)
      (put symbol 'saved-value '(nil))
      (should (equal "nil" (emacsvox-settings-changes--saved symbol)))
      (put symbol 'saved-value nil)
      (should (equal "No Customize save" (emacsvox-settings-changes--saved symbol)))
      (execute-kbd-macro (kbd ". d"))
      (let ((row (tabulated-list-get-entry)))
        (cl-letf (((symbol-function 'emacsvox-aural-ui-speak) (lambda (text) (setq heard text))))
          (emacsvox-settings-changes--speak))
        (should (string-match-p (regexp-quote (aref row 0)) heard))
        (should (string-match-p "Current:.*Global default:.*Saved startup or draft baseline:" heard)))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-buffer))
      (should-not (file-exists-p custom-file)))))

(ert-deftest emacsvox-settings-changes-retained-voice-status-is-read-only ()
  "A pending voice draft is reported through its owning status without saving it."
  (emacsvox-test--with-voice-editor
    (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
    (emacsvox-aural-voice-editor--put :automatic-sample nil)
    (emacsvox-aural-voice-editor--set 'average-pitch 7)
    (let* ((before (emacsvox-aural-read-user-data))
           (draft (emacsvox-aural-voice-editor--draft))
           (working (copy-tree (emacsvox-aural-voice-draft-working draft)))
           (row (assoc '(draft "Voice bolden in reading-owned") (emacsvox-settings-changes--drafts))))
      (should row)
      (should (equal (aref (cadr row) 4) (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))
      (should (equal working (emacsvox-aural-voice-draft-working draft)))
      (should (equal before (emacsvox-aural-read-user-data)))
      (should-not requests)
      (should-not callbacks))))

(provide 'emacsvox-settings-workflows-tests)
;;; emacsvox-settings-workflows-tests.el ends here
