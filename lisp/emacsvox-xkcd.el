;;; emacsvox-xkcd.el --- Speech-enable XKCD  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop xkcd
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
;; XKCD ==  XKCD In Emacs
;; View XKCD comics in Emacs.
;; Speech enables package xkcd
;; Augments it by displaying the alt text and the transcript.

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'json)
(require 'xkcd "xkcd" 'no-error)

;;;  Fix error when loading images on the console:

(defun emacsvox--advice-xkcd-insert-image-around (orig-fun &rest args)
  "Call ORIG-FUN with ARGS when running in a graphical display."
  (cond ((not window-system) t) (t (apply orig-fun args))))

(defun emacsvox--advice-xkcd-kill-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'xkcd-kill-buffer)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(defvar xkcd-transcript nil
  "Cache current transcript.")
;; Cache transcript.
;; Content downloaded by the time this is called.
(defun emacsvox-xkcd-get-current-transcript ()
  "Cache current transcript."
  
  (setq 
   xkcd-transcript 
   (cdr 
    (assoc 'transcript (json-read-from-string (xkcd-get-json "" xkcd-cur))))))

(defun emacsvox--advice-xkcd-get-after (&rest _)
  "Insert cached transcript in xkcd-transcript."
  (let ((inhibit-read-only t))
    (emacsvox-xkcd-get-current-transcript) (goto-char (point-max))
    (insert xkcd-alt) (insert "\n")
    (insert
     (format "Transcript: %s"
             (if (zerop (length xkcd-transcript)) "Not available yet."
               xkcd-transcript)))
    (goto-char (point-min)) (emacsvox-icon 'open-object)
    (emacsvox-speak-buffer)))

;;;  Advice browse-url-default-browser:

(defun emacsvox--advice-browse-url-default-browser-around
    (_orig-fun url &rest _args)
  "Use Emacs browser --- rather than an external browser."
  (eww-browse-url url))

(defconst emacsvox-xkcd--advice
  '((xkcd-insert-image :around
     emacsvox--advice-xkcd-insert-image-around)
    (xkcd-kill-buffer :after
     emacsvox--advice-xkcd-kill-buffer-after)
    (xkcd-get :after emacsvox--advice-xkcd-get-after)
    (browse-url-default-browser :around
     emacsvox--advice-browse-url-default-browser-around))
  "Current XKCD targets and their native advice functions.")

(defun emacsvox-xkcd--install-advice ()
  "Install native advice for XKCD and URL features loaded so far."
  (dolist (entry emacsvox-xkcd--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(xkcd browse-url))
  (eval `(with-eval-after-load ',feature
           (emacsvox-xkcd--install-advice))))

(emacsvox-xkcd--install-advice)

(defun emacsvox-xkcd-open-explanation-browser ()
  "Open explanation of current xkcd in default browser"
  (interactive)
  
  (browse-url (concat "http://www.explainxkcd.com/wiki/index.php/"
                      (number-to-string xkcd-cur))))
(when (boundp 'xkcd-mode-map)
  (define-key xkcd-mode-map "e" 'emacsvox-xkcd-open-explanation-browser))
(provide 'emacsvox-xkcd)

;;; emacsvox-xkcd.el ends here
