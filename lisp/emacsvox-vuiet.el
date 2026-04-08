;;; emacsvox-vuiet.el --- Speech-enable VUIET  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable VUIET An Emacs Interface to vuiet
;; Keywords: Emacsvox,  Audio Desktop vuiet
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNVUIET FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; VUIET ==  Emacs Music Explorer And Player with last.fm integration
;; This module speech-enables vuiet.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defun ems--vuiet-stop-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))

(advice-add 'vuiet-stop :after #'ems--vuiet-stop-after)

(defun ems--vuiet-love-track-after (&rest _)
  "speak." (when (ems-interactive-p) (dtk-notify "loved track")))

(advice-add 'vuiet-love-track :after #'ems--vuiet-love-track-after)

(defun ems--vuiet-unlove-track-after (&rest _)
  "speak." (when (ems-interactive-p) (dtk-notify "UnLoved track")))

(advice-add 'vuiet-unlove-track :after #'ems--vuiet-unlove-track-after)

(cl-loop
 for f in 
 '(
   vuiet-playing-track-lyrics vuiet-loved-tracks-info
   vuiet-playing-artist-info vuiet-playing-artist-lastfm-page
   vuiet-album-info-search vuiet-artist-info
   vuiet-artist-info-search vuiet-artist-lastfm-page)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in 
 '(vuiet-disable-scrobbling vuiet-enable-scrobbling)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon
        (if vuiet-scrobble-enabled 'on 'off))
       (dtk-speak (format "Turned %s scrobbling"
                          (if vuiet-scrobble-enabled "on" "off")))))))

(cl-loop
 for f in 
 '(vuiet-player-volume-inc vuiet-player-volume-dec)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-notify
        (format "Volume %s" (vuiet-player-volume)))))))

;;; Additional Commands:
(defun emacsvox-vuiet-track-info ()
  "Speak current playing state."
  (interactive)
  
  (cond
   ((null mode-line-misc-info)
    (dtk-notify "Nothing playing on vuiet?") )
   (t
    (dtk-notify (mapconcat #'identity mode-line-misc-info " ")))))

(provide 'emacsvox-vuiet)
;;;  end of file

