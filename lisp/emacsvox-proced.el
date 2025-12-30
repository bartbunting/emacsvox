;;; emacsvox-proced.el --- Speech-enable PROCED -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Speech-enable PROCED A Task manager for Emacs
;; Keywords: Emacsvox,  Audio Desktop proced Task Manager
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
;; MERCHANTABILITY or FITNPROCED FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; PROCED ==  Process Editor
;; A new Task Manager for Emacs.
;; Proced is part of emacs 23.

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Variables

(defvar emacsvox-proced-minibuffer-history nil
  "History variable to track minibuffer usage in proced.")

(defvar emacsvox-proced-fields nil
  "Association list holding field-name . column-position pairs.")
(defvar emacsvox-proced-process-cache nil
  "Cache of processes that are displayed.")

;;;  Helpers and actions

(defun emacsvox-proced-update-fields ()
  "Updates cache of field-name .column-positions alist."
  
  (let ((positions nil)
        (next nil)
        (header proced-header-line)
        (start 0)
        (end 0))
    (setq start (string-match "[A-Za-z%]" header))
    (while (and (<  end (length header))
                (setq end (string-match " " header start)))
      (setq next (string-match "[A-Za-z%]" header end))
      (push
       (cons (substring header start end)
             (cons start (1- next)))
       positions)
      (setq start next))
    (push
     (cons (substring header start)
           (cons start  (window-width)))
     positions)
    (setq emacsvox-proced-fields
          (nreverse positions))))

;; Destructuring: (field-name . (start . end))
(defun emacsvox-proced-field-name (entry)
  "Return field name."
  (car entry))

(defun emacsvox-proced-field-start (entry)
  "Return start column."
  (cadr entry))

(defun emacsvox-proced-field-end (entry)
  "Return end column."
  (cddr entry))

(defun emacsvox-proced-field-to-position (field)
  "Return column position of this field."
  
  (cdr (assoc-string field emacsvox-proced-fields)))

(defun emacsvox-proced-position-to-field (pos)
  "Return field  for this position."
  
  (let ((fields emacsvox-proced-fields)
        (field nil)
        (range nil)
        (found nil))
    (while (and fields (not found))
      (setq field (car fields))
      (setq range (cdr field))
      (setq fields (cdr fields))
      (when (and
             (<= (car range) pos)
             (<= pos (cdr range)))
        (setq found t)))
    field))

(defun emacsvox-proced-speak-this-field (&optional position)
  "Speak field at specified column --- defaults to current column."
  (interactive)
  (setq position (or position (current-column)))
  (let ((field (emacsvox-proced-position-to-field position))
        (start nil)
        (end nil))
    (save-excursion
      (goto-char
       (+ (line-beginning-position)
          (emacsvox-proced-field-start field)))
      (setq start (point))
      (when (looking-at "[^ ]")
        (skip-syntax-backward "^ ")
        (setq start (point)))
      (skip-syntax-forward " ")
      (skip-syntax-forward "^ ")
      (setq end (point))
      (when (equal field (car (last emacsvox-proced-fields)))
        (setq end (line-end-position)))
      (message
       "%s: %s"
       (emacsvox-proced-field-name field)
       (buffer-substring start end)))))

