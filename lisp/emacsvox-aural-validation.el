;;; emacsvox-aural-validation.el --- Aural configuration diagnostics -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Shared validation for complete aural schemes and presentation-option
;; fragments.  This module keeps diagnostic model logic independent of the
;; interactive managers that display its reports.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'subr-x)
(require 'emacsvox-aural-transport)

(cl-defstruct
    (emacsvox-aural-validation-report
     (:constructor emacsvox-aural--make-validation-report))
  "Validation result for an aural scheme or presentation option."
  scheme valid errors warnings missing-assets unavailable-voices
  unreachable-rules ambiguous-ties disabled-rules semantic-diagnostics)

(defun emacsvox-aural-validation--content-patch-empty-p (patch)
  "Return non-nil when content PATCH cannot change presentation."
  (not
   (or
    (emacsvox-aural-content-patch-suppress patch)
    (emacsvox-aural-content-patch-speak-set-p patch)
    (emacsvox-aural-content-patch-voice-set-p patch)
    (emacsvox-aural-content-patch-volume-set-p patch)
    (emacsvox-aural-content-patch-space-set-p patch))))

(defun emacsvox-aural-validation--phase-empty-p (operations)
  "Return non-nil when phase OPERATIONS cannot change presentation."
  (not
   (or
    (emacsvox-aural-phase-operations-suppress operations)
    (emacsvox-aural-phase-operations-replace-set-p operations)
    (emacsvox-aural-phase-operations-remove operations)
    (emacsvox-aural-phase-operations-prepend operations)
    (emacsvox-aural-phase-operations-append operations))))

(defun emacsvox-aural-validation--rule-ineffective-p (rule)
  "Return non-nil when RULE has no presentation operation."
  (let ((contribution (emacsvox-aural-rule-contribution rule)))
    (and
     (emacsvox-aural-validation--phase-empty-p
      (emacsvox-aural-contribution-before contribution))
     (emacsvox-aural-validation--content-patch-empty-p
      (emacsvox-aural-contribution-content contribution))
     (emacsvox-aural-validation--phase-empty-p
      (emacsvox-aural-contribution-after contribution)))))

(defun emacsvox-aural-validation--ambiguous-ties (rules)
  "Return pairs in RULES requiring stable identifier tie-breaking."
  (let (ties)
    (while rules
      (let ((left (pop rules)))
        (dolist (right rules)
          (when
              (and
               (eq
                (emacsvox-aural-rule-origin left)
                (emacsvox-aural-rule-origin right))
               (= (emacsvox-aural-rule-layer-order left)
                  (emacsvox-aural-rule-layer-order right))
               (= (emacsvox-aural-rule-order left)
                  (emacsvox-aural-rule-order right))
               (equal
                (emacsvox-aural-rule-selector left)
                (emacsvox-aural-rule-selector right)))
            (push
             (cons
              (emacsvox-aural-rule-id left)
              (emacsvox-aural-rule-id right))
             ties)))))
    (nreverse ties)))

(defun emacsvox-aural-validation--semantic-diagnostics (rules)
  "Return alias and fallback-shadow diagnostics for compiled RULES."
  (let (diagnostics seen-aliases)
    (dolist (rule rules)
      (dolist
          (alias
           (emacsvox-aural-selector-semantic-aliases
            (emacsvox-aural-rule-selector rule)))
        (let ((id (emacsvox-aural-semantic-alias-id alias)))
          (unless (memq id seen-aliases)
            (push id seen-aliases)
            (push
             (list
              :kind 'deprecated-alias
              :rule (emacsvox-aural-rule-id rule)
              :alias id
              :canonical
              (emacsvox-aural-canonical-semantic-id id)
              :message
              (emacsvox-aural-semantic-alias-diagnostic id))
             diagnostics)))))
    (dolist (shadow (emacsvox-aural-fallback-shadow-diagnostics rules))
      (push
       (append
        (list
         :kind 'fallback-shadow
         :message
         (format
          "Rule %s selects a fallback of %s; both contribute, with %s stronger"
          (plist-get shadow :general)
          (plist-get shadow :specific)
          (plist-get shadow :specific)))
        shadow)
       diagnostics))
    (nreverse diagnostics)))

(defun emacsvox-aural-validation--rule-voices (rule)
  "Return voice values referenced by RULE."
  (let* ((contribution (emacsvox-aural-rule-contribution rule))
         (content (emacsvox-aural-contribution-content contribution))
         voices)
    (when (emacsvox-aural-content-patch-voice-set-p content)
      (push (emacsvox-aural-content-patch-voice content) voices))
    (dolist (action (emacsvox-aural-rule-actions rule))
      (when (emacsvox-aural-action-voice action)
        (push (emacsvox-aural-action-voice action) voices)))
    voices))

(defun emacsvox-aural-validation--voice-available-p (voice palette)
  "Return non-nil when VOICE can be supplied by PALETTE or existing ACSS."
  (cond
   ((or (null voice) (eq voice 'inaudible)) t)
   ((eq (type-of voice) 'acss) t)
   ((and (listp voice) (proper-list-p voice))
    (cl-every
     (lambda (entry)
       (emacsvox-aural-validation--voice-available-p entry palette))
     voice))
   ((symbolp voice)
    (or
     (emacsvox-aural-voice voice palette)
     (boundp voice)))
   (t nil)))

(defun emacsvox-aural-validation--scheme-cues (rules)
  "Return unique cue names referenced by RULES."
  (let (cues)
    (dolist (rule rules)
      (dolist (action (emacsvox-aural-rule-actions rule))
        (when (eq (emacsvox-aural-action-kind action) 'cue)
          (push (emacsvox-aural-action-cue action) cues))))
    (delete-dups cues)))

(defun emacsvox-aural-validation--prepare-scheme (scheme)
  "Return validation inputs for registered SCHEME."
  (let ((chain (emacsvox-aural--scheme-chain scheme)))
    (emacsvox-aural--validate-scheme-providers scheme)
    (list
     :rules (emacsvox-aural-effective-scheme-rules scheme)
     :all-rules
     (cl-mapcan
      (lambda (entry)
        (copy-sequence
         (emacsvox-aural-scheme-rules
          (emacsvox-aural-scheme-entry-compiled entry))))
      chain)
     :pack
     (emacsvox-aural-effective-scheme-provider 'resource-pack scheme)
     :palette
     (or
      (emacsvox-aural-effective-scheme-provider 'voice-palette scheme)
      'acss-default)
     :report-unknown-assets t)))

(defun emacsvox-aural-validation--prepare-fragment (fragment)
  "Return validation inputs for registered presentation option FRAGMENT."
  (let* ((entry
          (or
           (emacsvox-aural-feature-fragment-entry fragment)
           (emacsvox-aural--scheme-error
            "Unknown feature fragment: %S" fragment)))
         (all-rules
          (copy-sequence
           (emacsvox-aural-scheme-rules
            (emacsvox-aural-feature-fragment-entry-compiled entry)))))
    (list
     :rules (cl-remove-if-not #'emacsvox-aural-rule-enabled all-rules)
     :all-rules all-rules
     :pack (emacsvox-aural-effective-scheme-provider 'resource-pack)
     :palette
     (or
      (emacsvox-aural-effective-scheme-provider 'voice-palette)
      'acss-default))))

(defun emacsvox-aural-validation--report (object prepare)
  "Validate OBJECT using the input-producing function PREPARE."
  (let
      (errors warnings rules all-rules missing-assets unavailable
              unreachable ties disabled semantic-diagnostics)
    (condition-case error
        (let* ((input (funcall prepare object))
               (pack (plist-get input :pack))
               (palette (plist-get input :palette)))
          (setq
           rules (plist-get input :rules)
           all-rules (plist-get input :all-rules)
           disabled
           (mapcar
            #'emacsvox-aural-rule-id
            (cl-remove-if #'emacsvox-aural-rule-enabled all-rules)))
          (when pack
            (let ((resource-report
                   (emacsvox-aural-validate-resource-pack
                    pack
                    (emacsvox-aural-validation--scheme-cues rules))))
              (setq
               missing-assets
               (emacsvox-aural-resource-report-missing-required
                resource-report))
              (when
                  (emacsvox-aural-resource-report-missing-directory
                   resource-report)
                (push
                 (format "Resource directory for %s is missing" pack)
                 errors))
              (when
                  (plist-get input :report-unknown-assets)
                (when-let* ((unknown
                             (emacsvox-aural-resource-report-unknown-assets
                              resource-report)))
                  (push
                   (format "Unknown assets in %s: %S" pack unknown)
                   errors)))))
          (when (featurep 'voice-defs)
            (setq
             unavailable
             (emacsvox-aural-validate-voice-palette palette)))
          (dolist (rule rules)
            (when (emacsvox-aural-validation--rule-ineffective-p rule)
              (push (emacsvox-aural-rule-id rule) unreachable))
            (dolist (voice (emacsvox-aural-validation--rule-voices rule))
              (unless
                  (emacsvox-aural-validation--voice-available-p
                   voice palette)
                (push voice unavailable))))
          (setq
           ties (emacsvox-aural-validation--ambiguous-ties rules)
           semantic-diagnostics
           (emacsvox-aural-validation--semantic-diagnostics rules)))
      (error (push (error-message-string error) errors)))
    (when missing-assets
      (push
       (format "Missing required cues: %S" missing-assets)
       errors))
    (when unavailable
      (push
       (format "Unavailable voices: %S" (delete-dups unavailable))
       errors))
    (when unreachable
      (push
       "Rules listed as unreachable contain no presentation operation"
       warnings))
    (when ties
      (push
       "Ambiguous ties are resolved only by stable rule identifier"
       warnings))
    (dolist (diagnostic semantic-diagnostics)
      (push (plist-get diagnostic :message) warnings))
    (emacsvox-aural--make-validation-report
     :scheme object
     :valid (null errors)
     :errors (nreverse errors)
     :warnings (nreverse warnings)
     :missing-assets (copy-sequence missing-assets)
     :unavailable-voices (delete-dups (nreverse unavailable))
     :unreachable-rules (nreverse unreachable)
     :ambiguous-ties ties
     :disabled-rules disabled
     :semantic-diagnostics semantic-diagnostics)))

(defun emacsvox-aural-validate-scheme (scheme)
  "Return a complete validation report for registered SCHEME."
  (emacsvox-aural-validation--report
   scheme #'emacsvox-aural-validation--prepare-scheme))

(defun emacsvox-aural-validate-feature-fragment (fragment)
  "Return a validation report for registered presentation option FRAGMENT."
  (emacsvox-aural-validation--report
   fragment #'emacsvox-aural-validation--prepare-fragment))

(defun emacsvox-aural-display-validation (report &optional kind)
  "Display validation REPORT for object KIND in a help buffer."
  (with-help-window (help-buffer)
    (princ
     (format
      "Aural %s %s: %s\n\n"
      (or kind "scheme")
      (emacsvox-aural-validation-report-scheme report)
      (if (emacsvox-aural-validation-report-valid report)
          "valid"
        "invalid")))
    (dolist (error (emacsvox-aural-validation-report-errors report))
      (princ (format "Error: %s\n" error)))
    (dolist (warning (emacsvox-aural-validation-report-warnings report))
      (princ (format "Warning: %s\n" warning)))
    (when-let* ((rules
                 (emacsvox-aural-validation-report-unreachable-rules
                  report)))
      (princ (format "Unreachable rules: %S\n" rules)))
    (when-let* ((ties
                 (emacsvox-aural-validation-report-ambiguous-ties
                  report)))
      (princ (format "Ambiguous ties: %S\n" ties)))
    (when-let* ((disabled
                 (emacsvox-aural-validation-report-disabled-rules
                  report)))
      (princ (format "Disabled rules: %S\n" disabled)))
    (when-let* ((assets
                 (emacsvox-aural-validation-report-missing-assets
                  report)))
      (princ (format "Missing assets: %S\n" assets)))
    (when-let* ((voices
                 (emacsvox-aural-validation-report-unavailable-voices
                  report)))
      (princ (format "Unavailable voices: %S\n" voices)))))

(provide 'emacsvox-aural-validation)

;;; emacsvox-aural-validation.el ends here
