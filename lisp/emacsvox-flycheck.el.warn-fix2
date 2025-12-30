;;; emacsvox-flycheck.el --- Speech-enable FLYCHECK -*- lexical-binding: t; -*-
;; $Id: emacsvox-flycheck.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable FLYCHECK An Emacs Interface to flycheck
;; Keywords: Emacsvox,  Audio Desktop flycheck
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

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
;; MERCHANTABILITY or FITNFLYCHECK FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; FLYCHECK == On-the-fly checking.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Map faces

(voice-setup-add-map
 '(
   (flycheck-warning voice-animate)
   (flycheck-error voice-bolden)
   (flycheck-info voice-monotone-extra)
   (flycheck-error-list-highlight-at-point voice-bolden-extra)
   (flycheck-error-list-highlight voice-bolden-medium)
   (flycheck-error-list-line-number voice-lighten)
   (flycheck-error-list-info voice-monotone-extra)
   (flycheck-error-list-warning voice-animate)
   (flycheck-error-list-error voice-bolden)))

;;;  Advice interactive commands.

(cl-loop
 for  f in
 '(flycheck-next-error flycheck-previous-error flycheck-first-error)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))


(defun ems--flycheck-list-errors-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done)
    (dtk-speak "Displayed error listing in other window.")))


(advice-add 'flycheck-list-errors :after
	    #'ems--flycheck-list-errors-after)





(defun ems--flycheck-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Checking buffer.")))


(advice-add 'flycheck-buffer :after #'ems--flycheck-buffer-after)





(defun ems--flycheck-clear-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Cleared errors")))


(advice-add 'flycheck-clear :after #'ems--flycheck-clear-after)





(defun ems--flycheck-compile-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Compiling buffer")))


(advice-add 'flycheck-compile :after #'ems--flycheck-compile-after)





(defun ems--flycheck-error-list-refresh-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (dtk-speak "Refreshed errors")))


(advice-add 'flycheck-error-list-refresh :after
	    #'ems--flycheck-error-list-refresh-after)




(provide 'emacsvox-flycheck)
;;; emacsvox-flycheck ends here
;;;  end of file

