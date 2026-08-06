;;; omnivox-voices.el --- Omnivox voice adapter  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Voice and rate support for the Omnivox speech server.  Omnivox accepts
;; generic Emacsvox protocol commands and uses [[pitch FLOAT]] inline codes.

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'json)
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

(defconst omnivox-control-protocol-version 1
  "Control protocol version supported by this adapter.")

(defconst omnivox-control-event-prefix "__OMNIVOX_CONTROL__ "
  "Prefix of Base64-JSON control events emitted by Omnivox.")

(defconst omnivox-control-max-payload-bytes (* 256 1024)
  "Maximum decoded Omnivox control payload accepted by Emacsvox.")

(defconst omnivox-control-max-encoded-bytes 349532
  "Maximum encoded Omnivox control payload accepted by Emacsvox.")

(defconst omnivox--control-filter-installed-property
  'omnivox--control-filter-installed
  "Process property recording installation of the control filter.")

(defconst omnivox--control-original-filter-property
  'omnivox--control-original-filter
  "Process property retaining the filter wrapped by Omnivox.")

(defconst omnivox--control-fragment-property 'omnivox--control-fragment
  "Process property retaining an incomplete Omnivox output line.")

(defconst omnivox--control-pending-property 'omnivox--control-pending
  "Process property holding callbacks for outstanding control requests.")

(defconst omnivox--control-capabilities-property
  'omnivox--control-capabilities
  "Process property holding negotiated Omnivox capabilities.")

(defconst omnivox--control-inventory-property 'omnivox--control-inventory
  "Process property holding the latest Omnivox engine inventory.")

(defconst omnivox--control-negotiated-property 'omnivox--control-negotiated
  "Process property preventing duplicate capability negotiation.")

(defvar omnivox--control-request-sequence 0
  "Sequence used to identify Omnivox control requests.")

(defvar omnivox-control-capabilities nil
  "Capabilities most recently reported by the main Omnivox process.")

(defvar omnivox-engine-inventory nil
  "Engine inventory most recently reported by the main Omnivox process.")

(defvar omnivox-control-last-error nil
  "Most recent Omnivox control error or malformed event.")

