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

(require 'cl-lib)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-provider-workflows)

;;; Forward declarations:

(defvar git-commit-mode)
(defvar magit-blame-mode)
(defvar magit-blob-mode)
(defvar with-editor-post-cancel-hook)
(defvar with-editor-post-finish-hook)

;;;  Map voices to faces:

(defconst emacsvox-magit--face-voice-map
  '((git-commit-comment-action voice-annotate)
    (git-commit-comment-branch-local voice-brighten)
    (git-commit-comment-branch-remote voice-smoothen)
    (git-commit-comment-button voice-lighten)
    (git-commit-comment-detached voice-monotone-extra)
    (git-commit-comment-file voice-lighten)
    (git-commit-comment-heading voice-bolden)
    (git-commit-keyword voice-animate)
    (git-commit-nonempty-second-line voice-bolden-and-animate)
    (git-commit-overlong-summary voice-bolden-and-animate)
    (git-commit-summary voice-bolden)
    (git-commit-trailer-token voice-annotate)
    (git-commit-trailer-value voice-lighten)
    (git-rebase-action voice-animate)
    (git-rebase-comment-hash inaudible)
    (git-rebase-comment-heading voice-bolden)
    (git-rebase-description voice-lighten)
    (git-rebase-hash inaudible)
    (git-rebase-killed-action voice-smoothen)
    (git-rebase-label voice-annotate)
    (magit-bisect-bad voice-animate)
   (magit-bisect-good voice-lighten)
   (magit-bisect-skip voice-monotone-extra)
   (magit-blame-date voice-bolden-and-animate)
   (magit-blame-dimmed voice-smoothen)
   (magit-blame-hash voice-monotone-extra)
   (magit-blame-heading voice-bolden)
   (magit-blame-highlight voice-brighten)
   (magit-blame-margin voice-smoothen)
   (magit-blame-name voice-animate)
   (magit-blame-summary voice-lighten)
   (magit-branch-current voice-lighten)
   (magit-branch-local voice-brighten)
   (magit-branch-remote voice-smoothen)
   (magit-branch-remote-head voice-bolden)
   (magit-branch-upstream voice-animate)
   (magit-branch-warning voice-bolden-and-animate)
   (magit-cherry-equivalent voice-lighten)
   (magit-cherry-unmatched voice-bolden)
   (magit-diff-added voice-animate-extra)
   (magit-diff-added-highlight voice-animate-extra)
   (magit-diff-added-indicator voice-animate-extra)
   (magit-diff-base voice-annotate)
   (magit-diff-base-heading voice-annotate)
   (magit-diff-base-highlight voice-animate)
   (magit-diff-base-indicator voice-annotate)
   (magit-diff-conflict-heading voice-bolden-extra)
   (magit-diff-conflict-heading-highlight voice-bolden-and-animate)
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
   (magit-diff-our-heading voice-smoothen)
   (magit-diff-our-highlight voice-lighten)
   (magit-diff-our-indicator voice-smoothen)
   (magit-diff-removed voice-monotone-extra)
   (magit-diff-removed-highlight voice-smoothen)
   (magit-diff-removed-indicator voice-monotone-extra)
   (magit-diff-revision-summary voice-monotone-extra)
   (magit-diff-revision-summary-highlight voice-animate-extra)
   (magit-diff-their voice-animate)
   (magit-diff-their-heading voice-animate)
   (magit-diff-their-highlight voice-bolden-and-animate)
   (magit-diff-their-indicator voice-animate)
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
   (magit-mode-line-process voice-animate)
   (magit-mode-line-process-error voice-bolden-and-animate)
   (magit-process-ng voice-bolden-and-animate)
   (magit-process-ok voice-lighten)
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
   (magit-refname-pullreq voice-animate)
   (magit-refname-stash voice-monotone-extra)
   (magit-refname-wip voice-lighten)
   (magit-section-child-count voice-annotate)
   (magit-section-heading voice-bolden)
   (magit-section-heading-selection voice-bolden-medium)
   (magit-section-highlight voice-bolden)
   (magit-section-secondary-heading voice-bolden-medium)
   (magit-sequence-done voice-monotone-extra)
   (magit-sequence-drop voice-lighten)
   (magit-sequence-exec voice-annotate)
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
   (magit-tag voice-smoothen))
  "Voice personalities for the current Magit and Git editing faces.")

