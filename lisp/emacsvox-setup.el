;;; emacsvox-setup.el --- Setup Emacsvox -- -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  File for setting up and starting Emacsvox
;; Keywords: Emacsvox, Setup, Spoken Output
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

;;; Commentary:
;; Entry point for Emacsvox.
;; The simplest and most basic way to start emacsvox is:
;; emacs -q -l <emacsvox-dir>/lisp/emacsvox-setup.el
;; The above starts a vanilla Emacs with just Emacsvox loaded.
;; Once the above has been verified to work,
;; You can  add
;; (load-library "emacsvox-setup")
;; To your .emacs file.
;; See tvr/emacs-startup.el in the Emacsvox Git repository for  my setup.

;;; Code:

;;; Load-path:
(eval-when-compile (require 'cl-lib))
(cl-pushnew (file-name-directory load-file-name) load-path :test #'string=)
(require 'emacsvox-preamble)

;; load and start emacsvox if interactive
(require 'emacsvox)
(unless noninteractive
  (let ((file-name-handler-alist nil)
        (load-source-file-function nil))
    (load  "emacsvox-loaddefs")
    (emacsvox)))

(provide 'emacsvox-setup)

;; mode: emacs-lisp

