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
(defvar magit-buffer-file-name)
(defvar magit-buffer-diff-range)
(defvar magit-buffer-locked-p)
(defvar magit-buffer-revision)
(defvar magit-blob-mode)
(defvar magit-diff-fontify-hunk)
(defvar magit-diff-refine-hunk)
(defvar magit-display-buffer-noselect)
(defvar magit-log-margin-show-shortstat)
(defvar magit-mouse-set-point-hook)
(defvar magit-refs-show-commit-count)
(defvar magit--right-margin-config)
(defvar transient-current-command)
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

(defvar emacsvox-magit--operation-detail nil
  "Dynamically bound detail for an operation dispatched through Magit.")

(defun emacsvox-magit-enable-aural-context ()
  "Identify the current Magit buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'magit)
  (add-hook
   'magit-section-movement-hook
   #'emacsvox-magit--section-moved nil t)
  (add-hook
   'magit-mouse-set-point-hook
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
   ((derived-mode-p 'magit-cherry-mode) 'log)
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
    (downcase
     (or
      (and (stringp mode-name) mode-name)
      (and (listp mode-name) (cl-find-if #'stringp mode-name))
      (replace-regexp-in-string
       "-mode\\'" "" (symbol-name major-mode))))
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

(defun emacsvox-magit-process-facts (failed &optional operation)
  "Return semantic facts for a Magit process according to FAILED.
Include optional OPERATION identity."
  (append
   (list
    :role 'vcs-process
    :events (list (if failed 'operation-failed 'operation-completed)))
   (when operation (list :vcs-operation operation))))

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
    magit-section-backward-sibling
    magit-mouse-set-point)
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
    magit-go-backward
    magit-go-forward
    magit-back-to-indentation
    magit-log-move-to-parent
    magit-log-move-to-revision
    magit-jump-to-revision-diffstat
    magit-jump-to-revision-diff
    magit-jump-to-diffstat-or-diff
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

(defun emacsvox--advice-magit-mouse-toggle-section-around
    (original event &rest arguments)
  "Present a section whose visibility changed through EVENT."
  (if
      (not
       (eq ems--interactive-fn-name 'magit-mouse-toggle-section))
      (apply original event arguments)
    (let* ((position
            (ignore-errors (posn-point (event-start event))))
           (section
            (and
             position
             (fboundp 'magit-section-at)
             (ignore-errors (magit-section-at position))))
           (hidden-before
            (emacsvox-magit--section-value section 'hidden))
           (result (apply original event arguments))
           (hidden-after
            (emacsvox-magit--section-value section 'hidden)))
      (when
          (and
           section
           (not (eq hidden-before hidden-after))
           (ems-interactive-p 'magit-mouse-toggle-section))
        (emacsvox-magit-present-line
         (if hidden-after 'close-object 'open-object)
         'state-change
         'magit-mouse-toggle-section
         section
         'visibility-changed
         (if hidden-after 'folded 'expanded)
         t))
      result)))

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
       (emacsvox-magit--submit-text
        (emacsvox-magit--blob-summary)
        (append
         (emacsvox-magit-view-facts 'blob 'focus-entered)
         '(:vcs-operation ,target))
        'navigation 'large-movement)))))

(defun emacsvox-magit--blob-summary ()
  "Return the selected blob revision, file, and current source line."
  (concat
   (propertize
    (format
     "%s, %s. "
     (or
      (and (boundp 'magit-buffer-revision) magit-buffer-revision)
      "worktree")
     (or
      (and (boundp 'magit-buffer-file-name) magit-buffer-file-name)
      (buffer-name)))
    'personality voice-annotate)
   (emacsvox-magit--line-content)))

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

(defconst emacsvox-magit--quit-targets
  '(magit-mode-quit-window
    magit-mode-bury-buffer
    magit-log-bury-buffer
    magit-bury-or-kill-buffer)
  "Magit commands that close or bury their buffers.")

(cl-loop
 for target in emacsvox-magit--quit-targets
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

;;;  Advise process-sentinel:

(defun emacsvox--advice-magit-process-finish-after (argument &rest _)
  "Present completion or failure when ARGUMENT is an asynchronous process."
  (when (processp argument)
    (let* ((failed
            (or
             (eq (process-status argument) 'signal)
             (not (zerop (process-exit-status argument)))))
           (icon (if failed 'warn-user 'task-done))
           (operation
            (process-get argument 'emacsvox-magit-operation))
           (label
            (process-get argument 'emacsvox-magit-operation-label)))
      (if label
          (emacsvox-magit--submit-text
           (format
            "%s %s"
            (if failed "Failed" "Completed")
            label)
           (emacsvox-magit-process-facts failed operation)
           'notification icon)
        (emacsvox-magit--submit-actions
         (emacsvox-magit-process-facts failed)
         'notification icon)))))

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
  (emacsvox-magit--present-blame-entry
   'magit-blame "Entering Magit Blame"))

(defun emacsvox-magit--present-blame-entry (target text)
  "Present entry into a blame view through TARGET using TEXT."
  (when (ems-interactive-p target)
    (emacsvox-magit--submit-text
     text
     (append
      (emacsvox-magit-view-facts 'blame 'vcs-view-opened)
      (list :vcs-operation target))
     'state-change 'open-object)))

(defconst emacsvox-magit--blame-entry-targets
  '((magit-blame-addition "Blaming line additions")
    (magit-blame-removal "Blaming line removals")
    (magit-blame-reverse "Blaming line history in reverse"))
  "Additional blame commands and their spoken entry labels.")

(cl-loop
 for (target label) in emacsvox-magit--blame-entry-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Present entry into a specialized Magit Blame view."
     (emacsvox-magit--present-blame-entry ',target ,label))))

(defun emacsvox--advice-magit-blame-cycle-style-after (&rest _)
  "Present the blame chunk after changing its display style."
  (when (ems-interactive-p 'magit-blame-cycle-style)
    (emacsvox-magit--submit-text
     (emacsvox-magit--blame-content)
     '(:role vcs-blame-chunk
       :vcs-operation magit-blame-cycle-style
       :events (operation-completed))
     'inspection 'task-done)))

(defun emacsvox-magit--call-diff-show-or-scroll
    (original target scroll-function arguments)
  "Call ORIGINAL for TARGET while observing SCROLL-FUNCTION.
ARGUMENTS are passed to ORIGINAL unchanged."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((original-scroll (symbol-function scroll-function))
          scrolled-buffer
          scrolled-window
          result)
      (cl-letf
          (((symbol-function scroll-function)
            (lambda (&rest scroll-arguments)
              (setq scrolled-buffer (current-buffer))
              (setq scrolled-window (selected-window))
              (apply original-scroll scroll-arguments))))
        (setq result (apply original arguments)))
      (when (ems-interactive-p target)
        (if scrolled-buffer
            (let ((content
                   (if
                       (and
                        (window-live-p scrolled-window)
                        (eq
                         (window-buffer scrolled-window)
                         scrolled-buffer))
                       (with-selected-window scrolled-window
                         (emacsvox-magit--line-content))
                     (with-current-buffer scrolled-buffer
                       (emacsvox-magit--line-content)))))
              (emacsvox-magit--submit-text
               content
               (emacsvox-magit-view-facts 'diff 'vcs-diff-scrolled)
               'navigation 'scroll))
          (emacsvox-magit--submit-text
           "Displayed commit in other window"
           (emacsvox-magit-view-facts 'commit 'vcs-commit-displayed)
           'state-change 'open-object)))
      result)))

(defun emacsvox--advice-magit-diff-show-or-scroll-up-around
    (original &rest arguments)
  "Present upward scrolling or a newly displayed commit accurately."
  (emacsvox-magit--call-diff-show-or-scroll
   original 'magit-diff-show-or-scroll-up 'scroll-up arguments))

(defun emacsvox--advice-magit-diff-show-or-scroll-down-around
    (original &rest arguments)
  "Present downward scrolling or a newly displayed commit accurately."
  (emacsvox-magit--call-diff-show-or-scroll
   original 'magit-diff-show-or-scroll-down 'scroll-down arguments))

(defconst emacsvox-magit--reference-navigation-targets
  '(magit-next-reference magit-previous-reference)
  "Commands that navigate between visible Git references.")

(defun emacsvox-magit--call-reference-navigation
    (original target arguments)
  "Call reference-navigation ORIGINAL for TARGET with ARGUMENTS."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((origin (point))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (if (/= origin (point))
            (emacsvox-magit--submit-text
             (emacsvox-magit--line-content)
             (append
              (emacsvox-magit-view-facts
               (emacsvox-magit-current-view-kind)
               'focus-entered)
              (list :vcs-operation target))
             'navigation 'select-object)
          (emacsvox-magit--submit-text
           "No more references"
           (append
            (emacsvox-magit-view-facts
             (emacsvox-magit-current-view-kind)
             'operation-failed)
            (list :vcs-operation target))
           'navigation 'warn-user)))
      result)))

(cl-loop
 for target in emacsvox-magit--reference-navigation-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present movement to another visible Git reference."
     (emacsvox-magit--call-reference-navigation
     original ',target arguments))))

(defconst emacsvox-magit--blob-targets
  '(magit-blob-previous magit-blob-next)
  "Magit blob navigation commands.")

(defconst emacsvox-magit--blame-navigation-targets
  '(magit-blame-previous-chunk
    magit-blame-previous-chunk-same-commit
    magit-blame-next-chunk
    magit-blame-next-chunk-same-commit)
  "Magit blame navigation commands.")

(defconst emacsvox-magit--copy-targets
  '(magit-copy-section-value
    magit-copy-buffer-revision
    magit-blame-copy-hash)
  "Magit commands that copy repository data to the kill ring.")

(defconst emacsvox-magit--destination-targets
  '(magit-dired-jump
    magit-diff-visit-file
    magit-diff-visit-file-other-window
    magit-diff-visit-file-other-frame
    magit-diff-visit-worktree-file
    magit-diff-visit-worktree-file-other-window
    magit-diff-visit-worktree-file-other-frame
    magit-blame-visit-file
    magit-blame-visit-other-file)
  "Magit commands that select a non-Magit destination buffer.")

(defun emacsvox-magit--selected-destination-content ()
  "Return a summary and current line for the selected destination."
  (with-current-buffer (window-buffer (selected-window))
    (concat
     (emacsvox-magit--buffer-summary)
     ". "
     (emacsvox-magit--line-content))))

(defun emacsvox-magit--call-destination-command
    (original target arguments)
  "Call destination command ORIGINAL for TARGET with ARGUMENTS."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((result (apply original arguments)))
      ;; A Magit view selected through `magit-display-buffer' consumes the
      ;; marker and presents its more precise kind at that central boundary.
      (when (ems-interactive-p target)
        (emacsvox-magit--submit-text
         (emacsvox-magit--selected-destination-content)
         (append
          (emacsvox-magit-view-facts 'other 'vcs-view-opened)
          (list :vcs-operation target))
         'navigation 'open-object))
      result)))

(cl-loop
 for target in emacsvox-magit--destination-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present the buffer selected by a Magit destination command."
     (emacsvox-magit--call-destination-command
      original ',target arguments))))

(defun emacsvox-magit--copied-content ()
  "Return concise feedback for the latest kill-ring entry."
  (let ((text (ignore-errors (current-kill 0 t))))
    (cond
     ((not (stringp text)) "Copied repository data")
     ((string-match-p "\n" text)
      (format "Copied %d lines" (1+ (cl-count ?\n text))))
     ((> (length text) 200)
      (format "Copied %d characters" (length text)))
     (t
      (concat
       (propertize "Copied. " 'personality voice-annotate)
       text)))))

(defun emacsvox-magit--call-copy-command
    (original target arguments)
  "Call copy command ORIGINAL for TARGET with ARGUMENTS."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((result (apply original arguments)))
      (when (ems-interactive-p target)
        (emacsvox-magit--submit-text
         (emacsvox-magit--copied-content)
         (append
          (emacsvox-magit-view-facts
           (emacsvox-magit-current-view-kind)
           'operation-completed)
          (list :vcs-operation target))
         'state-change 'mark-object))
      result)))

(cl-loop
 for target in emacsvox-magit--copy-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present repository data copied to the kill ring."
     (emacsvox-magit--call-copy-command
      original ',target arguments))))

(defconst emacsvox-magit--describe-targets
  '(magit-describe-section magit-describe-section-briefly)
  "Magit commands that inspect the section at point.")

(cl-loop
 for target in emacsvox-magit--describe-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (section &rest _)
     "Present the identity of an inspected Magit section."
     (when (ems-interactive-p ',target)
       (emacsvox-magit--submit-text
        (or
         (ignore-errors
           (magit-describe-section-briefly section))
         "Magit section")
        (append
         (emacsvox-magit-section-facts
          ',target section 'operation-completed)
         '(:vcs-operation ,target))
        'notification 'help)))))

(defun emacsvox-magit--call-process-kill (original arguments)
  "Call `magit-process-kill' through ORIGINAL with ARGUMENTS."
  (if (not (eq ems--interactive-fn-name 'magit-process-kill))
      (apply original arguments)
    (let* ((process
            (and
             (fboundp 'magit-section-value-if)
             (ignore-errors (magit-section-value-if 'process))))
           (running
            (and process (eq (process-status process) 'run)))
           (force
            (and
             running
             (eq (process-get process 'sigint) t)))
           (result (apply original arguments)))
      (when (ems-interactive-p 'magit-process-kill)
        (let* ((failed (not running))
               (operation (if force 'kill 'interrupt))
               (text
                (cond
                 ((not process) "No process at point")
                 ((not running) "Process no longer running")
                 (force "Killed process")
                 (t "Interrupted process"))))
          (emacsvox-magit--submit-text
           text
           (emacsvox-magit-process-facts failed operation)
           'notification
           (if failed 'warn-user 'close-object))))
      result)))

(defun emacsvox--advice-magit-process-kill-around
    (original &rest arguments)
  "Present the result of interrupting or killing a Magit process."
  (emacsvox-magit--call-process-kill original arguments))

(defconst emacsvox-magit--view-setting-targets
  '(magit-diff-less-context
    magit-diff-more-context
    magit-diff-default-context
    magit-log-toggle-commit-limit
    magit-log-double-commit-limit
    magit-log-half-commit-limit
    magit-refs-set-show-commit-count
    magit-diff-toggle-refine-hunk
    magit-diff-toggle-fontify-hunk
    magit-diff-toggle-file-filter
    magit-diff-switch-range-type
    magit-diff-flip-revs
    magit-toggle-buffer-lock
    magit-toggle-margin
    magit-cycle-margin-style
    magit-toggle-margin-details
    magit-toggle-log-margin-style
    magit-blob-mode
    magit-smerge-keep-current
    magit-smerge-keep-upper
    magit-smerge-keep-base
    magit-smerge-keep-lower
    magit-smerge-keep-all)
  "Commands that change the presentation or extent of a Magit view.")

(defun emacsvox-magit--setting-value-label (value)
  "Return a concise spoken label for setting VALUE."
  (cond
   ((stringp value) "absolute date and time")
   ((symbolp value)
    (replace-regexp-in-string "-" " " (symbol-name value)))
   (t (format "%s" value))))

(defun emacsvox-magit--view-setting-description (target)
  "Return the current view-setting description for TARGET."
  (pcase target
    ((or
      'magit-diff-less-context
      'magit-diff-more-context
      'magit-diff-default-context)
     (format
      "Diff context is %d lines"
      (if (fboundp 'magit-diff-get-context)
          (magit-diff-get-context)
        0)))
    ((or
      'magit-log-toggle-commit-limit
      'magit-log-double-commit-limit
      'magit-log-half-commit-limit)
     (let ((limit
            (and
             (fboundp 'magit-log-get-commit-limit)
             (magit-log-get-commit-limit))))
       (if limit
           (format "Showing up to %d commits" limit)
         "Showing all commits")))
    ('magit-refs-set-show-commit-count
     (format
      "Commit counts shown for %s"
      (pcase magit-refs-show-commit-count
        ('all "all references")
        ('t "branches")
        (_ "no references"))))
    ('magit-diff-toggle-refine-hunk
     (format
      "Hunk refinement %s"
      (pcase magit-diff-refine-hunk
        ('all "enabled immediately")
        ('t "enabled on selection")
        (_ "disabled"))))
    ('magit-diff-toggle-fontify-hunk
     (format
      "Hunk fontification %s"
      (pcase magit-diff-fontify-hunk
        ('all "enabled immediately")
        ('t "enabled on selection")
        (_ "disabled"))))
    ('magit-diff-toggle-file-filter "Toggled diff file filter")
    ('magit-diff-switch-range-type
     (format "Diff range is %s" (or magit-buffer-diff-range "unchanged")))
    ('magit-diff-flip-revs
     (format "Flipped diff range to %s"
             (or magit-buffer-diff-range "unchanged")))
    ('magit-toggle-buffer-lock
     (if magit-buffer-locked-p "Buffer locked" "Buffer unlocked"))
    ('magit-toggle-margin
     (if
         (and
          (fboundp 'magit--right-margin-active)
          (magit--right-margin-active))
         "Right margin shown"
       "Right margin hidden"))
    ('magit-cycle-margin-style
     (format
      "Right margin style is %s"
      (emacsvox-magit--setting-value-label
       (cadr magit--right-margin-config))))
    ('magit-toggle-margin-details
     (if
         (nth 3 magit--right-margin-config)
         "Right margin details shown"
       "Right margin details hidden"))
    ('magit-toggle-log-margin-style
     (if
         magit-log-margin-show-shortstat
         "Log margin shows short statistics"
       "Log margin shows author and date"))
    ('magit-blob-mode
     (if magit-blob-mode
         "Blob navigation mode enabled"
       "Blob navigation mode disabled"))
    ((or
      'magit-smerge-keep-current
      'magit-smerge-keep-upper
      'magit-smerge-keep-base
      'magit-smerge-keep-lower
      'magit-smerge-keep-all)
     (format
      "Kept %s conflict version"
      (pcase target
        ('magit-smerge-keep-current "current")
        ('magit-smerge-keep-upper "upper")
        ('magit-smerge-keep-base "base")
        ('magit-smerge-keep-lower "lower")
        (_ "all"))))
    (_
     (format
      "Changed %s"
      (emacsvox-magit--operation-label target)))))

(defun emacsvox-magit--present-view-setting (target)
  "Present the view setting changed by TARGET."
  (emacsvox-magit--submit-text
   (concat
    (propertize
     (concat (emacsvox-magit--view-setting-description target) ". ")
     'personality voice-annotate)
    (emacsvox-magit--line-content))
   (append
    (emacsvox-magit-view-facts
     (emacsvox-magit-current-view-kind)
     'operation-completed)
    (list :vcs-operation target))
   'state-change 'task-done))

(cl-loop
 for target in emacsvox-magit--view-setting-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Present a changed Magit view setting."
     (when (ems-interactive-p ',target)
       (emacsvox-magit--present-view-setting ',target)))))

(defun emacsvox-magit--call-transient-refresh
    (original target arguments)
  "Call refresh prefix ORIGINAL for TARGET with ARGUMENTS.
Only present the invocation that applies the transient's selected values."
  (let ((refreshing (eq transient-current-command target))
        (result (apply original arguments)))
    (when
        (and refreshing (ems-interactive-p target))
      (emacsvox-magit--submit-text
       (concat
        (propertize
         (format
          "Refreshed %s view. "
          (emacsvox-magit--view-kind-label
           (emacsvox-magit-current-view-kind)))
         'personality voice-annotate)
        (emacsvox-magit--line-content))
       (append
        (emacsvox-magit-view-facts
         (emacsvox-magit-current-view-kind)
         'refresh-completed)
        (list :vcs-operation target))
       'notification 'task-done))
    result))

(defun emacsvox--advice-magit-diff-refresh-around
    (original &rest arguments)
  "Present a diff refresh, but not initial transient entry."
  (emacsvox-magit--call-transient-refresh
   original 'magit-diff-refresh arguments))

(defun emacsvox--advice-magit-log-refresh-around
    (original &rest arguments)
  "Present a log refresh, but not initial transient entry."
  (emacsvox-magit--call-transient-refresh
   original 'magit-log-refresh arguments))

(defun emacsvox--advice-magit-patch-save-around
    (original file &rest arguments)
  "Present a patch exported to FILE."
  (if (not (eq ems--interactive-fn-name 'magit-patch-save))
      (apply original file arguments)
    (let ((result (apply original file arguments)))
      (when (ems-interactive-p 'magit-patch-save)
        (emacsvox-magit--submit-text
         (format "Saved patch to %s" (abbreviate-file-name file))
         (append
          (emacsvox-magit-view-facts 'diff 'operation-completed)
          '(:vcs-operation magit-patch-save))
         'state-change 'save-object))
      result)))

(defun emacsvox--advice-magit-do-async-shell-command-around
    (original file &rest arguments)
  "Present an asynchronous shell command started for FILE."
  (if
      (not
       (eq ems--interactive-fn-name 'magit-do-async-shell-command))
      (apply original file arguments)
    (let ((result (apply original file arguments)))
      (when (ems-interactive-p 'magit-do-async-shell-command)
        (emacsvox-magit--submit-text
         (format
          "Started shell command for %s"
          (file-name-nondirectory file))
         (append
          (emacsvox-magit-view-facts
           (emacsvox-magit-current-view-kind) nil)
          '(:vcs-operation magit-do-async-shell-command))
         'notification 'progress))
      result)))

(defun emacsvox--advice-magit-commit-add-log-after (&rest _)
  "Present insertion of a changelog stub into the commit message."
  (when (ems-interactive-p 'magit-commit-add-log)
    (emacsvox-magit--submit-text
     "Added changelog entry to commit message"
     (emacsvox-magit-commit-facts
      'add-log 'operation-completed)
     'state-change 'open-object)))

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
     magit-process-finish)
   '(magit-commit-add-log)
   emacsvox-magit--describe-targets
   emacsvox-magit--view-setting-targets
   emacsvox-magit--blame-navigation-targets
   '(magit-blame-quit
     magit-blame
     magit-blame-cycle-style)
   (mapcar #'car emacsvox-magit--blame-entry-targets))
  "Current Magit targets that receive native after advice.")

(defvar emacsvox-magit--setting-up-buffer nil
  "Non-nil while `magit-setup-buffer-internal' is preparing a view.")

(defconst emacsvox-magit--dedicated-view-targets
  '(magit-status
    magit-show-commit
    magit-list-repositories
    magit-repolist-status
    magit-blob-visit-file
    magit-blame
    magit-blame-addition
    magit-blame-removal
    magit-blame-reverse
    magit-diff-show-or-scroll-up
    magit-diff-show-or-scroll-down
    magit-diff-while-committing
    git-rebase-show-commit
    git-rebase-show-or-scroll-up
    git-rebase-show-or-scroll-down)
  "Commands whose more specific advice presents their opened view.")

(defconst emacsvox-magit--dedicated-operation-targets
  '(magit-stage
    magit-stage-files
    magit-stage-modified
    magit-file-stage
    magit-unstage
    magit-unstage-files
    magit-unstage-all
    magit-file-unstage
    magit-repolist-fetch
    magit-repolist-find-file-other-frame)
  "Operations whose specific feedback supersedes process-boundary feedback.")

(defun emacsvox-magit--operation-label (operation)
  "Return a concise spoken label for OPERATION."
  (let* ((name (symbol-name operation))
         (name
          (replace-regexp-in-string
           "\\`\\(?:magit\\|git\\)-" "" name)))
    (setq name (replace-regexp-in-string "-" " " name))
    (if emacsvox-magit--operation-detail
        (format "%s, %s" name emacsvox-magit--operation-detail)
      name)))

(defun emacsvox-magit--operation-facts (operation &optional event)
  "Return current-view facts for OPERATION and optional EVENT."
  (append
   (list
    :role 'vcs-view
    :vcs-view-kind (emacsvox-magit-current-view-kind)
    :vcs-operation operation)
   (when event (list :events (list event)))))

(defun emacsvox-magit--present-operation
    (operation state &optional asynchronous)
  "Present OPERATION in lifecycle STATE.
When ASYNCHRONOUS is non-nil, use process facts for terminal states."
  (let* ((label (emacsvox-magit--operation-label operation))
         (event
          (pcase state
            ('completed 'operation-completed)
            ('failed 'operation-failed)))
         (facts
          (if (and asynchronous event)
              (emacsvox-magit-process-facts
               (eq state 'failed) operation)
            (emacsvox-magit--operation-facts operation event)))
         (text
          (format
           "%s %s"
           (pcase state
             ('started "Started")
             ('completed "Completed")
             ('failed "Failed"))
           label))
         (icon
          (pcase state
            ('started 'progress)
            ('completed 'task-done)
            ('failed 'warn-user))))
    (emacsvox-magit--submit-text
     text facts 'notification icon)))

(defun emacsvox-magit--call-synchronous-operation (original arguments)
  "Call a synchronous Git operation through ORIGINAL with ARGUMENTS."
  (let ((operation ems--interactive-fn-name))
    (if
        (or
         (null operation)
         (memq operation emacsvox-magit--dedicated-view-targets)
         (memq operation emacsvox-magit--dedicated-operation-targets)
         (not (ems-interactive-p operation)))
        (apply original arguments)
      (emacsvox-magit--present-operation operation 'started)
      (condition-case error-data
          (let* ((result (apply original arguments))
                 (failed (and (integerp result) (not (zerop result)))))
            (emacsvox-magit--present-operation
             operation (if failed 'failed 'completed))
            result)
        (error
         (emacsvox-magit--present-operation operation 'failed)
         (signal (car error-data) (cdr error-data)))))))

(defun emacsvox--advice-magit-run-git-around
    (original &rest arguments)
  "Present a synchronous `magit-run-git' operation."
  (emacsvox-magit--call-synchronous-operation original arguments))

(defun emacsvox--advice-magit-git-around
    (original &rest arguments)
  "Present a synchronous `magit-git' operation."
  (emacsvox-magit--call-synchronous-operation original arguments))

(defun emacsvox--advice-magit-run-git-with-input-around
    (original &rest arguments)
  "Present a synchronous `magit-run-git-with-input' operation."
  (if (file-remote-p default-directory)
      ;; Magit implements the remote path asynchronously and waits for it.
      ;; Leave the interactive marker for `magit-start-process' so that its
      ;; actual process status owns the lifecycle feedback.
      (apply original arguments)
    (emacsvox-magit--call-synchronous-operation original arguments)))

(defun emacsvox--advice-magit-start-process-around
    (original program &optional input &rest arguments)
  "Present an asynchronous process started by an interactive Magit command."
  (let ((operation ems--interactive-fn-name))
    (if
        (or
         (null operation)
         (memq operation emacsvox-magit--dedicated-view-targets)
         (memq operation emacsvox-magit--dedicated-operation-targets)
         (not (ems-interactive-p operation)))
        (apply original program input arguments)
      (condition-case error-data
          (let* ((process (apply original program input arguments))
                 (label (emacsvox-magit--operation-label operation)))
            (process-put process 'emacsvox-magit-operation operation)
            (process-put process 'emacsvox-magit-operation-label label)
            (emacsvox-magit--present-operation operation 'started t)
            process)
        (error
         (emacsvox-magit--present-operation operation 'failed t)
         (signal (car error-data) (cdr error-data)))))))

(defun emacsvox-magit--view-kind-label (kind)
  "Return a concise spoken label for Magit view KIND."
  (capitalize
   (replace-regexp-in-string "-" " " (symbol-name kind))))

(defun emacsvox-magit--present-opened-buffer (buffer target)
  "Present BUFFER opened by interactive TARGET."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((kind (emacsvox-magit-current-view-kind)))
        (emacsvox-magit--submit-text
         (concat
          (propertize
           (format
            "%s view. "
            (emacsvox-magit--view-kind-label kind))
           'personality voice-annotate)
          (let ((line (emacsvox-magit--line-content)))
            (if (> (length line) 0)
                line
              (emacsvox-magit--buffer-summary))))
         (append
          (emacsvox-magit-view-facts kind 'vcs-view-opened)
          (list :vcs-operation target))
         'navigation 'open-object)))))

(defun emacsvox--advice-magit-setup-buffer-internal-around
    (original &rest arguments)
  "Present a fully refreshed Magit view created through the setup boundary."
  (let* ((target ems--interactive-fn-name)
         (emacsvox-magit--setting-up-buffer t)
         (buffer (apply original arguments)))
    (when
        (and
         target
         (not (memq target emacsvox-magit--dedicated-view-targets))
         (ems-interactive-p target))
      (emacsvox-magit--present-opened-buffer buffer target))
    buffer))

(defun emacsvox--advice-magit-display-buffer-around
    (original buffer &rest arguments)
  "Present BUFFER when it is displayed outside the setup boundary."
  (let ((target ems--interactive-fn-name)
        (result (apply original buffer arguments)))
    (when
        (and
         target
         (not emacsvox-magit--setting-up-buffer)
         (not magit-display-buffer-noselect)
         (not (memq target emacsvox-magit--dedicated-view-targets))
         (ems-interactive-p target))
      (emacsvox-magit--present-opened-buffer buffer target))
    result))

(defun emacsvox-magit--install-advice ()
  "Install advice for the Magit functions that are currently loaded."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (when
      (fboundp 'magit-diff-show-or-scroll-up)
    (dolist
        (entry
         '((magit-diff-show-or-scroll-up
            emacsvox--advice-magit-diff-show-or-scroll-up-around)
           (magit-diff-show-or-scroll-down
            emacsvox--advice-magit-diff-show-or-scroll-down-around)))
      (pcase-let ((`(,target ,function) entry))
        (unless (advice-member-p function target)
          (advice-add
           target :around function '((name . emacsvox)))))))
  (dolist (target emacsvox-magit--reference-navigation-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox))))))
  (dolist (target emacsvox-magit--copy-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox))))))
  (dolist (target emacsvox-magit--destination-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox))))))
  (dolist
      (entry
       '((magit-setup-buffer-internal
          emacsvox--advice-magit-setup-buffer-internal-around)
         (magit-display-buffer
          emacsvox--advice-magit-display-buffer-around)
         (magit-run-git
          emacsvox--advice-magit-run-git-around)
         (magit-git
          emacsvox--advice-magit-git-around)
         (magit-run-git-with-input
          emacsvox--advice-magit-run-git-with-input-around)
         (magit-start-process
          emacsvox--advice-magit-start-process-around)
         (magit-process-kill
          emacsvox--advice-magit-process-kill-around)
         (magit-diff-refresh
          emacsvox--advice-magit-diff-refresh-around)
         (magit-log-refresh
          emacsvox--advice-magit-log-refresh-around)
         (magit-mouse-toggle-section
          emacsvox--advice-magit-mouse-toggle-section-around)
         (magit-patch-save
          emacsvox--advice-magit-patch-save-around)
         (magit-do-async-shell-command
          emacsvox--advice-magit-do-async-shell-command-around)))
    (pcase-let ((`(,target ,function) entry))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox)))))))

(dolist
    (feature
     '(magit
       magit-apply
       magit-blame
       magit-commit
       magit-diff
       magit-dired
       magit-extras
       magit-files
       magit-log
       magit-margin
       magit-process
       magit-patch
       magit-refs
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

;;; Log selection:

(defun emacsvox-magit--log-selection-revision ()
  "Return the commit selected in a Magit log-selection buffer."
  (and
   (fboundp 'magit-commit-at-point)
   (ignore-errors (magit-commit-at-point))))

(defun emacsvox--advice-magit-log-select-pick-around
    (original &rest arguments)
  "Present a selected log commit unless its callback owns feedback."
  (if (not (eq ems--interactive-fn-name 'magit-log-select-pick))
      (apply original arguments)
    (let* ((revision (emacsvox-magit--log-selection-revision))
           (emacsvox-magit--operation-detail
            (and revision (format "commit %s" revision)))
           (result (apply original arguments)))
      (when (ems-interactive-p 'magit-log-select-pick)
        (emacsvox-magit--submit-text
         (format "Selected commit %s" (or revision "at point"))
         '(:role vcs-view
           :vcs-view-kind log
           :vcs-operation magit-log-select-pick
           :events (operation-completed))
         'state-change 'select-object))
      result)))

(defun emacsvox--advice-magit-log-select-quit-around
    (original &rest arguments)
  "Present return from a canceled Magit log selection."
  (if (not (eq ems--interactive-fn-name 'magit-log-select-quit))
      (apply original arguments)
    (let ((result (apply original arguments)))
      (when (ems-interactive-p 'magit-log-select-quit)
        (emacsvox-magit--submit-text
         (emacsvox-magit--selected-destination-content)
         '(:role vcs-view
           :vcs-view-kind log
           :vcs-operation magit-log-select-quit
           :events (vcs-view-closed))
         'state-change 'close-object))
      result)))

(defconst emacsvox-magit--log-select-advice
  '((magit-log-select-pick
     emacsvox--advice-magit-log-select-pick-around)
    (magit-log-select-quit
     emacsvox--advice-magit-log-select-quit-around))
  "Around advice for completing or canceling log selection.")

(defun emacsvox-magit--install-log-select-advice ()
  "Install Magit log-selection advice."
  (dolist (entry emacsvox-magit--log-select-advice)
    (pcase-let ((`(,target ,function) entry))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox)))))))

(with-eval-after-load 'magit-log
  (emacsvox-magit--install-log-select-advice))

;;; Commit message editor:

(defvar git-commit-post-finish-hook)

(defconst emacsvox-magit--commit-history-targets
  '((git-commit-prev-message previous-message select-object)
    (git-commit-next-message next-message select-object)
    (git-commit-search-message-backward search-backward search-hit)
    (git-commit-search-message-forward search-forward search-hit))
  "Commit-message history commands, operations, and cues.")

(defconst emacsvox-magit--commit-trailer-targets
  '((git-commit-ack ack "Acked-by")
    (git-commit-modified modified "Modified-by")
    (git-commit-review review "Reviewed-by")
    (git-commit-signoff signoff "Signed-off-by")
    (git-commit-test test "Tested-by")
    (git-commit-cc cc "Cc")
    (git-commit-reported reported "Reported-by")
    (git-commit-suggested suggested "Suggested-by")
    (git-commit-co-authored co-authored "Co-authored-by")
    (git-commit-co-developed co-developed "Co-developed-by"))
  "Commit trailer commands, operations, and displayed labels.")

(defconst emacsvox-magit--commit-insertion-targets
  '((git-commit-insert-changelog-gnu changelog-gnu
     "Inserted GNU changelog")
    (git-commit-insert-changelog-plain changelog-plain
     "Inserted plain changelog"))
  "Commit-message insertion commands and their feedback.")

(defun emacsvox-magit-commit-facts (operation event)
  "Return semantic commit-message facts for OPERATION and EVENT."
  (append
   (list :role 'vcs-commit-message :vcs-operation operation)
   (when event (list :events (list event)))))

(defun emacsvox-magit--commit-message-content ()
  "Return the editable commit message with source properties intact."
  (save-excursion
    (goto-char (point-min))
    (let ((end
           (if
               (and
                (stringp comment-start)
                (re-search-forward
                 (concat "^" (regexp-quote comment-start)) nil t))
               (line-beginning-position)
             (point-max))))
      (string-trim-right
       (buffer-substring (point-min) end)))))

(defun emacsvox-magit--commit-labelled-content (label &optional content)
  "Return LABEL followed by optional commit-message CONTENT."
  (concat
   (propertize
    (concat label (if content ". " "."))
    'personality voice-annotate)
   content))

(defun emacsvox-magit--call-commit-history
    (original target operation icon arguments)
  "Call ORIGINAL with ARGUMENTS and present commit history TARGET."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (let ((changed (/= tick (buffer-chars-modified-tick))))
          (emacsvox-magit--submit-text
           (emacsvox-magit--commit-labelled-content
            (if changed
                (emacsvox-magit--rebase-operation-label operation)
              (format
               "No %s available"
               (downcase
                (emacsvox-magit--rebase-operation-label operation))))
            (and changed (emacsvox-magit--commit-message-content)))
           (emacsvox-magit-commit-facts
            operation
            (if changed 'focus-entered 'operation-failed))
           'navigation
           (if changed icon 'warn-user))))
      result)))

(cl-loop
 for (target operation icon) in emacsvox-magit--commit-history-targets
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present an interactive commit-message history operation."
     (emacsvox-magit--call-commit-history
      original ',target ',operation ',icon arguments))))

(defun emacsvox-magit--call-commit-trailer
    (original target operation label arguments)
  "Call ORIGINAL with ARGUMENTS and present commit trailer TARGET.
OPERATION and LABEL describe the trailer."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (let* ((changed (/= tick (buffer-chars-modified-tick)))
               (name (car arguments))
               (mail (cadr arguments))
               (detail
                (if
                    (and
                     changed
                     (stringp name)
                     (stringp mail))
                    (format "%s: %s <%s>" label name mail)
                  (format "No %s trailer inserted" label))))
          (emacsvox-magit--submit-text
           detail
           (emacsvox-magit-commit-facts
            operation
            (if changed 'operation-completed 'operation-failed))
           'state-change
           (if changed 'open-object 'warn-user))))
      result)))

(cl-loop
 for (target operation label) in emacsvox-magit--commit-trailer-targets
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present an interactive commit-trailer insertion."
     (emacsvox-magit--call-commit-trailer
      original ',target ',operation ,label arguments))))

(defun emacsvox-magit--call-commit-insertion
    (original target operation label arguments)
  "Call ORIGINAL with ARGUMENTS and present commit insertion TARGET."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original arguments)))
      (when (ems-interactive-p target)
        (let ((changed (/= tick (buffer-chars-modified-tick))))
          (emacsvox-magit--submit-text
           (if changed label (format "No %s change" label))
           (emacsvox-magit-commit-facts
            operation
            (if changed 'operation-completed 'operation-failed))
           'state-change
           (if changed 'open-object 'warn-user))))
      result)))

(cl-loop
 for (target operation label) in emacsvox-magit--commit-insertion-targets
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Present an interactive commit-message insertion."
     (emacsvox-magit--call-commit-insertion
      original ',target ',operation ,label arguments))))

(defun emacsvox--advice-git-commit-save-message-around
    (original &rest arguments)
  "Present an interactive commit-message save accurately."
  (if (not (eq ems--interactive-fn-name 'git-commit-save-message))
      (apply original arguments)
    (let ((message-content (emacsvox-magit--commit-message-content))
          (result (apply original arguments)))
      (when (ems-interactive-p 'git-commit-save-message)
        (let ((saved (> (length message-content) 0)))
          (emacsvox-magit--submit-text
           (if saved "Saved commit message" "Commit message was not saved")
           (emacsvox-magit-commit-facts
            'save
            (if saved 'operation-completed 'operation-failed))
           'state-change
           (if saved 'save-object 'warn-user))))
      result)))

(defun emacsvox--advice-magit-pop-revision-stack-around
    (original revision toplevel &rest arguments)
  "Present REVISION inserted into a commit message."
  (if
      (or
       (not (bound-and-true-p git-commit-mode))
       (not (eq ems--interactive-fn-name 'magit-pop-revision-stack)))
      (apply original revision toplevel arguments)
    (let ((tick (buffer-chars-modified-tick))
          (result (apply original revision toplevel arguments)))
      (when (ems-interactive-p 'magit-pop-revision-stack)
        (let ((changed (/= tick (buffer-chars-modified-tick))))
          (emacsvox-magit--submit-text
           (if changed
               (format "Inserted revision %s" revision)
             "No revision inserted")
           (emacsvox-magit-commit-facts
            'insert-revision
            (if changed 'operation-completed 'operation-failed))
           'state-change
           (if changed 'yank-object 'warn-user))))
      result)))

(defun emacsvox--advice-magit-diff-while-committing-after (&rest _)
  "Present the commit diff displayed by the user."
  (when (ems-interactive-p 'magit-diff-while-committing)
    (emacsvox-magit--submit-text
     "Displayed changes for this commit"
     (append
      (emacsvox-magit-view-facts 'diff 'vcs-view-opened)
      '(:vcs-operation inspect-commit))
     'navigation 'open-object)))

(defun emacsvox-magit--commit-start-feedback ()
  "Present entry into a Git commit-message editor."
  (emacsvox-magit--submit-text
   "Editing Git commit message"
   (emacsvox-magit-commit-facts 'edit 'vcs-view-opened)
   'state-change 'open-object))

(defun emacsvox-magit--commit-finish-feedback ()
  "Present creation of a Git commit after the repository confirms it."
  (when (ems-interactive-p 'with-editor-finish)
    (emacsvox-magit--submit-text
     "Created Git commit"
     (emacsvox-magit-commit-facts 'finish 'operation-completed)
     'state-change 'task-done)))

(defun emacsvox-magit--commit-cancel-feedback ()
  "Present cancellation of a Git commit message."
  (when (ems-interactive-p 'with-editor-cancel)
    (emacsvox-magit--submit-text
     "Canceled Git commit"
     (emacsvox-magit-commit-facts 'cancel 'operation-completed)
     'state-change 'close-object)))

(defun emacsvox-magit-enable-commit-feedback ()
  "Install buffer-local Git commit lifecycle feedback."
  (add-hook
   'git-commit-post-finish-hook
   #'emacsvox-magit--commit-finish-feedback nil t)
  (add-hook
   'with-editor-post-cancel-hook
   #'emacsvox-magit--commit-cancel-feedback nil t)
  (emacsvox-magit--commit-start-feedback))

(defconst emacsvox-magit--commit-around-advice
  (append
   (mapcar
    (lambda (entry)
      (list
       (car entry)
       (intern (format "emacsvox--advice-%s-around" (car entry)))))
    emacsvox-magit--commit-history-targets)
   (mapcar
    (lambda (entry)
      (list
       (car entry)
       (intern (format "emacsvox--advice-%s-around" (car entry)))))
    emacsvox-magit--commit-trailer-targets)
   (mapcar
    (lambda (entry)
      (list
       (car entry)
       (intern (format "emacsvox--advice-%s-around" (car entry)))))
    emacsvox-magit--commit-insertion-targets)
   '((git-commit-save-message
      emacsvox--advice-git-commit-save-message-around)
     (magit-pop-revision-stack
      emacsvox--advice-magit-pop-revision-stack-around)))
  "Around advice for commit-message interactions.")

(defconst emacsvox-magit--commit-after-advice
  '((magit-diff-while-committing
     emacsvox--advice-magit-diff-while-committing-after))
  "After advice for commit-message interactions.")

(defun emacsvox-magit--install-commit-advice ()
  "Install current Git commit-message advice."
  (dolist (entry emacsvox-magit--commit-around-advice)
    (pcase-let ((`(,target ,function) entry))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox))))))
  (dolist (entry emacsvox-magit--commit-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (when
          (and
           (fboundp target)
           (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'git-commit
  (emacsvox-magit--install-commit-advice)
  (add-hook
   'git-commit-setup-hook
   #'emacsvox-magit-enable-commit-feedback))

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
  (let ((label
         (replace-regexp-in-string "-" " " (symbol-name operation))))
    (concat (upcase (substring label 0 1)) (substring label 1))))

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