(defun emacsvox-proced-speak-that-field ()
  "Speak desired field via single keystroke."
  (interactive)
  (cl-case (read-char "?")
    (?u (emacsvox-proced-speak-field 'user))
    (?p (emacsvox-proced-speak-field 'pid))
    (?c (emacsvox-proced-speak-field 'pcpu))
    (?m (emacsvox-proced-speak-field 'pmem))
    (?v (emacsvox-proced-speak-field 'vsz))
    (?r (emacsvox-proced-speak-field 'rss))
    (?T (emacsvox-proced-speak-field 'tty))
    (?S (emacsvox-proced-speak-field 'stat))
    (?s (emacsvox-proced-speak-field 'start))
    (?t (emacsvox-proced-speak-field 'time))
    (?a (emacsvox-proced-speak-field 'args))
    (otherwise (message "Pick field using mnemonic chars"))))

(defun emacsvox-proced-speak-args ()
  "Speak command  invocation  for this process."
  (interactive)
  (emacsvox-proced-speak-field 'args))

(defun emacsvox-proced-next-field ()
  "Navigate to next field."
  (interactive)
  
  (let ((tabs emacsvox-proced-fields))
    (while
        (and tabs
             (>= (current-column) (emacsvox-proced-field-start (car tabs))))
      (setq tabs (cdr tabs)))
    (cond
     ((null tabs) (error "On last field "))
     (t
      (goto-char
       (+ (line-beginning-position)
          (emacsvox-proced-field-start (car tabs))))
      (emacsvox-icon 'large-movement)
      (when (called-interactively-p 'interactive)
        (emacsvox-proced-speak-this-field))))))

(defun emacsvox-proced-previous-field ()
  "Navigate to previous field."
  (interactive)
  
  (let ((tabs emacsvox-proced-fields)
        (target nil))
    (forward-char -1)
    (while
        (and tabs
             (>= (current-column) (emacsvox-proced-field-start (car tabs))))
      (setq target (car tabs)
            tabs (cdr tabs)))
    (cond
     ((null target) (error "On first field "))
     (t
      (goto-char
       (+ (line-beginning-position)
          (emacsvox-proced-field-start target)))
      (when (called-interactively-p 'interactive)
        (emacsvox-icon 'large-movement)
        (emacsvox-proced-speak-this-field))))))

(defun emacsvox-proced-speak-field (field-name)
  "Speak value of specified field in current line."
  (interactive
   (list
    (let ((completion-ignore-case t))
      (intern
       (completing-read
        "Field: "
        (mapcar
         #'car
         (cdr (assoc (get-text-property (point) 'proced-pid)
                     proced-process-alist)))
        nil t nil)))))
  
  (let ((value
         (cdr
          (assoc
           field-name
           (assoc (get-text-property (point) 'proced-pid)
                  proced-process-alist)))))
    (message "%s: %s" field-name value)))

(defun emacsvox-proced-add-keys ()
  "Add additional keybindings for emacsvox."
  
  (define-key proced-mode-map "a" 'emacsvox-proced-speak-args)
  (define-key proced-mode-map "n" 'emacsvox-proced-next-line)
  (define-key proced-mode-map "p" 'emacsvox-proced-previous-line)
  (define-key proced-mode-map "j" 'emacsvox-proced-jump-to-process)
  (define-key proced-mode-map "\t" 'emacsvox-proced-next-field)
  (define-key proced-mode-map [S-tab] 'emacsvox-proced-previous-field)
  (define-key proced-mode-map [backtab] 'emacsvox-proced-previous-field)
  (define-key proced-mode-map "." 'emacsvox-proced-speak-field)
  (define-key proced-mode-map "<" 'beginning-of-buffer)
  (define-key proced-mode-map ">" 'end-of-buffer)
  (define-key proced-mode-map ";" 'emacsvox-proced-speak-that-field)
  (define-key proced-mode-map "," 'emacsvox-proced-speak-this-field))

(add-hook 'proced-mode-hook #'emacsvox-proced-add-keys)

(defun emacsvox-proced-update-process-cache ()
  "Updated display cache "
  
  (let ((cache nil))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (goto-char (+ (line-beginning-position)
                      (car (emacsvox-proced-field-to-position "Args"))))
        (push
         (buffer-substring-no-properties (point)
                                         (line-end-position))
         cache)
        (forward-line 1))
      (setq emacsvox-proced-process-cache (nreverse cache)))))

(defun emacsvox-proced-jump-to-process (name)
  "Jump to process by name."
  (interactive
   (list
    (completing-read
     "Jump to process: "
     emacsvox-proced-process-cache)))
  
  (let ((pos (cl-position name  emacsvox-proced-process-cache
                          :test #'string-equal)))
    (cond
     (pos
      (forward-line (1+ pos))
      (emacsvox-proced-speak-this-field))
     (t (error "Can't find %s" name)))))

;;;  Advice interactive commands:


(defun ems--proced-mark-before (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (emacsvox-proced-speak-this-field)))


(advice-add 'proced-mark :before #'ems--proced-mark-before)





(defun ems--proced-unmark-before (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-proced-speak-this-field)))


(advice-add 'proced-unmark :before #'ems--proced-unmark-before)





(defun ems--proced-mark-all-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Marked all processes. ") (emacsvox-icon 'mark-object)))


(advice-add 'proced-mark-all :after #'ems--proced-mark-all-after)





(defun ems--proced-unmark-all-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Removed all marks. ") (emacsvox-icon 'deselect-object)))


(advice-add 'proced-unmark-all :after #'ems--proced-unmark-all-after)




(cl-loop
 for f in
 '(proced proced-update)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "Update cache of field positions."
     (let ((emacsvox-speak-messages nil))
       ad-do-it
       (emacsvox-proced-update-fields)
       (emacsvox-proced-update-process-cache)
       (when (ems-interactive-p)
         (emacsvox-icon 'open-object)
         (funcall-interactively #'emacsvox-speak-mode-line))))))

(cl-loop
 for f  in
 '(proced-sort-pcpu proced-sort-start
                    proced-sort-time proced-sort-interactive
                    proced-sort-user  proced-sort-pmem
                    proced-sort-pid)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Provide auditory feedbak."
     (when (ems-interactive-p)
       (emacsvox-proced-speak-this-field)
       (emacsvox-icon 'task-done)))))

;;;  additional commands:

(defun emacsvox-proced-next-line ()
  "Move to next line and speak a summary."
  (interactive)
  (goto-char (line-end-position))
  (cond
   ((eobp) (error "On last line."))
   (t (forward-line 1)
      (skip-syntax-forward " ")
      (emacsvox-proced-speak-field 'args))))

(defun emacsvox-proced-previous-line ()
  "Move to next line and speak a summary."
  (interactive)
  (goto-char (line-beginning-position))
  (cond
   ((bobp) (error "On first line"))
   (t (forward-line -1)
      (beginning-of-line)
      (skip-syntax-forward " ")
      (emacsvox-proced-speak-field 'args))))

(provide 'emacsvox-proced)
;;;  end of file

