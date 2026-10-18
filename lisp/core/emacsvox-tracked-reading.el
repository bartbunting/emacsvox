;;; emacsvox-tracked-reading.el --- Interruptible buffer reading -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Spoken Output
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

;; Read a buffer in bounded chunks, advancing point after playback completion.
;; Keep session markers, callback generations and cancellation hooks together.
;; The core speech library loads these definitions; loading them alone neither
;; starts speech nor installs hooks.  The public command starts each session.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function tts-cancel-tracked-dispatch "tts-lifecycle" (identifier))
(declare-function tts-tracked-playback-completion-p "tts-lifecycle" (&optional program))
(declare-function tts-stop "tts-speak" (&optional all))
(declare-function tts-initialize "tts-speak" ())
(declare-function tts-speak-tracked "tts-speak" (text callback))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-aural-source-substring "emacsvox-aural-source"
                  (start end &optional buffer))

(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-stop-immediately)

(defcustom emacsvox-tracked-reading-max-chars 280
  "Maximum source characters in one tracked reading chunk.
Tracked reading prefers sentence boundaries and uses this limit to keep the
position retained after interruption reasonably close to audible playback."
  :type 'positive-integer
  :group 'emacsvox)

(cl-defstruct
    (emacsvox--tracked-reading-session
     (:constructor emacsvox--make-tracked-reading-session))
  "State for one interruptible rest-of-buffer reading session."
  buffer window limit next current-start current-end identifier generation
  process)

(defvar emacsvox--tracked-reading-session nil
  "The active interruptible rest-of-buffer reading session.")

(defvar emacsvox--tracked-reading-generation 0
  "Generation distinguishing current and stale tracked reading callbacks.")

(defun emacsvox--tracked-reading-set-point (session position)
  "Set SESSION's source buffer and live source window to POSITION."
  (let ((buffer (emacsvox--tracked-reading-session-buffer session))
        (window (emacsvox--tracked-reading-session-window session)))
    (with-current-buffer buffer
      (goto-char position))
    (when
        (and
         (window-live-p window)
         (eq (window-buffer window) buffer))
      (set-window-point window position))))

(defun emacsvox--tracked-reading-release-markers (session)
  "Detach all source markers owned by SESSION."
  (dolist
      (marker
       (list
        (emacsvox--tracked-reading-session-limit session)
        (emacsvox--tracked-reading-session-next session)
        (emacsvox--tracked-reading-session-current-start session)
        (emacsvox--tracked-reading-session-current-end session)))
    (when (markerp marker)
      (set-marker marker nil))))

(defun emacsvox--tracked-reading-cancel (&optional stop-speech)
  "Cancel tracked reading, optionally stopping current speech."
  (when-let* ((session emacsvox--tracked-reading-session))
    (setq emacsvox--tracked-reading-session nil)
    (remove-hook 'pre-command-hook #'emacsvox--tracked-reading-pre-command)
    (remove-hook 'tts-stopped-hook #'emacsvox--tracked-reading-stopped)
    (when-let* ((identifier
                 (emacsvox--tracked-reading-session-identifier session)))
      (tts-cancel-tracked-dispatch identifier))
    (when-let* ((buffer
                 (emacsvox--tracked-reading-session-buffer session)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (remove-hook
           'kill-buffer-hook #'emacsvox--tracked-reading-buffer-killed t))))
    (emacsvox--tracked-reading-release-markers session)
    (when stop-speech
      (tts-stop 'all))))

(defun emacsvox--tracked-reading-pre-command ()
  "Stop tracked reading before the next user command."
  (emacsvox--tracked-reading-cancel t))

(defun emacsvox--tracked-reading-stopped (process)
  "Cancel tracked reading when its speech PROCESS is stopped elsewhere."
  (when
      (and
       emacsvox--tracked-reading-session
       (eq
        process
        (emacsvox--tracked-reading-session-process
         emacsvox--tracked-reading-session)))
    (emacsvox--tracked-reading-cancel)))

(defun emacsvox--tracked-reading-buffer-killed ()
  "Cancel tracked reading when its source buffer is killed."
  (emacsvox--tracked-reading-cancel t))

(defun emacsvox--tracked-reading-chunk-end (limit)
  "Return a sentence-oriented chunk end no later than LIMIT."
  (let* ((start (point))
         (hard-limit
          (min limit (+ start emacsvox-tracked-reading-max-chars)))
         sentence-end)
    (save-excursion
      (condition-case nil
          (progn
            (forward-sentence 1)
            (setq sentence-end (min limit (point))))
        (error
         (setq sentence-end limit)))
      (when (<= sentence-end start)
        (goto-char start)
        (forward-line 1)
        (setq sentence-end (min limit (point))))
      (when (> sentence-end hard-limit)
        (goto-char hard-limit)
        (setq
         sentence-end
         (if
             (and
              (re-search-backward "[[:space:]]+" start t)
              (> (match-end 0) start))
             (match-end 0)
           hard-limit)))
      (max (min limit sentence-end) (min limit (1+ start))))))

(defun emacsvox--tracked-reading-finish (generation)
  "Finish tracked reading session GENERATION at its saved limit."
  (when
      (and
       emacsvox--tracked-reading-session
       (= generation
          (emacsvox--tracked-reading-session-generation
           emacsvox--tracked-reading-session)))
    (let* ((session emacsvox--tracked-reading-session)
           (buffer (emacsvox--tracked-reading-session-buffer session))
           (limit (emacsvox--tracked-reading-session-limit session)))
      (when (and (buffer-live-p buffer) (marker-position limit))
        (emacsvox--tracked-reading-set-point session (marker-position limit)))
      (emacsvox--tracked-reading-cancel))))

(defun emacsvox--tracked-reading-complete (generation identifier status)
  "Handle tracked reading IDENTIFIER with STATUS for GENERATION."
  (when-let* ((session emacsvox--tracked-reading-session))
    (when
        (and
         (= generation
            (emacsvox--tracked-reading-session-generation session))
         (eql
          identifier
          (emacsvox--tracked-reading-session-identifier session)))
      (setf (emacsvox--tracked-reading-session-identifier session) nil)
      (if (eq status 'completed)
          (progn
            (let ((end
                   (marker-position
                    (emacsvox--tracked-reading-session-current-end session))))
              (when end
                (set-marker
                 (emacsvox--tracked-reading-session-next session) end)
                (emacsvox--tracked-reading-set-point session end)))
            (emacsvox--tracked-reading-next generation))
        (emacsvox--tracked-reading-cancel)
        (when (eq status 'failed)
          (message "Tracked speech playback failed"))))))

(defun emacsvox--tracked-reading-next (generation)
  "Speak the next source chunk for tracked reading GENERATION."
  (when-let* ((session emacsvox--tracked-reading-session))
    (when
        (= generation
           (emacsvox--tracked-reading-session-generation session))
      (let ((buffer (emacsvox--tracked-reading-session-buffer session)))
        (if (not (buffer-live-p buffer))
            (emacsvox--tracked-reading-cancel)
          (with-current-buffer buffer
            (let* ((limit-marker
                    (emacsvox--tracked-reading-session-limit session))
                   (next-marker
                    (emacsvox--tracked-reading-session-next session))
                   (limit (marker-position limit-marker))
                   (next (marker-position next-marker)))
              (if (not (and limit next))
                  (emacsvox--tracked-reading-cancel)
                (goto-char next)
                (skip-chars-forward " \t\r\n" limit)
                (if (>= (point) limit)
                    (emacsvox--tracked-reading-finish generation)
                  (let* ((start (point))
                         (end (emacsvox--tracked-reading-chunk-end limit))
                         (text
                          (emacsvox-aural-source-substring
                           start end buffer))
                         identifier)
                    (set-marker
                     (emacsvox--tracked-reading-session-current-start session)
                     start)
                    (set-marker
                     (emacsvox--tracked-reading-session-current-end session)
                     end)
                    (emacsvox--tracked-reading-set-point session start)
                    (let ((tts-stop-immediately nil))
                      (setq
                       identifier
                       (tts-speak-tracked
                        text
                        (lambda (completed-identifier status)
                          (emacsvox--tracked-reading-complete
                           generation completed-identifier status)))))
                    (if (integerp identifier)
                        (setf
                         (emacsvox--tracked-reading-session-identifier session)
                         identifier)
                      (emacsvox--tracked-reading-cancel))))))))))))

(defun emacsvox-speak-rest-of-buffer ()
  "Speak from point to buffer end, tracking interrupt position by chunk.
Any subsequent user command interrupts speech.  Point remains at the start of
the sentence-oriented chunk that was audible when interruption occurred."
  (interactive)
  (unless (tts-tracked-playback-completion-p)
    (user-error
     "Speech server `%s' does not support tracked rest-of-buffer reading"
     (file-name-nondirectory (or tts-program "unset"))))
  (if emacsvox--tracked-reading-session
      (emacsvox--tracked-reading-cancel t)
    (tts-stop 'all))
  (unless (process-live-p tts-speaker-process)
    (tts-initialize))
  (emacsvox-icon 'select-object)
  (let* ((generation (cl-incf emacsvox--tracked-reading-generation))
         (position (point))
         (session
          (emacsvox--make-tracked-reading-session
           :buffer (current-buffer)
           :window (selected-window)
           :limit (copy-marker (point-max))
           :next (copy-marker position)
           :current-start (copy-marker position)
           :current-end (copy-marker position t)
           :generation generation
           :process tts-speaker-process)))
    (setq emacsvox--tracked-reading-session session)
    (add-hook 'pre-command-hook #'emacsvox--tracked-reading-pre-command)
    (add-hook 'tts-stopped-hook #'emacsvox--tracked-reading-stopped)
    (add-hook
     'kill-buffer-hook #'emacsvox--tracked-reading-buffer-killed nil t)
    (emacsvox--tracked-reading-next generation)))

(provide 'emacsvox-tracked-reading)

;;; emacsvox-tracked-reading.el ends here
