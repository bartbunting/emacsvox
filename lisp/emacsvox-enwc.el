;;; emacsvox-enwc.el --- Speech-enable ENWC  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Keywords: Emacsvox,  Audio Desktop enwc
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;; ENWC ==  Emacs Network Client
;; Work easily with NM and friends.
;;; Code:

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (enwc-connected voice-bolden)
   (enwc-header voice-lighten)))

;;;  Interactive Commands:

'(
  enwc-disable-auto-scan
  enwc-disable-display-mode-line
  enwc-disconnect-network
  enwc-enable-auto-scan
  enwc-enable-display-mode-line
  enwc-find-network
  enwc-load-backend
  enwc-mode
  enwc-redisplay-networks
  enwc-restart-auto-scan
  enwc-scan
  enwc-toggle-auto-scan
  enwc-toggle-display-mode-line
  enwc-toggle-wired
  )

(defun emacsvox--advice-enwc-after (&rest _)
  "Speak after opening ENWC."
  (when (ems-interactive-p 'enwc)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defconst emacsvox-enwc--connection-targets
  '(enwc-connect-to-network-at-point enwc-connect-to-network
    enwc-connect-to-network-essid)
  "ENWC commands that connect to a network.")

(cl-loop
 for target in emacsvox-enwc--connection-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Provide feedback after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)))))

(defconst emacsvox-enwc--advice-targets
  (cons 'enwc emacsvox-enwc--connection-targets)
  "Current ENWC targets that receive native after advice.")

(defun emacsvox-enwc--install-advice ()
  "Install native advice after the optional ENWC package loads."
  (dolist (target emacsvox-enwc--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'enwc
  (emacsvox-enwc--install-advice))

(provide 'emacsvox-enwc)
;;;  end of file
