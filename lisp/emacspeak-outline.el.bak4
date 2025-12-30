;;; emacspeak-outline.el --- Speech enable Outline -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacspeak extensions for outline-mode
;; Keywords:emacspeak, audio interface to emacs Outlines
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |raman@crl.dec.com
;; A speech interface to Emacs |
;; $date: $ |
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacspeak
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



;;; Commentary:

;; Provide additional advice to outline-mode

;;; Code:

;;;  requires

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)
(require 'outline)

;;;   Navigating through an outline:

(cl-loop
 for f in 
 '(
   outline-next-heading outline-previous-heading outline-next-preface
   outline-next-visible-heading outline-previous-visible-heading
   outline-back-to-heading outline-up-heading
   outline-backward-same-level outline-forward-same-level)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacspeak-icon 'section)
       (emacspeak-speak-line)))))

;;; outline-flag-region:

;; Handle outline hide/show directly here --- rather than relying on
;;overlay advice alone.

(defvar ems--voiceify-overlays)


(defun ems--outline-flag-region-around (orig-fun &rest args)
  "Reflect hide/show via property invisible as well"
  (let
      ((ems--voiceify-overlays nil) (beg (ad-get-arg 0))
       (end (ad-get-arg 1)) (inhibit-read-only t))
    (apply orig-fun args) (when (zerop beg) (setq beg (point-min)))
    (with-silent-modifications
      (put-text-property beg end 'invisible
			 (if (ad-get-arg 2) 'outline nil)))))


(advice-add 'outline-flag-region :around
	    #'ems--outline-flag-region-around)




;;; Misc Commands:

(cl-loop
 for f in 
 '(outline-insert-heading outline-cycle-buffer outline-cycle)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacspeak-icon 'open-object)
       (emacspeak-speak-line)))))

;;;   Hiding and showing subtrees


(defun ems--outline-show-only-headings-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid the body directly following this heading")))


(advice-add 'outline-show-only-headings :after
	    #'ems--outline-show-only-headings-after)





(defun ems--outline-hide-entry-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid the body directly following this heading")))


(advice-add 'outline-hide-entry :after #'ems--outline-hide-entry-after)





(defun ems--outline-show-entry-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object)
    (message "Exposed body directly following current heading")))


(advice-add 'outline-show-entry :after #'ems--outline-show-entry-after)





(defun ems--outline-hide-body-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid all of the buffer except for header lines")))


(advice-add 'outline-hide-body :after #'ems--outline-hide-body-after)





(defun ems--outline-show-all-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object)
    (message "Exposed all text in the buffer")))


(advice-add 'outline-show-all :after #'ems--outline-show-all-after)





(defun ems--outline-hide-subtree-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid everything at deeper levels from current heading")))


(advice-add 'outline-hide-subtree :after
	    #'ems--outline-hide-subtree-after)





(defun ems--outline-hide-leaves-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid all of the body at deeper levels")))


(advice-add 'outline-hide-leaves :after
	    #'ems--outline-hide-leaves-after)





(defun ems--outline-show-subtree-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object)
    (message
     "Exposed everything after current heading at deeper levels")))


(advice-add 'outline-show-subtree :after
	    #'ems--outline-show-subtree-after)





(defun ems--outline-hide-sublevels-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid everything except the top  %s levels" (ad-get-arg 0))))


(advice-add 'outline-hide-sublevels :after
	    #'ems--outline-hide-sublevels-after)





(defun ems--outline-hide-other-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object)
    (message "Hid everything except current body and parent headings")))


(advice-add 'outline-hide-other :after #'ems--outline-hide-other-after)





(defun ems--outline-show-branches-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object)
    (message
     "Exposed all subheadings while leaving their bodies hidden")))


(advice-add 'outline-show-branches :after
	    #'ems--outline-show-branches-after)





(defun ems--outline-show-children-after (&rest _)
  "Produce an auditory icon"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object)
    (message "Exposed subheadings below current level")))


(advice-add 'outline-show-children :after
	    #'ems--outline-show-children-after)




;;;   Interactive speaking of sections

(defvar emacspeak-outline-dont-query-before-speaking t
  "Option to control prompts when speaking  outline sections.")

(defun emacspeak-outline-speak-heading (what direction)
  "Function used by all interactive section speaking
commands. "
  (cl-declare (special emacspeak-outline-query-before-speaking))
  (let ((start nil)
        (end nil))
    (funcall what  direction)
    (setq start (point))
    (save-excursion
      (condition-case nil
          (progn
            (forward-line 1)
            (funcall what 1)
            (setq end (point)))
        (error (setq end (point-max)))))
    (when (or  emacspeak-outline-dont-query-before-speaking
               (y-or-n-p
                (format  "Speak %s lines from section %s"
                         (count-lines start end) (ems--this-line))))
      (emacspeak-speak-region start end))))

(defun emacspeak-outline-speak-next-heading ()
  "Analogous to outline-next-visible-heading,
except that the outline section is  spoken"
  (interactive)
  (emacspeak-icon 'section)
  (emacspeak-outline-speak-heading 'outline-next-visible-heading 1))

(defun emacspeak-outline-speak-previous-heading ()
  "Analogous to outline-previous-visible-heading,
except that the outline section is  spoken"
  (interactive)
  (emacspeak-icon 'section)
  (emacspeak-outline-speak-heading 'outline-next-visible-heading -1))

(defun emacspeak-outline-speak-forward-heading ()
  "Analogous to outline-forward-same-level,
except that the outline section is  spoken"
  (interactive)
  (emacspeak-icon 'section)
  (emacspeak-outline-speak-heading 'outline-forward-same-level 1))

(defun emacspeak-outline-speak-backward-heading ()
  "Analogous to outline-backward-same-level
except that the outline section is  spoken"
  (interactive)
  (emacspeak-icon 'section)
  (forward-line -1)
  (emacspeak-outline-speak-heading 'outline-forward-same-level -1))

(defun emacspeak-outline-speak-this-heading ()
  "Speak current outline section starting from point"
  (interactive)
  (emacspeak-icon 'select-object)
  (let ((start (point))
        (end nil))
    (save-excursion
      (condition-case nil
          (progn
            (outline-next-visible-heading 1)
            (setq end (point)))
        (error (setq end (point-max)))))
    (and
     (or emacspeak-outline-dont-query-before-speaking
         (y-or-n-p
          (format "Speak %s lines from section %s"
                  (count-lines start end) (ems--this-line))))
     (emacspeak-speak-region start end))))

;;;  bind these in outline mode

(defun emacspeak-outline-setup-keys ()
  "Bind keys in outline minor mode map"
  (cl-declare (special outline-mode-prefix-map
                       outline-navigation-repeat-map))
  (cl-loop
   for map in
   (if (and (bound-and-true-p outline-navigation-repeat-map)
            (keymapp outline-navigation-repeat-map))
       (list outline-mode-prefix-map outline-navigation-repeat-map)
     (list outline-mode-prefix-map ))
   do
   (define-key map "j" 'outline-next-visible-heading)
   (define-key map "k" 'outline-previous-visible-heading)
   (define-key map "p" 'emacspeak-outline-speak-previous-heading)
   (define-key map "n" 'emacspeak-outline-speak-next-heading)
   (define-key map "b" 'emacspeak-outline-speak-backward-heading)
   (define-key map "f" 'emacspeak-outline-speak-forward-heading)
   (define-key map " " 'emacspeak-outline-speak-this-heading))
  
  (mapc
   #'(lambda (cmd)
       (put cmd 'repeat-map 'outline-navigation-repeat-map))
   '(emacspeak-outline-speak-next-heading
     emacspeak-outline-speak-backward-heading
     emacspeak-outline-speak-forward-heading
     emacspeak-outline-speak-this-heading)))

(add-hook 'outline-mode-hook 'emacspeak-outline-setup-keys)
(add-hook 'outline-minor-mode-hook 'emacspeak-outline-setup-keys)

;;;  Personalities (
(voice-setup-add-map
 '(
   (outline-1 voice-bolden)
   (outline-2 voice-brighten)
   (outline-3 voice-lighten)
   (outline-4 voice-smoothen)
   (outline-5 voice-monotone)
   (outline-6 voice-lighten-medium)
   ))

;;;  silence errors to help org-mode:

;;;  foldout specific advice

(with-eval-after-load "foldout"
  (defadvice foldout-zoom-subtree (after emacspeak pre act comp)
    "speak about the child we zoomed into"
    (when (ems-interactive-p)
      (emacspeak-icon 'open-object)
      (message
       "Zoomed into outline %s containing %s lines"
       (ems--this-line) (count-lines (point-min) (point-max)))))

  (defadvice foldout-exit-fold (after emacspeak pre act comp)
    "speak when exiting a fold"
    (when (ems-interactive-p)
      (emacspeak-icon 'close-object)
      (emacspeak-speak-line))))

(provide  'emacspeak-outline)

