;;; emacsvox-eglot.el --- Speech-enable EGLOT  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable EGLOT An Emacs Interface to eglot
;; Keywords: Emacsvox,  Audio Desktop eglot
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
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
;; MERCHANTABILITY or FITNEGLOT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EGLOT ==  LSP Support for emacs

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'eglot)
(require 'eldoc)
(defvar eldoc--doc-buffer)
(defvar eglot--managed-mode)

;;;  Map Faces:

(voice-setup-add-map 
 '((eglot-mode-line voice-lighten)))

;;;  Interactive Commands:

(defun emacsvox--advice-eldoc-doc-buffer-after (&rest _)
  "Speak documentation displayed from an Eglot-managed buffer."
  (when (and (ems-interactive-p 'eldoc-doc-buffer)
             (bound-and-true-p eglot--managed-mode)
             (buffer-live-p eldoc--doc-buffer))
    (emacsvox-icon 'help)
    (with-current-buffer eldoc--doc-buffer
      (emacsvox-speak-buffer))))

(advice-add 'eldoc-doc-buffer :after
            #'emacsvox--advice-eldoc-doc-buffer-after)

(cl-loop
 for target in
 '(eglot-find-declaration
   eglot-find-implementation
   eglot-find-typeDefinition)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive Eglot navigation command."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-line)
         (emacsvox-icon 'large-movement)))
     (advice-add ',target :after #',function))))

(provide 'emacsvox-eglot)
;;;  end of file
