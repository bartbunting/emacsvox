;;; emacsvox-texinfo.el --- Speech enable texinfo -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description:  Emacsvox extension to speech enable
;; texinfo mode
;; Keywords: Emacsvox, texinfo
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/robertmeta/emacsvox
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
(require 'emacsvox-preamble)
(require 'texinfo)

;;; Commentary:

;; This module speech enables net-texinfo mode

;;; Code:

;;;  voice locking

(defun emacsvox-texinfo-mode-hook ()
  "Setup Emacsvox extensions"
  
  (tts-set-punctuations 'all)
  (or dtk-split-caps
      (dtk-toggle-split-caps))
  (or emacsvox-audio-indentation
      (emacsvox-toggle-audio-indentation)))

(add-hook 'texinfo-mode-hook 'emacsvox-texinfo-mode-hook)

;;;  advice

(defun emacsvox--advice-texinfo-insert-@end-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-@end)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-@end :after
            #'emacsvox--advice-texinfo-insert-@end-after)

(defun emacsvox--advice-texinfo-insert-block-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-block)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-block :after
            #'emacsvox--advice-texinfo-insert-block-after)

(defun emacsvox--advice-texinfo-insert-@item-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-@item)
    (emacsvox-icon 'item) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-@item :after
            #'emacsvox--advice-texinfo-insert-@item-after)

(defun emacsvox--advice-texinfo-insert-@node-after (&rest _)
  "speak"
  (when (ems-interactive-p 'texinfo-insert-@node)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'texinfo-insert-@node :after
            #'emacsvox--advice-texinfo-insert-@node-after)

(provide 'emacsvox-texinfo)
;;;  end of file 
