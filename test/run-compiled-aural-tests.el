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
        '("emacsvox-emoji.el"
          "emacsvox-aural.el"
          "emacsvox-aural-compatibility-voice.el"
          "emacsvox-aural-concrete.el"
          "emacsvox-aural-history.el"
          "emacsvox-aural-spatial.el"
          "emacsvox-aural-rules.el"
          "emacsvox-aural-resources.el"
          "emacsvox-aural-schemes.el"
          "emacsvox-aural-routing-profiles.el"
          "emacsvox-aural-voice-data.el"
          "emacsvox-aural-voice-runtime.el"
          "emacsvox-aural-voice-drafts.el"
          "emacsvox-aural-profile-service.el"
          "emacsvox-aural-providers.el"
          "emacsvox-aural-compiler.el"
          "emacsvox-aural-voice-editing.el"
          "emacsvox-aural-source.el"
          "emacsvox-aural-planner.el"
          "emacsvox-aural-submission.el"
          "tts-queue-state.el"
          "emacsvox-aural-transport.el"
          "omnivox-remote.el"
          "tts-speak.el"
          "voice-setup.el"
          "voice-defs.el"
          "dectalk-voices.el"
          "plain-voices.el"
          "espeak-voices.el"
          "outloud-voices.el"
          "mac-voices.el"
          "swiftmac-voices.el"
          "omnivox-choice-codec.el"
          "omnivox-preview.el"
          "omnivox-voices.el"
          "emacsvox-pronounce.el"
          "emacsvox-speak.el"
          "emacsvox-aural-description.el"
          "emacsvox-aural-preview.el"
          "emacsvox-aural-replay.el"
          "emacsvox-aural-validation.el"
          "ui/emacsvox-aural-ui.el"
          "emacsvox-aural-inspection.el"
          "ui/emacsvox-aural-semantics.el"
          "emacsvox-aural-explanation.el"
          "emacsvox-aural-tools.el"
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
          "ui/emacsvox-aural-voice-workbench.el"
          "ui/emacsvox-aural-voice-editor.el"
          "ui/emacsvox-aural-voice-bulk.el"
          "ui/omnivox-espeak-variants.el"
          "ui/emacsvox-aural-voice-context.el"
          "ui/emacsvox-aural-change-feedback.el"
          "emacsvox-aural-provider-org.el"
          "emacsvox-aural-provider-org-srs.el"
          "emacsvox-aural-provider-workflows.el"
          "emacsvox-aural-provider-markdown.el"
          "emacsvox-aural-provider-notmuch.el"
          "emacsvox-sounds.el"
          "ui/emacsvox-aural-sound-packs.el"
          "emacsvox-keymap.el"))
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
