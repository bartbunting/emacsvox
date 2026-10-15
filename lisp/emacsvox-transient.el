;;; emacsvox-transient.el --- TRANSIENT  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop transient
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
;; TRANSIENT ==  Transient commands --- used by magit and friends.
;; This module speech-enables transient.

;; @subsection Introduction
;; 
;; Package Transient is similar to package Hydra in the sense that it
;; can be used to create a sequence of chained/hierarchical commands
;; that are invoked via a sequence of keys. It is used by Magit for
;; dispatching to the various Git commands.  Speech-enabling package
;; Transient results in the various interactive commands producing
;; auditory feedback. Transient shows an ephemeral window with the
;; currently available commands, Emacsvox speech-enables
;; transient--show to cache that content so it can be browsed if
;; desired.
;; 
;; Finally, this module defines a new minor mode called
;; transient-emacsvox  that  enables  interactive browsing of the
;; contents displayed temporarily. Note that without this
;; functionality, learning complex packages like Magit would be difficult
;; because  the list of available commands can be very long.
;; @subsection Recommended Customizations
;; I use the following customizations via .custom, adjust to taste,
;; but use these only after reading the transient info documentations.
;; @itemize
;; @item transient-force-single-column: t
;; @item transient-show-menu: t
;; @item transient-enable-menu-navigation:  t
;; @end itemize
;; 
;; This displays the menu immediately and lets you move through its
;; buttons with the up/down arrows.
;; @subsection Browsing Contents Of transient--show
;; 
;; When executing a command defined via Transient --- e.g. command
;; Magit-dispatch and friends, 
;; @code{?} twice to suspend the transient   --- this calls
;; 2@code{transient-suspend}. Emacsvox now
;; displays a  *transient-emacsvox* buffer that displays the contents of the
;; most recently displayed transient choices. Pressing @kbd {r} resumes
;; the transient; Pressing @kbd{C-q} quits the transient.
;; 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'package)

(defconst emacsvox-transient-minimum-version "0.13.3"
  "Minimum Transient version supported by Emacsvox menus.")

