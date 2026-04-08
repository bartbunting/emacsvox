;;; emacsvox-eterm.el --- Speech enable eterm -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech enable eterm.
;; Keywords: Emacsvox, Eterm, Terminal emulation, Spoken Output
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;; 
;; This file is not part of GNU Emacs, but the same permissions apply.
;; 
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Commentary:
;; This module makes eterm talk.
;; Eterm is the new terminal emulator for Emacs.
;; Use of emacsvox with eterm really needs an info page.
;; At present, the only documentation is the source level documentation.
;; This module uses Control-t as an additional prefix key to allow the user
;; To move around the terminal and have different parts spoken.

;;; Code:
;;;  required packages:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'term)

;;;  custom

(defgroup emacsvox-eterm nil
  "Terminal emulator for the Emacsvox Desktop."
  :group 'emacsvox
  :prefix "emacsvox-eterm-")

;;;   keybindings:

(defvar emacsvox-eterm-keymap (make-keymap)
  "Keymap used to navigate a terminal without moving the cursor.")
(defvar emacsvox-eterm-prefix "\C-t"
  "Prefix char used by emacsvox for navigating an eterm.")

(defun emacsvox-eterm-setup-keys()
  "Make eterm usable with emacsvox"
  (cl-declare (special emacsvox-prefix emacsvox-eterm-prefix
                       emacsvox-eterm-keymap  term-mode-map))
  (define-prefix-command 'emacsvox-eterm-prefix-command
                         'emacsvox-eterm-keymap)
  (define-key term-mode-map emacsvox-eterm-prefix
              'emacsvox-eterm-prefix-command)
  (suppress-keymap emacsvox-eterm-keymap)
  (let  ((i 0))
    (while (< i 10)
      (define-key emacsvox-eterm-keymap
                  (format "%s" i) 'emacsvox-eterm-speak-predefined-window)
      (cl-incf i)))
  (define-key emacsvox-eterm-keymap "\C-i" 'emacsvox-eterm-speak-cursor)
  (define-key emacsvox-eterm-keymap "\C-q" 'emacsvox-toggle-eterm-autospeak)
  (define-key emacsvox-eterm-keymap " "  'emacsvox-eterm-speak-screen)
  (define-key emacsvox-eterm-keymap '[up] 'emacsvox-eterm-pointer-up)
  (define-key emacsvox-eterm-keymap '[down] 'emacsvox-eterm-pointer-down)
  (define-key emacsvox-eterm-keymap '[left] 'emacsvox-eterm-pointer-left)
  (define-key emacsvox-eterm-keymap '[right] 'emacsvox-eterm-pointer-right)
  (define-key emacsvox-eterm-keymap "a" 'emacsvox-eterm-pointer-to-left-edge)
  (define-key emacsvox-eterm-keymap "e" 'emacsvox-eterm-pointer-to-right-edge)
  (define-key
   emacsvox-eterm-keymap "\M-b" 'emacsvox-eterm-pointer-backward-word)
  (define-key
   emacsvox-eterm-keymap "\M-f"  'emacsvox-eterm-pointer-forward-word)
  (define-key emacsvox-eterm-keymap "." 'emacsvox-eterm-pointer-to-cursor)
  (define-key emacsvox-eterm-keymap "," 'emacsvox-eterm-speak-pointer)
  (define-key emacsvox-eterm-keymap "c" 'emacsvox-eterm-speak-pointer-char)
  (define-key emacsvox-eterm-keymap "w" 'emacsvox-eterm-speak-pointer-word)
  (define-key emacsvox-eterm-keymap "l" 'emacsvox-eterm-speak-pointer-line)
  (define-key emacsvox-eterm-keymap "p"  'emacsvox-eterm-pointer-up)
  (define-key emacsvox-eterm-keymap "n" 'emacsvox-eterm-pointer-down)
  (define-key emacsvox-eterm-keymap "b"  'emacsvox-eterm-pointer-left)
  (define-key emacsvox-eterm-keymap "f" 'emacsvox-eterm-pointer-right)
  (define-key emacsvox-eterm-keymap "h"
              'emacsvox-eterm-pointer-to-next-color-change)
  (define-key emacsvox-eterm-keymap "H"
              'emacsvox-eterm-pointer-to-previous-color-change)
  (define-key emacsvox-eterm-keymap "t" 'emacsvox-eterm-pointer-to-top)
  (define-key emacsvox-eterm-keymap "<" 'emacsvox-eterm-pointer-to-top)
  (define-key emacsvox-eterm-keymap ">" 'emacsvox-eterm-pointer-to-bottom)
  (define-key emacsvox-eterm-keymap "g" 'emacsvox-eterm-goto-line)
  (define-key emacsvox-eterm-keymap "s" 'emacsvox-eterm-search-forward)
  (define-key emacsvox-eterm-keymap "y"
              'emacsvox-eterm-kill-ring-save-region)
  (define-key emacsvox-eterm-keymap "x"
              'emacsvox-eterm-copy-region-to-register)
  (define-key emacsvox-eterm-keymap "v" 'emacsvox-eterm-paste-register)
  (define-key emacsvox-eterm-keymap "m" 'emacsvox-eterm-set-marker)
  (define-key emacsvox-eterm-keymap "\C-p"
              'emacsvox-eterm-toggle-pointer-mode)
  (define-key emacsvox-eterm-keymap "\C-w" 'emacsvox-eterm-define-window)
  (define-key emacsvox-eterm-keymap "\C-y"
              'emacsvox-eterm-yank-window)
  (define-key emacsvox-eterm-keymap "f"
              'emacsvox-eterm-set-filter-window)
  (define-key emacsvox-eterm-keymap "\C-f"
              'emacsvox-eterm-set-focus-window)
  (define-key emacsvox-eterm-keymap "A" 'emacsvox-eterm-toggle-filter-window)
  (define-key
   emacsvox-eterm-keymap "\C-a" 'emacsvox-eterm-toggle-focus-window)
  (define-key emacsvox-eterm-keymap "\C-d" 'emacsvox-eterm-describe-window)
  (define-key emacsvox-eterm-keymap "\C-m" 'emacsvox-eterm-speak-window)
  (define-key emacsvox-eterm-keymap "r" 'emacsvox-eterm-toggle-review)
  (define-key emacsvox-eterm-keymap "q" 'emacsvox-eterm-toggle-review)
  (and term-raw-escape-map
       (mapc
        #'(lambda (key)
            (define-key term-raw-escape-map key
                        (lookup-key (current-global-map) key)))
        '("\M-x" "\C-h")))
  t)

(defvar emacsvox-eterm-raw-prefix
  "\C-r"
  "Prefix key to use  to send out raw term input.
Useful when eterm is in review mode.")

(defun emacsvox-eterm-setup-raw-keys ()
  "Setup emacsvox keys for raw terminal mode."
  (cl-declare (special term-raw-map
                       emacsvox-prefix term-raw-escape-map
                       emacsvox-eterm-keymap
                       emacsvox-eterm-raw-prefix))
  (when term-raw-map
    (define-key term-raw-map emacsvox-prefix 'emacsvox-keymap)
    (define-key term-raw-map (concat emacsvox-prefix emacsvox-prefix)
                'emacsvox-eterm-maybe-send-raw)
    (define-key term-raw-map emacsvox-eterm-prefix
                'emacsvox-eterm-prefix-command)
    (define-key term-raw-map emacsvox-eterm-raw-prefix term-raw-map)
    (define-key term-raw-map
                (concat emacsvox-eterm-raw-prefix emacsvox-eterm-raw-prefix)
                'emacsvox-eterm-maybe-send-raw)
    (define-key
     term-raw-map
     (concat emacsvox-eterm-prefix emacsvox-eterm-prefix)
     'emacsvox-eterm-maybe-send-raw)
    (define-key emacsvox-eterm-keymap emacsvox-eterm-raw-prefix
                term-raw-map)))

;;;   voice definitions  for eterm  highlight, underline etc

(defvar emacsvox-eterm-highlight-personality voice-bolden
  "Personality to show terminal highlighting.")

(defvar emacsvox-eterm-bold-personality voice-bolden
  "Personality to indicate terminal bold.")

(defvar emacsvox-eterm-underline-personality 'ursula
  "Personality to indicate terminal underlining.")

(defvar emacsvox-eterm-default-personality 'paul
  "Default personality for terminal.")

;;;   functions

;; nuke term cache info
(defun emacsvox-eterm-nuke-cached-info ()
  
  (setq term-current-row nil
        term-current-column nil))

;; Send the last input character as a  raw key,
;; ie without any interpretation.
;; Ensure you're in a terminal before sending it through."
(defun emacsvox-eterm-maybe-send-raw ()
  "Send a raw character through if in the terminal buffer.
Execute end of line if
in a non eterm buffer if executed via C-e C-e"
  (interactive)
  
  (cond
   ((or (eq major-mode 'term-mode)
        (eq major-mode 'tshell-mode))
    (term-send-raw))
   ((= last-input-event 5) (call-interactively #'move-end-of-line))
   (t (beep))))

(defun emacsvox-eterm-speak-cursor ()
  "Speak cursor position."
  (interactive)
  (message
   "Cursor at Row %s Column %s"
   (term-current-row)
   (term-current-column)))

(defun emacsvox-eterm-speak-pointer ()
  "Speak current pointer position."
  (interactive)
  
  (let ((coordinates (emacsvox-eterm-position-to-coordinates
                      (marker-position emacsvox-eterm-pointer))))
    (message
     "Pointer at row %s column %s "
     (cdr coordinates) (car coordinates))))

(defun emacsvox-eterm-speak-screen (&optional flag)
  "Speak the screen.  Default is to speak from the emacsvox pointer  to point.
Optional prefix arg FLAG causes region above
the Emacsvox pointer to be spoken."
  (interactive "P")
  
  (if flag
      (emacsvox-speak-region term-home-marker  emacsvox-eterm-pointer)
    (emacsvox-speak-region  emacsvox-eterm-pointer (point-max))))

;;;   Speaking the screen pointer:

;; The pointer is an invisible marker that is
;; moved around to speak the screen.
;; The pointer is emacsvox-eterm-pointer and starts off at the cursor.
;; Speaking relative to the pointer:

(defun emacsvox-eterm-speak-pointer-line ()
  "Speak the line the pointer is on."
  (interactive)
  
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (emacsvox-speak-line)))

(defun emacsvox-eterm-speak-pointer-word ()
  "Speak the word  the pointer is on."
  (interactive)
  
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (emacsvox-speak-word nil)))

(defun emacsvox-eterm-speak-pointer-char (&optional prefix)
  "Speak char under eterm pointer.
Pronounces character phonetically unless  called with a PREFIX arg."
  (interactive "P")
  
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (emacsvox-speak-char prefix)))

;;;   moving the screen pointer:

(defun emacsvox-eterm-pointer-to-cursor ()
  "Move the pointer to the cursor."
  (interactive)
  
  (set-marker emacsvox-eterm-pointer (point))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'large-movement)
    (emacsvox-eterm-speak-cursor)))

(defun emacsvox-eterm-pointer-to-top ()
  "Move the pointer to the top of the screen."
  (interactive)
  
  (save-excursion
    (goto-char term-home-marker)
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-line))))

(defun emacsvox-eterm-pointer-to-bottom  ()
  "Move the pointer to the bottom  of the screen."
  (interactive)
  
  (save-excursion
    (goto-char (point-max))
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-line))))

(defun emacsvox-eterm-pointer-up (count)
  "Move the pointer up a line.
Argument COUNT .specifies number of lines by which to move."
  (interactive "P")
  (cl-declare (special emacsvox-eterm-pointer
                       term-home-marker))
  (setq count (or count 1))
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (forward-line (- count))
    (beginning-of-line)
    (cond
     ((<= (marker-position term-home-marker) (point))
      (set-marker emacsvox-eterm-pointer (point))
      (emacsvox-speak-line))
     (t (error "At top of screen. ")))))

(defun emacsvox-eterm-pointer-down (count)
  "Move the pointer down a line.
Argument COUNT specifies number of lines by which to move."
  (interactive "P")
  
  (setq count (or count 1))
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (forward-line count)
    (beginning-of-line)
    (cond
     ((<= (point) (point-max))
      (set-marker emacsvox-eterm-pointer (point))
      (emacsvox-speak-line))
     (t (error "Not that many lines on the screen")))))

(defun emacsvox-eterm-pointer-left (count)
  "Move the pointer left.
Argument COUNT specifies number of columns by which to move."
  (interactive "P")
  
  (setq count (or count 1))
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (backward-char count)
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (dtk-stop)
      (emacsvox-speak-char t))))

(defun emacsvox-eterm-pointer-right (count)
  "Move the pointer right.
Argument COUNT specifies number of columns by which to move."
  (interactive "P")
  
  (setq count (or count 1))
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (forward-char  count)
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (dtk-stop)
      (emacsvox-speak-char t))))

(defun emacsvox-eterm-pointer-to-right-edge ()
  "Move the pointer to the right edge."
  (interactive)
  
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (end-of-line)
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (dtk-stop)
      (emacsvox-icon 'right)
      (emacsvox-speak-char t))))

(defun emacsvox-eterm-pointer-to-left-edge ()
  "Move the pointer to the right edge."
  (interactive)
  
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (forward-line 0)
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (dtk-stop)
      (emacsvox-icon 'left)
      (emacsvox-speak-char t))))

(defun emacsvox-eterm-pointer-backward-word (count)
  "Move the pointer backward  by words.
Interactive numeric prefix arg specifies number of words to move.
Argument COUNT specifies number of words by which to move."
  (interactive "P")
  
  (setq count (or count 1))
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (condition-case nil
        (forward-word  (- count))
      (error nil))
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (emacsvox-speak-word))))

(defun emacsvox-eterm-pointer-forward-word (count)
  "Move the pointer forward by words.
Interactive numeric prefix arg specifies number of words to move.
Argument COUNT specifies number of words by which to move."
  (interactive "P")
  
  (setq count (or count 1))
  (save-excursion
    (goto-char emacsvox-eterm-pointer)
    (condition-case nil
        (forward-word  count)
      (error nil))
    (skip-syntax-forward " ")
    (set-marker emacsvox-eterm-pointer (point))
    (when (called-interactively-p 'interactive)
      (emacsvox-speak-word))))

(defun emacsvox-eterm-goto-line (line)
  "Move emacsvox eterm pointer to a specified LINE."
  (interactive "nGo to line:")
  (cl-declare (special emacsvox-eterm-pointer
                       term-home-marker))
  (save-excursion
    (goto-char term-home-marker)
    (forward-line line)
    (set-marker emacsvox-eterm-pointer (point))
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(defun emacsvox-eterm-search-forward ()
  "Search forward on the terminal."
  (interactive)
  (emacsvox-eterm-search 1))

(defun emacsvox-eterm-search-backward ()
  "Search backward on the terminal."
  (interactive)
  (emacsvox-eterm-search -1))

;; Helper function for searching:

(defun emacsvox-eterm-search(direction)
  "Prompt for a string,
and try and locate it on the terminal.
If found, the Emacsvox pointer is left at the hit. "
  (cl-declare (special emacsvox-eterm-pointer
                       term-home-marker))
  (let ((found nil)
        (start nil)
        (end nil)
        (string (read-from-minibuffer "Enter search string: ")))
    (if (= 1 direction)                 ; forward search
        (setq start  (marker-position emacsvox-eterm-pointer)
              end (point-max))
                                        ; backward search
      (setq start (marker-position emacsvox-eterm-pointer)
            end (marker-position term-home-marker)))
    (save-excursion
      (goto-char start)
      (save-restriction
        (narrow-to-region start end)
        (save-match-data
          (if (= 1 direction)           ;forward search
              (setq found (search-forward  string  end t))
            (setq found (search-backward   string end t))))
        (cond
         (found (set-marker emacsvox-eterm-pointer (point-marker))
                (emacsvox-icon 'search-hit)
                (emacsvox-eterm-speak-pointer-line))
         (t(emacsvox-icon 'search-miss)
           (message "%s not found " string)))))))

;;;   Highlight tracking:

;; Moving pointer  to the next highlighted portion of the screen:

(defun emacsvox-eterm-pointer-to-next-color-change  (&optional count)
  "Move the eterm pointer to the next color change.
This allows you to move between highlighted regions of the screen.
Optional argument COUNT specifies how many changes to skip."
  (interactive "p")
  
  (setq count (or count 1))
  (let ((current (dtk-get-style emacsvox-eterm-pointer))
        (found nil))
    (save-excursion
      (goto-char emacsvox-eterm-pointer)
      (setq found (text-property-not-all (point) (point-max)
                                         'personality current))
      (cond
       (found (set-marker emacsvox-eterm-pointer found)
              (emacsvox-icon 'large-movement)
              (emacsvox-eterm-speak-pointer-line))
       (t (message "No color change found on the screen "))))))

(defun emacsvox-eterm-pointer-to-previous-color-change  (&optional count)
  "Move the eterm pointer to the next color change.
This allows you to move between highlighted regions of the screen.
Optional argument COUNT specifies how many changes to skip."
  (interactive "p")
  
  (setq count (or count 1))
  (let ((current (dtk-get-style emacsvox-eterm-pointer))
        (found nil))
    (save-excursion
      (goto-char emacsvox-eterm-pointer)
      (setq found (text-property-not-all (point)  term-home-marker
                                         'personality current))
      (cond
       (found (set-marker emacsvox-eterm-pointer found)
              (emacsvox-icon 'large-movement)
              (emacsvox-eterm-speak-pointer-line))
       (t (message "No color change found on the screen "))))))

;;;   reviewing the terminal:
(defvar-local emacsvox-eterm-pointer nil
  "Terminal pointer. Can be moved around to listen to the contents of the
terminal. See commands provided by the emacsvox extension to eterm:
\\{emacsvox-eterm-keymap}
Each term-mode buffer has a buffer local value of this variable. ")
(defvar emacsvox-eterm-review-p nil
  "T if eterm is in review mode.
In review mode, you can move around the terminal and listen to parts of it.
Do not set this variable by hand.
Use \\[emacsvox-eterm-toggle-review].")

(defun emacsvox-eterm-toggle-review ()
  "Toggle state of eterm review.
In review mode, you can move around the terminal and listen to the contents
without sending input to the terminal itself."
  (interactive)
  (cl-declare (special emacsvox-eterm-review-p
                       eterm-char-mode
                       buffer-read-only emacsvox-eterm-keymap term-raw-map))
  (emacsvox-eterm-nuke-cached-info)
  (setq mode-line-process
        '("review"))
  (if eterm-char-mode
      (cond
       (emacsvox-eterm-review-p        ;turn it off
        (message "Returning to terminal character mode ")
        (setq emacsvox-eterm-review-p nil)
        (use-local-map term-raw-map))
       (t                               ; turn it on
        (message "Entering terminal review mode press  q  to return to normal")
        (setq emacsvox-eterm-review-p t)
        (use-local-map emacsvox-eterm-keymap)))
    (message
     "Terminal review should be used when eterm is in character mode "))
  (emacsvox-icon (if emacsvox-eterm-review-p 'on 'off)))

;;;   Cut and paste while reviewing:

(defvar emacsvox-eterm-marker nil
  "Marker used by emacsvox to yank when in eterm review mode.")

(defun emacsvox-eterm-set-marker ()
  "Set Emacsvox eterm marker.
This sets  the emacsvox eterm marker to the position pointed
to by the emacsvox eterm pointer."
  (interactive)
  (cl-declare (special emacsvox-eterm-pointer
                       emacsvox-eterm-marker))
  (let ((coordinates nil))
    (set-marker emacsvox-eterm-marker
                (marker-position emacsvox-eterm-pointer))
    (setq coordinates
          (emacsvox-eterm-position-to-coordinates
           (marker-position emacsvox-eterm-pointer)))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'mark-object)
      (dtk-stop)
      (message "Set eterm mark at row %s column %s"
               (cdr coordinates)
               (car coordinates)))))

(defun emacsvox-eterm-kill-ring-save-region  ()
  "Copy text from terminal to kill ring.
This copies  region delimited by the emacsvox eterm marker
set by command \\[emacsvox-eterm-set-marker] and the
emacsvox eterm pointer."
  (interactive)
  (cl-declare (special emacsvox-eterm-marker
                       emacsvox-eterm-pointer))
  (kill-ring-save (marker-position emacsvox-eterm-marker)
                  (marker-position emacsvox-eterm-pointer))
  (emacsvox-icon 'mark-object)
  (message "Snarfed %s characters "
           (abs (- (marker-position emacsvox-eterm-marker)
                   (marker-position emacsvox-eterm-pointer)))))

(defun emacsvox-eterm-copy-region-to-register  (register)
  "Copy text from terminal to an Emacs REGISTER.
This copies  region delimited by the emacsvox eterm marker
set by command \\[emacsvox-eterm-set-marker] and the
emacsvox eterm pointer to a register."
  (interactive (list (register-read-with-preview "Copy to register: ")))
  (cl-declare (special emacsvox-eterm-marker
                       emacsvox-eterm-pointer))
  (copy-to-register register
                    (marker-position emacsvox-eterm-marker)
                    (marker-position emacsvox-eterm-pointer)
                    nil)
  (emacsvox-icon 'mark-object)
  (message "Snarfed %s characters to register %c "
           (abs (- (marker-position emacsvox-eterm-marker)
                   (marker-position emacsvox-eterm-pointer)))
           register))

(defun emacsvox-eterm-paste-register (register)
  "Paste contents of REGISTER at current location.
If the specified register contains text, then that text is
sent to the terminal as if it were typed by the user."
  (interactive (list (register-read-with-preview "Copy to register: ")))
  (let ((contents (get-register register)))
    (cond
     ((stringp contents)
      (term-send-raw-string contents)
      (emacsvox-icon 'yank-object))
     (t (error "Register %c does not contain text"
               register)))))

;;;   Defining and speaking terminal windows:

;; A window structure is of the form
;; [column row right-stretch left-stretch ]

(defun emacsvox-eterm-make-window (top-left bottom-right
                                            right-stretch left-stretch)
  (let ((win (make-vector 4  nil)))
    (aset win 0 top-left)
    (aset win 1 bottom-right)
    (aset win 2 right-stretch)
    (aset win 3 left-stretch)
    win))

(defun emacsvox-eterm-window-top-left (w) (aref w 0))
(defun emacsvox-eterm-window-bottom-right (w) (aref w 1))
(defun emacsvox-eterm-window-right-stretch (w) (aref w 2))
(defun emacsvox-eterm-window-left-stretch  (w) (aref w 3))

(defun  emacsvox-eterm-coordinate-within-window-p (coordinate id)
  "Predicate to test if COORDINATE is within window.
Argument ID specifies the window."
  (when (and coordinate id)
    (let*  ((window  (emacsvox-eterm-get-window id))
            (row (cdr coordinate))
            (column (car coordinate))
            (left-stretch (emacsvox-eterm-window-left-stretch window))
            (right-stretch (emacsvox-eterm-window-right-stretch window))
            (top-left-row (cdr
                           (emacsvox-eterm-window-top-left window)))
            (top-left-column (car
                              (emacsvox-eterm-window-top-left window)))
            (bottom-right-row (cdr
                               (emacsvox-eterm-window-bottom-right window)))
            (bottom-right-column
             (car (emacsvox-eterm-window-bottom-right window))))
      (not
       (or  (< row top-left-row)
            (> row bottom-right-row)
            (and (not left-stretch) (< column top-left-column))
            (and (not right-stretch) (> column bottom-right-column)))))))

;; Translate a screen position to a buffer position

(defun emacsvox-eterm-coordinates-to-position (coordinates)
  "Translate screen COORDINATES to buffer position.
This translate  screen coordinates specified
as a cons cell (column .  row) to a buffer position in the eterm buffer"
  
  (let ((column (car coordinates))
        (row (cdr coordinates)))
    (save-excursion
      (save-restriction
        (emacsvox-eterm-nuke-cached-info)
        (narrow-to-region term-home-marker (point-max))
        (term-goto row column)
        (emacsvox-eterm-nuke-cached-info)
        (point)))))

;; Translate buffer position to screen coordinates.
;; returns a cons cell (column . row)
(defun emacsvox-eterm-position-to-coordinates (pos)
  "Translate a buffer POS in the eterm buffer to screen coordinates."
  
  (save-excursion
    (save-restriction
      (narrow-to-region term-home-marker (point-max))
      (goto-char pos)
      (emacsvox-eterm-nuke-cached-info)
      (let ((coordinates
             (cons
              (term-current-column)
              (term-current-row))))
        (emacsvox-eterm-nuke-cached-info)
        coordinates))))

;; return contents of a term window
(defun emacsvox-eterm-return-window-contents (eterm-window)
  "Return  the contents of a window as a string.
Argument ETERM-WINDOW specifies a predefined eterm window."
  
  (let ((start nil)
        (end nil)
        (right-stretch (emacsvox-eterm-window-right-stretch eterm-window))
        (left-stretch (emacsvox-eterm-window-left-stretch eterm-window))
        (contents nil)
        (top-left
         (emacsvox-eterm-window-top-left eterm-window))
        (bottom-right
         (emacsvox-eterm-window-bottom-right eterm-window)))
    (save-excursion
      (save-restriction
        (narrow-to-region term-home-marker (point-max))
        (setq start (emacsvox-eterm-coordinates-to-position top-left)
              end (emacsvox-eterm-coordinates-to-position bottom-right))
        (setq contents
              (cond
               ((and left-stretch right-stretch) ;; stretchable window
                (goto-char start)
                (beginning-of-line)
                (setq start (point))
                (goto-char end)
                (end-of-line)
                (buffer-substring start (point)))
               (right-stretch
                (let  ((lines nil))
                  (goto-char start)
                  (while (< start end)
                    (end-of-line)
                    (push
                     (buffer-substring start (point))
                     lines)
                    (forward-line 1)
                    (forward-line 0)
                    (forward-char (car top-left))
                    (setq start (point)))
                  (setq lines (nreverse lines))
                  (mapconcat 'identity
                             lines " \n ")))
               (left-stretch
                (let  ((lines nil))
                  (goto-char start)
                  (forward-line 0)
                  (setq start (point))
                  (while (< start end)
                    (forward-char (car bottom-right))
                    (push
                     (buffer-substring start (point))
                     lines)
                    (forward-line 1)
                    (forward-line 0)

                    (setq start (point)))
                  (setq lines (nreverse lines))
                  (mapconcat 'identity
                             lines " \n ")))
               (t (mapconcat 'identity
                             (extract-rectangle start end)
                             " \n "))))
        (emacsvox-eterm-nuke-cached-info)
        contents))))

(defvar emacsvox-eterm-maximum-windows 20
  "Variable specifying how many windows can be defined.")

(defvar emacsvox-eterm-window-table
  (make-vector emacsvox-eterm-maximum-windows  nil)
  "Vector of window positions.
A terminal window is recorded by the  positions of its top left
and bottom right.")

(defun emacsvox-eterm-record-window  (window-id
                                      top-left bottom-right
                                      &optional right-stretch left-stretch)
  "Insert this window definition into the table of terminal windows.
Argument WINDOW-ID specifies the window.
Argument TOP-LEFT  specifies top-left of window.
Argument BOTTOM-RIGHT  specifies bottom right of window.
Optional argument RIGHT-STRETCH  specifies if the window stretches to the right.
Optional argument LEFT-STRETCH  specifies if the window stretches to the left."
  (cl-declare (special emacsvox-eterm-window-table
                       emacsvox-eterm-maximum-windows))
  (cl-assert (< window-id emacsvox-eterm-maximum-windows)  t
             "Your installation of Emacsvox only supports %d windows"
             emacsvox-eterm-maximum-windows)
  (aset emacsvox-eterm-window-table window-id
        (emacsvox-eterm-make-window top-left bottom-right
                                    right-stretch left-stretch)))

(defun emacsvox-eterm-get-window (id)
  "Retrieve a window.
Argument ID specifies window whose definition is being requested."
  (cl-declare (special emacsvox-eterm-window-table
                       emacsvox-eterm-maximum-windows))
  (cl-assert (<  id emacsvox-eterm-maximum-windows)  t
             "Your installation of Emacsvox only supports %d windows"
             emacsvox-eterm-maximum-windows)
  (or (aref emacsvox-eterm-window-table  id)
      (error "Window %s is not defined" id)))

(defun emacsvox-eterm-define-window (id)
  "Prompt for a window ID.
The window is then define to be
the rectangle delimited by point and eterm mark.  This is to
be used when emacsvox is set to review mode inside an
eterm."

  (interactive "nDefine window: ")
  (cl-declare (special emacsvox-eterm-marker emacsvox-eterm-pointer
                       emacsvox-eterm-maximum-windows))
  (cl-assert (<  id emacsvox-eterm-maximum-windows)  t
             "Your installation of Emacsvox only supports %d windows"
             emacsvox-eterm-maximum-windows)
  (let  ((top-left
          (emacsvox-eterm-position-to-coordinates
           (marker-position emacsvox-eterm-marker)))
         (bottom-right
          (emacsvox-eterm-position-to-coordinates (marker-position
                                                   emacsvox-eterm-pointer)))
         (right-stretch
          (y-or-n-p "Should the window stretch to the right as required "))
         (left-stretch
          (y-or-n-p "Should the window stretch to the left as required ")))
    (emacsvox-eterm-record-window  id top-left bottom-right
                                   right-stretch left-stretch)
    (message "Defined %s window %s
with top left at %s %s
and bottom right at %s %s"
             (cond
              ((and left-stretch right-stretch)
               " stretchable ")
              (left-stretch " left stretchable")
              (right-stretch " right stretchable ")
              (t " "))
             id (cdr top-left) (car top-left)
             (cdr bottom-right) (car bottom-right))))

(defun emacsvox-eterm-speak-window (id)
  "Speak an eterm window.
Argument ID specifies the window."
  (interactive "nSpeak window")
  (cl-declare (special emacsvox-eterm-maximum-windows
                       term-home-marker))
  (cl-assert (<  id emacsvox-eterm-maximum-windows)  t
             "Your installation of Emacsvox only supports %d windows"
             emacsvox-eterm-maximum-windows)
  (save-excursion
    (save-restriction
      (narrow-to-region term-home-marker (point-max))
      (dtk-speak
       (emacsvox-eterm-return-window-contents
        (emacsvox-eterm-get-window id))))))

(defun emacsvox-eterm-yank-window (id)
  "Yank contents of  an eterm window at point."
  (interactive "nYank contents of window")
  (cl-declare (special emacsvox-eterm-maximum-windows
                       term-home-marker))
  (cl-assert (<  id emacsvox-eterm-maximum-windows)  t
             "Your installation of Emacsvox only supports %d windows"
             emacsvox-eterm-maximum-windows)
  (insert
   (save-excursion
     (save-restriction
       (narrow-to-region term-home-marker (point-max))
       (emacsvox-eterm-return-window-contents
        (emacsvox-eterm-get-window id)))))
  (emacsvox-icon 'yank-object)
  (message "Yanked contents of window %s at point" id))

(defun emacsvox-eterm-describe-window  (id)
  "Describe an eterm  window.
Description indicates eterm window coordinates and whether it is stretchable"
  (interactive "nDescribe window: ")
  (let* ((window (emacsvox-eterm-get-window id))
         (top-left (emacsvox-eterm-window-top-left window))
         (bottom-right (emacsvox-eterm-window-bottom-right window))
         (right-stretch (emacsvox-eterm-window-right-stretch window))
         (left-stretch (emacsvox-eterm-window-left-stretch window)))
    (message " %s window %s
has  top left at %s %s
and bottom right at %s %s"
             (cond
              ((and left-stretch right-stretch)
               " stretchable ")
              (left-stretch " left stretchable")
              (right-stretch " right stretchable ")
              (t " "))
             id (cdr top-left) (car top-left)
             (cdr bottom-right) (car bottom-right))))

(defvar emacsvox-eterm-focus-window nil
  "Current window that emacsvox eterm focuses on")
(make-variable-buffer-local 'emacsvox-eterm-filter-window)

(defun emacsvox-eterm-set-focus-window (flag)
  "Prompt for the id of a predefined window,
and set the `focus' window to it.
Non-nil interactive prefix arg `unsets' the focus window;
this is equivalent to having the entire terminal as the focus window (this is
what eterm starts up with).
Setting the focus window results in emacsvox  monitoring screen
and speaking that window upon seeing screen activity."
  (interactive "P")
  
  (let  ((window-id nil))
    (cond
     (flag (setq emacsvox-eterm-focus-window nil)
           (message "Emacsvox eterm focus set to entire screen "))
     (t
      (setq window-id
            (read-minibuffer  "Specify eterm window to focus on "))
      (cl-assert (numberp window-id) t
                 "Please specify a valid window id, a
non-negative integer ")
      (cond
       ((= 0 window-id)
        (message "Unset focus window.")
        (setq emacsvox-eterm-focus-window nil))
       (t
        (setq emacsvox-eterm-focus-window window-id)
        (message "Set emacsvox eterm focus window  to %d "
                 window-id)))))))

(defvar emacsvox-eterm-filter-window nil
  "Window id used to filter screen activity.")

(make-variable-buffer-local 'emacsvox-eterm-filter-window)

(defun emacsvox-eterm-set-filter-window (flag)
  "Prompt for the id of a predefined window,
and set the `filter' window to it.
Non-nil interactive prefix arg `unsets' the filter window;
this is equivalent to having the entire terminal as the filter window (this is
what eterm starts up with).
Setting the filter window results in emacsvox  only monitoring screen
activity within the filter window."
  (interactive "P")
  
  (let  ((window-id nil))
    (cond
     (flag (setq emacsvox-eterm-filter-window nil)
           (message "Emacsvox eterm filter set to entire screen "))
     (t
      (setq window-id
            (read-minibuffer  "Specify eterm window to filter on "))
      (cl-assert (numberp window-id) t
                 "Please specify a valid window id, a non-negative integer ")
      (cond
       ((= 0 window-id)
        (message "Unset filter window.")
        (setq emacsvox-eterm-filter-window nil))
       (t
        (setq emacsvox-eterm-filter-window window-id)
        (message "Set emacsvox eterm filter window  to %d " window-id)))))))

(defun emacsvox-eterm-toggle-focus-window ()
  "Toggle active state of focus window."
  (interactive)
  
  (if emacsvox-eterm-focus-window
      (setq emacsvox-eterm-focus-window nil)
    (setq emacsvox-eterm-focus-window 1))
  (dtk-stop)
  (emacsvox-icon (if emacsvox-eterm-focus-window
                     'on 'off)))

(defun emacsvox-eterm-toggle-filter-window ()
  "Toggle active state of filter window."
  (interactive)
  
  (if emacsvox-eterm-filter-window
      (setq emacsvox-eterm-filter-window nil)
    (setq emacsvox-eterm-filter-window 1))
  (dtk-stop)
  (emacsvox-icon (if emacsvox-eterm-filter-window
                     'on 'off)))

(defun emacsvox-eterm-speak-predefined-window ()
  "Speak a predefined eterm window between 1 and 10."
  (interactive)
  (emacsvox-eterm-speak-window
   (condition-case nil
       (read (format "%c" last-input-event))
     (error nil))))

;;;   advice emulator

(defvar eterm-current-personality nil
  "Current personality for eterm. ")

(defun ems--term-before (&rest _)
  "Single window please!" (delete-other-windows))

(advice-add 'term :before #'ems--term-before)

(defun ems--ansi-term-before (&rest _)
  "Single window please!" (delete-other-windows))

(advice-add 'ansi-term :before #'ems--ansi-term-before)

(defun ems--term-mode-after (&rest _)
  "Customize eterm to work with Emacsvox.\nAdditional commands provided by emacsvox under eterm are\navailable with the prefix emacsvox-eterm-prefix and are listed below:\n\\{emacsvox-eterm-keymap}"
  
  (emacsvox-eterm-setup-keys) (emacsvox-eterm-setup-raw-keys)
  (make-local-variable 'eterm-current-personality)
  (setq eterm-current-personality emacsvox-eterm-default-personality)
  (modify-syntax-entry 10 ">")
  (make-local-variable 'emacsvox-eterm-pointer)
  (setq emacsvox-eterm-pointer (copy-marker (point)))
  (make-local-variable 'emacsvox-eterm-marker)
  (setq emacsvox-eterm-marker (copy-marker (point))))

(advice-add 'term-mode :after #'ems--term-mode-after)

(defvar emacsvox-eterm-row nil
  "Record the eterm row last spoken")

(defvar emacsvox-eterm-column nil
  "Record the column last spoken")

(defvar emacsvox-eterm-marker nil
  "Mark set in an eterm buffer. Used to cut and paste from the terminal.")

(defvar emacsvox-eterm-autospeak t
  "Tells if eterm output is automatically spoken when in line mode.
Use emacsvox-toggle-eterm-autospeak bound to
\\[emacsvox-toggle-eterm-autospeak] to set this.")

(make-variable-buffer-local 'emacsvox-eterm-autospeak)

(ems-generate-switcher 'emacsvox-toggle-eterm-autospeak
                       'emacsvox-eterm-autospeak
                       "Toggle state of eterm autospeak.
When eterm autospeak is turned on and the terminal is in line
mode, all output to the terminal is automatically spoken.
Interactive prefix arg means toggle the global default value, and
then set the current local value to the result.")

(defvar eterm-line-mode nil
  "T if eterm is in line mode.")

(defvar eterm-char-mode t
  "Flag indicating if eterm is in char mode.")

(defvar emacsvox-eterm-pointer-mode t
  "If T then the emacsvox pointer will not track the terminal cursor.
Do not set this by hand.
Use emacsvox-eterm-toggle-pointer-mode bound to
\\[emacsvox-eterm-toggle-pointer-mode].")

(defun emacsvox-eterm-activity-window (window)
  "T if terminal activity within bounds of window."
  (emacsvox-eterm-coordinate-within-window-p
   (cons (term-current-column) (term-current-row))
   window))

(defun ems--term-emulate-terminal-around (orig-fun &rest args)
  "Record position, emulate, then speak what happened.\nAlso keep track of terminal highlighting etc.  Feedback is\nlimited to current window If a `current window` is set (see\ncommand emacsvox-eterm-set-filter-window bound to\n\\[emacsvox-eterm-set-filter-window].  How output is spoken\ndepends on whether the terminal is in character or line mode.\n\nWhen in character mode, output is spoken like off a real\nterminal.  When in line mode, behavior resembles that of comint\nmode; i.e. you hear the output if emacsvox-eterm-autospeak is t.\nDo not set this variable by hand: See command\nemacsvox-toggle-eterm-autospeak bound to\n\\[emacsvox-toggle-eterm-autospeak]"
  (cl-declare
   (special emacsvox-eterm-row emacsvox-eterm-column eterm-line-mode
            eterm-char-mode emacsvox-eterm-filter-window
            emacsvox-eterm-pointer-mode emacsvox-eterm-autospeak))
  (when (process-live-p (ad-get-arg 0))
    (let
        ((emacsvox-eterm-window
          (get-buffer-window (process-buffer (ad-get-arg 0))))
         (emacsvox-eterm-row (term-current-row))
         (emacsvox-eterm-column (term-current-column))
         (current-char (preceding-char)) (new-row nil)
         (new-column nil) (old-point (point))
         (dtk-stop-immediately (not eterm-line-mode))
         (inhibit-read-only t))
      (apply orig-fun args)
      (setq new-row (term-current-row) new-column
            (term-current-column))
      (when
          (and emacsvox-eterm-autospeak
               (window-live-p emacsvox-eterm-window)
               (or (not emacsvox-eterm-focus-window)
                   (emacsvox-eterm-activity-window
                    emacsvox-eterm-focus-window)
                   (emacsvox-eterm-activity-window
                    emacsvox-eterm-filter-window)))
        (cond
         ((and eterm-char-mode emacsvox-eterm-filter-window
               (not
                (and
                 (emacsvox-eterm-coordinate-within-window-p
                  (cons new-column new-row)
                  emacsvox-eterm-filter-window)
                 (emacsvox-eterm-coordinate-within-window-p
                  (cons (term-current-column) (term-current-row))
                  emacsvox-eterm-filter-window))))
          nil)
         ((and eterm-line-mode emacsvox-eterm-autospeak)
          (setq dtk-stop-immediately nil)
          (condition-case nil
              (emacsvox-speak-region (1- old-point) (1- (point)))
            (error nil)))
         (emacsvox-eterm-focus-window
          (emacsvox-eterm-speak-window emacsvox-eterm-focus-window))
         ((and
           (or (eq last-command-event 127)
               (eq last-command-event 'backspace))
           (= new-row emacsvox-eterm-row)
           (= -1 (- new-column emacsvox-eterm-column)) current-char)
          (emacsvox-speak-this-char current-char) (delete-char 1)
          (dtk-tone-deletion))
         ((and (= new-row emacsvox-eterm-row)
               (= 1 (- new-column emacsvox-eterm-column)))
          (if (eq 32 last-command-event)
              (save-excursion
                (backward-char 2) (emacsvox-speak-word nil))
            (emacsvox-speak-this-char (preceding-char))))
         ((and (= new-row emacsvox-eterm-row)
               (= 1 (abs (- new-column emacsvox-eterm-column))))
          (emacsvox-speak-this-char (following-char)))
         ((= emacsvox-eterm-row new-row)
          (if (= 32 (following-char))
              (save-excursion (forward-char 1) (emacsvox-speak-word))
            (emacsvox-speak-word)))
         (t (emacsvox-speak-line)))
        (when
            (and (not emacsvox-eterm-pointer-mode)
                 emacsvox-eterm-pointer)
          (emacsvox-eterm-pointer-to-cursor))))))

(advice-add 'term-emulate-terminal :around
            #'ems--term-emulate-terminal-around)

(ems-generate-switcher 'emacsvox-eterm-toggle-pointer-mode
                       'emacsvox-eterm-pointer-mode
                       "Toggle emacsvox eterm pointer mode.
With optional interactive prefix  arg, turn it on.
When emacsvox eterm is in pointer mode, the eterm read pointer
stays where it is rather than automatically moving to the terminal cursor when
there is terminal activity.")

(defun ems--term-dynamic-complete-around (orig-fun &rest args)
  "Speak the completion. "
  (let ((result (apply orig-fun args)))
    
    (let ((saved-point (point)))
      (apply orig-fun args)
      (unless (= saved-point (point))
        (emacsvox-speak-region saved-point (point)))
      result)
    result))

(advice-add 'term-dynamic-complete :around
            #'ems--term-dynamic-complete-around)

(voice-setup-add-map
 '(
   (term-underline voice-brighten-medium)
   ))

(defun ems--term-line-mode-after (&rest _)
  "Announce that you entered line mode. "
  (make-local-variable 'eterm-line-mode)
  (setq mode-line-process '("line"))
  (setq eterm-char-mode nil eterm-line-mode t)
  (when (ems-interactive-p) (dtk-speak "Terminal line mode ")))

(advice-add 'term-line-mode :after #'ems--term-line-mode-after)

(defun ems--term-char-mode-after (&rest _)
  "Announce you entered character mode. "
  (setq mode-line-process '("char"))
  (setq eterm-char-mode t eterm-line-mode nil)
  (emacsvox-eterm-setup-raw-keys)
  (when (ems-interactive-p) (dtk-speak "Terminal character mode ")))

(advice-add 'term-char-mode :after #'ems--term-char-mode-after)

;;;   Advice term functions 

(defun ems--term-next-input-after (&rest _)
  "Speak the line. " (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'term-next-input :after #'ems--term-next-input-after)

(defun ems--term-next-matching-input-after (&rest _)
  "Speak the line. " (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'term-next-matching-input :after
            #'ems--term-next-matching-input-after)

(defun ems--term-previous-input-after (&rest _)
  "Speak the line. " (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'term-previous-input :after
            #'ems--term-previous-input-after)

(defun ems--term-previous-matching-input-after (&rest _)
  "Speak the line. " (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'term-previous-matching-input :after
            #'ems--term-previous-matching-input-after)

(defun ems--term-send-input-after (&rest _)
  "Flush any ongoing speech" (when (ems-interactive-p) (dtk-stop)))

(advice-add 'term-send-input :after #'ems--term-send-input-after)

(defun ems--term-previous-prompt-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'item)
    (if (eolp) (emacsvox-speak-line) (emacsvox-speak-line 1))))

(advice-add 'term-previous-prompt :after
            #'ems--term-previous-prompt-after)

(defun ems--term-next-prompt-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'item)
    (if (eolp) (emacsvox-speak-line) (emacsvox-speak-line 1))))

(advice-add 'term-next-prompt :after #'ems--term-next-prompt-after)

(defun ems--term-dynamic-list-input-ring-after (&rest _)
  "speak"
  (message "Switch to the other window to browse the input history "))

(advice-add 'term-dynamic-list-input-ring :after
            #'ems--term-dynamic-list-input-ring-after)

(defun ems--term-kill-output-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (message "Nuked output of last command ")))

(advice-add 'term-kill-output :after #'ems--term-kill-output-after)

(defun ems--term-quit-subjob-after (&rest _)
  "speak"
  (when (ems-interactive-p) (message "Sent quit signal to subjob ")))

(advice-add 'term-quit-subjob :after #'ems--term-quit-subjob-after)

(defun ems--term-stop-subjob-after (&rest _)
  "speak" (when (ems-interactive-p) (message "Stopped the subjob")))

(advice-add 'term-stop-subjob :after #'ems--term-stop-subjob-after)

(defun ems--term-interrupt-subjob-after (&rest _)
  "speak"
  (when (ems-interactive-p) (message "Interrupted  the subjob")))

(advice-add 'term-interrupt-subjob :after
            #'ems--term-interrupt-subjob-after)

(defun ems--term-kill-input-before (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (let
        ((pmark (process-mark (get-buffer-process (current-buffer)))))
      (when (> (point) (marker-position pmark))
        (emacsvox-icon 'delete-object)
        (emacsvox-speak-region pmark (point))))))

(advice-add 'term-kill-input :before #'ems--term-kill-input-before)

(defun ems--term-dynamic-list-filename-completions-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (message
     "Switch to the completions window to browse the possible\ncompletions for filename at point")))

(advice-add 'term-dynamic-list-filename-completions :after
            #'ems--term-dynamic-list-filename-completions-after)

(provide 'emacsvox-eterm)

