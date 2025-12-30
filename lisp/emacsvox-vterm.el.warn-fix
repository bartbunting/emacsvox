;;; emacsvox-vterm.el --- Speech-enable VTERM  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable VTERM An Emacs Interface to vterm
;; Keywords: Emacsvox,  Audio Desktop vterm
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNVTERM FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; VTERM == vterm using native vterm library
;; @subsection Usage
;; @itemize
;; @item Turn on @code{emacsvox-comint-autospeak} for using  the
;; shell.
;; @item Turn off @code{emacsvox-comint-autospeak} when using
;; full-screen ncurses apps like @code{vi}.
;; @item Use @code{vterm-copy-mode} to review the contents of the
;; terminal @MDash{} @kbd{C-c C-t}.
;; @end itemize
;; 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (vterm-color-black voice-bolden)
   (vterm-color-blue voice-brighten)
   (vterm-color-cyan voice-smoothen)
   (vterm-color-default 'paul)
   (vterm-color-green voice-lighten)
   (vterm-color-inverse-video voice-bolden)
   (vterm-color-magenta voice-annotate)
   (vterm-color-underline voice-monotone-extra)
   (vterm-color-white 'paul)
   (vterm-color-yellow voice-animate)))

;;;  Interactive Commands:


(defun ems--vterm-clear-after (&rest _)
  "speak." (emacsvox-vterm-snapshot)
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (message "Cleared screen")))


(advice-add 'vterm-clear :after #'ems--vterm-clear-after)





(defun ems--vterm-clear-scrollback-after (&rest _)
  "speak." (emacsvox-vterm-snapshot)
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (message "Cleared scrollback")))


(advice-add 'vterm-clear-scrollback :after
	    #'ems--vterm-clear-scrollback-after)





(defun ems--vterm-copy-mode-done-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))


(advice-add 'vterm-copy-mode-done :after
	    #'ems--vterm-copy-mode-done-after)




(with-eval-after-load "vterm"
  (cl-declaim (special vterm-mode-map vterm-copy-mode-map))
  (define-key vterm-mode-map (kbd "C-e")
              'emacsvox-keymap)
  (define-key vterm-copy-mode-map (kbd "C-e") 'emacsvox-keymap))


(defun ems--vterm-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))


(advice-add 'vterm :after #'ems--vterm-after)




(cl-loop
 for f in
 '(vterm-end-of-line vterm-beginning-of-line)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))


(defun ems--vterm-reset-cursor-point-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))


(advice-add 'vterm-reset-cursor-point :after
	    #'ems--vterm-reset-cursor-point-after)





(defun ems--vterm-send-return-after (&rest _)
  "speak." (emacsvox-vterm-snapshot))


(advice-add 'vterm-send-return :after #'ems--vterm-send-return-after)




(cl-loop
 for f in
 '(vterm-previous-prompt vterm-next-prompt)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

;;; Speech-enable term emulation:

;; This sends what you typed to the term process.  Handle terminal
;; emulation logic here, as per term-emulate-term in emacsvox-eterm.
;; Simpler because for now, we dont implement sub-windows etc.
;; ad-do-it doesn't update for native module functions?
;; tried with before/after advice pair, and we still dont see the
;; updates, so  using before advice to record state,
;; and an after advice on vterm--redraw to implement the spoken
;; feedback loop.

(defvar-local ems--vterm-row nil
  "Cache row.")

(defvar-local ems--vterm-column nil
  "Cache vterm column.")

(defvar-local ems--vterm-char nil
  "Cache current char.")

(defvar-local ems--vterm-opoint nil
  "Cache current point.")

(defsubst emacsvox-vterm-snapshot ()
  "Snapshot VTerm state."
  (cl-declare (special ems--vterm-char ems--vterm-opoint
                       ems--vterm-row ems--vterm-column))
  (setq ems--vterm-row(1+ (count-lines (point-min) (point))) ;;; line number
        ems--vterm-column (current-column) ;;; column number
        ems--vterm-opoint (point)
        ems--vterm-char (preceding-char))
  )


(defun ems--vterm--flush-output-before (&rest _)
  "Cache state before input event is processed."
  (emacsvox-vterm-snapshot))


(advice-add 'vterm--flush-output :before
	    #'ems--vterm--flush-output-before)




;; speech-enable term update loop, using previously cached state.
(defvar emacsvox-vterm-debug nil
  "Debug flag")


(defun ems--vterm--redraw-after (&rest _)
  "Speech-enable term emulation."
  (let
      ((current-char ems--vterm-char) (opoint ems--vterm-opoint)
       (row ems--vterm-row) (column ems--vterm-column)
       (new-row (1+ (count-lines (point-min) (point))))
       (new-column (current-column)))
    (ems-with-messages-silenced
     (message "Event: %c r: %d c: %d new-row: %d new-col: %d char: %c"
	      last-command-event row column new-row new-column
	      current-char))
    (cond
     ((and (memq last-command-event '(127 backspace)) (= new-row row)
	   (= -1 (- new-column column)))
      (dtk-tone-deletion) (emacsvox-speak-this-char current-char))
     ((and (= new-row row) (= 1 (- new-column column)))
      (ems-with-messages-silenced (message "char insert"))
      (if (eq 32 last-command-event)
	  (save-excursion
	    (backward-char 2) (emacsvox-speak-word nil))
	(emacsvox-speak-this-char (preceding-char))))
     ((and (= new-row row) (= 1 (abs (- new-column column))))
      (ems-with-messages-silenced (message "horizontal char motion"))
      (emacsvox-speak-this-char (following-char)))
     ((= row new-row)
      (ems-with-messages-silenced (message "left/right motion"))
      (if (= 32 (following-char))
	  (save-excursion (forward-char 1) (emacsvox-speak-word))
	(emacsvox-speak-word)))
     (t
      (if emacsvox-comint-autospeak
	  (let ((dtk-stop-immediately nil))
	    (dtk-speak
	     (string-trim
	      (ansi-color-filter-apply
	       (save-excursion
		 (beginning-of-line)
		 (buffer-substring (1+ opoint) (point)))))))
	(emacsvox-speak-line))))))


(advice-add 'vterm--redraw :after #'ems--vterm--redraw-after)




(provide 'emacsvox-vterm)
;;;  end of file

