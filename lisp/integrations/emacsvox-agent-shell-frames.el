;;; emacsvox-agent-shell-frames.el --- Agent Shell speech subscriptions -*- lexical-binding: t; -*-

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

;; Process Agent Shell events once. Deliver their spoken results to the
;; subscribed frames using each transport's workers and focus policy.
;;; Code:

(require 'emacsvox-frame-speech)
(require 'map)
(require 'tts-queue-state)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar emacsvox-agent-shell--question-command-active)
(declare-function emacsvox-agent-shell--speech-level-at-least-p "emacsvox-agent-shell-presentation" (level &optional buffer))
(declare-function tts-stop "tts-speak" (&optional all))
(declare-function tts-notify-process "tts-speak" ())
(declare-function emacsvox-agent-shell--viewport-session-buffer "emacsvox-agent-shell-presentation" (buffer))

(defvar-local emacsvox-agent-shell--speech-subscribers nil)
(defvar emacsvox-agent-shell--speech-audience nil)
(defvar emacsvox-agent-shell--permission-key nil)
(defvar emacsvox-agent-shell--notification-focus nil)
(defvar emacsvox-agent-shell--frame-hooks-installed nil)
(defvar emacsvox-agent-shell-frame-permission-functions nil
  "Transport functions called with FRAME, request KEY and spoken TEXT.
A non-nil return means the transport owns playback. A nil TEXT resolves KEY.")

(defun emacsvox-agent-shell--subscribers (&optional buffer)
  ;; Capture the current handle for this delivery. An offline subscriber
  ;; still has a private destination. Its expired handle discards speech.
  (cl-loop for frame in (buffer-local-value 'emacsvox-agent-shell--speech-subscribers
                                             (or buffer (current-buffer)))
           when (frame-live-p frame) collect (cons frame (emacsvox-frame-speech-endpoint frame))))

(defun emacsvox-agent-shell--each-destination (audience deliver)
  (let ((source (current-buffer)) (emacsvox-agent-shell--speech-audience nil) seen)
    (dolist (entry audience)
      (let ((frame (car entry)) (endpoint (cdr entry)))
        (when (and (frame-live-p frame) (buffer-live-p source)
                   (eq endpoint (emacsvox-frame-speech-endpoint frame)))
          (condition-case err
              (with-selected-frame frame
                (with-current-buffer source
                  (save-excursion
                    (emacsvox-frame-speech-call
                     endpoint
                     (lambda ()
                       (let ((lanes (cons tts-speaker-process tts-notify-process)))
                         (unless (member lanes seen)
                           (push lanes seen)
                           (funcall deliver frame))))))))
            ;; A disconnected transport must not abort the ACP event or silence
            ;; another subscriber. Keep the utterance out of diagnostics.
            (error (message "Agent Shell frame speech failed (%s)" (car err)))))))))

(defun emacsvox-agent-shell--frame-feedback (original &rest args)
  (if emacsvox-agent-shell--speech-audience
      (emacsvox-agent-shell--each-destination emacsvox-agent-shell--speech-audience
       (lambda (_frame) (apply original args)))
    (apply original args)))

(defun emacsvox-agent-shell--frame-notification (original text facts &rest args)
  (if (not emacsvox-agent-shell--speech-audience)
      (apply original text facts args)
    (emacsvox-agent-shell--each-destination
     emacsvox-agent-shell--speech-audience
     (lambda (_frame)
       (when (or (not (eq 'agent-tool (plist-get facts :role)))
                 (emacsvox-agent-shell--speech-level-at-least-p 'full))
         (apply original text facts args))))))

(defun emacsvox-agent-shell--frame-tool-update (original event)
  ;; The upstream renderer can finish processing this event after emit-event returns.
  (let ((emacsvox-agent-shell--speech-audience (emacsvox-agent-shell--subscribers)))
    (funcall original event)))

(defun emacsvox-agent-shell--frame-announcement (original facts occasion icon text &optional policy)
  (if (not emacsvox-agent-shell--speech-audience)
      (funcall original facts occasion icon text policy)
    (emacsvox-agent-shell--each-destination emacsvox-agent-shell--speech-audience
     (lambda (frame)
       (let* ((urgent (and emacsvox-agent-shell--permission-key (eq policy 'urgent)
                           (memq 'agent-permission-requested (plist-get facts :events))))
              (notify (and urgent (tts-notify-process)))
              (distinct (and notify (not (eq notify tts-speaker-process)))))
         (unless (and urgent (run-hook-with-args-until-success
                              'emacsvox-agent-shell-frame-permission-functions
                              frame emacsvox-agent-shell--permission-key text))
           (let ((emacsvox-agent-shell--notification-focus distinct))
             (funcall original facts occasion icon text policy))
           (when distinct
             (process-put notify 'emacsvox-frame-permission
                          (list (current-buffer) emacsvox-agent-shell--permission-key
                                (tts-queue--state-serial (tts-queue--state notify)))))))))))

(defun emacsvox-agent-shell--resolve-frame-permission (frame key)
  (unless (run-hook-with-args-until-success
           'emacsvox-agent-shell-frame-permission-functions frame key nil)
    (when-let* ((notify (tts-notify-process))
                (request (process-get notify 'emacsvox-frame-permission))
                ((eq (car request) (current-buffer)))
                ((equal (nth 1 request) key)))
      (process-put notify 'emacsvox-frame-permission nil)
      ;; Intervening sound on the same worker is owned by its later submission.
      (when (equal (nth 2 request) (tts-queue--state-serial (tts-queue--state notify)))
        (let ((tts-speaker-process notify)) (tts-stop))))))

(defun emacsvox-agent-shell--protected-frame-stop (original &optional all)
  (interactive (list t))
  (let* ((notify (and all (tts-notify-process)))
         (request (and notify (process-get notify 'emacsvox-frame-permission))))
    (cond
     ;; Navigation uses the 'all symbol for its incidental stop. Only
     ;; protect the notification that actually carries the current request.
     ((and request (eq all 'all)
           (equal (nth 2 request) (tts-queue--state-serial (tts-queue--state notify))))
      (funcall original nil))
     (t
      (when request (process-put notify 'emacsvox-frame-permission nil))
      (funcall original all)))))

(defun emacsvox-agent-shell--frame-event (original &rest args)
  (let* ((event (plist-get args :event)) (data (plist-get args :data))
         (owned (or (eq event 'input-submitted)
                    (and (eq event 'elicitation-response)
                         (bound-and-true-p emacsvox-agent-shell--question-command-active))))
         (emacsvox-frame-speech--command-owner
          (or (and owned (emacsvox-frame-speech--origin)) 'desktop))
         (emacsvox-agent-shell--speech-audience (unless owned (emacsvox-agent-shell--subscribers)))
         (key (or (map-elt data :request-id) (map-elt data :tool-call-id)))
         (emacsvox-agent-shell--permission-key (and (eq event 'permission-request) key)))
    (when (and key (eq event 'permission-response))
      (emacsvox-agent-shell--each-destination emacsvox-agent-shell--speech-audience
       (lambda (frame) (emacsvox-agent-shell--resolve-frame-permission frame key))))
    (apply original args)))

(defun emacsvox-agent-shell--frame-deferred (original buffer &rest args)
  (when (buffer-live-p buffer)
    (let ((emacsvox-frame-speech--command-owner 'desktop)
          (emacsvox-agent-shell--speech-audience (emacsvox-agent-shell--subscribers buffer)))
      (apply original buffer args))))

(defun emacsvox-agent-shell--frame-out-of-turn-receiver (original)
  (let ((deliver (funcall original))
        (audience (emacsvox-agent-shell--subscribers)))
    (lambda (body)
      (if audience
          (emacsvox-agent-shell--each-destination
           audience (lambda (frame)
                      (when (memq frame emacsvox-agent-shell--speech-subscribers)
                        (funcall deliver body))))
        (emacsvox-frame-speech-call nil deliver body)))))

(defun emacsvox-agent-shell--frame-focused (original &optional buffer)
  (cond
   (emacsvox-agent-shell--notification-focus nil)
   (emacsvox-agent-shell--speech-audience
    (let ((source (or buffer (current-buffer))))
      (seq-some (lambda (entry)
                  (and (frame-live-p (car entry))
                       (with-selected-frame (car entry) (funcall original source))))
                emacsvox-agent-shell--speech-audience)))
   (t (funcall original buffer))))

(defun emacsvox-agent-shell--frame-steering (original &rest args)
  (when (equal (map-elt (plist-get args :request) :method) "_session/steering")
    (let ((origin (or (emacsvox-frame-speech--origin) 'desktop)))
      (setq args (copy-sequence args))
      (dolist (key '(:on-success :on-failure))
        (when-let* ((callback (plist-get args key)))
          (setq args (plist-put args key (lambda (&rest result)
                                          (apply #'emacsvox-frame-speech--with-origin origin callback result))))))))
  (apply original args))

(defconst emacsvox-agent-shell--frame-advice
  '((agent-shell--emit-event emacsvox-agent-shell--frame-event)
    (agent-shell--send-request emacsvox-agent-shell--frame-steering 50)
    (emacsvox-agent-shell--deliver-announcement emacsvox-agent-shell--frame-announcement)
    (emacsvox-agent-shell--session-focused-p emacsvox-agent-shell--frame-focused)
    (emacsvox-agent-shell--deliver-pending-blocks emacsvox-agent-shell--frame-deferred)
    (emacsvox-agent-shell--out-of-turn-receiver emacsvox-agent-shell--frame-out-of-turn-receiver)
    (emacsvox-agent-shell--speak-rendered-blocks emacsvox-agent-shell--frame-feedback)
    (emacsvox-agent-shell--speak-content emacsvox-agent-shell--frame-feedback)
    (emacsvox-agent-shell--speak-turn-completion emacsvox-agent-shell--frame-feedback)
    (emacsvox-agent-shell--question-event emacsvox-agent-shell--frame-feedback)
    (emacsvox-agent-shell--present-tool-update emacsvox-agent-shell--frame-tool-update)
    (emacsvox-agent-shell--notify-event emacsvox-agent-shell--frame-notification)
    (emacsvox-agent-shell--submit-icon-feedback emacsvox-agent-shell--frame-feedback)
    (tts-stop emacsvox-agent-shell--protected-frame-stop 10)))

(defun emacsvox-agent-shell--frame-hooks (enable)
  (unless (eq enable emacsvox-agent-shell--frame-hooks-installed)
    (setq emacsvox-agent-shell--frame-hooks-installed enable)
    (dolist (entry emacsvox-agent-shell--frame-advice)
      (if enable (advice-add (car entry) :around (nth 1 entry) (and (nth 2 entry) (list (cons 'depth (nth 2 entry)))))
        (advice-remove (car entry) (nth 1 entry))))
    (dolist (hook '(delete-frame-functions emacsvox-frame-speech-detach-hook))
      (if enable (add-hook hook #'emacsvox-agent-shell--forget-frame)
        (remove-hook hook #'emacsvox-agent-shell--forget-frame)))))

(defun emacsvox-agent-shell--subscription-buffer ()
  (cond ((derived-mode-p 'agent-shell-mode) (current-buffer))
        ((derived-mode-p 'agent-shell-viewport-view-mode 'agent-shell-viewport-edit-mode)
         (emacsvox-agent-shell--viewport-session-buffer (current-buffer)))))

;;;###autoload
(defun emacsvox-agent-shell-subscribe-frame (&optional buffer frame)
  "Send Agent Shell replies and permissions for BUFFER to FRAME.
Interactively, use this conversation and the selected frame. Each subscribed
speech destination receives one announcement. Editing feedback follows the
frame that acted."
  (interactive)
  (setq frame (or frame (selected-frame)) buffer (or buffer (emacsvox-agent-shell--subscription-buffer)))
  (unless (and (frame-live-p frame) (buffer-live-p buffer)
               (with-current-buffer buffer (derived-mode-p 'agent-shell-mode)))
    (user-error "Select a live Agent Shell conversation and frame"))
  (with-current-buffer buffer
    (cl-pushnew frame emacsvox-agent-shell--speech-subscribers)
    (add-hook 'kill-buffer-hook #'emacsvox-agent-shell--forget-buffer nil t))
  (set-frame-parameter frame 'emacsvox-agent-shell-buffers
                       (cons buffer (delq buffer (frame-parameter frame 'emacsvox-agent-shell-buffers))))
  (emacsvox-agent-shell--frame-hooks t)
  (when (called-interactively-p 'interactive) (message "Subscribed to %s" (buffer-name buffer))))

;;;###autoload
(defun emacsvox-agent-shell-unsubscribe-frame (&optional buffer frame)
  "End this FRAME's subscription to Agent Shell BUFFER.
Interactively, use the current conversation and the selected frame."
  (interactive)
  (setq frame (or frame (selected-frame)) buffer (or buffer (emacsvox-agent-shell--subscription-buffer)))
  (when (and (frame-live-p frame) (buffer-live-p buffer))
    (with-current-buffer buffer
      (when (memq frame emacsvox-agent-shell--speech-subscribers)
        (emacsvox-frame-speech-call
         (emacsvox-frame-speech-endpoint frame)
         (lambda ()
           (when-let* ((notify (tts-notify-process))
                       (request (process-get notify 'emacsvox-frame-permission))
                       ((eq buffer (car request))))
             (emacsvox-agent-shell--resolve-frame-permission frame (nth 1 request))))))
      (setq emacsvox-agent-shell--speech-subscribers (delq frame emacsvox-agent-shell--speech-subscribers))
      (unless emacsvox-agent-shell--speech-subscribers
        (remove-hook 'kill-buffer-hook #'emacsvox-agent-shell--forget-buffer t)))
    (set-frame-parameter frame 'emacsvox-agent-shell-buffers
                         (delq buffer (frame-parameter frame 'emacsvox-agent-shell-buffers)))
    (unless (seq-some (lambda (f) (frame-parameter f 'emacsvox-agent-shell-buffers)) (frame-list))
      (emacsvox-agent-shell--frame-hooks nil)))
  (when (called-interactively-p 'interactive) (message "Subscription ended")))

(defun emacsvox-agent-shell--forget-frame (frame)
  (dolist (buffer (frame-parameter frame 'emacsvox-agent-shell-buffers))
    (emacsvox-agent-shell-unsubscribe-frame buffer frame)))

(defun emacsvox-agent-shell--forget-buffer ()
  (dolist (frame (copy-sequence emacsvox-agent-shell--speech-subscribers))
    (emacsvox-agent-shell-unsubscribe-frame (current-buffer) frame)))

(provide 'emacsvox-agent-shell-frames)
;;; emacsvox-agent-shell-frames.el ends here
