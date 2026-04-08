;;; emacsvox-selectrum.el --- SELECTRUM  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable SELECTRUM An Emacs Interface to selectrum
;; Keywords: Emacsvox,  Audio Desktop selectrum
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
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
;; MERCHANTABILITY or FITNSELECTRUM FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; SELECTRUM ==  Flexibly select from lists.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (selectrum-completion-annotation voice-annotate)
   (selectrum-completion-docsig voice-monotone)
   (selectrum-current-candidate voice-bolden)
   (selectrum-primary-highlight voice-animate)
   (selectrum-secondary-highlight voice-lighten)))

;;; Fix interactive commands:

'(
  selectrum-kill-ring-save
  selectrum-prescient-toggle-anchored
  selectrum-prescient-toggle-fuzzy
  selectrum-prescient-toggle-initialism
  selectrum-prescient-toggle-literal
  selectrum-prescient-toggle-prefix
  selectrum-prescient-toggle-regexp
  selectrum-repeat
  
  selectrum-select-from-history
  
  )

(defun ems--selectrum-select-current-candidate-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (when (and ad-return-value (stringp ad-return-value))
      (dtk-speak ad-return-value))
    (emacsvox-icon 'close-object)))

(advice-add 'selectrum-select-current-candidate :after
            #'ems--selectrum-select-current-candidate-after)

(defun ems--selectrum-submit-exact-input-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'close-object)))

(advice-add 'selectrum-submit-exact-input :after
            #'ems--selectrum-submit-exact-input-after)

(defun ems--selectrum-insert-current-candidate-around
    (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((orig (point)))
        (apply orig-fun args) (emacsvox-icon 'complete)
        (emacsvox-speak-region orig (point))))
     (t (apply orig-fun args)))
    result))

(advice-add 'selectrum-insert-current-candidate :around
            #'ems--selectrum-insert-current-candidate-around)

(cl-loop
 for f in 
 '(
   selectrum-next-page selectrum-previous-page
   selectrum-goto-beginning selectrum-goto-end)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(cl-loop
 for f in 
 '(selectrum-previous-candidate selectrum-next-candidate)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(provide 'emacsvox-selectrum)
;;;  end of file

