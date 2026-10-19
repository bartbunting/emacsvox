;;; emacsvox-speak-navigation.el --- Reading navigation and repeat feedback -*- lexical-binding: t; -*-

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

;; Reading navigation and repeat feedback.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'text-property-search)
(require 'tts-speak)
(require 'emacsvox-aural-source)
(require 'emacsvox-speak-status)

(defvar repeat-in-progress)
(declare-function emacsvox-speak-line "emacsvox-speak" (&optional arg))
(declare-function emacsvox-speak-region "emacsvox-speak" (start end))
(declare-function emacsvox-mark-speak-mark-line "emacsvox-speak" ())
(declare-function emacsvox-icon "emacsvox-sounds" (icon))

(defun emacsvox-goto-percent (percent)
  "Move to end  PERCENT of buffer like in View mode.
Display is centered at point.
Also set the mark at the position where point was."
  (interactive "nPercent:")
  (push-mark)
  (goto-char
   (if percent
       (+ (point-min)
          (floor (* (- (point-max) (point-min)) 0.01
                    (max 0 (min 100 (prefix-numeric-value percent))))))
     (point-max)))
  (recenter)
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

;;;  speaking personality chunks

;; Block navigation

;;; Face Ranges:

(defun emacsvox-speak-face-browse ()
  "Use C-f and C-b or left/right arrows to browse by current face."
  (interactive )
  (call-interactively #'emacsvox-speak-range)
  (while t
    (let ((key (read-key "" t)))
      (cond
       ((memq key '(right 6))
        (funcall-interactively #'emacsvox-speak-face-forward))
       ((memq key '(left 2))
        (funcall-interactively #'emacsvox-speak-face-backward))
       (t (keyboard-quit))))))

(defun emacsvox-speak-range (&optional prop)
  "Speak and return  range at point"
  (interactive )
  (setq prop (or prop 'face))
  (let*
      ((start (previous-single-property-change (1+ (point)) prop))
       (pre-start (previous-single-property-change (point) prop))
       (end (next-single-property-change (point) prop))
       (beg (or start pre-start)))
    (when (and  beg end)
      (emacsvox-speak-region beg end)
      (emacsvox-aural-source-substring beg end))))

(defun emacsvox-speak-face-forward ()
  "Property search for face --- see \\[text-property-search-forward]"
  (interactive)
  (when-let*
      ((match
        (funcall-interactively
         #'text-property-search-forward
         'face (get-text-property (point) 'face)
         t t)))
    (goto-char (prop-match-beginning match))))

(defun emacsvox-speak-face-backward ()
  "Property search for face at point see \\[text-property-search-backward]"
  (interactive)
  (when-let*
      ((match
        (funcall-interactively
         #'text-property-search-backward
         'face (get-text-property (point) 'face) t t)))
    (goto-char (prop-match-beginning match))))

;;;   Execute command repeatedly:

(defun emacsvox-execute-repeatedly (command)
  "Execute COMMAND repeatedly."
  (emacsvox-icon 'repeat-start)
  (let ((key "")
        (pos (point))
        (continue t)
        (message "Space Repeats."))
    (while continue
      (emacsvox-icon 'repeat-active)
      (call-interactively command)
      (cond
       ((= (point) pos) (setq continue nil))
       (t (setq pos (point))
          (setq key (read-key message))
          (when (not (= 32 key))
            (tts-stop 'all)
            (setq continue nil))))
      (emacsvox-icon 'repeat-end)
      (tts-speak "Exited continuous mode "))))

(defun emacsvox-speak-continuously ()
  "Speak a buffer continuously.
First prompts using the minibuffer for the kind of action to
perform after speaking each chunk,   E.G.  speak a line at a time
etc.  Speaking commences at current buffer position.  Pressing
\\[keyboard-quit] breaks out, leaving point on last chunk that
was spoken.  Pressing SPC  continues to speak the buffer; any other
  key quits."
  (interactive)
  (let ((command
         (key-binding (read-key-sequence "Press navigation key to repeat: "))))
    (unless command (error "You specified an invalid key sequence.  "))
    (emacsvox-execute-repeatedly command)))

;;;   skimming

(defun emacsvox-speak-skim-buffer ()
  "Skim the current buffer  a paragraph at a time."
  (interactive)
  (emacsvox-execute-repeatedly 'forward-paragraph))

;;;   Moving across fields:

;; Fields are defined by property 'field

;; helper function: speak a field

(defun emacsvox-speak-field ()
  "Speak the field at point, choosing the right-hand field at a boundary.
At the accessible buffer end, speak the final field."
  (interactive)
  ;; Use the same property boundaries as navigation.  `field-string' chooses
  ;; the left-hand field at an edge, even after moving to the next field.
  (tts-speak
   (if (= (point-min) (point-max)) ""
     (let* ((position (min (point) (1- (point-max))))
            (start (previous-single-property-change
                    (1+ position) 'field nil (point-min)))
            (end (next-single-property-change
                  position 'field nil (point-max))))
       (buffer-substring start end)))))

(defun emacsvox-speak-next-field ()
  "Move to and speak next field.
Signal a user error without moving if there is no next field."
  (interactive)

  (let ((inhibit-field-text-motion t))
    (if-let* ((destination (next-single-property-change (point) 'field)))
        (progn
          (goto-char destination)
          (emacsvox-speak-field))
      (user-error "No next field"))))

(defun emacsvox-speak-previous-field ()
  "Move to previous field boundary and speak the field starting there.
Signal a user error without moving at the accessible buffer beginning."
  (interactive)

  (let ((inhibit-field-text-motion t))
    (when (bobp) (user-error "No previous field"))
    (goto-char (previous-single-property-change
                (point) 'field nil (point-min)))
    (emacsvox-speak-field)))

(defun emacsvox-speak-current-column ()
  "Speak the current column."
  (interactive)
  (message "Column %d" (current-column)))

(defun emacsvox-speak-current-percentage ()
  "Announce the percentage into the current buffer."
  (interactive)
  (message "Point is  %d%% into  the current buffer"
           (emacsvox-get-current-percentage-into-buffer)))

(defun emacsvox-mark-backward-mark ()
  "Cycle backward through the mark ring.
To cycle forward, use pop-to-mark-command bound to \\[pop-to-mark-command] "
  (interactive)

  (unless mark-ring (error "Mark ring is empty."))
  (let ((target (elt mark-ring (1- (length mark-ring)))))
    (when target
      (setq mark-ring
            (cons (copy-marker (mark-marker))
                  (nbutlast mark-ring 1)))
      (set-marker (mark-marker) (point) (current-buffer))
      (goto-char (marker-position target))
      (move-marker target nil)
      (when (called-interactively-p 'interactive)
        (emacsvox-mark-speak-mark-line)))))

;;; Repeat Mode:
;; See https://karthinks.com/software/it-bears-repeating/

(defvar emacsvox-repeat-was-active nil
  "Cache repeat-progress")

(defun emacsvox-repeat-check-hook ()
  "Play appropriate repeat icon."

  (cond
   ((and repeat-in-progress (not emacsvox-repeat-was-active))
    (setq emacsvox-repeat-was-active t)
    (emacsvox-icon 'repeat-start))
   ((and (not repeat-in-progress)  emacsvox-repeat-was-active)
    (setq emacsvox-repeat-was-active nil)
    (emacsvox-icon 'repeat-end))
   (repeat-in-progress (emacsvox-icon 'repeat-active))))

(defun ems--repeat-sentinel (process _state)
  "Process sentinel to disable repeat. "
  (when (memq (process-status process) '(failed signal exit stop nil))
    (when repeat-mode (repeat-exit))))

(defsubst emacsvox-repeat-mode-hook ()
  "Add or remove emacsvox-repeat-check-hook from post-command-hook"

  (cond
   (repeat-mode
    (add-hook 'post-command-hook 'emacsvox-repeat-check-hook 'at-end))
   (t (remove-hook 'post-command-hook 'emacsvox-repeat-check-hook))))

;;; go top or bottom
(defun emacsvox-beginning-or-end ()
  "Move to start or end of buffer."
  (interactive)
  (cond
   ((= (point) (point-min)) (call-interactively 'end-of-buffer))
   ((= (point) (point-max)) (call-interactively 'beginning-of-buffer))
   (t (call-interactively 'beginning-of-buffer)))
  (when (called-interactively-p 'interactive)
    (tts-notify
     (format "%s%%" (emacsvox-get-current-percentage-into-buffer)))))

;;; Smarter selective-display:

(defun emacsvox-selective-display (&optional arg)
  "Continuously adjust selective-display.
Use `,' and `.' to continuously decrease/increase `selective-display'.
 If not specified, `arg' defaults to current-column."
  (interactive "P")

  (setq selective-display
        (if arg (prefix-numeric-value arg) (current-column)))
  (let ((key (event-basic-type last-command-event)))
    (emacsvox-icon 'repeat-start)
    (cl-case key
      (?,
       (cl-assert (numberp selective-display) t
                  "Selective display is off")
       (if (> selective-display 2)
           (setq selective-display (- selective-display 2))
         (setq selective-display nil))
       (funcall-interactively #'set-selective-display selective-display))
      (?.
       (when (or (numberp selective-display) (null selective-display))
         (if (null selective-display)
             (setq selective-display 2)
           (setq selective-display (+ selective-display 2)))
         (funcall-interactively #'set-selective-display selective-display))))
    (set-transient-map
     (let ((map (make-sparse-keymap)))  ; map
       (dolist (key '("," "."))
         (define-key
          map key
          (lambda ()
            (interactive)
            (emacsvox-selective-display selective-display))))
       map)
     t                                  ; continue predicate
     (lambda nil (emacsvox-icon 'repeat-end)) ; done action
     (propertize
      (format "Selective Display: %s" selective-display)
      'personality 'voice-bolden))))

(provide 'emacsvox-speak-navigation)

;;; emacsvox-speak-navigation.el ends here
