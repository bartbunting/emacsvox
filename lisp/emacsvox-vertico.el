;;; emacsvox-vertico.el --- Speech-enable Vertico  -*- lexical-binding: t; -*-
;; Author: Krzysztof Drewniak <krzysdrewniak@gmail.com>
;; Description:  Speech-enable Vertico, a modern Emacs completion interface
;; Keywords: Emacsvox, Audio Desktop, Vertico, completion

;;;   Copyright:

;; Copyright (C) 2021 Krzysztof Drewniak <krzysdrewniak@gmail.com>
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
;; MERCHANTABILITY or FITNMARKDOWN FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Vertico is a modern completion UI that uses Emacs's native completion engine
;; This module speech-enables Vertico's UI

;;; Code:

;;; Forward variable declarations:

(defvar vertico--allow-prompt)
(defvar vertico--base)
(defvar vertico--index)
(defvar vertico--input)
;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-source)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)
(require 'vertico nil 'noerror)

;;;  Map faces to voices:

(defconst emacsvox-vertico--face-map
  '((vertico-group-title voice-smoothen)
    (vertico-group-separator voice-overlay-0))
  "Voice mappings for current Vertico faces.")

(voice-setup-add-map emacsvox-vertico--face-map)

;;;  Define bookkeeping variables for UI state

(defvar-local emacsvox-vertico--prev-candidate nil
  "Previously spoken candidate")

(defvar-local emacsvox-vertico--prev-index nil
  "Index of previously spoken candidate")

(defvar-local emacsvox-vertico--suppress-next-exhibit-p nil
  "Non-nil when a command already presented the next display update.")