(defun emacsvox-transient--require-supported ()
  "Load a supported Transient, activating installed dependencies if needed.
Never download packages or replace an already loaded Transient."
  (unless (featurep 'transient)
    (unless (package-built-in-p
             'transient (version-to-list emacsvox-transient-minimum-version))
      ;; Isolated -Q sessions skip package activation and Debian site startup.
      ;; Activate only Transient and its dependencies, without loading init files.
      (let ((package-directory-list
             (append package-directory-list
                     (when (file-directory-p "/usr/share/emacs/site-lisp/elpa")
                       '("/usr/share/emacs/site-lisp/elpa")))))
        (package-load-all-descriptors)
        (package-activate 'transient))))
  (require 'transient)
  (let* ((reported (and (boundp 'transient-version) transient-version))
         ;; Bundled releases can use v0.13.3-10-gHASH-builtin.
         (version (and (stringp reported)
                       (string-match "\\`v?\\([0-9]+\\(?:\\.[0-9]+\\)*\\)" reported)
                       (match-string 1 reported))))
    (unless (and version
                 (version<= emacsvox-transient-minimum-version version))
      (error (concat "Emacsvox requires Transient %s or newer; loaded %s from %s. "
                     "Upgrade Transient with M-x package-upgrade, then restart Emacs")
             emacsvox-transient-minimum-version (or reported "unknown")
             (or (symbol-file 'transient-setup) "unknown location")))))

(emacsvox-transient--require-supported)

(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-provider-workflows)
(require 'derived)
(require 'transient)

(defcustom emacsvox-transient-navigation-style 'section-wrap
  "How Up and Down move through Transient menu items.
Continuous navigation crosses sections and wraps around the whole menu.
Section wrapping cycles within the current section.  Section stops keep
point at its first or last item and play a boundary cue.  Left and Right
move between sections in every style.  This setting applies globally."
  :type '(choice (const :tag "Continuous" continuous)
                 (const :tag "Wrap within section" section-wrap)
                 (const :tag "Stop at section edges" section-stop))
  :group 'emacsvox)

(defcustom emacsvox-transient-section-announcement-order 'item-first
  "How Transient navigation announces items and sections.
Item first speaks the item, then the section name and position.  Section
first speaks the section name and position before the item.  By movement
speaks only the section for section navigation and only the item for item
navigation, even across sections.  Section navigation still selects the
first item; a zero-count item movement reads it without moving.
This setting applies globally, including Magit, and does not change navigation."
  :type '(choice (const :tag "Item first" item-first)
                 (const :tag "Section first" section-first)
                 (const :tag "By movement: sections or items" by-movement))
  :group 'emacsvox)

(defcustom emacsvox-transient-verbose-descriptions t
  "Whether Transient items include their command documentation summaries.
When enabled, retain each label and value and add the first line of the
command's docstring.  This applies to all Transient menus, including Magit.
Items without command documentation keep their labels; Transient's native
infix controls keep their usual descriptions."
  :type 'boolean
  :group 'emacsvox)

(defun emacsvox--advice-transient-format-description-around (original object)
  "Format OBJECT with ORIGINAL, optionally adding command summaries."
  (let ((transient--docsp (or emacsvox-transient-verbose-descriptions
                             transient--docsp))
        (transient-show-docstring-format
         (if emacsvox-transient-verbose-descriptions "%c. %s"
           transient-show-docstring-format)))
    (funcall original object)))

(advice-add 'transient-format-description :around
            #'emacsvox--advice-transient-format-description-around)

;;; Map Faces:

(defconst emacsvox-transient--face-voice-map
  '((transient-active-infix voice-animate)
    (transient-argument voice-animate)
    (transient-delimiter inaudible)
    (transient-disabled-suffix inaudible)
    (transient-enabled-suffix voice-brighten)
    (transient-heading voice-lighten)
    (transient-higher-level voice-brighten)
    (transient-inactive-argument inaudible)
    (transient-inactive-value inaudible)
    (transient-inapt-argument voice-monotone-extra)
    (transient-inapt-suffix voice-smoothen)
    (transient-key voice-animate)
    (transient-key-exit voice-bolden)
    (transient-key-noop inaudible)
    (transient-key-recurse voice-lighten)
    (transient-key-return voice-lighten-medium)
    (transient-key-stack voice-bolden-medium)
    (transient-key-stay voice-animate)
    (transient-mismatched-key voice-monotone-extra)
    (transient-nonstandard-key voice-monotone-extra)
    (transient-unreachable voice-monotone-extra)
    (transient-unreachable-key voice-monotone-extra)
    (transient-value voice-brighten))
  "Voice personalities for the current Transient faces.")

(voice-setup-add-map emacsvox-transient--face-voice-map)

;;;  Advice Interactive Commands:

(defun emacsvox--advice-transient--show-hint-around (original &rest arguments)
  "Keep the visual shortcut hint without sending it to notification speech."
  (let ((emacsvox-speak-messages nil))
    (apply original arguments)))

(advice-add 'transient--show-hint :around
            #'emacsvox--advice-transient--show-hint-around)

(defun emacsvox--advice-transient--invalid-around (original message)
  "Keep the visual invalid-key MESSAGE and speak concise recovery guidance."
  ;; Preserve upstream emergency diagnostics if its overriding map was lost.
  (if (not (and transient--transient-map
                (memq transient--transient-map overriding-terminal-local-map)))
      (funcall original message)
    (let ((key (emacsvox-transient--key-text
                (key-description (this-single-command-keys)))))
      (prog1 (let ((emacsvox-speak-messages nil)) (funcall original message))
        (emacsvox-transient--submit-text
         (format "%s is not available here. Control G closes this menu." key)
         (emacsvox-transient--item-facts 'command this-command 'operation-failed)
         'state-change 'warn-user)))))

(advice-add 'transient--invalid :around
            #'emacsvox--advice-transient--invalid-around)

(defun emacsvox--advice-transient-toggle-common-after (&rest _)
  "Present the new common-command visibility setting."
  (when (ems-interactive-p 'transient-toggle-common)
    (emacsvox-transient--submit-actions
     (emacsvox-transient--menu-facts
      'toggle-common 'command-menu-value-changed)
     'state-change
     (if transient-show-common-commands 'on 'off))))

(advice-add 'transient-toggle-common :after
            #'emacsvox--advice-transient-toggle-common-after)

(defun emacsvox-transient--quit-feedback (target)
  "Provide quit feedback when TARGET is the interactive command."
  (when (or (ems-interactive-p target)
            ;; Transient can invoke its suffix through an interactive wrapper.
            (and (eq this-command target)
                 (or transient--prefix transient--exitp)
                 (not (symbolp ems--interactive-fn-name))
                 (functionp ems--interactive-fn-name)))
    (setq ems--interactive-fn-name nil)
    (cond
     ((eq major-mode 'emacsvox-transient-mode)
      (bury-buffer)
      (emacsvox-transient--submit-text
       (emacsvox-transient--buffer-summary)
       (emacsvox-transient--menu-facts
        'close-browser 'command-menu-closed)
       'state-change
       'close-object))
     ((eq target 'transient-quit-seq)
      (emacsvox-transient--submit-actions
       (emacsvox-transient--menu-facts 'abort-key-sequence)
       'navigation
       'close-object))
     ((and (null transient--prefix) (null transient--stack))
      (emacsvox-transient--submit-text
       (emacsvox-transient--buffer-summary)
       (emacsvox-transient--menu-facts
        target 'command-menu-closed)
       'state-change
       'close-object)))))

(defun emacsvox--advice-transient-quit-all-after (&rest _)
  "Provide feedback after quitting all transients."
  (emacsvox-transient--quit-feedback 'transient-quit-all))

(advice-add 'transient-quit-all :after
            #'emacsvox--advice-transient-quit-all-after)

(defun emacsvox--advice-transient-quit-one-after (&rest _)
  "Provide feedback after quitting one transient."
  (emacsvox-transient--quit-feedback 'transient-quit-one))

(advice-add 'transient-quit-one :after
            #'emacsvox--advice-transient-quit-one-after)

(defun emacsvox--advice-transient-quit-seq-after (&rest _)
  "Provide feedback after quitting a transient key sequence."
  (emacsvox-transient--quit-feedback 'transient-quit-seq))

(advice-add 'transient-quit-seq :after
            #'emacsvox--advice-transient-quit-seq-after)

(defun emacsvox-transient--value-feedback (target icon)
  "Present a value change for interactive TARGET with compatibility ICON."
  (when (ems-interactive-p target)
    (emacsvox-transient--submit-actions
     (emacsvox-transient--menu-facts
      target 'command-menu-value-changed)
     'state-change
     icon)))

(defun emacsvox--advice-transient-save-after (&rest _)
  "Provide feedback after saving a transient value."
  (emacsvox-transient--value-feedback 'transient-save 'save-object))

(advice-add 'transient-save :after
            #'emacsvox--advice-transient-save-after)

(defun emacsvox--advice-transient-save-and-exit-after (&rest _)
  "Provide feedback after saving a transient value and exiting."
  (emacsvox-transient--value-feedback
   'transient-save-and-exit 'save-object))

(advice-add 'transient-save-and-exit :after
            #'emacsvox--advice-transient-save-and-exit-after)

(defun emacsvox--advice-transient-set-after (&rest _)
  "Provide feedback after setting a transient value."
  (emacsvox-transient--value-feedback 'transient-set 'save-object))

(advice-add 'transient-set :after
            #'emacsvox--advice-transient-set-after)

(defun emacsvox--advice-transient-set-and-exit-after (&rest _)
  "Provide feedback after setting a transient value and exiting."
  (emacsvox-transient--value-feedback
   'transient-set-and-exit 'save-object))

(advice-add 'transient-set-and-exit :after
            #'emacsvox--advice-transient-set-and-exit-after)

(defun emacsvox--advice-transient-reset-after (&rest _)
  "Provide feedback after clearing saved and session values."
  (emacsvox-transient--value-feedback 'transient-reset 'delete-object))

(advice-add 'transient-reset :after
            #'emacsvox--advice-transient-reset-after)

(defun emacsvox-transient--value-text ()
  "Return a concise textual rendering of the active Transient value."
  (let ((value
         (and
          transient--prefix
          (ignore-errors (oref transient--prefix value)))))
    (emacsvox-transient--format-value value "No arguments")))

(defun emacsvox-transient--format-value (value &optional empty)
  "Return a concise textual rendering of VALUE, using EMPTY for nil."
  (cond
   ((null value) (or empty "off"))
   ((stringp value) value)
   ((listp value)
    (mapconcat
     (lambda (element)
       (if (stringp element) element (format "%s" element)))
     value
     ", "))
   (t (format "%s" value))))

(defun emacsvox-transient--infix-text (object target)
  "Return a concise description of changed infix OBJECT named TARGET."
  (let ((description
         (or
          (ignore-errors
            (transient-with-shadowed-buffer (transient-format-description object)))
          (replace-regexp-in-string
           "\\`[^-]+-" "" (symbol-name target)))))
    (format
     "%s, %s"
     description
     (emacsvox-transient--infix-state object))))

(defun emacsvox-transient--infix-state (object)
  "Describe the current state of infix OBJECT."
  (if (object-of-class-p object 'transient-switch)
      (if (oref object value) "on" "off")
    (emacsvox-transient--format-value (oref object value) "not set")))

(defun emacsvox-transient--key-text (key)
  "Describe KEY for speech, preserving modifiers and letter case."
  (mapconcat
   (lambda (event)
     (let ((text (key-description (vector event)))
           (case-fold-search nil)
           modifiers)
       (while (string-match "\\`\\([CMSsHA]\\)-" text)
         (push (pcase (match-string 1 text)
                 ("C" "Control") ("M" "Alt") ("S" "Shift")
                 ("s" "Super") ("H" "Hyper") ("A" "Alt"))
               modifiers)
         (setq text (substring text 2)))
       (string-join
        (append (nreverse modifiers)
                (list (cond ((equal text "-") "minus")
                            ((equal text "RET") "Enter")
                            ((equal text "SPC") "Space")
                            ((string-match-p "\\`[A-Z]\\'" text)
                             (concat "capital " text))
                            (t text))))
        " ")))
   (kbd key) " "))

(defun emacsvox-transient--choice-text (object &optional _group rendered)
  "Describe suffix OBJECT with RENDERED fallback text.
Section context is announced when navigation enters a section."
  (when (and (eieio-object-p object) (object-of-class-p object 'transient-suffix))
    (let* ((description (ignore-errors
                          (transient-with-shadowed-buffer
                            (transient-format-description object))))
           (infix (object-of-class-p object 'transient-infix))
           ;; Custom suffixes can implement only `transient-format', including
           ;; multiple values.  Keep that rendered evidence without adding it twice.
           (label (or description
                      (when rendered
                        (string-trim
                         (replace-regexp-in-string
                          (concat "\\`[ \t]*" (regexp-quote (oref object key)) "[ \t]+")
                          "" rendered t t))))))
      (when label
        (concat
         label
         (when (and description infix)
           (concat ", " (emacsvox-transient--infix-state object)))
         (if (string-suffix-p "." label) " " ". ")
         (when (oref object inapt) "Unavailable. ")
         (emacsvox-transient--key-text (oref object key)) ".")))))

(defun emacsvox--advice-transient-infix-set-after (object _value)
  "Present an interactively changed Transient infix OBJECT."
  (let ((target (ignore-errors (oref object command))))
    (when
        (and
         target
         (or (ems-interactive-p target)
             ;; Transient wraps interactive suffix commands in a function
             ;; object.  Require the active suffix, not just a command name,
             ;; so initialization and cleanup of other values stay silent.
             (and transient--prefix
                  (eq target this-command)
                  (not (symbolp ems--interactive-fn-name))
                  (functionp ems--interactive-fn-name)
                  (eq object (transient-suffix-object this-command)))))
      (setq ems--interactive-fn-name nil)
      (emacsvox-transient--submit-text
       (emacsvox-transient--infix-text object target)
       (emacsvox-transient--item-facts
        'value target 'command-menu-value-changed '(selected))
       'state-change
       'select-object))))

(advice-add 'transient-infix-set :after
            #'emacsvox--advice-transient-infix-set-after)

(defun emacsvox--advice-transient-prefix-set-after (value)
  "Present VALUE set by an interactive Transient value preset."
  (let ((target ems--interactive-fn-name))
    (when (and target (ems-interactive-p target))
      (emacsvox-transient--submit-text
       (emacsvox-transient--format-value value "No arguments")
       (emacsvox-transient--item-facts
        'value target 'command-menu-value-changed '(selected))
       'state-change
       'select-object))))

(advice-add 'transient-prefix-set :after
            #'emacsvox--advice-transient-prefix-set-after)

(defun emacsvox-transient--history-feedback (target)
  "Present the active history value when TARGET is interactive."
  (when (ems-interactive-p target)
    (emacsvox-transient--submit-text
     (emacsvox-transient--value-text)
     (emacsvox-transient--item-facts
      'history target 'command-menu-value-changed '(selected))
     'state-change
     'select-object)))

(defun emacsvox--advice-transient-history-next-after (&rest _)
  "Speak the next transient history value."
  (emacsvox-transient--history-feedback 'transient-history-next))

(advice-add 'transient-history-next :after
            #'emacsvox--advice-transient-history-next-after)

(defun emacsvox--advice-transient-history-prev-after (&rest _)
  "Speak the previous transient history value."
  (emacsvox-transient--history-feedback 'transient-history-prev))

(advice-add 'transient-history-prev :after
            #'emacsvox--advice-transient-history-prev-after)

(defun emacsvox-transient--toggle-feedback (target enabled)
  "Present interactive TARGET as ENABLED or disabled."
  (when (ems-interactive-p target)
    (emacsvox-transient--submit-actions
     (emacsvox-transient--menu-facts
      target 'command-menu-value-changed)
     'state-change
     (if enabled 'on 'off))))

(defun emacsvox--advice-transient-toggle-docstrings-after (&rest _)
  "Present the new Transient docstring visibility."
  (emacsvox-transient--toggle-feedback
   'transient-toggle-docstrings transient--docsp))

(advice-add 'transient-toggle-docstrings :after
            #'emacsvox--advice-transient-toggle-docstrings-after)

(defun emacsvox--advice-transient-toggle-level-limit-after (&rest _)
  "Present the new Transient suffix-level visibility."
  (emacsvox-transient--toggle-feedback
   'transient-toggle-level-limit transient--all-levels-p))

(advice-add 'transient-toggle-level-limit :after
            #'emacsvox--advice-transient-toggle-level-limit-after)

(defun emacsvox--advice-transient-toggle-debug-after (&rest _)
  "Present the new Transient debugging state."
  (emacsvox-transient--toggle-feedback
   'transient-toggle-debug transient--debug))

(advice-add 'transient-toggle-debug :after
            #'emacsvox--advice-transient-toggle-debug-after)

(defun emacsvox--advice-transient-set-level-after
    (&optional command level)
  "Present entry to level editing or a saved COMMAND LEVEL."
  (when (ems-interactive-p 'transient-set-level)
    (cond
     ((null command)
      (emacsvox-transient--submit-actions
       (emacsvox-transient--menu-facts 'edit-levels)
       'state-change
       'open-object))
     (level
      (emacsvox-transient--submit-actions
       (emacsvox-transient--menu-facts
        'set-level 'command-menu-value-changed)
       'state-change
       'save-object)))))

(advice-add 'transient-set-level :after
            #'emacsvox--advice-transient-set-level-after)

(defun emacsvox--advice-transient-copy-menu-text-after (&rest _)
  "Present successful copying of the active menu text."
  (when (ems-interactive-p 'transient-copy-menu-text)
    (emacsvox-transient--submit-text
     "Transient menu copied"
     (emacsvox-transient--menu-facts
      'copy-menu-text 'operation-completed)
     'state-change
     'yank-object)))

(advice-add 'transient-copy-menu-text :after
            #'emacsvox--advice-transient-copy-menu-text-after)

(defun emacsvox-transient--scroll-feedback (target)
  "Present the visible menu line after interactive scroll TARGET."
  (when (ems-interactive-p target)
    (emacsvox-transient--present-visible-menu
     target nil 'navigation 'scroll)))

(defun emacsvox--advice-transient-scroll-up-after (&rest _)
  "Present the line reached after scrolling the menu up."
  (emacsvox-transient--scroll-feedback 'transient-scroll-up))

(advice-add 'transient-scroll-up :after
            #'emacsvox--advice-transient-scroll-up-after)

(defun emacsvox--advice-transient-scroll-down-after (&rest _)
  "Present the line reached after scrolling the menu down."
  (emacsvox-transient--scroll-feedback 'transient-scroll-down))

(advice-add 'transient-scroll-down :after
            #'emacsvox--advice-transient-scroll-down-after)

(define-derived-mode emacsvox-transient-mode special-mode
  "Browse current transient choices"
  "emacsvox integration with Transient."

  (setq-local emacsvox-aural-module 'transient)
  (let ((map (copy-keymap transient-sticky-map)))
    (define-key map (kbd "M-n") #'emacsvox-transient-next-section)
    (define-key map (kbd "M-p") #'emacsvox-transient-previous-section)
    (define-key map "q" #'bury-buffer)
    (define-key map "r" #'transient-resume)
    (define-key map (kbd "C-g") #'bury-buffer)
    (use-local-map map)))

(defvar emacsvox-transient-cache nil
  "Cache of the last Transient buffer contents.")

(defvar emacsvox-transient--announced-prefix nil
  "Transient prefix object whose initial display was last announced.")

(defvar emacsvox-transient--announced-stack nil
  "Command identity of the stack paired with the announced prefix.")

(defvar emacsvox-transient--return-targets
  (make-hash-table :test #'eq :weakness 'key)
  "Invoking items owned by live stack entries or awaiting prefix displays.
Each value contains the parent command, suffix key, and suffix command.
Weak keys let abandoned menus release their return state.")

(defvar emacsvox-transient--restoring-target nil
  "Invoking item awaiting display while a parent menu is being restored.")

(defun emacsvox--advice-transient--do-stack-around (original)
  "Retain an Emacsvox submenu's invoking item while ORIGINAL stacks its parent."
  (let* ((prefix transient--prefix)
         (command (and prefix (oref prefix command)))
         (suffix (and command
                      (string-prefix-p "emacsvox-" (symbol-name command))
                      (cl-find this-command transient--suffixes
                               :key (lambda (item) (oref item command)))))
         (target (and suffix (list command (oref suffix key) this-command))))
    (prog1 (funcall original)
      (when (and target transient--stack)
        (puthash (car transient--stack) target emacsvox-transient--return-targets)))))

(advice-add 'transient--do-stack :around
            #'emacsvox--advice-transient--do-stack-around)

(defun emacsvox--advice-transient--stack-pop-around (original)
  "Make the saved invoking item available while ORIGINAL restores its parent."
  (let* ((entry (car transient--stack))
         (emacsvox-transient--restoring-target
          (gethash entry emacsvox-transient--return-targets)))
    (remhash entry emacsvox-transient--return-targets)
    (prog1 (funcall original)
      ;; A delayed menu may not have displayed during `transient-setup'.
      (when (and emacsvox-transient--restoring-target transient--prefix
                 (eq (oref transient--prefix command)
                     (car emacsvox-transient--restoring-target)))
        (puthash transient--prefix emacsvox-transient--restoring-target
                 emacsvox-transient--return-targets)))))

(advice-add 'transient--stack-pop :around
            #'emacsvox--advice-transient--stack-pop-around)

(defun emacsvox-transient--restore-return-target ()
  "Restore the invoking item once, before announcing the displayed parent."
  (when-let* ((target (or emacsvox-transient--restoring-target
                          (gethash transient--prefix emacsvox-transient--return-targets)))
              (_ (eq (oref transient--prefix command) (car target))))
    (setq emacsvox-transient--restoring-target nil)
    (remhash transient--prefix emacsvox-transient--return-targets)
    (when-let* ((suffix (cl-find-if
                        (lambda (item)
                          (and (equal (oref item key) (nth 1 target))
                               (eq (oref item command) (nth 2 target))))
                        transient--suffixes)))
      (with-selected-window transient--window
        (transient--goto-button suffix)))))

(defun emacsvox-transient--stack-commands ()
  "Return the command identities in the current Transient stack."
  (mapcar #'car transient--stack))

(defun emacsvox-transient--menu-facts (action &optional event)
  "Return semantic command-menu facts for ACTION and optional EVENT."
  (append
   (list :role 'command-menu :command-menu-action action)
   (when event (list :events (list event)))))

(defun emacsvox-transient--item-facts
    (kind action &optional event states)
  "Return semantic item facts for KIND, ACTION, optional EVENT and STATES."
  (append
   (list
    :role 'command-menu-item
    :command-menu-item-kind kind
    :command-menu-action action)
   (when event (list :events (list event)))
   (when states (list :states states))))

(defun emacsvox-transient--submit-actions (facts occasion &rest icons)
  "Submit FACTS and compatibility ICONS, replacing previous main feedback."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'transient
   :occasion occasion
   :lane 'main :delivery-policy 'replaceable
   :replacement-key 'speaker :interruption-policy 'lane
   :compatibility-actions
   (mapcar #'emacsvox-aural-compatibility-icon icons)))

(defun emacsvox-transient--submit-text
    (content facts occasion &optional icon icon-phase)
  "Submit CONTENT under FACTS and OCCASION with an optional compatibility ICON.
ICON-PHASE defaults to `before'.  Replace and interrupt previous main speech."
  (if (and (stringp content) (> (length content) 0))
      (emacsvox-aural-submit
       content
       :facts facts
       :module 'transient
       :occasion occasion
       :lane 'main :delivery-policy 'replaceable
       :replacement-key 'speaker :interruption-policy 'lane
       :compatibility-actions
       (when icon
         (list
          (emacsvox-aural-compatibility-icon icon icon-phase))))
    (when icon
      (emacsvox-transient--submit-actions facts occasion icon))))

(defun emacsvox-transient--line-content ()
  "Return the current menu line with source presentation metadata."
  (emacsvox-aural-source-substring
   (line-beginning-position) (line-end-position)))

(defun emacsvox-transient--buffer-summary ()
  "Return a concise voice-preserving summary of the selected buffer."
  (concat
   (propertize (buffer-name) 'personality 'voice-lighten-medium)
   ", "
   (propertize
    (downcase
     (or
      (and (stringp mode-name) mode-name)
      (and (listp mode-name) (cl-find-if #'stringp mode-name))
      (replace-regexp-in-string
       "-mode\\'" "" (symbol-name major-mode))))
    'personality 'voice-animate)))

(defun emacsvox-transient--present-visible-menu
    (action event occasion icon)
  "Present the visible menu for ACTION, EVENT, OCCASION, and compatibility ICON."
  (let ((facts (emacsvox-transient--menu-facts action event)))
    (if (window-live-p transient--window)
        (with-current-buffer (window-buffer transient--window)
          (emacsvox-transient--submit-text
           (emacsvox-transient--line-content)
           facts occasion icon))
      (emacsvox-transient--submit-actions facts occasion icon))))

(defun emacsvox-transient--new-menu-p ()
  "Return non-nil when the current Transient menu was not yet announced."
  (or
   (not (eq transient--prefix emacsvox-transient--announced-prefix))
   (not
    (equal
     (emacsvox-transient--stack-commands)
     emacsvox-transient--announced-stack))))

(defun emacsvox-transient--record-announced-menu ()
  "Record the current Transient prefix and stack as announced."
  (setq
   emacsvox-transient--announced-prefix transient--prefix
   emacsvox-transient--announced-stack
   (emacsvox-transient--stack-commands)))

(defun emacsvox-transient--opening-text ()
  "Describe the menu purpose, navigation keys, and current line."
  (let* ((command (ignore-errors (oref transient--prefix command)))
         (purpose (and command (documentation command t))))
    (concat
     (if (and (stringp purpose) (not (string-empty-p purpose)))
         (car (split-string purpose "\n"))
       "Command menu.")
     " Up and down: options. Left and right: sections."
     (when (eq command 'emacsvox-indentation)
       " Shift left and right: adjust volume. Space: preview.")
     (when (eq command 'emacsvox-indentation-tone)
       " Shift left and right: adjust. Space: preview pitch tone.")
     (when (eq command 'emacsvox-aural-menu-sounds)
       " Shift left and right: adjust volume.")
     (when (eq command 'emacsvox-aural-menu-speech)
       " Shift left and right: adjust rate.")
     (when (eq command 'emacsvox-aural-voice-menu)
       " Shift left and right: adjust. Capital P: preview. Capital S: stop.")
     (when (eq command 'emacsvox-capitalization-cue)
       " Shift left and right: adjust draft. Space: preview beep.")
     (when (eq command 'emacsvox-interaction)
       " Shift left and right: adjust phonetic delay. Space: preview source line.")
     (if (eq (lookup-key transient--transient-map (kbd "RET"))
             #'transient-push-button)
         " Enter: activate. Control G: close. "
       " Control J: activate. Control G: close. ")
     (emacsvox-transient--line-content))))

(defun emacsvox--advice-transient--show-after (&rest _)
  "Cache the menu and announce a new or explicitly requested display."
  (when (window-live-p transient--window)
    (emacsvox-transient--restore-return-target)
    (with-current-buffer (window-buffer transient--window)
      (setq-local emacsvox-aural-module 'transient)
      (setq
       emacsvox-transient-cache
       (emacsvox-aural-source-substring (point-min) (point-max)))
      (when
          (or
           (emacsvox-transient--new-menu-p)
           (eq ems--interactive-fn-name 'transient-show))
        (emacsvox-transient--record-announced-menu)
        (unless (eq ems--interactive-fn-name 'transient-resume)
          (emacsvox-transient--submit-text
           (emacsvox-transient--opening-text)
           (emacsvox-transient--menu-facts
            'show 'command-menu-opened)
           'navigation
           'open-object))))))

(advice-add 'transient--show :after
            #'emacsvox--advice-transient--show-after)

(defun emacsvox--advice-transient-help-after (&optional interactivep)
  "Announce help selection when INTERACTIVEP enters that state."
  ;; The next key calls this function again noninteractively to display help.
  (when (and interactivep transient--helpp)
    (emacsvox-transient--submit-text
     "Help: press an item's key, or question mark for the menu overview."
     (emacsvox-transient--menu-facts 'help-selection)
     'state-change)))

(advice-add 'transient-help :after #'emacsvox--advice-transient-help-after)

(defun emacsvox--advice-transient-show-help-around (original object)
  "Show the active menu overview, retaining ORIGINAL help for other OBJECTs."
  (if (and (eieio-object-p object)
           (object-of-class-p object 'transient-prefix)
           (eq object transient--prefix))
      (progn
        ;; Render now even when help was requested before the display delay.
        (transient--show)
        (let ((contents emacsvox-transient-cache)
              (purpose (documentation (oref object command) t))
              (buffer (get-buffer-create "*Transient-Emacsvox*")))
          (with-current-buffer buffer
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert "q to return to the menu.\n\n")
              (when purpose (insert purpose "\n\n"))
              (insert contents)
              ;; This is a readable snapshot; actions run in the resumed menu.
              (remove-text-properties
               (point-min) (point-max)
               '(button nil category nil keymap nil action nil))
              (goto-char (point-min)))
            (emacsvox-transient-mode)
            ;; `transient--display-help' enables the minor mode that remaps
            ;; `quit-window' to resume the captured menu and its parent stack.
            (local-set-key "q" #'quit-window)
            (local-set-key (kbd "C-g") #'quit-window))
          (pop-to-buffer buffer)
          (emacsvox-transient--submit-text
           (emacsvox-transient--buffer-summary)
           (emacsvox-transient--menu-facts 'help 'command-menu-suspended)
           'state-change 'open-object)))
    (funcall original object)))

(advice-add 'transient-show-help :around
            #'emacsvox--advice-transient-show-help-around)

(defun emacsvox--advice-transient-suspend-around (orig-fun)
  "Suspend once and display the cached menu in a browsable buffer."
  ;; Transient also suspends while displaying Help, which owns its return path.
  (if (and (not (bound-and-true-p transient-resume-mode))
           (ems-interactive-p 'transient-suspend))
      (let
          ((buff (get-buffer-create "*Transient-Emacsvox*"))
           (inhibit-read-only t))
        (prog1 (funcall orig-fun)
          (with-current-buffer buff
            (erase-buffer)
            (insert "r to resume, q to close this browser.\n\n")
            (insert emacsvox-transient-cache)
            (goto-char (point-min))
            (emacsvox-transient-mode))
          (switch-to-buffer buff)
          (emacsvox-transient--submit-text
           (emacsvox-transient--buffer-summary)
           (emacsvox-transient--menu-facts
            'suspend 'command-menu-suspended)
           'state-change
           'close-object)))
    (funcall orig-fun)))

(advice-add 'transient-suspend :around
            #'emacsvox--advice-transient-suspend-around)

(defun emacsvox--advice-transient-resume-around
    (orig-fun &rest arguments)
  "Resume once and present success only when a suspended menu existed."
  (let ((resumable (or transient--stack transient-resume-mode)))
    (prog1
        (apply orig-fun arguments)
      (when (ems-interactive-p 'transient-resume)
        (when resumable
          (emacsvox-transient--present-visible-menu
           'resume 'command-menu-resumed 'state-change 'open-object))))))

(advice-add 'transient-resume :around
            #'emacsvox--advice-transient-resume-around)

;;; section nav:

(defun emacsvox-transient--navigation-window ()
  "Return the window whose Transient menu content should be navigated."
  (if (derived-mode-p 'emacsvox-transient-mode)
      (selected-window)
    (if (window-live-p transient--window)
        transient--window
      (selected-window))))

(defun emacsvox-transient--present-range (start end kind action &optional icon)
  "Present START through END as a selected menu item of KIND and ACTION.
When non-nil, preserve compatibility ICON."
  (emacsvox-transient--submit-text
   (emacsvox-aural-source-substring start end)
   (emacsvox-transient--item-facts
    kind action 'focus-entered '(selected))
   'navigation
   icon))

(defun emacsvox-transient--sections ()
  "Return complete heading line ranges in the current single-column menu."
  (save-excursion
    (goto-char (point-min))
    (let (sections match)
      (while (setq match (text-property-search-forward
                         'face nil
                         (lambda (_ face)
                           (or (eq face 'transient-heading)
                               (and (listp face) (memq 'transient-heading face))))))
        ;; A branch name or value can have a different face inside one heading.
        (goto-char (prop-match-beginning match))
        (push (cons (line-beginning-position) (line-end-position)) sections)
        (forward-line 1))
      (nreverse sections))))

(defun emacsvox-transient--section-at (position sections)
  "Return the heading containing POSITION, from ordered SECTIONS."
  (car (last (seq-take-while (lambda (section) (<= (car section) position)) sections))))

(defun emacsvox-transient--section-text (section sections)
  "Describe SECTION and its position within SECTIONS."
  (concat
   (string-trim (emacsvox-aural-source-substring (car section) (cdr section)))
   ". "
   (propertize
    (format "%d of %d section%s."
            (1+ (cl-position section sections :test #'equal)) (length sections)
            (if (= (length sections) 1) "" "s"))
    'personality 'voice-annotate)))

(defun emacsvox-transient--move-section (backward)
  "Select the first item in the next section, or previous when BACKWARD."
  (with-selected-window (emacsvox-transient--navigation-window)
    (let* ((action (if backward 'previous-section 'next-section))
           (previous (point))
           (sections (emacsvox-transient--sections))
           (position (or (car (emacsvox-transient--section-at (point) sections))
                         (line-beginning-position)))
           (section (cl-find-if
                     (lambda (range) (if backward (< (car range) position)
                                       (> (car range) position)))
                     (if backward (reverse sections) sections))))
      (if section
          (let ((end (or (car (cadr (member section sections))) (point-max)))
                button)
            (goto-char (car section))
            (setq button (next-button (point) t))
            (while (and button (< (button-start button) end)
                        (button-get button 'skip))
              (setq button (next-button (button-end button) t)))
            (if (and button (< (button-start button) end))
                (progn
                  (goto-char (button-start button))
                  (emacsvox-transient--speak-button
                   previous nil
                   (eq emacsvox-transient-section-announcement-order 'by-movement)))
              (emacsvox-transient--submit-text
               (emacsvox-transient--section-text section sections)
               (emacsvox-transient--item-facts 'section action 'focus-entered)
               'navigation 'section)))
        (emacsvox-transient--submit-text
         (cond ((null sections) "No sections in this menu.")
               (backward "First section.")
               (t "Last section."))
         (emacsvox-transient--item-facts
          'section action 'operation-failed)
         'navigation
         'warn-user)))))

(defun emacsvox-transient-next-section ()
  "Next transient section."
  (interactive)
  (emacsvox-transient--move-section nil))

(defun emacsvox-transient-previous-section ()
  "Previous transient section."
  (interactive)
  (emacsvox-transient--move-section t))

;;; Hooks:

(defun emacsvox-transient-post-hook ()
  "Forget the announcement after exit unless a new menu is already active."
  ;; A child can be displayed before the parent's exit hook runs.
  (unless transient--prefix
    (setq
     emacsvox-transient--announced-prefix nil
     emacsvox-transient--announced-stack nil)))

(add-hook 'transient-exit-hook 'emacsvox-transient-post-hook)

;;; Advice transient navigation:

(defun emacsvox-transient--move-within-section (n)
  "Move N items within the current section; return non-nil at a hard stop."
  (with-selected-window transient--window
    (let* ((sections (emacsvox-transient--sections))
           (section (or (emacsvox-transient--section-at (point) sections)
                        (car sections)))
           (start (or (car section) (point-min)))
           (end (or (car (cadr (member section sections))) (point-max)))
           (position start)
           buttons button)
      (while (and (< position end)
                  (setq button (next-button position t))
                  (< (button-start button) end))
        (unless (button-get button 'skip)
          (push (button-start button) buttons))
        (setq position (button-end button)))
      (setq buttons (nreverse buttons))
      (if (null buttons)
          t
        (let* ((current (cl-position
                         (when-let* ((at-point (button-at (point))))
                           (button-start at-point))
                         buttons))
               ;; A section heading enters at its first item with Down and
               ;; its last item with Up, without crossing to another section.
               (target (if current (+ current n)
                         (if (< n 0) (+ (length buttons) n) (max 0 (1- n)))))
               (index (if (eq emacsvox-transient-navigation-style 'section-wrap)
                          (mod target (length buttons))
                        (max 0 (min target (1- (length buttons)))))))
          (goto-char (nth index buttons))
          (and (eq emacsvox-transient-navigation-style 'section-stop)
               current (= current index) (/= target index)))))))

(defun emacsvox-transient--navigate-button (original n direction interactive)
  "Call ORIGINAL with N or move DIRECTION items for INTERACTIVE navigation."
  (if (and interactive (window-live-p transient--window)
           (memq emacsvox-transient-navigation-style '(section-wrap section-stop)))
      (let ((previous (window-point transient--window)))
        (if (emacsvox-transient--move-within-section direction)
            (emacsvox-transient--submit-actions
             (emacsvox-transient--item-facts
              'section 'section-boundary 'operation-failed)
             'navigation 'warn-user)
          (emacsvox-transient--speak-button previous direction)))
    (let ((previous (and (window-live-p transient--window)
                         (window-point transient--window))))
      (prog1 (funcall original n)
        (when interactive
          (emacsvox-transient--speak-button previous direction))))))

(defun emacsvox-transient--choice-selected-p (object text)
  "Return non-nil if OBJECT has an active value or TEXT marks it selected."
  (or (and (eieio-object-p object)
           (object-of-class-p object 'transient-infix)
           (oref object value))
      (and (stringp text) (> (length text) 0)
           (memq 'selected
                 (plist-get (get-text-property 0 emacsvox-aural-facts-property text)
                            :states)))))

(defun emacsvox-transient--speak-button (&optional previous direction section-only)
  "Present the current button, noting section changes and wraps from PREVIOUS.
DIRECTION is positive for forward movement, negative for backward movement.
SECTION-ONLY speaks its section while retaining the button's facts and cues."
  (with-selected-window (emacsvox-transient--navigation-window)
    (when-let* ((button (button-at (point)))
                (start (button-start button))
                (end (button-end button)))
      (let* ((sections (emacsvox-transient--sections))
             (section (emacsvox-transient--section-at start sections))
             (old-section (and previous (emacsvox-transient--section-at previous sections)))
             (object (button-get button 'button-data))
             (choice (or (emacsvox-transient--choice-text
                          object nil (emacsvox-aural-source-substring start end))
                         (emacsvox-aural-source-substring start end)))
             (selected (emacsvox-transient--choice-selected-p object choice))
             (toggle (get-text-property 0 'emacsvox-transient-toggle-state choice))
             (wrap (and previous direction
                        (or (and (> direction 0) (<= start previous))
                            (and (< direction 0) (>= start previous)))))
             (section-change
              (and section
                   (or (not (equal section old-section))
                       (and wrap (eq emacsvox-transient-navigation-style 'continuous))))))
        (emacsvox-transient--submit-text
         (cond
          ((and section-only section)
           (emacsvox-transient--section-text section sections))
          ((and section-change
                (not (eq emacsvox-transient-section-announcement-order 'by-movement)))
           (let ((heading (emacsvox-transient--section-text section sections)))
             (if (eq emacsvox-transient-section-announcement-order 'section-first)
                 (concat heading " " choice)
               (concat choice " " heading))))
          (t choice))
         (emacsvox-transient--item-facts
          (if (and (eieio-object-p object)
                   (object-of-class-p object 'transient-infix)) 'value 'command)
          'focus-button 'focus-entered (when selected '(selected)))
         'navigation
         (cond (wrap 'repeat-start)
               (section-change 'section)
               ((memq toggle '(on off)) toggle)
               (selected 'select-object)))))))

(defun emacsvox--advice-transient-backward-button-around
    (orig-fun n)
  "Speak the button reached after moving backward by N."
  ;; Transient's temporary interactive wrapper can replace our command marker
  ;; with a function object.  Check the interactive call before moving instead.
  (let ((interactive
         (or (ems-interactive-p 'transient-backward-button)
             (and (eq this-command 'transient-backward-button)
                  (called-interactively-p 'any)))))
    (emacsvox-transient--navigate-button orig-fun n (- n) interactive)))

(advice-add 'transient-backward-button :around
            #'emacsvox--advice-transient-backward-button-around)

(defun emacsvox--advice-transient-forward-button-around
    (orig-fun n)
  "Speak the button reached after moving forward by N."
  (let ((interactive
         (or (ems-interactive-p 'transient-forward-button)
             (and (eq this-command 'transient-forward-button)
                  (called-interactively-p 'any)))))
    (emacsvox-transient--navigate-button orig-fun n n interactive)))

(advice-add 'transient-forward-button :around
            #'emacsvox--advice-transient-forward-button-around)

;;; Enable And Customize Transient Navigation:

(defun emacsvox-transient--settings-enter-binding (map)
  "Add Enter activation to MAP for the Emacsvox settings menus."
  (when (and transient-enable-menu-navigation transient--prefix
             (memq (oref transient--prefix command)
                   '(emacsvox-aural-menu emacsvox-aural-menu-speech
                     emacsvox-aural-menu-navigation emacsvox-aural-menu-sounds
                     emacsvox-aural-menu-punctuation emacsvox-aural-menu-voices
                     emacsvox-aural-voice-menu emacsvox-indentation
                     emacsvox-capitalization emacsvox-capitalization-cue
                     emacsvox-interaction emacsvox-indentation-tone
                     emacsvox-aural-menu-line-cues emacsvox-line-cues-edit
                     emacsvox-output-settings emacsvox-settings-buffer emacsvox-settings-feedback emacsvox-settings-presentation emacsvox-settings-setups emacsvox-settings-integrations
                     emacsvox-settings-diagnostics emacsvox-settings-history emacsvox-settings-switches
                     emacsvox-settings-voice-presentation emacsvox-settings-preview-labels
                     emacsvox-settings-integrations--comint
                     emacsvox-settings-integrations--eat
                         emacsvox-settings-integrations--eat-choice
                         emacsvox-settings-integrations--agent
                         emacsvox-settings-integrations--choice
                         emacsvox-settings-integrations--org
                         emacsvox-settings-integrations--eww
                         emacsvox-settings-integrations--notmuch)))
    (keymap-set map "RET" #'transient-push-button)
    (keymap-set map "<return>" #'transient-push-button))
  map)

(advice-add 'transient--make-transient-map :filter-return
            #'emacsvox-transient--settings-enter-binding)

(defun emacsvox-transient-setup ()
  "Emacsvox Transient Customizations"
  (keymap-set  transient-popup-navigation-map "C-j" #'transient-push-button)
  (define-key transient-predicate-map
              [emacsvox-transient-previous-section] 'transient--do-move)
  (define-key transient-predicate-map
              [emacsvox-transient-next-section] 'transient--do-move)

  (define-key transient-popup-navigation-map
              [left] 'emacsvox-transient-previous-section)
  (define-key transient-popup-navigation-map
              [right] 'emacsvox-transient-next-section)

  (setq transient-enable-menu-navigation t
        transient-force-single-column t
        transient-semantic-coloring t
        transient-show-menu t))
(emacsvox-transient-setup)

(provide 'emacsvox-transient)

;;; emacsvox-transient.el ends here
