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
        '(emacsvox-aural
          emacsvox-aural-spatial
          emacsvox-aural-rules
          emacsvox-aural-resources
          emacsvox-aural-schemes
          emacsvox-aural-transport
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
        '(emacsvox-aural-voice-lock-enabled-p
          emacsvox-aural-spatial-clamp
          emacsvox-aural--rule-error
          emacsvox-aural--resource-error
          emacsvox-aural--migrate-user-data-v1-to-v2
          emacsvox-aural--transport-error
          emacsvox-aural-tools--interface-buffer-p
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
  (when-let* ((stale (emacsvox-setup--stale-byte-code lisp-directory)))
    (error "Normal aural build left stale byte-code: %S" stale)))

(princ "Normal build-tree aural startup checks passed\n")

;;; verify-build-tree-aural.el ends here
