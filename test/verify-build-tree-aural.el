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
          emacsvox-aural-concrete
          emacsvox-aural-history
          emacsvox-aural-spatial
          emacsvox-aural-rules
          emacsvox-aural-resources
          emacsvox-aural-schemes
          emacsvox-aural-source
          emacsvox-aural-transport
          emacsvox-aural-preview
          emacsvox-aural-validation
          emacsvox-aural-ui
          emacsvox-aural-inspection
          emacsvox-aural-semantics
          emacsvox-aural-explanation
          emacsvox-aural-tools
          emacsvox-aural-editor
          emacsvox-aural-simple-editor
          emacsvox-aural-doctor
          emacsvox-aural-profiles
          emacsvox-aural-voice-palettes
          emacsvox-aural-provider-org
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
          emacsvox-aural-voice-lock-enabled-p
          emacsvox-aural--make-concrete-plan
          emacsvox-aural-record-presentation
          emacsvox-aural-spatial-clamp
          emacsvox-aural--rule-error
          emacsvox-aural--resource-error
          emacsvox-aural--migrate-user-data-v1-to-v2
          emacsvox-aural-capture-source-faces
          emacsvox-aural--transport-error
          emacsvox-aural-preview-play-plan
          emacsvox-aural-validation--report
          emacsvox-aural-ui-interface-buffer-p
          emacsvox-aural-inspection-source-buffer
          emacsvox-aural-semantics--set-entries
          emacsvox-aural-explanation--training-presented
          emacsvox-aural-editor--scope-label
          emacsvox-aural-simple-editor--humanize
          emacsvox-aural-doctor--finding
          emacsvox-aural-profiles--ids
          emacsvox-aural-voice-palettes--active-id
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
  (unless
      (string-suffix-p
       ".elc" (or (symbol-file 'voice-animate 'defvar) ""))
    (error "voice-animate was not loaded from normal byte-code: %S"
           (symbol-file 'voice-animate 'defvar)))
  (when-let* ((stale (emacsvox-setup--stale-byte-code lisp-directory)))
    (error "Normal aural build left stale byte-code: %S" stale)))

(princ "Normal build-tree aural startup checks passed\n")

;;; verify-build-tree-aural.el ends here
