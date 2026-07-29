;;; verify-compiled-aural.el --- Clean compiled aural checks -*- lexical-binding: t; -*-

;;; Commentary:

;; This file is run only by `run-compiled-aural-tests.el' in a clean child
;; Emacs whose build directory contains freshly compiled aural entry points.

;;; Code:

(require 'cl-lib)
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
  (dolist
      (library
       '("emacsvox-aural"
         "emacsvox-aural-concrete"
         "emacsvox-aural-spatial"
         "emacsvox-aural-rules"
         "emacsvox-aural-description"))
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
   (expand-file-name "emacsvox-aural-history.elc" build-directory)
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
  (load
   (expand-file-name "emacsvox-aural-schemes.elc" build-directory)
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
       '("emacsvox-aural-profile-service"
         "emacsvox-aural-providers"
         "emacsvox-aural-compiler"
         "emacsvox-aural-source"
         "emacsvox-aural-planner"
         "emacsvox-aural-submission"
         "emacsvox-aural-ui"
         "emacsvox-aural-inspection"))
    (load
     (expand-file-name (concat library ".elc") build-directory)
     nil nil))
  (load
   (expand-file-name
    "emacsvox-aural-compatibility-voice.elc"
    build-directory)
   nil nil)
  (dolist (feature '(tts-speak voice-setup))
    (when (featurep feature)
      (error
       "Compatibility voice policy loaded low-level provider %S"
       feature)))
  (unless
      (string-match-p
       "emacsvox-aural-compatibility-voice"
       (or (symbol-file 'voice-lock-mode 'defun) ""))
    (error "Aural compatibility policy does not own voice-lock-mode"))
  (when (featurep 'emacsvox-aural-transport)
    (error
     "Aural compiler, planner, source, and inspection loaded queue transport"))
  (dolist
      (library
       '("tts-speak"
         "voice-setup"
         "voice-defs"
         "dectalk-voices"
         "plain-voices"
         "espeak-voices"
         "outloud-voices"
         "mac-voices"
         "swiftmac-voices"
         "emacsvox-pronounce"
         "emacsvox-speak"
         "emacsvox-aural-transport"
         "emacsvox-aural-preview"
         "emacsvox-aural-validation"
         "emacsvox-aural-scheme-manager"
         "emacsvox-aural-semantics"
         "emacsvox-aural-explanation"
         "emacsvox-aural-tools"
         "emacsvox-aural-recent-feedback"
         "emacsvox-aural-feature-fragments"
         "emacsvox-aural-home"
         "emacsvox-aural-editor"
         "emacsvox-aural-overrides"
         "emacsvox-aural-simple-editor"
         "emacsvox-aural-doctor"
         "emacsvox-aural-profiles"
         "emacsvox-aural-voice-palettes"
         "emacsvox-aural-provider-org"
         "emacsvox-aural-provider-workflows"
         "emacsvox-aural-provider-markdown"
         "emacsvox-aural-provider-notmuch"
         "emacsvox-sounds"
         "emacsvox-aural-sound-packs"
         "emacsvox-keymap"))
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
         emacsvox-aural-describe-selector
         emacsvox-aural-preview-play-plan
         emacsvox-aural-preview-play-runs
         emacsvox-aural-validation--report
         emacsvox-aural-inspection-source-buffer
         emacsvox-aural-scheme-manager--scheme-row
         emacsvox-aural-semantics--set-entries
         emacsvox-aural-explanation--training-presented
         emacsvox-aural-recent-feedback--entries
         emacsvox-aural-ui-announce-boundary
         emacsvox-aural-feature-fragments-install-state
         emacsvox-aural-feature-fragments-refresh-if-live
         emacsvox-aural-feature-fragments--set-entries
         emacsvox-aural-home--entries
         emacsvox-aural-editor--scope-label
         emacsvox-aural-editor-open-prefilled-rule
         emacsvox-aural-editor-normalized-rules
         emacsvox-aural-overrides--collect
         emacsvox-aural-simple-editor--humanize
         emacsvox-aural-doctor--finding
         emacsvox-aural-profiles--ids
         emacsvox-aural-voice-palettes--active-id
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
  (unless
      (string-suffix-p
       ".elc" (or (symbol-file 'voice-animate 'defvar) ""))
    (error "voice-animate was not loaded from byte-code: %S"
           (symbol-file 'voice-animate 'defvar)))
  (unless (eq (lookup-key emacsvox-keymap (kbd "H")) 'emacsvox-aural)
    (error "Compiled keymap does not bind C-e H to the aural home"))
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
      (advice-remove 'tts--protocol-stop advice))))

;;; verify-compiled-aural.el ends here
