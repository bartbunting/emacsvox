;;; emacsvox-speak-windows.el --- Window reading and buffer selection -*- lexical-binding: t; -*-

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

;; Window reading and buffer selection.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'tts-speak)
(require 'emacsvox-aural-source)
(require 'sox-gen)

(declare-function emacsvox-speak-line "emacsvox-speak" (&optional arg))
(declare-function emacsvox-speak-region "emacsvox-speak" (start end))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))

(defun emacsvox--sox-multiwindow ()
  "Use `window-edges' and plays a sound cuew."
  (let ((corners (window-edges))
        (tr 0)
        (mr (/ (frame-height) 2))
        (br (1- (frame-height)))
        (lc 0)
        (mc (/ (frame-width) 2))
        (rc (frame-width)))
    (cond
     ((equal corners `(,lc ,tr ,mc ,br))
      (sox-multiwindow 1 2 "pluck")
      'left-half)
     ((equal corners `(,mc ,tr ,rc ,br))
      (sox-multiwindow 1 2  "pluck")
      'right-half)
     ((equal corners `(,lc ,tr ,rc ,mr))
      (sox-multiwindow nil 2)
      'top-half)
     ((equal corners `(,lc ,mr ,rc ,br))
      (sox-multiwindow nil 1.3)
      'bottom-half)
     ((equal corners `(,lc ,tr ,mc ,mr))
      (sox-multiwindow nil 2.5)
      'top-left)
     ((equal corners `(,mc ,tr ,rc ,mr))
      (sox-multiwindow t 2.5)
      'top-right)
     ((equal corners `(,lc ,mr ,mc ,br))
      (sox-multiwindow nil 0.9)
      'bottom-left)
     ((equal corners `(,mc ,mr ,rc ,br))
      (sox-multiwindow 'swap 0.9)
      'bottom-right)
     ((and (zerop (cl-first corners))
           (zerop (cl-second corners))
           (= rc (cl-third corners)))
      (sox-multiwindow nil 2)
      'top-half)
     ((and (zerop (cl-first corners))
           (= rc (cl-third corners))
           (= br (cl-fourth corners)))
      (sox-multiwindow nil 1.3)
      'bottom-half)
     ((and (zerop (cl-first corners))
           (zerop (cl-second corners))
           (= br (cl-fourth corners)))
      (sox-multiwindow)
      'left-half)
     ((and (zerop (cl-second corners))
           (= rc (cl-third corners))
           (= br (cl-fourth corners)))
      (sox-multiwindow 'swap)
      'right-half)
     (t ""))))

;;;   Using emacs's windows usefully:

;;Return current window contents
(defsubst emacsvox-get-window-contents ()
  "Return window contents."
  (save-excursion
    (emacsvox-aural-source-substring
     (window-start (selected-window))
     (window-end (selected-window)  'update ))))

(defun emacsvox-speak-windowful ()
  "Delete other windows, Line to top, then Speak window contents."
  (interactive)
  (delete-other-windows)
  (recenter 0)
  (emacsvox-icon 'scroll)
  (tts-speak (emacsvox-get-window-contents)))

(defun emacsvox-speak-window-information ()
  "Speaks information about current window."
  (interactive)
  (message "Current window has %s lines and %s columns with
top left %s %s "
           (window-height)
           (window-width)
           (cl-first (window-edges))
           (cl-second (window-edges))))

(defun emacsvox-speak-current-window ()
  "Speak contents of current window.
Speaks entire window irrespective of point."
  (interactive)
  (emacsvox-speak-region
   (window-start (selected-window))
   (window-end (selected-window) 'update)))

(defun emacsvox-owindow-scroll-up ()
  "Scroll up the window that command `other-window' would move to.
Speak the window contents after scrolling."
  (interactive)
  (save-window-excursion
    (other-window 1)
    (call-interactively 'scroll-up)))

(defun emacsvox-owindow-scroll-down ()
  "Scroll down  the window that command `other-window' would move to.
Speak the window contents after scrolling."
  (interactive)
  (save-window-excursion
    (other-window 1)
    (call-interactively 'scroll-down)))

(defun emacsvox-owindow-next-line (count)
  "Move to the next line in the other window and speak it.
Numeric prefix arg COUNT can specify number of lines to move."
  (interactive "p")
  (setq count (or count 1))
  (let ((residue nil))
    (save-current-buffer
      (set-buffer (window-buffer (next-window)))
      (end-of-line)
      (setq residue (forward-line count))
      (cond
       ((> residue 0) (message "At bottom of other window "))
       (t (set-window-point (get-buffer-window (current-buffer))
                            (point))
          (emacsvox-speak-line))))))

(defun emacsvox-owindow-previous-line (count)
  "Move to the next line in the other window and speak it.
Numeric prefix arg COUNT specifies number of lines to move."
  (interactive "p")
  (setq count (or count 1))
  (let ((residue nil))
    (save-current-buffer
      (set-buffer (window-buffer (next-window)))
      (end-of-line)
      (setq residue (forward-line (- count)))
      (cond
       ((> 0 residue) (message "At top of other window "))
       (t (set-window-point (get-buffer-window (current-buffer))
                            (point))
          (emacsvox-speak-line))))))

(defun emacsvox-owindow-speak-line ()
  "Speak the current line in the other window."
  (interactive)
  (save-current-buffer
    (set-buffer (window-buffer (next-window)))
    (goto-char (window-point))
    (emacsvox-speak-line)))

(defun emacsvox-speak-this-window ()
  "Speak current window."
  (interactive )
  (emacsvox-speak-region
   (window-start (selected-window))
   (window-end  (selected-window) 'update)))

(defun emacsvox-speak-other-window ()
  "Speak other window"
  (interactive )
  (save-window-excursion
    (other-window 1)
    (emacsvox-speak-region
     (window-start (selected-window))
     (window-end  (selected-window) 'update))))

(defun emacsvox-speak-predefined-window (&optional arg)
  "Speak one of the first 10 windows on the screen, 0 is current window.
Speaks entire window irrespective of point.  Semantics of `other'
is the same as for the Emacs builtin `other-window'."
  (interactive "P")

  (let* ((window
          (cond
           ((not (called-interactively-p 'interactive)) arg)
           (t
            (read (format "%c" last-input-event))))))
    (or (numberp window)
        (setq window  (read-number "Window   between 1 and 9:" 1)))
    (save-window-excursion
      (other-window window)
      (emacsvox-speak-region
       (window-start (selected-window))

       (window-end  (selected-window) 'update)))))

;;; Tapestry --Jump to window by name:

(defun emacsvox-describe-tapestry (&optional details)
  "Describe the current layout of visible buffers in current frame.
Use interactive prefix arg to get coordinate positions of the
displayed buffers."
  (interactive "P")

  (let* ((window-list (window-list))
         (count (length window-list))
         (windows nil)
         (description
          (propertize
           (format
            "Displaying %s window%s "
            count
            (if (> count 1) "s" ""))
           'personality 'voice-annotate)))
    (setq
     windows
     (cond
      (details
       (cl-loop
        for window in window-list
        collect
        (let ((w
               (propertize
                (format "%s "  (window-buffer window))
                'personality 'voice-animate))
              (corners  (window-edges window))
              (tl nil)
              (br nil))
          (setq tl (format  " %d %d " (cl-second corners) (cl-first corners))
                br  (format " %d %d " (cl-fourth corners) (cl-third corners)))
          (put-text-property 0 (length tl) 'personality 'voice-bolden tl)
          (put-text-property 0 (length br) 'personality 'voice-bolden br)
          (concat w " with top left " tl " and bottom right " br))))
      (t (mapcar #'buffer-name (mapcar #'window-buffer window-list)))))
    (emacsvox--sox-multiwindow )
    (tts-speak (concat description (mapconcat #'identity windows " ")))))

(defun emacsvox-select-window-by-name (buffer-name)
  "Select window by the name of the buffer it displays.
This is useful when using modes like ECB or the new GDB UI where
  you want to preserve the window layout
but quickly switch to a window by name."
  (interactive
   (list
    (completing-read
     "Select window: "
     (mapcar
      #'(lambda (w)
          (list (buffer-name (window-buffer w))))
      (window-list))
     nil 'must-match)))
  (pop-to-buffer buffer-name)
  (emacsvox-speak-line))

;;;  Buffer Select:

;; Helpers:

(defsubst emacsvox-buffer-cycle-previous (mode)
  "Return previous  buffer in cycle order having same major mode as `mode'."
  (catch 'cl-loop
    (dolist (buf (reverse (cdr (buffer-list (selected-frame)))))
      (when (with-current-buffer buf (eq mode major-mode))
        (throw 'cl-loop buf)))))

(defsubst emacsvox-buffer-cycle-next (mode)
  "Return next buffer in cycle order having same major mode as `mode'."
  (catch 'cl-loop
    (dolist (buf (cdr (buffer-list (selected-frame))))
      (when (with-current-buffer buf (eq mode major-mode))
        (throw 'cl-loop buf)))))

(defun emacsvox-cycle-to-previous-buffer ()
  "Cycles to previous buffer having same mode."
  (interactive)
  (let ((prev (emacsvox-buffer-cycle-previous major-mode)))
    (cond
     (prev
      (funcall-interactively #'switch-to-buffer prev))
     (t (error "No previous buffer in mode %s" major-mode)))))

(defun emacsvox-cycle-to-next-buffer ()
  "Cycles to next buffer having same mode."
  (interactive)
  (let ((next (emacsvox-buffer-cycle-next major-mode))
        (current (current-buffer)))
    (cond
     (next
      (prog1 (funcall-interactively #'switch-to-buffer next)
        ;; Rotate the buffer just left to the end.  Merely switching promotes
        ;; NEXT to the front and makes repeated next commands toggle two buffers.
        ;; This rotation is the inverse of promoting the last matching buffer.
        (bury-buffer current)))
     (t (error "No next buffer in mode %s" major-mode)))))

;; Inspired by text-adjust-scale:

(defcustom emacsvox-buffer-select-help
  ""
  "String passed to speak help.
Set this to the empty string once you've learnt this command. "
  :type '(choice
          (const :tag "Speak Keys" :value "Repeat with %k")
          (const :tag "Silence" :value ""))
  :group 'emacsvox)

(defun emacsvox-buffer-select()
  "Select buffer by smart cycling.
Use option emacsvox-buffer-select-help to customize interactive feedback.
By default, this command is bound to multiple keys.
The final key of the initial  key-sequence, and  further invocations
of the keys below call the following bindings:

, previous-buffer
. next-buffer
b switch-to-buffer
f find-file
k emacsvox-kill-buffer-quietly
n emacsvox-cycle-to-next-buffer
o other-window
p emacsvox-cycle-to-previous-buffer
"
  (interactive )

  (let ((key (event-basic-type last-command-event)))
    (emacsvox-icon 'repeat-active)
    (cl-case key
      (?b (call-interactively 'switch-to-buffer))
      (?f (call-interactively 'find-file))
      (?k (call-interactively 'emacsvox-kill-buffer-quietly))
      (?p
       (call-interactively 'emacsvox-cycle-to-previous-buffer))
      (?, (call-interactively 'previous-buffer))
      (?n
       (call-interactively 'emacsvox-cycle-to-next-buffer))
      (?o (call-interactively 'other-window))
      (?. (call-interactively 'next-buffer)))
    (set-transient-map
     (let ((map (make-sparse-keymap)))
       (dolist (key '("b" "f" "k" "," "."   "p" "n" "o"))
         (define-key
          map key
          #'(lambda () (interactive) (emacsvox-buffer-select ))))
       map)
     t (lambda nil (emacsvox-icon 'repeat-end))
     emacsvox-buffer-select-help)))

(provide 'emacsvox-speak-windows)

;;; emacsvox-speak-windows.el ends here
