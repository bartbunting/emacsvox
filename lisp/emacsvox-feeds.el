;;; emacsvox-feeds.el --- Atom, RSS -*- lexical-binding: t; -*-
;; $Id:$
;; $Author: tv.raman.tv $
;; Description:  Emacsvox Feeds Support
;; Keywords: Emacsvox, RSS, Atom
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4634 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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


;;; Commentary:
;; This module provides Feeds support for Emacsvox

;;  required modules

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-feeds)
(defvar emacsvox-feeds-archive-file)
(eval-when-compile (require 'cl-lib))
(require 'cl-extra)
(require 'emacsvox-preamble)
(require 'emacsvox-xslt)
(require 'url)
(require 'eww)
(require 'browse-url)

;;;   feed cache

(defgroup emacsvox-feeds nil
  "RSS Feeds for the Emacsvox desktop."
  :group 'emacsvox)

(defvar emacsvox-feeds-feeds-table (make-hash-table :test #'equal)
  "Hash table to enable efficient feed look up when adding feeds.")

(defun emacsvox-feeds-cache-feeds (&optional feeds)
  "Cache feeds in  `feeds' in a hash table."
  
  (or feeds (setq feeds emacsvox-feeds))
  (cl-loop
   for f in feeds
   do
   (set-text-properties 0 (length (cl-second f)) nil (cl-second f))
   (puthash
    (cl-second f)                       ; URL is the key
    f emacsvox-feeds-feeds-table)))

(defcustom emacsvox-feeds
  '(
    ("Wired News" "http://www.wired.com/news_drop/netcenter/netcenter.rdf"  rss)
    ("BBC Podcast Directory" "http://www.bbc.co.uk/podcasts.opml" opml)
    ("CNet Tech News"  "http://feeds.feedburner.com/cnet/tcoc"  rss)
    )
  "Table of RSS/Atom feeds.
The feed list is persisted to file saved-feeds on exit."
  :type
  '(repeat
    (list :tag "Feed"
          (string :tag "Title")
          (string :tag "URI")
          (choice
           :tag "Type"
           (const :tag "RSS" rss)
           (const :tag "opml" opml)
           (const :tag "Atom" atom))))
  :initialize  'custom-initialize-reset
  :set
  #'(lambda (sym val)
      (set-default
       sym
       (sort
        val
        #'(lambda (a b)
            (string-lessp
             (downcase (string-trim (cl-first a)))
             (downcase (string-trim (cl-first b)))))))
      (setq emacsvox-feeds-feeds-table (make-hash-table :test #'equal))
      (emacsvox-feeds-cache-feeds val))
  :group 'emacsvox-feeds)

(add-hook
 'kill-emacs-hook
 #'(lambda nil
     (when (bound-and-true-p emacsvox-feeds)
       (emacsvox--persist-variable
        'emacsvox-feeds
        (expand-file-name "saved-feeds"
                          emacsvox-user-directory)))))

(defun emacsvox-feeds-added-p (feed-url)
  "Check if this feed has been added before."
  
  (gethash feed-url emacsvox-feeds-feeds-table))

;;;###autoload
(defun emacsvox-feeds-add-feed (title url type)
  "Add specified feed to our feed store."
  (interactive
   (list
    (read-from-minibuffer "Title: ")
    (read-from-minibuffer "URL: ")
    (cl-ecase (read-char-exclusive "a Atom, o OPML, r RSS: ")
      (?a 'atom)
      (?o 'opml)
      (?r 'rss))))
  
  (let ((found (emacsvox-feeds-added-p url)))
    (cond
     (found (message "Feed already present  as %s" (cl-first found)))
     (t (push (list title url type) emacsvox-feeds)
        (setopt emacsvox-feeds emacsvox-feeds)
        (message "Added feed as %s" title)))))

(defun emacsvox-feeds-delete-feed (title)
  "Delete specified feed from our feed store."
  (interactive
   (list (completing-read "Delete:" (mapcar #'cl-first emacsvox-feeds))))
  
  (setq emacsvox-feeds
        (cl-remove-if
         #'(lambda (f) (string= title (cl-first f)))
         emacsvox-feeds))
  (setopt emacsvox-feeds emacsvox-feeds)
  (message "Deleted %s" title))

(defvar emacsvox-feeds-archive-file
  (expand-file-name "feeds.el" emacsvox-user-directory)
  "Feed archive.")

(defun emacsvox-feeds-archive-feeds ()
  "Archive list of subscribed fees to personal resource directory.
Archiving is useful when synchronizing feeds across multiple machines."
  (interactive)
  (let ((buffer (find-file-noselect emacsvox-feeds-archive-file))
        (print-level nil)
        (print-length nil))
    (with-current-buffer buffer
      (erase-buffer)
      (ems-with-messages-silenced (cl-prettyprint emacsvox-feeds))
      (save-buffer)
      (emacsvox-icon 'save-object)
      (message "Archived emacsvox-feeds containing %d feeds in %s"
               (length emacsvox-feeds)
               emacsvox-feeds-archive-file))))

(defun emacsvox-feeds-restore-feeds ()
  "Restore list of subscribed fees from  personal resource directory.
Archiving is useful when synchronizing feeds across multiple machines."
  (interactive)
  
  (unless (file-exists-p emacsvox-feeds-archive-file)
    (user-error "No archived feeds to restore. "))
  (with-current-buffer (find-file-noselect emacsvox-feeds-archive-file)
    (goto-char (point-min))
    (setq emacsvox-feeds (read (current-buffer))))
  (emacsvox-feeds-cache-feeds)
  (setopt emacsvox-feeds emacsvox-feeds))

(defun emacsvox-feeds-fastload-feeds ()
  "Fast load list of feeds from archive.
This directly updates emacsvox-feeds from the archive, rather
than adding those entries to the current set of subscribed
feeds."
  (interactive)
  
  (unless (file-exists-p emacsvox-feeds-archive-file)
    (error "No archived feeds to restore. "))
  (let ((buffer (find-file-noselect emacsvox-feeds-archive-file)))
    (setq emacsvox-feeds (read buffer))
    (kill-buffer buffer)
    (when
        (y-or-n-p
         (format "After restoring  we have a total of %d feeds. Save? "
                 (length emacsvox-feeds)))
      (customize-save-variable 'emacsvox-feeds emacsvox-feeds))))

;;;  display  feeds:
;;;###autoload
(defun emacsvox-feeds-feed-display(feed-url style &optional speak)
  "Fetch feed asynchronously via Emacs and display using xsltproc."
  (let ((read-process-output-max  (* 1024 1024)))
    (url-retrieve
     feed-url #'emacsvox-feeds-render
     (list feed-url  style  speak)))
  (message "pulling feed.")
  (emacsvox-icon 'item))

(defun emacsvox-feeds-render  (_status feed-url style   speak)
  "Render the result of asynchronously retrieving feed-url."
  (let ((inhibit-read-only t)
        (browse-url-browser-function  'eww-browse-url)
        (data-buffer (current-buffer))
        (coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8)
        (emacsvox-xslt-options "--nonet --novalid"))
    (with-current-buffer data-buffer
      (when speak (emacsvox-eww-autospeak))
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda ()
           (setq eww-current-url feed-url
                 emacsvox-eww-feed t
                 emacsvox-eww-style style)
           (plist-put eww-data :url feed-url)))
      (goto-char (point-min))
      (search-forward "\n\n")
      (delete-region (point-min) (point))
      (decode-coding-region (point-min) (point-max) 'utf-8)
      (emacsvox-xslt-region
       style (point-min) (point-max)
       (list (cons "base" (format "\"'%s'\"" feed-url))))
      (setq eww-current-url feed-url
            emacsvox-eww-feed t
            emacsvox-eww-style style)
      (emacsvox-xslt-without-xsl (browse-url-of-buffer)))))

;;;###autoload
(defun emacsvox-feeds-rss-display (feed-url)
  "Display RSS feed."
  (interactive (list (ems--read-url)))
  
  (emacsvox-icon 'open-object)
  (emacsvox-feeds-feed-display feed-url emacsvox-rss-xsl 'speak))

;;;###autoload
(defun emacsvox-feeds-opml-display (feed-url)
  "Display OPML feed."
  (interactive (list (ems--read-url)))
  
  (emacsvox-feeds-feed-display feed-url emacsvox-opml-xsl 'speak))

;;;###autoload
(defun emacsvox-feeds-select-feed (feed-type)
  "Prompt for feed-type (Atom, RSS, OPML and open it."
  (interactive
   (list
    (read-char "a Atom, o OPML, r RSS")))
  (cl-case feed-type
    (?a (call-interactively 'emacsvox-feeds-atom-display))
    (?o (call-interactively 'emacsvox-feeds-opml-display))
    (?r (call-interactively 'emacsvox-feeds-rss-display))
    (otherwise (keyboard-quit))))

;;;###autoload
(defun emacsvox-feeds-atom-display (feed-url)
  "Display ATOM feed."
  (interactive (list (ems--read-url)))
  
  (emacsvox-icon 'open-object)
  (emacsvox-feeds-feed-display feed-url emacsvox-atom-xsl 'speak))

;;;  Validate Feed:

;;;   view feed

;;; Helper:
(defun emacsvox-feeds-browse-feed (feed &optional speak)
  "Display specified feed.
Argument `feed' is a feed structure (label url type)."
  (let ((uri (cl-second feed))
        (type  (cl-third feed))
        (style nil))
    (setq style
          (cond
           ((eq type 'rss)emacsvox-rss-xsl)
           ((eq type 'opml) emacsvox-opml-xsl)
           ((eq type 'atom) emacsvox-atom-xsl)
           (t (error "Unknown feed type %s" type))))
    (emacsvox-feeds-feed-display uri style speak)))

;;;###autoload
(defun emacsvox-feeds-browse (feed)
  "Browse   feed."
  (interactive
   (list
    (let ((completion-ignore-case t))
      (completing-read "Feed:" emacsvox-feeds nil 'must-match))))
  (add-hook 'emacsvox-eww-post-hook
            #'(lambda nil (emacsvox-icon 'open-object)))
  (emacsvox-feeds-browse-feed (assoc feed emacsvox-feeds) 'speak))

;;;  Finding Feeds:

(define-button-type 'emacsvox-feeds-feed-button
  'follow-link t
  'action 'emacsvox-feeds-feed-button-action
  'link nil ;site url
  'url nil; site url
  )

(defun emacsvox-feeds-feed-button-action (button)
  "Open feed associated with this button."
  (let ((browse-url-browser-function  'eww-browse-url)
        (url (button-get button 'url))
        (link (button-get button 'link)))
    (cond
     ((zerop (length url)) ; missing feed url
      (browse-url link))
     ((string-match "atom" url)
      (emacsvox-feeds-atom-display url))
     ((string-match "blogspot" url)
      (emacsvox-feeds-atom-display url))
     ((string-match "rss" url)
      (emacsvox-feeds-rss-display url))
     (t (emacsvox-feeds-rss-display url)))))

(provide 'emacsvox-feeds)
;;;  end of file
