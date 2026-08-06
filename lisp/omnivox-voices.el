;;; omnivox-voices.el --- Omnivox voice adapter  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Voice and rate support for the Omnivox speech server.  Omnivox accepts
;; generic Emacsvox protocol commands and uses [[pitch FLOAT]] inline codes.

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'subr-x)

(defvar emacsvox-servers-directory)
(defvar emacsvox-play-program)
(defvar tts-default-speech-rate)
(defvar tts-default-voice)
(defvar tts-notify-process)
(defvar tts-speaker-process)
(defvar tts-speech-rate)
(defvar tts-speech-rate-base)
(defvar tts-speech-rate-step)
(defvar tts-voice-capabilities-function)

(defgroup omnivox nil
  "Omnivox speech server."
  :group 'tts
  :prefix "omnivox-")

(defcustom omnivox-default-speech-rate 60
  "Default Omnivox speech rate on its zero-to-100 scale."
  :group 'omnivox
  :type 'integer)

(defcustom omnivox-default-voice-id ""
  "Default physical voice identifier for the current Omnivox engine.
An empty string leaves voice selection to the engine.  Use
`omnivox-select-voice' to choose from the voices reported by the server."
  :group 'omnivox
  :type 'string)

(defvar omnivox-available-voices nil
  "Physical voices most recently discovered from Omnivox.
Each entry has the form (ID NAME LANGUAGE QUALITY).")

(defun omnivox--server-program ()
  "Return the Omnivox server program used for discovery, or nil."
  (let ((server (expand-file-name "omnivox" emacsvox-servers-directory)))
    (cond
     ((file-executable-p server) server)
     ((executable-find "omnivox")))))

(defun omnivox--voice-entry-p (entry)
  "Return non-nil when ENTRY is a valid discovered voice record."
  (and (listp entry)
       (= (length entry) 4)
       (cl-every #'stringp entry)))

(defun omnivox--parse-voices (output)
  "Parse and validate Omnivox voice discovery OUTPUT."
  (condition-case error-data
      (let* ((parsed (read-from-string output))
             (voices (car parsed))
             (remainder (substring output (cdr parsed))))
        (unless (string-empty-p (string-trim remainder))
          (error "Unexpected data after voice list"))
        (unless (and (listp voices)
                     (cl-every #'omnivox--voice-entry-p voices))
          (error "Invalid Omnivox voice list"))
        voices)
    (error
     (error "Could not parse Omnivox voices: %s"
            (error-message-string error-data)))))

(defun omnivox-query-voices ()
  "Return physical voices reported by the Omnivox executable.
Signal an error if discovery cannot run or returns malformed data."
  (let ((program (omnivox--server-program)))
    (unless program
      (error "Could not find the Omnivox server executable"))
    (with-temp-buffer
      (let ((status
             (process-file program nil t nil "--list-voices-alist")))
        (unless (and (integerp status) (zerop status))
          (error "Omnivox voice discovery failed%s"
                 (if (string-empty-p (string-trim (buffer-string)))
                     ""
                   (format ": %s" (string-trim (buffer-string))))))
        (omnivox--parse-voices (buffer-string))))))

(defun omnivox-refresh-voices ()
  "Refresh and return the physical voices available from Omnivox."
  (interactive)
  (setq omnivox-available-voices (omnivox-query-voices))
  (when (called-interactively-p 'interactive)
    (message "Found %d Omnivox voices" (length omnivox-available-voices)))
  omnivox-available-voices)

(defun omnivox--send-state-command (command)
  "Send Omnivox state COMMAND to the live speaker processes.
Return the number of distinct processes that received the command."
  (let (sent)
    (dolist (process (list tts-speaker-process tts-notify-process))
      (when (and (process-live-p process) (not (memq process sent)))
        (process-send-string process (concat command "\n"))
        (push process sent)))
    (length sent)))

(defun omnivox-set-voice (voice-id)
  "Select physical Omnivox VOICE-ID for speaker and notification speech."
  (when (or (string-empty-p voice-id)
            (string-match-p "[\0\r\n]" voice-id))
    (user-error "Invalid Omnivox voice identifier"))
  (setq omnivox-default-voice-id voice-id)
  (unless (> (omnivox--send-state-command
              (format "tts_set_voice %s" voice-id))
             0)
    (user-error "No live Omnivox speech process"))
  voice-id)

(defun omnivox-select-voice ()
  "Select a discovered physical voice for the current Omnivox engine."
  (interactive)
  (unless omnivox-available-voices
    (omnivox-refresh-voices))
  (unless omnivox-available-voices
    (user-error "Omnivox reported no available voices"))
  (let* ((candidates
          (mapcar
           (lambda (voice)
             (pcase-let ((`(,id ,name ,language ,quality) voice))
               (cons
                (format "%s [%s, %s] — %s"
                        name language quality id)
                id)))
           omnivox-available-voices))
         (choice (completing-read "Omnivox voice: " candidates nil t))
         (voice-id (cdr (assoc-string choice candidates))))
    (omnivox-set-voice voice-id)
    (message "Omnivox voice set to %s" voice-id)))

