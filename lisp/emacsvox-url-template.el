;;; emacsvox-url-template.el ---  URI templates -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
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

;; It is often useful to have ``parametrized hot list entries''
;; i.e., hotlist entries that are ``templates'' for the
;; actual URL.
;; The user provides values for the parametrized portions
;; of the URL e.g. the date.
;; See @xref{URL Templates}, for details on the URL templates
;; that are presently defined.

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-atom-xsl)
(defvar emacsvox-curl)
(defvar emacsvox-we-paragraphs-xpath-filter)
(defvar emacsvox-we-xpath-filter)
(defvar g-curl-options)

;;  required modules
(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'subr-x))
(require 'emacsvox-preamble)
(require 'eww)
(require 'dom-addons)
(require 'emacsvox-eww)
(require 'emacsvox-feeds)
(require 'gweb)
(require 'gmaps)
(require 'g-utils)
(require 'emacsvox-we)
(require 'emacsvox-xslt)
;;; Appease Emacs-30:
(declare-function
 emacsvox-websearch-google "emacsvox-websearch" (arg1 &optional arg2))

(declare-function iimage-recenter "iimage" (&optional arg))

;;;  structures

(cl-defstruct (emacsvox-url-template
               (:constructor emacsvox-url-template-constructor))
  name                                ;Human-readable name
  template                            ;template URL string
  generators                          ; list of param generator
  post-action                         ;action to perform after opening
  documentation                       ;resource documentation
  fetcher                             ; custom fetcher
  dont-url-encode)

;;;  Helpers

(defun emacsvox-url-template-url (ut)
  "Instantiate URL identified by URL template."
  (let ((url
         (apply 'format
                (emacsvox-url-template-template ut)
                (mapcar
                 #'(lambda (g)
                     (let ((input nil))
                       (setq input
                             (cond
                              ((stringp g)
                               (if (emacsvox-url-template-dont-url-encode ut)
                                   (read-from-minibuffer g)
                                 (url-encode-url (read-from-minibuffer g))))
                              (t (funcall g))))
                       input))
                 (emacsvox-url-template-generators ut)))))
    url))

;;;  persistent store

(defvar emacsvox-url-template-table (make-hash-table :test 'equal)
  "Stores URL templates. ")

(defun emacsvox-url-template-set (key ut)
  "Add specified template to key. "
  
  (setf (gethash (downcase key) emacsvox-url-template-table) ut))

;;;###autoload
(defun emacsvox-url-template-get (key)
  "Lookup key and return corresponding template. "
  
  (gethash (downcase key) emacsvox-url-template-table))

;;;  define resources

(defun emacsvox-url-template-define (name template
                                          &optional generators post-action
                                          documentation fetcher
                                          dont-url-encode)
  "Define a URL template.

name Name used to identify template
template Template URI with `%s' for slots
generators List of prompters.
 Generators are strings or functions.
 String values specify prompts.
 Function values are called to obtain values.
post-action Function called to apply post actions.
 Possible actions include speaking the result.
fetcher Unless specified, browse-url retrieves URL.
 If specified, fetcher is a function of one arg
 that is called with the URI to retrieve.
documentation Documents this template resource.
dont-url-encode if true then url arguments are not url-encoded "
  
  (emacsvox-url-template-set
   name
   (emacsvox-url-template-constructor
    :name name
    :template template
    :generators generators
    :post-action post-action
    :documentation documentation
    :fetcher fetcher
    :dont-url-encode dont-url-encode)))

(defun emacsvox-url-template-load (file)
  "Load URL template resources from specified location."
  (interactive
   (list
    (read-file-name "Load URL templates from file: "
                    emacsvox-user-directory)))
  (condition-case nil
      (progn
        (ems--fastload (expand-file-name file emacsvox-user-directory)))
    (error (message "Error loading resources from %s "
                    file))))

(defun emacsvox-url-template-save (file)
  "Save url templates."
  (interactive
   (list
    (read-file-name "Save URL templates to: " emacsvox-user-directory)))
  
  (let ((print-level nil)
        (print-length nil)
        (buffer (find-file-noselect
                 (expand-file-name file emacsvox-user-directory))))
    (with-current-buffer buffer
      (setq buffer-undo-list  t)
      (erase-buffer)
      (cl-loop
       for key being the hash-keys of emacsvox-url-template-table do
       (insert
        (format
         "\n(setf
 (gethash %s emacsvox-url-template-table)\n %s)"
         (prin1-to-string key)
         (prin1-to-string (emacsvox-url-template-get key)))))
      (basic-save-buffer)
      (kill-buffer buffer))))

;; template resources

;;;  Stock Tickers:

;;;###autoload
(defcustom emacsvox-stock-tickers
  (list "goog" "aapl" "meta" "amzn" "nflx" "msft" "nvda")
  "Set this to the stock tickers you want to check. Default is
the current fab-7!. Tickers is a list of stock symbols sorted in lexical order
with duplicates removed when saving as a list of string."
  :type
  '(repeat
    :tag "Tickers" (string :tag "Symbol"))
  :group 'emacsvox
  :initialize 'custom-initialize-reset
  :set
  #'(lambda (sym val)
      (set-default
       sym
       (cl-remove-duplicates (sort val #'string-lessp) :test #'string=))))

(defsubst emacsvox-stock-tickers ()
  "Return emacsvox-stock-tickers as a CSV string."
  
  (mapconcat #'identity emacsvox-stock-tickers ","))

;;;  amazon

(emacsvox-url-template-define
 "Amazon Product Details By ASIN"
 "https://amazon.com/o/dt/upda-1.0-i/tg/aa/upda/item/-/%s"
 (list "ASIN Or ISBN: ")
 nil
 "Retrieve product details from Amazon by either ISBN or ASIN.")

;;;  Guardian Feed Directory:
(emacsvox-url-template-define
 "Guardian RSS Feeds Directory"
 "http://rss2.io/lists/guardian.opml"
 nil nil
 "Guardian Feeds  Directory"
 #'emacsvox-feeds-opml-display)

;;;  bbc
(emacsvox-url-template-define
 "BBC 5-live  Schedule "
 "https://www.bbc.co.uk/sounds/schedules/bbc_radio_five_live "
 nil
 #'emacsvox-eww-next-h1
 "BBC Radio 5 Live  Schedule")

(emacsvox-url-template-define
 "BBC World Service  Schedule "
 "https://www.bbc.co.uk/sounds/schedules/bbc_world_service " 
 nil
 #'emacsvox-eww-next-h1
 "BBC World Service Schedule")

(emacsvox-url-template-define
 "BBC r4 Schedule "
 "https://www.bbc.co.uk/sounds/schedules/bbc_radio_fourfm "
 nil
 #'emacsvox-eww-next-h1
 "BBC R4 Schedule")

(emacsvox-url-template-define
 "BBC r4 Extra Schedule "
 "https://www.bbc.co.uk/schedules/p00fzl7l"
 nil
 #'emacsvox-eww-next-h1
 "BBC Radio 4 Extra Schedule")

(emacsvox-url-template-define
 "BBC Sounds"
 "https://www.bbc.co.uk/sounds/search?q=%s"
 (list "BBC Sounds:")
 #'emacsvox-speak-line
 "Search BBC Sounds.
Result page is filtered down to two sections, Shows and Episodes.

Press [RET] on links in the Show section to open that show page.
The page for that show contains playable links for Episodes.

Press `y' on Episode links to play them with MPV."
 #'(lambda (url)
     (let ((filter
            (mapconcat
             #'(lambda  (i)
                 (format "/descendant::section[%s]" i))
             '(  3 4 5)
             " | ")))
       (emacsvox-we-xslt-filter filter url))))

(declare-function
 emacsvox-xslt-view-xml
 "emacsvox-xslt" (style url &optional unescape-charent))

(emacsvox-url-template-define
 "Player FM BBC RSS Feeds"
 "https://player.fm/networks/uk-podcast-networks.txt"
 nil #'emacsvox-speak-line
 "Player FM BBC RSS Feeds")

(emacsvox-url-template-define
 "BBC Podcast Directory"
 "http://www.bbc.co.uk/podcasts.opml"
 nil nil
 "BBC PodCast Directory"
 #'emacsvox-feeds-opml-display)

;;;  Google Trends:
(declare-function
 emacsvox-google-canonicalize-result-url "emacsvox-google" (url))
(declare-function emacsvox-google-result-url-prefix "emacsvox-google" nil)
(emacsvox-url-template-define
 "Google Trends"
 "https://www.google.com/trends/hottrends/atom/feed?pn=p1"
 nil nil
 "Google Trends"
 #'emacsvox-feeds-rss-display)
;;; Google Emacsvox Site:

(declare-function
 emacsvox-websearch-google-lite
 "emacsvox-websearch" (query &optional options))

(emacsvox-url-template-define
 "Emacsvox Search Via Google"
 "%s"
 (list "Search Emacsvox Site: ") nil
 "Search Emacsvox Site"
 #'(lambda (q)
     (emacsvox-websearch-google-lite
      (format
       "site:tvraman.github.io+%s" q))))

;;;  utils:

(defun emacsvox-url-template-setup-content-filter ()
  "Set up content filter in displayed page."
  (setq emacsvox-we-xpath-filter emacsvox-we-paragraphs-xpath-filter))
;;; AcuWeather:
(emacsvox-url-template-define
 "ACU Weather"
 "http://rss.accuweather.com/rss/liveweather_rss.asp?locCode=%s"
 (list #'(lambda nil
           (read-from-minibuffer "Location: "
                                 nil nil t nil gmaps-my-zip)))
 #'emacsvox-speak-buffer
 "Weather Forecast from ACUWeather"
 #'emacsvox-feeds-rss-display)

;;; Basic Google:

(emacsvox-url-template-define
 "Local Weather From Google"
 "https://www.google.com/search?num=25&gbv=1&q=weather+%s"
 (list #'(lambda nil gmaps-my-zip))
 #'(lambda nil
     (setq header-line-format "Local Weather")
     (search-forward "Search Tools")
     (forward-line 2)
     (emacsvox-icon 'open-object)
     (tts-with-punctuations 'some
                            (emacsvox-speak-region
                             (point)
                             (save-excursion (forward-line 1) (line-end-position)))))
 "Light-weight Google weather. Displays weather for your current US-ZIP Code. ")

(emacsvox-url-template-define
 "Global Weather From Google"
 "https://www.google.com/search?num=25&gbv=1&q=weather+%s"
 (list "Location:")
 #'(lambda nil
     (search-forward "Search Tools")
     (forward-line 2)
     (emacsvox-icon 'open-object)
     (setq header-line-format "Global Weather")
     (tts-with-punctuations 'some
                            (emacsvox-speak-region
                             (save-excursion (forward-line -1) (line-beginning-position))
                             (save-excursion (forward-line 1) (line-end-position)))))
 "World Weather From Google")

;;;  Calendar Mobile:

;;;  google finance

(emacsvox-url-template-define
 "Finance  Google"
 "https://finance.google.com/quote/%s"
 (list
  #'(lambda nil
      (format
       "%s:%s"
       (read-from-minibuffer "ticker:")
       (cl-case (read-char "o,n")
         (?n "nyse")
         (?o "nasdaq")
         (error "O: nasdaq N: nyse")))))
 #'(lambda nil
     (emacsvox-icon 'open-object)
     (search-forward "Most Active")
     (emacsvox-speak-windowful))
 "Lookup ticker on Google Finance.")

(emacsvox-url-template-define
 "Finance Summary From Google"
 "https://finance.google.com"
 nil
 #'(lambda nil
     (emacsvox-icon 'open-object)
     (search-forward "Most Active")
     (emacsvox-speak-windowful))
 "Display top stocks  from Google Finance.")

;;;  google scholar

(emacsvox-url-template-define
 "Google Scholar"
 (concat  "https://scholar.google.com/scholar"
          "?ie=UTF-8&oe=UTF-8&hl=en&btnG=Search&num=25&q=%s")
 (list "Google Scholar Search: ")
 nil
 "Google Scholar Search"
 #'(lambda (url)
     (emacsvox-we-extract-by-class "gs_r" url 'speak)))

;;;  google translation service

;;;  dictionary.com:
(emacsvox-url-template-define
 "Dictionary Lookup"
 "http://dictionary.reference.com/search?q=%s"
 (list "Dictionary Lookup: ")
 #'(lambda ()
     (search-forward "entries found for " nil t)
     (emacsvox-speak-line))
 "Dictionary Lookup"
 #'(lambda (url)
     (emacsvox-xslt-without-xsl
      (browse-url url))))

;;;  google OverviewOfNews

(emacsvox-url-template-define
 "html Google News Search"
 "https://news.google.com/news?hl=en&ned=tus&q=%s&btnG=Google+Search"
 (list #'gweb-news-autocomplete)
 #'(lambda ()
     (emacsvox-url-template-setup-content-filter)
     (emacsvox-speak-windowful))
 "Search Google news.")

(defun emacsvox-url-template-google-atom-news-display (feed-url)
  "View Google Atom news feed pulled using Curl."
  (emacsvox-eww-autospeak)
  (g-display-result
   (format
    "%s %s    '%s' 2>/dev/null"
    emacsvox-curl g-curl-options feed-url)
   emacsvox-atom-xsl))

(emacsvox-url-template-define
 "Google News Search"
 (concat
  "https://news.google.com/atom/"
  "search?hl=en-US&q=%s&btnG=Google+Search&gl=US&ceid=US:en")
 (list #'gweb-news-autocomplete)
 nil
 "Search Google news."
 #'emacsvox-url-template-google-atom-news-display)

;;;  Google Structured Data Parser:

;;;  Google Archive Search

;;;  cnet news

(emacsvox-url-template-define
 "Tech News From CNet"
 "http://feeds.feedburner.com/cnet/tcoc"
 nil
 'emacsvox-url-template-setup-content-filter
 "Display tech news from CNET"
 #'emacsvox-feeds-rss-display)

;;;  yahoo daily news
(emacsvox-url-template-define
 "Yahoo RSSNews"
 "http://news.yahoo.com/rss"
 nil
 #'(lambda ()
     (emacsvox-pronounce-add-local-entry
      "http://rss.news.yahoo.com/rss/" ""))
 "News  From Yahoo As RSS."
 #'emacsvox-feeds-rss-display)

(emacsvox-url-template-define
 "Yahoo Finance"
 "https://finance.yahoo.com/quote/%s/"
 (list "Ticker:")
 'emacsvox-eww-h2
 "Yahoo Finance Stock News")

;;; CNBC Quotes

(defun ems--ut-quotes-cleanup ()
  "Clean up stock quotes buffer."
  
  (let ((inhibit-read-only t))
    (mapc
     #'(lambda (s) (flush-lines s (point-min) (point-max)))
     '("WATCHLIST" "^52 High" "^Last " "RT Quote " "^quote price arrow "
       "^Volume" "^$"))
    (goto-char (point-min))
    (forward-line 1)
    (emacsvox-icon 'open-object)
    (setq header-line-format "Portfolio")
    (setq
     emacsvox-eww-a-speaker
     #'(lambda nil
         (emacsvox-speak-region
          (point)
          (save-excursion
            (forward-line 6)
            (point)))))
    (rename-buffer "Portfolio" 'unique)
    (forward-line -1)
    (emacsvox-speak-line)))

(emacsvox-url-template-define
 "CNBC Ticker"
 "https://www.cnbc.com/quotes/%s"
 (list "Ticker:")
 #'ems--ut-quotes-cleanup
 "Stock Quote via CNBC"
 #'(lambda (u)
     (emacsvox-we-extract-by-id "MainContentContainer" u )))

(emacsvox-url-template-define
 "CNBC Quotes"
 "https://www.cnbc.com/quotes/%s"
 (list #'emacsvox-stock-tickers)
 #'ems--ut-quotes-cleanup
 "Stock portfolio via CNBC"
 #'(lambda (u)
     (emacsvox-we-extract-by-id "MainContentContainer" u )))

(flush-lines "^Price Quote Arrow Quote " (point-min) (point-max))
;;; Seeking Alpha

(emacsvox-url-template-define
 "Seeking Alpha"
 "https://seekingalpha.com/symbol/%s"
 (list "Ticker: ")
 #'emacsvox-eww-next-h
 "Stock profile from Seeking Alpha ")

;;;  cnn

(emacsvox-url-template-define
 "CNN Money"
 "https://money.cnn.com"
 nil
 #'(lambda ()
     (eww-display-dom-by-role "main"))
 "CNN Money")

(emacsvox-url-template-define
 "CNN Headlines"
 "http://rss.cnn.com/rss/cnn_latest.rss"
 nil nil
 "News Headlines From CNN"
 #'emacsvox-feeds-rss-display)

(declare-function eww-display-dom-by-element "emacsvox-eww" (tag))

(emacsvox-url-template-define
 "Business Headlines From CNN"
 "https://cnn.com/business"
 nil
 #'(lambda nil
     
     (eww-display-dom-by-element 'h2)
     (setq
      emacsvox-we-url-executor 'emacsvox-url-template-cnn-content))
 "Money Headlines From CNN")

;;; Gita:

(emacsvox-url-template-define
 "Gita"
 "https://www.holy-bhagavad-gita.org/chapter/%s/verse/%s"
 (list "Chapter" "Verse")
 'emacsvox-eww-next-h
 "Open specific chapter/verse in the Gita ")

;;;  sourceforge

(emacsvox-url-template-define
 "sourceforge project"
 "http://sourceforge.net/projects/%s"
 (list "Project name")
 nil
 "Open specified project page at SourceForge.")

(emacsvox-url-template-define
 "sourceforge browse mirrors"
 "http://prdownloads.sourceforge.net/%s/?sort_by=date"
 (list "Project name")
 nil
 "Retrieve download page at Sourceforge for specified project.")

(emacsvox-url-template-define
 "sourceforge Download"
 "http://prdownloads.sourceforge.net/%s"
 (list "File: project/filename: ")
 nil
 "Download specified file."
 'browse-url
 'dont-url-encode)

;;;  NBA Standings:
(declare-function emacsvox-wizards-nba-standings  "emacsvox-wizards" nil)
(emacsvox-url-template-define
 "NBA  standings"
 "http://www.nba.com/NASApp/nba/nba/standings/index.jsp" ;;; dummy
 nil
 nil
 "Display NBA standings."
 #'(lambda (_url)
     (emacsvox-wizards-nba-standings)))

;;;  Listening to Air Traffic control

(emacsvox-url-template-define
 "Air Traffic Control"
 "http://www.liveatc.net/search?icao=%s"
 (list "Airport Code: ")
 nil
 "Find live streams for Air Traffic Control."
 #'(lambda (url)
     (emacsvox-we-extract-by-class
      "col1wrap"
      url
      'speak)))

;;;  airport conditions:
(emacsvox-url-template-define
 "Airport conditions"
 "http://www.fly.faa.gov/flyfaa/flyfaaindex.jsp?ARPT=%s&p=0"
 (list "Airport Code:")
 nil
 "Display airport conditions from the FAA."
 #'(lambda (url)
     (emacsvox-we-extract-table-by-match "Status"
                                         url 'speak)))

;;;  wordnet

(emacsvox-url-template-define
 "WordNet Search"
 (concat "http://wordnetweb.princeton.edu/perl/webwn"
         "?s=%s&o1=1&o8=1&o0=1&sub=Search+WordNet")
 (list "WordNet Define: ")
 #'(lambda ()
     (search-forward "(gloss)")
     (forward-line 1)
     (emacsvox-speak-windowful))
 "Look up term in WordNet.")

;;;  Radio station streams

(emacsvox-url-template-define
 "CBS Radio streams from streamtheworld"
 "http://provisioning.streamtheworld.com/pls/%s.pls"
 (list
  #'(lambda () (upcase (read-from-minibuffer "Station ID: "))))
 nil
 "Play radio stream.
Example: kcbsFM.
Format is stationid+AM/FM."
 #'(lambda (url)
     (emacsvox-empv-play-file url )))
;;; Url Shortener:

(emacsvox-url-template-define
 "TinyURL"
 "http://tinyurl.com/api-create.php?url=%s"
 (list
  #'(lambda nil
      (or (thing-at-point 'url)
          (shr-url-at-point nil)
          (read-string "URL: "))))
 nil 
 "URL Shortener via tinyurl.
If on a URL, replace it with the shortened version. If on a link
in EWW, use it. Otherwise prompt for a URL to shorten and insert
the result at point."
 #'(lambda (u)
     (let ((b (bounds-of-thing-at-point 'url))
           (r (shell-command-to-string (format "curl -s '%s'" u))))
       (cond
        ((not buffer-read-only)
         (when (thing-at-point 'url)
           (kill-new r)
           (when b (kill-region (car b) (cdr b))))
         (insert r)
         (emacsvox-speak-line))
        (t (tts-speak "Saved shortened url to kill ring"))))))

;;; Hoogle
(declare-function emacsvox-eww-next-h1 "emacsvox-eww" (&optional speak))

(emacsvox-url-template-define
 "Hoogle Haskell API Search"
 "http://localhost:8080/?hoogle=%s"
 (list "Hoogle: ")
 #'emacsvox-eww-next-h1
 "Haskell API Search against a local server.")

;;;  Bing RSS

(emacsvox-url-template-define
 "Microsoft Search"
 "http://www.bing.com/search?format=rss&q=%s%s"
 (list
  "Bing Search: "
  #'(lambda ()
      (let ((choice
             (completing-read "Date Restrict d w m y: "
                              '("d" "w" "m" "y"))))
        (cond
         ((string= "" choice) "")
         (t (format "&tbs=qdr:%s" choice))))))
 nil
 "Bing results as RSS feed."
 #'emacsvox-feeds-rss-display)

(emacsvox-url-template-define
 "Bing News"
 "http://www.bing.com:80/news/search?q=%s&format=RSS"
 (list "Bing Search: ")
 nil
 "Bing News results as RSS feed."
 #'emacsvox-feeds-rss-display)

;;;  TuneIn: streamId->URL
;; wget -O t    "http://stream.radiotime.com/listen.stream?streamIds=4299203"
(emacsvox-url-template-define
 "TuneIn Radio"
 "https://opml.radiotime.com/Tune.ashx?id=%s"
 (list "StreamId: ")
 nil
 "Translate StreamId to playable stream."
 #'(lambda (url)
     (kill-new url)
     (emacsvox-empv-play-file url)
     (message "%s" url))
 "TuneIn Helper.")

(emacsvox-url-template-define
 "Online RadioTime Browser"
 "http://opml.radiotime.com/"
 nil
 nil
 "RadioTime Entry point."
 #'emacsvox-feeds-opml-display)

(emacsvox-url-template-define
 "Online RadioTime Search"
 "http://opml.radiotime.com/Search.ashx?query=%s"
 (list "Search: ")
 nil
 "RadioTime Search"
 #'emacsvox-feeds-opml-display)

(defvar emacsvox-url-template--radiotime-categories
  '("best" "lang" "local"
    "location" "music" "podcast" "popular" "sports" "sports" "talk" "world")
  "Categories from Radio Time.")

(emacsvox-url-template-define
 "RadioTime Categories"
 "http://opml.radiotime.com/browse.ashx?c=%s"
 (list
  #'(lambda ()
      (completing-read
       "Category: " emacsvox-url-template--radiotime-categories)))
 nil
 "RadioTime Categories "
 #'emacsvox-feeds-opml-display)

;;;  OpenLibrary

(emacsvox-url-template-define
 "OpenLibrary"
 (concat  "https://openlibrary.org/search?"
          "subject_facet=Accessible+book&q=%s&has_fulltext=true")
 (list "Query: ")
 nil
 "Open Library Search")

;;;  FreeSound.org:

(emacsvox-url-template-define
 "FreeSound"
 "http://freesound.org/search/?q=%s"
 (list "Search FreeSound: ")
 nil
 "Search FreeSound.")

;;;  Interactive commands

;;;###autoload
(defun emacsvox-url-template-open (ut)
  "Fetch resource identified by URL template."
  
  (let ((read-process-output-max (* 1024 1024))
        (fetcher (or (emacsvox-url-template-fetcher ut) 'browse-url))
        (url (emacsvox-url-template-url ut))
        (action (emacsvox-url-template-post-action ut)))
    (when action (add-hook 'emacsvox-eww-post-hook action))
    (kill-new url)
    (funcall fetcher url)))

(defun emacsvox-url-template-help-internal (name)
  "Display and speak help."
  (with-output-to-temp-buffer "*Help*"
    (princ name)
    (princ "\n\n")
    (princ
     (emacsvox-url-template-documentation
      (emacsvox-url-template-get name)))
    (save-current-buffer
      (set-buffer standard-output)
      (fill-region (point-min)
                   (point-max)))
    (help-print-return-message))
  (emacsvox-speak-help)
  (emacsvox-icon 'help))
(defun emacsvox-url-template-generate-name-setter (name)
  "Generate a setter that sets emacsvox-eww-url-template
to specified name for use as a callback."
  (eval
   `#'(lambda ()
        
        (setq emacsvox-eww-url-template ',name))))

;;;###autoload
(defun emacsvox-url-template-fetch (&optional documentation)
  "Fetch a pre-defined resource.
Use Emacs completion to obtain a list of available resources.
Resources typically prompt for the relevant information
before completing the request.
Optional interactive prefix arg displays documentation for specified resource."
  (interactive "P")
  (let ((completion-ignore-case t)
        (name nil))
    (setq name
          (completing-read
           "Resource: " emacsvox-url-template-table nil 'must-match))
    (cond
     (documentation (emacsvox-url-template-help-internal name))
     (t
      (add-hook
       'emacsvox-eww-post-hook
       (emacsvox-url-template-generate-name-setter name))
      (emacsvox-url-template-open (emacsvox-url-template-get name))))))

(defun emacsvox-url-template-help ()
  "Display documentation for a URL template.
Use Emacs completion to obtain a list of available
resources."
  (interactive)
  
  (let ((completion-ignore-case t)
        (name nil))
    (setq name
          (completing-read "Resource: "
                           emacsvox-url-template-table))
    (emacsvox-url-template-help-internal name)))

;;;  Generate texinfo documentation for all defined url

(defun emacsvox-url-template-generate-texinfo-documentation (buffer)
  "Generates texinfo section documenting all defined URL templates."
  
  (with-current-buffer buffer
    (insert
     "@node URL Templates \n@section URL Templates\n\n")
    (insert
     (format
      "
This section documents a total of %d URL Templates.\n\n"
      (hash-table-count emacsvox-url-template-table)))
    (insert
     (format
      "All of these URL templates can be invoked via command
 @kbd{M-x emacsvox-url-template-fetch} normally bound to
 @kbd{%s}.
This command prompts for the name of the template, and completion
 is available via Emacs' minibuffer completion.
Each URL template carries out the following steps:
@itemize @bullet
@item Prompt for the relevant information.
@item Fetch the resulting URL using an appropriate fetcher.
@item Set up the resulting resource with appropriate
 customizations.
@end itemize
"
      (mapconcat #'key-description
                 (where-is-internal
                  'emacsvox-url-template-fetch)
                 " ")))
    (let*
        ((case-fold-search  t)
         (keys
          (sort
           (cl-loop
            for k being the hash-keys of emacsvox-url-template-table
            collect k)
           'string-lessp)))
      (insert "@enumerate \n\n")
      (cl-loop
       for key in keys do
       (insert
        (format "\n@item @b{%s}\n\n" key))
       (condition-case nil
           (insert
            (emacsvox-url-template-documentation
             (emacsvox-url-template-get key)))
         (error
          (message "Error: URL Template  %s"
                   (emacsvox-url-template-name
                    (emacsvox-url-template-get key))))))
      (insert "\n\n@end enumerate\n\n"))))

;;;  wikiData:

(emacsvox-url-template-define
 "Wikipedia At Point"
 "" nil nil
 "Extract body content from Wikipedia link at point"
 #'(lambda (_)
     (emacsvox-icon 'open-object)
     (emacsvox-eww-autospeak)
     (emacsvox-we-extract-by-id "bodyContent" (shr-url-at-point nil))))

(emacsvox-url-template-define
 "Wiki Data Search"
 "https://www.wikidata.org/w/index.php?search=%s"
 (list "WikiData Query: ")
 #'(lambda nil
     (re-search-forward "^Result")
     (forward-line 1)
     (emacsvox-speak-windowful))
 "Search WikiData.")

;;;  Search NLS Bard:

(defun emacsvox-url-template-nls-add-to-wishlist  (book)
  "Add book under point to wishlist."
  (interactive (list  (ems--read-url)))
  (let  ((add nil))
    (unless book (error "No Book URL specified"))
    (setq add
          (replace-regexp-in-string "download/detail" "wishlist/add" book))
    (message "Updating  book in  wishlist.")
    (emacsvox-icon 'progress)
    (eww add)))

(emacsvox-url-template-define
 "NLS Bard Search"
 (concat  "https://nlsbard.loc.gov/nlsbardprod/search/"
          "collection/page/1/sort/s/srch/%s/local/0")
 (list "Search For: ")
 #'(lambda nil
     
     (setq emacsvox-we-url-executor
           #'emacsvox-url-template-nls-add-to-wishlist)
     (emacsvox-speak-mode-line))
 "Search NLS Bard Catalog. Login once before using this template."
 #'(lambda (url)
     (let ((url-privacy-level
            'high))
       (eww-browse-url url))))

(emacsvox-url-template-define
 "NLS Bard Bookshelf"
 "https://nlsbard.loc.gov/nlsbardprod/wishlist/collection/page/1/sort/rch"
 nil
 #'(lambda nil
     
     (setq emacsvox-we-url-executor
           #'emacsvox-url-template-nls-add-to-wishlist)
     (emacsvox-speak-mode-line))
 "NLS Bard Catalog: Most Popular. Login once before using this
template."
 #'(lambda (url)
     (let ((url-privacy-level
            'high))
       (eww-browse-url url))))

(emacsvox-url-template-define
 "NLS Bard Popular"
 (concat
  "https://nlsbard.loc.gov:443/"
  "nlsbardprod/search/most_popular/page/1/sort/s/srch/most_popular/local/0")
 nil
 #'(lambda nil
     
     (setq emacsvox-we-url-executor
           #'emacsvox-url-template-nls-add-to-wishlist)
     (emacsvox-speak-mode-line))
 "NLS Bard Catalog: Most Popular. Login once before using this
template."
 #'(lambda (url)
     (let ((url-privacy-level
            'high))
       (eww-browse-url url))))

(emacsvox-url-template-define
 "NLS Bard Recent"
 "https://nlsbard.loc.gov/mainpage/srch_recentlyadded"
 nil
 #'(lambda nil
     
     (setq emacsvox-we-url-executor
           #'emacsvox-url-template-nls-add-to-wishlist)
     (emacsvox-speak-mode-line))
 "NLS Bard Catalog: Recently Added. Login once before using this
template."
 #'(lambda (url)
     (let ((url-privacy-level
            'high))
       (eww-browse-url url))))

;;;  Washington Post
(declare-function emacsvox-eww-next-h "emacsvox-eww" (&optional speak))

(emacsvox-url-template-define
 "Washington Post"
 "https://www.washingtonpost.com/"
 nil
 #'(lambda nil
     (emacsvox-eww-next-h)
     (emacsvox-speak-line))
 "Washington Post Contents")

;;;  ArchWiki

(emacsvox-url-template-define
 "ArchWiki Search"
 "https://wiki.archlinux.org/index.php/%s"
 (list "Search: ")
 #'(lambda ()
     (emacsvox-eww-next-h)
     (emacsvox-speak-windowful))
 "Search Linux ArchWiki")

;;; Reddit Tools:

(declare-function shr-url-at-point "shr" (image-url))

(emacsvox-url-template-define
 "Reddit At Point"
 "" nil nil
 "Open RSS Feed for Reddit URL under point."
 #'(lambda (_url)
     (let* ((u
             (or
              (shr-url-at-point nil)
              (browse-url-url-at-point)
              (read-from-minibuffer "URL:")))
            (url
             (if (string-prefix-p (emacsvox-google-result-url-prefix) u)
                 (emacsvox-google-canonicalize-result-url u)
               u)))
       (cl-assert url t "No URL under point.")
       (cl-assert
        (string-match "https://www.reddit.com" url) t
        "Does not look like a Reddit URL")
       (emacsvox-eww-autospeak)
       (emacsvox-feeds-atom-display (concat url ".rss")))))

(emacsvox-url-template-define
 "Reddit Search"
 "https://www.reddit.com/search.rss?q=%s&sort=new&t=all"
 (list "Reddit Search:")
 nil
 "Reddit Search Results Feed."
 #'emacsvox-feeds-atom-display)

(emacsvox-url-template-define
 "Reddit By Topic"
 "https://www.reddit.com/r/%s/.rss"
 (list "Topic:")
 nil
 "Open RSS Feed for Reddit Topic."
 #'emacsvox-feeds-atom-display)

(emacsvox-url-template-define
 "Reddit Front Page"
 "https://www.reddit.com/.rss"
 nil
 nil
 "Open  Feed for Reddit  Front Page."
 #'emacsvox-feeds-atom-display)

;;; Hacker News:

(emacsvox-url-template-define
 "Hacker  News Frontpage"
 "https://hnrss.org/frontpage"
 nil nil
 "Display Hacker News Front Page"
 #'emacsvox-feeds-rss-display)

(emacsvox-url-template-define
 "Hacker  News Search"
 "https://hnrss.org/newest?q=%s"
 (list "Hacker News Search:")
 nil
 "Display Hacker News Front Page"
 #'emacsvox-feeds-rss-display)

;;; Air Quality From Wunderground

(emacsvox-url-template-define
 "AQI From Wunderground"
 "https://www.wunderground.com/health/us/%s"
 (list
  #'(lambda ()
      (read-from-minibuffer "state/city/zip: " "ca/san-jose/95123")))
 nil
 "Air quality from Wunderground"
 #'(lambda (url)
     (emacsvox-we-extract-by-class
      "small-6" url 'speak))
 'dont-encode)

;;; cricinfo print rule

(emacsvox-url-template-define
 "Cricinfo Print"
 "_" ; place holder
 nil nil
 "Printer friendly   link on Cricinfo"
 #'(lambda (_u)
     (add-hook
      'emacsvox-eww-post-hook
      #'(lambda nil
          (search-forward "\n\n")
          (tts-apply-punctuation-mode-policy)
          (emacsvox-speak-rest-of-buffer))
      'at-end)
     (browse-url
      (replace-regexp-in-string
       "ci/content/\\(.*\\)\\.html*"
       "print/\\1"
       (shr-url-at-point nil)))))

(emacsvox-url-template-define
 "ESPN Cricinfo Search"
 "_" ;() place holder
 (list "Query: ") nil
 "Cricinfo Search Using Google"
 #'(lambda (q)
     (emacsvox-websearch-google
      (format "site:cricinfo.com+%s" q))))

;;; npr:

(declare-function emacsvox-eww-links-rel "emacsvox-eww" nil)

(emacsvox-url-template-define
 "NPR"
 "http://npr.org"
 nil
 #'emacsvox-eww-links-rel
 "Open NPR home , then display the alternative links to access RSS feeds.")

(provide 'emacsvox-url-template)

;;; emacsvox-url-template.el ends here
