;;; emacspeak-magit.el --- Speech-enable MAGIT -*- lexical-binding: t; -*-
;; $Id: emacspeak-magit.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable MAGIT An Emacs Interface to magit
;; Keywords: Emacspeak,  Audio Desktop magit
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
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
;; MERCHANTABILITY or FITNMAGIT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; MAGIT ==  Git interface in Emacs
;; git clone git://github.com/magit/magit.git

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;;  Map voices to faces:

(voice-setup-add-map
 '(
   (magit-bisect-bad voice-animate)
   (magit-bisect-good voice-lighten)
   (magit-bisect-skip voice-monotone-extra)
   (magit-blame-date voice-bolden-and-animate)
   (magit-blame-dimmed voice-smoothen)
   (magit-blame-hash voice-monotone-extra)
   (magit-blame-heading voice-bolden)
   (magit-blame-highlight voice-brighten)
   (magit-blame-name voice-animate)
   (magit-blame-summary voice-lighten)
   (magit-branch-current voice-lighten)
   (magit-branch-local voice-brighten)
   (magit-branch-remote voice-smoothen)
   (magit-branch-remote-head voice-bolden)
   (magit-branch-upstream voice-animate)
   (magit-cherry-equivalent voice-lighten)
   (magit-cherry-unmatched voice-bolden)
   (magit-diff-added voice-animate-extra)
   (magit-diff-added-highlight voice-animate)
   (magit-diff-added-highlight voice-animate-extra)
   (magit-diff-base voice-annotate)
   (magit-diff-base-highlight voice-animate)
   (magit-diff-conflict-heading voice-bolden-extra)
   (magit-diff-context voice-monotone-extra)
   (magit-diff-context-highlight voice-brighten)
   (magit-diff-file-heading voice-brighten)
   (magit-diff-file-heading-highlight voice-bolden-extra)
   (magit-diff-file-heading-selection voice-lighten)
   (magit-diff-hunk-heading voice-bolden)
   (magit-diff-hunk-heading-highlight voice-brighten)
   (magit-diff-hunk-heading-selection voice-lighten)
   (magit-diff-hunk-region voice-smoothen)
   (magit-diff-lines-boundary voice-monotone-extra)
   (magit-diff-lines-heading voice-lighten)
   (magit-diff-our voice-smoothen)
   (magit-diff-our-highlight voice-lighten)
   (magit-diff-removed voice-monotone-extra)
   (magit-diff-removed-highlight voice-smoothen)
   (magit-diff-revision-summary voice-monotone-extra)
   (magit-diff-revision-summary-highlight voice-animate-extra)
   (magit-diff-their voice-animate)
   (magit-diff-their-highlight voice-bolden-and-animate)
   (magit-diff-whitespace-warning voice-monotone-medium)
   (magit-diffstat-added voice-animate)
   (magit-diffstat-removed voice-monotone-extra)
   (magit-dimmed voice-smoothen)
   (magit-filename voice-bolden)
   (magit-hash inaudible)
   (magit-head voice-bolden-medium)
   (magit-header-line voice-bolden)
   (magit-header-line-key voice-bolden-extra)
   (magit-header-line-log-select voice-animate)
   (magit-keyword voice-animate)
   (magit-keyword-squash voice-monotone-extra)
   (magit-log-author voice-monotone-extra)
   (magit-log-date voice-monotone-medium)
   (magit-log-graph voice-monotone)
   (magit-reflog-amend voice-animate)
   (magit-reflog-checkout voice-smoothen)
   (magit-reflog-cherry-pick voice-lighten)
   (magit-reflog-commit voice-monotone-extra)
   (magit-reflog-merge voice-annotate)
   (magit-reflog-other voice-monotone-extra)
   (magit-reflog-rebase voice-lighten)
   (magit-reflog-remote voice-annotate)
   (magit-reflog-reset voice-lighten)
   (magit-refname voice-bolden)
   (magit-refname-stash voice-monotone-extra)
   (magit-refname-wip voice-lighten)
   (magit-section-heading voice-bolden)
   (magit-section-heading-selection voice-bolden-medium)
   (magit-section-highlight voice-bolden)
   (magit-section-secondary-heading voice-bolden-medium)
   (magit-sequence-done voice-monotone-extra)
   (magit-sequence-drop voice-lighten)
   (magit-sequence-head voice-bolden)
   (magit-sequence-onto voice-lighten)
   (magit-sequence-part voice-monotone-extra)
   (magit-sequence-pick voice-animate)
   (magit-sequence-stop voice-smoothen)
   (magit-signature-bad voice-animate)
   (magit-signature-error voice-bolden-and-animate)
   (magit-signature-expired voice-monotone-extra)
   (magit-signature-expired-key voice-monotone-medium)
   (magit-signature-good voice-smoothen)
   (magit-signature-revoked voice-bolden)
   (magit-signature-untrusted voice-brighten)
   (magit-tag voice-smoothen)))

