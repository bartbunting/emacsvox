;;; emacsvox-helm.el --- Speech-enable HELM  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable HELM An Emacs Interface to helm
;; Keywords: Emacsvox,  Audio Desktop helm
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
;; MERCHANTABILITY or FITNHELM FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; HELM == Smart narrowing/selection in emacs This module
;; speech-enables Helm interaction.  See tvr/helm-prepare.el in the
;; GitHub repository for my helm setup.  that file provides convenient
;; emacsvox-centric keybindings for Helm interaction.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-google)
(require 'emacsvox-preamble)

;;;  Setup Helm Hooks:

(defun ems--helm-mode-after (&rest _)
  "Cue state of helm mode."
  (when (ems-interactive-p)
    (emacsvox-icon (if helm-mode 'on 'off))
    (message "Turned %s helm-mode" (if helm-mode "on" "off"))))

(advice-add 'helm-mode :after #'ems--helm-mode-after)

(declare-function emacsvox-minibuffer-setup-hook "emacsvox-advice" nil)

(defun emacsvox-helm-before-initialize-hook ()
  "Remove emacsvox minibuffer setup hook."
  (emacsvox-icon 'complete)
  (remove-hook 'minibuffer-setup-hook #'emacsvox-minibuffer-setup-hook))

                                        ;(add-hook
                                        ;'helm-minibuffer-set-up-hook
(defun emacsvox-helm-cleanup-hook ()
  "Restore Emacsvox's minibuffer setup hook."
  (add-hook 'minibuffer-setup-hook #'emacsvox-minibuffer-setup-hook))

(defun emacsvox-helm-cue-update ()
  " Cue update."
  (let ((inhibit-read-only t)
        (line (buffer-substring (line-beginning-position) (line-end-position)))
        (count-msg nil))
    (setq count-msg
          (concat
           (propertize
            (format "%d of %d"
                    (- (line-number-at-pos) 2)
                    (- (count-lines(point-min) (point-max))2))
            'personality voice-bolden)))
    (when (and line count-msg)
      (dtk-speak (concat line count-msg)))))

(add-hook 'helm-move-selection-after-hook #'emacsvox-helm-cue-update 'at-end)
(add-hook 'helm-after-action-hook #'emacsvox-speak-mode-line 'at-end)

;;;  Advice helm-google-suggest to filter results:

(declare-function eww-display-dom-by-id-list  "emacsvox-eww.el" (id-list))

(defun ems--helm-google-suggest-before (&rest _)
  "setup emacsvox post-processing-hook"
  (add-hook 'emacsvox-eww-post-hook
            #'(lambda nil
                (let
                    ((emacsvox-google-toolbelt
                      (emacsvox-google-toolbelt)))
                  (eww-display-dom-by-id-list '("center_col" "rhs"))))))

(advice-add 'helm-google-suggest :before
            #'ems--helm-google-suggest-before)

;;;  Advice helm-recenter-top-bottom-other-window:

(defun ems--helm-recenter-top-bottom-other-window-after (&rest _)
  "Speak current selection."
  (when (ems-interactive-p)
    (with-current-buffer (helm-buffer-get)
      (emacsvox-icon 'scroll) (emacsvox-speak-line))))

(advice-add 'helm-recenter-top-bottom-other-window :after
            #'ems--helm-recenter-top-bottom-other-window-after)

;;;  Advice helm-yank-selection

(defun ems--helm-yank-selection-after (&rest _)
  "Speak minibuffer after yanking."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-line)))

(advice-add 'helm-yank-selection :after
            #'ems--helm-yank-selection-after)

;;;  Support helm-help
(add-hook
 'helm-help-mode-before-hook
 #'(lambda()
     "Turn off speaking read-key prompts"
     (setq emacsvox-speak-messages nil)
     (emacsvox-icon 'open-object)))

(add-hook
 'helm-help-mode-after-hook
 #'(lambda()
     "restore speaking messages."
     (setq emacsvox-speak-messages t)
     (emacsvox-icon 'close-object)))

(provide 'emacsvox-helm)
;;;  end of file

