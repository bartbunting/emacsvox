;;; emacspeak-texinfo.el --- Speech enable texinfo -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description:  Emacspeak extension to speech enable
;; texinfo mode
;; Keywords: Emacspeak, texinfo
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacspeak
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;   Required modules: 
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;; Commentary:

;; This module speech enables net-texinfo mode

;;; Code:

;;;  voice locking

(defun emacspeak-texinfo-mode-hook ()
  "Setup Emacspeak extensions"
  (cl-declare (special dtk-split-caps))
  (dtk-set-punctuations 'all)
  (or dtk-split-caps
      (dtk-toggle-split-caps))
  (or emacspeak-audio-indentation
      (emacspeak-toggle-audio-indentation)))

(add-hook 'texinfo-mode-hook 'emacspeak-texinfo-mode-hook)

;;;  advice


(defun ems--texinfo-insert-@end-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (emacspeak-speak-line)))


(advice-add 'texinfo-insert-@end :after
	    #'ems--texinfo-insert-@end-after)





(defun ems--TeXinfo-insert-environment-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'TeXinfo-insert-environment :after
	    #'ems--TeXinfo-insert-environment-after)





(defun ems--texinfo-insert-@item-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'item) (emacspeak-speak-line)))


(advice-add 'texinfo-insert-@item :after
	    #'ems--texinfo-insert-@item-after)





(defun ems--texinfo-insert-@node-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'open-object) (emacspeak-speak-line)))


(advice-add 'texinfo-insert-@node :after
	    #'ems--texinfo-insert-@node-after)




(provide 'emacspeak-texinfo)
;;;  end of file 