;;;  Pronunciations in Magit:
(emacspeak-pronounce-add-dictionary-entry
 'magit-mode
 emacspeak-pronounce-sha-checksum-pattern
 (cons 're-search-forward
       'emacspeak-pronounce-sha-checksum))
(emacspeak-pronounce-add-super 'magit-mode 'magit-commit-mode)
(emacspeak-pronounce-add-super 'magit-mode 'magit-revision-mode)
(emacspeak-pronounce-add-super 'magit-mode 'magit-log-mode)

(add-hook
 'magit-mode-hook
 'emacspeak-pronounce-refresh-pronunciations)

;;;  Advice navigation commands:

;; Advice navigators:

(defun ems--magit-mark-item-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'mark-object) (emacspeak-speak-line)))


(advice-add 'magit-mark-item :after #'ems--magit-mark-item-after)




(cl-loop
 for f in
 '(
   magit-section-forward magit-section-backward magit-section-up
   magit-next-line magit-previous-line
   magit-section-forward-sibling magit-section-backward-sibling
   magit-ignore-file magit-ignore-item
   magit-stash
   magit-unstage magit-unstage-all magit-unstage-file
   magit-stage magit-stage-file  magit-stage-modified
   magit-ignore-item-locally)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak"
     (when (ems-interactive-p)
       (emacspeak-icon 'select-object)
       (emacspeak-speak-line)))))

;;;  Section Toggle:

(cl-loop
 for f in
 '(
   magit-section-show-children magit-section-show-headings
   magit-show-commit
   magit-section-show-level-1  magit-section-show-level-2
   magit-section-show-level-3 magit-section-show-level-4
   magit-section-show-level-1-all magit-section-show-level-2-all
   magit-section-show-level-3-all magit-section-show-level-4-all
   magit-section-cycle-diffs)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (emacspeak-speak-line)
     (emacspeak-icon 'open-object))))


(defun ems--magit-section-hide-after (&rest _)
  "Icon." (emacspeak-icon 'close-object))


(advice-add 'magit-section-hide :after #'ems--magit-section-hide-after)





(defun ems--magit-section-cycle-global-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-notify "Cycling global visibility of sections")))


(advice-add 'magit-section-cycle-global :after
	    #'ems--magit-section-cycle-global-after)




(cl-loop
 for f in
 '(
   magit-section-toggle magit-section-cycle)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacspeak-speak-line)
       (emacspeak-icon
        (if   (oref (ad-get-arg 0) hidden) 'close-object 'open-object))))))

;;; blob mode:


(defun ems--magit-kill-this-buffer-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (emacspeak-speak-mode-line)))


(advice-add 'magit-kill-this-buffer :after
	    #'ems--magit-kill-this-buffer-after)





(defun ems--magit-blob-visit-file-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-mode-line)))


(advice-add 'magit-blob-visit-file :after
	    #'ems--magit-blob-visit-file-after)




(cl-loop
 for f in 
 '(magit-blob-previous magit-blob-next)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "Speak."
     (when (ems-interactive-p)
       (emacspeak-icon 'large-movement)))))

;;;  Additional commands to advice:


(defun ems--magit-refresh-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'task-done) (emacspeak-speak-line)))


(advice-add 'magit-refresh :after #'ems--magit-refresh-after)





(defun ems--magit-status-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'magit-status :after #'ems--magit-status-after)




(cl-loop
 for f in
 '(magit-mode-quit-window magit-mode-bury-buffer magit-log-bury-buffer)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act  comp)
     "speak."
     (when (ems-interactive-p)
       (with-current-buffer (window-buffer (selected-window))
         (emacspeak-icon 'close-object)
         (emacspeak-speak-mode-line))))))


(defun ems--magit-refresh-all-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'task-done) (emacspeak-speak-line)))


(advice-add 'magit-refresh-all :after #'ems--magit-refresh-all-after)





(defun ems--magit-display-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'magit-display-buffer :after
	    #'ems--magit-display-buffer-after)




;;;  Advise process-sentinel:


(defun ems--magit-process-finish-after (&rest _)
  "Produce auditory icon." (emacspeak-icon 'task-done))


(advice-add 'magit-process-finish :after
	    #'ems--magit-process-finish-after)




;;;  Magit Blame:

(defun emacspeak-magit-blame-speak ()
  "Summarize current blame chunk."
  (emacspeak-icon 'left)
  (dtk-speak
   (concat
    (buffer-substring (line-beginning-position) (line-end-position))
    (ems--display-props-get))))

(cl-loop
 for f in
 '(
   magit-blame-previous-chunk magit-blame-previous-chunk-same-commit
   magit-blame-next-chunk magit-blame-next-chunk-same-commit)
 do
 (eval
  `(defadvice ,f (after emacspeak pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacspeak-magit-blame-speak)
       (emacspeak-icon 'large-movement)))))


(defun ems--magit-blame-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (emacspeak-speak-mode-line)))


(advice-add 'magit-blame-quit :after #'ems--magit-blame-quit-after)




(defun ems--magit-blame-toggle-headings-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon (if magit-blame-show-headings 'on 'off))
    (message "Toggled blame headings.")))


(advice-add 'magit-blame-toggle-headings :after
	    #'ems--magit-blame-toggle-headings-after)





(defun ems--magit-blame-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Entering Magit Blame") (emacspeak-icon 'open-object)))


(advice-add 'magit-blame :after #'ems--magit-blame-after)





(defun ems--magit-diff-show-or-scroll-up-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((orig (point)))
	(apply orig-fun args)
	(cond
	 ((= orig (point))
	  (message "Displayed commit in other window.")
	  (emacspeak-icon 'open-object))
	 (t (emacspeak-icon 'scroll) (emacspeak-speak-line)))))
     (t (apply orig-fun args)))
    result))


(advice-add 'magit-diff-show-or-scroll-up :around
	    #'ems--magit-diff-show-or-scroll-up-around)




;;; Keys:
(cl-declaim (special magit-file-mode-map))
(when (and (bound-and-true-p magit-file-mode-map)
           (keymapp magit-file-mode-map))
  (define-key magit-file-mode-map (kbd "C-c g") 'magit-file-dispatch))
(cl-declaim (special ctl-x-map))
(define-key ctl-x-map  "g" 'magit-status)

;;; Rebase:


(defun ems--git-rebase-squash-after (&rest _)
  "speak." (when (ems-interactive-p) (emacspeak-speak-line)))


(advice-add 'git-rebase-squash :after #'ems--git-rebase-squash-after)




(provide 'emacspeak-magit)
;;;  end of file

