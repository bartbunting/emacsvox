;;; emacsvox-ediff.el --- Speech enable  ediff -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for ediff
;; Keywords:emacsvox, audio interface to emacs, Comparing files
;;;  LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;; $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;  Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995 by .
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.


:

;;; Commentary:

;; Ediff provides a nice visual interface to diff. ;;;Comparing and
;; patching files is easy with ediff when you can see the screen.
;; ;;;This module provides Emacsvox extensions to work fluently
;; ;;;with ediff. Try it out, it's an excellent example of why
;; Emacsvox is better than a traditional screenreader. This module
;; was originally written to interface to the old ediff.el bundled
;; with GNU Emacs 19.28 and earlier. It has been updated to work
;; with the newer and much larger ediff system found in Emacs 19.29
;; and later.
;; 
;; When using under modern versions of Emacs, I recommend setting
;; (setq ediff-window-setup-function 'ediff-setup-windows-plain)
;; so that Emacs always displays Ediff windows in a single frame.
;;; Code:

;;;  required:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'voice-setup)
(require 'ediff)

;;;  Map faces to voices.

(voice-setup-add-map
 '(
   (ediff-current-diff-A voice-smoothen)
   (ediff-current-diff-B voice-brighten)
   (ediff-current-diff-C voice-lighten)
   (ediff-current-diff-Ancestor voice-lighten-extra)
   (ediff-fine-diff-A voice-overlay-1)
   (ediff-fine-diff-B voice-overlay-2)
   (ediff-fine-diff-C voice-overlay-3)
   (ediff-fine-diff-Ancestor voice-overlay-4)
   (ediff-even-diff-A voice-brighten)
   (ediff-even-diff-B voice-smoothen)
   (ediff-even-diff-C voice-monotone-extra)
   (ediff-even-diff-Ancestor voice-monotone-extra)
   (ediff-odd-diff-A voice-smoothen)
   (ediff-odd-diff-B voice-brighten)
   (ediff-odd-diff-C voice-monotone-extra)
   (ediff-odd-diff-Ancestor voice-lighten)
   ))

;;;  Helper functions:

(defvar emacsvox-ediff-control-buffer nil
  "Holds the control buffer for the most recent ediff")
;; Please tell me what control buffer you're using--

(defun ems--ediff-setup-control-buffer-after (&rest _)
  (setq emacsvox-ediff-control-buffer (ad-get-arg 0)))

(advice-add 'ediff-setup-control-buffer :after
            #'ems--ediff-setup-control-buffer-after)

(defsubst emacsvox-ediff-control-panel ()
  
  emacsvox-ediff-control-buffer)

(defun emacsvox-ediff-difference-a-overlay (n)
  (cl-declare (special ediff-difference-vector-A
                       ediff-number-of-differences))
  (cl-assert (< n ediff-number-of-differences) t
             "There are only %s differences"
             ediff-number-of-differences)
  (aref (aref ediff-difference-vector-A n) 0))

(defun emacsvox-ediff-difference-b-overlay (n)
  (cl-declare (special ediff-difference-vector-B
                       ediff-number-of-differences))
  (cl-assert (< n ediff-number-of-differences) t
             "There are only %s differences"
             ediff-number-of-differences)
  (aref (aref ediff-difference-vector-B n) 0))

(defun emacsvox-ediff-difference-c-overlay (n)
  (cl-declare (special ediff-difference-vector-B
                       ediff-difference-vector-C
                       ediff-number-of-differences))
  (cl-assert (< n ediff-number-of-differences) t
             "There are only %s differences"
             ediff-number-of-differences)
  (aref (aref ediff-difference-vector-C n) 0))

(defun emacsvox-ediff-fine-difference-a-overlays (n)
  (cl-declare (special ediff-difference-vector-A
                       ediff-number-of-differences))
  (cl-assert (< n ediff-number-of-differences) t
             "There are only %s differences"
             ediff-number-of-differences)
  (aref (aref ediff-difference-vector-A n) 1))

(defun emacsvox-ediff-fine-difference-b-overlays (n)
  (cl-declare (special ediff-difference-vector-B
                       ediff-number-of-differences))
  (cl-assert (< n ediff-number-of-differences) t
             "There are only %s differences"
             ediff-number-of-differences)
  (aref (aref ediff-difference-vector-B n) 1))

(defun emacsvox-ediff-fine-difference-c-overlays (n)
  (cl-declare (special ediff-difference-vector-B
                       ediff-difference-vector-C
                       ediff-number-of-differences))
  (cl-assert (< n ediff-number-of-differences) t
             "There are only %s differences"
             ediff-number-of-differences)
  (aref (aref ediff-difference-vector-C n) 1))

(defun emacsvox-ediff-difference-fine-diff (difference)
  (aref difference 2))

;;;  Diff Overlay Accessors:

(defun emacsvox-ediff-diff-overlay-from-difference (diff counter)
  (aref (aref diff counter) 0))

(defun emacsvox-ediff-fine-overlays-from-difference (diff counter)
  (aref (aref diff counter) 1))

;;;  Setup Ediff Hook

(add-hook
 'ediff-startup-hook
 #'(lambda ()
     
     (setq voice-lock-mode t
           ediff-window-setup-function 'ediff-setup-windows-plain)
     (define-key
      ediff-mode-map "." 'emacsvox-ediff-speak-current-difference)))

;;;  Speak an ediff difference:

;; To speak an ediff difference,
;; First announce difference a and speak it.
;; If you see keyboard activity, shut up
;; and offer to speak difference b.

(defun emacsvox-ediff-speak-difference (n)
  "Speak a difference chunk"
  (let ((a-overlay (emacsvox-ediff-difference-a-overlay n))
        (b-overlay (emacsvox-ediff-difference-b-overlay n))
        (key ""))
    (emacsvox-icon 'select-object)
    (dtk-speak
     (concat
      "Difference ai "
      (emacsvox-overlay-get-text a-overlay)))
    (let ((dtk-stop-immediately nil))
      (sit-for 2)
      (setq key
            (read-key-sequence "Press any key to continue")))
    (unless (= 7 (string-to-char key))
      (dtk-stop 'all)
      (dtk-speak
       (concat
        "Difference B "
        (emacsvox-overlay-get-text b-overlay))))))

(defun emacsvox-ediff-speak-current-difference ()
  "Speak the current difference"
  (interactive)
  (cl-declare (special ediff-current-difference
                       ediff-number-of-differences))
  (emacsvox-ediff-speak-difference
   (cond
    ((cl-minusp ediff-current-difference) 0)
    ((>= ediff-current-difference ediff-number-of-differences)
     (1- ediff-number-of-differences))
    (t ediff-current-difference))))

;;;  Advice:

(defun ems--ediff-toggle-help-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'help)))

(advice-add 'ediff-toggle-help :after #'ems--ediff-toggle-help-after)

(defun ems--ediff-next-difference-after (&rest _)
  "Speak the difference interactively."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ediff-speak-current-difference)))

(advice-add 'ediff-next-difference :after
            #'ems--ediff-next-difference-after)

(defun ems--ediff-previous-difference-after (&rest _)
  "Speak the difference interactively."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ediff-speak-current-difference)))

(advice-add 'ediff-previous-difference :after
            #'ems--ediff-previous-difference-after)

(defun ems--ediff-status-info-after (&rest _)
  "Speak the status information"
  (when (ems-interactive-p)
    (save-current-buffer
      (set-buffer " *ediff-info*") (emacsvox-speak-buffer))))

(advice-add 'ediff-status-info :after #'ems--ediff-status-info-after)

(defun ems--ediff-scroll-up-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (message "Scrolled up buffers A and B")))

(advice-add 'ediff-scroll-up :after #'ems--ediff-scroll-up-after)

(defun ems--ediff-scroll-down-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (message "Scrolled down buffers A and B")))

(advice-add 'ediff-scroll-down :after #'ems--ediff-scroll-down-after)

(defun ems--ediff-toggle-split-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (if (eq ediff-split-window-function 'split-window-vertically)
        (message "Split ediff windows vertically")
      (message "Split ediff windows horizontally"))))

(advice-add 'ediff-toggle-split :after #'ems--ediff-toggle-split-after)

(defun ems--ediff-recenter-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "Refreshed the ediff display")))

(advice-add 'ediff-recenter :after #'ems--ediff-recenter-after)

(defun ems--ediff-jump-to-difference-after (&rest _)
  "Speak the difference you jumped to"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ediff-speak-current-difference)))

