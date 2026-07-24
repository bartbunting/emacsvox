;;; emacsvox-reftex.el --- speech enable reftex -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech enable
;; reftex 
;; Keywords: Emacsvox, reftex
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;;  required modules

(require 'emacsvox-preamble)

;;; Commentary:

;; This module speech-enables refteex --
;; reftex is a minor mode that makes navigation of TeX
;; documents  possible via a table of contents buffer.

;;; Code:

;;;  advice interactive commands

(defun emacsvox--advice-reftex-select-previous-heading-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-select-previous-heading)
    (emacsvox-speak-line) (emacsvox-icon 'section)))

(advice-add 'reftex-select-previous-heading :after
            #'emacsvox--advice-reftex-select-previous-heading-after)

(defun emacsvox--advice-reftex-select-next-heading-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-select-next-heading)
    (emacsvox-speak-line) (emacsvox-icon 'section)))

(advice-add 'reftex-select-next-heading :after
            #'emacsvox--advice-reftex-select-next-heading-after)

(defun emacsvox--advice-reftex-toc-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-toc-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'reftex-toc-quit :after #'emacsvox--advice-reftex-toc-quit-after)

(defun emacsvox--advice-reftex-toc-previous-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-toc-previous)
    (emacsvox-speak-line) (emacsvox-icon 'item)))

(advice-add 'reftex-toc-previous :after
            #'emacsvox--advice-reftex-toc-previous-after)

(defun emacsvox--advice-reftex-toc-next-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-toc-next)
    (emacsvox-speak-line) (emacsvox-icon 'item)))

(advice-add 'reftex-toc-next :after #'emacsvox--advice-reftex-toc-next-after)

(defun emacsvox--advice-reftex-toc-goto-line-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-toc-goto-line)
    (emacsvox-icon 'large-movement) (recenter 0)
    (cond (outline-minor-mode (emacsvox-outline-speak-this-heading))
          (t (emacsvox-speak-predefined-window 1)))))

(advice-add 'reftex-toc-goto-line :after
            #'emacsvox--advice-reftex-toc-goto-line-after)

(defun emacsvox--advice-reftex-toc-goto-line-and-hide-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-toc-goto-line-and-hide)
    (emacsvox-icon 'large-movement)
    (if outline-minor-mode (emacsvox-outline-speak-this-heading)
      (emacsvox-speak-line))))

(advice-add 'reftex-toc-goto-line-and-hide :after
            #'emacsvox--advice-reftex-toc-goto-line-and-hide-after)

(defun emacsvox--advice-reftex-toc-view-line-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-toc-view-line)
    (emacsvox-icon 'large-movement) (other-window 1) (recenter 0)
    (other-window 1) (emacsvox-speak-predefined-window 2)))

(advice-add 'reftex-toc-view-line :after
            #'emacsvox--advice-reftex-toc-view-line-after)

(defun emacsvox--advice-reftex-select-previous-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-select-previous)
    (emacsvox-speak-line) (emacsvox-icon 'item)))

(advice-add 'reftex-select-previous :after
            #'emacsvox--advice-reftex-select-previous-after)

(defun emacsvox--advice-reftex-select-next-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-select-next)
    (emacsvox-speak-line) (emacsvox-icon 'select-object)))

(advice-add 'reftex-select-next :after #'emacsvox--advice-reftex-select-next-after)

(defun emacsvox--advice-reftex-select-accept-after (&rest _)
  "Speak line where we inserted the reference."
  (when (ems-interactive-p 'reftex-select-accept)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(advice-add 'reftex-select-accept :after
            #'emacsvox--advice-reftex-select-accept-after)

(defun emacsvox--advice-reftex-toc-toggle-follow-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-toc-toggle-follow)
    (emacsvox-icon (if reftex-toc-follow-mode 'on 'off))
    (message "Turned %s follow mode. "
             (if reftex-toc-follow-mode 'on 'off))))

(advice-add 'reftex-toc-toggle-follow :after
            #'emacsvox--advice-reftex-toc-toggle-follow-after)

(defun emacsvox--advice-reftex-toc-toggle-labels-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-toc-toggle-labels)
    (emacsvox-icon (if reftex-toc-include-labels 'on 'off))
    (message "Turned %s labels. "
             (if reftex-toc-include-labels 'on 'off))))

(advice-add 'reftex-toc-toggle-labels :after
            #'emacsvox--advice-reftex-toc-toggle-labels-after)

(defun emacsvox--advice-reftex-toc-toggle-file-boundary-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-toc-toggle-file-boundary)
    (emacsvox-icon (if reftex-toc-include-file-boundaries 'on 'off))
    (message "Turned %s file boundary markers. "
             (if reftex-toc-include-file-boundaries 'on 'off))))

(advice-add 'reftex-toc-toggle-file-boundary :after
            #'emacsvox--advice-reftex-toc-toggle-file-boundary-after)

(defun emacsvox--advice-reftex-toc-toggle-context-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-toc-toggle-context)
    (emacsvox-icon (if reftex-toc-include-context 'on 'off))
    (message "Turned %s context markers. "
             (if reftex-toc-include-context 'on 'off))))

(advice-add 'reftex-toc-toggle-context :after
            #'emacsvox--advice-reftex-toc-toggle-context-after)

(defun emacsvox--advice-reftex-index-next-after (&rest _)
  "Speech enable  by speaking  entry."
  (when (ems-interactive-p 'reftex-index-next)
    (emacsvox-speak-line) (emacsvox-icon 'item)))

(advice-add 'reftex-index-next :after #'emacsvox--advice-reftex-index-next-after)

(defun emacsvox--advice-reftex-index-previous-after (&rest _)
  "Speech enable  by speaking  entry."
  (when (ems-interactive-p 'reftex-index-previous)
    (emacsvox-speak-line) (emacsvox-icon 'item)))

(advice-add 'reftex-index-previous :after
            #'emacsvox--advice-reftex-index-previous-after)

(defun emacsvox--advice-reftex-index-goto-entry-after (&rest _)
  "Speech enable  by speaking index entry."
  (when (ems-interactive-p 'reftex-index-goto-entry)
    (emacsvox-icon 'large-movement) (recenter 0)
    (cond (outline-minor-mode (emacsvox-outline-speak-this-heading))
          (t (emacsvox-speak-predefined-window 1)))))

(advice-add 'reftex-index-goto-entry :after
            #'emacsvox--advice-reftex-index-goto-entry-after)

(defun emacsvox--advice-reftex-index-goto-entry-and-hide-after (&rest _)
  "Speech enable  by speaking toc entry."
  (when (ems-interactive-p 'reftex-index-goto-entry-and-hide)
    (emacsvox-icon 'large-movement)
    (if outline-minor-mode (emacsvox-outline-speak-this-heading)
      (emacsvox-speak-line))))

(advice-add 'reftex-index-goto-entry-and-hide :after
            #'emacsvox--advice-reftex-index-goto-entry-and-hide-after)

(defun emacsvox--advice-reftex-index-view-entry-after (&rest _)
  "Speech enable  by speaking index entry."
  (when (ems-interactive-p 'reftex-index-view-entry)
    (emacsvox-icon 'large-movement) (other-window 1) (recenter 0)
    (other-window 1) (emacsvox-speak-predefined-window 2)))

(advice-add 'reftex-index-view-entry :after
            #'emacsvox--advice-reftex-index-view-entry-after)

(defun emacsvox--advice-reftex-index-toggle-follow-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-index-toggle-follow)
    (emacsvox-icon (if reftex-index-follow-mode 'on 'off))
    (message "Turned %s follow mode. "
             (if reftex-index-follow-mode 'on 'off))))

(advice-add 'reftex-index-toggle-follow :after
            #'emacsvox--advice-reftex-index-toggle-follow-after)

(defun emacsvox--advice-reftex-index-toggle-context-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-index-toggle-context)
    (emacsvox-icon (if reftex-index-include-context 'on 'off))
    (message "Turned %s context markers. "
             (if reftex-index-include-context 'on 'off))))

(advice-add 'reftex-index-toggle-context :after
            #'emacsvox--advice-reftex-index-toggle-context-after)

(defun emacsvox--advice-reftex-display-index-after (&rest _)
  "Speech enable index mode."
  (when (ems-interactive-p 'reftex-display-index)
    (emacsvox-speak-mode-line) (emacsvox-icon 'open-object)))

(advice-add 'reftex-display-index :after
            #'emacsvox--advice-reftex-display-index-after)

(defun emacsvox--advice-reftex-index-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-index-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'reftex-index-quit :after #'emacsvox--advice-reftex-index-quit-after)

(defun emacsvox--advice-reftex-index-quit-and-kill-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reftex-index-quit-and-kill)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'reftex-index-quit-and-kill :after
            #'emacsvox--advice-reftex-index-quit-and-kill-after)

;;;  highlighting 

(defun emacsvox--advice-reftex-highlight-after
    (_index begin end &optional _buffer)
  "Add  voice properties."
  (with-silent-modifications
    (put-text-property begin end 'personality voice-bolden))
  (emacsvox-speak-line)
  (sit-for 2))

(advice-add 'reftex-highlight :after #'emacsvox--advice-reftex-highlight-after)

;;;   indexing 

(provide 'emacsvox-reftex)
;;;  end of file
