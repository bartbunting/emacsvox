;;; emacsvox-elpher.el --- Speech-enable ELPHER  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ELPHER An Emacs Interface to elpher
;; Keywords: Emacsvox,  Audio Desktop elpher
;;;   LCD Archive entry:men

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
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
;; MERCHANTABILITY or FITNELPHER FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ELPHER ==  gopher/gemini client 
;; Let's see if we can rescue the Content-Oriented Web 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (elpher-binary voice-monotone)
   (elpher-gemini voice-animate-extra)
   (elpher-gemini-heading1 voice-lighten)
   (elpher-gemini-heading2 voice-brighten)
   (elpher-gemini-heading3 voice-smoothen)
   (elpher-gemini-preformatted voice-monotone)
   (elpher-html voice-bolden)
   (elpher-image voice-annotate)
   (elpher-index voice-lighten)
   (elpher-info voice-monotone)
   (elpher-margin-brackets voice-annotate)
   (elpher-margin-key voice-lighten)
   (elpher-other-url voice-smoothen-extra)
   (elpher-search voice-bolden)
   (elpher-telnet voice-smoothen-extra)
   (elpher-text voice-monotone)
   (elpher-unknown voice-annotate)))

;;;  Interactive Commands:

'(
  elpher-bookmark-current elpher-bookmark-link elpher-bookmarks
  elpher-copy-current-url elpher-copy-link-url
  elpher-download
  elpher-download-current
  elpher-info-current
  elpher-info-link

  elpher-set-gopher-coding-system
  elpher-toggle-tls
  elpher-unbookmark-current
  elpher-unbookmark-link
  elpher-view-raw
  )

(defconst emacsvox-elpher--open-targets
  '(elpher-back elpher-back-to-start elpher elpher-root-dir
    elpher-follow-current-link elpher-jump
    elpher-go elpher-go-current elpher-reload)
  "Elpher commands that display a page.")

(cl-loop
 for target in emacsvox-elpher--open-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s' displays a page." target)
     (when (ems-interactive-p ',target)
       (emacsvox-speak-mode-line)
       (emacsvox-icon 'open-object)))))

(defconst emacsvox-elpher--movement-targets
  '(elpher-prev-link elpher-next-link)
  "Elpher link navigation commands.")

(cl-loop
 for target in emacsvox-elpher--movement-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak the link selected by `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)
       (tts-speak
        (car (get-text-property (point) 'elpher-page)))))))

(defconst emacsvox-elpher--advice-targets
  (append emacsvox-elpher--open-targets
          emacsvox-elpher--movement-targets)
  "Current Elpher targets that receive native after advice.")

(defun emacsvox-elpher--install-advice ()
  "Install native advice after the optional Elpher package loads."
  (dolist (target emacsvox-elpher--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'elpher
  (emacsvox-elpher--install-advice))

(provide 'emacsvox-elpher)
;;;  end of file
