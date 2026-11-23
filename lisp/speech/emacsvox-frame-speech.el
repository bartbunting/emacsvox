;;; emacsvox-frame-speech.el --- Speech workers for an Emacs frame -*- lexical-binding: t; -*-

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

;; A transport starts and negotiates its workers, then attaches them to a
;; frame. Commands capture that attachment across minibuffers and callbacks.
;; The handle expires when either the frame or its attachment is replaced.

;;; Code:

(require 'cl-lib)
(require 'seq)

(defvar tts-quiet)
(defvar emacsvox-play-program)
(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar tts-speech-rate)
(defvar omnivox--control-capabilities-property)
(defvar omnivox--control-inventory-property)
(defvar omnivox--control-registration-property)

(cl-defstruct (emacsvox-frame-speech--endpoint
               (:constructor emacsvox-frame-speech--create)
               (:copier nil))
  frame main notification program rate)

(defvar emacsvox-frame-speech-detach-hook nil
  "Functions called with FRAME before its speech attachment changes.")

(defvar emacsvox-frame-speech--command-owner nil)
(defvar emacsvox-frame-speech--hook-owner nil)
(defvar emacsvox-frame-speech--active nil)
(defvar emacsvox-frame-speech--desktop-values nil)
(defvar emacsvox-frame-speech--installed nil)
(defconst emacsvox-frame-speech--variables
  '(tts-speaker-process tts-notify-process tts-program tts-speech-rate
    emacsvox-play-program omnivox-control-capabilities omnivox-engine-inventory
    omnivox-engine-inventory-time omnivox-logical-voice-registration
    omnivox-routing-policy-registration omnivox-control-last-error tts-handle-unicode))

(defun emacsvox-frame-speech-endpoint (&optional frame)
  "Return the speech attachment for FRAME, or nil for ordinary desktop speech.
FRAME defaults to the selected frame. Capture this handle before starting
asynchronous work and pass it to `emacsvox-frame-speech-call' on completion."
  (frame-parameter frame 'emacsvox-speech-endpoint))

(defun emacsvox-frame-speech--valid-p (endpoint)
  (and (emacsvox-frame-speech--endpoint-p endpoint)
       (let ((frame (emacsvox-frame-speech--endpoint-frame endpoint)))
         (and (frame-live-p frame)
              (eq (emacsvox-frame-speech-endpoint frame) endpoint)
              (process-live-p (emacsvox-frame-speech--endpoint-main endpoint))))))

(defun emacsvox-frame-speech--origin ()
  (or emacsvox-frame-speech--command-owner emacsvox-frame-speech--hook-owner))

(defun emacsvox-frame-speech--values (endpoint)
  (let* ((main (emacsvox-frame-speech--endpoint-main endpoint))
         (inventory (and (boundp 'omnivox--control-inventory-property)
                         (process-get main omnivox--control-inventory-property))))
    (list main (or (emacsvox-frame-speech--endpoint-notification endpoint) main)
          (emacsvox-frame-speech--endpoint-program endpoint)
          (emacsvox-frame-speech--endpoint-rate endpoint)
          nil
          (and (boundp 'omnivox--control-capabilities-property)
               (process-get main omnivox--control-capabilities-property))
          inventory (process-get main 'omnivox-inventory-received-at)
          (and (boundp 'omnivox--control-registration-property)
               (process-get main omnivox--control-registration-property))
          (plist-get inventory :routing_policy) nil
          (bound-and-true-p tts-handle-unicode))))

(defun emacsvox-frame-speech-call (endpoint function &rest args)
  "Call FUNCTION with ARGS through ENDPOINT. Return its result.
A nil ENDPOINT uses ordinary desktop speech. An expired attachment
discards the callback. Nested calls can target a different frame."
  (let ((emacsvox-frame-speech--command-owner (or endpoint 'desktop)))
    (cond
     ((memq endpoint '(nil desktop))
      (if (and emacsvox-frame-speech--active emacsvox-frame-speech--desktop-values)
          (let ((emacsvox-frame-speech--active nil))
            (cl-progv emacsvox-frame-speech--variables emacsvox-frame-speech--desktop-values
              (apply function args)))
        (apply function args)))
     ((emacsvox-frame-speech--valid-p endpoint)
      (if (eq emacsvox-frame-speech--active endpoint)
          (apply function args)
        (let ((emacsvox-frame-speech--active endpoint)
              (emacsvox-frame-speech--desktop-values
               (or emacsvox-frame-speech--desktop-values
                   (mapcar (lambda (key) (and (boundp key) (symbol-value key)))
                           emacsvox-frame-speech--variables))))
          (cl-progv emacsvox-frame-speech--variables (emacsvox-frame-speech--values endpoint)
            (apply function args))))))))

(defun emacsvox-frame-speech--route (function &rest args)
  (let ((owner (emacsvox-frame-speech--origin)))
    (cond
     ((and (eq owner emacsvox-frame-speech--active) (emacsvox-frame-speech--endpoint-p owner))
      ;; An integration may select a local player inside a command. The
      ;; frame's server owns both its immediate and its queued recordings.
      (let ((emacsvox-play-program nil))
        (apply #'emacsvox-frame-speech-call owner function args)))
     (owner (apply #'emacsvox-frame-speech-call owner function args))
     (t (apply function args)))))

(defun emacsvox-frame-speech--pre-command ()
  (setq emacsvox-frame-speech--hook-owner (or (emacsvox-frame-speech-endpoint) 'desktop)))

(defun emacsvox-frame-speech--post-command ()
  (setq emacsvox-frame-speech--hook-owner nil))

(defun emacsvox-frame-speech--with-origin (owner function &rest args)
  "Run FUNCTION even if OWNER expired while an editor request was pending."
  (if (or (memq owner '(nil desktop)) (emacsvox-frame-speech--valid-p owner))
      (apply #'emacsvox-frame-speech-call owner function args)
    (let ((emacsvox-frame-speech--command-owner owner)
          (tts-speaker-process nil) (tts-notify-process nil)
          (emacsvox-play-program nil) (tts-quiet t))
      (apply function args))))

(defun emacsvox-frame-speech--command (function &rest args)
  (apply #'emacsvox-frame-speech--with-origin (emacsvox-frame-speech-endpoint) function args))

(defun emacsvox-frame-speech--key-echo (function text)
  ;; Emacs can echo a partial key before either command hook runs.
  (let* ((endpoint (emacsvox-frame-speech-endpoint))
         (keys (and endpoint (this-single-command-keys)))
         (name (and (length> keys 0) (key-description keys)))
         (emacsvox-frame-speech--command-owner
          (or (emacsvox-frame-speech--origin)
              (and name (stringp text)
                   (or (equal text name) (equal text (concat name "-"))
                       (string-prefix-p (concat name "- (") text))
                   endpoint))))
    (funcall function text)))

(defun emacsvox-frame-speech--phonetic (function request)
  (let ((window (nth 1 request)))
    (when (window-live-p window)
      (emacsvox-frame-speech-call (emacsvox-frame-speech-endpoint (window-frame window))
                                  function request))))

(defun emacsvox-frame-speech--stop (function &optional all)
  (interactive (list t))
  (emacsvox-frame-speech--route function all))

(defun emacsvox-frame-speech--set-rate (function rate &optional prefix)
  (let ((owner (emacsvox-frame-speech--origin)))
    (cond
     ((memq owner '(nil desktop)) (emacsvox-frame-speech--route function rate prefix))
     ((emacsvox-frame-speech--valid-p owner)
      (setf (emacsvox-frame-speech--endpoint-rate owner) rate)
      (emacsvox-frame-speech-call
       owner (lambda ()
               (when (and prefix (process-live-p tts-notify-process)
                          (not (eq tts-notify-process tts-speaker-process)))
                 (let ((tts-speaker-process tts-notify-process)) (funcall function rate nil)))
               (funcall function rate nil)))))))

(defconst emacsvox-frame-speech--entries
  '(emacsvox-aural-call-with-submission emacsvox-icon tts-letter tts-speak
    tts-voice-inventory tts-refresh-voice-inventory tts-preview-voices
    tts-dispatch tts-tone tts-silence tts-notify-apply tts--protocol-set-punctuations
    emacsvox--delayed-phonetic-schedule))

(defun emacsvox-frame-speech--install ()
  (unless emacsvox-frame-speech--installed
    (add-hook 'pre-command-hook #'emacsvox-frame-speech--pre-command -100)
    (add-hook 'post-command-hook #'emacsvox-frame-speech--post-command 100)
    (add-hook 'delete-frame-functions #'emacsvox-frame-speech-detach)
    (advice-add 'command-execute :around #'emacsvox-frame-speech--command)
    (advice-add 'set-minibuffer-message :around #'emacsvox-frame-speech--key-echo '((depth . -90)))
    (advice-add 'emacsvox--delayed-phonetic-announce :around #'emacsvox-frame-speech--phonetic)
    (advice-add 'tts-stop :around #'emacsvox-frame-speech--stop)
    (advice-add 'tts-set-rate :around #'emacsvox-frame-speech--set-rate)
    (dolist (entry emacsvox-frame-speech--entries)
      (advice-add entry :around #'emacsvox-frame-speech--route))
    (setq emacsvox-frame-speech--installed t)))

(defun emacsvox-frame-speech--uninstall ()
  (remove-hook 'pre-command-hook #'emacsvox-frame-speech--pre-command)
  (remove-hook 'post-command-hook #'emacsvox-frame-speech--post-command)
  (remove-hook 'delete-frame-functions #'emacsvox-frame-speech-detach)
  (advice-remove 'command-execute #'emacsvox-frame-speech--command)
  (advice-remove 'set-minibuffer-message #'emacsvox-frame-speech--key-echo)
  (advice-remove 'emacsvox--delayed-phonetic-announce #'emacsvox-frame-speech--phonetic)
  (advice-remove 'tts-stop #'emacsvox-frame-speech--stop)
  (advice-remove 'tts-set-rate #'emacsvox-frame-speech--set-rate)
  (dolist (entry emacsvox-frame-speech--entries)
    (advice-remove entry #'emacsvox-frame-speech--route))
  (setq emacsvox-frame-speech--installed nil emacsvox-frame-speech--hook-owner nil))

;;;###autoload
(defun emacsvox-frame-speech-attach (frame main &optional notification program rate)
  "Attach ready speech workers MAIN and NOTIFICATION to FRAME and return a handle.
Omit NOTIFICATION to use MAIN for both lanes. PROGRAM and RATE default to
the current speech configuration. The caller owns worker startup, negotiation
and shutdown. Attaching again replaces the handle for future commands."
  (unless (and (frame-live-p frame) (processp main) (process-live-p main)
               (or (null notification) (and (processp notification) (process-live-p notification))))
    (user-error "Frame attachment requires a live frame and speech workers"))
  (let ((endpoint (emacsvox-frame-speech--create
                   :frame frame :main main :notification notification
                   :program (or program (bound-and-true-p tts-program))
                   :rate (or rate (bound-and-true-p tts-speech-rate)))))
    (run-hook-with-args 'emacsvox-frame-speech-detach-hook frame)
    (set-frame-parameter frame 'emacsvox-speech-endpoint endpoint)
    (emacsvox-frame-speech--install)
    endpoint))

;;;###autoload
(defun emacsvox-frame-speech-detach (&optional frame)
  "Return FRAME to ordinary speech and expire its earlier callbacks.
FRAME defaults to the selected frame. Its transport still owns its workers."
  (setq frame (or frame (selected-frame)))
  (when (emacsvox-frame-speech-endpoint frame)
    (run-hook-with-args 'emacsvox-frame-speech-detach-hook frame)
    (set-frame-parameter frame 'emacsvox-speech-endpoint nil)
    (when (and emacsvox-frame-speech--installed
               (not (seq-some #'emacsvox-frame-speech-endpoint (frame-list))))
      (emacsvox-frame-speech--uninstall))))

(provide 'emacsvox-frame-speech)
;;; emacsvox-frame-speech.el ends here
