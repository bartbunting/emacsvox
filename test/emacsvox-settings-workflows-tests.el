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

(ert-deftest emacsvox-settings-workflows-task-section-targets ()
  "Section arrows name their task and select its first action without applying."
  (emacsvox-test--with-settings
    (dolist (style '(continuous section-wrap section-stop))
      (let ((emacsvox-transient-navigation-style style)
            (emacsvox-transient-section-announcement-order 'by-movement)
            speech)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (push text speech))))
          (dolist (case '(("s p" 2 "Pronunciation editing" "e" emacsvox-aural-menu--pronunciations)
                          ("o" 2 "Output routing" "n" emacsvox-output-settings)
                          ("r" 1 "Feedback rules: save inside each editor" "o" emacsvox-settings-workflows--overrides)
                          ("j" 2 "Finish" "q" transient-quit-one)))
            (execute-kbd-macro (kbd (car case)))
            (dotimes (_ (nth 1 case)) (execute-kbd-macro (kbd "<right>")))
            (should (string-prefix-p (concat (nth 2 case) ".") (car speech)))
            (with-selected-window transient--window
              (let ((suffix (button-get (button-at (point)) 'button-data)))
                (should (equal (oref suffix key) (nth 3 case)))
                (should (eq (oref suffix command) (nth 4 case)))))
            (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
            (should-not (file-exists-p custom-file))
            (execute-kbd-macro (kbd "C-q <f8>"))))))))

(ert-deftest emacsvox-settings-editors-open-settings-with-source ()
  "Editor h opens Transient with the captured item, never the old Home buffer."
  (emacsvox-test--with-settings
    (dolist (path '("D d" "r h" "r o" "r s" "p p" "v p" "o p"))
      (execute-kbd-macro (kbd path))
      (should (emacsvox-aural-ui-interface-buffer-p))
      (let ((editor (current-buffer)))
        (should (eq (key-binding (kbd "h")) 'emacsvox-aural-menu))
        (cl-letf (((symbol-function 'emacsvox-aural)
                   (lambda () (interactive) (error "Unexpected Home entry"))))
          (execute-kbd-macro (kbd "h")))
        (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
        (let ((context (emacsvox-aural-menu--context)))
          (should (eq (plist-get context :source) source))
          (should (= (plist-get context :position) 3)))
        (execute-kbd-macro (kbd "q"))
        (should (eq (current-buffer) editor))
        (execute-kbd-macro (kbd "q"))
        (should
         (eq (oref transient--prefix command)
             (cdr (assoc (substring path 0 1)
                         '(("D" . emacsvox-settings-diagnostics)
                           ("r" . emacsvox-settings-presentation)
                           ("p" . emacsvox-settings-setups)
                           ("v" . emacsvox-aural-menu-voices)
                           ("o" . emacsvox-aural-menu-sounds))))))
        ;; Re-enter from the original source for the next independent route.
        (when transient--prefix (execute-kbd-macro (kbd "C-q")))
        (switch-to-buffer source)
        (execute-kbd-macro (kbd "<f8>"))))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-diagnostics-inspect-and-return ()
  "Reports and Customize return directly, preserving scope and selected entry."
  (emacsvox-test--with-settings
    (let ((emacsvox-aural-diagnostic-log-file nil)
          (before (emacsvox-aural-read-user-data)))
      (execute-kbd-macro (kbd "D"))
      (dolist (entry '(("d" emacsvox-aural-doctor-mode emacsvox-settings-workflows--doctor)
                       ("s" help-mode emacsvox-settings-workflows--spatial)
                       ("A" Custom-mode emacsvox-settings-workflows--diagnostic-options)))
        (execute-kbd-macro (kbd (car entry)))
        (should (derived-mode-p (nth 1 entry)))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-diagnostics))
        (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
        (with-selected-window transient--window
          (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                      (nth 2 entry)))))
      (should-not emacsvox-aural-diagnostic-log-file)
      (should-not (file-exists-p custom-file))
      (should (equal before (emacsvox-aural-read-user-data)))
      (execute-kbd-macro (kbd "q q"))
      (should (eq (current-buffer) source))
      (should (= (point) 3)))))

(ert-deftest emacsvox-settings-diagnostics-enter-activation ()
  "Both Enter events open the selected report and q restores its selection."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "D"))
    (dolist (key '("RET" "<return>"))
      (with-selected-window transient--window
        (transient--goto-button
         (transient-suffix-object 'emacsvox-settings-workflows--doctor)))
      (execute-kbd-macro (kbd key))
      (should (derived-mode-p 'emacsvox-aural-doctor-mode))
      (execute-kbd-macro (kbd "q <down>"))
      (execute-kbd-macro (kbd key))
      (should (derived-mode-p 'help-mode))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-diagnostics))
      (with-selected-window transient--window
        (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                    'emacsvox-settings-workflows--spatial)))
      (execute-kbd-macro (kbd "<up>")))))

(ert-deftest emacsvox-settings-diagnostics-help-does-not-capture-later-help ()
  "Reusing the report's Help buffer preserves Transient's normal Help return."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "D s q q ? s"))
    (should (derived-mode-p 'help-mode))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))))

(ert-deftest emacsvox-settings-diagnostics-retained-output ()
  "Both retained server buffers keep their contents and original maps on return."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "D"))
    (dolist (entry '(("m" "Speaker") ("n" "Notify")))
      (let* ((buffer (tts--diagnostic-buffer (cadr entry) t))
             (map (buffer-local-value 'major-mode buffer)))
        (unwind-protect
            (progn
              (with-current-buffer buffer (insert "retained diagnostic output"))
              (execute-kbd-macro (kbd (car entry)))
              (should (eq (current-buffer) buffer))
              (should (equal (buffer-string) "retained diagnostic output"))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-settings-diagnostics))
              (with-current-buffer buffer
                (should (eq major-mode map))
                (should-not (local-key-binding (kbd "q")))))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-settings-diagnostics-logging-is-explicit ()
  "Browsing does not log; activation toggles session logging without saving."
  (emacsvox-test--with-settings
    (let ((emacsvox-aural-diagnostic-log-file nil)
          (emacsvox-aural--diagnostic-log-toggle-file
           (expand-file-name "speech.log" (file-name-directory custom-file))))
      (execute-kbd-macro (kbd "D <down> <up>"))
      (should-not (file-exists-p emacsvox-aural--diagnostic-log-toggle-file))
      (execute-kbd-macro (kbd "l"))
      (should (equal emacsvox-aural-diagnostic-log-file
                     emacsvox-aural--diagnostic-log-toggle-file))
      (should (file-exists-p emacsvox-aural-diagnostic-log-file))
      (execute-kbd-macro (kbd "l"))
      (should-not emacsvox-aural-diagnostic-log-file)
      (should-not (file-exists-p custom-file)))))

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

(ert-deftest emacsvox-settings-context-close-announces-source ()
  "Direct exits announce the restored buffer once; nested Back stays in the menu."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (require 'org)
  (emacsvox-test--with-settings
   (execute-kbd-macro (kbd "C-q"))
   (let (closed)
     (cl-letf (((symbol-function 'emacsvox-aural-submit)
                (lambda (text &rest args)
                  (when (memq 'command-menu-closed
                              (plist-get (plist-get args :facts) :events))
                    (push (cons text args) closed)))))
       (dolist (mode '(text-mode comint-mode eat-mode org-mode))
         (with-current-buffer source (funcall mode))
         (dolist (key '("q" "C-g" "C-q"))
           (ert-info ((format "Mode %S, exit %s" mode key))
             (execute-kbd-macro (kbd "C-e S"))
             (setq closed nil)
             (execute-kbd-macro (kbd key))
             (should-not transient--prefix)
             (should (eq (current-buffer) source))
             (should (= (length closed) 1))
             (should (string-prefix-p (buffer-name source) (caar closed)))
             (let ((args (cdar closed)))
               (should (eq (plist-get args :interruption-policy) 'lane))
               (should (equal
                        (mapcar #'emacsvox-aural-compatibility-action-value
                                (plist-get args :compatibility-actions))
                        '(close-object)))))))
       (with-current-buffer source (eat-mode))
       (execute-kbd-macro (kbd "C-e S p"))
       (setq closed nil)
       (execute-kbd-macro (kbd "q"))
       (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat))
       (should-not closed)
       (execute-kbd-macro (kbd "q"))
       (should (= (length closed) 1))
       (execute-kbd-macro (kbd "C-e H j c"))
       (setq closed nil)
       (execute-kbd-macro (kbd "q"))
       (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations))
       (should-not closed)))))

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
(ert-deftest emacsvox-settings-workflows-presentation-references-return ()
  "Both reference views use the captured source and return without changing rules."
  (emacsvox-test--with-settings
    (let ((before (emacsvox-aural-read-user-data)))
      (execute-kbd-macro (kbd "r"))
      (dolist (entry '(("o" emacsvox-aural-overrides-mode emacsvox-settings-workflows--overrides)
                       ("h" emacsvox-aural-semantics-mode emacsvox-settings-workflows--semantics)))
        (execute-kbd-macro (kbd (car entry)))
        (should (derived-mode-p (nth 1 entry)))
        (should (eq (emacsvox-aural-inspection-source-buffer) source))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-presentation))
        (with-selected-window transient--window
          (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                      (nth 2 entry)))))
      (should (equal before (emacsvox-aural-read-user-data)))
      (should-not (file-exists-p custom-file)))))

(ert-deftest emacsvox-settings-workflows-training-is-explicit-and-temporary ()
  "Training navigation is passive; activation installs and removes its hooks."
  (emacsvox-test--with-settings
    (unwind-protect
        (progn
          (execute-kbd-macro (kbd "r <down> <up>"))
          (should-not emacsvox-aural-training-mode)
          (execute-kbd-macro (kbd "t"))
          (should emacsvox-aural-training-mode)
          (should (memq 'emacsvox-aural-explanation--training-presented
                        emacsvox-aural-plan-presented-hook))
          (execute-kbd-macro (kbd "t"))
          (should-not emacsvox-aural-training-mode)
          (should-not (memq 'emacsvox-aural-explanation--training-presented
                            emacsvox-aural-plan-presented-hook))
          (should-not (file-exists-p custom-file)))
      (emacsvox-aural-training-mode -1))))

(ert-deftest emacsvox-settings-workflows-tune-retains-draft-and-source ()
  "Contextual tuning preserves source text, a changed draft, and return focus."
  (emacsvox-test--with-settings
    (emacsvox-test--with-voice-editor
      (let ((before (emacsvox-aural-read-user-data)) seen)
        (cl-letf (((symbol-function 'emacsvox-aural-tools--remap-source-input)
                   (lambda (&rest _)
                     (setq seen (list (current-buffer) (point)))
                     (list :source source :facts '(:content "Captured heading"))))
                  ((symbol-function 'emacsvox-aural-change-feedback--named-voice)
                   (lambda (_) '(reading-owned bolden))))
          (execute-kbd-macro (kbd "f t")))
        (should (equal seen (list source 3)))
        (should (derived-mode-p 'emacsvox-aural-voice-editor-mode))
        (should (equal (emacsvox-aural-voice-editor--get :text) "Captured heading"))
        (should (eq (emacsvox-aural-voice-editor--get :voice) 'bolden))
        (emacsvox-aural-voice-editor--put :automatic-sample nil)
        (emacsvox-aural-voice-editor--set 'average-pitch 7)
        (let ((editor (current-buffer)))
          (execute-kbd-macro (kbd "h"))
          (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
          (should (eq (plist-get (emacsvox-aural-menu--context) :source) source))
          (execute-kbd-macro (kbd "q"))
          (should (eq (current-buffer) editor)))
        (let ((draft (emacsvox-aural-voice-editor--draft)))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _) "Continue editing")))
            (execute-kbd-macro (kbd "q")))
          (should (derived-mode-p 'emacsvox-aural-voice-editor-mode))
          (should emacsvox-aural-ui--return-function)
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _) "Keep draft and return")))
            (execute-kbd-macro (kbd "q")))
          (should (eq (oref transient--prefix command) 'emacsvox-settings-feedback))
          (with-selected-window transient--window
            (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                        'emacsvox-settings-workflows--tune)))
          (should (emacsvox-aural-voice-drafts--dirty-fields draft))
          (execute-kbd-macro (kbd "q p d"))
          (should (derived-mode-p 'emacsvox-aural-voice-editor-mode))
          (should (eq (emacsvox-aural-voice-editor--draft) draft))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _) "Keep draft and return")))
            (execute-kbd-macro (kbd "q")))
          (should (eq (oref transient--prefix command) 'emacsvox-settings-setups))
          (with-selected-window transient--window
            (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                        'emacsvox-settings-workflows--drafts))))
        (should (equal before (emacsvox-aural-read-user-data)))
        (should-not requests)))))

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

(ert-deftest emacsvox-settings-workflows-cancel-draft-chooser ()
  "Cancelling a choice among retained drafts restores Saved setups unchanged."
  (emacsvox-test--with-settings
    (let ((first (generate-new-buffer " *first retained draft*"))
          (second (generate-new-buffer " *second retained draft*")))
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-aural-home--pending-drafts)
                     (lambda () (list first second))))
            (execute-kbd-macro (kbd "p"))
            (condition-case nil (execute-kbd-macro (kbd "d C-g")) (quit nil))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-setups))
            (should-not (get-buffer-window first))
            (should-not (get-buffer-window second))
            (should-not (file-exists-p custom-file)))
        (kill-buffer first)
        (kill-buffer second)))))

(ert-deftest emacsvox-settings-workflows-no-drafts-keeps-menu ()
  "An empty draft registry reports the absence without opening Home or saving."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "p"))
    (cl-letf (((symbol-function 'emacsvox-aural-home--pending-drafts) (lambda () nil)))
      (should-error (emacsvox-settings-workflows--drafts) :type 'user-error))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-setups))
    (should-not (file-exists-p custom-file))))

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
    (execute-kbd-macro (kbd "c A"))
    (should (derived-mode-p 'Custom-mode))
    (should (save-excursion (goto-char (point-min))
                           (search-forward "Table After Movement Function" nil t)))
    (execute-kbd-macro (kbd "q q q"))
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
    (execute-kbd-macro (kbd "a O r g SPC t a b l e s RET A"))
    (should (derived-mode-p 'Custom-mode))
    (execute-kbd-macro (kbd "q q"))
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
        (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eat-choice))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'earcon))
        (should (string-match-p "Ready cue, selected" (car spoken)))
        (execute-kbd-macro (kbd "<down>"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'earcon))
        (execute-kbd-macro (kbd "RET"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'text))
        (should (string-match-p "Prompt feedback: read prompt" (car spoken)))
        (with-selected-window transient--window
          (should (equal (oref (button-get (button-at (point)) 'button-data) key) "p")))
        (execute-kbd-macro (kbd "p <down> q"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'text))
        (execute-kbd-macro (kbd "p 3"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'silent))
        (execute-kbd-macro (kbd "p 1"))
        (should (eq (buffer-local-value 'emacsvox-eat-prompt-feedback source) 'earcon))
        (execute-kbd-macro (kbd "<down>"))
        (should (string-match-p "Automatic feedback detail: normal.*d" (car spoken)))
        (execute-kbd-macro (kbd "RET"))
        (should (eq (buffer-local-value 'emacsvox-eat-verbosity source) 'normal))
        (should (string-match-p "Normal:.*selected" (car spoken)))
        (execute-kbd-macro (kbd "<down> RET"))
        (should (eq (buffer-local-value 'emacsvox-eat-verbosity source) 'verbose))
        (should (string-match-p "Automatic feedback detail: verbose" (car spoken)))
        (execute-kbd-macro (kbd "d 1 d 2"))
        (should (eq (buffer-local-value 'emacsvox-eat-verbosity source) 'normal)))
      (should (equal defaults (mapcar #'default-value emacsvox-settings-integrations--eat-options)))
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "q"))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "c")))
      (execute-kbd-macro (kbd "q q q"))
      (should (eq (current-buffer) source)))))

(ert-deftest emacsvox-settings-integrations-eat-confirmations-interrupt ()
  "Each Enter confirmation replaces main speech on its first activation."
  (skip-unless (require 'eat nil t))
  (require 'emacsvox-eat)
  (let ((submit (symbol-function 'emacsvox-aural-submit)))
    (emacsvox-test--with-settings
     (with-current-buffer source
       (eat-mode)
       (setq-local emacsvox-eat-autospeak t
                   emacsvox-eat-monitor-background-output nil))
     (execute-kbd-macro (kbd "j c"))
     (let (submissions)
       ;; Keep real policy normalization, intercept only before rendering/audio.
       (cl-letf (((symbol-function 'emacsvox-aural-submit) submit)
                 ((symbol-function 'emacsvox-aural--submit-content)
                  (lambda (text _actions)
                    (when (eq emacsvox-aural-submission-occasion 'state-change)
                      (push (list text emacsvox-aural-submission-lane
                                  emacsvox-aural-submission-delivery-policy
                                  emacsvox-aural-submission-replacement-key
                                  emacsvox-aural-submission-interruption-policy)
                            submissions))
                    nil)))
         (dolist (key '("s" "b" "p 2" "d 3"))
           (setq submissions nil)
           (execute-kbd-macro (kbd key))
           (should (= (length submissions) 1))
           (should (equal (cdar submissions) '(main replaceable speaker lane)))))))))

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
            (execute-kbd-macro (kbd "j c s p 2"))
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

(defun emacsvox-test--integration-defaults (feature function)
  "Call FUNCTION with FEATURE's global defaults and Customize metadata isolated."
  (require feature)
  (let* ((options (mapcar (lambda (entry) (nth 2 entry))
                         (seq-filter (lambda (entry) (eq (nth 1 entry) feature))
                                     emacsvox-settings-integrations--options)))
         (defaults (mapcar (lambda (option) (cons option (default-value option))) options))
         (properties (mapcar (lambda (option) (cons option (copy-tree (symbol-plist option)))) options)))
    (unwind-protect (funcall function)
      (dolist (entry defaults) (set-default (car entry) (cdr entry)))
      (dolist (entry properties) (setplist (car entry) (cdr entry))))))

(ert-deftest emacsvox-settings-integrations-agent-session-and-defaults ()
  "Session overrides use the existing lifecycle and stay out of saved defaults."
  (skip-unless (require 'agent-shell nil t))
  (emacsvox-test--integration-defaults 'emacsvox-agent-shell
   (lambda ()
     (emacsvox-test--with-settings
       (with-current-buffer source
         (setq major-mode 'agent-shell-mode)
         (setq-local emacsvox-agent-shell-speech-level 'auto))
       (execute-kbd-macro (kbd "j c s 5"))
       (should (eq (buffer-local-value 'emacsvox-agent-shell-speech-level source) 'quiet))
       (should-not (file-exists-p custom-file))
       (let (cancelled)
         (set-default 'emacsvox-agent-shell-background-speech-level 'response)
         (cl-letf (((symbol-function 'emacsvox-agent-shell--cancel-background-pending-speech)
                    (lambda () (setq cancelled t))))
           (execute-kbd-macro (kbd "b"))
           (should-not cancelled)
           (execute-kbd-macro (kbd "3")))
         (should cancelled)
         (should (eq (default-value 'emacsvox-agent-shell-background-speech-level) 'notify)))
       (execute-kbd-macro (kbd "w"))
       (should (file-exists-p custom-file))
       (with-temp-buffer
         (insert-file-contents custom-file)
         (should (search-forward "emacsvox-agent-shell-background-speech-level" nil t))
         (goto-char (point-min))
         (should-not (search-forward "emacsvox-agent-shell-speech-level" nil t)))
       (execute-kbd-macro (kbd "q"))
       (with-selected-window transient--window
         (should (equal (oref (button-get (button-at (point)) 'button-data) key) "c")))))))

(ert-deftest emacsvox-settings-integrations-agent-choice-lists ()
  "Choices browse without applying, preserve global scope and return to their control."
  (skip-unless (require 'agent-shell nil t))
  (emacsvox-test--integration-defaults 'emacsvox-agent-shell
   (lambda ()
     (emacsvox-test--with-settings
       (with-current-buffer source
         (setq major-mode 'agent-shell-mode)
         (setq-local emacsvox-agent-shell-speech-level 'quiet))
       (execute-kbd-macro (kbd "C-q C-e S"))
       (dolist (case '(("f" emacsvox-agent-shell-foreground-speech-level
                       (full response notify quiet))
                      ("b" emacsvox-agent-shell-background-speech-level
                       (full response notify quiet))
                      ("t" emacsvox-agent-shell-speak-thought-process
                       (icon speak nil))
                      ("o" emacsvox-agent-shell-tool-output-verbosity
                       (summary status full))))
         (let ((key (nth 0 case)) (option (nth 1 case)) (values (nth 2 case))
               spoken cancelled)
           (set-default option (car values))
           (cl-letf (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest args) (push (cons text args) spoken)))
                     ((symbol-function 'emacsvox-agent-shell--cancel-background-pending-speech)
                      (lambda () (setq cancelled t))))
             (execute-kbd-macro (kbd key))
             (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--choice))
             (should (string-match-p "selected" (caar spoken)))
             (should (eq (default-value option) (car values)))
             (with-selected-window transient--window
               (should (= (how-many "^ +[1-5] " (point-min) (point-max)) (length values))))
             (execute-kbd-macro (kbd "<down>"))
             (should (eq (default-value option) (car values)))
             (should-not cancelled)
             (execute-kbd-macro (kbd "q"))
             (should (eq (default-value option) (car values)))
             (should-not cancelled)
             (execute-kbd-macro (vconcat (kbd key) (kbd "<down> RET")))
             (should (eq (default-value option) (cadr values)))
             (should (eq (plist-get (cdar spoken) :interruption-policy) 'lane))
             (should (eq (plist-get (cdar spoken) :delivery-policy) 'replaceable))
             (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--agent))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key) key)))
             ;; Exercise every choice, including nil (silent) and both cancellation levels.
             (cl-loop for value in values for index from 1 do
                      (setq cancelled nil)
                      (execute-kbd-macro (vconcat (kbd key) (number-to-string index)))
                      (should (eq (default-value option) value))
                      (should (eq (not (null cancelled))
                                  (and (eq option 'emacsvox-agent-shell-background-speech-level)
                                       (not (null (memq value '(notify quiet))))))))
             (execute-kbd-macro (kbd key))
             (should (string-match-p "selected" (caar spoken)))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                              (number-to-string (length values)))))
             (execute-kbd-macro (kbd "q")))
           (should-not (local-variable-p option source))
           (should (eq (buffer-local-value 'emacsvox-agent-shell-speech-level source) 'quiet))
           (should-not (file-exists-p custom-file))))))))

(ert-deftest emacsvox-settings-integrations-agent-session-choice-help ()
  "Session choices explain their effect and retain cancellation and interruption."
  (skip-unless (require 'agent-shell nil t))
  (require 'emacsvox-agent-shell)
  (let ((submit (symbol-function 'emacsvox-aural-submit)))
    (emacsvox-test--with-settings
      (with-current-buffer source
        (setq major-mode 'agent-shell-mode)
        (setq-local emacsvox-agent-shell-speech-level 'auto))
      (let ((foreground (default-value 'emacsvox-agent-shell-foreground-speech-level))
            (background (default-value 'emacsvox-agent-shell-background-speech-level))
            spoken confirmations cancelled)
        (cl-letf (((symbol-function 'emacsvox-aural-submit) submit)
                  ((symbol-function 'emacsvox-aural--submit-content)
                   (lambda (text _actions)
                     (push text spoken)
                     (when (eq emacsvox-aural-submission-occasion 'state-change)
                       (push (list emacsvox-aural-submission-lane
                                   emacsvox-aural-submission-delivery-policy
                                   emacsvox-aural-submission-interruption-policy)
                             confirmations))
                     nil))
                  ((symbol-function 'emacsvox-agent-shell--cancel-pending-speech)
                   (lambda () (push (current-buffer) cancelled))))
          (execute-kbd-macro (kbd "C-q C-e S s"))
          (should (string-match-p "Auto: follow foreground and background defaults.*selected" (car spoken)))
          (execute-kbd-macro (kbd "<down>"))
          (should (string-match-p "Full: responses and configured thought, plan and tool feedback" (car spoken)))
          (should (eq (buffer-local-value 'emacsvox-agent-shell-speech-level source) 'auto))
          (execute-kbd-macro (kbd "? 2"))
          (should (derived-mode-p 'help-mode))
          (should (string-match-p "only the captured session" (car spoken)))
          (should (save-excursion (goto-char (point-min))
                                 (search-forward "Full: responses and configured thought, plan and tool feedback" nil t)))
          (should (save-excursion (goto-char (point-min))
                                 (search-forward "only the captured session" nil t)))
          (execute-kbd-macro (kbd "q"))
          (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--choice))
          (execute-kbd-macro (kbd "? ?"))
          (should (derived-mode-p 'emacsvox-transient-mode))
          (should (save-excursion (goto-char (point-min))
                                 (search-forward "Auto: follow foreground and background defaults" nil t)))
          (should (save-excursion (goto-char (point-min))
                                 (search-forward "Quiet: suppress routine feedback" nil t)))
          (execute-kbd-macro (kbd "q q"))
          (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--agent))
          (should (eq (buffer-local-value 'emacsvox-agent-shell-speech-level source) 'auto))
          (should-not cancelled)
          (cl-loop for level in '(auto full response notify quiet) for index from 1 do
                   (setq confirmations nil cancelled nil)
                   (execute-kbd-macro (vconcat (kbd "s") (number-to-string index)))
                   (should (eq (buffer-local-value 'emacsvox-agent-shell-speech-level source) level))
                   (should (equal confirmations '((main replaceable lane))))
                   (should (equal cancelled (when (memq level '(notify quiet)) (list source)))))
          (should (eq foreground (default-value 'emacsvox-agent-shell-foreground-speech-level)))
          (should (eq background (default-value 'emacsvox-agent-shell-background-speech-level)))
          (should-not (file-exists-p custom-file)))))))

(ert-deftest emacsvox-settings-integrations-agent-limits-and-search ()
  "Search focuses a limit; shifted arrows and exact input preserve selection."
  (skip-unless (require 'agent-shell nil t))
  (emacsvox-test--integration-defaults 'emacsvox-agent-shell
   (lambda ()
     (emacsvox-test--with-settings
       (set-default 'emacsvox-agent-shell-automatic-content-max-characters 2000)
       (execute-kbd-macro (kbd "/ A g e n t SPC a u t o m a t i c RET"))
       (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--agent))
       (should (= (default-value 'emacsvox-agent-shell-automatic-content-max-characters) 2000))
       (let (spoken)
         (cl-letf (((symbol-function 'emacsvox-aural-submit)
                    (lambda (text &rest _) (when (stringp text) (push text spoken)))))
           (execute-kbd-macro (kbd "S-<right>"))
           (should (string-match-p "Automatic content characters: 2100" (car spoken)))))
       (execute-kbd-macro (kbd "RET C-a C-k 3 0 0 RET S-<left>"))
       (should (= (default-value 'emacsvox-agent-shell-automatic-content-max-characters) 200))
       (execute-kbd-macro (kbd "RET C-a C-k n o n e RET"))
       (should-not (default-value 'emacsvox-agent-shell-automatic-content-max-characters))
       (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "0")))
         (should-error (emacsvox-settings-integrations--agent-automatic-limit) :type 'user-error))
       (should-not (default-value 'emacsvox-agent-shell-automatic-content-max-characters))
       (should-not (file-exists-p custom-file))))))

(ert-deftest emacsvox-settings-integrations-agent-direct-viewport ()
  "The direct shortcut controls the viewport's session and returns to the viewport."
  (skip-unless (require 'agent-shell nil t))
  (require 'emacsvox-agent-shell)
  (require 'emacsvox-keymap)
  (emacsvox-test--with-settings
    (let ((shell (generate-new-buffer " *settings-agent-session*")))
      (unwind-protect
          (progn
            (with-current-buffer shell
              (setq major-mode 'agent-shell-mode)
              (setq-local emacsvox-agent-shell-speech-level 'auto))
            (with-current-buffer source (setq major-mode 'agent-shell-viewport-view-mode))
            (cl-letf (((symbol-function 'agent-shell-shell-buffer) (lambda (&rest _) shell)))
              (execute-kbd-macro (kbd "C-q C-e S s 5"))
              (should (eq (buffer-local-value 'emacsvox-agent-shell-speech-level shell) 'quiet))
              (should-not (local-variable-p 'emacsvox-agent-shell-speech-level source))
              (execute-kbd-macro (kbd "q"))
              (should-not transient--prefix)
              (should (eq (current-buffer) source))))
        (kill-buffer shell)))))

(ert-deftest emacsvox-settings-integrations-org-feedback-and-editors ()
  "Each table choice changes real spoken output; editors return without saving."
  (emacsvox-test--integration-defaults 'emacsvox-org
   (lambda ()
     (emacsvox-test--with-settings
       (set-default 'emacsvox-org-table-after-movement-function
                    'emacsvox-org-table-speak-current-element)
       (with-current-buffer source
         (org-mode)
         (erase-buffer)
         (insert "| Name | Count |\n|------+-------|\n| Apples | 5 |\n")
         (goto-char (point-min)) (search-forward "5"))
       (execute-kbd-macro (kbd "C-q C-e S"))
       (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--org))
       (cl-loop for expected in '("5" "Count" "Apples" "Count 5" "Apples 5" "Apples Count 5")
                for index from 1 do
         (execute-kbd-macro (vconcat (kbd "c") (number-to-string index)))
         (let (spoken)
           (cl-letf (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest _) (setq spoken (substring-no-properties text)))))
             (with-current-buffer source (emacsvox-org--present-table-after-movement)))
           (should (equal spoken expected))))
       (should-not (file-exists-p custom-file))
       (execute-kbd-macro (kbd "t"))
       (should (derived-mode-p 'Custom-mode))
       (execute-kbd-macro (kbd "q"))
       (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--org))
       (with-selected-window transient--window
         (should (equal (oref (button-get (button-at (point)) 'button-data) key) "t")))
       (should-not (file-exists-p custom-file))
       (execute-kbd-macro (kbd "c 2 w q"))
       (should-not transient--prefix)
       (should (eq (current-buffer) source))
       (should (file-exists-p custom-file))
       (set-default 'emacsvox-org-table-after-movement-function 'emacsvox-org-table-speak-current-element)
       (load custom-file nil t)
       (should (eq (default-value 'emacsvox-org-table-after-movement-function)
                   'emacsvox-org-table-speak-column-header))))))

(ert-deftest emacsvox-settings-integrations-org-and-notmuch-choice-help ()
  "Choice browsing and Help preserve defaults and local overrides until applying."
  (skip-unless (require 'notmuch nil t))
  (dolist (case '((emacsvox-org org-mode emacsvox-settings-integrations--org
                  emacsvox-org-table-after-movement-function
                  emacsvox-org-table-speak-current-element
                  emacsvox-org-table-speak-column-header
                  emacsvox-org-table-speak-both-headers-and-element
                  6 "Both headers and cell: read row, column, then cell"
                  "Buffer-local settings take precedence")
                 (emacsvox-notmuch notmuch-search-mode emacsvox-settings-integrations--notmuch
                  emacsvox-notmuch-search-completion-style adaptive summary silent
                  4 "Silent: suppress successful completion feedback"
                  "Failures remain audible in every style")))
    (emacsvox-test--integration-defaults (nth 0 case)
     (lambda ()
       (emacsvox-test--with-settings
         (let ((option (nth 3 case)) (initial (nth 4 case))
               (second (nth 5 case)) (last (nth 6 case))
               (count (nth 7 case)) spoken)
           (set-default option initial)
           (with-current-buffer source
             (setq major-mode (nth 1 case))
             (set (make-local-variable option) last))
           (cl-letf (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest args) (push (cons text args) spoken))))
             (execute-kbd-macro (kbd "C-q C-e S c"))
             (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--choice))
             (should (string-match-p "selected" (caar spoken)))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key) "1"))
               (should (= (how-many "^ +[1-6] " (point-min) (point-max)) count)))
             (execute-kbd-macro (kbd "<down> q"))
             (should (eq (default-value option) initial))
             (should (eq (oref transient--prefix command) (nth 2 case)))
             (execute-kbd-macro (kbd "c <down> RET"))
             (should (eq (default-value option) second))
             (should (eq (buffer-local-value option source) last))
             (should (eq (plist-get (cdar spoken) :interruption-policy) 'lane))
             (should (eq (plist-get (cdar spoken) :delivery-policy) 'replaceable))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key) "c")))
             (execute-kbd-macro (kbd "c"))
             (should (string-match-p "selected" (caar spoken)))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key) "2")))
             ;; Browse to the last choice, including Org's sixth row, without applying.
             (dotimes (_ (- count 2)) (execute-kbd-macro (kbd "<down>")))
             (should (string-match-p (nth 8 case) (caar spoken)))
             (should (eq (default-value option) second))
             ;; Asking about another key must still restore the browsed choice.
             (execute-kbd-macro (kbd "? 1"))
             (should (derived-mode-p 'help-mode))
             (should (string-match-p (nth 9 case) (caar spoken)))
             (should (string-match-p "global default" (caar spoken)))
             (should (string-match-p "Use w" (caar spoken)))
             (should-not (string-match-p "Permissions and errors" (caar spoken)))
             (execute-kbd-macro (kbd "q"))
             (should (string-match-p (nth 8 case) (caar spoken)))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                              (number-to-string count))))
             (execute-kbd-macro (kbd "RET"))
             (should (eq (default-value option) last))
             (should (eq (oref transient--prefix command) (nth 2 case)))
             (should (eq (buffer-local-value option source) last))
             (should-not (file-exists-p custom-file))
             (execute-kbd-macro (kbd "c"))
             (should (string-match-p "selected" (caar spoken)))
             (with-selected-window transient--window
               (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                              (number-to-string count))))
             (execute-kbd-macro (kbd "q q"))
             (should-not transient--prefix)
             (should (eq (current-buffer) source)))))))))

(ert-deftest emacsvox-settings-integrations-eww-rendering-and-save ()
  "Image changes affect subsequent rendering without reloading or losing overrides."
  (require 'shr)
  (let ((old-shr (default-value 'shr-inhibit-images)))
    (unwind-protect
        (emacsvox-test--integration-defaults 'emacsvox-eww
         (lambda ()
           (emacsvox-test--with-settings
             (set-default 'emacsvox-eww-autospeak t)
             (set-default 'emacsvox-eww-inhibit-images nil)
             (set-default 'shr-inhibit-images nil)
             (with-current-buffer source
               (eww-mode)
               (setq-local shr-inhibit-images 'local-override))
             (cl-letf (((symbol-function 'eww-reload)
                        (lambda (&rest _) (ert-fail "Settings must not reload a page"))))
               (execute-kbd-macro (kbd "C-q C-e S"))
               (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--eww))
               (execute-kbd-macro (kbd "s i"))
               (should-not (default-value 'emacsvox-eww-autospeak))
               (should (default-value 'emacsvox-eww-inhibit-images))
               (should (default-value 'shr-inhibit-images))
               (should (eq (buffer-local-value 'shr-inhibit-images source) 'local-override))
               (let (displayed)
                 (emacsvox--advice-eww-display-image-around (lambda (_) (setq displayed t)) source)
                 (should-not displayed)
                 (execute-kbd-macro (kbd "i"))
                 (emacsvox--advice-eww-display-image-around (lambda (_) (setq displayed t)) source)
                 (should displayed))
               (should-not (file-exists-p custom-file))
               (execute-kbd-macro (kbd "A"))
               (should (derived-mode-p 'Custom-mode))
               (execute-kbd-macro (kbd "q"))
               (with-selected-window transient--window
                 (should (equal (oref (button-get (button-at (point)) 'button-data) key) "A")))
               (execute-kbd-macro (kbd "i w q"))
               (should-not transient--prefix)
               (should (eq (current-buffer) source))
               (set-default 'emacsvox-eww-autospeak t)
               (set-default 'emacsvox-eww-inhibit-images nil)
               (load custom-file nil t)
               (should-not (default-value 'emacsvox-eww-autospeak))
               (should (default-value 'emacsvox-eww-inhibit-images))))))
      (set-default 'shr-inhibit-images old-shr))))

(ert-deftest emacsvox-settings-integrations-notmuch-limits-and-save ()
  "Mail limits support arrows, exact input and explicit persistence from each view."
  (skip-unless (require 'notmuch nil t))
  (emacsvox-test--integration-defaults 'emacsvox-notmuch
   (lambda ()
     (emacsvox-test--with-settings
       (set-default 'emacsvox-notmuch-search-completion-style 'adaptive)
       (set-default 'emacsvox-notmuch-automatic-field-character-limit 256)
       (execute-kbd-macro (kbd "C-q"))
       (dolist (mode '(notmuch-hello-mode notmuch-search-mode notmuch-show-mode notmuch-tree-mode))
         ;; Identify each view without opening a database or starting a search.
         (with-current-buffer source (setq major-mode mode))
         (execute-kbd-macro (kbd "C-e S"))
         (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--notmuch))
         (execute-kbd-macro (kbd "q"))
         (should-not transient--prefix)
         (should (eq (current-buffer) source)))
       (execute-kbd-macro (kbd "C-e S"))
       (cl-loop for expected in '(adaptive summary cue silent)
                for index from 1 do
         (execute-kbd-macro (vconcat (kbd "c") (number-to-string index)))
         (should (eq (default-value 'emacsvox-notmuch-search-completion-style) expected)))
       (with-selected-window transient--window
         (transient--goto-button (transient-suffix-object 'emacsvox-settings-integrations--notmuch-field-characters)))
       (let (spoken)
         (cl-letf (((symbol-function 'emacsvox-aural-submit)
                    (lambda (text &rest _) (when (stringp text) (push text spoken)))))
           (execute-kbd-macro (kbd "S-<right>"))
           (should (string-match-p "Per-field characters: 356" (car spoken)))))
       (execute-kbd-macro (kbd "RET C-a C-k 5 0 0 RET S-<left>"))
       (should (= (default-value 'emacsvox-notmuch-automatic-field-character-limit) 400))
       (execute-kbd-macro (kbd "b C-a C-k n o n e RET t C-a C-k 9 0 0 RET B C-a C-k 2 0 0 0 RET"))
       (should-not (default-value 'emacsvox-notmuch-automatic-field-byte-limit))
       (should (= (default-value 'emacsvox-notmuch-automatic-total-character-limit) 900))
       (should (= (default-value 'emacsvox-notmuch-automatic-total-byte-limit) 2000))
       (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "-1")))
         (should-error (emacsvox-settings-integrations--notmuch-total-bytes) :type 'user-error))
       (should-not (file-exists-p custom-file))
       (execute-kbd-macro (kbd "c 2 w q"))
       (set-default 'emacsvox-notmuch-search-completion-style 'silent)
       (set-default 'emacsvox-notmuch-automatic-field-character-limit 1)
       (load custom-file nil t)
       (should (eq (default-value 'emacsvox-notmuch-search-completion-style) 'summary))
       (should (= (default-value 'emacsvox-notmuch-automatic-field-character-limit) 400))
       (with-temp-buffer
         (insert-file-contents custom-file)
         (should-not (string-match-p "search-result-fields\\|show-message-fields\\|status-icons" (buffer-string))))))))

(ert-deftest emacsvox-settings-integrations-notmuch-structured-return ()
  "Structured editors preserve order, custom formatters and their own save boundary."
  (skip-unless (require 'notmuch nil t))
  (require 'emacsvox-notmuch)
  (emacsvox-test--with-settings
    (let* ((formatter (lambda (_) "Custom field"))
           (emacsvox-notmuch-search-result-fields (list 'subject formatter 'authors))
           (emacsvox-notmuch-show-message-fields '(tags from))
           (emacsvox-notmuch-search-status-icons '(("unread") ("flagged" . mark-object)))
           (emacsvox-notmuch-show-status-icons '(("replied" . mail-replied)))
           (fields (copy-sequence emacsvox-notmuch-search-result-fields)))
      (with-current-buffer source (setq major-mode 'notmuch-search-mode))
      (execute-kbd-macro (kbd "C-q C-e S"))
      (dolist (style '(continuous section-wrap section-stop))
        (let ((emacsvox-transient-navigation-style style)
              (emacsvox-transient-section-announcement-order 'by-movement)
              speech)
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (text &rest _) (push text speech))))
            (dolist (section '(("Status feedback (global)" "c")
                               ("Reading limits (global); w saves" "f")
                               ("Defaults and advanced settings" "w")
                               ("Finish" "q")))
              (execute-kbd-macro (kbd "<right>"))
              (should (string-prefix-p (concat (car section) ".") (car speech)))
              (with-selected-window transient--window
                (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                               (cadr section)))))
            (execute-kbd-macro (kbd "<left> <left> <left> <left>"))
            (should (string-prefix-p "Spoken content: save inside each editor."
                                     (car speech)))))
        (should (equal emacsvox-notmuch-search-result-fields fields))
        (should-not (file-exists-p custom-file)))
      (dolist (key '("s" "m" "i" "I" "A"))
        (execute-kbd-macro (kbd key))
        (should (derived-mode-p 'Custom-mode))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--notmuch))
        (with-selected-window transient--window
          (should (equal (oref (button-get (button-at (point)) 'button-data) key) key)))
        (should-not (file-exists-p custom-file)))
      (should (equal emacsvox-notmuch-search-result-fields fields))
      (should (eq (cadr emacsvox-notmuch-search-result-fields) formatter))
      (should (equal emacsvox-notmuch-show-message-fields '(tags from)))
      (should (equal emacsvox-notmuch-search-status-icons '(("unread") ("flagged" . mark-object))))
      (execute-kbd-macro (kbd "p"))
      (should (derived-mode-p 'emacsvox-aural-feature-fragments-mode))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-integrations--notmuch))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "p")))
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "q"))
      (should-not transient--prefix)
      (should (eq (current-buffer) source)))))

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

(ert-deftest emacsvox-settings-history-enter-and-return ()
  "Enter opens history policy from its parent and restores the invoking item."
  (emacsvox-test--with-settings
    (let ((emacsvox-transient-navigation-style 'continuous))
      (execute-kbd-macro (kbd "f <right> <down>"))
      (dolist (key '("RET" "<return>"))
        (with-selected-window transient--window
          (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                      'emacsvox-settings-history)))
        (execute-kbd-macro (kbd key))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-history))
        (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-feedback)))
      (should-not (file-exists-p custom-file)))))

(ert-deftest emacsvox-settings-history-controls ()
  "Navigation is inert; adjustments trim oldest records and Save is explicit."
  (emacsvox-test--with-settings
    (let ((emacsvox-aural-presentation-history-limit 3)
          (emacsvox-aural-history-record-interface-presentations nil)
          (emacsvox-aural-presentation-history (list 'new 'middle 'old))
          speech)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest args) (push (cons text args) speech))))
        (execute-kbd-macro (kbd "f H <down> <down> <up>"))
        (should (= emacsvox-aural-presentation-history-limit 3))
        (should (equal emacsvox-aural-presentation-history '(new middle old)))
        (execute-kbd-macro (kbd "S-<left>"))
        (should (= emacsvox-aural-presentation-history-limit 2))
        (should (equal (caar speech) "History limit: 2"))
        (should (equal emacsvox-aural-presentation-history '(new middle)))
        (should (eq (plist-get (cdar speech) :delivery-policy) 'replaceable))
        (should (eq (plist-get (cdar speech) :interruption-policy) 'lane))
        (execute-kbd-macro (kbd "S-<right> RET 3 RET i"))
        (should (= emacsvox-aural-presentation-history-limit 3))
        (should (= (length emacsvox-aural-presentation-history) 2))
        (should emacsvox-aural-history-record-interface-presentations)
        (should-not (file-exists-p custom-file))
        (execute-kbd-macro (kbd "w"))
        (with-temp-buffer
          (insert-file-contents custom-file)
          (should (search-forward "emacsvox-aural-presentation-history-limit 3" nil t))
          (goto-char (point-min))
          (should (search-forward "emacsvox-aural-history-record-interface-presentations t" nil t)))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-settings-feedback))
        (with-selected-window transient--window
          (should (equal (oref (button-get (button-at (point)) 'button-data) key) "H")))))))

(ert-deftest emacsvox-settings-history-validation-and-zero ()
  "Invalid limits preserve records; zero clears and disables through lifecycle."
  (emacsvox-test--with-settings
    (let ((emacsvox-aural-presentation-history-limit 2)
          (emacsvox-aural-presentation-history (list 'new 'old)))
      (cl-letf (((symbol-function 'emacsvox-aural-submit) #'ignore))
        (execute-kbd-macro (kbd "f H <down>"))
        (dolist (value '(-1 1.5))
          (cl-letf (((symbol-function 'emacsvox-aural-menu--read-number)
                     (lambda (&rest _) value)))
            (should-error (emacsvox-settings-workflows--history-limit) :type 'user-error))
          (should (= emacsvox-aural-presentation-history-limit 2))
          (should (equal emacsvox-aural-presentation-history '(new old))))
        (cl-letf (((symbol-function 'emacsvox-aural-menu--read-number)
                   (lambda (&rest _) (signal 'quit nil))))
          (should (eq (condition-case nil
                          (emacsvox-settings-workflows--history-limit)
                        (quit 'cancelled)) 'cancelled)))
        (execute-kbd-macro (kbd "S-<left> S-<left> S-<left>"))
        (should (zerop emacsvox-aural-presentation-history-limit))
        (should-not emacsvox-aural-presentation-history)
        (should-not (file-exists-p custom-file))))))

(ert-deftest emacsvox-settings-switches-source-and-default-scopes ()
  "Buffer switches and inherited earcon defaults have distinct effects."
  (emacsvox-test--with-settings
    (let ((old-default (default-value 'emacsvox-use-icons))
          (other (generate-new-buffer " *settings other*")) events)
      (unwind-protect
          (progn
            (set-default 'emacsvox-use-icons t)
            (with-current-buffer source
              (kill-local-variable 'emacsvox-use-icons)
              (voice-lock-mode 1))
            (with-current-buffer other (voice-lock-mode 1))
            (let ((emacsvox-aural-compatibility-voice-changed-hook
                   (list (lambda (buffer enabled) (push (cons buffer enabled) events)))))
              (execute-kbd-macro (kbd "r l <down> <down> <up> RET")))
            (should-not (buffer-local-value 'voice-lock-mode source))
            (should (buffer-local-value 'voice-lock-mode other))
            (should (equal events (list (cons source nil))))
            (execute-kbd-macro (kbd "v e"))
            (should (buffer-local-value 'voice-lock-mode source))
            (should-not (buffer-local-value 'emacsvox-use-icons source))
            (should (buffer-local-value 'emacsvox-use-icons other))
            (execute-kbd-macro (kbd "E E"))
            (should-not (buffer-local-value 'emacsvox-use-icons source))
            (should (buffer-local-value 'emacsvox-use-icons other))
            (execute-kbd-macro (kbd "i"))
            (should (buffer-local-value 'emacsvox-use-icons source))
            (should-not (local-variable-p 'emacsvox-use-icons source))
            (should-not (file-exists-p custom-file))
            (execute-kbd-macro (kbd "? e"))
            (should (derived-mode-p 'help-mode))
            (should (string-match-p "local override" (buffer-string)))
            (execute-kbd-macro (kbd "q q"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-presentation)))
        (set-default 'emacsvox-use-icons old-default)
        (kill-buffer other)))))

(ert-deftest emacsvox-settings-switches-global-voice-lock ()
  "Global Voice Lock uses its lifecycle and only its explicit Save persists."
  (emacsvox-test--with-settings
    (let ((original global-voice-lock-mode)
          (states (mapcar (lambda (buffer)
                            (cons buffer (buffer-local-value 'voice-lock-mode buffer)))
                          (buffer-list))))
      (unwind-protect
          (progn
            (execute-kbd-macro (kbd "r l V"))
            (should (eq global-voice-lock-mode (not original)))
            (should (eq (buffer-local-value 'voice-lock-mode source) (not original)))
            (should-not (file-exists-p custom-file))
            (execute-kbd-macro (kbd "V w"))
            (should (eq global-voice-lock-mode original))
            (with-temp-buffer
              (insert-file-contents custom-file)
              (should (search-forward "global-voice-lock-mode" nil t))
              (should-not (search-forward "emacsvox-use-icons" nil t))))
        (global-voice-lock-mode (if original 1 -1))
        (dolist (entry states)
          (when (buffer-live-p (car entry))
            (with-current-buffer (car entry)
              (voice-lock-mode (if (cdr entry) 1 -1)))))))))

(ert-deftest emacsvox-settings-switches-silence-captured-item ()
  "Local suppression targets the captured personality, and can be restored."
  (emacsvox-test--with-settings
    (require 'voice-setup)
    (with-current-buffer source
      (put-text-property 3 4 'personality 'bolden)
      (goto-char 3))
    (execute-kbd-macro (kbd "C-q <f8>"))
    (with-current-buffer source (goto-char (point-max)))
    (let (speech)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest args) (push (cons text args) speech))))
        (execute-kbd-macro (kbd "r l s"))
        (should (gethash 'bolden (buffer-local-value 'emacsvox-aural-suppressed-personalities source)))
        (should (string-match-p "Silenced personality bolden" (caar speech)))
        (should (eq (plist-get (cdar speech) :interruption-policy) 'lane))
        (with-current-buffer source (should (= (point) (point-max))))
        (execute-kbd-macro (kbd "s"))
        (should-not (gethash 'bolden (buffer-local-value 'emacsvox-aural-suppressed-personalities source)))
        (should (string-match-p "Made personality bolden audible" (caar speech)))
        (with-current-buffer source (remove-text-properties 3 4 '(personality nil)))
        (should-error (emacsvox-settings-workflows--silence) :type 'user-error)
        (execute-kbd-macro (kbd "C-q <f8> r l s"))
        (should (equal (caar speech) "No personality or mapped face here."))
        (should-not (file-exists-p custom-file))))))

(ert-deftest emacsvox-settings-voice-presentation-label-choices ()
  "Labels are browsable without changing samples; Enter applies and returns."
  (emacsvox-test--with-settings
    (require 'emacsvox-aural-preview)
    (let ((emacsvox-aural-preview-label-verbosity 'names)
          (entry '(:text "same sentence" :voice "sample")))
      (execute-kbd-macro (kbd "v o l <down>"))
      (should (eq emacsvox-aural-preview-label-verbosity 'names))
      (execute-kbd-macro (kbd "? b"))
      (should (string-match-p "sample text stays unchanged" (buffer-string)))
      (execute-kbd-macro (kbd "q q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-voice-presentation))
      (execute-kbd-macro (kbd "l <down> RET"))
      (should (eq emacsvox-aural-preview-label-verbosity 'brief))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-voice-presentation))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "l")))
      (should (equal (emacsvox-aural-preview-labelled-entry entry "Engine, voice" "A")
                     (list '(:text "A." :voice "sample") entry)))
      (execute-kbd-macro (kbd "l <down> RET"))
      (should-not emacsvox-aural-preview-label-verbosity)
      (should (equal (emacsvox-aural-preview-labelled-entry entry "Engine, voice" "A") (list entry)))
      (execute-kbd-macro (kbd "l n"))
      (should (eq emacsvox-aural-preview-label-verbosity 'names))
      (should-not (file-exists-p custom-file)))))

(ert-deftest emacsvox-settings-voice-presentation-contrast-and-save ()
  "Pitch changes validate, schedule registration, and save only on request."
  (emacsvox-test--with-settings
    (require 'omnivox-voices)
    (require 'emacsvox-aural-preview)
    (let ((omnivox-average-pitch-contrast 0.5)
          (emacsvox-aural-preview-label-verbosity 'brief)
          (registrations 0) speech)
      (cl-letf (((symbol-function 'omnivox--schedule-logical-registration)
                 (lambda () (cl-incf registrations)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest args) (push (cons text args) speech))))
        (execute-kbd-macro (kbd "v o <down> <down>"))
        (should (zerop registrations))
        (execute-kbd-macro (kbd "S-<right> S-<left>"))
        (should (= omnivox-average-pitch-contrast 0.5))
        (should (= registrations 2))
        (should (eq (plist-get (cdar speech) :interruption-policy) 'lane))
        (execute-kbd-macro (kbd "RET 2 RET S-<right>"))
        (should (= omnivox-average-pitch-contrast 2))
        (dolist (value '(-0.1 2.1))
          (cl-letf (((symbol-function 'emacsvox-aural-menu--read-number)
                     (lambda (&rest _) value)))
            (should-error (emacsvox-settings-workflows--pitch-contrast) :type 'user-error)))
        (cl-letf (((symbol-function 'emacsvox-aural-menu--read-number)
                   (lambda (&rest _) (signal 'quit nil))))
          (should (eq (condition-case nil (emacsvox-settings-workflows--pitch-contrast)
                        (quit 'cancelled)) 'cancelled)))
        (should (= omnivox-average-pitch-contrast 2))
        (should-not (file-exists-p custom-file))
        (execute-kbd-macro (kbd "RET 0 RET S-<left> w"))
        (should (zerop omnivox-average-pitch-contrast))
        (with-temp-buffer
          (insert-file-contents custom-file)
          (should (search-forward "omnivox-average-pitch-contrast 0.0" nil t))
          (goto-char (point-min))
          (should (search-forward "emacsvox-aural-preview-label-verbosity 'brief" nil t)))))))

(ert-deftest emacsvox-settings-dictionaries-definition-save-and-load ()
  "Define in source scope; only persistent dictionaries go to their own file."
  (emacsvox-test--with-settings
    (let ((emacsvox-pronounce-dictionaries (make-hash-table :test #'eq))
          (emacsvox-pronounce-dictionaries-loaded t)
          (emacsvox-pronounce-dictionaries-file
           (expand-file-name "dictionary.el" (file-name-directory custom-file))))
      (execute-kbd-macro (kbd "s p d"))
      (should-not (buffer-local-value 'emacsvox-pronounce-table source))
      (execute-kbd-macro (vconcat (kbd "d") "buffer" (kbd "RET") "localword" (kbd "RET") "local speech" (kbd "RET")))
      (should (equal (gethash "localword" (buffer-local-value 'emacsvox-pronounce-table source)) "local speech"))
      (should (zerop (hash-table-count emacsvox-pronounce-dictionaries)))
      (execute-kbd-macro (vconcat (kbd "d") "mode" (kbd "RET") "modeword" (kbd "RET") "mode speech" (kbd "RET")))
      (should (equal (emacsvox-pronounce-get-dictionary 'text-mode) '(("modeword" . "mode speech"))))
      (should-not (gethash "localword" (buffer-local-value 'emacsvox-pronounce-table source)))
      (should-not (file-exists-p emacsvox-pronounce-dictionaries-file))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) emacsvox-pronounce-dictionaries-file)))
        (execute-kbd-macro (kbd "w")))
      (should-not (file-exists-p custom-file))
      (with-temp-buffer
        (insert-file-contents emacsvox-pronounce-dictionaries-file)
        (should (search-forward "modeword" nil t))
        (should-not (search-forward "localword" nil t)))
      (setq emacsvox-pronounce-dictionaries (make-hash-table :test #'eq))
      (with-current-buffer source (setq emacsvox-pronounce-table nil))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) emacsvox-pronounce-dictionaries-file)))
        (execute-kbd-macro (kbd "l")))
      (should (equal (emacsvox-pronounce-get-dictionary 'text-mode) '(("modeword" . "mode speech"))))
      (should-not (buffer-local-value 'emacsvox-pronounce-table source))
      (execute-kbd-macro (kbd "r"))
      (should (equal (gethash "modeword" (buffer-local-value 'emacsvox-pronounce-table source)) "mode speech"))
      (execute-kbd-macro (kbd "t"))
      (should-not (buffer-local-value 'emacsvox-pronounce-table source))
      (execute-kbd-macro (kbd "t q"))
      (should (gethash "modeword" (buffer-local-value 'emacsvox-pronounce-table source)))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-punctuation)))))

(ert-deftest emacsvox-settings-dictionaries-editor-fields-and-return ()
  "Widget text remains editable; return/reopen preserves fields without saving."
  (emacsvox-test--with-settings
    (let ((emacsvox-pronounce-dictionaries (make-hash-table :test #'eq))
          (emacsvox-pronounce-dictionaries-loaded t)
          editor before)
      (emacsvox-pronounce-set-dictionary 'emacsvox-test-menu-dictionary '(("word" . "speech")))
      (unwind-protect
          (progn
            (execute-kbd-macro (kbd "s p d"))
            (execute-kbd-macro (vconcat (kbd "e") "emacsvox-test-menu-dictionary" (kbd "RET")))
            (setq editor (current-buffer))
            (should (string-prefix-p "*Dict:" (buffer-name)))
            (should-not (buffer-local-value 'emacsvox-pronounce-table source))
            (goto-char (point-min))
            (search-forward "word")
            (should (widget-field-at (point)))
            (should (eq (key-binding (kbd "q")) 'self-insert-command))
            (execute-kbd-macro "q")
            (should (string-match-p "wordq" (buffer-string)))
            (setq before (buffer-string))
            (execute-kbd-macro (kbd "C-c C-c"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-dictionaries))
            (with-selected-window transient--window
              (should (equal (oref (button-get (button-at (point)) 'button-data) key) "e")))
            (should (equal (emacsvox-pronounce-get-dictionary 'emacsvox-test-menu-dictionary)
                           '(("wordq" . "speech"))))
            (with-current-buffer editor
              (should-not emacsvox-settings-workflows--dictionary-return-mode)
              (should (eq (current-local-map) widget-keymap)))
            (execute-kbd-macro (vconcat (kbd "e") "emacsvox-test-menu-dictionary" (kbd "RET")))
            (should (eq (current-buffer) editor))
            (should (equal (buffer-string) before))
            (goto-char (point-min))
            (execute-kbd-macro (kbd "q"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-dictionaries))
            (should-not (file-exists-p custom-file)))
        (when (buffer-live-p editor)
          (with-current-buffer editor (set-buffer-modified-p nil))
          (kill-buffer editor))))))

(ert-deftest emacsvox-settings-dictionaries-cancel-and-failed-open ()
  "Cancelled prompts and absent dictionaries retain the menu and its source."
  (emacsvox-test--with-settings
    (let ((emacsvox-pronounce-dictionaries (make-hash-table :test #'eq)))
      (execute-kbd-macro (kbd "s p d"))
      (condition-case nil (execute-kbd-macro (kbd "e")) (user-error nil))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-dictionaries))
      (emacsvox-pronounce-set-dictionary 'text-mode '(("word" . "speech")))
      (execute-kbd-macro (kbd "e C-g"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-dictionaries))
      (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
      (should-not (buffer-local-value 'emacsvox-pronounce-table source))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) "/nonexistent/emacsvox-test-dictionary")))
        (should-error (emacsvox-settings-workflows--dictionary-load) :type 'user-error))
      (should-not (file-exists-p custom-file)))))

(provide 'emacsvox-settings-workflows-tests)
;;; emacsvox-settings-workflows-tests.el ends here
