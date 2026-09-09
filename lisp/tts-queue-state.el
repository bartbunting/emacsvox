;;; tts-queue-state.el --- Bounded speech input observation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Private stream knowledge for complete captured queue promotion.  This does
;; not own a queue or replay output.  Unknown input preserves legacy delivery.
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'nadvice)

(defconst tts-queue--limit (* 16 1024 1024))
(defconst tts-queue--line-limit (* 512 1024))
(defconst tts-queue--observer-depth 100)
(defconst tts-queue--metadata-bytes 128)
(defvar tts-queue--birth nil "Shared one-cell taint flag during owned creation.")
(defvar tts-queue--token nil "Exact, single-use output token.")

(cl-defstruct (tts-queue--state (:constructor tts-queue--make-state))
	      generation remote (queue 2) (framing 1) unusable (serial 0) flight overlap
	      birth auth)
(cl-defstruct (tts-queue--description (:constructor tts-queue--make-description))
	      table hash)
(cl-defstruct (tts-queue--write (:constructor tts-queue--make-write))
	      process string description auth guard own-stop used receipt)
(cl-defstruct (tts-queue--guard (:constructor tts-queue--make-guard))
	      process state serial generation registry-property registry stop-used)
(define-error 'tts-queue--proof-lost "Speech input changed during preparation")

;; State indices are queue * 2 + framing.  Queue: empty=0, pending=1,
;; unknown=2; framing: boundary=0, unproven=1.  Bit 3 records disturbance.
(defun tts-queue--identity () [0 1 2 3 4 5])

(defun tts-queue--compose (first second)
  "Compose fixed transfer tables FIRST then SECOND."
  (let ((result (make-vector 6 0)))
    (dotimes (index 6)
      (let* ((a (aref first index)) (b (aref second (logand a 7))))
        (aset result index (logior b (logand a 8)))))
    result))

(defun tts-queue--bounded-p (string)
  "Whether STRING fits the bounded proof inspection budget."
  (and (stringp string) (<= (string-bytes string) tts-queue--limit)))

(defun tts-queue--hash (string)
  "Fingerprint bounded STRING without retaining another command."
  (when (tts-queue--bounded-p string)
    (secure-hash 'sha256 string nil nil t)))

(defun tts-queue--matches-p (description string)
  "Whether DESCRIPTION still describes STRING."
  (and (tts-queue--description-p description)
       (equal (tts-queue--description-hash description) (tts-queue--hash string))
       (tts-queue--description-hash description)))

(defun tts-queue--opaque (string)
  "Describe unknown STRING without inferring its command semantics."
  (cond
   ((equal string "") (tts-queue--identity))
   ((and (tts-queue--bounded-p string) (string-suffix-p "\n" string))
    [12 12 12 12 12 12])
   (t [13 13 13 13 13 13])))

(defun tts-queue--utf8-p (string)
  "Whether STRING contains Unicode scalar values, or valid UTF-8 bytes."
  (let ((decoded (if (multibyte-string-p string) string
                   (decode-coding-string string 'utf-8-unix))))
    (cl-loop for character across decoded
             always (and (<= character #x10ffff)
                         (not (<= #xd800 character #xdfff))))))

(defun tts-queue--record-valid-p (line &optional remote)
  "Validate one complete LINE against local or REMOTE framing."
  (and (<= (string-bytes line) (+ tts-queue--line-limit 2))
       (string-suffix-p "\n" line)
       (not (string-match-p "\n" (substring line 0 -1)))
       (tts-queue--utf8-p line)
       (let ((bytes (string-bytes (encode-coding-string line 'utf-8-unix))))
         (if remote
             (and (<= bytes tts-queue--line-limit)
                  (not (string-search "\0" line))
                  (or (not (string-prefix-p "OMNIVOX-REMOTE" line))
                      (member line '("OMNIVOX-REMOTE ping\n" "OMNIVOX-REMOTE ping\r\n"))))
           (<= (- bytes (if (string-suffix-p "\r\n" line) 2 1))
               tts-queue--line-limit)))))

(defun tts-queue--remote-packet-p (string)
  "Validate complete bounded remote STRING without a retained decoder tail."
  (and (tts-queue--bounded-p string)
       (or (string-empty-p string)
           (and (string-suffix-p "\n" string)
                (let ((start 0) end (valid t))
                  (while (and valid (setq end (string-search "\n" string start)))
                    (setq valid (tts-queue--record-valid-p
                                 (substring string start (1+ end)) t)
                          start (1+ end)))
                  valid)))))

(defun tts-queue--typed-record-p (line effect)
  "Check a constructor's declared EFFECT against its one complete LINE.
This validator is never used to classify generic output."
  (and (tts-queue--record-valid-p line)
       (let ((value (string-trim line)))
         (pcase effect
           ('clear
            (or (member value '("d" "s" "tts_reset"))
                (and (string-match
                      "\\`emacsvox_\\(?:tracked\\|marker\\)_dispatch \\([0-9]+\\)\\'" value)
                     (<= 1 (string-to-number (match-string 1 value))
                         18446744073709551615))))
           ('queue
            (string-match-p
             "\\`\\(?:[qc] \\|\\(?:sh\\|t\\|a\\|emacsvox_tone\\) \\)" value))
           ('interrupt (string-match-p "\\`\\(?:l\\|tts_say\\) " value))
           ('neutral
            (or (equal value "OMNIVOX-REMOTE ping")
                (string-match-p
                 (concat "\\`\\(?:p\\|version\\|tts_sync_state\\|tts_split_caps\\|"
                         "tts_set_\\(?:speech_rate\\|character_scale\\|pitch_multiplier\\|"
                         "sound_volume\\|tone_volume\\|voice_volume\\|voice\\|speech_channel\\|"
                         "punctuations\\|capitalization_presentation\\)\\|"
                         "set_\\(?:lang\\|next_lang\\|previous_lang\\|preferred_lang\\)\\|"
                         "omnivox_control\\|emacsvox_timeline\\(?:_part\\)?\\)\\(?: \\|\\'\\)")
                 value)))
           ('frame (string-match-p "\\`emacsvox_tx [0-9]+ {[A-Za-z0-9+/=]+}\\'" value))
           (_ nil)))))

(defun tts-queue--record-table (effect)
  "Return the transfer table for validated EFFECT."
  (pcase effect
    ('clear [8 12 8 12 8 12])
    ('queue [10 12 10 12 12 12])
    ('interrupt [8 12 10 12 12 12])
    ('neutral [0 12 2 12 4 12])
    ;; Closed frame executes to empty or is skipped.  Only empty joins empty.
    ('frame [8 12 12 12 12 12])
    (_ (error "Invalid private queue effect"))))

(defun tts-queue--describe (string effects)
  "Describe constructor STRING with ordered EFFECTS, never generic output.
EFFECTS is one symbol, or one symbol per record.  Mismatches remain opaque."
  (save-match-data
    (when (tts-queue--bounded-p string)
      (let ((table (tts-queue--identity)) (start 0) end
            (remaining (if (symbolp effects) (list effects) effects)))
	(while (setq end (string-search "\n" string start))
          (let* ((line (substring string start (1+ end)))
		 (effect (pop remaining)))
            (setq table (tts-queue--compose
			 table (if (tts-queue--typed-record-p line effect)
                                   (tts-queue--record-table effect)
				 (tts-queue--opaque line)))
                  start (1+ end))))
	(unless (= start (length string))
          (setq table (tts-queue--compose table (tts-queue--opaque (substring string start)))))
	(tts-queue--make-description :table table :hash (tts-queue--hash string))))))

(defun tts-queue--packet (strings descriptions)
  "Join STRINGS and checked DESCRIPTIONS into a command and bounded summary."
  (let ((table (tts-queue--identity)))
    (cl-mapc
     (lambda (string description)
       (when (and description (not (tts-queue--matches-p description string)))
         (error "Speech command changed after preparation"))
       (setq table (tts-queue--compose
                    table (if description (tts-queue--description-table description)
                            (tts-queue--opaque string)))))
     strings descriptions)
    (let ((command (apply #'concat strings)))
      (cons command (and (tts-queue--bounded-p command)
                         (tts-queue--make-description
                          :table table :hash (tts-queue--hash command)))))))

(defun tts-queue--resolve (process)
  "Resolve primitive PROCESS arguments without affecting other processes."
  (condition-case nil
      (cond ((processp process) process)
            ((null process) (get-buffer-process (current-buffer)))
            ((bufferp process) (get-buffer-process process))
            ((stringp process) (or (get-process process) (get-buffer-process process))))
    (error nil)))

(defun tts-queue--invalidate (state &optional unusable)
  "Conservatively invalidate STATE; never make an unusable record usable."
  (when (tts-queue--state-p state)
    (setf (tts-queue--state-queue state) 2
          (tts-queue--state-framing state) 1
          (tts-queue--state-birth state) nil
          (tts-queue--state-auth state) nil
          (tts-queue--state-unusable state)
          (or unusable (tts-queue--state-remote state) (tts-queue--state-unusable state)))))

(defun tts-queue--bump (process state)
  "Advance STATE's serial without ever reusing an old guard on PROCESS."
  (when (eq state (process-get process 'tts-queue--state))
    (if (< (tts-queue--state-serial state) most-positive-fixnum)
	(cl-incf (tts-queue--state-serial state))
      (tts-queue--invalidate state t)
      (process-put process 'tts-queue--state
                   (tts-queue--make-state
                    :generation (tts-queue--state-generation state)
                    :remote (tts-queue--state-remote state)
                    :unusable (tts-queue--state-remote state))))))

(defun tts-queue--state (process)
  "Find PROCESS's record, adopting attached or malformed managed state unknown."
  (when (processp process)
    (let ((state (process-get process 'tts-queue--state)))
      (if (and (tts-queue--state-p state)
               (memq (tts-queue--state-queue state) '(0 1 2))
               (memq (tts-queue--state-framing state) '(0 1))
               (integerp (tts-queue--state-serial state))
               (<= 0 (tts-queue--state-serial state) most-positive-fixnum))
          state
        (when (or state (process-get process 'tts--speech-process-generation)
                  (process-get process 'omnivox-remote-managed)
                  (and (boundp 'tts-speaker-process) (eq process (symbol-value 'tts-speaker-process)))
                  (and (boundp 'tts-notify-process) (eq process (symbol-value 'tts-notify-process))))
          (let ((remote (or (process-get process 'omnivox-remote-managed)
                            (eq (process-type process) 'network))))
            (process-put process 'tts-queue--state
                         (tts-queue--make-state
                          :remote remote :unusable remote
                          :generation (process-get process 'tts--speech-process-generation)))))))))

(defun tts-queue--coverage-p ()
  "Whether all three observers are present nearest their respective primitives."
  (cl-every
   (lambda (pair)
     (let ((seen nil) (valid t))
       (advice-mapc
        (lambda (function properties)
          (if (eq function (cdr pair)) (setq seen t)
            (when (>= (or (alist-get 'depth properties) 0) tts-queue--observer-depth)
              (setq valid nil))))
        (car pair))
       (and seen valid)))
   '((process-send-string . tts-queue--observe-string)
     (process-send-region . tts-queue--observe-region)
     (process-send-eof . tts-queue--observe-eof))))

(defun tts-queue--current-p (process state)
  "Whether STATE still belongs to PROCESS's live generation."
  (and (eq state (process-get process 'tts-queue--state))
       (process-live-p process)
       (not (process-get process 'tts--speech-process-retiring))
       (equal (tts-queue--state-generation state)
              (process-get process 'tts--speech-process-generation))))

(defun tts-queue--known-empty-p (process)
  "Whether PROCESS has usable empty-queue and input-boundary proof."
  (when-let* ((state (tts-queue--state process)))
    (unless (tts-queue--coverage-p) (tts-queue--invalidate state))
    (and (tts-queue--current-p process state)
         (not (tts-queue--state-flight state))
         (not (tts-queue--state-unusable state))
         (not (tts-queue--state-birth state))
         (zerop (tts-queue--state-queue state))
         (zerop (tts-queue--state-framing state))
         (eq (cdr (process-coding-system process)) 'utf-8-unix))))

(defun tts-queue--guard (process &optional registry-property)
  "Freeze PROCESS's proof and optional REGISTRY-PROPERTY in one bounded guard."
  (when (tts-queue--known-empty-p process)
    (let ((state (tts-queue--state process)))
      (tts-queue--make-guard
       :process process :state state :serial (tts-queue--state-serial state)
       :generation (tts-queue--state-generation state)
       :registry-property registry-property
       :registry (and registry-property (process-get process registry-property))))))

(defun tts-queue--guard-identity-p (guard process state serial)
  "Check GUARD against PROCESS, STATE and SERIAL, including its registry."
  (and (eq process (tts-queue--guard-process guard))
       (eq state (tts-queue--guard-state guard))
       (= serial (tts-queue--guard-serial guard))
       (equal (tts-queue--guard-generation guard) (tts-queue--state-generation state))
       (or (not (tts-queue--guard-registry-property guard))
           (eq (tts-queue--guard-registry guard)
               (process-get process (tts-queue--guard-registry-property guard))))))

(defun tts-queue--guard-valid-p (guard)
  "Whether the complete proof retained by GUARD still holds."
  (let ((process (tts-queue--guard-process guard)))
    (and (tts-queue--known-empty-p process)
         (let ((state (tts-queue--state process)))
           (tts-queue--guard-identity-p guard process state (tts-queue--state-serial state))))))

(defun tts-queue--advance-stop (guard receipt)
  "Advance GUARD exactly once using its private, successful policy Stop RECEIPT."
  (unless (and receipt (not (tts-queue--guard-stop-used guard))
               (eq guard (tts-queue--write-guard (nth 5 receipt)))
               (tts-queue--write-own-stop (nth 5 receipt))
               (eq (car receipt) (tts-queue--guard-state guard))
               (= (nth 1 receipt) (tts-queue--guard-serial guard))
               (= (nth 3 receipt) 0) (= (nth 4 receipt) 0)
               (tts-queue--known-empty-p (tts-queue--guard-process guard))
               (= (nth 2 receipt) (tts-queue--state-serial (car receipt))))
    (signal 'tts-queue--proof-lost nil))
  (setf (tts-queue--guard-stop-used guard) t
        (tts-queue--guard-serial guard) (nth 2 receipt))
  (unless (tts-queue--guard-valid-p guard) (signal 'tts-queue--proof-lost nil)))

(defun tts-queue--observe (primitive argument string other arguments)
  "Observe PRIMITIVE output to ARGUMENT with STRING, OTHER type and ARGUMENTS."
  (let* ((process (tts-queue--resolve argument))
         (state (tts-queue--state process))
         (token tts-queue--token)
         (typed (and (not other) token (not (tts-queue--write-used token))
                     (eq process (tts-queue--write-process token))
                     (eq string (tts-queue--write-string token)))))
    (when typed (setf (tts-queue--write-used token) t))
    (let ((tts-queue--token nil))
      (cond
       ((not state)
        (when tts-queue--birth (setcar tts-queue--birth t))
        (apply primitive argument arguments))
       ((tts-queue--state-flight state)
        (setf (tts-queue--state-overlap state) t)
        (tts-queue--invalidate state (eq other 'eof))
        (tts-queue--bump process state)
        (apply primitive argument arguments))
       (t
        (let ((before (+ (* 2 (tts-queue--state-queue state)) (tts-queue--state-framing state)))
              (serial (tts-queue--state-serial state))
              (description (and typed (tts-queue--write-description token)))
              (guard (and typed (tts-queue--write-guard token)))
              (auth (and typed (tts-queue--write-auth token)
                         (tts-queue--state-birth state)
                         (not (tts-queue--state-auth state))
                         (<= (string-bytes string) 256)
                         (string-match-p
                          "\\`OMNIVOX-REMOTE 1 [0-9a-f]\\{64\\} [0-9a-f]\\{32\\} \\(?:speaker\\|notification\\)\n\\'"
                          string)))
              (flight (list nil)) complete result)
          (unwind-protect
              (progn
                (setf (tts-queue--state-flight state) flight
                      (tts-queue--state-overlap state) nil
                      (tts-queue--state-queue state) 2
                      (tts-queue--state-framing state) 1)
                (when (or (not (tts-queue--current-p process state))
                          (not (tts-queue--coverage-p))
                          (not (eq (cdr (process-coding-system process)) 'utf-8-unix)))
                  (tts-queue--invalidate state)
                  (setq before 5))
                (when (and description (not (tts-queue--matches-p description string)))
                  (error "Speech command changed before output"))
                (when (and (tts-queue--state-birth state) (not auth))
                  (tts-queue--invalidate state t))
                (when (and guard
                           (not (and (= before 0)
                                     (not (tts-queue--state-unusable state))
                                     (tts-queue--current-p process state)
                                     (tts-queue--coverage-p)
                                     (tts-queue--guard-identity-p guard process state serial)
                                     (or (not (tts-queue--state-remote state))
                                         (tts-queue--remote-packet-p string)))))
                  (signal 'tts-queue--proof-lost nil))
                (setq result (apply primitive argument arguments))
                (when (and (tts-queue--current-p process state)
                           (not (tts-queue--state-overlap state))
                           (not (tts-queue--state-unusable state))
                           (tts-queue--coverage-p)
                           (eq (cdr (process-coding-system process)) 'utf-8-unix)
                           (not other)
                           (tts-queue--bounded-p string)
                           (or (not description) (tts-queue--matches-p description string))
                           (or auth (not (tts-queue--state-remote state))
                               (or (string-empty-p string)
                                   (and (zerop (% before 2)) (tts-queue--remote-packet-p string)))))
                  (let* ((table (if auth (tts-queue--identity)
                                  (if description (tts-queue--description-table description)
                                    (tts-queue--opaque string))))
                         (value (aref table before)) (index (logand value 7)))
                    (when (/= 0 (logand value 8)) (tts-queue--bump process state))
                    (when (tts-queue--current-p process state)
                      (setf (tts-queue--state-queue state) (/ index 2)
                            (tts-queue--state-framing state) (% index 2))
                      (when typed
                        (setf (tts-queue--write-receipt token)
                              (list state serial (tts-queue--state-serial state) before index token)))
                      (when auth
                        (setf (tts-queue--state-auth state)
                              (tts-queue--write-receipt token)))
                      (setq complete t))))
                result)
            (unwind-protect
                (unless complete
                  (tts-queue--invalidate state (eq other 'eof))
                  (tts-queue--bump process state))
              (when (eq flight (tts-queue--state-flight state))
                (setf (tts-queue--state-flight state) nil
                      (tts-queue--state-overlap state) nil))))))))))

(defun tts-queue--observe-string (primitive process string)
  "Observe string output while retaining PRIMITIVE semantics."
  (save-match-data (tts-queue--observe primitive process string nil (list string))))

(defun tts-queue--observe-region (primitive process start end)
  "Invalidate on region output, without retaining its contents."
  (tts-queue--observe primitive process nil 'region (list start end)))
(defun tts-queue--observe-eof (primitive &optional process)
  "Invalidate permanently on EOF."
  (tts-queue--observe primitive process nil 'eof nil))

(defun tts-queue--install ()
  "Install private observers without removing other advice."
  (dolist (pair '((process-send-string . tts-queue--observe-string)
                  (process-send-region . tts-queue--observe-region)
                  (process-send-eof . tts-queue--observe-eof)))
    (advice-add (car pair) :around (cdr pair) `((depth . ,tts-queue--observer-depth)))))

(defun tts-queue--send (process command description &optional auth guard own-stop)
  "Send COMMAND once with DESCRIPTION, returning a proof receipt when available."
  (let* ((resolved (tts-queue--resolve process)) (state (tts-queue--state resolved))
         (tts-queue--token (tts-queue--make-write
                            :process resolved :string command :description description :auth auth
                            :guard guard :own-stop (and own-stop (equal command "s\n"))))
         complete)
    (unwind-protect
        (progn
          (when (and state (not (tts-queue--coverage-p)))
            (tts-queue--invalidate state))
          (when (and guard
                     (not (and (tts-queue--guard-valid-p guard)
                               (tts-queue--matches-p description command)
                               (or (not (tts-queue--state-remote state))
                                   (tts-queue--remote-packet-p command)))))
            (signal 'tts-queue--proof-lost nil))
          (process-send-string process command)
          (unless (tts-queue--write-receipt tts-queue--token)
            (when state (tts-queue--invalidate state)))
          (when (and guard
                     (not (and (tts-queue--write-receipt tts-queue--token)
                               (or own-stop (tts-queue--guard-valid-p guard)))))
            (signal 'tts-queue--proof-lost nil))
          (setq complete t)
          (tts-queue--write-receipt tts-queue--token))
      (unless complete
        (when state
          (tts-queue--invalidate state)
          (tts-queue--bump resolved state)))
      (setf (tts-queue--write-string tts-queue--token) nil))))

(defun tts-queue--authenticated (process receipt)
  "Consume PROCESS's exact fresh authentication RECEIPT after remote ready."
  (when-let* ((state (tts-queue--state process)))
    (when (and receipt (eq receipt (tts-queue--state-auth state))
               (tts-queue--state-birth state)
               (not (tts-queue--state-unusable state))
               (not (tts-queue--state-flight state))
               (tts-queue--current-p process state)
               (tts-queue--coverage-p))
      (setf (tts-queue--state-queue state) 0
            (tts-queue--state-framing state) 0
            (tts-queue--state-birth state) nil
            (tts-queue--state-auth state) nil))))

(defun tts-queue--send-typed (process command effects)
  "Send constructor COMMAND with declared EFFECTS."
  (tts-queue--send process command (tts-queue--describe command effects)))

(defun tts-queue--attach (process remote clean)
  "Attach owned PROCESS provisionally; REMOTE birth awaits authentication."
  (or (tts-queue--state process)
      (process-put process 'tts-queue--state
                   (tts-queue--make-state
                    :remote remote :birth (and remote clean)
                    :unusable (and remote (not clean))
                    :queue (if (and clean (not remote)) 0 2)
                    :framing (if clean 0 1)))))

(defun tts-queue--create (factory remote)
  "Call owned FACTORY under birth observation, then attach its returned process."
  (let* ((tts-queue--birth (or tts-queue--birth (list nil)))
         (constructor (if remote 'make-network-process 'make-process))
         (native (symbol-function constructor))
         (process (funcall factory)))
    ;; Factory advice could return an old, unregistered process.  Only the
    ;; unchanged native constructor establishes a fresh birth; otherwise keep
    ;; ordinary output available without granting fresh empty-queue proof.
    (tts-queue--attach process remote
                       (and (subrp native)
                            (eq native (symbol-function constructor))
                            (not (car tts-queue--birth))
                            (tts-queue--coverage-p)))
    process))

(defun tts-queue--set-generation (process generation)
  "Attach GENERATION to PROCESS without erasing observed provisional state."
  (when-let* ((state (tts-queue--state process)))
    (when (tts-queue--state-generation state) (tts-queue--invalidate state))
    (setf (tts-queue--state-generation state) generation)))

(defun tts-queue--retire (process)
  "Retire PROCESS's proof permanently."
  (tts-queue--invalidate (tts-queue--state process) t))

(tts-queue--install)
(provide 'tts-queue-state)
;;; tts-queue-state.el ends here