(defconst emacsvox-magit--unvoiced-faces
  '(magit-left-margin)
  "Magit faces intentionally left without a voice.
The left-margin face is purely graphical and contains no spoken content.")

(voice-setup-add-map emacsvox-magit--face-voice-map)

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

(defconst emacsvox-magit--no-local-aural-module
  (make-symbol "no-local-aural-module")
  "Sentinel recording that a minor Magit view inherited its aural module.")

(defvar-local emacsvox-magit--saved-aural-module
    emacsvox-magit--no-local-aural-module
  "Aural module that preceded a Magit minor view in the current buffer.")

(defvar-local emacsvox-magit--aural-context-owners nil
  "Active Magit minor views currently owning the buffer's aural context.")

(defun emacsvox-magit-enable-aural-context ()
  "Identify the current Magit buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'magit)
  (add-hook
   'magit-section-movement-hook
   #'emacsvox-magit--section-moved nil t))

(add-hook 'magit-mode-hook #'emacsvox-magit-enable-aural-context)
(add-hook 'magit-repolist-mode-hook #'emacsvox-magit-enable-aural-context)
(add-hook 'git-rebase-mode-hook #'emacsvox-magit-enable-aural-context)

(defun emacsvox-magit--update-minor-mode-context (owner enabled)
  "Add or remove OWNER according to ENABLED and preserve prior context."
  (if enabled
      (progn
        (unless emacsvox-magit--aural-context-owners
          (setq
           emacsvox-magit--saved-aural-module
           (if (local-variable-p 'emacsvox-aural-module)
               emacsvox-aural-module
             emacsvox-magit--no-local-aural-module)))
        (cl-pushnew owner emacsvox-magit--aural-context-owners)
        (setq-local emacsvox-aural-module 'magit))
    (when (memq owner emacsvox-magit--aural-context-owners)
      (setq emacsvox-magit--aural-context-owners
            (delq owner emacsvox-magit--aural-context-owners))
      (unless emacsvox-magit--aural-context-owners
        (if
            (eq
             emacsvox-magit--saved-aural-module
             emacsvox-magit--no-local-aural-module)
            (kill-local-variable 'emacsvox-aural-module)
          (setq-local
           emacsvox-aural-module
           emacsvox-magit--saved-aural-module))
        (setq
         emacsvox-magit--saved-aural-module
         emacsvox-magit--no-local-aural-module)))))

(defun emacsvox-magit--update-blame-context ()
  "Update semantic ownership for the current Magit Blame minor view."
  (emacsvox-magit--update-minor-mode-context
   'blame (bound-and-true-p magit-blame-mode)))

(defun emacsvox-magit--update-blob-context ()
  "Update semantic ownership for the current Magit Blob minor view."
  (emacsvox-magit--update-minor-mode-context
   'blob (bound-and-true-p magit-blob-mode)))

(defun emacsvox-magit--update-commit-context ()
  "Update semantic ownership for the current Git Commit editor."
  (emacsvox-magit--update-minor-mode-context
   'commit (bound-and-true-p git-commit-mode)))

(add-hook 'magit-blame-mode-hook #'emacsvox-magit--update-blame-context)
(add-hook 'magit-blob-mode-hook #'emacsvox-magit--update-blob-context)
(add-hook 'git-commit-mode-hook #'emacsvox-magit--update-commit-context)

(defun emacsvox-magit-current-view-kind ()
  "Return the semantic kind of the current Magit-related view."
  (cond
   ((bound-and-true-p magit-blame-mode) 'blame)
   ((bound-and-true-p magit-blob-mode) 'blob)
   ((bound-and-true-p git-commit-mode) 'commit)
   ((derived-mode-p 'git-rebase-mode) 'rebase)
   ((derived-mode-p 'magit-repolist-mode) 'repositories)
   ((derived-mode-p 'magit-process-mode) 'process)
   ((derived-mode-p 'magit-status-mode) 'status)
   ((derived-mode-p 'magit-revision-mode) 'commit)
   ((derived-mode-p 'magit-refs-mode) 'refs)
   ((derived-mode-p 'magit-log-mode 'magit-reflog-mode) 'log)
   ((derived-mode-p 'magit-diff-mode) 'diff)
   (t 'other)))

(defun emacsvox-magit--submit-actions (facts occasion &rest icons)
  "Submit FACTS and compatibility ICONS as one action-only transaction."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'magit
   :occasion occasion
   :compatibility-actions
   (mapcar #'emacsvox-aural-compatibility-icon icons)))

(defun emacsvox-magit--submit-text
    (content facts occasion &optional icon icon-phase)
  "Submit CONTENT under FACTS and OCCASION with optional compatibility ICON.
ICON-PHASE defaults to `before'."
  (if (and (stringp content) (> (length content) 0))
      (emacsvox-aural-submit
       content
       :facts facts
       :module 'magit
       :occasion occasion
       :compatibility-actions
       (when icon
         (list
          (emacsvox-aural-compatibility-icon icon icon-phase))))
    (when icon
      (emacsvox-magit--submit-actions facts occasion icon))))

(defun emacsvox-magit--buffer-summary ()
  "Return a concise voice-preserving summary of the selected buffer."
  (concat
   (propertize (buffer-name) 'personality voice-lighten-medium)
   ", "
   (propertize
    (downcase (format-mode-line mode-name))
    'personality voice-animate)))

(defun emacsvox-magit--line-content ()
  "Return the current line with speech-relevant text properties intact.
Also include display, before-string, and after-string content at point."
  (concat
   (buffer-substring (line-beginning-position) (line-end-position))
   (ems--display-props-get)))

(defun emacsvox-magit-view-facts (kind event)
  "Return semantic facts for a Magit view of KIND undergoing EVENT."
  (append
   (list :role 'vcs-view :vcs-view-kind kind)
   (when event (list :events (list event)))))

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

(defun emacsvox-magit-repository-facts (operation &optional event)
  "Return semantic facts for repository OPERATION and optional EVENT."
  (append
   (list :role 'vcs-repository :vcs-operation operation)
   (when event (list :events (list event)))))

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
  (emacsvox-magit--submit-text
   (emacsvox-magit--line-content)
   (emacsvox-magit-section-facts target section event visibility)
   occasion icon (and icon-after 'after)))

;;;  Advice navigation commands:

(defconst emacsvox-magit--section-movement-targets
  '(magit-section-forward
    magit-section-backward
    magit-section-up
    magit-section-forward-sibling
    magit-section-backward-sibling)
  "Commands presented centrally by `magit-section-movement-hook'.")

(defconst emacsvox-magit--section-jump-targets
  '(magit-jump-to-unpulled-from-upstream
    magit-jump-to-unpulled-from-pushremote
    magit-jump-to-unpushed-to-upstream
    magit-jump-to-unpushed-to-pushremote
    magit-jump-to-revision-headers
    magit-jump-to-revision-message
    magit-jump-to-revision-notes
    magit-jump-to-unstaged
    magit-jump-to-staged
    magit-jump-to-stashes
    magit-jump-to-untracked
    magit-jump-to-tracked
    magit-jump-to-ignored
    magit-jump-to-skip-worktree
    magit-jump-to-assume-unchanged)
  "Current Magit section jumpers that bypass the movement hook.")

(defun emacsvox-magit--section-moved (section)
  "Present SECTION after an interactive central section movement."
  (let ((target ems--interactive-fn-name))
    (when
        (and
         (memq target emacsvox-magit--section-movement-targets)
         (ems-interactive-p target))
      (emacsvox-magit-present-line
       'select-object 'navigation target section))))

(defconst emacsvox-magit--navigation-targets
  (append
   '(magit-next-line
    magit-previous-line
    magit-unstage
    magit-unstage-all
    magit-file-unstage
    magit-stage
    magit-file-stage
     magit-stage-modified)
   emacsvox-magit--section-jump-targets)
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
    magit-section-show-level-1
    magit-section-show-level-2
    magit-section-show-level-3
    magit-section-show-level-4
    magit-section-show-level-1-all
    magit-section-show-level-2-all
    magit-section-show-level-3-all
    magit-section-show-level-4-all)
  "Magit commands that reveal sections.")

(cl-loop
 for target in emacsvox-magit--show-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-magit-present-line
        'open-object 'state-change ',target nil
        'visibility-changed 'expanded t)))))

(defun emacsvox--advice-magit-section-hide-after (&rest _)
  "Present a hidden Magit section."
  (when (ems-interactive-p 'magit-section-hide)
    (emacsvox-magit--submit-actions
     (emacsvox-magit-section-facts
      'magit-section-hide nil 'visibility-changed 'folded)
     'state-change 'close-object)))

(defun emacsvox--advice-magit-show-commit-after (&rest _)
  "Present a commit view opened by an interactive Magit command."
  (when (ems-interactive-p 'magit-show-commit)
    (emacsvox-magit--submit-text
     (emacsvox-magit--line-content)
     (emacsvox-magit-view-facts 'commit 'vcs-view-opened)
     'navigation 'open-object)))

(defun emacsvox--advice-magit-section-cycle-diffs-after (&rest _)
  "Present an interactive aggregate diff-visibility change."
  (when (ems-interactive-p 'magit-section-cycle-diffs)
    (emacsvox-magit--submit-text
     (emacsvox-magit--line-content)
     (emacsvox-magit-view-facts 'diff 'visibility-changed)
     'state-change 'large-movement)))

(defun emacsvox--advice-magit-section-cycle-global-after (&rest _)
  "Present an aggregate section-visibility change."
  (when (ems-interactive-p 'magit-section-cycle-global)
    (emacsvox-magit--submit-text
     "Cycled global section visibility"
     (emacsvox-magit-section-facts
      'magit-section-cycle-global nil 'visibility-changed)
     'state-change)))

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
  "Present the buffer selected after killing a Magit buffer."
  (when (ems-interactive-p 'magit-kill-this-buffer)
    (emacsvox-magit--submit-text
     (emacsvox-magit--buffer-summary)
     (emacsvox-magit-view-facts 'other 'vcs-view-closed)
     'state-change 'close-object)))

(defun emacsvox--advice-magit-blob-visit-file-after (&rest _)
  "Present the source file visited from a blob."
  (when (ems-interactive-p 'magit-blob-visit-file)
    (emacsvox-magit--submit-text
     (emacsvox-magit--buffer-summary)
     (emacsvox-magit-view-facts 'blob 'vcs-view-opened)
     'navigation 'open-object)))

(cl-loop
 for target in '(magit-blob-previous magit-blob-next)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak."
     (when (ems-interactive-p ',target)
       (emacsvox-magit--submit-actions
        (emacsvox-magit-view-facts 'blob 'focus-entered)
        'navigation 'large-movement)))))

;;;  Additional commands to advice:

(defun emacsvox--advice-magit-refresh-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-refresh)
    (emacsvox-magit-present-line
     'task-done 'notification 'magit-refresh nil
     'refresh-completed)))

(defun emacsvox--advice-magit-status-after (&rest _)
  "Present a newly selected status view."
  (when (ems-interactive-p 'magit-status)
    (emacsvox-magit--submit-text
     (emacsvox-magit--line-content)
     (emacsvox-magit-view-facts 'status 'vcs-view-opened)
     'state-change 'open-object)))

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
         (emacsvox-magit--submit-text
          (emacsvox-magit--buffer-summary)
          (emacsvox-magit-view-facts 'other 'vcs-view-closed)
          'state-change 'close-object))))))

(defun emacsvox--advice-magit-refresh-all-after (&rest _)
  "speak."
  (when (ems-interactive-p 'magit-refresh-all)
    (emacsvox-magit-present-line
     'task-done 'notification 'magit-refresh-all nil
     'refresh-completed)))

(defun emacsvox--advice-magit-display-buffer-after (&rest _)
  "Present a Magit buffer displayed directly by the user."
  (when (ems-interactive-p 'magit-display-buffer)
    (emacsvox-magit--submit-text
     (emacsvox-magit--line-content)
     (emacsvox-magit-view-facts 'other 'vcs-view-opened)
     'navigation 'open-object)))

;;;  Advise process-sentinel:

(defun emacsvox--advice-magit-process-finish-after (argument &rest _)
  "Present completion or failure when ARGUMENT is an asynchronous process."
  (when (processp argument)
    (let* ((failed
            (or
             (eq (process-status argument) 'signal)
           (not (zerop (process-exit-status argument)))))
           (icon (if failed 'warn-user 'task-done)))
      (emacsvox-magit--submit-actions
       (emacsvox-magit-process-facts failed)
       'notification icon))))

;;;  Magit Blame:

(defun emacsvox-magit--blame-content ()
  "Return the voice-preserving summary of the current blame chunk."
  (emacsvox-magit--line-content))

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
      (apply
       #'emacsvox-magit--submit-actions
       facts 'navigation
       (append '(left) (when movement-icon (list movement-icon)))))))

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
  "Present the buffer selected after leaving blame."
  (when (ems-interactive-p 'magit-blame-quit)
    (emacsvox-magit--submit-text
     (emacsvox-magit--buffer-summary)
     (emacsvox-magit-view-facts 'blame 'vcs-view-closed)
     'state-change 'close-object)))

(defun emacsvox--advice-magit-blame-after (&rest _)
  "Present entry into Magit Blame."
  (when (ems-interactive-p 'magit-blame)
    (emacsvox-magit--submit-text
     "Entering Magit Blame"
     (emacsvox-magit-view-facts 'blame 'vcs-view-opened)
     'state-change 'open-object)))

(defun emacsvox--advice-magit-diff-show-or-scroll-up-around
    (orig-fun &rest args)
  "speak."
  (let ((origin (point))
        (result (apply orig-fun args)))
    (when (ems-interactive-p 'magit-diff-show-or-scroll-up)
      (cond
       ((= origin (point))
        (emacsvox-magit--submit-text
         "Displayed commit in other window"
         (emacsvox-magit-view-facts 'commit 'vcs-commit-displayed)
         'state-change 'open-object))
       (t
        (emacsvox-magit--submit-text
         (emacsvox-magit--line-content)
         (emacsvox-magit-view-facts 'diff 'vcs-diff-scrolled)
         'navigation 'scroll))))
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
     magit-show-commit
     magit-section-cycle-diffs
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
       magit-repos
       magit-section
       magit-stash
       magit-status))
  (eval-after-load feature #'emacsvox-magit--install-advice))

;;; Repository list:

(defun emacsvox-magit--repolist-id ()
  "Return the repository identifier at point, if any."
  (and
   (fboundp 'tabulated-list-get-id)
   (ignore-errors (tabulated-list-get-id))))

(defun emacsvox-magit--repository-label (repository)
  "Return a concise label for REPOSITORY."
  (if (and (stringp repository) (> (length repository) 0))
      (file-name-nondirectory (directory-file-name repository))
    "repository"))

(defun emacsvox-magit--repolist-result-content (label)
  "Return LABEL followed by the newly focused repository row."
  (let ((line (emacsvox-magit--line-content)))
    (concat
     (propertize (concat label ". ") 'personality voice-annotate)
     line)))

(defun emacsvox-magit--call-repolist-tag
    (original target operation event icon arguments)
  "Call ORIGINAL with ARGUMENTS and present a repository tag change.
TARGET, OPERATION, EVENT, and ICON describe the interaction."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let* ((repository (emacsvox-magit--repolist-id))
           (result (apply original arguments)))
      (when (ems-interactive-p target)
        (emacsvox-magit--submit-text
         (emacsvox-magit--repolist-result-content
          (format
           "%s %s"
           (if (eq operation 'mark) "Marked" "Unmarked")
           (emacsvox-magit--repository-label repository)))
         (emacsvox-magit-repository-facts operation event)
         'state-change icon))
      result)))

(defun emacsvox--advice-magit-repolist-mark-around
    (original &rest arguments)
  "Present an interactively marked repository."
  (emacsvox-magit--call-repolist-tag
   original 'magit-repolist-mark 'mark 'entry-marked
   'mark-object arguments))

(defun emacsvox--advice-magit-repolist-unmark-around
    (original &rest arguments)
  "Present an interactively unmarked repository."
  (emacsvox-magit--call-repolist-tag
   original 'magit-repolist-unmark 'unmark 'entry-unmarked
   'unmark-object arguments))

(defun emacsvox--advice-magit-list-repositories-after (&rest _)
  "Present a repository list opened by the user."
  (when (ems-interactive-p 'magit-list-repositories)
    (emacsvox-magit--submit-text
     (emacsvox-magit--repolist-result-content "Repository list")
     (emacsvox-magit-view-facts 'repositories 'vcs-view-opened)
     'navigation 'open-object)))

(defun emacsvox--advice-magit-repolist-status-after (&rest _)
  "Present a status buffer opened from a repository list."
  (when (ems-interactive-p 'magit-repolist-status)
    (emacsvox-magit--submit-text
     (emacsvox-magit--line-content)
     (append
      (emacsvox-magit-view-facts 'status 'vcs-view-opened)
      '(:vcs-operation open-status))
     'navigation 'open-object)))

(defun emacsvox--advice-magit-repolist-refresh-after (&rest _)
  "Present a repository-list refresh requested through `revert-buffer'."
  (when
      (and
       (derived-mode-p 'magit-repolist-mode)
       (ems-interactive-p 'revert-buffer))
    (emacsvox-magit--submit-text
     (emacsvox-magit--repolist-result-content "Refreshed repositories")
     (emacsvox-magit-repository-facts 'refresh 'refresh-completed)
     'notification 'task-done)))

(defun emacsvox-magit--repository-set-description (repositories)
  "Return a concise description of REPOSITORIES."
  (if (eq repositories 'all)
      "all displayed repositories"
    (format
     "%d %s"
     (length repositories)
     (if (= (length repositories) 1) "repository" "repositories"))))

(defun emacsvox--advice-magit-repolist-fetch-around
    (original repositories &rest arguments)
  "Present aggregate fetch lifecycle for REPOSITORIES."
  (if (not (ems-interactive-p 'magit-repolist-fetch))
      (apply original repositories arguments)
    (let ((description
           (emacsvox-magit--repository-set-description repositories))
          (facts
           (append
            (emacsvox-magit-view-facts 'repositories nil)
            '(:vcs-operation fetch))))
      (emacsvox-magit--submit-text
       (format "Fetching %s" description)
       facts 'notification 'progress)
      (condition-case error-data
          (let ((result (apply original repositories arguments)))
            (emacsvox-magit--submit-text
             (format "Fetched %s" description)
             (plist-put
              (copy-sequence facts)
              :events '(operation-completed))
             'notification 'task-done)
            result)
        (error
         (emacsvox-magit--submit-text
          (format "Failed to fetch %s" description)
          (plist-put
           (copy-sequence facts)
           :events '(operation-failed))
          'notification 'warn-user)
         (signal (car error-data) (cdr error-data)))))))

(defun emacsvox--advice-magit-repolist-find-file-other-frame-around
    (original repositories file &rest arguments)
  "Present FILE opened across REPOSITORIES."
  (if
      (not
       (ems-interactive-p 'magit-repolist-find-file-other-frame))
      (apply original repositories file arguments)
    (let* ((result (apply original repositories file arguments))
           (description
            (emacsvox-magit--repository-set-description repositories)))
      (emacsvox-magit--submit-text
       (format "Opened %s in %s" file description)
       (append
        (emacsvox-magit-view-facts 'repositories 'operation-completed)
        '(:vcs-operation find-file))
       'state-change 'open-object)
      result)))

(defconst emacsvox-magit--repolist-around-advice
  '((magit-repolist-mark
     emacsvox--advice-magit-repolist-mark-around)
    (magit-repolist-unmark
     emacsvox--advice-magit-repolist-unmark-around)
    (magit-repolist-fetch
     emacsvox--advice-magit-repolist-fetch-around)
    (magit-repolist-find-file-other-frame
     emacsvox--advice-magit-repolist-find-file-other-frame-around))
  "Around advice for repository-list interactions.")

(defconst emacsvox-magit--repolist-after-advice
  '((magit-list-repositories
     emacsvox--advice-magit-list-repositories-after)
    (magit-repolist-status
     emacsvox--advice-magit-repolist-status-after)
    (magit-repolist-refresh
     emacsvox--advice-magit-repolist-refresh-after))
  "After advice for repository-list interactions.")

(defun emacsvox-magit--install-repolist-advice ()
  "Install current repository-list advice."
  (dolist (entry emacsvox-magit--repolist-around-advice)
    (pcase-let ((`(,target ,function) entry))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox))))))
  (dolist (entry emacsvox-magit--repolist-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'magit-repos
  (emacsvox-magit--install-repolist-advice))

;;; Keys:
(cl-declaim (special magit-file-mode-map))
(when (and (bound-and-true-p magit-file-mode-map)
           (keymapp magit-file-mode-map))
  (define-key magit-file-mode-map (kbd "C-c g") 'magit-file-dispatch))
(cl-declaim (special ctl-x-map))
(define-key ctl-x-map  "g" 'magit-status)

;;; Rebase:

(defconst emacsvox-magit--rebase-action-targets
  '((git-rebase-pick pick select-object)
    (git-rebase-drop drop delete-object)
    (git-rebase-reword reword select-object)
    (git-rebase-edit edit select-object)
    (git-rebase-squash squash select-object)
    (git-rebase-squish fixup-edit-current select-object)
    (git-rebase-fixup fixup select-object)
    (git-rebase-alter fixup-use-current select-object)
    (git-rebase-kill-line toggle-comment delete-object)
    (git-rebase-insert insert open-object)
    (git-rebase-exec exec select-object)
    (git-rebase-label label select-object)
    (git-rebase-reset reset select-object)
    (git-rebase-update-ref update-ref select-object)
    (git-rebase-merge merge select-object)
    (git-rebase-merge-toggle-editmsg toggle-merge-message select-object)
    (git-rebase-noop noop select-object)
    (git-rebase-break break select-object)
    (git-rebase-move-line-up move-up large-movement)
    (git-rebase-move-line-down move-down large-movement)
    (git-rebase-undo undo large-movement))
  "Interactive rebase editing commands, operations, and compatibility cues.")

(defconst emacsvox-magit--rebase-view-targets
  '((git-rebase-show-commit open-object)
    (git-rebase-show-or-scroll-up scroll)
    (git-rebase-show-or-scroll-down scroll))
  "Interactive rebase commands that display or scroll a commit.")

(defun emacsvox-magit--rebase-action-symbol ()
  "Return the normalized rebase action at point, if one is recognized."
  (when (fboundp 'git-rebase-current-line)
    (let* ((entry (ignore-errors (git-rebase-current-line)))
           (action (emacsvox-magit--section-value entry 'action))
           (options
            (emacsvox-magit--section-value entry 'action-options)))
      (when (and (stringp action) (> (length action) 0))
        (cond
         ((member action '("f -c" "fixup -c")) 'fixup-edit-message)
         ((member action '("f -C" "fixup -C")) 'fixup-use-message)
         ((and
           (equal action "merge")
           (string-prefix-p "-c " (or options "")))
          'merge-edit-message)
         ((and
           (equal action "merge")
           (string-prefix-p "-C " (or options "")))
          'merge-use-message)
         (t
          (intern
           (replace-regexp-in-string
            "[[:space:]]+" "-"
            (downcase action)))))))))

(defun emacsvox-magit-rebase-facts (operation event)
  "Return semantic facts for rebase OPERATION and EVENT at point."
  (let ((action (emacsvox-magit--rebase-action-symbol)))
    (append
     '(:role vcs-rebase-entry)
     (when operation (list :vcs-operation operation))
     (when action (list :vcs-rebase-action action))
     (when event (list :events (list event))))))

(defun emacsvox-magit--rebase-operation-label (operation)
  "Return a concise spoken label for rebase OPERATION."
  (capitalize
   (replace-regexp-in-string "-" " " (symbol-name operation))))

(defun emacsvox-magit--present-rebase-line
    (operation event occasion icon &optional announcement)
  "Present the current rebase line under OPERATION, EVENT, and OCCASION.
Present compatibility ICON before the line.  ANNOUNCEMENT may be a string
to prepend, or non-nil to prepend the default operation label."
  (let ((content (emacsvox-magit--line-content)))
    (when announcement
      (setq
       content
       (concat
        (propertize
         (format
          "%s. "
          (if (stringp announcement)
              announcement
            (emacsvox-magit--rebase-operation-label operation)))
         'personality voice-annotate)
        content)))
    (emacsvox-magit--submit-text
     content
     (emacsvox-magit-rebase-facts operation event)
     occasion icon)))

(defun emacsvox-magit--call-rebase-action
    (original target operation icon arguments)
  "Call ORIGINAL with ARGUMENTS and present interactive rebase TARGET.
OPERATION and ICON describe the requested edit."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (if (= tick (buffer-chars-modified-tick))
            (emacsvox-magit--present-rebase-line
             operation 'operation-failed 'state-change 'warn-user
             (format
              "No %s change"
              (downcase
               (emacsvox-magit--rebase-operation-label operation))))
          (emacsvox-magit--present-rebase-line
           operation 'operation-completed 'state-change icon t)))
      result)))

(cl-loop
 for (target operation icon) in emacsvox-magit--rebase-action-targets
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present the result of an interactive rebase edit."
     (emacsvox-magit--call-rebase-action
      original ',target ',operation ',icon arguments))))

(defun emacsvox--advice-git-rebase-backward-line-after (&rest _)
  "Present the rebase entry selected by backward movement."
  (when (ems-interactive-p 'git-rebase-backward-line)
    (emacsvox-magit--present-rebase-line
     'move-backward 'focus-entered 'navigation 'select-object)))

(defun emacsvox--advice-git-rebase-forward-line-after (&rest _)
  "Present the rebase entry selected by `forward-line'."
  (when
      (and
       (derived-mode-p 'git-rebase-mode)
       (ems-interactive-p 'forward-line))
    (emacsvox-magit--present-rebase-line
     'move-forward 'focus-entered 'navigation 'select-object)))

(cl-loop
 for (target icon) in emacsvox-magit--rebase-view-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Present a commit displayed from an interactive rebase."
     (when (ems-interactive-p ',target)
       (emacsvox-magit--submit-text
        "Displayed commit from interactive rebase"
        (append
         (emacsvox-magit-view-facts 'commit 'vcs-commit-displayed)
         '(:vcs-operation show-commit))
        'navigation ',icon)))))

(defun emacsvox-magit--rebase-finish-feedback ()
  "Present successful submission of an interactive rebase plan."
  (when (ems-interactive-p 'with-editor-finish)
    (emacsvox-magit--submit-text
     "Submitted interactive rebase"
     (append
      (emacsvox-magit-view-facts 'rebase 'operation-completed)
      '(:vcs-operation finish))
     'state-change 'task-done)))

(defun emacsvox-magit--rebase-cancel-feedback ()
  "Present cancellation of an interactive rebase plan."
  (when (ems-interactive-p 'with-editor-cancel)
    (emacsvox-magit--submit-text
     "Canceled interactive rebase"
     (append
      (emacsvox-magit-view-facts 'rebase 'operation-completed)
      '(:vcs-operation cancel))
     'state-change 'close-object)))

(defun emacsvox-magit-enable-rebase-feedback ()
  "Install buffer-local completion feedback for a rebase editor."
  (add-hook
   'with-editor-post-finish-hook
   #'emacsvox-magit--rebase-finish-feedback nil t)
  (add-hook
   'with-editor-post-cancel-hook
   #'emacsvox-magit--rebase-cancel-feedback nil t))

(defun emacsvox-magit--install-rebase-advice ()
  "Install advice after Git Rebase loads."
  (dolist (target (mapcar #'car emacsvox-magit--rebase-action-targets))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox))))))
  (dolist
      (target
       (append
        '(git-rebase-backward-line)
        (mapcar #'car emacsvox-magit--rebase-view-targets)))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (unless
      (advice-member-p
       #'emacsvox--advice-git-rebase-forward-line-after
       'forward-line)
    (advice-add
     'forward-line :after
     #'emacsvox--advice-git-rebase-forward-line-after
     '((name . emacsvox)))))

(with-eval-after-load 'git-rebase
  (emacsvox-magit--install-rebase-advice)
  (add-hook
   'git-rebase-mode-hook
   #'emacsvox-magit-enable-rebase-feedback))

(provide 'emacsvox-magit)
;;;  end of file