(defun omnivox--encode-control-request (request)
  "Encode control REQUEST as bounded, unwrapped Base64 JSON."
  (let* ((json (json-serialize request))
         (payload (encode-coding-string json 'utf-8 t)))
    (when (> (string-bytes payload) omnivox-control-max-payload-bytes)
      (error "Omnivox control request exceeds %d bytes"
             omnivox-control-max-payload-bytes))
    (base64-encode-string payload t)))

(defun omnivox--decode-control-response (payload)
  "Decode and validate one Base64-JSON control response PAYLOAD."
  (when (> (string-bytes payload) omnivox-control-max-encoded-bytes)
    (error "Encoded Omnivox control response exceeds its size limit"))
  (let ((decoded (base64-decode-string payload)))
    (when (> (string-bytes decoded) omnivox-control-max-payload-bytes)
      (error "Decoded Omnivox control response exceeds its size limit"))
    (json-parse-string
     (decode-coding-string decoded 'utf-8 t)
     :object-type 'plist :array-type 'list
     :null-object nil :false-object nil)))

(defun omnivox--pending-requests (process)
  "Return the pending control request table for PROCESS."
  (or (process-get process omnivox--control-pending-property)
      (let ((pending (make-hash-table :test #'eql)))
        (process-put process omnivox--control-pending-property pending)
        pending)))

(defun omnivox--send-control-request (process request callback)
  "Send REQUEST to Omnivox PROCESS and register CALLBACK.
CALLBACK receives PROCESS and the decoded response plist."
  (unless (process-live-p process)
    (error "Omnivox speech process is not live"))
  (let* ((identifier (cl-incf omnivox--control-request-sequence))
         (envelope
          (append
           (list :protocol_version omnivox-control-protocol-version
                 :request_id identifier)
           request))
         (pending (omnivox--pending-requests process)))
    (puthash identifier callback pending)
    (condition-case error-data
        (process-send-string
         process
         (format "omnivox_control {%s}\n"
                 (omnivox--encode-control-request envelope)))
      (error
       (remhash identifier pending)
       (signal (car error-data) (cdr error-data))))
    identifier))

(defun omnivox--record-control-error (process response)
  "Record control error RESPONSE from PROCESS without speaking it."
  (setq omnivox-control-last-error
        (list :process process :response response :time (current-time)))
  (message "Omnivox control error: %s"
           (or (plist-get response :message) "malformed response")))

(defun omnivox--dispatch-control-response (process response)
  "Match decoded control RESPONSE to its request on PROCESS."
  (unless (= (or (plist-get response :protocol_version) -1)
             omnivox-control-protocol-version)
    (error "Unsupported Omnivox control response version"))
  (let* ((identifier (plist-get response :request_id))
         (pending (omnivox--pending-requests process))
         (callback (and (integerp identifier) (gethash identifier pending))))
    (when (integerp identifier)
      (remhash identifier pending))
    (cond
     (callback (funcall callback process response))
     ((equal (plist-get response :type) "error")
      (omnivox--record-control-error process response)))))

(defun omnivox--handle-control-line (process line)
  "Handle an Omnivox control event LINE from PROCESS.
Return non-nil when LINE is a control event, including a malformed one."
  (when (string-prefix-p omnivox-control-event-prefix line)
    (condition-case error-data
        (omnivox--dispatch-control-response
         process
         (omnivox--decode-control-response
          (substring line (length omnivox-control-event-prefix))))
      (error
       (setq omnivox-control-last-error
             (list :process process :error error-data :time (current-time)))
       (message "Invalid Omnivox control event: %s"
                (error-message-string error-data))))
    t))

(defun omnivox--forward-process-output (process output)
  "Forward ordinary PROCESS OUTPUT to the filter wrapped by Omnivox."
  (when-let* ((filter
               (process-get
                process omnivox--control-original-filter-property)))
    (unless (eq filter #'omnivox--control-process-filter)
      (funcall filter process output))))

(defun omnivox--control-process-filter (process output)
  "Extract Omnivox control events from PROCESS OUTPUT."
  (let ((pending
         (concat
          (or (process-get process omnivox--control-fragment-property) "")
          output))
        line-end)
    (while (setq line-end (string-search "\n" pending))
      (let ((line (string-trim-right (substring pending 0 line-end) "\r")))
        (unless (omnivox--handle-control-line process line)
          (omnivox--forward-process-output process (concat line "\n"))))
      (setq pending (substring pending (1+ line-end))))
    (process-put process omnivox--control-fragment-property pending)))

(defun omnivox--install-control-filter (process)
  "Install bounded control-event filtering on Omnivox PROCESS once."
  (unless (process-get process omnivox--control-filter-installed-property)
    (process-put process omnivox--control-filter-installed-property t)
    (process-put
     process omnivox--control-original-filter-property (process-filter process))
    (process-put process omnivox--control-fragment-property "")
    (set-process-filter process #'omnivox--control-process-filter)))

(defun omnivox--handle-inventory-response (process response)
  "Store an inventory RESPONSE received from PROCESS."
  (if (equal (plist-get response :type) "inventory")
      (progn
        (process-put process omnivox--control-inventory-property response)
        (when (eq process tts-speaker-process)
          (setq omnivox-engine-inventory response)))
    (omnivox--record-control-error process response)))

(defun omnivox--handle-capabilities-response (process response)
  "Store capability RESPONSE from PROCESS and request its inventory."
  (if (not (equal (plist-get response :type) "capabilities"))
      (omnivox--record-control-error process response)
    (process-put process omnivox--control-capabilities-property response)
    (when (eq process tts-speaker-process)
      (setq omnivox-control-capabilities response))
    (when (member "engine_inventory" (plist-get response :features))
      (omnivox--send-control-request
       process '(:type "inventory") #'omnivox--handle-inventory-response))))

(defun omnivox--negotiate-process (process)
  "Start capability negotiation for one live Omnivox PROCESS."
  (when (and (process-live-p process)
             (not (process-get process omnivox--control-negotiated-property)))
    (process-put process omnivox--control-negotiated-property t)
    (omnivox--install-control-filter process)
    (condition-case error-data
        (omnivox--send-control-request
         process '(:type "capabilities")
         #'omnivox--handle-capabilities-response)
      (error
       (setq omnivox-control-last-error
             (list :process process :error error-data :time (current-time)))
       (message "Could not negotiate Omnivox control protocol: %s"
                (error-message-string error-data))))))

(defun omnivox--negotiate-processes ()
  "Negotiate capabilities on all distinct live Omnivox processes."
  (dolist (process (delete-dups (list tts-speaker-process tts-notify-process)))
    (when (process-live-p process)
      (omnivox--negotiate-process process))))

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
  (omnivox--negotiate-processes)
  (unless (string-empty-p omnivox-default-voice-id)
    (omnivox--send-state-command
     (format "tts_set_voice %s" omnivox-default-voice-id))))

(provide 'omnivox-voices)
;;; omnivox-voices.el ends here