(defun emacsvox-vertico--owns-minibuffer-content-p ()
  "Return non-nil when Vertico owns the current minibuffer's content speech.

Vertico sets `vertico--input' buffer-locally from its setup hook before the
appended Emacsvox minibuffer setup hook runs."
  (bound-and-true-p vertico--input))

;;; 
(declare-function 'vertico--candidate "vertico.el" (&optional hl))
(declare-function 'vertico--match-p "vertico.el" (input))

;;;  Semantic aural presentation:

(defun emacsvox-vertico-candidate-facts (&optional event unselected-p)
  "Return facts for the current candidate.

EVENT defaults to `focus-entered'.  For compatibility, t means `accepted'.
When UNSELECTED-P is non-nil, describe raw completion input instead of the
currently highlighted candidate."
  (append
   (list
    :role 'candidate
    :events
    (list
     (cond
      ((eq event t) 'accepted)
      (event event)
      (t 'focus-entered)))
    :completion-index (if unselected-p -1 vertico--index))
   (when (and (not unselected-p) (>= vertico--index 0))
     '(:states (selected)))))

(defun emacsvox-vertico--submit-candidate-feedback (facts icon text)
  "Submit candidate TEXT with FACTS and optional leading ICON."
  (let ((arguments
         (list
          :facts facts
          :module 'vertico
          :occasion
          (if (memq 'focus-entered (plist-get facts :events))
              'navigation
            'state-change)
          :compatibility-actions
          (when icon
            (list (emacsvox-aural-compatibility-icon icon))))))
    (if (and (stringp text) (not (string-empty-p text)))
        (apply #'emacsvox-aural-submit text arguments)
      (apply #'emacsvox-aural-submit-actions arguments))))

(defun emacsvox-vertico--inserted-content (start end)
  "Return inserted completion content between START and END, if any."
  (unless (= start end)
    (emacsvox-aural-source-substring start end)))

(defun emacsvox-vertico--initial-candidate-content (candidate)
  "Return one utterance containing the minibuffer prompt and CANDIDATE."
  (let* ((raw-prompt (minibuffer-prompt))
         (prompt (and raw-prompt (string-trim raw-prompt))))
    (mapconcat
     #'identity
     (delq
      nil
      (list
       (and prompt (not (string-empty-p prompt)) prompt)
       (and candidate (not (string-empty-p candidate)) candidate)))
     " ")))

(defun emacsvox-vertico--interactive-exit-p ()
  "Return non-nil for either interactive Vertico exit command."
  (or (ems-interactive-p 'vertico-exit)
      (ems-interactive-p 'vertico-exit-input)))

(defun emacsvox-vertico--exit-content (raw-input-p)
  "Return the content that a Vertico exit will accept.

When RAW-INPUT-P is non-nil, use minibuffer input even when a candidate is
selected."
  (if (and (not raw-input-p) (>= vertico--index 0))
      (vertico--candidate)
    (minibuffer-contents)))

;;;  Advice interactive commands

(defun emacsvox--advice-vertico-insert-around (orig-fun &rest args)
  "Call ORIG-FUN once and present the updated completion input."
  (let ((interactive-p (ems-interactive-p 'vertico-insert))
        (orig-point (point))
        result)
    (setq result (apply orig-fun args))
    (when interactive-p
      (emacsvox-vertico--submit-candidate-feedback
       (emacsvox-vertico-candidate-facts 'completion-input-updated)
       'item
       (emacsvox-vertico--inserted-content orig-point (point)))
      (setq-local emacsvox-vertico--suppress-next-exhibit-p t))
    result))

(defun emacsvox--advice-vertico-exit-around (orig-fun &rest args)
  "Present one accepted completion before calling exiting ORIG-FUN.

Vertico exits its recursive edit nonlocally, so acceptance must be presented
before calling ORIG-FUN.  The same match predicate used by Vertico prevents
feedback when an attempted exit is refused."
  (let* ((interactive-p (emacsvox-vertico--interactive-exit-p))
         (raw-input-p (car args))
         (content
          (and interactive-p
               (emacsvox-vertico--exit-content raw-input-p))))
    (when (and content
               (vertico--match-p (substring-no-properties content)))
      (emacsvox-vertico--submit-candidate-feedback
       (emacsvox-vertico-candidate-facts 'accepted raw-input-p)
       'complete
       content))
    (apply orig-fun args)))

(defconst emacsvox-vertico--navigation-icons
  '((vertico-next . select-object)
    (vertico-previous . select-object)
    (vertico-first . large-movement)
    (vertico-last . large-movement)
    (vertico-scroll-up . scroll)
    (vertico-scroll-down . scroll)
    (vertico-next-group . large-movement)
    (vertico-previous-group . large-movement))
  "Cues folded into native Vertico candidate transactions.")

(defun emacsvox-vertico--interactive-navigation-icon ()
  "Consume and return the cue for an interactive Vertico navigation command."
  (catch 'icon
    (dolist (entry emacsvox-vertico--navigation-icons)
      (when (ems-interactive-p (car entry))
        (throw 'icon (cdr entry))))))

(defun emacsvox--advice-vertico--exhibit-after (&rest _)
  "Present the current candidate after Vertico updates its display."
  (let* ((initial-p (null emacsvox-vertico--prev-index))
         (navigation-icon
          (emacsvox-vertico--interactive-navigation-icon))
         (new-cand
          (substring
           (vertico--candidate)
           (if (>= vertico--index 0)
               (if (stringp vertico--base)
                   (length vertico--base)
                 vertico--base)
             0)))
         (changed-p
          (not (equal emacsvox-vertico--prev-candidate new-cand)))
         (suppress-p emacsvox-vertico--suppress-next-exhibit-p)
         (content
          (cond
           (initial-p
            (emacsvox-vertico--initial-candidate-content new-cand))
           (changed-p new-cand)))
         (icon
          (or navigation-icon
              (when
                  (or (equal vertico--index emacsvox-vertico--prev-index)
                      (and (not (equal vertico--index -1))
                           (equal emacsvox-vertico--prev-index -1)))
                'select-object))))
    (setq-local emacsvox-vertico--suppress-next-exhibit-p nil)
    (when
        (and
         (not suppress-p)
         (or initial-p
             navigation-icon
             (and changed-p (>= vertico--index 0))))
      (emacsvox-vertico--submit-candidate-feedback
       (emacsvox-vertico-candidate-facts)
       icon
       content))
    (setq-local emacsvox-vertico--prev-candidate new-cand
                emacsvox-vertico--prev-index vertico--index)))

(defconst emacsvox-vertico--advice
  '((vertico-insert :around emacsvox--advice-vertico-insert-around)
    (vertico-exit :around emacsvox--advice-vertico-exit-around)
    (vertico--exhibit :after emacsvox--advice-vertico--exhibit-after))
  "Current Vertico targets and their native advice functions.")

(defun emacsvox-vertico--install-advice ()
  "Install native advice after Vertico loads."
  (dolist (entry emacsvox-vertico--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'vertico
  (emacsvox-vertico--install-advice))

(provide 'emacsvox-vertico)
;;;  end of file
