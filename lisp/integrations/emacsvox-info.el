;;; emacsvox-info.el --- Speech enable Info -- -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs
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

;; This module speech-enables the Emacs Info Reader.
;;; Code:

;;;  requires

(require 'emacsvox-preamble)
(require 'info)

;;;   Voices

(voice-setup-add-map
 '(
   (Info-emphasis voice-animate)
   (Info-strong voice-bolden)
   (Info-quoted voice-lighten)
   (info-index-match 'voice-animate)
   (info-title-1 voice-bolden-extra)
   (info-title-2 voice-bolden-medium)
   (info-title-3 voice-bolden)
   (info-title-4 voice-lighten)
   (info-header-node voice-smoothen)
   (info-header-xref voice-brighten)
   (info-node voice-monotone-extra)
   (info-xref voice-animate-extra)
   (info-menu-star voice-brighten)
   (info-menu-header voice-bolden)
   (info-xref-visited voice-animate-medium)))

;;;  advice

(defcustom  emacsvox-info-select-node-speak-chunk 'screenfull
  "Specifies how much of the selected node gets spoken.
Possible values are:
screenfull  -- speak the displayed screen
node -- speak the entire node."
  :type '(menu-choice
          (const :tag "First screenfull" screenfull)
          (const :tag "Entire node" node))
  :group 'emacsvox-info)

(defun emacsvox-info-speak-current-window ()
  "Speak current window in info buffer."
  (let ((start  (point))
        (window (get-buffer-window (current-buffer))))
    (save-excursion
      (forward-line (window-height window))
      (emacsvox-speak-region start (point)))))

(defun emacsvox-info-visit-node()
  "Apply requested action upon visiting a node."
  
  (emacsvox-icon 'open-object)
  (cond
   ((eq emacsvox-info-select-node-speak-chunk 'screenfull)
    (emacsvox-info-speak-current-window))
   ((eq emacsvox-info-select-node-speak-chunk 'node)
    (emacsvox-speak-buffer))
   (t (emacsvox-speak-line))))

(cl-loop
 for target in
 '(info info-display-manual Info-follow-reference
        Info-goto-node info-emacs-manual
        Info-top-node Info-final-node Info-up
        Info-goto-emacs-key-command-node Info-goto-emacs-command-node
        Info-history Info-virtual-index Info-directory Info-help
        Info-nth-menu-item
        Info-menu Info-follow-nearest-node
        Info-history-back Info-history-forward
        Info-backward-node Info-forward-node
        Info-next Info-prev)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak a node selected by an interactive Info command."
       (when (ems-interactive-p ',target)
         (emacsvox-info-visit-node)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-Info-search-after (&rest _)
  "Announce an interactive Info search result."
  (when (ems-interactive-p 'Info-search)
    (emacsvox-icon 'search-hit) (emacsvox-speak-line)))

(advice-add 'Info-search :after
            #'emacsvox--advice-Info-search-after)

(defun emacsvox--advice-Info-scroll-up-after (&rest _)
  "Speak the screenful."
  (when (ems-interactive-p 'Info-scroll-up)
    (emacsvox-icon 'scroll)
    (emacsvox-info-speak-current-window)))

(advice-add 'Info-scroll-up :after
            #'emacsvox--advice-Info-scroll-up-after)

(defun emacsvox--advice-Info-scroll-down-after (&rest _)
  "Speak the screenful."
  (when (ems-interactive-p 'Info-scroll-down)
    (emacsvox-icon 'scroll)
    (emacsvox-info-speak-current-window)))

(advice-add 'Info-scroll-down :after
            #'emacsvox--advice-Info-scroll-down-after)

(defun emacsvox--advice-Info-next-reference-after (&rest _)
  "Speak the line. "
  (when (ems-interactive-p 'Info-next-reference)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Info-next-reference :after
            #'emacsvox--advice-Info-next-reference-after)

(defun emacsvox--advice-Info-prev-reference-after (&rest _)
  "Speak the line. "
  (when (ems-interactive-p 'Info-prev-reference)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Info-prev-reference :after
            #'emacsvox--advice-Info-prev-reference-after)

;;;###autoload
(defun emacsvox-info-wizard (node-spec)
  "Read a node spec from the minibuffer and launch
Info-goto-node.
See documentation for command `Info-goto-node' for details on
node-spec."
  (interactive
   (list
    (let ((completion-ignore-case t)
          (f nil)
          (n nil))
      (info-initialize)
      (setq f (completing-read "File: " (info--manual-names nil) nil t))
      (setq n (completing-read "Node: " (Info-build-node-completions f)))
      (format "(%s)%s" f n))))
  (Info-goto-node node-spec)
  (emacsvox-info-visit-node))

;;;  Info: Section navigation
;; Use property info-title-* to move across section titles.
(defvar emacsvox-info--title-faces
  '(info-title-1 info-title-2 info-title-3 info-title-4 info-menu-header)
  "Faces that identify section titles.")

(defun emacsvox-info-next-section ()
  "Move forward to next section in this node."
  (interactive)
  (let ((target nil))
    (save-excursion
      (while (and (null target)
                  (not (eobp)))
        (goto-char
         (next-single-property-change (point)  'face nil (point-max)))
        (when
            (memq (get-text-property (point) 'face) emacsvox-info--title-faces)
          (setq target (point)))))
    (cond
     (target
      (goto-char target)
      (emacsvox-speak-line)
      (emacsvox-icon 'large-movement))
     (t (message "No more sections in this node")))))

(defun emacsvox-info-previous-section ()
  "Move backward to previous section in this node."
  (interactive)
  (let ((target nil))
    (save-excursion
      (while (and (null target)
                  (not (bobp)))
        (goto-char
         (previous-single-property-change (point)  'face nil (point-min)))
        (when
            (memq (get-text-property (point) 'face) emacsvox-info--title-faces)
          (setq target (line-beginning-position)))))
    (cond
     (target
      (goto-char target)
      (emacsvox-speak-line)
      (emacsvox-icon 'large-movement))
     (t (message "No previous section in   this node")))))

;;;  Speak header line if hidden

(defvar Info-use-header-line)
(defvar Info-header-line)

(defun emacsvox-info-speak-header ()
  "Speak info header line."
  (interactive)
  (cond
   ((and (boundp 'Info-use-header-line)
         (boundp 'Info-header-line)
         Info-header-line)
    (tts-speak Info-header-line))
   (t (save-excursion
        (goto-char (point-min))
        (emacsvox-speak-line)))))

;;; Hook:
(add-hook
 'Info-mode-hook
 'emacsvox-pronounce-toggle-dictionaries)

;;;  keymaps

(cl-declaim (special Info-mode-map))
(define-key Info-mode-map "T" 'emacsvox-info-speak-header)
(define-key Info-mode-map "'" 'emacsvox-speak-rest-of-buffer)
(define-key Info-mode-map "\M-n" 'emacsvox-info-next-section)
(define-key Info-mode-map "\M-p" 'emacsvox-info-previous-section)

(provide  'emacsvox-info)

;;; emacsvox-info.el ends here
