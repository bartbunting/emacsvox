;;; emacsvox-aural-concrete.el --- Backend-ready aural plans -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Data-only records shared by concrete compilation, queue transport,
;; descriptions, inspection, and history.  This module owns no rule
;; resolution, resource lookup, TTS policy, or backend calls.

;;; Code:

(require 'cl-lib)

(define-error
  'emacsvox-aural-transport-error
  "Cannot compile or queue an Emacsvox aural presentation")

(defconst emacsvox-aural-concrete-plan-property
  'emacsvox-aural-concrete-plan
  "Text property holding a source-resolved concrete plan.")

(cl-defstruct
    (emacsvox-aural-concrete-action
     (:constructor emacsvox-aural--make-concrete-action))
  "One backend-ready ordered action."
  id kind text cue resource sample-id duration voice-command source
  anchor requested-space balance spatial-capability spatial-degradations
  voice-request voice-style voice-provenance voice-capability
  voice-degradations
  requested-volume volume-capability volume-degradation)

(cl-defstruct
    (emacsvox-aural-concrete-content
     (:constructor emacsvox-aural--make-concrete-content))
  "Backend-ready styling and speaking state for object content."
  text speak voice-command provenance requested-space balance
  spatial-capability spatial-degradations
  voice-request voice-style voice-provenance voice-capability
  voice-degradations
  requested-volume volume-capability volume-degradation)

(cl-defstruct
    (emacsvox-aural-compiled-voice
     (:constructor emacsvox-aural--make-compiled-voice))
  "One device-independent voice compiled for the active adapter."
  command request style provenance capability degradations preset)

(cl-defstruct
    (emacsvox-aural-concrete-plan
     (:constructor emacsvox-aural--make-concrete-plan))
  "A backend-ready ordered plan frozen at its source boundary."
  before content after facts context resource-pack voice-palette
  source-plan degradations object-id run-id object-start-p object-end-p
  scheme configuration-generation rule-provenance)

(provide 'emacsvox-aural-concrete)
;;; emacsvox-aural-concrete.el ends here
