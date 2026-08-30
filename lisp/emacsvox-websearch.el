;;; emacsvox-websearch.el --- search utilities  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, WWW interaction
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This module provides utility functions for searching the WWW

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-eww-masquerade)
(defvar emacsvox-google-toolbelt)
(defvar emacsvox-websearch-google-lite)


;;  required modules
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-google)
(require 'gweb)
(declare-function word-at-point "thingatpt" (&optional no-properties))
(declare-function calendar-cursor-to-date "calendar" (&optional error event))
(declare-function emacsvox-eww-autospeak "emacsvox-eww" nil)

(declare-function gweb-google-autocomplete "gweb" (&optional prompt))
(declare-function calendar-astro-date-string "cal-julian" (&optional date))
;;;###autoload
(define-prefix-command 'emacsvox-websearch)
(cl-declaim (special emacsvox-websearch))

(cl-loop
 for b in
 '(
   ("C-a"       emacsvox-websearch-amazon-search)
   ("SPC"       emacsvox-websearch-google-feeling-lucky)
   ("?"         emacsvox-websearch-help)
   ("G"         emacsvox-websearch-gutenberg)
   ("a"         emacsvox-websearch-google-lite)
   ("f"         emacsvox-websearch-foldoc-search)
   ("g"         emacsvox-websearch-google)
   ("i"         emacsvox-websearch-google-with-toolbelt)
   ("j"         emacsvox-websearch-ask-jeeves)
   ("n"         emacsvox-websearch-google-news)
   ("u"         emacsvox-websearch-web-filter-google)
   ("w"         emacsvox-websearch-wikipedia-search)
   ("y"         emacsvox-websearch-youtube-search))
 do
 (emacsvox-keymap-update emacsvox-websearch b ))

(defun emacsvox-websearch-help ()
  "Displays key mapping used by Emacsvox Websearch."
  (interactive)
  (funcall-interactively 'describe-bindings (kbd "C-e /") ))

;;;  helpers to read the query

(defvar ems--ws-history nil
  "Holds history of search queries.")

(defsubst emacsvox-websearch-read (prompt)
  "Read search query"
  (let ((q (read-from-minibuffer prompt nil  nil nil 'ems--ws-history )))
    (cl-pushnew q  ems--ws-history :test #'string=)
    q))

;;; post-processor
(defun emacsvox-websearch-post (locator speaker &rest args)
  "Set up post processing steps on a result page.
LOCATOR is a string to search for in the results page.
SPEAKER is a function to call to speak relevant information.
ARGS specifies additional arguments to SPEAKER if any."
  
  (add-hook
   'emacsvox-eww-post-hook
   (eval
    `#'(lambda nil
         (let ((inhibit-read-only t))
           (condition-case nil
               (cond
                ((search-forward ,locator nil t)
                 (recenter 0)
                 (apply(quote ,speaker) ,args))
                (t (message "Your search appears to have failed.")))
             (error nil)))))
   'at-end))

;;;  FolDoc

(defun emacsvox-websearch-foldoc-search (query)
  "Perform a FolDoc search. "
  (interactive (list (emacsvox-websearch-read "Computing Dict: ")))
  (browse-url
   (concat
    "http://foldoc.org/"
    (url-hexify-string query)))
  (emacsvox-websearch-post query 'emacsvox-speak-line))

;;;  Gutenberg

(defun emacsvox-websearch-gutenberg (type query)
  "Perform an Gutenberg search"
  (interactive
   (list
    (read-char "Author a, Title t")
    (emacsvox-websearch-read "Gutenberg query: ")))
  (browse-url
   (concat
    "http://digital.library.upenn.edu/webbin/book/search?"
    (cl-ecase type
      (?a "author=")
      (?t "title="))
    (url-hexify-string query)))
  (emacsvox-websearch-post query 'emacsvox-speak-line))

;;;  google

(defvar emacsvox-websearch-google-uri
  "https://www.google.com/search?q="
  "Base  URI for Google search")

(defvar emacsvox-websearch-google-options nil
  "Additional options to pass to Google e.g. &xx=yy...")

(declare-function emacsvox-eww-next-h "emacsvox-eww" (&optional speak))
(declare-function emacsvox-eww-next-h1 "emacsvox-eww" (&optional speak))

(defun emacsvox-websearch-google (query &optional flag)
  "Perform a Google search.  First optional interactive prefix arg
`flag' prompts for additional search options. Second interactive
prefix arg is equivalent to hitting the I'm Feeling Lucky button on Google. "
  (interactive (list (gweb-google-autocomplete) current-prefix-arg))
  (setq emacsvox-google-toolbelt nil)
  (let ((toolbelt (emacsvox-google-toolbelt))
        (search-url nil)
        (add-toolbelt (and flag  (consp flag) (= 4 (car flag))))
        (lucky (and flag  (consp flag) (= 16 (car flag)))))
    (emacsvox-google-cache-query query)
    (emacsvox-google-cache-toolbelt toolbelt)
    (setq search-url
          (concat
           emacsvox-websearch-google-uri query
           (format "&num=25%s"          ; accumulate options
                   (or emacsvox-websearch-google-options ""))
           (when lucky
             (concat
              "&btnI="
              (url-hexify-string "I'm Feeling Lucky")))))
    (cond
     (add-toolbelt (emacsvox-google-toolbelt-change))
     (lucky
      (emacsvox-eww-autospeak)
      (browse-url search-url))
     (t                                 ; always just show results
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda ()
           (goto-char (point-min))
           (emacsvox-eww-next-h)
           (tts-stop)
           (emacsvox-eww-next-h)
           (emacsvox-speak-windowful))
       'at-end)
      (emacsvox-we-extract-by-id-list
       ems--google-filter
       search-url)))))

(defvar emacsvox-websearch-google-lite
  "https://www.google.com/search?num=25&lite=90586&q=%s"
  "Using Google Lite.")

(defun emacsvox-websearch-google-lite(query &optional options)
  "Use Google Lite.
Optional prefix arg prompts for toolbelt options."
  (interactive (list (gweb-google-autocomplete "Q: ") current-prefix-arg))
  (setq emacsvox-google-toolbelt nil)
  (let ((emacsvox-eww-masquerade t)
        (toolbelt (emacsvox-google-toolbelt)))
    (emacsvox-google-cache-query query)
    (emacsvox-google-cache-toolbelt toolbelt)
    (cond
     (options (emacsvox-google-toolbelt-change))
     (t
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda ()
           (goto-char (point-min))
           (emacsvox-eww-next-h)
           (search-forward "Search Tools" nil t)
           (tts-stop)
           (emacsvox-eww-next-h)
           (emacsvox-speak-windowful)))
      (emacsvox-we-extract-by-id-list
       ems--google-filter
       (format emacsvox-websearch-google-lite query))))))

(defvar emacsvox-websearch-wf-google
  "https://www.google.com/search?num=25&lite=90586&udm=14&q=%s"
  "Using Google Lite with Web Filter turned on.")

(defun emacsvox-websearch-web-filter-google (query &optional options)
  "Use Google Lite with Web filter.
Optional prefix arg prompts for toolbelt options."
  (interactive
   (list (gweb-google-autocomplete "WFGoogle: ") current-prefix-arg))
  (setq emacsvox-google-toolbelt nil)
  (let ((emacsvox-eww-masquerade t)
        (toolbelt (emacsvox-google-toolbelt)))
    (emacsvox-google-cache-query query)
    (emacsvox-google-cache-toolbelt toolbelt)
    (cond
     (options (emacsvox-google-toolbelt-change))
     (t
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda ()
           (goto-char (point-min))
           (emacsvox-eww-next-h) (search-forward "Search Tools" nil
                                                 t)
           (tts-stop)
           (emacsvox-eww-next-h)
           (emacsvox-speak-windowful)))
      (emacsvox-we-extract-by-id-list
       ems--google-filter
       (format emacsvox-websearch-wf-google query))))))

(defun emacsvox-websearch-google-with-toolbelt (query)
  "Launch Google search with toolbelt."
  (interactive (list (gweb-google-autocomplete "IGoogle: ")))
  (emacsvox-websearch-google-lite query 'use-toolbelt))

(defun emacsvox-websearch-google-feeling-lucky (query)
  "Do a I'm Feeling Lucky Google search."
  (interactive
   (list
    (gweb-google-autocomplete "Google Lucky Search: ")))
  (emacsvox-websearch-google query '(16)))

(defun emacsvox-websearch-google-search-in-date-range ()
  "Use this from inside the calendar to do Google date-range searches."
  (interactive)
  
  (let ((query (emacsvox-websearch-read "Google for: "))
        (from (read (calendar-astro-date-string (calendar-cursor-to-date t))))
        (to
         (read
          (calendar-astro-date-string
           (or (car calendar-mark-ring)
               (error "No mark set"))))))
    (emacsvox-websearch-google
     (concat
      (url-hexify-string query)
      (format "+daterange:%s-%s"
              (min from to)
              (max from to))))))

(when (featurep 'calendar)
  (cl-declaim (special calendar-mode-map))
  (define-key calendar-mode-map "gg"
              'emacsvox-websearch-google-search-in-date-range))

;;;  Google News

(defun emacsvox-websearch-google-news ()
  "Invoke Google News url template."
  (interactive)
  (let ((name "Google News Search"))
    (emacsvox-url-template-open (emacsvox-url-template-get name))))

;;;   Ask Jeeves

(defun emacsvox-websearch-ask-jeeves (query)
  "Ask Jeeves for the answer."
  (interactive (list (emacsvox-websearch-read "Ask Jeeves for: ")))
  (browse-url
   (concat
    "http://www.ask.com/web?qsrc=0&o=0&ASKDSBHO=0&q="
    (url-hexify-string query)))
  (emacsvox-websearch-post query 'emacsvox-speak-line))

;;;  wikipedia

(defun emacsvox-websearch-wikipedia-search (query)
  "Search Wikipedia using Google.
Use URL Template `wikipedia at point' to advantage in the results buffer."
  (interactive
   (list (emacsvox-websearch-read "Search Wikipedia: ")))
  (emacsvox-websearch-google
   (url-hexify-string (format "site:wikipedia.org %s"query))))

;;;  YouTube Search:

(defun emacsvox-websearch-youtube-search (query)
  "YouTube search."
  (interactive (list (gweb-youtube-autocomplete)))
  (emacsvox-websearch-google
   (url-hexify-string (format "site:youtube.com  %s"query))))

;;;  Shopping at Amazon

(defun emacsvox-websearch-amazon-search ()
  "Amazon search."
  (interactive)
  (browse-url "http://www.amazon.com/access"))

(provide 'emacsvox-websearch)

;;; emacsvox-websearch.el ends here