(defun omnivox-list-voices ()
  "Display physical voices available from the current Omnivox engine."
  (interactive)
  (unless omnivox-available-voices
    (omnivox-refresh-voices))
  (with-help-window "*Omnivox Voices*"
    (princ (format "Omnivox reported %d voices.\n\n"
                   (length omnivox-available-voices)))
    (dolist (voice omnivox-available-voices)
      (pcase-let ((`(,id ,name ,language ,quality) voice))
        (princ (format "%s\n  ID: %s\n  Language: %s\n  Quality: %s\n\n"
                       name id language quality))))))

(defun omnivox-voice-capabilities ()
  "Return normalized ACSS capabilities for Omnivox."
  '(:adapter omnivox
    :source static
    :family-selection unsupported
    :families nil
    :generic-families nil
    :dimensions (average-pitch)
    :parameters
    ((average-pitch :type integer :minimum 0 :maximum 9 :default 5))))

;;;###autoload
(defun omnivox ()
  "Select the Omnivox speech server."
  (interactive)
  (tts-select-server "omnivox"))

(defvar omnivox-default-voice-string "[[pitch 1.0]]"
  "Omnivox inline code for the default voice.")

(defvar omnivox-voice-table (make-hash-table)
  "Map Emacsvox voice symbols to Omnivox inline codes.")

(defconst omnivox-average-pitch-table
  ["[[pitch 0.5]]"
   "[[pitch 0.6]]"
   "[[pitch 0.7]]"
   "[[pitch 0.8]]"
   "[[pitch 0.9]]"
   "[[pitch 1.0]]"
   "[[pitch 1.2]]"
   "[[pitch 1.4]]"
   "[[pitch 1.7]]"
   "[[pitch 2.0]]"]
  "Map normalized ACSS average pitch to Omnivox pitch multipliers.")

(defun omnivox-define-voice (name command)
  "Define Omnivox voice NAME using inline COMMAND."
  (puthash name command omnivox-voice-table))

(defun omnivox-get-voice-command (name)
  "Return the Omnivox inline command for voice NAME."
  (cond
   ((listp name)
    (mapconcat #'omnivox-get-voice-command name " "))
   (t
    (or (gethash name omnivox-voice-table)
        omnivox-default-voice-string))))

(defun omnivox-voice-defined-p (name)
  "Return non-nil when Omnivox voice NAME is defined."
  (gethash name omnivox-voice-table))

(omnivox-define-voice 'paul omnivox-default-voice-string)

(defun omnivox-define-voice-from-acss (name style)
  "Define Omnivox voice NAME from ACSS STYLE."
  (let ((pitch (acss-average-pitch style)))
    (omnivox-define-voice
     name
     (if pitch
         (aref omnivox-average-pitch-table pitch)
       omnivox-default-voice-string))))

;;;###autoload
(defun omnivox-configure-tts ()
  "Configure Emacsvox to use Omnivox."
  (setq tts-default-voice 'paul)
  (fset 'tts-voice-defined-p #'omnivox-voice-defined-p)
  (fset 'tts-get-voice-command #'omnivox-get-voice-command)
  (fset 'tts-define-voice-from-acss #'omnivox-define-voice-from-acss)
  (setq tts-voice-capabilities-function #'omnivox-voice-capabilities)
  (setq tts-default-speech-rate omnivox-default-speech-rate)
  (set-default 'tts-default-speech-rate omnivox-default-speech-rate)
  (setq tts-speech-rate omnivox-default-speech-rate)
  (setq-default tts-speech-rate omnivox-default-speech-rate)
  (setq tts-speech-rate-base 20
        tts-speech-rate-step 5
        emacsvox-play-program nil)
  (tts-unicode-update-untouched-charsets
   '(ascii latin-iso8859-1 latin-iso8859-15 latin-iso8859-9
           eight-bit-graphic))
  (unless (string-empty-p omnivox-default-voice-id)
    (omnivox--send-state-command
     (format "tts_set_voice %s" omnivox-default-voice-id))))

(provide 'omnivox-voices)
;;; omnivox-voices.el ends here
