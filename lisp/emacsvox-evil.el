;;; emacsvox-evil.el --- Speech-enable EVIL  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable EVIL An Emacs Interface to evil
;; Keywords: Emacsvox,  Audio Desktop evil
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
;; MERCHANTABILITY or FITNEVIL FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EVIL ==  VIM In Emacs
;; This is work-in-progress and is not complete.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (evil-ex-commands voice-bolden)
   (evil-ex-info voice-monotone-extra)
   (evil-ex-lazy-highlight voice-animate)
   (evil-ex-search voice-bolden-and-animate)
   (evil-ex-substitute-matches voice-lighten)
   (evil-ex-substitute-replacement voice-smoothen)))

;;;  Interactive Commands:

(defvar emacsvox-evil--advice nil
  "Current Evil targets and their native advice functions.")
(setq emacsvox-evil--advice nil)

(defun emacsvox-evil--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-evil--advice))))

;;;  Switching Buffers:

(defun emacsvox-evil--mode-line-feedback ()
  "Speak the mode line after switching Evil buffers."
  (emacsvox-speak-mode-line))

(emacsvox-evil--register-after-group
 '(evil-next-buffer evil-prev-buffer)
 #'emacsvox-evil--mode-line-feedback)

;;;  Structured  Motion:

(defun emacsvox-evil--selected-line-feedback ()
  "Speak the selected Evil line."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-evil--register-after-group
 '(evil-beginning-of-line evil-end-of-line evil-ret evil-window-top)
 #'emacsvox-evil--selected-line-feedback)

;; we want the next set to be a little less noisy and not play
;; auditory icons when they execute
(defun emacsvox-evil--line-feedback ()
  "Speak the current line."
  (emacsvox-speak-line))

(emacsvox-evil--register-after-group
 '(evil-next-line evil-previous-line)
 #'emacsvox-evil--line-feedback)

;; read visual lines when moving in visual lines 
(defun emacsvox-evil--visual-line-feedback ()
  "Speak the current visual line."
  (emacsvox-speak-visual-line))

(emacsvox-evil--register-after-group
 '(evil-next-visual-line evil-previous-visual-line)
 #'emacsvox-evil--visual-line-feedback)

(defun emacsvox-evil--large-movement-feedback ()
  "Speak after a large Evil movement."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'large-movement)
    (emacsvox-speak-line)))

(emacsvox-evil--register-after-group
 '(evil-goto-mark evil-goto-mark-line
   evil-goto-definition evil-goto-first-line evil-goto-line
   evil-forward-section-begin evil-forward-section-end
   evil-backward-paragraph evil-forward-paragraph
   evil-backward-section-begin evil-backward-section-end
   evil-previous-open-paren evil-previous-match evil-next-match
   evil-next-line-first-non-blank evil-next-line-1-first-non-blank
   evil-next-close-paren evil-last-non-blank
   evil-jump-backward evil-jump-forward evil-jump-to-tag
   evil-forward-sentence-begin evil-first-non-blank
   evil-backward-sentence-begin)
 #'emacsvox-evil--large-movement-feedback)

(defun emacsvox-evil--scroll-feedback ()
  "Speak the current window after an Evil scroll."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-current-window))

(emacsvox-evil--register-after-group
 '(evil-scroll-down evil-scroll-up)
 #'emacsvox-evil--scroll-feedback)

;;;  Word Motion

(defun emacsvox-evil--word-feedback ()
  "Speak the current word after Evil word motion."
  (emacsvox-speak-word))

(emacsvox-evil--register-after-group
 '(evil-backward-word-begin evil-backward-word-end
   evil-forward-word-begin evil-forward-word-end)
 #'emacsvox-evil--word-feedback)

;;;  Char Motion :

(defun emacsvox--advice-evil-backward-char-after (&rest _)
  "Speak the character selected by backward Evil motion."
  (when (ems-interactive-p 'evil-backward-char)
    (emacsvox-speak-this-char (following-char))))

(push '(evil-backward-char :after
        emacsvox--advice-evil-backward-char-after)
      emacsvox-evil--advice)

(defun emacsvox--advice-evil-forward-char-after (&rest _)
  "Speak the character selected by forward Evil motion."
  (when (ems-interactive-p 'evil-forward-char)
    (emacsvox-speak-this-char (following-char))))

(push '(evil-forward-char :after
        emacsvox--advice-evil-forward-char-after)
      emacsvox-evil--advice)

;;;  Deletion:

(defun emacsvox--advice-evil-delete-char-before (&rest _)
  "Speak char we are deleting."
  (when (ems-interactive-p 'evil-delete-char)
    (emacsvox-speak-char t) (dtk-tone-deletion)))

(push '(evil-delete-char :before
        emacsvox--advice-evil-delete-char-before)
      emacsvox-evil--advice)

(defun emacsvox--advice-evil-delete-backward-char-before (&rest _)
  "Speak char we are deleting."
  (when (ems-interactive-p 'evil-delete-backward-char)
    (emacsvox-speak-this-char (preceding-char)) (dtk-tone-deletion)))

(push '(evil-delete-backward-char :before
        emacsvox--advice-evil-delete-backward-char-before)
      emacsvox-evil--advice)

(defun emacsvox--advice-evil-delete-line-after (&rest _)
  "Report deleting to the end of the line."
  (when (ems-interactive-p 'evil-delete-line)
    (tts-speak "Deleted to end of line.")
    (emacsvox-icon 'delete-object)))

(push '(evil-delete-line :after
        emacsvox--advice-evil-delete-line-after)
      emacsvox-evil--advice)

(defun emacsvox--advice-evil-delete-before (beg end &rest _)
  "Speak the Evil deletion between BEG and END."
  (when (ems-interactive-p 'evil-delete)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-region beg end)))

(push '(evil-delete :before emacsvox--advice-evil-delete-before)
      emacsvox-evil--advice)

;;;  Searching:
(defun emacsvox-evil--search-feedback ()
  "Speak an Evil search match with point highlighted."
  (let ((emacsvox-show-point t))
    (emacsvox-speak-line)
    (emacsvox-icon 'search-hit)))

(emacsvox-evil--register-after-group
 '(evil-search-next evil-search-previous)
 #'emacsvox-evil--search-feedback)

;;;  Completion:

(cl-loop
 for target in
 '(evil-complete-next evil-complete-previous)
 for advice-function =
 (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest args)
     ,(format "Call `%s' and speak the completed text." target)
     (if (ems-interactive-p ',target)
         (let ((start
                (save-excursion
                  (skip-syntax-backward "^ >")
                  (point))))
           (ems-with-messages-silenced
            (let ((result (apply original args)))
              (emacsvox-icon 'complete)
              (if (< start (point))
                  (tts-speak (buffer-substring start (point)))
                (tts-speak (word-at-point)))
              result)))
       (apply original args))))
 (push (list target :around advice-function) emacsvox-evil--advice))

(defun emacsvox-evil--line-completion-feedback ()
  "Speak a line completed by Evil."
  (let ((emacsvox-show-point t))
    (emacsvox-icon 'complete)
    (emacsvox-speak-line)))

(emacsvox-evil--register-after-group
 '(evil-complete-next-line evil-complete-previous-line)
 #'emacsvox-evil--line-completion-feedback)

;;;  Marks:

(defun emacsvox--advice-evil-set-marker-after (char &rest _)
  "Speak after setting Evil marker CHAR."
  (when (ems-interactive-p 'evil-set-marker)
    (emacsvox-icon 'mark-object)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line)
      (tts-notify (format "Marker %c" char)))))

(push '(evil-set-marker :after emacsvox--advice-evil-set-marker-after)
      emacsvox-evil--advice)

;;;  Update keymaps:

(defun emacsvox-evil-fix-emacsvox-prefix (keymap)
  "Move original evil command on C-e to C-e e."
  
  (when (keymapp keymap)
    (let ((orig (lookup-key keymap emacsvox-prefix)))
      (when orig
        (define-key keymap emacsvox-prefix  'emacsvox-keymap)
        (define-key keymap (concat emacsvox-prefix "e") orig)
        (define-key keymap (concat emacsvox-prefix emacsvox-prefix) orig)))))

(cl-declaim (special
             evil-normal-state-map evil-insert-state-map
             evil-visual-state-map evil-replace-state-map
             evil-operator-state-map evil-motion-state-map
             evil-evilified-state-map))

(eval-after-load
    "evil-maps"
  `(progn
     (mapc
      #'emacsvox-evil-fix-emacsvox-prefix
      (list
       evil-normal-state-map evil-insert-state-map
       evil-visual-state-map evil-replace-state-map
       evil-operator-state-map evil-motion-state-map))
     (emacsvox-keymap-recover-eol)))

(eval-after-load
    "evil-evilified-state"
  `(progn
     (mapc
      #'emacsvox-evil-fix-emacsvox-prefix
      (list
       evil-evilified-state-map))
     (emacsvox-keymap-recover-eol)))

;;;  State Hooks:

(defun  emacsvox-evil-state-change-hook  ()
  "State change feedback."
  
  (when (and evil-previous-state evil-next-state
             (not (eq evil-previous-state evil-next-state)))
    (emacsvox-icon 'select-object)
    (tts-notify
     (format "Changing state from %s to %s"
             evil-previous-state evil-next-state))))

(cl-loop
 for hook in
 '(
   evil-normal-state-exit-hook evil-insert-state-exit-hook
   evil-visual-state-exit-hook evil-replace-state-exit-hook
   evil-operator-state-exit-hook evil-motion-state-exit-hook)
 do
 (add-hook hook #'emacsvox-evil-state-change-hook))

(defun emacsvox--advice-evil-exit-emacs-state-after (&rest _)
  "Report leaving Evil's Emacs state."
  (when (ems-interactive-p 'evil-exit-emacs-state)
    (emacsvox-icon 'open-object) (tts-notify "Leaving Emacs state.")))

(push '(evil-exit-emacs-state :after
        emacsvox--advice-evil-exit-emacs-state-after)
      emacsvox-evil--advice)

(defun emacsvox-evil--install-advice ()
  "Install native advice after the optional Evil package loads."
  (dolist (entry emacsvox-evil--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'evil
  (emacsvox-evil--install-advice))

;;;  Additional Commands:

(declare-function evil-mode "evil-core" (&optional flag))

(defun emacsvox-evil-toggle-evil ()
  "Interactively toggle evil-mode."
  (interactive)
  
  (cl-assert (locate-library "evil") nil "I see no evil!")
  (require 'evil)
  (evil-mode (if evil-mode -1 1))
  (emacsvox-icon (if evil-mode 'on 'off))
  (message "Turned %s evil-mode"
           (if evil-mode "on" "off")))

(provide 'emacsvox-evil)
;;;  end of file
