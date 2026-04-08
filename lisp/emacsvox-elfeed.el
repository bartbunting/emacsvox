;;; emacsvox-elfeed.el --- Speech-enable ELFEED -*- lexical-binding: t; -*-
;; $Id: emacsvox-elfeed.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ELFEED A Feed Reader For Emacs
;; Keywords: Emacsvox,  Audio Desktop elfeed, Feed Reader
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
;; MERCHANTABILITY or FITNELFEED FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ELFEED ==  Feed Reader for Emacs.
;; Install from elpa
;; M-x package-install  elfeed

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-we)
(require 'elfeed "elfeed" 'no-error)

;;;  Map Faces to voices

(voice-setup-add-map
 '(
   (elfeed-search-date-face  voice-smoothen)
   (elfeed-search-title-face voice-lighten)
   (elfeed-search-unread-title-face voice-bolden)
   (elfeed-search-feed-face voice-animate)
   (elfeed-search-tag-face voice-lighten)))

;;;  Advice interactive commands:

(cl-loop
 for f in
 '(
   elfeed-apply-hooks-now elfeed-search-browse-url
   elfeed-show-entry elfeed-show-visit
   elfeed-update-feed elfeed-update elfeed-show-refresh
   elfeed-search-update--force elfeed-search-update
   elfeed-search-untag-all-unread
   elfeed-search-untag-all elfeed-search-tag-all-unread elfeed-search-tag-all
   elfeed-load-opml elfeed-export-opml
   elfeed-db-compact elfeed-add-feed
   )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(elfeed-show-tag elfeed-show-untag)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(
   elfeed-show-entry elfeed-ssearch-show-entry
   )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(
   elfeed-show-add-enclosure-to-playlist elfeed-show-play-enclosure
   )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)))))

(defun ems--elfeed-after (&rest _)
  "Emacsvox setup."
  (when (ems-interactive-p) (emacsvox-icon 'open-object)))

(advice-add 'elfeed :after #'ems--elfeed-after)

(cl-loop
 for f in
 '(elfeed-kill-buffer  elfeed-search-quit-window)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act  comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'close-object)
       (emacsvox-speak-mode-line)))))

(defun ems--elfeed-search-yank-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'yank-object)))

(advice-add 'elfeed-search-yank :after #'ems--elfeed-search-yank-after)

;;;  Helpers:

(defun emacsvox-elfeed-entry-at-point ()
  "Return entry at point."
  
  (let ((index  (- (line-number-at-pos (point)) elfeed-search--offset)))
    (cond
     ((>= index 0) (nth index elfeed-search-entries))
     (t (error "No entry at point.")))))

(defun emacsvox-elfeed-speak-entry-at-point ()
  "Speak entry at point."
  (interactive)
  (let* ((e (emacsvox-elfeed-entry-at-point))
         (title (and e (elfeed-entry-title e)))
         (tags (and e (elfeed-entry-tags e))))
    (unless e (message "No entry here"))
    (when title
      (dtk-speak (propertize title 'personality voice-brighten))
      (when (memq 'read tags)
        (emacsvox-icon 'modified-object))
      (when (memq 'seen  tags)
        (emacsvox-icon 'mark-object))
      (emacsvox-icon 'item)
      (elfeed-tag e 'seen))))

;;;  Define additional interactive commands:

(defun emacsvox-elfeed-next-entry ()
  "Move to next entry and speak it."
  (interactive)
  (forward-line 1)
  (emacsvox-elfeed-speak-entry-at-point))

(defun emacsvox-elfeed-previous-entry ()
  "Move to previous entry and speak it."
  (interactive)
  (forward-line -1)
  (emacsvox-elfeed-speak-entry-at-point))

(defun emacsvox-elfeed-filter-entry-at-point ()
  "Display current article after filtering."
  (interactive)
  
  (let* ((entry (emacsvox-elfeed-entry-at-point))
         (link(elfeed-entry-link entry)))
    (when (string=  "" emacsvox-we-recent-xpath-filter)
      (setq emacsvox-we-recent-xpath-filter "//p"))
    (cond
     (entry (elfeed-untag  entry 'unread)
            (emacsvox-we-xslt-filter
             emacsvox-we-recent-xpath-filter link 'speak))
     (t (message "No link under point.")))))

(defun emacsvox-elfeed-eww-entry-at-point ()
  "Display current article in EWW."
  (interactive)
  (let* ((entry (emacsvox-elfeed-entry-at-point))
         (link(elfeed-entry-link entry)))
    (cond
     (entry (elfeed-untag  entry 'unread)
            (eww link))
     (t (message "No link under point.")))))

;;;  Silence warnings/errors
(cl-loop
 for f in
 '(elfeed-update-feed elfeed-handle-parse-error  elfeed-handle-http-error
                      elfeed-unjam elfeed-update)
 do
 (eval
  `(defadvice  ,f (around emacsvox pre act comp)
     "Silence messages and errors."
     (ems-with-errors-silenced ad-do-it))))

;;;  Set things up

(defun ems--elfeed-search-mode-after (&rest _)
  "Set up Emacsvox commands."
  
  (setq goal-column 11)
  (define-key elfeed-search-mode-map "n" 'emacsvox-elfeed-next-entry)
  (define-key elfeed-search-mode-map "p"
              'emacsvox-elfeed-previous-entry)
  (define-key elfeed-search-mode-map "."
              'emacsvox-elfeed-filter-entry-at-point)
  (define-key elfeed-search-mode-map [right]
              'emacsvox-elfeed-filter-entry-at-point)
  (define-key elfeed-search-mode-map "e"
              'emacsvox-elfeed-eww-entry-at-point)
  (define-key elfeed-search-mode-map " "
              'emacsvox-elfeed-speak-entry-at-point))

(advice-add 'elfeed-search-mode :after #'ems--elfeed-search-mode-after)

(provide 'emacsvox-elfeed)
;;;  end of file

