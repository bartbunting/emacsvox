;;; emacsvox-aural-preview.el --- Shared aural preview runtime -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Coordinate explicit previews without owning their feature-specific content.
;; Speech previews stop earlier output, queue one concrete plan or caller-built
;; sequence, and dispatch once.  Cue-only previews stop speech but bypass the
;; speech queue, presentation history, and training hooks.

;;; Code:

(require 'emacsvox-aural-transport)

(defvar emacsvox-speak-messages)

(declare-function emacsvox-sounds-play-concrete-cue
                  "emacsvox-sounds"
                  (resource sample-id &optional balance))
(declare-function tts-stop "tts-speak" ())
(declare-function tts--protocol-dispatch "tts-speak" ())

(defun emacsvox-aural-preview-stop ()
  "Stop speech before an explicitly requested preview."
  (when (fboundp 'tts-stop)
    (tts-stop)))

(defun emacsvox-aural-preview-message (format-string &rest arguments)
  "Display a preview status message without sending it to speech.

FORMAT-STRING and ARGUMENTS have the same meaning as for `message'."
  (let ((emacsvox-speak-messages nil))
    (apply #'message format-string arguments)))

(defun emacsvox-aural-preview-begin (&optional speech-required)
  "Stop old output and prepare an explicit preview.

When SPEECH-REQUIRED is non-nil, ensure that the speech server is available
after stopping existing output.  Cue-only previews can leave it nil because
their concrete audio resources do not use the speech queue."
  (emacsvox-aural-preview-stop)
  (when speech-required
    (emacsvox-aural--ensure-speaker)))

(defun emacsvox-aural-preview-dispatch (&optional result)
  "Dispatch queued preview speech and return RESULT."
  (tts--protocol-dispatch)
  result)

(defun emacsvox-aural-preview-play-plan (concrete)
  "Stop old output, play concrete plan CONCRETE, and return it."
  (emacsvox-aural-preview-begin t)
  (emacsvox-aural-queue-concrete-plan concrete)
  (emacsvox-aural-preview-dispatch concrete))

(defun emacsvox-aural-preview-play-runs (runs &optional transaction-id)
  "Stop old output and replay exact concrete RUNS once.

RUNS have the form accepted by `emacsvox-aural-queue-concrete-runs'.
TRANSACTION-ID, when non-nil, retains the replay as one history transaction."
  (emacsvox-aural-preview-begin t)
  (if transaction-id
      (emacsvox-aural-call-with-presentation-transaction
       transaction-id #'emacsvox-aural-queue-concrete-runs runs)
    (emacsvox-aural-queue-concrete-runs runs))
  (emacsvox-aural-preview-dispatch runs))

(defun emacsvox-aural-preview--play-cue (resource sample-id balance)
  "Play concrete cue RESOURCE with SAMPLE-ID and optional BALANCE."
  (if (and (numberp balance) (not (zerop balance)))
      (emacsvox-sounds-play-concrete-cue resource sample-id balance)
    (emacsvox-sounds-play-concrete-cue resource sample-id)))

(defun emacsvox-aural-preview-play-cue
    (resource sample-id &optional balance)
  "Stop speech and play concrete cue RESOURCE using SAMPLE-ID and BALANCE."
  (emacsvox-aural-preview-begin)
  (emacsvox-aural-preview--play-cue resource sample-id balance)
  resource)

(defun emacsvox-aural-preview-play-cues (cues)
  "Stop speech, play concrete cue actions CUES, and return CUES.

The cues are played directly so no content, presentation history, or training
explanation is submitted to the speech transport."
  (emacsvox-aural-preview-begin)
  (dolist (cue cues)
    (emacsvox-aural-preview--play-cue
     (emacsvox-aural-concrete-action-resource cue)
     (emacsvox-aural-concrete-action-sample-id cue)
     (emacsvox-aural-concrete-action-balance cue)))
  cues)

(provide 'emacsvox-aural-preview)
;;; emacsvox-aural-preview.el ends here
