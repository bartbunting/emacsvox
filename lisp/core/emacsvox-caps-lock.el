;;; emacsvox-caps-lock.el --- Speak keyboard Caps Lock changes -*- lexical-binding: t; -*-

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
;; Read the X11 Caps Lock indicator asynchronously with the optional xset
;; utility.  An optional Python/XKB helper also observes modifier presses.
;; Observe state rather than guessing from key events, which other accessibility
;; tools may intercept.  Loading this module starts no watcher.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural-submission)
(defvar emacsvox-etc-directory)

(defgroup emacsvox-caps-lock nil
  "Keyboard Caps Lock announcements and reminders."
  :group 'emacsvox)

(defcustom emacsvox-caps-lock-reminder-presentation 'tone
  "How keyboard input reminds you that Caps Lock is on.
`tone' plays the editable reminder tone without stopping main speech.
`spoken' says Caps Lock after ordinary key feedback, or immediately for a
modifier press.  This global choice requires `emacsvox-caps-lock-mode'.
State-change and focus-entry announcements remain spoken in both cases."
  :type '(choice (const :tag "Tone" tone) (const :tag "Speech" spoken))
  :group 'emacsvox-caps-lock)

(defun emacsvox-caps-lock--tone-action (values)
  "Build a reminder tone action from global or private preview VALUES."
  (append (list :id 'caps-lock-reminder-tone :kind 'tone :audio-mode 'overlay)
          (copy-tree values)))

(defcustom emacsvox-caps-lock-reminder-tone
  '(:pitch 160 :duration 400 :volume 0.30
    :shape (:waveform triangle
            :envelope (:attack-ms 5 :decay-ms 20 :sustain-level 0.4 :release-ms 45)))
  "Tone played for keyboard input while Caps Lock is on.
Pitch is in Hz, duration in milliseconds and volume is a gain from 0 to 1.
Shape describes waveform, optional pitch sweep and envelope.  Use the Caps
Lock reminder tone editor to preview and adjust these global defaults.
This applies only to the tone reminder, with `emacsvox-caps-lock-mode' enabled;
editing or saving it does not enable the mode or change the presentation."
  :type '(plist :options ((:pitch number) (:duration number)
                         (:volume number) (:shape plist)))
  :set (lambda (symbol value)
         (emacsvox-aural--compile-action
          (emacsvox-caps-lock--tone-action value) 'caps-lock-reminder 'before 0 'run)
         (set-default symbol (copy-tree value)))
  :group 'emacsvox-caps-lock)

(defvar emacsvox-caps-lock-mode nil)
(defvar emacsvox-caps-lock--timer nil)
(defvar emacsvox-caps-lock--deadline nil)
(defvar emacsvox-caps-lock--process nil)
(defvar emacsvox-caps-lock--program nil)
(defvar emacsvox-caps-lock--display nil)
(defvar emacsvox-caps-lock--focus-pending nil)
(defvar emacsvox-caps-lock--reminder-pending nil)
(defvar emacsvox-caps-lock--input-count 0)
(defvar emacsvox-caps-lock--modifier-program nil)
(defvar emacsvox-caps-lock--modifier-process nil)
(defvar emacsvox-caps-lock--modifier-deadline nil)
(defvar emacsvox-caps-lock--modifier-retry-at 0)
(defvar emacsvox-caps-lock--modifier-error nil
  "Most recent optional modifier helper failure, or nil when ready.")
(defvar emacsvox-caps-lock--states (make-hash-table :test #'equal))
(defvar emacsvox-caps-lock--retry-at 0)
(defvar emacsvox-caps-lock--last-error nil
  "Most recent indicator query failure, or nil after a successful query.
Failed queries leave the last known state intact and retry after five seconds.")

(defun emacsvox-caps-lock--focused-display ()
  "Return the display of an X11 frame with confirmed input focus."
  (cl-loop for frame in (frame-list)
           when (and (eq (window-system frame) 'x)
                     (eq (frame-focus-state frame) t))
           return (frame-parameter frame 'display)))

(defun emacsvox-caps-lock--parse (output)
  "Return `on' or `off' for the named Caps Lock indicator in OUTPUT.
Return nil for an unavailable or unrecognised indicator.  Do not infer state
from a fixed LED bit: keyboard configurations can use different mappings."
  (let ((case-fold-search nil))
    (when (string-match "\\bCaps Lock:[ \t]+\\(on\\|off\\)\\b" output)
      (if (equal (match-string 1 output) "on") 'on 'off))))

(defun emacsvox-caps-lock--cancel-query ()
  "Dispose of the current query and reject any late completion."
  (let ((process emacsvox-caps-lock--process))
    (setq emacsvox-caps-lock--process nil)
    (when (timerp emacsvox-caps-lock--deadline)
      (cancel-timer emacsvox-caps-lock--deadline))
    (setq emacsvox-caps-lock--deadline nil)
    (when (processp process)
      (let ((buffer (process-buffer process)))
        (set-process-sentinel process #'ignore)
        (delete-process process)
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(defun emacsvox-caps-lock--failed (reason)
  "Record REASON and defer another query without inventing a lock state."
  (setq emacsvox-caps-lock--last-error reason
        emacsvox-caps-lock--reminder-pending nil
        emacsvox-caps-lock--retry-at (+ (float-time) 5)))

(defun emacsvox-caps-lock--accept (display state &optional modifier-press)
  "Record STATE for focused DISPLAY and deliver current keyboard feedback.
MODIFIER-PRESS requests immediate feedback before any command key is entered."
  (when (and emacsvox-caps-lock-mode
             (equal display (emacsvox-caps-lock--focused-display)))
    (let* ((previous (gethash display emacsvox-caps-lock--states 'unknown))
           (announce (if emacsvox-caps-lock--focus-pending
                         (eq state 'on)
                       (not (memq previous (list 'unknown state))))))
      (puthash display state emacsvox-caps-lock--states)
      (setq emacsvox-caps-lock--last-error nil
            emacsvox-caps-lock--retry-at 0)
      ;; Returning always warns when on, even if unchanged.  Returning with
      ;; Caps Lock off is quiet, including when it was turned off elsewhere.
      (cond
       (announce
        (emacsvox-aural-submit
         (if (eq state 'on) "Caps Lock on" "Caps Lock off")
         :module 'caps-lock :occasion 'state-change :lane 'main
         :delivery-policy 'replaceable :replacement-key 'caps-lock-state
         :interruption-policy 'lane))
       ((and (eq state 'on) emacsvox-caps-lock--reminder-pending)
        (emacsvox-caps-lock--remind modifier-press)))
      (setq emacsvox-caps-lock--focus-pending nil
            emacsvox-caps-lock--reminder-pending nil))))

(defun emacsvox-caps-lock--tone-context ()
  "Capture a private reminder context with the current tone defaults."
  (let* ((context (emacsvox-aural-capture-context 'caps-lock 'inspection))
         (rule (list :id 'caps-lock-reminder
                     :match '(:module caps-lock :occasion inspection)
                     :render (list :before
                                   (list :append
                                         (list (emacsvox-caps-lock--tone-action
                                                emacsvox-caps-lock-reminder-tone)))))))
    (plist-put context :buffer-rules
               (append (plist-get context :buffer-rules) (list rule)))))

(defun emacsvox-caps-lock--remind (&optional immediate)
  "Deliver the chosen reminder; IMMEDIATE applies to spoken modifier feedback.
The tone overlays current speech.  Spoken ordinary-key reminders follow
normal key feedback, while spoken modifier reminders interrupt older speech."
  (if (eq emacsvox-caps-lock-reminder-presentation 'spoken)
      (emacsvox-aural-submit
       "Caps Lock" :module 'caps-lock :occasion 'inspection :lane 'main
       :delivery-policy 'replaceable :replacement-key 'caps-lock-reminder
       :interruption-policy (if immediate 'lane 'none))
    (emacsvox-aural-submit-actions
     :context (emacsvox-caps-lock--tone-context)
     :module 'caps-lock :occasion 'inspection :lane 'main
     ;; Tone-only output uses compatibility delivery.  Its replaceable path
     ;; hard-stops the worker even with interruption `none'.  Ordered delivery
     ;; sends the overlay immediately and preserves speech already playing.
     :delivery-policy 'ordered
     :interruption-policy 'none)))

(defun emacsvox-caps-lock--observe-input ()
  "Notice fresh keyboard input, including a prefix awaiting another key.
Coalesce input already superseded by later typing.  Mouse, focus and macro
events do not produce reminders; an explicit speech stop remains silent."
  (unless (= emacsvox-caps-lock--input-count num-nonmacro-input-events)
    (setq emacsvox-caps-lock--input-count num-nonmacro-input-events
          emacsvox-caps-lock--reminder-pending nil)
    ;; Invalidate older input, including when the new command stops speech.
    (emacsvox-caps-lock--cancel-query)
    (when (and (not executing-kbd-macro)
               (not (memq this-command '(tts-stop keyboard-quit)))
               (or (integerp last-input-event)
                   (and last-input-event (symbolp last-input-event)
                        (not (cl-intersection
                              '(click down drag double triple)
                              (event-modifiers last-input-event)))
                        (not (get last-input-event 'event-kind))
                        (not (memq last-input-event '(help-echo menu-bar tool-bar))))))
      ;; A query started before the key may describe an earlier lock state.
      (setq emacsvox-caps-lock--reminder-pending t))))

(defun emacsvox-caps-lock--stop-modifiers ()
  "Stop the optional helper and invalidate its pending output."
  (let ((process emacsvox-caps-lock--modifier-process))
    (setq emacsvox-caps-lock--modifier-process nil)
    (when (timerp emacsvox-caps-lock--modifier-deadline)
      (cancel-timer emacsvox-caps-lock--modifier-deadline))
    (setq emacsvox-caps-lock--modifier-deadline nil)
    (when (processp process)
      (set-process-sentinel process #'ignore)
      (set-process-filter process #'ignore)
      (delete-process process))))

(defun emacsvox-caps-lock--modifier-failed (reason)
  "Stop the helper after REASON and delay another attempt."
  (emacsvox-caps-lock--stop-modifiers)
  (setq emacsvox-caps-lock--modifier-error reason
        emacsvox-caps-lock--modifier-retry-at (+ (float-time) 5)))

(defun emacsvox-caps-lock--modifier-filter (process output)
  "Read complete, bounded helper records from PROCESS and OUTPUT."
  (when (eq process emacsvox-caps-lock--modifier-process)
    (let* ((text (concat (process-get process 'partial) output))
           (lines (split-string text "\n"))
           (partial (car (last lines))))
      (process-put process 'partial partial)
      (if (> (length partial) 128)
          (emacsvox-caps-lock--modifier-failed "Invalid modifier helper output")
        (dolist (line (butlast lines))
          (when (eq process emacsvox-caps-lock--modifier-process)
            (pcase line
              ("ready"
               (when (timerp emacsvox-caps-lock--modifier-deadline)
                 (cancel-timer emacsvox-caps-lock--modifier-deadline))
               (setq emacsvox-caps-lock--modifier-deadline nil
                     emacsvox-caps-lock--modifier-error nil))
              ("modifier"
               (when (and emacsvox-caps-lock-mode
                          (equal (process-get process 'display)
                                 (emacsvox-caps-lock--focused-display)))
                 ;; The helper checks the real indicator for this press.
                 (emacsvox-caps-lock--cancel-query)
                 (setq emacsvox-caps-lock--reminder-pending t)
                 (emacsvox-caps-lock--accept (process-get process 'display) 'on t)))
              (_ (emacsvox-caps-lock--modifier-failed
                  "Modifier helper unavailable; ordinary-key reminders remain active")))))))))

(defun emacsvox-caps-lock--modifier-finished (process _event)
  "Retire a failed or exited modifier PROCESS."
  (when (and (eq process emacsvox-caps-lock--modifier-process)
             (memq (process-status process) '(exit signal failed)))
    (emacsvox-caps-lock--modifier-failed "Modifier helper stopped")))

(defun emacsvox-caps-lock--modifier-timeout (process)
  "Stop PROCESS if its readiness report has not arrived."
  (when (eq process emacsvox-caps-lock--modifier-process)
    (emacsvox-caps-lock--modifier-failed "Modifier helper startup timed out")))

(defun emacsvox-caps-lock--start-modifiers (display)
  "Start the optional modifier observer for DISPLAY when available."
  (when (and emacsvox-caps-lock--modifier-program
             (not emacsvox-caps-lock--modifier-process)
             (>= (float-time) emacsvox-caps-lock--modifier-retry-at))
    (let ((default-directory "/"))
      (condition-case err
          (let ((process
                 (make-process
                  :name "emacsvox-caps-lock-modifiers" :noquery t
                  :connection-type 'pipe :coding 'utf-8-unix
                  :command (list emacsvox-caps-lock--modifier-program "-u"
                                 (expand-file-name "emacsvox-caps-lock-watch.py"
                                                   emacsvox-etc-directory)
                                 display)
                  :filter #'emacsvox-caps-lock--modifier-filter
                  :sentinel #'emacsvox-caps-lock--modifier-finished)))
            (setq emacsvox-caps-lock--modifier-process process)
            (process-put process 'display display)
            (setq emacsvox-caps-lock--modifier-deadline
                  (run-at-time 2 nil #'emacsvox-caps-lock--modifier-timeout process)))
        (error (emacsvox-caps-lock--modifier-failed (error-message-string err)))))))

(defun emacsvox-caps-lock--finished (process _event)
  "Accept a completed indicator PROCESS if it is still the current query."
  (when (and (eq process emacsvox-caps-lock--process)
             (memq (process-status process) '(exit signal failed)))
    (let* ((display emacsvox-caps-lock--display)
           (state (and (eq (process-status process) 'exit)
                       (zerop (process-exit-status process))
                       (buffer-live-p (process-buffer process))
                       (with-current-buffer (process-buffer process)
                         (emacsvox-caps-lock--parse (buffer-string))))))
      (emacsvox-caps-lock--cancel-query)
      (if state (emacsvox-caps-lock--accept display state)
        (emacsvox-caps-lock--failed "xset did not report the Caps Lock indicator")))))

(defun emacsvox-caps-lock--timeout (process)
  "Stop a stalled indicator PROCESS if it still owns the query."
  (when (eq process emacsvox-caps-lock--process)
    (emacsvox-caps-lock--cancel-query)
    (emacsvox-caps-lock--failed "Caps Lock indicator query timed out")))

(defun emacsvox-caps-lock--query (display)
  "Start one bounded, asynchronous indicator query for DISPLAY."
  (let ((buffer (generate-new-buffer " *Emacsvox Caps Lock*"))
        ;; Keyboard state belongs to the local display, even in a remote
        ;; buffer or a buffer whose working directory has been removed.
        (default-directory "/")
        (process-environment (copy-sequence process-environment)))
    (setenv "LC_ALL" "C")
    (condition-case error-data
        (progn
          (setq emacsvox-caps-lock--process
                (make-process
                 :name "emacsvox-caps-lock" :buffer buffer :noquery t
                 :connection-type 'pipe :coding 'utf-8-unix
                 :command (list emacsvox-caps-lock--program "-display" display "-q")
                 :sentinel #'emacsvox-caps-lock--finished))
          (setq emacsvox-caps-lock--deadline
                (run-at-time 1 nil #'emacsvox-caps-lock--timeout
                             emacsvox-caps-lock--process)))
      (error
       (emacsvox-caps-lock--cancel-query)
       (when (buffer-live-p buffer) (kill-buffer buffer))
       (emacsvox-caps-lock--failed (error-message-string error-data))))))

(defun emacsvox-caps-lock--poll ()
  "Check the focused X11 display without blocking keyboard interaction."
  (when emacsvox-caps-lock-mode
    (let ((display (emacsvox-caps-lock--focused-display)))
      (unless (equal display emacsvox-caps-lock--display)
        (emacsvox-caps-lock--cancel-query)
        (emacsvox-caps-lock--stop-modifiers)
        (setq emacsvox-caps-lock--display display
              emacsvox-caps-lock--retry-at 0
              emacsvox-caps-lock--modifier-retry-at 0
              emacsvox-caps-lock--focus-pending (not (null display))
              emacsvox-caps-lock--reminder-pending nil
              emacsvox-caps-lock--input-count num-nonmacro-input-events))
      (when display
        (emacsvox-caps-lock--observe-input)
        (emacsvox-caps-lock--start-modifiers display))
      (when (and display (not emacsvox-caps-lock--process)
                 (>= (float-time) emacsvox-caps-lock--retry-at))
        (emacsvox-caps-lock--query display)))))

(defun emacsvox-caps-lock--stop ()
  "Remove the watcher, pending query and focus observer."
  (when (timerp emacsvox-caps-lock--timer)
    (cancel-timer emacsvox-caps-lock--timer))
  (setq emacsvox-caps-lock--timer nil
        emacsvox-caps-lock--display nil
        emacsvox-caps-lock--focus-pending nil
        emacsvox-caps-lock--reminder-pending nil)
  (emacsvox-caps-lock--cancel-query)
  (emacsvox-caps-lock--stop-modifiers)
  (remove-function after-focus-change-function #'emacsvox-caps-lock--poll)
  (remove-hook 'post-command-hook #'emacsvox-caps-lock--poll)
  (remove-hook 'kill-emacs-hook #'emacsvox-caps-lock--stop))

;;;###autoload
(define-minor-mode emacsvox-caps-lock-mode
  "Announce keyboard Caps Lock changes while an X11 Emacs frame has focus.
This global option requires the xset program.  It supports X11, including
WSLg's X display; native Wayland, Windows, macOS and terminal frames are unsupported.
The desktop must expose its current Caps Lock indicator to X11.

Say \"Caps Lock on\" or \"Caps Lock off\" on the main speech stream when
the reported state changes.  Ordinary reading can interrupt this feedback.
On gaining focus, announce \"Caps Lock on\" whenever it is on; stay quiet
if it is off.  While it is on, keyboard input also plays a brief tone without
stopping current speech.  Choose tone or speech with
`emacsvox-caps-lock-reminder-presentation'; edit the tone through the Caps Lock
reminder settings.  Spoken reminders say \"Caps Lock\" after normal key
feedback.  Fast typing can replace reminders.
Modifier presses alone also trigger the reminder when Python 3 and libX11
are available and the desktop delivers the modifier change.  The spoken
choice interrupts older main speech promptly; releases do not remind.
Enabling while focused checks the current state in the same way as entry.
Changes are sampled every 0.2 seconds, so a very rapid pair of toggles can
be missed.  No key bindings or keyboard settings are changed.

Enabling or disabling lasts for this session.  Save this option through
Customize or the settings menu to retain it across restarts."
  :global t :group 'emacsvox-caps-lock :init-value nil
  (emacsvox-caps-lock--stop)
  (clrhash emacsvox-caps-lock--states)
  (setq emacsvox-caps-lock--retry-at 0
        emacsvox-caps-lock--modifier-retry-at 0
        emacsvox-caps-lock--modifier-error nil
        emacsvox-caps-lock--input-count num-nonmacro-input-events
        emacsvox-caps-lock--last-error nil)
  (when emacsvox-caps-lock-mode
    (setq emacsvox-caps-lock--program (executable-find "xset"))
    (unless emacsvox-caps-lock--program
      (setq emacsvox-caps-lock-mode nil)
      (user-error "Caps Lock announcements require xset and an X11 Emacs frame"))
    (setq emacsvox-caps-lock--modifier-program (executable-find "python3"))
    (add-function :after after-focus-change-function #'emacsvox-caps-lock--poll)
    (add-hook 'post-command-hook #'emacsvox-caps-lock--poll 90)
    (add-hook 'kill-emacs-hook #'emacsvox-caps-lock--stop)
    (setq emacsvox-caps-lock--timer
          (run-at-time 0 0.2 #'emacsvox-caps-lock--poll))))

(provide 'emacsvox-caps-lock)
;;; emacsvox-caps-lock.el ends here
