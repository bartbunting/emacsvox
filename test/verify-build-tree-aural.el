;;; verify-build-tree-aural.el --- Verify the normal aural build -*- lexical-binding: t; -*-

;;; Commentary:

;; Build the normal aural target in `lisp/Makefile' before running this file.
;; check starts from the documented setup entry point and confirms that every
;; shipped aural component is available as current byte-code.

;;; Code:

(require 'subr-x)

(let* ((test-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (root-directory (expand-file-name "../" test-directory))
       (lisp-directory (expand-file-name "lisp/" root-directory))
       (setup (expand-file-name "emacsvox-setup.elc" lisp-directory))
       (features
        '(tts-speak
          voice-setup
          voice-defs
          dectalk-voices
          plain-voices
          espeak-voices
          outloud-voices
          mac-voices
          swiftmac-voices
          emacsvox-pronounce
          emacsvox-speak
          emacsvox-aural
          emacsvox-aural-compatibility-voice
          emacsvox-aural-concrete
          emacsvox-aural-history
          emacsvox-aural-spatial
          emacsvox-aural-rules
          emacsvox-aural-resources
          emacsvox-aural-schemes
          emacsvox-aural-routing-profiles
          emacsvox-aural-profile-service
          emacsvox-aural-providers
          emacsvox-aural-compiler
          emacsvox-aural-source
          emacsvox-aural-planner
          emacsvox-aural-transport
          emacsvox-aural-submission
          emacsvox-aural-preview
          emacsvox-aural-validation
          emacsvox-aural-ui
          emacsvox-aural-inspection
          emacsvox-aural-semantics
          emacsvox-aural-explanation
          emacsvox-aural-tools
          emacsvox-aural-editor
          emacsvox-aural-doctor
          emacsvox-aural-profiles
          emacsvox-aural-voice-palettes
          emacsvox-aural-voice-workbench
          emacsvox-aural-voice-experiment
          emacsvox-aural-provider-org
          emacsvox-aural-provider-org-srs
          emacsvox-aural-provider-workflows
          emacsvox-aural-provider-markdown
          emacsvox-aural-provider-notmuch
          emacsvox-sounds
          emacsvox-aural-sound-packs))
       (functions
        '(tts--protocol-queue-text
          voice-from-acss
          dectalk-voice-capabilities
          plain-voice-capabilities
          espeak-voice-capabilities
          outloud-voice-capabilities
          mac-voice-capabilities
          swiftmac-voice-capabilities
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
          emacsvox-aural-preview-play-plan
          emacsvox-aural-preview-play-runs
          emacsvox-aural-validation--report
          emacsvox-aural-ui-interface-buffer-p
          emacsvox-aural-ui-announce-boundary
          emacsvox-aural-inspection-source-buffer
          emacsvox-aural-semantics--set-entries
          emacsvox-aural-explanation--training-presented
          emacsvox-aural-feature-fragments-install-state
          emacsvox-aural-feature-fragments-refresh-if-live
          emacsvox-aural-editor--scope-label
          emacsvox-aural-editor-open-prefilled-rule
          emacsvox-aural-editor-normalized-rules
          emacsvox-aural-doctor--finding
          emacsvox-aural-profiles--ids
          emacsvox-aural-voice-palettes--active-id
          emacsvox-aural-voice-experiment-open
          emacsvox-org--require-aural-semantics
          emacsvox-aural-register-workflow-provider
          emacsvox-markdown-register-aural-presentation
          emacsvox-notmuch-register-aural-preview-examples
          emacsvox-toggle-icons
          emacsvox-aural-sound-packs--symbol-less-p)))
  (add-to-list 'load-path lisp-directory)
  (unless (file-exists-p setup)
    (error "Normal build did not create %s" setup))
  (load setup nil nil)
  (dolist (feature features)
    (require feature))
  (dolist (external-feature '(org markdown-mode notmuch))
    (when (featurep external-feature)
      (error
       "Data-only providers loaded external package feature %S"
       external-feature)))
  (dolist (function functions)
    (let ((file (symbol-file function 'defun)))
      (unless (and file (string-suffix-p ".elc" file))
        (error "%S was not loaded from normal byte-code: %S" function file))))
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
  (unless
      (string-suffix-p
       ".elc" (or (symbol-file 'voice-animate 'defvar) ""))
    (error "voice-animate was not loaded from normal byte-code: %S"
           (symbol-file 'voice-animate 'defvar)))
  (when-let* ((stale (emacsvox-setup--stale-byte-code lisp-directory)))
    (error "Normal aural build left stale byte-code: %S" stale)))

(princ "Normal build-tree aural startup checks passed\n")

;;; verify-build-tree-aural.el ends here
