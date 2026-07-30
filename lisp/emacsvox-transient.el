;;; emacsvox-transient.el --- TRANSIENT  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable TRANSIENT An Emacs Interface to transient
;; Keywords: Emacsvox,  Audio Desktop transient
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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
;; MERCHANTABILITY or FITNTRANSIENT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


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
;; @item  transient-show-menu:  1
;; @item transient-enable-menu-navigation:  t
;; @end itemize
;; 
;; this pops up the transient buffer after a short delay  and lets
;; you move through the buttons with the    up/down arrows. 
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
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-provider-workflows)
(require 'derived)
(require 'transient)

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

(defun emacsvox--advice-transient-toggle-common-after (&rest _)
  "Present the new common-command visibility setting."
  (when (ems-interactive-p 'transient-toggle-common)
    (tts-stop 'all)
    (emacsvox-transient--submit-actions
     (emacsvox-transient--menu-facts
      'toggle-common 'command-menu-value-changed)
     'state-change
     (if transient-show-common-commands 'on 'off))))

(advice-add 'transient-toggle-common :after
            #'emacsvox--advice-transient-toggle-common-after)

(defun emacsvox-transient--quit-feedback (target)
  "Provide quit feedback when TARGET is the interactive command."
  (when (ems-interactive-p target)
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
     ((null transient--prefix)
      (tts-stop 'all)
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
    (tts-stop 'all)
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
    (cond
     ((null value) "No arguments")
     ((stringp value) value)
     ((listp value)
      (mapconcat
       (lambda (element)
         (if (stringp element) element (format "%s" element)))
       value
       ", "))
     (t (format "%s" value)))))

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
  "Submit FACTS and compatibility ICONS as one action-only transaction."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'transient
   :occasion occasion
   :compatibility-actions
   (mapcar #'emacsvox-aural-compatibility-icon icons)))

(defun emacsvox-transient--submit-text
    (content facts occasion &optional icon icon-phase)
  "Submit CONTENT under FACTS and OCCASION with an optional compatibility ICON.
ICON-PHASE defaults to `before'."
  (if (and (stringp content) (> (length content) 0))
      (emacsvox-aural-submit
       content
       :facts facts
       :module 'transient
       :occasion occasion
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

(defun emacsvox--advice-transient--show-after (&rest _)
  "Cache the menu and announce a new or explicitly requested display."
  (when (window-live-p transient--window)
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
           (emacsvox-transient--line-content)
           (emacsvox-transient--menu-facts
            'show 'command-menu-opened)
           'navigation
           'open-object))))))

(advice-add 'transient--show :after
            #'emacsvox--advice-transient--show-after)

(defun emacsvox--advice-transient-suspend-around (orig-fun)
  "Suspend once and display the cached menu in a browsable buffer."
  (if (ems-interactive-p 'transient-suspend)
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
          (tts-stop 'all)
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

(defun emacsvox-transient--move-section (backward)
  "Move to and present the next section, or previous when BACKWARD."
  (with-selected-window (emacsvox-transient--navigation-window)
    (let* ((action (if backward 'previous-section 'next-section))
           (match
            (if backward
                (text-property-search-backward
                 'face 'transient-heading t t)
              (text-property-search-forward
               'face 'transient-heading t t))))
      (if match
          (progn
            (goto-char (prop-match-beginning match))
            (emacsvox-transient--present-range
             (point) (prop-match-end match) 'section action))
        (emacsvox-transient--submit-actions
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
  "Forget the menu announcement when a Transient level exits."
  (setq
   emacsvox-transient--announced-prefix nil
   emacsvox-transient--announced-stack nil))

(add-hook 'transient-exit-hook 'emacsvox-transient-post-hook)

;;; Advice transient navigation:

(defun emacsvox-transient--speak-button ()
  "Present the current button in the Transient menu window."
  (with-current-buffer (window-buffer transient--window)
    (when-let* ((button (button-at (point)))
                (start (button-start button))
                (end (button-end button)))
      (emacsvox-transient--present-range
       start end 'command 'focus-button 'button))))

(defun emacsvox--advice-transient-backward-button-around
    (orig-fun n)
  "Speak the button reached after moving backward by N."
  (prog1 (funcall orig-fun n)
    (when (ems-interactive-p 'transient-backward-button)
      (emacsvox-transient--speak-button))))

(advice-add 'transient-backward-button :around
            #'emacsvox--advice-transient-backward-button-around)

(defun emacsvox--advice-transient-forward-button-around
    (orig-fun n)
  "Speak the button reached after moving forward by N."
  (prog1 (funcall orig-fun n)
    (when (ems-interactive-p 'transient-forward-button)
      (emacsvox-transient--speak-button))))

(advice-add 'transient-forward-button :around
            #'emacsvox--advice-transient-forward-button-around)

;;; Enable And Customize Transient Navigation:

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
        transient-show-menu 1))
(emacsvox-transient-setup)

(provide 'emacsvox-transient)
;;;  end of file
