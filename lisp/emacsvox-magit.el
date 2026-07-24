;;; emacsvox-magit.el --- Speech-enable MAGIT -*- lexical-binding: t; -*-
;; $Id: emacsvox-magit.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable MAGIT An Emacs Interface to magit
;; Keywords: Emacsvox,  Audio Desktop magit
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
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
(require 'emacsvox-preamble)

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
(emacsvox-pronounce-add-dictionary-entry
 'magit-mode
 emacsvox-pronounce-sha-checksum-pattern
 (cons 're-search-forward
       'emacsvox-pronounce-sha-checksum))
(emacsvox-pronounce-add-super 'magit-mode 'magit-commit-mode)
(emacsvox-pronounce-add-super 'magit-mode 'magit-revision-mode)
(emacsvox-pronounce-add-super 'magit-mode 'magit-log-mode)

(add-hook
 'magit-mode-hook
 'emacsvox-pronounce-refresh-pronunciations)

;;;  Advice navigation commands:

(defconst emacsvox-magit--navigation-targets
  '(magit-section-forward
    magit-section-backward
    magit-section-up
    magit-next-line
    magit-previous-line
    magit-section-forward-sibling
    magit-section-backward-sibling
    magit-stash
    magit-unstage
    magit-unstage-all
    magit-file-unstage
    magit-stage
    magit-file-stage
    magit-stage-modified)
  "Current Magit navigation and staging commands.")

(cl-loop
 for target in emacsvox-magit--navigation-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak"
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

;;;  Section Toggle:

(defconst emacsvox-magit--show-targets
  '(magit-section-show-children
    magit-section-show-headings
    magit-show-commit
    magit-section-show-level-1
    magit-section-show-level-2
    magit-section-show-level-3
    magit-section-show-level-4
    magit-section-show-level-1-all
    magit-section-show-level-2-all
    magit-section-show-level-3-all
    magit-section-show-level-4-all
    magit-section-cycle-diffs)
  "Magit commands that reveal sections.")

(cl-loop
 for target in emacsvox-magit--show-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (emacsvox-speak-line)
     (emacsvox-icon 'open-object))))

(defun emacsvox--advice-magit-section-hide-after (&rest _)
  "Icon." (emacsvox-icon 'close-object))

(defun emacsvox--advice-magit-section-cycle-global-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-section-cycle-global)
    (tts-notify "Cycling global visibility of sections")))

(cl-loop
 for target in '(magit-section-toggle magit-section-cycle)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (section &rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-speak-line)
       (emacsvox-icon
        (if (oref section hidden) 'close-object 'open-object))))))

;;; blob mode:

(defun emacsvox--advice-magit-kill-this-buffer-after (&rest _)
  "Speak."
  (when (ems-interactive-p 'magit-kill-this-buffer)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-magit-blob-visit-file-after (&rest _)
  "Speak"
  (when (ems-interactive-p 'magit-blob-visit-file)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(cl-loop
 for target in '(magit-blob-previous magit-blob-next)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)))))

;;;  Additional commands to advice:

(defun emacsvox--advice-magit-refresh-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-refresh)
    (emacsvox-icon 'task-done) (emacsvox-speak-line)))

(defun emacsvox--advice-magit-status-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-status)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(cl-loop
 for target in
 '(magit-mode-quit-window magit-mode-bury-buffer magit-log-bury-buffer)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (with-current-buffer (window-buffer (selected-window))
         (emacsvox-icon 'close-object)
         (emacsvox-speak-mode-line))))))

(defun emacsvox--advice-magit-refresh-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-refresh-all)
    (emacsvox-icon 'task-done) (emacsvox-speak-line)))

(defun emacsvox--advice-magit-display-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-display-buffer)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

;;;  Advise process-sentinel:

(defun emacsvox--advice-magit-process-finish-after (&rest _)
  "Produce auditory icon." (emacsvox-icon 'task-done))

;;;  Magit Blame:

(defun emacsvox-magit-blame-speak ()
  "Summarize current blame chunk."
  (emacsvox-icon 'left)
  (tts-speak
   (concat
    (buffer-substring (line-beginning-position) (line-end-position))
    (ems--display-props-get))))

(cl-loop
 for target in
 '(magit-blame-previous-chunk
   magit-blame-previous-chunk-same-commit
   magit-blame-next-chunk
   magit-blame-next-chunk-same-commit)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-magit-blame-speak)
       (emacsvox-icon 'large-movement)))))

(defun emacsvox--advice-magit-blame-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-blame-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-magit-blame-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-blame)
    (message "Entering Magit Blame") (emacsvox-icon 'open-object)))

(defun emacsvox--advice-magit-diff-show-or-scroll-up-around
    (orig-fun &rest args)
  "speak."
  (let ((origin (point))
        (result (apply orig-fun args)))
    (when (ems-interactive-p 'magit-diff-show-or-scroll-up)
      (cond
       ((= origin (point))
        (message "Displayed commit in other window.")
        (emacsvox-icon 'open-object))
       (t
        (emacsvox-icon 'scroll)
        (emacsvox-speak-line))))
    result))

(defconst emacsvox-magit--quit-targets
  '(magit-mode-quit-window magit-mode-bury-buffer magit-log-bury-buffer)
  "Magit commands that close or bury their buffers.")

(defconst emacsvox-magit--blob-targets
  '(magit-blob-previous magit-blob-next)
  "Magit blob navigation commands.")

(defconst emacsvox-magit--blame-navigation-targets
  '(magit-blame-previous-chunk
    magit-blame-previous-chunk-same-commit
    magit-blame-next-chunk
    magit-blame-next-chunk-same-commit)
  "Magit blame navigation commands.")

(defconst emacsvox-magit--simple-advice-targets
  (append
   emacsvox-magit--navigation-targets
   emacsvox-magit--show-targets
   '(magit-section-hide
     magit-section-cycle-global
     magit-section-toggle
     magit-section-cycle
     magit-kill-this-buffer
     magit-blob-visit-file)
   emacsvox-magit--blob-targets
   '(magit-refresh magit-status)
   emacsvox-magit--quit-targets
   '(magit-refresh-all
     magit-display-buffer
     magit-process-finish)
   emacsvox-magit--blame-navigation-targets
   '(magit-blame-quit magit-blame))
  "Current Magit targets that receive native after advice.")

(defun emacsvox-magit--install-advice ()
  "Install advice for the Magit functions that are currently loaded."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (when
      (and
       (fboundp 'magit-diff-show-or-scroll-up)
       (not
        (advice-member-p
         #'emacsvox--advice-magit-diff-show-or-scroll-up-around
         'magit-diff-show-or-scroll-up)))
    (advice-add
     'magit-diff-show-or-scroll-up :around
     #'emacsvox--advice-magit-diff-show-or-scroll-up-around
     '((name . emacsvox)))))

(dolist
    (feature
     '(magit
       magit-apply
       magit-blame
       magit-diff
       magit-files
       magit-log
       magit-process
       magit-section))
  (eval-after-load feature #'emacsvox-magit--install-advice))

;;; Keys:
(cl-declaim (special magit-file-mode-map))
(when (and (bound-and-true-p magit-file-mode-map)
           (keymapp magit-file-mode-map))
  (define-key magit-file-mode-map (kbd "C-c g") 'magit-file-dispatch))
(cl-declaim (special ctl-x-map))
(define-key ctl-x-map  "g" 'magit-status)

;;; Rebase:

(defun emacsvox--advice-git-rebase-squash-after (&rest _)
  "speak."
  (when (ems-interactive-p 'git-rebase-squash)
    (emacsvox-speak-line)))

(defun emacsvox-magit--install-rebase-advice ()
  "Install advice after Git Rebase loads."
  (when
      (and
       (fboundp 'git-rebase-squash)
       (not
        (advice-member-p
         #'emacsvox--advice-git-rebase-squash-after
         'git-rebase-squash)))
    (advice-add
     'git-rebase-squash :after
     #'emacsvox--advice-git-rebase-squash-after
     '((name . emacsvox)))))

(with-eval-after-load 'git-rebase
  (emacsvox-magit--install-rebase-advice))

(provide 'emacsvox-magit)
;;;  end of file
