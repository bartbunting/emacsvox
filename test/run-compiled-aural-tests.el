;;; run-compiled-aural-tests.el --- Verify compiled aural parity -*- lexical-binding: t; -*-

;;; Commentary:

;; Compile the complete aural subsystem into an isolated directory, then
;; verify it in a clean child Emacs.  No byte-code is written into the source
;; tree.

;;; Code:

(require 'bytecomp)
(require 'subr-x)

(let* ((test-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (root-directory (expand-file-name "../" test-directory))
       (lisp-directory (expand-file-name "lisp/" root-directory))
       (build-root (make-temp-file "emacsvox-compiled-aural-" t))
       (build-directory (expand-file-name "lisp/" build-root))
       (files
        '("core/emacsvox-emoji.el"
          "aural/emacsvox-aural.el"
          "aural/emacsvox-aural-compatibility-voice.el"
          "aural/emacsvox-aural-concrete.el"
          "aural/emacsvox-aural-history.el"
          "aural/emacsvox-aural-spatial.el"
          "aural/emacsvox-aural-rules.el"
          "aural/emacsvox-aural-resources.el"
          "aural/emacsvox-aural-schemes.el"
          "aural/emacsvox-aural-routing-profiles.el"
          "voices/emacsvox-aural-voice-data.el"
          "voices/emacsvox-aural-voice-runtime.el"
          "voices/emacsvox-aural-voice-drafts.el"
          "aural/emacsvox-aural-profile-service.el"
          "aural/emacsvox-aural-providers.el"
          "aural/emacsvox-aural-compiler.el"
          "voices/emacsvox-aural-voice-editing.el"
          "aural/emacsvox-aural-source.el"
          "aural/emacsvox-aural-planner.el"
          "aural/emacsvox-aural-submission.el"
          "speech/tts-queue-state.el"
          "aural/emacsvox-aural-timeline-codec.el"
          "aural/emacsvox-aural-transport.el"
          "speech/omnivox-library-runtime.el"
          "speech/omnivox-remote.el"
          "speech/tts-lifecycle.el"
          "speech/tts-voice-api.el"
          "speech/tts-speak.el"
          "speech/voice-setup.el"
          "voices/voice-defs.el"
          "speech/dectalk-voices.el"
          "speech/plain-voices.el"
          "speech/espeak-voices.el"
          "speech/outloud-voices.el"
          "speech/mac-voices.el"
          "speech/swiftmac-voices.el"
          "speech/omnivox-control-codec.el"
          "speech/omnivox-choice-codec.el"
          "speech/omnivox-preview.el"
          "speech/omnivox-inventory.el"
          "speech/omnivox-discovery.el"
          "speech/omnivox-voices.el"
          "core/emacsvox-pronounce.el"
          "core/emacsvox-tracked-reading.el"
          "core/emacsvox-speak-characters.el"
          "core/emacsvox-speak-presentation.el"
          "core/emacsvox-speak-completion.el"
          "core/emacsvox-speak-messages.el"
          "core/emacsvox-speak-time.el"
          "core/emacsvox-speak-windows.el"
          "core/emacsvox-speak-status.el"
          "core/emacsvox-speak-navigation.el"
          "core/emacsvox-speak-filters.el"
          "core/emacsvox-speak.el"
          "aural/emacsvox-aural-description.el"
          "aural/emacsvox-aural-preview.el"
          "aural/emacsvox-aural-replay.el"
          "aural/emacsvox-aural-validation.el"
          "ui/emacsvox-aural-ui.el"
          "aural/emacsvox-aural-inspection.el"
          "ui/emacsvox-aural-semantics.el"
          "aural/emacsvox-aural-explanation.el"
          "aural/emacsvox-aural-tools.el"
          "ui/emacsvox-aural-recent-feedback.el"
          "ui/emacsvox-aural-feedback-details.el"
          "ui/emacsvox-aural-feature-fragments.el"
          "ui/emacsvox-omnivox-components.el"
          "ui/emacsvox-aural-home.el"
          "ui/emacsvox-aural-editor.el"
          "ui/emacsvox-aural-overrides.el"
          "ui/emacsvox-aural-doctor.el"
          "ui/emacsvox-aural-profiles.el"
          "ui/emacsvox-aural-voice-palettes.el"
          "ui/emacsvox-aural-voice-workbench-views.el"
          "ui/emacsvox-aural-voice-workbench-preview.el"
          "ui/emacsvox-aural-voice-workbench.el"
          "ui/emacsvox-aural-voice-editor.el"
          "ui/emacsvox-aural-voice-bulk.el"
          "ui/omnivox-espeak-variants.el"
          "ui/emacsvox-aural-voice-context.el"
          "ui/emacsvox-aural-change-feedback.el"
          "aural/emacsvox-aural-provider-org.el"
          "aural/emacsvox-aural-provider-org-srs.el"
          "aural/emacsvox-aural-provider-workflows.el"
          "aural/emacsvox-aural-provider-markdown.el"
          "aural/emacsvox-aural-provider-notmuch.el"
          "aural/emacsvox-sounds.el"
          "ui/emacsvox-aural-sound-packs.el"
          "core/emacsvox-keymap.el"))
       (byte-compile-dest-file-function
        (lambda (source)
          (expand-file-name
           (concat (file-relative-name source build-directory) "c")
           build-directory)))
       (child-program
        (expand-file-name invocation-name invocation-directory))
       (verify-file
        (expand-file-name "verify-compiled-aural.el" test-directory)))
  (unwind-protect
      (progn
        ;; Keep sources beside generated files so the real bootstrap can
        ;; register this isolated installation without preferring the checkout.
        (load (expand-file-name "emacsvox-paths.el" lisp-directory) nil t t)
        (make-directory build-directory)
        (dolist (source (emacsvox-paths--files lisp-directory ".el"))
          (let ((target (expand-file-name (file-relative-name source lisp-directory)
                                          build-directory)))
            (make-directory (file-name-directory target) t)
            (copy-file source target)))
        (copy-file (expand-file-name "VERSION" root-directory)
                   (expand-file-name "VERSION" build-root))
        (dolist (name '("etc" "sounds"))
          (copy-directory (expand-file-name name root-directory)
                          (expand-file-name name build-root)))
        (emacsvox-paths--register build-directory)
        (setq load-prefer-newer t)
        (dolist (file files)
          (let ((source (expand-file-name file build-directory)))
            (unless (byte-compile-file source)
              (error "Could not byte-compile %s" source))))
        (let ((process-environment (copy-sequence process-environment))
              (output (get-buffer-create " *compiled-aural-child*")))
          (setenv "EMACSVOX_COMPILED_AURAL_DIR" build-directory)
          (setenv "EMACSVOX_COMPILED_AURAL_ROOT" root-directory)
          (with-current-buffer output (erase-buffer))
          (let ((status
                 (call-process
                  child-program nil (list output t) nil
                  "-Q" "--batch" "-l" verify-file)))
            (unless (zerop status)
              (princ (with-current-buffer output (buffer-string)))
              (error "Compiled aural verification failed")))))
    (delete-directory build-root t)))

(princ "Compiled aural parity checks passed\n")

;;; run-compiled-aural-tests.el ends here
