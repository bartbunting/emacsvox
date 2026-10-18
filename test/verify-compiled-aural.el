;;; verify-compiled-aural.el --- Clean compiled aural checks -*- lexical-binding: t; -*-

;;; Commentary:

;; This file is run only by `run-compiled-aural-tests.el' in a clean child
;; Emacs whose build directory contains freshly compiled aural entry points.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'subr-x)

(let* ((build-directory
        (or
         (getenv "EMACSVOX_COMPILED_AURAL_DIR")
         (error "EMACSVOX_COMPILED_AURAL_DIR is not set")))
       (root-directory
        (or
         (getenv "EMACSVOX_COMPILED_AURAL_ROOT")
         (error "EMACSVOX_COMPILED_AURAL_ROOT is not set")))
       (lisp-directory (expand-file-name "lisp/" root-directory)))
  (add-to-list 'load-path lisp-directory)
  (add-to-list 'load-path build-directory)
  (load (expand-file-name "emacsvox-paths.el" build-directory) nil t t)
  (emacsvox-paths--register build-directory)
  (dolist
      (library
       '("aural/emacsvox-aural"
         "aural/emacsvox-aural-concrete"
         "aural/emacsvox-aural-spatial"
         "aural/emacsvox-aural-rules"
         "aural/emacsvox-aural-description"))
    (load
     (expand-file-name (concat library ".elc") build-directory)
     nil nil))
  (dolist
      (feature
       '(emacsvox-aural-resources
         emacsvox-aural-schemes
         emacsvox-aural-profile-service
         emacsvox-aural-compatibility-voice
         emacsvox-aural-compiler
         emacsvox-aural-planner
         emacsvox-aural-transport))
    (when (featurep feature)
      (error
       "Pure aural description boundary loaded higher layer %S"
       feature)))
  (load
   (expand-file-name "aural/emacsvox-aural-history.elc" build-directory)
   nil nil)
  (dolist
      (feature
       '(emacsvox-aural-resources
         emacsvox-aural-schemes
         emacsvox-aural-profile-service
         emacsvox-aural-compatibility-voice
         emacsvox-aural-compiler
         emacsvox-aural-planner
         emacsvox-aural-transport))
    (when (featurep feature)
      (error
       "Aural history boundary loaded higher layer %S"
       feature)))
  (dolist (library '("speech/omnivox-control-codec"
                     "aural/emacsvox-aural-timeline-codec"))
    (load (expand-file-name (concat library ".elc") build-directory) nil nil))
  (dolist (feature '(tts-speak omnivox-voices emacsvox-aural-transport
                    omnivox-library emacsvox-aural-voice-workbench))
    (when (featurep feature)
      (error "Wire codec loaded runtime or editor %S" feature)))
  (when (process-list)
    (error "Wire codec started a process"))
  ;; Generic voice definitions must not initialize an adapter or speech runtime.
  (load (expand-file-name "speech/tts-voice-api.elc" build-directory) nil nil)
  (dolist (feature '(tts-speak tts-lifecycle voice-setup omnivox-voices))
    (when (featurep feature)
      (error "Voice API loaded speech runtime %S" feature)))
  (when (process-list)
    (error "Voice API started a process"))
  (load
   (expand-file-name "aural/emacsvox-aural-schemes.elc" build-directory)
   nil nil)
  (when (featurep 'emacsvox-aural-profile-service)
    (error "Aural scheme storage loaded profile coordination"))
  (dolist
      (function
       '(emacsvox-aural-capture-profile-data
         emacsvox-aural-apply-profile
         emacsvox-aural-profile-status))
    (unless (autoloadp (symbol-function function))
      (error "Aural scheme compatibility entry is not autoloaded: %S" function)))
  (dolist
      (library
       '("aural/emacsvox-aural-profile-service"
         "aural/emacsvox-aural-providers"
         "aural/emacsvox-aural-compiler"
         "aural/emacsvox-aural-source"
         "aural/emacsvox-aural-planner"
         "aural/emacsvox-aural-submission"
         "ui/emacsvox-aural-ui"
         "aural/emacsvox-aural-inspection"))
    (load
     (expand-file-name (concat library ".elc") build-directory)
     nil nil))
  (load
   (expand-file-name
    "aural/emacsvox-aural-compatibility-voice.elc"
    build-directory)
   nil nil)
  (dolist (feature '(tts-speak voice-setup))
    (when (featurep feature)
      (error
       "Compatibility voice policy loaded low-level provider %S"
       feature)))
  (unless
      (string-match-p
       "aural/emacsvox-aural-compatibility-voice"
       (or (symbol-file 'voice-lock-mode 'defun) ""))
    (error "Aural compatibility policy does not own voice-lock-mode"))
  (when (featurep 'emacsvox-aural-transport)
    (error
     "Aural compiler, planner, source, and inspection loaded queue transport"))
  ;; Lifecycle definitions load independently, without initializing the facade.
  (load (expand-file-name "speech/tts-lifecycle.elc" build-directory) nil nil)
  (when (or (featurep 'tts-speak) (process-list))
    (error "Loading TTS lifecycle initialized speech"))
  (dolist
      (library
       '("speech/tts-queue-state"
         "speech/omnivox-remote"
         "speech/tts-speak"
         "speech/voice-setup"
         "voices/voice-defs"
         "speech/dectalk-voices"
         "speech/plain-voices"
         "speech/espeak-voices"
         "speech/outloud-voices"
         "speech/mac-voices"
         "speech/swiftmac-voices"
         "speech/omnivox-preview"
         "speech/omnivox-voices"
         "core/emacsvox-pronounce"
         "core/emacsvox-speak"
         "aural/emacsvox-aural-transport"
         "aural/emacsvox-aural-preview"
         "aural/emacsvox-aural-validation"
         "ui/emacsvox-aural-semantics"
         "aural/emacsvox-aural-explanation"
         "aural/emacsvox-aural-tools"
         "ui/emacsvox-aural-recent-feedback"
         "ui/emacsvox-aural-feedback-details"
         "ui/emacsvox-aural-feature-fragments"
         "ui/emacsvox-omnivox-components"
         "ui/emacsvox-aural-home"
         "aural/emacsvox-aural-routing-profiles"
         "ui/emacsvox-aural-editor"
         "ui/emacsvox-aural-overrides"
         "ui/emacsvox-aural-doctor"
         "ui/emacsvox-aural-profiles"
         "ui/emacsvox-aural-voice-palettes"
         "ui/emacsvox-aural-change-feedback"
         "ui/emacsvox-aural-voice-workbench"
         "aural/emacsvox-aural-provider-org"
         "aural/emacsvox-aural-provider-org-srs"
         "aural/emacsvox-aural-provider-workflows"
         "aural/emacsvox-aural-provider-markdown"
         "aural/emacsvox-aural-provider-notmuch"
         "aural/emacsvox-sounds"
         "ui/emacsvox-aural-sound-packs"
         "core/emacsvox-keymap"))
    (load
     (expand-file-name (concat library ".elc") build-directory)
     nil nil))
  (dolist (external-feature '(org markdown-mode notmuch))
    (when (featurep external-feature)
      (error
       "Data-only providers loaded external package feature %S"
       external-feature)))
  (dolist
      (function
       '(tts-voice-capabilities
         tts-voice-inventory
         tts-apply-voice-configuration
         tts--call-with-preparation
         tts--dispatch-command
         tts--interrupt-process
         tts--retire-process
         tts--speech-process-sentinel
         tts--protocol-queue-text
         voice-from-acss
         dectalk-voice-capabilities
         plain-voice-capabilities
         espeak-voice-capabilities
         outloud-voice-capabilities
         mac-voice-capabilities
         swiftmac-voice-capabilities
         omnivox-voice-capabilities
         omnivox--encode-control-request
         omnivox--preview-selector-json
         omnivox-library--edit-selection
         emacsvox-aural--frame-structured-timeline
         emacsvox-aural-voice-workbench--entries
         omnivox-remote-make-process
         emacsvox-pronounce-refresh-pronunciations
         emacsvox-speak-line
         voice-setup-face-mapping-diagnostic
         voice-setup-face-mapping-conflicts
         emacsvox-aural-compatibility-voice-enabled-p
         emacsvox-aural-voice-lock-enabled-p
         emacsvox-aural-set-compatibility-voice-enabled
         emacsvox-aural-toggle-compatibility-voice
         emacsvox-aural--make-concrete-plan
         emacsvox-aural-record-presentation
         emacsvox-aural-call-with-presentation-transaction
         emacsvox-aural-presentation-record-effective-plans
         emacsvox-aural-presentation-record-effective-transaction-id
         emacsvox-aural-spatial-clamp
         emacsvox-aural--rule-error
         emacsvox-aural-rule-actions
         emacsvox-aural-resolve-legacy-icon-adapter
         emacsvox-aural--resource-error
         emacsvox-aural--migrate-user-data-v1-to-v2
         emacsvox-aural-current-profile-id
         emacsvox-aural-effective-resource-pack
         emacsvox-aural-compile-plan
         emacsvox-aural-capture-source-faces
         emacsvox-aural-call-with-submission
         emacsvox-aural-prepare-text
         emacsvox-aural-compatibility-icon
         emacsvox-aural-submit
         emacsvox-aural-submit-actions
         emacsvox-aural--transport-error
         emacsvox-aural-describe-selector
         emacsvox-aural-preview-play-plan
         emacsvox-aural-preview-play-runs
         emacsvox-aural-validation--report
         emacsvox-aural-inspection-source-buffer
         emacsvox-aural-semantics--set-entries
         emacsvox-aural-explanation--training-presented
         emacsvox-aural-recent-feedback--entries
         emacsvox-aural-ui-announce-boundary
         emacsvox-aural-feature-fragments-install-state
         emacsvox-aural-feature-fragments-refresh-if-live
         emacsvox-aural-feature-fragments--set-entries
         emacsvox-omnivox-components--parse
         emacsvox-aural-home--entries
         emacsvox-aural-editor--scope-label
         emacsvox-aural-editor-open-prefilled-rule
         emacsvox-aural-editor-normalized-rules
         emacsvox-aural-overrides--collect
         emacsvox-aural-doctor--finding
         emacsvox-aural-profiles--ids
         emacsvox-aural-voice-palettes--active-id
         emacsvox-aural-change-feedback
         emacsvox-org--require-aural-semantics
         emacsvox-aural-register-workflow-provider
         emacsvox-markdown-register-aural-presentation
         emacsvox-notmuch-register-aural-preview-examples
         emacsvox-toggle-icons
         emacsvox-aural-sound-packs--symbol-less-p
         emacsvox-keymap-update))
    (unless
        (string-suffix-p
         ".elc" (or (symbol-file function 'defun) ""))
      (error "%S was not loaded from byte-code: %S"
             function (symbol-file function 'defun))))
  (dolist (function '(tts-queue--observe-string tts-queue--send omnivox-voice-capabilities omnivox-remote-make-process))
    (unless (file-in-directory-p (symbol-file function 'defun) build-directory)
      (error "%S escaped the isolated compiled build: %S"
             function (symbol-file function 'defun))))
  (unless
      (string-suffix-p
       ".elc" (or (symbol-file 'voice-animate 'defvar) ""))
    (error "voice-animate was not loaded from byte-code: %S"
           (symbol-file 'voice-animate 'defvar)))
  (dolist
      (feature
       '(emacsvox-aural-scheme-manager emacsvox-aural-simple-editor))
    (when (featurep feature)
      (error "Retired scheme interface was loaded: %S" feature)))
  (dolist
      (command
       '(emacsvox-list-aural-schemes
         emacsvox-set-aural-scheme
         emacsvox-aural-select-scheme
         emacsvox-edit-aural-scheme
         emacsvox-edit-aural-scheme-advanced
         emacsvox-aural-voice-palettes-follow-scheme))
    (when (fboundp command)
      (error "Retired scheme command remains available: %S" command)))
  (unless (eq (lookup-key emacsvox-keymap (kbd "H")) 'emacsvox-aural-menu)
    (error "Compiled keymap does not bind C-e H to settings"))
  (unless (eq (lookup-key emacsvox-keymap (kbd "S"))
              'emacsvox-settings-for-buffer)
    (error "Compiled keymap does not bind C-e S to current-buffer settings"))
  (unless
      (eq
       (lookup-key emacsvox-keymap (kbd "E"))
       'emacsvox-aural-explain-presentation)
    (error "Compiled keymap does not bind C-e E to explanation"))
  (let ((emacsvox-aural-session-rules
         (list
          '(:id compiled-preview
            :match (:role heading)
            :render
            (:before
             ((:id label :kind speech :text "Compiled preview"))))))
        stopped ensured queued dispatched)
    (cl-letf
        (((symbol-function 'emacsvox-aural-preview-stop)
          (lambda () (setq stopped t)))
         ((symbol-function 'emacsvox-aural--ensure-speaker)
          (lambda () (setq ensured t)))
         ((symbol-function 'emacsvox-aural-queue-concrete-plan)
          (lambda (plan &rest _) (setq queued plan)))
         ((symbol-function 'tts--protocol-dispatch)
          (lambda () (setq dispatched t))))
      (emacsvox-preview-aural-rule
       'compiled-preview
       '(:role heading :content "Title")
       '(:occasion navigation)))
    (unless
        (and
         stopped ensured dispatched
         (equal
          (emacsvox-aural-concrete-action-text
           (car (emacsvox-aural-concrete-plan-before queued)))
          "Compiled preview"))
      (error "Compiled preview bypassed replaceable boundaries")))
  (let ((plan
         (emacsvox-aural--make-concrete-plan
          :facts '(:role heading :level 2)
          :context '(:occasion navigation)))
        events)
    (cl-letf
        (((symbol-function 'emacsvox-aural-compile-voice)
          (lambda (voice)
            (unless (eq voice 'annotate)
              (error "Unexpected training voice: %S" voice))
            "TRAINING"))
         ((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
         ((symbol-function 'tts--protocol-queue-code)
          (lambda (code) (push (list 'code code) events)))
         ((symbol-function 'tts--protocol-queue-text)
          (lambda (text) (push (list 'text text) events))))
      (emacsvox-aural-explanation--training-presented plan))
    (unless
        (equal
         (nreverse events)
         '((code "RESET")
           (code "TRAINING")
           (text "heading, level 2, navigation occasion.")
           (code "RESET")))
      (error "Compiled training bypassed protocol extension points: %S"
             events)))
  (let* ((calls 0)
         (advice (lambda (&rest _) (cl-incf calls))))
    (unwind-protect
        (progn
          (advice-add 'tts--protocol-stop :before advice)
          (cl-letf
              (((symbol-function 'process-send-string)
                (lambda (&rest _) nil)))
            (let ((tts-speaker-process 'speaker))
              (tts--protocol-stop)))
          (unless (= calls 1)
            (error "Compiled protocol function bypassed native advice")))
      (advice-remove 'tts--protocol-stop advice)))
  ;; Reuse the independently stated style and delivery contracts with the compiled rules,
  ;; compiler, adapter, and transport already resident.  Test files require
  ;; these features; they must not reload their source implementations.
  (dolist (file '("emacsvox-aural-rules-tests.el"
                  "emacsvox-aural-schemes-tests.el"
                  "emacsvox-aural-voice-data-tests.el"
                  "emacsvox-aural-voice-runtime-tests.el"
                  "emacsvox-aural-voice-drafts-tests.el"
                  "emacsvox-aural-voice-editing-tests.el"
                  "emacsvox-aural-voice-choice-tests.el"
                  "omnivox-choice-codec-tests.el"
                  "omnivox-choice-registration-tests.el"
                  "omnivox-choice-timeline-tests.el"
                  "omnivox-choice-playback-tests.el"
                  "tts-dispatch-handoff-tests.el"
                  "tts-preparation-tests.el"
                  "tts-queue-state-tests.el"
                  "emacsvox-tts-tests.el"
                  "omnivox-preview-tests.el"
                  "emacsvox-emoji-tests.el"
                  "emacsvox-emoji-integration-tests.el"
                  "emacsvox-aural-voice-editor-tests.el"
                  "omnivox-espeak-variants-tests.el"
                  "emacsvox-aural-voice-bulk-tests.el"
                  "emacsvox-aural-voice-context-tests.el"
                  "emacsvox-aural-transport-tests.el"
                  "omnivox-choice-consumer-tests.el"
                  "tts-queue-handoff-tests.el"
                  "emacsvox-aural-voice-palettes-tests.el"
                  "emacsvox-aural-voice-workbench-tests.el"))
    (load (expand-file-name (concat "test/" file) root-directory) nil nil t))
  (dolist (function '(emacsvox-aural-profile-set-startup-palette
         emacsvox-aural-voice-data--read-exchange
         emacsvox-aural-voice-palettes-import
         emacsvox-aural-voice-data--resolve
                     emacsvox-aural-voice-data--put-choices
                     emacsvox-aural-routing--validate-choices
                     emacsvox-aural-voice-runtime--resolve
                     emacsvox-aural-voice-drafts--save
                     emacsvox-aural-voice-editing--proposal
                     emacsvox-aural-voice-editor-open
                     emacsvox-aural-voice-bulk-open
                     emacsvox-aural-voice-context--resolve
                      emacsvox-aural--validate-voice-style
                      emacsvox-aural--voice-style-field
                      emacsvox-aural-compile-voice-style
                      omnivox--accept-registration-response
                      tts--dispatch-arm
                      tts--call-with-preparation
                      tts--preparation-interrupt
                      tts--dispatch-publish
                      tts--dispatch-drain
                      tts--consume-process-lines
                      omnivox--prepare-choice-dispatch
                      omnivox--choice-receipt-context
                      omnivox--handle-choice-marker
                      omnivox--choice-decode-marker
                      omnivox--choice-span-projection
                      omnivox--choice-patch-json
                      omnivox--preview-sequence
                      omnivox--preview-drive
                      omnivox--preview-token-operation
                      emacsvox-aural-voice-editing--keep-for-choice
                      emacsvox-aural-voice-editor--read-choice
                      emacsvox-aural-voice-editing--field-sources
                      emacsvox-aural-voice-editor--explain-playback
                      emacsvox-aural-voice-editor--set-choice
                      emacsvox-aural-voice-editor--tuning-style
                      emacsvox-aural-voice-editor--submit-preview
                      emacsvox-emoji--prepare
                      emacsvox-aural--prepare-emoji-text
                      tts--emoji-preview-entries
                      emacsvox-aural-voice-context--preview
                      emacsvox-aural-voice-editing--cascade
                      emacsvox-aural-voice-editing--legacy-preview
                      omnivox--portable-style-acss
                      emacsvox-aural--timeline-style-acss
                      emacsvox-aural--timeline-effect-transition
                      emacsvox-aural--encode-timeline-delivery-fields
                      emacsvox-aural--timeline-delivery-fields
                      emacsvox-aural--build-structured-timeline
                      emacsvox-aural--finalize-structured-delivery
                      emacsvox-aural-voice-workbench--preview-effects
                      emacsvox-aural-voice-editor--set))
    (unless (file-in-directory-p (symbol-file function 'defun) build-directory)
      (error "Aural contract escaped compiled build: %S" function)))
  (dolist (tag '(voice-style-ui voice-palette-tools delivery-preparation))
    (unless (ert-select-tests (list 'tag tag) t)
      (error "No compiled %S contracts were loaded" tag)))
  (let ((stats
         (ert-run-tests-batch
          '(and (not (member emacsvox-emoji-graphical-explanation-is-visible
                             emacsvox-aural-voice-bulk-graphical-browser-review-cancel-and-save
                             emacsvox-aural-voice-editor-graphical-save-remains-visible
                             emacsvox-aural-voice-editor-graphical-more-controls-below-button))
                (or "^emacsvox-emoji-" "^emacsvox-aural-rules-"
               "^emacsvox-aural-voice-data-"
               "^emacsvox-aural-voice-runtime-"
               "^emacsvox-aural-voice-drafts-"
               "^emacsvox-aural-voice-editing-"
               "^emacsvox-aural-voice-choice-"
               "^omnivox-choice-codec-"
               "^omnivox-choice-registration-"
               "^omnivox-choice-timeline-"
               "^omnivox-choice-playback-"
               "^omnivox-choice-consumer-"
               "^omnivox-preview-"
               "^tts-queue-"
               "^tts-handoff-"
               "^tts-preparation-"
               "^emacsvox-aural-voice-editor-"
               "^emacsvox-aural-voice-bulk-"
               "^emacsvox-aural-voice-context-"
               (tag voice-palette-tools)
                    (tag voice-style-ui)
               (tag delivery-preparation)
               emacsvox-aural-delivery-keeps-stops-immediate-and-cancellable
               emacsvox-aural-delivery-contains-process-send-failure
               emacsvox-aural-schemes-persist-personal-voice-palettes
               emacsvox-aural-native-voice-fields-preserve-zero-and-omission
               emacsvox-aural-native-saved-style-matches-voice-previews
               emacsvox-aural-voice-workbench-logical-preview-carries-effects
               emacsvox-aural-voice-workbench-preview-preserves-effect-scale
               emacsvox-aural-transport-preset-nil-and-zero-retain-current-behavior)))))
    (unless (and (> (ert-stats-total stats) 0)
                 (= (ert-stats-completed stats) (ert-stats-total stats))
                 (= (ert-stats-completed-unexpected stats) 0)
                 (= (ert-stats-skipped stats) 0))
      (error "Compiled Aural contracts failed"))))

;;; verify-compiled-aural.el ends here
