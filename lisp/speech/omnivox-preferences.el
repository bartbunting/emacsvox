;;; omnivox-preferences.el --- Independent host preference reload -*- lexical-binding: t; -*-

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
;; Reload each local owned worker independently over its existing connection.
;; A deadline reports an unknown outcome; it never rolls back or replays work.
;;; Code:
(require 'cl-lib)
(require 'omnivox-voices)
(require 'omnivox-punctuation-profiles)

(defvar omnivox-preferences-last-result nil
  "Latest independent host reload results, with role, outcome and state.")

(defun omnivox-preferences--state-p (state)
  "Whether STATE contains the required live policy and operation identities."
  (and (stringp (plist-get state :incarnation))
       (stringp (plist-get state :configuration_file))
       (integerp (plist-get state :revision))
       (<= 0 (plist-get state :revision) #xffffffffffffffff)
       (stringp (plist-get state :punctuation_sha256))
       (let ((operation (plist-get state :last_operation)))
         (or (null operation)
             (and (integerp (plist-get operation :sequence))
                  (<= 1 (plist-get operation :sequence) #xffffffffffffffff)
                  (member (plist-get operation :outcome)
                          '("preparing" "pending" "applied" "unchanged" "rejected")))))))

(defun omnivox-preferences--reload-worker (process role expected-file callback &optional scope)
  "Reload PROCESS for ROLE, checking EXPECTED-FILE when non-nil.
Call CALLBACK once with an independent result.  Never wait for another worker.
SCOPE is `host' for all host preferences, or nil for punctuation only."
  (let ((identity (list 'reload)) (deadline (+ (float-time) 3))
        (request-type (if (eq scope 'host) "reload_host_preferences_v1" "reload_punctuation_v1"))
        (feature (if (eq scope 'host) "host_preferences_reload_v1" "host_preferences_v1"))
        done timer incarnation sequence)
    (cl-labels
        ((finish (outcome &optional state reason)
           (unless done
             (setq done t)
             (when (timerp timer) (cancel-timer timer))
             (when (and (processp process)
                        (eq identity (process-get process 'omnivox-preference-operation)))
               (process-put process 'omnivox-preference-operation nil))
             (when state (process-put process 'omnivox-preference-state state))
             (when (member outcome '("applied" "unchanged"))
               (condition-case nil
                   (omnivox--send-control-request
                    process '(:type "get_punctuation_profiles_v1")
                    #'omnivox-punctuation-profiles--receive 1)
                 (error nil)))
             (funcall callback (list :role role :process process :outcome outcome
                                     :state state :reason reason))))
         (send (request receiver)
           (condition-case error-data
               (omnivox--send-control-request process request receiver
                                              (max 0.01 (min 0.5 (- deadline (float-time)))))
             (error (finish "unknown" nil (error-message-string error-data)))))
         (poll ()
           (cond (done nil)
                 ((or (not (process-live-p process))
                      (process-get process 'tts--speech-process-retiring))
                  (finish "unavailable"))
                 ((>= (float-time) deadline) (finish "unknown" nil "Reload may still finish; query live status"))
                 (t (send '(:type "host_preferences_status_v1") #'observe))))
         (observe (_owner response)
           (unless done
             (let* ((state (if (equal (plist-get response :type) request-type)
                               (plist-get response :state) response))
                    (operation (plist-get state :last_operation)))
               (cond
                ((not (omnivox-preferences--state-p state))
                 (if (>= (float-time) deadline) (finish "unknown")
                   (setq timer (run-at-time 0.025 nil #'poll))))
                ((or (not (equal incarnation (plist-get state :incarnation)))
                     (not (eql sequence (plist-get operation :sequence)))
                     (and (or scope (plist-get operation :scope))
                          (not (equal (plist-get operation :scope)
                                      (if (eq scope 'host) "host" "punctuation")))))
                 (finish "stale" state "Worker or operation changed; nothing replayed"))
                ((member (plist-get operation :outcome) '("preparing" "pending"))
                 (setq timer (run-at-time 0.025 nil #'poll)))
                (t (finish (plist-get operation :outcome) state
                           (plist-get operation :reason)))))))
         (start (_owner state)
           (unless done
             (cond
              ((not (and (equal (plist-get state :type) "host_preferences_status_v1")
                         (omnivox-preferences--state-p state)))
               (finish "unknown" nil "Could not read live preferences"))
              ((and expected-file (not (equal expected-file (plist-get state :configuration_file))))
               (finish "rejected" state "Worker uses a different saved configuration; restart explicitly"))
              ((member (plist-get (plist-get state :last_operation) :outcome) '("preparing" "pending"))
               (finish "busy" state "An earlier reload is still pending"))
              (t
               (setq incarnation (plist-get state :incarnation)
                     sequence (1+ (or (plist-get (plist-get state :last_operation) :sequence) 0)))
               (if (> sequence #xffffffffffffffff) (finish "rejected" state "Operation IDs exhausted")
                 (send (list :type request-type :incarnation incarnation
                             :sequence sequence :expected_revision (plist-get state :revision))
                       #'observe)))))))
      (cond
       ((not (and (processp process) (process-live-p process))) (finish "unavailable"))
       ((not (omnivox--process-supports-p process feature))
        (finish "unsupported" nil "This worker needs explicit restart"))
       ((process-get process 'omnivox-preference-operation) (finish "busy"))
       (t
        (process-put process 'omnivox-preference-operation identity)
        (send '(:type "host_preferences_status_v1") #'start))))))

(defun omnivox-preferences--summary (results)
  "Describe independent RESULTS without claiming an atomic change."
  (mapconcat (lambda (result)
               (format "%s: %s%s" (plist-get result :role)
                       (or (cdr (assoc (plist-get result :outcome)
                                       '(("applied" . "reloaded") ("unchanged" . "already current")
                                         ("unknown" . "outcome unknown") ("stale" . "superseded")
                                         ("unsupported" . "reload unavailable"))))
                           (plist-get result :outcome))
                       (if-let* ((reason (plist-get result :reason))) (concat " (" reason ")") "")))
             results "; "))

;;;###autoload
(defun omnivox-reload-punctuation (&optional callback expected-file)
  "Reload saved punctuation on each current local owned speech worker.
Keep speaking during preparation.  A failed worker cannot delay installation
on another.  Other host preferences need `omnivox-reload-preferences'.
Temporary voice/rate/profile selections survive; Reset uses the new tables.
Recovery from retained startup may restore older preferences.
CALLBACK receives per-worker results.  EXPECTED-FILE optionally restricts the
operation to workers using the editor's saved file; it is never sent as a path."
  (interactive)
  (omnivox-preferences--reload nil callback expected-file))

;;;###autoload
(defun omnivox-reload-preferences (&optional callback)
  "Reload saved punctuation, capital cues, chunking and Reset defaults.
Each local worker installs independently while speech continues.  Current
client voice, rate, volume and profile choices remain; Reset uses the newly
loaded defaults.  Engine, model, routing and output changes require restart.
Recovery from retained startup may restore older preferences.
CALLBACK receives independent results for the current workers."
  (interactive)
  (omnivox-preferences--reload 'host callback nil))

(defun omnivox-preferences--reload (scope callback expected-file)
  "Reload SCOPE independently, passing results to CALLBACK.
EXPECTED-FILE restricts punctuation editor reload to its saved target."
  (let* ((workers (delete-dups (omnivox-punctuation-profiles--workers)))
         (remaining (length workers)) results)
    (dolist (process workers)
      (omnivox-preferences--reload-worker
       process (if (eq process (car workers)) "Main" "Notifications") expected-file
       (lambda (result)
         (push result results)
         (setq remaining (1- remaining))
         (when (= remaining 0)
           (setq omnivox-preferences-last-result (nreverse results))
           (if callback (funcall callback omnivox-preferences-last-result)
             (message "%s" (omnivox-preferences--summary omnivox-preferences-last-result)))))
       scope))))

;;;###autoload
(defun omnivox-preferences-status ()
  "Query actual live preference state separately for each current worker."
  (interactive)
  (dolist (process (delete-dups (omnivox-punctuation-profiles--workers)))
    (if (and (processp process) (process-live-p process)
             (omnivox--process-supports-p process "host_preferences_v1"))
        (omnivox--send-control-request
         process '(:type "host_preferences_status_v1")
         (lambda (owner state)
           (when (omnivox-preferences--state-p state)
             (process-put owner 'omnivox-preference-state state))
           (if (omnivox-preferences--state-p state)
               (message "%s: preference revision %s, %s; %s"
                        (if (eq owner tts-notify-process) "Notifications" "Main")
                        (plist-get state :revision)
                        (or (plist-get (plist-get state :last_operation) :outcome) "no reload")
                        (if (if (plist-get state :host_preferences_sha256)
                                (equal (plist-get state :host_preferences_sha256)
                                       (plist-get state :startup_host_preferences_sha256))
                              (equal (plist-get state :punctuation_sha256)
                                     (plist-get state :startup_punctuation_sha256)))
                            "matches startup" "changed since startup"))
             (message "Could not read live preferences for %s" (process-name owner)))) 1)
      (message "Preference status unavailable for %s" process))))

(provide 'omnivox-preferences)
;;; omnivox-preferences.el ends here
