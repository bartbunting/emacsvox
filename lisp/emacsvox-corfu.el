;;; emacsvox-corfu.el --- Speech-enable Corfu -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop corfu
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
;; CORFU ==  Completion Overlay Region FUnction.
;; This module speech-enables corfu.

;;; Code:

;;; Forward variable declarations:

(defvar corfu--candidates)
(defvar corfu--index)
(defvar corfu--metadata)
(defvar corfu--preselect)
(defvar corfu--total)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'corfu nil 'noerror)

;;;  Map Faces:

(defconst emacsvox-corfu--face-map
  '((corfu-default voice-smoothen)
    (corfu-current voice-bolden)
    (corfu-bar voice-monotone)
    (corfu-border voice-smoothen)
    (corfu-annotations voice-annotate)
    (corfu-deprecated voice-monotone-extra))
  "Voice mappings for current Corfu faces.")

(voice-setup-add-map emacsvox-corfu--face-map)

;;;  State tracking:

(defvar-local emacsvox-corfu--prev-candidate nil
  "Previously spoken candidate.")

(defvar-local emacsvox-corfu--prev-index -1
  "Previously spoken candidate index.")

(defvar-local emacsvox-corfu--prev-total 0
  "Previously announced number of candidates.")

(defvar-local emacsvox-corfu--session-active-p nil
  "Non-nil after the current Corfu completion session is announced.")

(defvar-local emacsvox-corfu--pending-expansion nil
  "Initial completion expansion awaiting Corfu's candidate update.")

;;;  Helper functions:

(defun emacsvox-corfu--reset-state ()
  "Reset aural state for the current Corfu completion session."
  (setq emacsvox-corfu--prev-candidate nil
        emacsvox-corfu--prev-index -1
        emacsvox-corfu--prev-total 0
        emacsvox-corfu--session-active-p nil
        emacsvox-corfu--pending-expansion nil))

