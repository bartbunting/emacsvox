;;; emacsvox-shx.el --- Speech-enable SHX  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable SHX An Emacs Interface to shx
;; Keywords: Emacsvox,  Audio Desktop shx
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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
;; MERCHANTABILITY or FITNSHX FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; SHX ==  Shell Extras For emacs

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Forward Declaration 
(declare-function shx-insert "shx" (&rest args))

;;;  Interactive Commands:

(defun ems--shx-after (&rest _)
  "Announce switching to shell mode.\nProvide an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'shx :after #'ems--shx-after)

(defun ems--shx-send-input-after (&rest _)
  "Flush any ongoing speech." (when (ems-interactive-p) (dtk-stop)))

(advice-add 'shx-send-input :after #'ems--shx-send-input-after)

(defun ems--shx-send-input-or-copy-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'shx-send-input-or-copy-line :after
            #'ems--shx-send-input-or-copy-line-after)

(defun ems--shx--turn-on-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'on) (message "Turned on shx")))

(advice-add 'shx--turn-on :after #'ems--shx--turn-on-after)

(defun ems--shx-send-input-or-open-thing-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (unless (eq major-mode 'shell-mode)
      (emacsvox-speak-line) (emacsvox-icon 'open-object))))

(advice-add 'shx-send-input-or-open-thing :after
            #'ems--shx-send-input-or-open-thing-after)

(defun ems--shx-global-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Turned %s shx globally" (if shx-global-mode "on" "off"))
    (emacsvox-icon (if shx-global-mode 'on 'off))))

(advice-add 'shx-global-mode :after #'ems--shx-global-mode-after)

(defun ems--shx-magic-insert-around (orig-fun &rest args)
  "Speak word or completion."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (ems-with-messages-silenced
       (let ((orig (point)) (count (ad-get-arg 0)))
         (setq count (or count 1)) (apply orig-fun args)
         (cond
          ((= (point) (+ count orig))
           (save-excursion (forward-word -1) (emacsvox-speak-word)))
          (t (emacsvox-icon 'complete)
             (emacsvox-speak-region (comint-line-beginning-position)
                                    (point)))))))
     (t (apply orig-fun args)))
    result))

(advice-add 'shx-magic-insert :around #'ems--shx-magic-insert-around)

;;;  Additional shx commands:

(defun shx-cmd-browse (url)
  "Browse the supplied URL."
  (shx-insert "Browsing " 'font-lock-keyword-face url "\n")
  (browse-url url))

(defun shx-cmd-grep (grep-args)
  "Run grep with `grep-args'."
  (shx-insert "grep " 'font-lock-keyword-face grep-args "\n")
  (grep (concat "grep --color -nH -e " grep-args)))

(provide 'emacsvox-shx)
;;;  end of file

