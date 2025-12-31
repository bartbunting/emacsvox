;;; emacsvox-analog.el Speech-enable analog --- -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for ANALOG log analyzer
;; Keywords: Emacsvox, analog
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4150 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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

;; Speech-enables package analog --convenient log analyzer 

;;  required modules

;;; Code:
(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  autoloads to help compiler

(autoload 'analog-get-entry-property "analog")

;;;  advice interactive commands

(defun ems--analog-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-analog-update-edit-keys)
    (emacsvox-speak-mode-line)))

(advice-add 'analog :after #'ems--analog-after)

(defun ems--analog-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'analog-quit :after #'ems--analog-quit-after)

(defun ems--analog-bury-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'analog-bury-buffer :after #'ems--analog-bury-buffer-after)

(cl-loop for command in
         '(analog-next-group
           analog-previous-group
           analog-next-entry
           analog-previous-entry
           analog-refresh-display-buffer
           analog-toggle-timer-and-redisplay)
         do
         (eval
          `(defadvice ,command (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-speak-line)
               (emacsvox-icon 'select-object)))))

;;;  voice setup 
(voice-setup-add-map
 '(
   (analog-entry-header-face voice-bolden)
   ))

;;;  field navigation

;; You can add a fields property that holds a list of field start
;; positions 
;; in analog-entries-list
;; emacsvox will use this to navigate using the arrow keys.

(defun emacsvox-analog-get-field-spec ()
  "Returns field specification if one defined for current entry.
Nil means no field specified."
  (save-excursion
    (let ((start (previous-single-property-change (point)
                                                  'analog-entry-start)))
      (when start
        (analog-get-entry-property
         (get-text-property
          (1- start)
          'analog-entry-start)
         'fields)))))

(defun emacsvox-analog-forward-field-or-char ()
  "Move forward to next field if field specification is available.
Otherwise move to next char.
Speak field or char moved to."
  (interactive)
  (let ((fields (emacsvox-analog-get-field-spec)))
    (cond
     (fields (emacsvox-analog-next-field fields)
             (emacsvox-analog-speak-field fields)
             (emacsvox-icon 'large-movement))
     (t (call-interactively 'forward-char)))))

(defun emacsvox-analog-backward-field-or-char ()
  "Move back to next field if field specification is available.
Otherwise move to previous char.
Speak field or char moved to."
  (interactive)
  (let ((fields (emacsvox-analog-get-field-spec)))
    (cond
     (fields (emacsvox-analog-previous-field fields)
             (emacsvox-analog-speak-field fields)
             (emacsvox-icon 'large-movement))
     (t (call-interactively 'backward-char)))))

(defun emacsvox-analog-speak-field (fields)
  "Speak field containing point."
  (save-excursion
    (let ((col (current-column))
          (start nil)
          (end nil)
          (left 0)
          (right  (cl-first fields)))
      (beginning-of-line)
      (while (and fields 
                  (<=  right col))
        (setq left right 
              right (pop fields)))
      (beginning-of-line)
      (forward-char left)
      (setq start (point))
      (cond
       ((or (null right)
            (<= right col))
        (beginning-of-line)
        (forward-char right)
        (setq start (point))
        (end-of-line)
        (setq end (point)))
       (t
        (beginning-of-line)
        (forward-char  right)
        (setq end (point))))
      (emacsvox-speak-region start end))))

(defun emacsvox-analog-speak-this-field ()
  "Speak current field."
  (interactive)
  (emacsvox-analog-speak-field (emacsvox-analog-get-field-spec)))

(defun emacsvox-analog-next-field (fields)
  "Move to next field."
  (let ((col (current-column))
        (end (cl-first fields)))
    (while (and fields 
                (<= end col))
      (setq end (pop fields)))  
    (cond
     ((> end col)
      (beginning-of-line)
      (forward-char end))
     (t (emacsvox-icon 'warn-user)))))

(defun emacsvox-analog-previous-field (fields)
  "Move to previous field."
  (let ((col (current-column))
        (prev 0)
        (start 0)
        (end (cl-first fields)))
    (while (and fields 
                (< end col))
      (setq prev start
            start end 
            end (pop fields)))
    (beginning-of-line)
    (cond
     ((<= start col)
      (forward-char start))
     (t (forward-char prev)))))

(defun emacsvox-analog-previous-line ()
  "Move up and speak current field."
  (interactive)
  (let ((fields (emacsvox-analog-get-field-spec)))
    (cond (fields
           (emacsvox-icon 'select-object)
           (forward-line -1)
           (emacsvox-analog-speak-field fields))
          (t (call-interactively 'previous-line)))))

(defun emacsvox-analog-next-line ()
  "Move down and speak current field."
  (interactive)
  (let ((fields (emacsvox-analog-get-field-spec)))
    (cond (fields
           (emacsvox-icon 'select-object)
           (forward-line 1)
           (emacsvox-analog-speak-field fields))
          (t (call-interactively 'next-line)))))

;;;  key bindings
(when (boundp 'analog-mode-map)
  (cl-declaim (special analog-mode-map))
  (define-key analog-mode-map '[left]
              'emacsvox-analog-backward-field-or-char)
  (define-key analog-mode-map '[right] 'emacsvox-analog-forward-field-or-char)
  (define-key analog-mode-map '[up] 'emacsvox-analog-previous-line)
  (define-key analog-mode-map '[down] 'emacsvox-analog-next-line))

(provide 'emacsvox-analog)
;;;  end of file