(defun emacsvox-corfu--total ()
  "Return the number of current Corfu candidates."
  (if (and (boundp 'corfu--total)
           (integerp corfu--total))
      corfu--total
    (length (and (boundp 'corfu--candidates) corfu--candidates))))

(defun emacsvox-corfu--voice (text personality)
  "Return a copy of TEXT spoken with PERSONALITY."
  (when (and (stringp text) (not (string-empty-p text)))
    (let ((copy (copy-sequence text)))
      (add-text-properties
       0 (length copy) (list 'personality personality) copy)
      copy)))

(defun emacsvox-corfu--metadata-function (property)
  "Return the current Corfu metadata function for PROPERTY."
  (when (bound-and-true-p corfu--metadata)
    (if (fboundp 'corfu--metadata-get)
        (corfu--metadata-get property)
      (completion-metadata-get corfu--metadata property))))

(defun emacsvox-corfu--candidate-affixes (candidate)
  "Return speech prefix and suffix for CANDIDATE."
  (let ((affixation
         (emacsvox-corfu--metadata-function 'affixation-function))
        (annotation
         (emacsvox-corfu--metadata-function 'annotation-function)))
    (cond
     ((functionp affixation)
      (pcase (car (funcall affixation (list candidate)))
        (`(,_candidate ,prefix ,suffix)
         (list prefix suffix))
        (_ nil)))
     ((functionp annotation)
      (list nil (funcall annotation candidate))))))

(defun emacsvox-corfu--candidate-with-annotation
    (&optional index count-only-p)
  "Return a voiced candidate, annotation, and list position.

INDEX defaults to the current Corfu index.  When COUNT-ONLY-P is non-nil,
follow the candidate with the total count instead of its ordinal position."
  (let ((index (or index corfu--index)))
    (when-let* ((cand
                 (and (>= index 0)
                      (< index (length corfu--candidates))
                      (nth index corfu--candidates))))
    (pcase-let* ((`(,prefix ,suffix)
                   (emacsvox-corfu--candidate-affixes cand))
                  (parts
                   (delq
                    nil
                    (list
                     (emacsvox-corfu--voice
                      (and prefix (string-trim prefix)) voice-annotate)
                     (emacsvox-corfu--voice cand voice-bolden)
                     (emacsvox-corfu--voice
                      (and suffix (string-trim suffix)) voice-annotate))))
                  (position
                   (emacsvox-corfu--voice
                    (if count-only-p
                        (format "%d completion%s"
                                (emacsvox-corfu--total)
                                (if (= (emacsvox-corfu--total) 1)
                                    ""
                                  "s"))
                      (format "%d of %d"
                              (1+ index)
                              (emacsvox-corfu--total)))
                    voice-annotate)))
        (concat (mapconcat #'identity parts " ") ", " position)))))

(defun emacsvox-corfu--count-text (&optional prefix)
  "Return voiced candidate count, optionally preceded by PREFIX."
  (let ((total (emacsvox-corfu--total)))
    (emacsvox-corfu--voice
     (format "%s%d completion%s"
             (or prefix "")
             total
             (if (= total 1) "" "s"))
     voice-annotate)))

(defun emacsvox-corfu--candidate-facts (&optional event index)
  "Return semantic facts for the current candidate.

EVENT defaults to `focus-entered'.  For compatibility, t means `accepted'.
INDEX snapshots a selection that Corfu may clear while completing."
  (let ((index
         (if (integerp index)
             index
           (and (boundp 'corfu--index) corfu--index))))
    (append
     (list
      :role 'candidate
      :events
      (list
       (cond
        ((eq event t) 'accepted)
        (event event)
        (t 'focus-entered))))
     (when (and (integerp index) (>= index 0))
       (list :states '(selected) :completion-index index)))))

(defun emacsvox-corfu--submit (text facts occasion icon)
  "Submit voiced TEXT with FACTS, OCCASION, and compatibility ICON."
  (let ((arguments
         (list
          :facts facts
          :module 'corfu
          :occasion occasion
          :compatibility-actions
          (when icon
            (list (emacsvox-aural-compatibility-icon icon))))))
    (if (and (stringp text) (not (string-empty-p text)))
        (apply #'emacsvox-aural-submit text arguments)
      (apply #'emacsvox-aural-submit-actions arguments))))

(defun emacsvox-corfu--closed-facts ()
  "Return facts for a dismissed Corfu completion session."
  '(:role candidate :events (completion-session-closed)))

(defun emacsvox-corfu--navigation-icon ()
  "Return the auditory icon for the current Corfu position."
  (if (or (< corfu--index 0)
          (= corfu--index 0)
          (= corfu--index (1- (emacsvox-corfu--total))))
      'large-movement
    'select-object))

(defun emacsvox-corfu--speak-candidate (&optional icon force snapshot)
  "Speak the current Corfu selection.

ICON overrides the position-derived cue.  FORCE presents feedback even when
the selection has not changed, which makes repeated boundary navigation
audible.  SNAPSHOT, when non-nil, is the already formatted candidate text."
  (let* ((index (if (boundp 'corfu--index) corfu--index -1))
         (text
          (or snapshot
              (emacsvox-corfu--candidate-with-annotation)
              (emacsvox-corfu--candidate-with-annotation 0 t)
              (emacsvox-corfu--count-text "Completion prompt, "))))
    (when (or force
              (not (and (equal text emacsvox-corfu--prev-candidate)
                        (= index emacsvox-corfu--prev-index))))
      (emacsvox-corfu--submit
       text
       (emacsvox-corfu--candidate-facts)
       'navigation
       (or icon (emacsvox-corfu--navigation-icon)))
      (setq emacsvox-corfu--prev-candidate text
            emacsvox-corfu--prev-index index))))

(defun emacsvox-corfu--completion-markers ()
  "Return markers around the active completion input, or nil."
  (when-let* ((data (bound-and-true-p completion-in-region--data))
              (start (nth 0 data))
              (end (nth 1 data)))
    (when (and (integer-or-marker-p start)
               (integer-or-marker-p end))
      (list (copy-marker start) (copy-marker end t)))))

(defun emacsvox-corfu--marker-text (markers)
  "Return buffer text delimited by MARKERS, or nil."
  (when (and markers
             (marker-buffer (car markers))
             (eq (marker-buffer (car markers))
                 (marker-buffer (cadr markers))))
    (with-current-buffer (marker-buffer (car markers))
      (buffer-substring-no-properties
       (marker-position (car markers))
       (marker-position (cadr markers))))))

(defun emacsvox-corfu--clear-markers (markers)
  "Detach completion region MARKERS."
  (dolist (marker markers)
    (set-marker marker nil)))

(defun emacsvox-corfu--expansion-text (input changed-p)
  "Return voiced feedback for completion INPUT.

CHANGED-P is non-nil when common-prefix expansion changed the input."
  (if changed-p
      (concat
       (emacsvox-corfu--voice input voice-bolden)
       (emacsvox-corfu--voice
        (format ", %d completion%s"
                (emacsvox-corfu--total)
                (if (= (emacsvox-corfu--total) 1) "" "s"))
        voice-annotate))
    (emacsvox-corfu--count-text "No common expansion, ")))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-corfu-insert-around (orig-fun &rest args)
  "Call ORIG-FUN once with ARGS and present the accepted Corfu candidate."
  (let ((interactive-p (ems-interactive-p 'corfu-insert))
        (text (emacsvox-corfu--candidate-with-annotation))
        (facts (emacsvox-corfu--candidate-facts t))
        result)
    (setq result (apply orig-fun args))
    (when interactive-p
      (emacsvox-corfu--submit
       text
       (if text facts (emacsvox-corfu--closed-facts))
       'state-change
       (if text 'complete 'close-object)))
    result))

(defun emacsvox--advice-corfu-quit-after (&rest _)
  "Reset spoken candidate state after quitting Corfu."
  (when (ems-interactive-p 'corfu-quit)
    (emacsvox-corfu--submit
     nil (emacsvox-corfu--closed-facts)
     'state-change 'close-object))
  (emacsvox-corfu--reset-state))

(defun emacsvox--advice-corfu-reset-around (orig-fun &rest args)
  "Call resetting ORIG-FUN once and present its actual lifecycle result."
  (let ((interactive-p (ems-interactive-p 'corfu-reset))
        (unselecting-p
         (and (boundp 'corfu--index)
              (boundp 'corfu--preselect)
              (/= corfu--index corfu--preselect)))
        result)
    (setq result (apply orig-fun args))
    (when interactive-p
      (if (bound-and-true-p completion-in-region-mode)
          (if unselecting-p
              (emacsvox-corfu--speak-candidate 'large-movement t)
            ;; Input was restored.  Candidate state is stale until Corfu's
            ;; post-command update, so force that update to present its result.
            (setq emacsvox-corfu--prev-candidate nil
                  emacsvox-corfu--prev-index -1
                  emacsvox-corfu--prev-total 0))
        (emacsvox-corfu--submit
         nil (emacsvox-corfu--closed-facts)
         'state-change 'close-object)
        (emacsvox-corfu--reset-state)))
    result))

(defun emacsvox--advice-corfu-insert-separator-after (&rest _)
  "Confirm insertion of a Corfu separator."
  (when (ems-interactive-p 'corfu-insert-separator)
    (emacsvox-aural-submit-actions
     :facts '(:events (completion-separator-inserted))
     :module 'corfu
     :occasion 'edit
     :compatibility-actions
     (list (emacsvox-aural-compatibility-icon 'select-object)))))

(defun emacsvox-corfu--complete-around (target orig-fun args)
  "Call ORIG-FUN with ARGS for TARGET and present its completion result."
  (let* ((interactive-p (ems-interactive-p target))
         (selected (emacsvox-corfu--candidate-with-annotation))
         (selected-index (and selected corfu--index))
         (markers (and interactive-p (emacsvox-corfu--completion-markers)))
         (before (and markers (emacsvox-corfu--marker-text markers)))
         result)
    (unwind-protect
        (progn
          (setq result (apply orig-fun args))
          (when interactive-p
            (let* ((after (emacsvox-corfu--marker-text markers))
                   (changed-p (and after (not (equal before after))))
                   (finished-p
                    (not (bound-and-true-p completion-in-region-mode))))
              (if selected
                (emacsvox-corfu--submit
                 selected
                 (emacsvox-corfu--candidate-facts
                  (if finished-p 'accepted 'completion-input-updated)
                  selected-index)
                 'state-change
                 (if finished-p 'complete 'item))
                (emacsvox-corfu--submit
                 (if finished-p
                     (emacsvox-corfu--voice
                      (or after before "Completion accepted")
                      voice-bolden)
                   (emacsvox-corfu--expansion-text
                    (or after before "") changed-p))
                 (list
                  :role 'candidate
                  :events
                  (list
                   (cond
                    (finished-p 'accepted)
                    (changed-p 'completion-input-updated)
                    (t 'operation-completed))))
                 'state-change
                 (if finished-p 'complete 'item)))))
          (setq emacsvox-corfu--prev-total (emacsvox-corfu--total))
          result)
      (emacsvox-corfu--clear-markers markers))))

(defun emacsvox--advice-corfu-complete-around (orig-fun &rest args)
  "Call ORIG-FUN once and present direct `corfu-complete' feedback."
  (emacsvox-corfu--complete-around 'corfu-complete orig-fun args))

(defun emacsvox--advice-corfu-expand-around (orig-fun &rest args)
  "Call ORIG-FUN once and present direct `corfu-expand' feedback."
  (emacsvox-corfu--complete-around 'corfu-expand orig-fun args))

;;;  Navigation advice:

(defconst emacsvox-corfu--navigation-targets
  '(corfu-next
    corfu-previous
    corfu-first
    corfu-last
    corfu-scroll-up
    corfu-scroll-down)
  "Current Corfu candidate navigation commands.")

(cl-loop
 for target in emacsvox-corfu--navigation-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak the current Corfu candidate."
     (when (ems-interactive-p ',target)
       (emacsvox-corfu--speak-candidate nil t)))))

;;;  Internal advice:

(defun emacsvox--advice-corfu--in-region-1-around
    (original beg end table pred)
  "Let Corfu own speech for an initial interactive completion.
Keep expanded input until the popup update can announce it with the new
candidate count.  Consuming the interactive marker prevents generic
`completion-at-point' feedback from being cut off by that update."
  (let* ((interactive-p (ems-interactive-p 'completion-at-point))
         (markers (and interactive-p
                       (list (copy-marker beg) (copy-marker end t))))
         (before (emacsvox-corfu--marker-text markers)))
    (unwind-protect
        (let ((result (funcall original beg end table pred)))
          (when (and interactive-p result)
            (let ((after (emacsvox-corfu--marker-text markers)))
              (if (bound-and-true-p completion-in-region-mode)
                  (unless (equal before after)
                    (setq emacsvox-corfu--pending-expansion after))
                (emacsvox-corfu--submit
                 (emacsvox-corfu--voice after voice-bolden)
                 '(:role candidate :events (accepted))
                 'state-change 'complete))))
          result)
      (emacsvox-corfu--clear-markers markers))))

(defun emacsvox--advice-corfu--update-after (&rest _)
  "Present candidate availability after Corfu updates."
  (when (bound-and-true-p corfu-mode)
    (if (bound-and-true-p corfu--candidates)
        (let* ((opening-p (not emacsvox-corfu--session-active-p))
               (total-changed-p
                (/= (emacsvox-corfu--total)
                    emacsvox-corfu--prev-total))
               (snapshot
                (or (emacsvox-corfu--candidate-with-annotation)
                    (emacsvox-corfu--candidate-with-annotation 0 t)
                    (emacsvox-corfu--count-text "Completion prompt, "))))
          (setq emacsvox-corfu--session-active-p t)
          (cond
           (emacsvox-corfu--pending-expansion
            (emacsvox-corfu--submit
             (emacsvox-corfu--expansion-text
              emacsvox-corfu--pending-expansion t)
             '(:role candidate :events (completion-input-updated))
             'state-change 'complete)
            ;; Remember the popup snapshot too, so another unchanged update
            ;; cannot replace the expansion with its first candidate.
            (setq emacsvox-corfu--pending-expansion nil
                  emacsvox-corfu--prev-candidate snapshot
                  emacsvox-corfu--prev-index corfu--index))
           ((or opening-p total-changed-p
                (not (equal snapshot emacsvox-corfu--prev-candidate)))
            (emacsvox-corfu--speak-candidate
             (if opening-p 'open-object 'item) nil snapshot)))
          (setq emacsvox-corfu--prev-total
                (emacsvox-corfu--total)))
      (unless (equal emacsvox-corfu--prev-candidate "No completions")
        (let ((text
               (emacsvox-corfu--voice
                "No completions" voice-annotate)))
          (emacsvox-corfu--submit
           text
           '(:role candidate :events (operation-failed))
           'navigation
           'warn-user)
          (setq emacsvox-corfu--prev-candidate "No completions"
                emacsvox-corfu--prev-index -1
                emacsvox-corfu--prev-total 0
                emacsvox-corfu--session-active-p t))))))

(defconst emacsvox-corfu--advice
  (append
   '((corfu-insert :around emacsvox--advice-corfu-insert-around)
     (corfu-quit :after emacsvox--advice-corfu-quit-after)
     (corfu-reset :around emacsvox--advice-corfu-reset-around)
     (corfu-insert-separator :after
      emacsvox--advice-corfu-insert-separator-after)
     (corfu-complete :around emacsvox--advice-corfu-complete-around)
     (corfu-expand :around emacsvox--advice-corfu-expand-around)
     (corfu--in-region-1 :around emacsvox--advice-corfu--in-region-1-around)
     (corfu--update :after emacsvox--advice-corfu--update-after))
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    emacsvox-corfu--navigation-targets))
  "Current Corfu targets and their native advice functions.")

(defun emacsvox-corfu--install-advice ()
  "Install advice after the optional Corfu package loads."
  (dolist (entry emacsvox-corfu--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'corfu
  (emacsvox-corfu--install-advice))

;;;  Hooks:

(defun emacsvox-corfu--completion-hook ()
  "Reset state when `completion-in-region-mode' changes."
  (unless completion-in-region-mode
    (emacsvox-corfu--reset-state)))

(add-hook 'completion-in-region-mode-hook
          #'emacsvox-corfu--completion-hook)

(provide 'emacsvox-corfu)

;;; emacsvox-corfu.el ends here
