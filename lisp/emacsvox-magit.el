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
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)

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

;;; Semantic aural presentation:

(defun emacsvox-magit-enable-aural-context ()
  "Identify the current Magit buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'magit))

(add-hook 'magit-mode-hook #'emacsvox-magit-enable-aural-context)

(defun emacsvox-magit--call-with-aural-presentation
    (facts occasion function &rest arguments)
  "Call FUNCTION with ARGUMENTS in a frozen Magit presentation.
FACTS describe the object or event, and OCCASION describes the interaction."
  (emacsvox-aural-call-with-submission
   function
   :facts (or facts '(:role vcs-view :vcs-view-kind other))
   :module 'magit
   :occasion (or occasion 'navigation)
   :arguments arguments))

(defun emacsvox-magit--present-feedback
    (facts occasion icon function &rest arguments)
  "Under FACTS and OCCASION, present ICON then call FUNCTION with ARGUMENTS."
  (emacsvox-magit--call-with-aural-presentation
   facts occasion
   (lambda ()
     (when icon (emacsvox-icon icon))
     (apply function arguments))))

(defun emacsvox-magit-view-facts (kind event)
  "Return semantic facts for a Magit view of KIND undergoing EVENT."
  (list :role 'vcs-view :vcs-view-kind kind :events (list event)))

(defun emacsvox-magit-blame-facts (&optional event)
  "Return semantic facts for the current blame chunk and optional EVENT."
  (append
   '(:role vcs-blame-chunk)
   (when event (list :events (list event)))))

(defun emacsvox-magit-process-facts (failed)
  "Return semantic facts for a Magit process according to FAILED."
  (list
   :role 'vcs-process
   :events (list (if failed 'operation-failed 'operation-completed))))

(defun emacsvox-magit--section-value (section property)
  "Return SECTION's PROPERTY without requiring Magit at startup."
  (cond
   ((and (listp section)
         (plist-member section (intern (format ":%s" property))))
    (plist-get section (intern (format ":%s" property))))
   ((and section (fboundp 'slot-boundp)
         (ignore-errors (slot-boundp section property)))
    (ignore-errors (slot-value section property)))))

(defun emacsvox-magit-section-facts
    (&optional target section event visibility)
  "Return semantic facts for Magit TARGET and SECTION.

EVENT and VISIBILITY override values inferred from the command and section."
  (let* ((section
          (or
           section
           (and
            (fboundp 'magit-current-section)
            (ignore-errors (magit-current-section)))))
         (kind (or (emacsvox-magit--section-value section 'type) 'section))
         (hidden (emacsvox-magit--section-value section 'hidden))
         (stage-p
          (memq
           target
           '(magit-stage magit-file-stage magit-stage-modified)))
         (unstage-p
          (memq
           target
           '(magit-unstage magit-unstage-all magit-file-unstage)))
         (event
          (or event
              (cond
               (stage-p 'entry-staged)
               (unstage-p 'entry-unstaged)
               (t 'focus-entered))))
         (visibility
          (or visibility
              (and section (if hidden 'folded 'expanded))))
         states)
    (when stage-p (push 'staged states))
    (when unstage-p (push 'unstaged states))
    (append
     (list :role 'vcs-section :section-kind
           (if (symbolp kind) kind 'section))
     (when event (list :events (list event)))
     (when states (list :states states))
     (when visibility (list :visibility visibility)))))

(defun emacsvox-magit-present-line
    (icon occasion &optional target section event visibility icon-after)
  "Present the current Magit line semantically.

ICON, OCCASION, TARGET, SECTION, EVENT, and VISIBILITY describe the existing
  feedback.  When ICON-AFTER is non-nil, retain speech-before-icon ordering."
  (emacsvox-magit--call-with-aural-presentation
   (emacsvox-magit-section-facts target section event visibility)
   occasion
   (lambda ()
     (if icon-after
         (progn (emacsvox-speak-line) (emacsvox-icon icon))
       (emacsvox-icon icon)
       (emacsvox-speak-line)))))

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
       (emacsvox-magit-present-line
        'select-object
        ,(if
             (memq
              target
              '(magit-stash magit-unstage magit-unstage-all
                magit-file-unstage magit-stage magit-file-stage
                magit-stage-modified))
             ''state-change
           ''navigation)
        ',target)))))

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
     (emacsvox-magit-present-line
      'open-object 'state-change ',target nil
      'visibility-changed 'expanded t))))

(defun emacsvox--advice-magit-section-hide-after (&rest _)
  "Present a hidden Magit section."
  (emacsvox-magit--present-feedback
   (emacsvox-magit-section-facts
    'magit-section-hide nil 'visibility-changed 'folded)
   'state-change 'close-object #'ignore))

(defun emacsvox--advice-magit-section-cycle-global-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-section-cycle-global)
    (emacsvox-magit--call-with-aural-presentation
     (emacsvox-magit-section-facts
      'magit-section-cycle-global nil 'visibility-changed)
     'state-change
     #'tts-notify "Cycling global visibility of sections")))

(cl-loop
 for target in '(magit-section-toggle magit-section-cycle)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (section &rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (let* ((hidden (emacsvox-magit--section-value section 'hidden))
              (visibility (if hidden 'folded 'expanded)))
         (emacsvox-magit-present-line
          (if hidden 'close-object 'open-object)
          'state-change ',target section
          'visibility-changed visibility t))))))

;;; blob mode:

(defun emacsvox--advice-magit-kill-this-buffer-after (&rest _)
  "Speak."
  (when (ems-interactive-p 'magit-kill-this-buffer)
    (emacsvox-magit--present-feedback
     (emacsvox-magit-view-facts 'other 'vcs-view-closed)
     'state-change 'close-object #'emacsvox-speak-mode-line)))

(defun emacsvox--advice-magit-blob-visit-file-after (&rest _)
  "Speak"
  (when (ems-interactive-p 'magit-blob-visit-file)
    (emacsvox-magit--present-feedback
     (emacsvox-magit-view-facts 'blob 'vcs-view-opened)
     'navigation 'open-object #'emacsvox-speak-mode-line)))

(cl-loop
 for target in '(magit-blob-previous magit-blob-next)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak."
     (when (ems-interactive-p ',target)
       (emacsvox-magit--present-feedback
        (emacsvox-magit-view-facts 'blob 'focus-entered)
        'navigation 'large-movement #'ignore)))))

;;;  Additional commands to advice:

(defun emacsvox--advice-magit-refresh-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-refresh)
    (emacsvox-magit-present-line
     'task-done 'notification 'magit-refresh nil
     'refresh-completed)))

(defun emacsvox--advice-magit-status-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-status)
    (emacsvox-magit--present-feedback
     (emacsvox-magit-view-facts 'status 'vcs-view-opened)
     'state-change 'open-object #'emacsvox-speak-line)))

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
         (emacsvox-magit--present-feedback
          (emacsvox-magit-view-facts 'other 'vcs-view-closed)
          'state-change 'close-object #'emacsvox-speak-mode-line))))))

(defun emacsvox--advice-magit-refresh-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-refresh-all)
    (emacsvox-magit-present-line
     'task-done 'notification 'magit-refresh-all nil
     'refresh-completed)))

(defun emacsvox--advice-magit-display-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-display-buffer)
    (emacsvox-magit--present-feedback
     (emacsvox-magit-view-facts 'other 'vcs-view-opened)
     'navigation 'open-object #'emacsvox-speak-line)))

;;;  Advise process-sentinel:

(defun emacsvox--advice-magit-process-finish-after
    (&optional process &rest _)
  "Present semantic completion or failure for Magit PROCESS."
  (let* ((failed
          (and
           (processp process)
           (memq (process-status process) '(exit signal))
           (not (zerop (process-exit-status process)))))
         (icon (if failed 'warn-user 'task-done)))
    (emacsvox-magit--present-feedback
     (emacsvox-magit-process-facts failed)
     'notification icon #'ignore)))

;;;  Magit Blame:

(defun emacsvox-magit--blame-content ()
  "Return the voice-preserving summary of the current blame chunk."
  (concat
   (buffer-substring (line-beginning-position) (line-end-position))
   (ems--display-props-get)))

(defun emacsvox-magit-blame-speak (&optional movement-icon)
  "Summarize the current blame chunk.
Present optional MOVEMENT-ICON after the chunk."
  (let ((content (emacsvox-magit--blame-content))
        (facts (emacsvox-magit-blame-facts 'focus-entered)))
    (if (> (length content) 0)
        (emacsvox-aural-submit
         content
         :facts facts
         :module 'magit
         :occasion 'navigation
         :compatibility-actions
         (append
          (list (emacsvox-aural-compatibility-icon 'left))
          (when movement-icon
            (list
             (emacsvox-aural-compatibility-icon
              movement-icon 'after)))))
      (emacsvox-magit--call-with-aural-presentation
       facts 'navigation
       (lambda ()
         (emacsvox-icon 'left)
         (tts-speak content)
         (when movement-icon
           (emacsvox-icon movement-icon)))))))

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
       (emacsvox-magit-blame-speak 'large-movement)))))

(defun emacsvox--advice-magit-blame-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-blame-quit)
    (emacsvox-magit--present-feedback
     (emacsvox-magit-view-facts 'blame 'vcs-view-closed)
     'state-change 'close-object #'emacsvox-speak-mode-line)))

(defun emacsvox--advice-magit-blame-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-blame)
    (emacsvox-magit--call-with-aural-presentation
     (emacsvox-magit-view-facts 'blame 'vcs-view-opened)
     'state-change
     (lambda ()
       (message "Entering Magit Blame")
       (emacsvox-icon 'open-object)))))

(defun emacsvox--advice-magit-diff-show-or-scroll-up-around
    (orig-fun &rest args)
  "speak."
  (let ((origin (point))
        (result (apply orig-fun args)))
    (when (ems-interactive-p 'magit-diff-show-or-scroll-up)
      (cond
       ((= origin (point))
        (message "Displayed commit in other window.")
        (emacsvox-magit--present-feedback
         (emacsvox-magit-view-facts 'commit 'vcs-commit-displayed)
         'state-change 'open-object #'ignore))
       (t
        (emacsvox-magit--present-feedback
         (emacsvox-magit-view-facts 'diff 'vcs-diff-scrolled)
         'navigation 'scroll #'emacsvox-speak-line))))
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
