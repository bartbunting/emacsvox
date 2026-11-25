;;; focused-graphical-final.el --- Disposable audit check -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off reproduction; see the investigation report.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(dolist (feature '(emacsvox-comint-tests emacsvox-markdown-tests emacsvox-org-tests
                   emacsvox-eww-tests emacsvox-dired-tests emacsvox-settings-tests
                   emacsvox-sound-library-tests emacsvox-advice-tests))
  (require feature))
(let ((profile (expand-file-name "graphical-private-profile/" audit-out)))
  (setq user-emacs-directory profile custom-file (expand-file-name "custom.el" profile)
        user-init-file custom-file emacsvox-user-directory (expand-file-name "data/" profile))
  (make-directory emacsvox-user-directory t))
(load (expand-file-name "lisp/emacsvox-loaddefs.el" audit-root) nil t)
(dolist (feature '(markdown-mode agent-shell eat notmuch magit)) (require feature))
(setq tts-speaker-process (make-process :name "audit-menu-main" :noquery t
                                      :command (list (expand-file-name "servers/log-null" audit-root)))
      tts-notify-process (make-process :name "audit-menu-notify" :noquery t
                                     :command (list (expand-file-name "servers/log-null" audit-root))))
(when-let* ((directory (getenv "EMACSVOX_AUDIT_VERTICO")))
  (add-to-list 'load-path directory))
(require 'emacsvox-aural-provider-notmuch)
(require 'plain-voices)
;; This test macro clears preview registries after the provider was loaded.
;; Restore its data in each isolated registry, as a normal profile retains it.
(advice-add 'emacsvox-aural--register-default-scheme :after
            (lambda (&rest _) (emacsvox-aural-register-workflow-provider) (emacsvox-notmuch-register-aural-preview-examples)))
(advice-add 'message :after
            (lambda (format-string &rest args)
              (when format-string
                (with-temp-buffer
                  (insert (apply #'format-message format-string args) "\n")
                  (write-region (point-min) (point-max)
                                (expand-file-name "focused-graphical-final.log" audit-out) t 'silent)))))
(condition-case failure
    (progn
      (unless (display-graphic-p) (error "Graphical frame required"))
      (let ((stats (ert-run-tests-batch '(member emacsvox-aural-menu-graphical-detailed-descriptions emacsvox-aural-menu-graphical-direct-speech-and-button-entry emacsvox-aural-menu-graphical-enter-activates-focused-item emacsvox-aural-menu-graphical-feedback-opens-real-details emacsvox-aural-menu-graphical-first-toggle-does-not-repeat-introduction emacsvox-aural-menu-graphical-help-replaces-aural-origin emacsvox-aural-menu-graphical-help-returns-to-menu emacsvox-aural-menu-graphical-help-selection-is-spoken emacsvox-aural-menu-graphical-links-scope-and-refresh emacsvox-aural-menu-graphical-manual-announces-entry emacsvox-aural-menu-graphical-manual-returns-to-menu emacsvox-aural-menu-graphical-navigation-style-and-save emacsvox-aural-menu-graphical-quit-announces-return-buffer emacsvox-aural-menu-graphical-review-keeps-selection-and-activation emacsvox-aural-menu-graphical-speech-order-and-navigation-entry emacsvox-aural-menu-graphical-submenu-return-targets emacsvox-aural-menu-graphical-task-sections emacsvox-aural-menu-output-graphical-adjust-and-return emacsvox-aural-menu-output-graphical-browser-keeps-source emacsvox-aural-menu-speech-graphical-rate-and-punctuation emacsvox-aural-menu-speech-graphical-save-survives-startup emacsvox-aural-menu-voices-graphical-engine-save-is-explicit emacsvox-aural-menu-voices-graphical-palettes-return-and-direct-entry emacsvox-aural-menu-voices-graphical-workbench-return-and-drafts emacsvox-aural-voice-workbench-graphical-engine-browser-return emacsvox-aural-workbench-graphical-engine-management-round-trip emacsvox-aural-workbench-graphical-espeak-tree-navigation emacsvox-aural-workbench-graphical-filter-search-and-editor-return emacsvox-aural-workbench-graphical-language-navigation-and-refresh emacsvox-aural-workbench-graphical-quit-unwinds-voice-browser emacsvox-capitalization-menu-graphical-cue-drafts-and-focus emacsvox-capitalization-menu-graphical-save-customize-and-reset emacsvox-capitalization-menu-graphical-scope-preview-and-defaults emacsvox-capitalization-parent-volume-graphical-focus-and-save emacsvox-capitalization-presentation-graphical-browse-return-and-cancel emacsvox-capitalization-shared-editor-graphical-return-and-save emacsvox-eww-link-navigation-keeps-graphical-url-echo emacsvox-indentation-menu-graphical-adjustment-bindings-stay-local emacsvox-indentation-menu-graphical-shift-arrows-adjust-volume emacsvox-indentation-menu-graphical-shortcuts-and-scope emacsvox-indentation-menu-graphical-tone-controls-and-return emacsvox-indentation-menu-navigation-cues-follow-active-choice emacsvox-indentation-shared-editor-graphical-navigation emacsvox-menu-choices-graphical-device-and-custom-mapping emacsvox-menu-choices-graphical-output-browse-and-return emacsvox-menu-choices-graphical-point-scope-and-return emacsvox-menu-prompts-graphical-earcon-focus emacsvox-menu-prompts-graphical-retain-focus-on-accept-and-cancel emacsvox-menu-prompts-graphical-shortcut-error-and-preset-focus emacsvox-settings-action-aliases-have-one-destination emacsvox-settings-actions-cover-home-without-activation emacsvox-settings-focused-reading-enter emacsvox-settings-library-preview-browses-applies-saves-and-returns emacsvox-settings-menu-action-search-and-return emacsvox-settings-menu-buffer-mode-and-custom-return emacsvox-settings-menu-search-alias-and-substring-selection emacsvox-settings-menu-search-cancel-keeps-menu emacsvox-settings-menu-search-every-destination emacsvox-settings-menu-search-partial-name-and-mixed-case emacsvox-settings-menu-search-preserves-source-and-scope emacsvox-settings-reading-enter-activation emacsvox-settings-return-source-restores-captured-position emacsvox-settings-search-literal-spaces-and-prompt-isolation emacsvox-settings-tone-search-keeps-parent-context emacsvox-sound-library-assignment-graphical-alphabetical-prompts emacsvox-sound-library-graphical-batch-cancel-and-return emacsvox-sound-library-graphical-cue-return-keeps-row))))
        (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))
  (error (message "Graphical runner error: %S" failure) (kill-emacs 2)))

;;; focused-graphical-final.el ends here
