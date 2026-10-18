;;; emacsvox-output-settings.el --- Notification and spatial settings -*- lexical-binding: t; -*-

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
;; Global output policy; persistence and speech restart are explicit actions.
;;; Code:
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-spatial)
(require 'emacsvox-aural-preview)

(defconst emacsvox-output-settings--options
  '(tts-notification-device emacsvox-aural-spatial-enabled
    emacsvox-aural-spatial-speech-enabled emacsvox-aural-spatial-cue-enabled
    emacsvox-aural-spatial-output emacsvox-aural-spatial-maximum-separation
    emacsvox-aural-spatial-remapping)
  "Global options saved by this menu.")
(defun emacsvox-output-settings--say (text)
  "Announce replaceable feedback TEXT."
  (emacsvox-transient--submit-text text
   (emacsvox-transient--menu-facts 'output-settings 'command-menu-value-changed)
   'state-change 'select-object))
(defun emacsvox-output-settings--set (symbol value text)
  "Set global SYMBOL to VALUE and announce TEXT without saving."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (customize-set-variable symbol value)
  (emacsvox-output-settings--say text))
(defun emacsvox-output-settings--label (symbol label)
  "Describe global boolean SYMBOL with LABEL."
  (format "%s: %s" label (if (default-value symbol) "on" "off")))
(defun emacsvox-output-settings--toggle (symbol label)
  "Toggle global SYMBOL and describe LABEL."
  (emacsvox-output-settings--set symbol (not (default-value symbol))
                                 (format "%s %s" label (if (default-value symbol) "off" "on"))))
