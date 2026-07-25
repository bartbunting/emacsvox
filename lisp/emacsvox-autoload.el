;;; emacsvox-autoload.el --- Autoload Generator  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  autoload Wizard for the emacsvox desktop
;; Keywords: Emacsvox,  Audio Desktop autoload
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;  Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman Copyright
;;(c) 1994, 1995 by Digital Equipment Corporation.  All Rights
;;Reserved.  This file is not part of GNU Emacs, but the same
;;permissions apply.  GNU Emacs is free software; you can redistribute
;;it and/or modify it under the terms of the GNU General Public
;;License as published by the Free Software Foundation; either version
;;2, or (at your option) any later version.  GNU Emacs is distributed
;;in the hope that it will be useful, but WITHOUT ANY WARRANTY;
;;without even the implied warranty of MERCHANTABILITY or FITNESS FOR
;;A PARTICULAR PURPOSE.  See the GNU General Public License for more
;;details.  You should have received a copy of the GNU General Public
;;License along with GNU Emacs; see the file COPYING.  If not, write
;;to the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;;Boston,MA 02110-1301, USA.


;;; Commentary:
;; generate autoloads for emacsvox
;;; Code:

(require 'loaddefs-gen)

(defvar emacsvox-auto-autoloads-file
  (expand-file-name "emacsvox-loaddefs.el"
                    (file-name-directory load-file-name))
  "File that holds automatically generated autoloads for Emacsvox.")

(defun emacsvox-auto-generate-autoloads ()
  "Generate emacsvox autoloads."
  (loaddefs-generate
   emacsvox-lisp-directory emacsvox-auto-autoloads-file))

(provide 'emacsvox-autoload)
;;;  end of file
