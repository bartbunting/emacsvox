;;; omnivox-discovery.el --- Omnivox voice discovery and refresh  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Bart Bunting <bart@ursys.com.au>
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

;; Discover physical voices locally or from the connected workstation and
;; request inventory refreshes through the voice adapter's control service.
;; The adapter retains negotiation, request coalescing and response handling,
;; including the routing registration that follows an inventory response.
;; Loading these definitions does not run discovery or start speech processes.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'omnivox-inventory)

(declare-function tts--resolve-program "tts-speak" (program))
(declare-function omnivox-remote-enabled-p "omnivox-remote" ())
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox--request-inventory "omnivox-voices" (process))

(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar omnivox--control-inventory-property)

(defvar omnivox-available-voices nil
  "Physical voices most recently discovered from Omnivox.
Each entry has the form (ID NAME LANGUAGE QUALITY).")

(defconst omnivox--discovery-timeout 30
  "Maximum seconds to wait for offline compatibility voice discovery.")

(defun omnivox--query-voices-program (program)
  "Run PROGRAM's compatibility voice listing with bounded output and waiting."
  (with-temp-buffer
    (let ((default-directory temporary-file-directory)
          (stderr (generate-new-buffer " *omnivox discovery errors*"))
          (deadline (+ (float-time) omnivox--discovery-timeout))
          (bytes 0) overflow process error-process)
      (unwind-protect
          (cl-labels ((capture (child text)
                       (cl-incf bytes (string-bytes text))
                       (if (> bytes (* 4 1024 1024))
                           (setq overflow t)
                         (with-current-buffer (process-buffer child)
                           (goto-char (point-max)) (insert text)))))
            (setq error-process
                  (make-pipe-process :name "omnivox discovery stderr" :buffer stderr
                                     :coding 'utf-8-unix :noquery t
                                     :filter #'capture :sentinel #'ignore)
                  process
                  (make-process :name "omnivox discovery" :buffer (current-buffer)
                                :command (list program "--list-voices-alist")
                                :connection-type 'pipe :coding 'utf-8-unix :noquery t
                                :filter #'capture :sentinel #'ignore :stderr error-process))
            ;; A separate stderr pipe must also reach EOF before parsing. Waits
            ;; permit other process callbacks and C-g, with no timer left behind.
            (while (and (or (process-live-p process) (process-live-p error-process))
                        (not overflow) (< (float-time) deadline))
              (accept-process-output nil (min 0.05 (max 0 (- deadline (float-time))))))
            (when overflow (error "Omnivox voice discovery exceeded its output limit"))
            (when (or (process-live-p process) (process-live-p error-process))
              (error "Omnivox voice discovery timed out after %s seconds" omnivox--discovery-timeout))
            (unless (and (eq (process-status process) 'exit) (zerop (process-exit-status process)))
              (error "Omnivox voice discovery failed: %s"
                     (truncate-string-to-width
                      (string-trim (concat (buffer-string) "\n"
                                           (with-current-buffer stderr (buffer-string)))) 4096)))
            (omnivox--parse-voices (buffer-string)))
        (dolist (child (list process error-process))
          (when (processp child) (delete-process child)))
        (kill-buffer stderr)))))

(defun omnivox--server-program ()
  "Return the Omnivox server program used for discovery, or nil."
  (let ((program (tts--resolve-program tts-program)))
    (and program (file-executable-p program) program)))

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
  "Return physical voices reported by the current Omnivox workstation.
Signal an error if discovery cannot run or returns malformed data."
  (let ((inventory
         (and (process-live-p tts-speaker-process)
              (process-get tts-speaker-process omnivox--control-inventory-property))))
    (cond
     (inventory
      (cl-mapcan
       (lambda (engine)
         (mapcar
          (lambda (voice)
            (list (plist-get (plist-get voice :id) :voice_id)
                  (plist-get voice :display_name)
                  (or (plist-get voice :language) "")
                  (or (plist-get voice :quality) "")))
          (append (plist-get engine :voices) nil)))
       (append (plist-get inventory :engines) nil)))
     ((omnivox-remote-enabled-p)
      (user-error "Workstation voice inventory is not ready; connect and wait for routing readiness"))
     (t
      (let ((program (omnivox--server-program)))
        (unless program
          (error "Could not find the Omnivox server executable"))
        (omnivox--query-voices-program program))))))

(defun omnivox-refresh-voices ()
  "Refresh and return the physical voices available from Omnivox."
  (interactive)
  (setq omnivox-available-voices (omnivox-query-voices))
  (when (called-interactively-p 'interactive)
    (message "Found %d Omnivox voices" (length omnivox-available-voices)))
  omnivox-available-voices)

(defun omnivox-refresh-voice-inventory ()
  "Request fresh inventories from live Omnivox processes and return a snapshot."
  (dolist (process (delete-dups (list tts-speaker-process tts-notify-process)))
    (when (and (process-live-p process)
               (omnivox--process-supports-p process "engine_inventory"))
      (omnivox--request-inventory process)))
  (omnivox-voice-inventory))

(provide 'omnivox-discovery)

;;; omnivox-discovery.el ends here