(defun emacsvox-output-settings--enabled ()
  "Toggle spatial presentation." (interactive)
  (emacsvox-output-settings--toggle 'emacsvox-aural-spatial-enabled "Spatial presentation"))
(defun emacsvox-output-settings--speech ()
  "Toggle spatial speech." (interactive)
  (emacsvox-output-settings--toggle 'emacsvox-aural-spatial-speech-enabled "Spatial speech"))
(defun emacsvox-output-settings--cues ()
  "Toggle spatial cues." (interactive)
  (emacsvox-output-settings--toggle 'emacsvox-aural-spatial-cue-enabled "Spatial cues"))
(defun emacsvox-output-settings--route-value ()
  "Return the notification choice, normalizing main output and named devices."
  (let ((value (default-value 'tts-notification-device)))
    (cond ((equal value "") "default")
          ((member value '(nil "left" "right" "both" "default")) value)
          (t 'other))))

(defun emacsvox-output-settings--choice-label (symbol value label)
  "Describe SYMBOL's VALUE with LABEL and its selection state."
  (concat label
          (when (equal value (if (eq symbol 'tts-notification-device)
                                 (emacsvox-output-settings--route-value)
                               (default-value symbol)))
            ", selected")))

(defun emacsvox-output-settings--choose (symbol value label)
  "Set global SYMBOL to VALUE, return to its control and announce LABEL."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (customize-set-variable symbol value)
  (transient--stack-pop)
  (transient--show)
  (emacsvox-output-settings--say
   (if (eq symbol 'tts-notification-device)
       (concat label ". Restart speech to apply; Save to keep it.")
     label)))

(defun emacsvox-output-settings--route-automatic ()
  "Use the backend default notification route.
Omnivox uses a separate process on both channels; other servers use main speech.
This is global and takes effect after a speech restart. Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'tts-notification-device nil "Automatic"))

(defun emacsvox-output-settings--route-left ()
  "Route separate notifications to the left channel.
Supported by Omnivox and SwiftMac; other backends need a device with this name.
This is global and takes effect after a speech restart. Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'tts-notification-device "left" "Left"))

(defun emacsvox-output-settings--route-right ()
  "Route separate notifications to the right channel.
Supported by Omnivox and SwiftMac; other backends need a device with this name.
This is global and takes effect after a speech restart. Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'tts-notification-device "right" "Right"))

(defun emacsvox-output-settings--route-both ()
  "Route separate notifications to both channels.
Omnivox supports this route; other backends need a device with this name.
This is global and takes effect after a speech restart. Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'tts-notification-device "both" "Both channels"))

(defun emacsvox-output-settings--route-main ()
  "Send notifications through main speech, where navigation can interrupt them.
Notifications remain audible; this disables the separate process.
This is global and takes effect after a speech restart. Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'tts-notification-device "default" "Main output"))

(defun emacsvox-output-settings--route-other ()
  "Name an existing device supported by the selected speech backend.
This global choice takes effect after a speech restart; Save is separate.
Cancelling the name prompt retains this list and the previous route."
  (interactive)
  (let ((value (emacsvox-transient--read
                #'read-string "Device name: "
                (when (eq (emacsvox-output-settings--route-value) 'other)
                  (default-value 'tts-notification-device)))))
    (emacsvox-output-settings--choose
     'tts-notification-device value
     (if (equal value "") "Main output" (concat "Device " value)))))

(transient-define-prefix emacsvox-output-settings--route ()
  "Choose the global notification route for the next speech restart.
Arrows browse without applying; Enter chooses and returns to the parent control.
The current choice is marked selected. Use q to cancel; Save is separate."
  ["Notification route for next restart"
   ("a" (lambda () (emacsvox-output-settings--choice-label 'tts-notification-device nil "Automatic"))
    emacsvox-output-settings--route-automatic :transient transient--do-replace)
   ("l" (lambda () (emacsvox-output-settings--choice-label 'tts-notification-device "left" "Left"))
    emacsvox-output-settings--route-left :transient transient--do-replace)
   ("r" (lambda () (emacsvox-output-settings--choice-label 'tts-notification-device "right" "Right"))
    emacsvox-output-settings--route-right :transient transient--do-replace)
   ("b" (lambda () (emacsvox-output-settings--choice-label 'tts-notification-device "both" "Both channels"))
    emacsvox-output-settings--route-both :transient transient--do-replace)
   ("m" (lambda () (emacsvox-output-settings--choice-label 'tts-notification-device "default" "Main output"))
    emacsvox-output-settings--route-main :transient transient--do-replace)
   ("o" (lambda () (emacsvox-output-settings--choice-label
                    'tts-notification-device 'other
                    (if (eq (emacsvox-output-settings--route-value) 'other)
                        (format "Other device: %s" (default-value 'tts-notification-device))
                      "Other device")))
    emacsvox-output-settings--route-other :transient t)]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-aural-menu--choice-setup
   'emacsvox-output-settings--route
   (or (cdr (assoc (emacsvox-output-settings--route-value)
                   '((nil . emacsvox-output-settings--route-automatic)
                     ("left" . emacsvox-output-settings--route-left)
                     ("right" . emacsvox-output-settings--route-right)
                     ("both" . emacsvox-output-settings--route-both)
                     ("default" . emacsvox-output-settings--route-main)
                     (other . emacsvox-output-settings--route-other))))
       'transient-quit-one)))

(defun emacsvox-output-settings--output-auto ()
  "Use each backend's reported spatial capability.
Stereo requires backend support and enabled spatial presentation.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-output 'auto "Automatic"))

(defun emacsvox-output-settings--output-mono ()
  "Center all spatial speech and cues, including on stereo backends.
Keep speech and cues audible while removing their direction.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-output 'mono "Mono"))

(transient-define-prefix emacsvox-output-settings--output ()
  "Choose global spatial capability without changing spatial enablement.
Arrows browse without applying; Enter chooses and returns to the parent control.
The current choice is marked selected. Use q to cancel; Save is separate."
  ["Spatial output"
   ("a" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-output 'auto "Automatic"))
    emacsvox-output-settings--output-auto :transient transient--do-replace)
   ("m" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-output 'mono "Mono"))
    emacsvox-output-settings--output-mono :transient transient--do-replace)]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-aural-menu--choice-setup
   'emacsvox-output-settings--output
   (or (cdr (assoc (default-value 'emacsvox-aural-spatial-output)
                   '((auto . emacsvox-output-settings--output-auto)
                     (mono . emacsvox-output-settings--output-mono))))
       'transient-quit-one)))

(defun emacsvox-output-settings--remapping-normal ()
  "Preserve requested left and right positions.
Maximum separation still limits the result.
Direction requires enabled spatial presentation and a capable stereo backend.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-remapping 'normal "Normal"))

(defun emacsvox-output-settings--remapping-reverse ()
  "Swap requested left and right positions.
Maximum separation still limits the result.
Direction requires enabled spatial presentation and a capable stereo backend.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-remapping 'reverse "Reverse left and right"))

(defun emacsvox-output-settings--remapping-collapse-left ()
  "Center left-side requests and preserve right-side requests.
Maximum separation still limits the remaining right-side positions.
Direction requires enabled spatial presentation and a capable stereo backend.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-remapping 'collapse-left "Center left-side requests"))

(defun emacsvox-output-settings--remapping-collapse-right ()
  "Center right-side requests and preserve left-side requests.
Maximum separation still limits the remaining left-side positions.
Direction requires enabled spatial presentation and a capable stereo backend.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-remapping 'collapse-right "Center right-side requests"))

(defun emacsvox-output-settings--remapping-center ()
  "Center every spatial request while keeping speech and cues audible.
Keep the configured output capability and maximum separation unchanged.
Direction requires enabled spatial presentation and a capable stereo backend.
Apply globally for this session; Save is separate."
  (interactive)
  (emacsvox-output-settings--choose 'emacsvox-aural-spatial-remapping 'center "Center all requests"))

(defun emacsvox-output-settings--remapping-custom-p ()
  "Return non-nil when direction mapping uses a custom function."
  (functionp (default-value 'emacsvox-aural-spatial-remapping)))

(defun emacsvox-output-settings--remapping-custom ()
  "Keep the current custom direction function and return to the parent control.
The function remains global and is not saved by this action. Use Customize
to edit it; the other choices replace it with a built-in mapping."
  (interactive)
  (transient--stack-pop)
  (transient--show)
  (emacsvox-output-settings--say "Custom mapping retained"))

(transient-define-prefix emacsvox-output-settings--remapping ()
  "Choose a global direction mapping without changing spatial enablement.
Arrows browse without applying; Enter chooses and returns to the parent control.
The current choice is marked selected. Use q to cancel; Save is separate.
A custom function remains active until you choose a built-in mapping."
  [:description (lambda () (if (functionp (default-value 'emacsvox-aural-spatial-remapping))
                   "Direction mapping (current: custom function)" "Direction mapping"))
   ("n" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-remapping 'normal "Normal"))
    emacsvox-output-settings--remapping-normal :transient transient--do-replace)
   ("r" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-remapping 'reverse "Reverse left and right"))
    emacsvox-output-settings--remapping-reverse :transient transient--do-replace)
   ("l" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-remapping 'collapse-left "Center left-side requests"))
    emacsvox-output-settings--remapping-collapse-left :transient transient--do-replace)
   ("h" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-remapping 'collapse-right "Center right-side requests"))
    emacsvox-output-settings--remapping-collapse-right :transient transient--do-replace)
   ("c" (lambda () (emacsvox-output-settings--choice-label 'emacsvox-aural-spatial-remapping 'center "Center all requests"))
    emacsvox-output-settings--remapping-center :transient transient--do-replace)
   ("k" "Custom function, selected" emacsvox-output-settings--remapping-custom
    :if emacsvox-output-settings--remapping-custom-p :transient transient--do-replace)]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-aural-menu--choice-setup
   'emacsvox-output-settings--remapping
   (or (cdr (assoc (default-value 'emacsvox-aural-spatial-remapping)
                   '((normal . emacsvox-output-settings--remapping-normal)
                     (reverse . emacsvox-output-settings--remapping-reverse)
                     (collapse-left . emacsvox-output-settings--remapping-collapse-left)
                     (collapse-right . emacsvox-output-settings--remapping-collapse-right)
                     (center . emacsvox-output-settings--remapping-center))))
       'emacsvox-output-settings--remapping-custom)))

(defun emacsvox-output-settings--separation (&optional delta)
  "Set maximum separation; Shift arrows change it by 0.1."
  (interactive)
  (when (and (not delta) (window-live-p transient--window))
    (with-selected-window transient--window
      (transient--goto-button (emacsvox-transient--menu-suffix 'emacsvox-output-settings--separation))))
  (let* ((old (default-value 'emacsvox-aural-spatial-maximum-separation))
         (value (if delta (max 0.0 (min 1.0 (/ (round (* 10 (+ old delta))) 10.0)))
                  (emacsvox-aural-menu--read-number "Maximum separation (0 to 1): " old))))
    (unless (and (numberp value) (= (- value value) 0) (<= 0 value 1))
      (user-error "Separation must be between 0 and 1"))
    (emacsvox-output-settings--set
     'emacsvox-aural-spatial-maximum-separation (float value)
     (format "%s%s" (if (and delta (= old value)) "Limit. " "") (float value)))))
(defun emacsvox-output-settings--adjust (direction)
  "Adjust selected separation in DIRECTION."
  (let ((command (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (oref (button-get button 'button-data) command)))))
    (unless (eq command 'emacsvox-output-settings--separation)
      (user-error "Choose Maximum separation first"))
    (emacsvox-output-settings--separation (* direction 0.1))))
(defun emacsvox-output-settings--decrease ()
  "Decrease separation." (interactive) (emacsvox-output-settings--adjust -1))
(defun emacsvox-output-settings--increase ()
  "Increase separation." (interactive) (emacsvox-output-settings--adjust 1))
(defun emacsvox-output-settings--bindings (map)
  "Add shifted-arrow separation adjustment to MAP."
  (when (and transient--prefix (eq (oref transient--prefix command) 'emacsvox-output-settings))
    (keymap-set map "S-<left>" #'emacsvox-output-settings--decrease)
    (keymap-set map "S-<right>" #'emacsvox-output-settings--increase)) map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-output-settings--bindings)
(define-key transient-predicate-map [emacsvox-output-settings--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-output-settings--increase] #'transient--do-stay)
(defun emacsvox-output-settings--save ()
  "Save global routing and spatial defaults without restarting speech."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (dolist (symbol emacsvox-output-settings--options)
    (customize-save-variable symbol (default-value symbol)))
  (emacsvox-output-settings--say "Saved output policy. Route changes require a speech restart."))
(defun emacsvox-output-settings--restart ()
  "Explicitly restart speech to apply the selected notification route."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (when (emacsvox-transient--read #'yes-or-no-p "Restart speech to apply notification routing? ")
      (tts-restart)
      (emacsvox-output-settings--say "Speech restart requested."))))
(defun emacsvox-output-settings--notify ()
  "Preview the active notification output without logging the sample."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (tts-notify "Notification output sample" t)))
(defun emacsvox-output-settings--preview ()
  "Preview left then right cue requests through the current spatial policy."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (let* ((rule (emacsvox-aural-compile-rule
                  '(:id spatial-sample :match ()
                    :render (:before ((:id left :kind cue :cue item :space (:balance -1.0))
                                      (:id gap :kind pause :duration 150)
                                      (:id right :kind cue :cue item :space (:balance 1.0)))))
                  'user 0 "spatial preview"))
           (context (emacsvox-aural-context-at-point))
           (render (emacsvox-aural-resolve nil context (list rule))))
      (emacsvox-aural-preview-play-plan
       (emacsvox-aural-compile-plan render nil context 'local-cue)))))
(defun emacsvox-output-settings--stop ()
  "Stop preview speech, cues, and notification speech."
  (interactive) (emacsvox-aural-preview-stop) (tts-notify-stop))
(defun emacsvox-output-settings--history ()
  "Open notification history; q returns to this menu."
  (interactive)
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (let ((buffer (get-buffer-create "*Emacsvox Notification History*")))
       (with-current-buffer buffer
         (emacsvox-aural-interface-mode)
         (let ((inhibit-read-only t))
           (erase-buffer)
           (if (buffer-live-p emacsvox-notifications-buffer)
               (insert-buffer-substring emacsvox-notifications-buffer)
             (insert "No notifications recorded.\n")))
         (goto-char (point-min)))
       (emacsvox-aural-ui-pop-to-buffer buffer)
       buffer))
   'emacsvox-output-settings--history))

;;;###autoload
(transient-define-prefix emacsvox-output-settings ()
  "Set global notification routing and spatial presentation policy."
  :refresh-suffixes t
  ["Notifications (route changes need speech restart)"
   ("r" (lambda () (format "Route for next restart: %s" (or tts-notification-device "automatic"))) emacsvox-output-settings--route :transient transient--do-stack)
   ("h" "Notification history" emacsvox-output-settings--history :transient transient--do-suspend)
   ("N" "Preview active notification output" emacsvox-output-settings--notify :transient t)
   ("R" "Restart speech to apply route" emacsvox-output-settings--restart :transient t)]
  ["Spatial presentation (global, immediate)"
   ("e" (lambda () (emacsvox-output-settings--label 'emacsvox-aural-spatial-enabled "Enabled")) emacsvox-output-settings--enabled :transient t)
   ("s" (lambda () (emacsvox-output-settings--label 'emacsvox-aural-spatial-speech-enabled "Speech")) emacsvox-output-settings--speech :transient t)
   ("c" (lambda () (emacsvox-output-settings--label 'emacsvox-aural-spatial-cue-enabled "Cues")) emacsvox-output-settings--cues :transient t)
   ("o" (lambda () (format "Output: %s" emacsvox-aural-spatial-output)) emacsvox-output-settings--output :transient transient--do-stack)
   ("m" (lambda () (format "Direction mapping: %s" emacsvox-aural-spatial-remapping)) emacsvox-output-settings--remapping :transient transient--do-stack)
   ("d" (lambda () (format "Maximum separation: %s" emacsvox-aural-spatial-maximum-separation)) emacsvox-output-settings--separation :transient t)]
  ["Preview and finish"
   ("SPC" "Preview left then right cues" emacsvox-output-settings--preview :transient t)
   ("x" "Stop previews" emacsvox-output-settings--stop :transient t)
   ("S" "Save routing and spatial defaults" emacsvox-output-settings--save :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (eq (oref prefix command) 'emacsvox-aural-menu-sounds))
                      (oref prefix scope) (emacsvox-aural-menu--capture nil))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-output-settings nil nil :scope context)))
(provide 'emacsvox-output-settings)
;;; emacsvox-output-settings.el ends here