(advice-add 'ediff-jump-to-difference :after
            #'ems--ediff-jump-to-difference-after)

(defun ems--ediff-jump-to-difference-at-point-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement)
    (emacsvox-ediff-speak-current-difference)))

(advice-add 'ediff-jump-to-difference-at-point :after
            #'ems--ediff-jump-to-difference-at-point-after)

;; advice meta panel

(defun ems--ediff-previous-meta-item-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'ediff-previous-meta-item :after
            #'ems--ediff-previous-meta-item-after)

(defun ems--ediff-next-meta-item-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'ediff-next-meta-item :after
            #'ems--ediff-next-meta-item-after)

(defun ems--ediff-registry-action-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'open-object)))

(advice-add 'ediff-registry-action :after
            #'ems--ediff-registry-action-after)

(defun ems--ediff-show-registry-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Welcome to the Ediff registry")))

(advice-add 'ediff-show-registry :after
            #'ems--ediff-show-registry-after)

(defun ems--ediff-toggle-filename-truncation-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "turned %s file name truncation in Ediff registry"
             ediff-meta-truncate-filenames)))

(advice-add 'ediff-toggle-filename-truncation :after
            #'ems--ediff-toggle-filename-truncation-after)

;;; Hooks:

(add-hook
 'ediff-mode-hook
 #'(lambda ()
     (emacsvox-speak-mode-line)
     (emacsvox-icon 'open-object)))

(provide 'emacsvox-ediff)
;;;  emacs local variables

