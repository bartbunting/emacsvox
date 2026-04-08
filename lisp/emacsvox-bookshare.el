;;; emacsvox-bookshare.el --- BOOKSHARE client  -*- lexical-binding: t; -*-
;; $Id: emacsvox-bookshare.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable BOOKSHARE An Emacs Interface to bookshare
;; Keywords: Emacsvox,  Audio Desktop bookshare
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
;; MERCHANTABILITY or FITNBOOKSHARE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; BOOKSHARE == http://www.bookshare.org
;; provides book access to print-disabled users.
;; It provides a simple Web  API http://developer.bookshare.org
;; This module implements an Emacsvox Bookshare client.
;; @subsection  requirements
;; @itemize
;; @item You need to get your own API key
;; @item You need Emacs built with libxml2 support
;; @end itemize
;; 
;; @subsection Usage
;; The main entry point is command
;; @code{emacsvox-bookshare} bound to @kbd{C-e C-b}.
;; This creates a special @strong{Bookshare Interaction} buffer that is
;; placed in @strong{emacsvox-bookshare-mode}.
;; Se the help for that mode on detailed usage instructions and key-bindings.
;; 
;; @subsection Sample Interaction
;; 
;; Assuming you have correctly setup your API key:
;; @itemize
;; @item Customize group @code{emacsvox-bookshare} by pressing @kbd{C-h G}.
;; @item  Press @kbd{C-e C-b} to open or switch to the Bookshare buffer.
;; @item Perform a search @kbd{a} or @kbd{t} for author or title search.
;; @item You will be prompted for your Bookshare password if this is
;; the first time.
;; @item The password will be saved to your configured
;; @code{auth-source} --- usually @code{~/.authinfo.gpg}.
;; You can also use @code{password-store[.]}
;; @item The results of the search appear in the Bookshare buffer.
;; Audio formatting and auditory icons convey 
;; if  a result is already available locally.
;; @item If not available locally, press @kbd{D} to download the content.
;; @item Press @kbd{U} to unpack the downloaded content.
;; @item Press @kbd{e} to  display the entire book.
;; @item Press @kbd{c} to display the table of contents.
;; @item Now, use all of EWW  @xref{emacsvox-eww} extensions  and profit!
;; @end itemize
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-xslt)
(eval-when-compile (require 'derived)
                   (require 'g-utils))
(require 'dom)
(require 'xml)
(declare-function auth-source-search "auth-source" (&rest rest))
(declare-function dired-get-filename "dired" (&optional localp
                                                        no-error))
(unless emacsvox-curl (warn "This module will not work without Curl."))
;;;  Customizations

(defgroup emacsvox-bookshare nil
  "Bookshare Access on the Complete Audio Desktop."
  :group 'emacsvox)

(defcustom emacsvox-bookshare-api-key nil
  "Web API  key for this application.
See http://developer.bookshare.org/docs for details on how to get
  an API key. "
  :type
  '(choice :tag "Key"
           (const :tag "Unspecified" nil)
           (string :tag "API Key"))
  :group 'emacsvox-bookshare)

(defvar emacsvox-bookshare-user-id nil
  "Bookshare user Id.")

(defcustom emacsvox-bookshare-directory
  (eval-when-compile (expand-file-name "~/books/book-share"))
  "Customize this to the root of where books are organized."
  :type 'directory
  :group 'emacsvox-bookshare)

(defvar emacsvox-bookshare-downloads-directory
  (expand-file-name "downloads/" emacsvox-bookshare-directory)
  "Directory where archives are saved on download.")

(defvar emacsvox-bookshare-browser-function
  'eww-browse-url
  "Function to display Bookshare Book content in a WWW browser.
This is used by the various Bookshare view commands to display
  content from Bookshare books.")

;;;  Variables:

(defvar emacsvox-bookshare-api-base
  "https://api.bookshare.org"
  "Base end-point for Bookshare API  access.")

;;;  Helpers:

(defun emacsvox-bookshare-dom-clean-text (dom tag)
  "Extract text from specified tag, and clean up entity references."
  (xml-substitute-special
   (xml-substitute-numeric-entities
    (dom-text (dom-by-tag dom tag)))))

(defsubst emacsvox-bookshare-assert ()
  "Error out if not in Bookshare mode."
  (unless (eq major-mode 'emacsvox-bookshare-mode)
    (error "Not in Bookshare Interaction.")))

(defvar emacsvox-bookshare-md5-cached-token nil
  "Cache MD5 token for future use.")

(defun emacsvox-bookshare-user-password ()
  "User password.
Get user and secret from auth-sources, and memoize the user and
the MD5-encoded secret."
  (cl-declare (special emacsvox-bookshare-user-id
                       emacsvox-bookshare-md5-cached-token))
  (unless emacsvox-bookshare-md5-cached-token
    (let ((auth-info (emacsvox-bookshare-get-auth-info)))
      (setq emacsvox-bookshare-user-id (car auth-info))
      (setq emacsvox-bookshare-md5-cached-token (md5 (cdr auth-info)))))
  (format "-H 'X-password: %s'" emacsvox-bookshare-md5-cached-token))

(defun emacsvox-bookshare-get-auth-info()
  "Get the email and password for BookShare if it already exists
in `auth-sources'. If not present, ask for email and password,
and create an entry in the `auth-sources'.

Returns a cons cell where the car is email, and the cdr is password."
  (let* ((auth-source-creation-prompts
          '((user . "Your BookShare.org e-mail: ")
            (secret . "Your BookShare.org password: ")))
         (found
          (nth 0
               (auth-source-search
                :max 1
                :host "api.bookshare.org"
                :port 'https
                :create t
                :require '(:user :secret)))))
    (when found
      (let ((user (plist-get found :user))
            (secret (plist-get found :secret))
            (save-function (plist-get found :save-function)))
        (while (functionp secret) (setq secret (funcall secret)))
        (when (functionp save-function) (funcall save-function))
        (cons user secret)))))

(defun emacsvox-bookshare-rest-endpoint (operation operand &optional noauth)
  "Return  URL  end point for specified operation.
Optional argument `noauth' says no user auth needed."
  (cl-assert emacsvox-bookshare-api-key nil "API key not set.")
  (unless (or  noauth  emacsvox-bookshare-user-id)
    ;;  initialize user-id
    (emacsvox-bookshare-user-password))
  (url-encode-url
   (format "%s/%s/%s/%s?api_key=%s"
           emacsvox-bookshare-api-base operation operand
           (if noauth "" (format "for/%s" emacsvox-bookshare-user-id))
           emacsvox-bookshare-api-key)))

(defun emacsvox-bookshare-page-rest-endpoint ()
  "Generate REST endpoint for the next page of results."
  
  (unless emacsvox-bookshare-last-action-uri
    (error "No query to  page!"))
  (let ((root
         (cl-first (split-string emacsvox-bookshare-last-action-uri "/for")))
        (page nil))
    (setq page (string-match "/page/" root))
    (cond
     (page
      (setq page (split-string root "/page/"));Already paged once
      (format "%s/page/%s/for/%s?api_key=%s"
              (cl-first page)
              (1+ (read (cl-second page)))
              emacsvox-bookshare-user-id
              emacsvox-bookshare-api-key))
     (t
      (format "%s/page/2/for/%s?api_key=%s"
              root
              emacsvox-bookshare-user-id
              emacsvox-bookshare-api-key)))))

(defun emacsvox-bookshare-destruct-rest-url (url)
  "Return operator and operand used to construct this REST end-point."
  
  (let* ((start (length emacsvox-bookshare-api-base))
         (end (string-match "for/" url)))
    (nthcdr 2
            (split-string
             (substring url start end) "/" 'no-null))))

(defun emacsvox-bookshare-download-url (id fmt)
  "Return  URL  end point for content download.
Argument id specifies content. Argument fmt = 0 for Braille, 1
   for Daisy, 3 for epub-3,6 for audio."
  (format "%s/%s/%s?api_key=%s"
          emacsvox-bookshare-api-base
          (format "download/content/%s/version/%s" id fmt)
          (format "for/%s" emacsvox-bookshare-user-id)
          emacsvox-bookshare-api-key))

(defun emacsvox-bookshare-get-result (command)
  "Run command and return its output."
  
  (g-using-scratch
   (call-process shell-file-name nil t
                 nil shell-command-switch
                 command)
   (goto-char (point-min))
   (message "Size: %d" (buffer-size))
   (libxml-parse-xml-region (point-min) (point-max))))

(defvar emacsvox-bookshare-last-action-uri nil
  "Cache last API call URI.")
(defvar emacsvox-bookshare-curl-options
  " --insecure --location "
  "Common Curl options for Bookshare. Includes --insecure as per
Bookshare docs.")

(defun emacsvox-bookshare-api-call (operation operand &optional no-auth)
  "Make a Bookshare API  call and get the result.
Optional argument `no-auth' says we dont need a user auth."
  
  (setq emacsvox-bookshare-last-action-uri
        (emacsvox-bookshare-rest-endpoint operation operand no-auth))
  (emacsvox-bookshare-get-result
   (format
    "%s %s %s  %s 2>/dev/null"
    emacsvox-curl emacsvox-bookshare-curl-options
    (if no-auth "" (emacsvox-bookshare-user-password))
    emacsvox-bookshare-last-action-uri)))

(defun emacsvox-bookshare-get-more-results ()
  "Get next page of results for last query."
  (interactive)
  
  (setq emacsvox-bookshare-last-action-uri
        (emacsvox-bookshare-page-rest-endpoint))
  (emacsvox-bookshare-get-result
   (format "%s %s %s  %s 2>/dev/null"
           emacsvox-curl emacsvox-bookshare-curl-options
           (emacsvox-bookshare-user-password)
           emacsvox-bookshare-last-action-uri)))

(defun emacsvox-bookshare-generate-target (author title &optional fmt)
  "Generate a suitable filename target."
  
  (expand-file-name
   (replace-regexp-in-string
    "[ _&'\":();]+" "-"
    (format "%s-%s%s.zip"
            author title
            (if  fmt
                (format "-%s" fmt) "")))
   emacsvox-bookshare-downloads-directory))

(defun emacsvox-bookshare-generate-directory (author title)
  "Generate name of unpack directory."
  
  (expand-file-name
   (replace-regexp-in-string
    "[ _&'\":();]+" "-"
    (format "%s/%s" author title))
   emacsvox-bookshare-directory))

(defun emacsvox-bookshare-destruct-target (target)
  "Destruct  a  filename target into components."
  (split-string
   (substring target  0 -4)
   "-" 'no-null))

;;;  Book Actions:

(defvar emacsvox-bookshare-categories nil
  "Cached list of categories.")

(defun emacsvox-bookshare-categories ()
  "Return memoized list of categories."
  
  (or
   emacsvox-bookshare-categories
   (setq
    emacsvox-bookshare-categories
    (let ((result
           (dom-by-tag
            (emacsvox-bookshare-api-call
             "reference/category/list" "" 'no-auth)
            'result)))
      (cl-loop
       for r in result collect
       (url-encode-url (dom-text (dom-by-tag r  'name))))))))

;;  Following actions return book metadata:

(defun emacsvox-bookshare-isbn-search (query)
  "Perform a Bookshare isbn search."
  (interactive "sISBN: ")
  (emacsvox-bookshare-api-call "book/isbn" query))

(defun emacsvox-bookshare-id-search (query)
  "Perform a Bookshare id search."
  (interactive "sId: ")
  (emacsvox-bookshare-api-call "book/id" query))

;; preference  getter/setter:

(defun emacsvox-bookshare-list-preferences ()
  "Return preference list."
  (interactive)
  (emacsvox-bookshare-api-call
   "user" "preferences/list"))

(defun emacsvox-bookshare-set-preference (preference-id value)
  "Set preference preference-id to value."
  (interactive "sPreference Id:\nsValue: ")
  (emacsvox-bookshare-api-call
   "user"
   (format "preference/%s/set/%s"
           preference-id value)))

;; Following Actions return book-list structures within a bookshare envelope.

(defun emacsvox-bookshare-author-search (query &optional category)
  "Perform a Bookshare author search.
Interactive prefix arg filters search by category."
  (interactive
   (list
    (url-hexify-string
     (read-from-minibuffer "author: "))
    current-prefix-arg))
  (cond
   ((null category)                     ; plain search
    (emacsvox-bookshare-api-call "book/searchFTS/author" query))
   (t                                   ; filter using category:
    (let* ((completion-ignore-case  t)
           (filter
            (completing-read "Category: "
                             (emacsvox-bookshare-categories))))
      (emacsvox-bookshare-api-call
       "book/searchFTS/author"
       (format "%s/category/%s"
               query filter))))))

(defun emacsvox-bookshare-title-search (query &optional category)
  "Perform a Bookshare title search.
Interactive prefix arg filters search by category."
  (interactive
   (list
    (url-hexify-string
     (read-from-minibuffer "Title: "))
    current-prefix-arg))
  (cond
   ((null category)                     ; plain search
    (emacsvox-bookshare-api-call "book/searchFTS/title" query))
   (t                                   ; filter using category:
    (let* ((completion-ignore-case t)
           (filter
            (completing-read "Category: "
                             (emacsvox-bookshare-categories))))
      (emacsvox-bookshare-api-call
       "book/searchFTS/title"
       (format "%s/category/%s"
               query filter))))))

(defun emacsvox-bookshare-title/author-search (query)
  "Perform a Bookshare title/author  search."
  (interactive "sTitle/Author: ")
  (emacsvox-bookshare-api-call "book/searchTA" query))

(defun emacsvox-bookshare-fulltext-search (query)
  "Perform a Bookshare fulltext search."
  (interactive "sFulltext Search: ")
  (emacsvox-bookshare-api-call "book/searchFTS" query))

(defun emacsvox-bookshare-since-search (query &optional category)
  "Perform a Bookshare date  search.
Optional interactive prefix arg filters by category."
  (interactive
   (list
    (read-from-minibuffer "Date:MmDdYyYy")
    current-prefix-arg))
  (cond
   ((null category)                     ; plain search
    (emacsvox-bookshare-api-call "book/search/since" query))
   (t                                   ; filter using category:
    (let* ((completion-ignore-case t)
           (filter
            (completing-read "Category: "
                             (emacsvox-bookshare-categories))))
      (emacsvox-bookshare-api-call
       "book/search/since"
       (format "%s/category/%s"
               query filter))))))

(defun emacsvox-bookshare-browse-latest()
  "Return latest books."
  (interactive)
  (emacsvox-bookshare-api-call "book/browse/latest" ""))

(defun emacsvox-bookshare-browse-popular(&optional category)
  "Browse popular books.
Optional interactive prefix arg prompts for a category to use as a filter."
  (interactive "P")
  (cond
   ((null category)                     ; plain search
    (emacsvox-bookshare-api-call "book/browse/popular" ""))
   (t                                   ; filter using category:
    (let* ((completion-ignore-case t)
           (filter
            (completing-read "Category: "
                             (emacsvox-bookshare-categories))))
      (emacsvox-bookshare-api-call
       "book/browse/popular"
       (format "category/%s" filter))))))

;;;  Periodical Actions:

;; Returns periodical list

(defun emacsvox-bookshare-periodical-list ()
  "Return list of periodicals."
  (interactive)
  (emacsvox-bookshare-api-call
   "periodical" "list"))

;;;  Downloading Content:

(defun emacsvox-bookshare-download-internal(url target)
  "Download content  to target location."
  (interactive)
  (shell-command
   (format
    "%s %s %s  '%s' -o \"%s\""
    emacsvox-curl
    emacsvox-bookshare-curl-options
    (emacsvox-bookshare-user-password)
    url
    target)))

(defun emacsvox-bookshare-download-daisy(id target)
  "Download Daisy format of specified book to target location."
  (interactive)
  (emacsvox-bookshare-download-internal
   (emacsvox-bookshare-download-url id 1)
   target))

(defun emacsvox-bookshare-download-audio(id target)
  "Download audio format of specified book to target location."
  (interactive)
  (emacsvox-bookshare-download-internal
   (emacsvox-bookshare-download-url id 6)
   target))

(defun emacsvox-bookshare-download-epub-3(id target)
  "Download epub-3 format of specified book to target location."
  (interactive)
  (emacsvox-bookshare-download-internal
   (emacsvox-bookshare-download-url id 3)
   target))

(defun emacsvox-bookshare-download-brf(id target)
  "Download Daisy format of specified book to target location."
  (interactive)
  (emacsvox-bookshare-download-internal
   (emacsvox-bookshare-download-url id 0)
   target))

;;;  Actions Table:

(defvar emacsvox-bookshare-action-table (make-hash-table :test #'equal)
  "Table mapping Bookshare actions to  handlers.")

(defun emacsvox-bookshare-action-set (action handler)
  "Set up action handler."
  
  (setf (gethash action emacsvox-bookshare-action-table) handler))

(defun emacsvox-bookshare-action-get (action)
  "Retrieve action handler."
  
  (or (gethash action emacsvox-bookshare-action-table)
      (error "No handler defined for action %s" action)))

(define-derived-mode emacsvox-bookshare-mode special-mode
  "Bookshare Library"
  "A Bookshare front-end for the Emacsvox desktop.

The Emacsvox Bookshare front-end is launched by command
emacsvox-bookshare bound to \\[emacsvox-bookshare]

This command switches to a special buffer that has Bookshare
commands bounds to single keystrokes-- see the key-binding list at
the end of this description. Use Emacs online help facility to
look up help on these commands.

emacsvox-bookshare-mode provides the necessary functionality to
Search and download Bookshare material, Manage a local library of
downloaded Bookshare content, And commands to easily read newer
Daisy books from Bookshare.

Here is a list of all emacsvox Bookshare commands  with their key-bindings:
a Author Search
A Author/Title Search
t Title Search
s Full Text Search
d Date Search
b Browse

\\{emacsvox-bookshare-mode-map}"
  (let ((inhibit-read-only t)
        (start (point)))
    (goto-char (point-min))
    (insert "Browse And Read Bookshare Materials\n\n")
    (put-text-property start (point)
                       'face font-lock-doc-face)
    (setq header-line-format "Bookshare Library")
    (cd-absolute emacsvox-bookshare-directory)))

(cl-declaim (special emacsvox-bookshare-mode-map))

(cl-loop
 for a in
 '(
   ("+" emacsvox-bookshare-get-more-results)
   ("/" emacsvox-bookshare-title/author-search)
   ("I" emacsvox-bookshare-id-search)
   ("P" emacsvox-bookshare-list-preferences)
   ("S" emacsvox-bookshare-set-preference)
   ("a" emacsvox-bookshare-author-search)
   ("d" emacsvox-bookshare-since-search)
   ("i" emacsvox-bookshare-isbn-search)
   ("l" emacsvox-bookshare-browse-latest)
   ("m" emacsvox-bookshare-periodical-list)
   ("p" emacsvox-bookshare-browse-popular)
   ("s" emacsvox-bookshare-fulltext-search)
   ("t" emacsvox-bookshare-title-search)
   )
 do
 (progn
   (emacsvox-bookshare-action-set (cl-first a) (cl-second a))
   (define-key emacsvox-bookshare-mode-map (kbd (cl-first a))
               'emacsvox-bookshare-action)))

;;;  Bookshare XML  handlers:

(defvar emacsvox-bookshare-handler-table
  (make-hash-table :test #'eq)
  "Table of handlers for processing  Bookshare response elements.")

(defun emacsvox-bookshare-handler-set (element handler)
  "Set up element handler."
  
  (setf (gethash element emacsvox-bookshare-handler-table) handler))

(defun emacsvox-bookshare-handler-get (element)
  "Retrieve action handler."
  
  (let ((handler (gethash element emacsvox-bookshare-handler-table)))
    (if (fboundp handler) handler 'emacsvox-bookshare-recurse)))

(defvar emacsvox-bookshare-response-elements
  '(bookshare debugInfo  version metadata messages string status-code
              book user string downloads-remaining
              id name value editable
              periodical list page num-pages limit result)
  "Bookshare response elements for which we have explicit handlers.")

(cl-loop
 for e in emacsvox-bookshare-response-elements
 do
 (emacsvox-bookshare-handler-set
  e
  (intern (format "emacsvox-bookshare-%s-handler" (symbol-name e)))))

(cl-loop
 for container in
 '(book list periodical user)
 do
 (eval
  `(defun
       ,(intern (format "emacsvox-bookshare-%s-handler"
                        (symbol-name container)))
       (element)
     "Process children silently."
     (mapc #'emacsvox-bookshare-apply-handler (dom-children element)))))

(defun emacsvox-bookshare-apply-handler (element)
  "Lookup and apply installed handler."
  (let* ((tag (dom-tag element))
         (handler  (emacsvox-bookshare-handler-get tag)))
    (cond
     ((and handler (fboundp handler))
      (funcall handler element))
     (t ; Can't get here:
      (insert (format "Handler for %s not implemented yet.\n" tag))))))

(defun emacsvox-bookshare-bookshare-handler (response)
  "Handle Bookshare response."
  (unless (eq (dom-tag response) 'bookshare)
    (error "Got %s: Expected <bookshare>" (dom-tag response)))
  (mapc #'emacsvox-bookshare-apply-handler (dom-children response)))

(defalias 'emacsvox-bookshare-version-handler 'ignore)
(defalias 'emacsvox-bookshare-debugInfo-handler 'ignore)

(defun emacsvox-bookshare-recurse (tree)
  "Recurse down tree."
  (insert (format "Begin %s:\n" (dom-tag tree)))
  (mapc #'emacsvox-bookshare-apply-handler (dom-children tree))
  (insert (format "\nEnd %s\n" (dom-tag tree))))

(defun emacsvox-bookshare-messages-handler (messages)
  "Handle messages element."
  
  (let ((start (point)))
    (mapc #'insert(dom-text   (dom-child-by-tag messages 'string)))
    (insert "\t")
    (insert
     (mapconcat
      #'identity
      (emacsvox-bookshare-destruct-rest-url
       emacsvox-bookshare-last-action-uri)
      " "))
    (add-text-properties  start (point)
                          (list 'uri emacsvox-bookshare-last-action-uri
                                'face 'font-lock-string-face))
    (insert "\n")))

(defun emacsvox-bookshare-status-code-handler (status-code)
  "Handlestatus-code element."
  
  (let ((start (point)))
    (message "Status-Code: %s" (dom-text    status-code))
    (insert "Status Code: ")
    (mapc #'insert (dom-text    status-code))
    (insert "\t")
    (insert
     (mapconcat
      #'identity
      (emacsvox-bookshare-destruct-rest-url
       emacsvox-bookshare-last-action-uri)
      " "))
    (add-text-properties  start (point)
                          (list 'uri emacsvox-bookshare-last-action-uri
                                'face 'font-lock-string-face))
    (insert "\n")))

(defun emacsvox-bookshare-page-handler (page)
  "Handle page element."
  (insert (format "Page: %s\t" (dom-text page))))

(defun emacsvox-bookshare-limit-handler (limit)
  "Handle limit element."
  (insert (format "Limit: %s\t" (dom-text limit))))

(defun emacsvox-bookshare-num-pages-handler (num-pages)
  "Handle num-pages element."
  (insert (format "Num-Pages: %s\n" (dom-text num-pages))))

(defun emacsvox-bookshare-display-setting (result)
  "Display user setting result."
  (mapc #'emacsvox-bookshare-apply-handler (dom-children result)))

(defun emacsvox-bookshare-result-handler (result)
  "Handle result element in Bookshare response."
  (insert "\n")
  (cond
   ((dom-child-by-tag result 'editable) ;handle settings
    (emacsvox-bookshare-display-setting result))
   (t ;Book Result
    (let ((start (point))
          (id (dom-text (dom-child-by-tag result 'id)))
          (title (emacsvox-bookshare-dom-clean-text result 'title))
          (author (emacsvox-bookshare-dom-clean-text result 'author))
          (directory nil)
          (target nil)
          (face nil)
          (icon nil))
      (unless ; We found a meaningful author or title
          (and (zerop (length title)) (zerop (length author)))
        (setq
         directory (emacsvox-bookshare-generate-directory author title)
         target (emacsvox-bookshare-generate-target author title))
                                        ;Render  with formatted properties
        (cond
         ((file-exists-p directory)
          (setq face 'highlight
                icon 'item))
         ((file-exists-p target)
          (setq face 'bold
                icon 'select-object))))
      (when title (insert (format "%s\t" title)))
      (when author
        (while (< (current-column)50)
          (insert "\t"))
        (insert (format "By %s" author)))
      (untabify start (point))
      (add-text-properties
       start (point)
       (list
        'author author 'title title 'id id
        'directory directory 'target target
        'face face 'auditory-icon icon))))))

(defvar emacsvox-bookshare-metadata-filtered-elements
  '(author bookshare-id brf content-id
           daisy images download-format title)
  "Elements in Bookshare Metadata that we filter.")

(defvar emacsvox-bookshare-leaf-elements
  '(string downloads-remaining
           id name value editable)
  "Leaf level elements, just print element name: children.")

(cl-loop
 for e in
 emacsvox-bookshare-leaf-elements
 do
 (eval
  `(defun
       ,(intern (format "emacsvox-bookshare-%s-handler" (symbol-name e)))
       (element)
     ,(format "Handle leaf-level element  %s. " e)
     (insert (format "%s:\t" ,e))
     (mapc #'insert (dom-children  element))
     (insert "\n"))))

(defun emacsvox-bookshare-metadata-handler (metadata)
  "Handle metadata element."
  
  (let* ((children (dom-children metadata))
         (available (dom-by-tag metadata 'download-format))
         (display
          (cl-remove-if
           #'(lambda (c)
               (member (dom-tag c)
                       emacsvox-bookshare-metadata-filtered-elements))
           children)))
    ;;; First render generic metadata items to display
    (mapc
     #'(lambda (child)
         (let ((start (point)))
           (insert
            (format "%s: "
                    (capitalize (symbol-name (dom-tag child)))))
           (put-text-property start (point)
                              'face 'highlight)
           (insert
            (format "%s\n"
                    (xml-substitute-special
                     (xml-substitute-numeric-entities
                      (dom-text child)))))
           (fill-region-as-paragraph start (point))))
     (sort
      display
      #'(lambda (a b)
          (string-lessp (symbol-name (car a)) (symbol-name (car b))))))
                                        ; Show availability:
    (insert
     (format "Available: %s"
             (mapconcat #'dom-text available " ")))))

;;;  Generate Declarations:
(declare-function emacsvox-bookshare-get-author    "emacsvox-bookshare" nil)
(declare-function emacsvox-bookshare-get-title    "emacsvox-bookshare" nil)
(declare-function emacsvox-bookshare-get-id    "emacsvox-bookshare" nil)
(declare-function emacsvox-bookshare-get-metadata
                  "emacsvox-bookshare" nil)
(declare-function emacsvox-bookshare-get-target    "emacsvox-bookshare" nil)
(declare-function emacsvox-bookshare-get-directory "emacsvox-bookshare" nil)

;;  
(cl-loop for p in
         '(author title id metadata target directory)
         do
         (eval
          `(defun ,(intern (format "emacsvox-bookshare-get-%s" p)) ()
             ,(format "Auto-generated function: Get %s at point. " p)
             (get-text-property (point) ',p))))

;;;  Bookshare Mode:

(defun emacsvox-bookshare-define-keys ()
  "Define keys for  Bookshare Interaction."
  
  (cl-loop for k in
           '(
             ("e" emacsvox-bookshare-eww)
             ("q" bury-buffer)
             ("f" emacsvox-bookshare-flush-lines)
             ("v" emacsvox-bookshare-view)
             ("c" emacsvox-bookshare-toc-at-point)
             ("\C-m" emacsvox-bookshare-toc-at-point)
             ("M-n" emacsvox-bookshare-next-result)
             ("n" emacsvox-bookshare-next-result)
             ("p" emacsvox-bookshare-previous-result)
             ("M-p" emacsvox-bookshare-previous-result)
             ("["  backward-page)
             ("]" forward-page)
             ("b" emacsvox-bookshare-browse)
             ("SPC" emacsvox-bookshare-expand-at-point)
             ("U" emacsvox-bookshare-unpack-at-point)
             ("A" emacsvox-bookshare-download-audio-at-point)
             ("3" emacsvox-bookshare-download-epub-3-at-point)
             ("V" emacsvox-bookshare-view-at-point)
             ("C" emacsvox-bookshare-fulltext)
             ("D" emacsvox-bookshare-download-daisy-at-point)
             ("E" emacsvox-bookshare-eww)
             ("B" emacsvox-bookshare-download-brf-at-point)
             ("j" next-line)
             ("k" previous-line)
             )
           do
           (emacsvox-keymap-update  emacsvox-bookshare-mode-map k)))

(emacsvox-bookshare-define-keys)

(defvar emacsvox-bookshare-interaction-buffer "*Bookshare*"
  "Buffer for Bookshare interaction.")

;;;###autoload
(defun emacsvox-bookshare ()
  "Bookshare  Interaction."
  (interactive)
  
  (let ((buffer (get-buffer emacsvox-bookshare-interaction-buffer)))
    (cond
     ((buffer-live-p buffer)
      (switch-to-buffer buffer))
     (t
      (with-current-buffer
          (get-buffer-create emacsvox-bookshare-interaction-buffer)
        (setq buffer-undo-list  t)
        (erase-buffer)
        (setq buffer-read-only t)
        (emacsvox-bookshare-mode))
      (switch-to-buffer emacsvox-bookshare-interaction-buffer)))
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))
;; All actions such as searches are handled here.
;; This is also the 
;; top-level entry point for parsing the response.
;; We expect the response to be in a bookshare element.
;; We initiate the recursive descent parse in the function below.

(defun emacsvox-bookshare-action  ()
  "Call action specified by  invoking key."
  (interactive)
  (emacsvox-bookshare-assert)
  (goto-char (point-max))
  (let* ((inhibit-read-only t)
         (key (format "%c" last-input-event))
         (start nil)
         (response (call-interactively (emacsvox-bookshare-action-get key))))
    (insert "\n\f\n")
    (setq start (point))
    (emacsvox-bookshare-bookshare-handler response) ;  recursive descent 
    (goto-char start)
    (emacsvox-icon 'task-done)
    (emacsvox-speak-line)))

(defun emacsvox-bookshare-browse ()
  "Browse Bookshare."
  (interactive)
  (let ((action (read-char "p Popular, l Latest")))
    (cl-case action
      (?p (call-interactively 'emacsvox-bookshare-action))
      (?l (call-interactively 'emacsvox-bookshare-action))
      (otherwise (error "Unrecognized browse action.")))))

(defun emacsvox-bookshare-expand-at-point ()
  "Expand entry at point by retrieving metadata.
Once retrieved, memoize to avoid multiple retrievals."
  (interactive)
  (emacsvox-bookshare-assert)
  (emacsvox-icon 'open-object)
  (let* ((inhibit-read-only t)
         (id (emacsvox-bookshare-get-id))
         (author (emacsvox-bookshare-get-author))
         (title (emacsvox-bookshare-get-title))
         (target (emacsvox-bookshare-generate-target author title))
         (metadata (emacsvox-bookshare-get-metadata))
         (start nil)
         (response (emacsvox-bookshare-id-search id)))
    (cond
     (metadata (message "Entry already expanded."))
     (t
      (add-text-properties (line-beginning-position)
                           (line-end-position)
                           (list  'metadata t))
      (goto-char (line-end-position))
      (insert "\n")
      (setq start (point))
      (emacsvox-bookshare-bookshare-handler response)
      (add-text-properties start (point)
                           (list 'metadata t 'id id 'target target))
      (indent-rigidly start (point) 4)
      (emacsvox-speak-region start (point))))
    (goto-char start)
    (emacsvox-icon 'large-movement)))

(defun emacsvox-bookshare-download-daisy-at-point ()
  "Download Daisy version of book under point.
Target location is generated from author and title."
  (interactive)
  (let* ((inhibit-read-only t)
         (id (emacsvox-bookshare-get-id))
         (author (emacsvox-bookshare-get-author))
         (title (emacsvox-bookshare-get-title))
         (target (emacsvox-bookshare-generate-target author title)))
    (emacsvox-icon 'select-object)
    (cond
     ((file-exists-p target)
      (message "This content is available locally at %s" target))
     (t
      (cond
       ((zerop (emacsvox-bookshare-download-daisy id target))
        (add-text-properties
         (line-beginning-position) (line-end-position)
         (list'face 'bold
                    'auditory-icon 'select-object))
        (emacsvox-icon 'task-done)
        (message "Downloaded content to %s" target))
       (t
        (let ((new (read-from-minibuffer "Retry with new target:" target)))
          (if (zerop (emacsvox-bookshare-download-daisy id new))
              (message "Downloaded to %s" new)
            (error "Error downloading to %s" new)))))))))

(defun emacsvox-bookshare-download-audio-at-point ()
  "Download audio version of book under point.
Target location is generated from author and title."
  (interactive)
  (let* ((inhibit-read-only t)
         (id (emacsvox-bookshare-get-id))
         (author (emacsvox-bookshare-get-author))
         (title (emacsvox-bookshare-get-title))
         (target (emacsvox-bookshare-generate-target author title "audio")))
    (emacsvox-icon 'select-object)
    (cond
     ((file-exists-p target)
      (message "This content is available locally at %s" target))
     (t
      (cond
       ((zerop (emacsvox-bookshare-download-audio id target))
        (add-text-properties
         (line-beginning-position) (line-end-position)
         (list'face 'bold
                    'auditory-icon 'select-object))
        (emacsvox-icon 'task-done)
        (message "Downloaded content to %s" target))
       (t
        (let ((new (read-from-minibuffer "Retry with new target:" target)))
          (if (zerop (emacsvox-bookshare-download-audio id new))
              (message "Downloaded to %s" new)
            (error "Error downloading to %s" new)))))))))

(defun emacsvox-bookshare-download-epub-3-at-point ()
  "Download epub-3 version of book under point.
Target location is generated from author and title."
  (interactive)
  (let* ((inhibit-read-only t)
         (id (emacsvox-bookshare-get-id))
         (author (emacsvox-bookshare-get-author))
         (title (emacsvox-bookshare-get-title))
         (target (emacsvox-bookshare-generate-target author title "epub-3")))
    (emacsvox-icon 'select-object)
    (cond
     ((file-exists-p target)
      (message "This content is available locally at %s" target))
     (t
      (cond
       ((zerop (emacsvox-bookshare-download-epub-3 id target))
        (add-text-properties
         (line-beginning-position) (line-end-position)
         (list'face 'bold
                    'auditory-icon 'select-object))
        (emacsvox-icon 'task-done)
        (message "Downloaded content to %s" target))
       (t
        (let ((new (read-from-minibuffer "Retry with new target:" target)))
          (if (zerop (emacsvox-bookshare-download-epub-3 id new))
              (message "Downloaded to %s" new)
            (error "Error downloading to %s" new)))))))))

(defun emacsvox-bookshare-download-brf-at-point ()
  "Download Braille version of book under point.
Target location is generated from author and title."
  (interactive)
  (let* ((inhibit-read-only t)
         (id (emacsvox-bookshare-get-id))
         (author (emacsvox-bookshare-get-author))
         (title (emacsvox-bookshare-get-title))
         (target (emacsvox-bookshare-generate-target author title)))
    (emacsvox-icon 'select-object)
    (cond
     ((file-exists-p target)
      (message "This content is available locally at %s" target))
     (t
      (cond
       ((zerop (emacsvox-bookshare-download-brf id target))
        (add-text-properties
         (line-beginning-position) (line-end-position)
         (list'face 'bold
                    'auditory-icon 'select-object))
        (emacsvox-icon 'task-done)
        (message "Downloaded content to %s" target))
       (t (error "Error downloading content.")))
      (emacsvox-icon 'task-done)
      (message "Downloading content to %s" target)))))

(defun emacsvox-bookshare-unpack-at-point ()
  "Unpack downloaded content if necessary."
  (interactive)
  (emacsvox-bookshare-assert)
  (let ((inhibit-read-only t)
        (target (emacsvox-bookshare-get-target))
        (directory nil))
    (when (null target) (error  "No downloaded content here."))
    (unless   (file-exists-p target) (error "First download this content."))
    (setq directory (emacsvox-bookshare-get-directory))
    (when (file-exists-p directory) (error "Already unpacked."))
    (make-directory directory 'parents)
    (shell-command
     (format "cd \"%s\"; unzip -P %s %s"
             directory
             (cdr (emacsvox-bookshare-get-auth-info))
             target))
    (add-text-properties
     (line-beginning-position) (line-end-position)
     (list'face 'highlight
                'auditory-icon 'item))
    (message "Unpacked content.")))

(defconst emacsvox-bookshare-xslt
  "daisyTransform.xsl"
  "Name of bookshare  XSL transform.")

(defun emacsvox-bookshare-xslt (directory)
  "Return suitable XSL  transform."
  (cl-declare (special emacsvox-bookshare-xslt
                       emacsvox-xslt-directory))
  (let ((xsl (expand-file-name emacsvox-bookshare-xslt directory)))
    (cond
     ((file-exists-p xsl) xsl)
     (t (expand-file-name emacsvox-bookshare-xslt emacsvox-xslt-directory)))))

(defconst emacsvox-bookshare-toc-xslt
  "bookshare-toc.xsl"
  "Name of bookshare supplied XSL transform.")

(defun emacsvox-bookshare-toc-xslt ()
  "Return suitable XSL  transform for TOC."
  (cl-declare (special emacsvox-bookshare-toc-xslt
                       emacsvox-xslt-directory))

  (expand-file-name emacsvox-bookshare-toc-xslt emacsvox-xslt-directory))
(declare-function emacsvox-xslt-view-file "emacsvox-xslt" (style file))

(defun emacsvox-bookshare-view-at-point ()
  "View book at point.
Make sure it's downloaded and unpacked first."
  (interactive)
  (let* ((target (emacsvox-bookshare-get-target))
         (directory (emacsvox-bookshare-get-directory))
         (xsl (emacsvox-bookshare-xslt  directory)))
    (unless (file-exists-p target)
      (error "First download this content."))
    (unless (file-exists-p directory)
      (error "First unpack this content."))
    (emacsvox-xslt-view-file
     xsl
     (cl-first
      (directory-files directory 'full "\\.xml\\'")))))

(defun emacsvox-bookshare-url-executor (url)
  "Custom URL executor for use in Bookshare TOC."
  (interactive "sURL: ")
  (cond
   ((string-match "#" url)
    (emacsvox-bookshare-extract-and-view url))
   ((char-equal ??  (aref url (1- (length url))))
    (emacsvox-bookshare-view-page-range (substring url 0 -1)))
   (t (error "Doesn't look like a bookshare-specific URL."))))

(defun emacsvox-bookshare-toc-at-point ()
  "View TOC for book at point.
Make sure it's downloaded and unpacked first."
  (interactive)
  (let ((target (emacsvox-bookshare-get-target))
        (directory (emacsvox-bookshare-get-directory))
        (xsl (emacsvox-bookshare-toc-xslt)))
    (cond
     ((null target) (call-interactively 'emacsvox-bookshare-toc))
     (t
      (unless (file-exists-p target)
        (error "First download this content."))
      (unless (file-exists-p directory)
        (error "First unpack this content."))
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda ()
           
           (setq emacsvox-we-url-executor 'emacsvox-bookshare-url-executor)
           (emacsvox-speak-mode-line)
           (emacsvox-icon 'open-object)))
      (emacsvox-xslt-view-file
       xsl
       (shell-quote-argument
        (cl-first
         (directory-files directory 'full "\\.xml\\'"))))))))

(defun emacsvox-bookshare-extract-xml (url)
  "Extract content referred to by link under point, and return an XML buffer."
  (interactive "sURL: ")
  
  (let ((fields (split-string url "#"))
        (id nil)
        (url nil))
    (unless (= (length fields) 2)
      (error "No fragment identifier in this link."))
    (setq url (cl-first fields)
          id (cl-second fields))
    (emacsvox-xslt-url
     emacsvox-we-xsl-filter
     url
     (emacsvox-xslt-params-from-xpath
      (format "//*[@id=\"%s\"]" id) url))))

(defun emacsvox-bookshare-extract-and-view (url)
  "Extract content referred to by link under point, and render via the browser."
  (interactive "sURL: ")
  (cl-declare (special emacsvox-bookshare-browser-function
                       emacsvox-xslt-directory))
  (let ((result (emacsvox-bookshare-extract-xml url))
        (browse-url-browser-function emacsvox-bookshare-browser-function))
    (save-current-buffer
      (set-buffer result)
      (emacsvox-eww-autospeak)
      (browse-url-of-buffer))))

(defun emacsvox-bookshare-view-page-range (url)
  "Play pages in specified page range from URL."
  (interactive "sURL:")
  
  (let* ((start (read-from-minibuffer "Start Page: "))
         (end (read-from-minibuffer "End Page: "))
         (result
          (emacsvox-xslt-xml-url
           (emacsvox-xslt-get "dtb-page-range.xsl")
           (substring url 7)
           (list
            (cons "start" (format "'%s'" start))
            (cons "end" (format "'%s'" end)))))
         (browse-url-browser-function emacsvox-bookshare-browser-function))
    (save-current-buffer
      (set-buffer result)
      (emacsvox-eww-autospeak)
      (browse-url-of-buffer))
    (kill-buffer result)))

(defun emacsvox-bookshare-view (directory)
  "View book in specified directory."
  (interactive
   (list
    (let ((completion-ignore-case t)
          (emacsvox-speak-messages nil)
          (read-file-name-completion-ignore-case t))
      (read-directory-name "Book: "
                           (when (eq major-mode 'dired-mode)
                             (dired-get-filename))
                           emacsvox-bookshare-directory))))
  
  (let* ((xsl (emacsvox-bookshare-xslt directory)))
    (emacsvox-xslt-view-file
     xsl
     (cl-first
      (directory-files directory 'full "\\.xml\\'")))))

(defun emacsvox-bookshare-toc (directory)
  "View TOC for book in specified directory."
  (interactive
   (list
    (let ((completion-ignore-case t)
          (emacsvox-speak-messages nil)
          (read-file-name-completion-ignore-case t))
      (read-directory-name "Book: "
                           (when (eq major-mode 'dired-mode)
                             (dired-get-filename))
                           emacsvox-bookshare-directory))))
  
  (let* ((xsl (emacsvox-bookshare-toc-xslt)))
    (add-hook
     'emacsvox-eww-post-hook
     #'(lambda ()
         
         (setq emacsvox-we-url-executor 'emacsvox-bookshare-url-executor)))
    (emacsvox-xslt-view-file
     xsl
     (cl-first (directory-files directory 'full "\\.xml\\'")))))

(defvar emacsvox-bookshare-html-to-text-command
  "lynx -dump -stdin"
  "Command to convert html to text on stdin.")

(defun emacsvox-bookshare-fulltext (directory)
  "Display fulltext contents of  book in specified directory.
Useful for fulltext search in a book."
  (interactive
   (list
    (or (emacsvox-bookshare-get-directory)
        (let ((completion-ignore-case t)
              (emacsvox-speak-messages nil)
              (read-file-name-completion-ignore-case t))
          (read-directory-name "Book: "
                               (when (eq major-mode 'dired-mode)
                                 (dired-get-filename))
                               emacsvox-bookshare-directory)))))
  
  (cl-declare (special emacsvox-bookshare-html-to-text-command
                       emacsvox-bookshare-directory))
  (let ((xsl (emacsvox-bookshare-xslt directory))
        (buffer (get-buffer-create "Full Text"))
        (command nil)
        (inhibit-read-only t))
    (with-current-buffer buffer
      (setq command
            (format
             "%s  --nonet --novalid %s %s | %s"
             emacsvox-xslt xsl
             (shell-quote-argument
              (cl-first (directory-files directory 'full "\\.xml\\'")))
             emacsvox-bookshare-html-to-text-command))
      (erase-buffer)
      (setq buffer-undo-list  t)
      (shell-command command (current-buffer) nil)
      (setq buffer-read-only t)
      (goto-char (point-min)))
    (switch-to-buffer buffer)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))
(defvar-local emacsvox-bookshare-this-book nil
  "Record current book in buffer where it is rendered.")
;;;###autoload
(defun emacsvox-bookshare-eww (directory)
  "Render  book using EWW"
  (interactive
   (list
    (or
     (emacsvox-bookshare-get-directory)
     (when (eq major-mode 'dired-mode) (dired-get-filename))
     (let ((completion-ignore-case t)
           (emacsvox-speak-messages nil)
           (read-file-name-completion-ignore-case t))
       (completing-read
        "Book: "
        (ems--subdirs-recursively emacsvox-bookshare-directory)
        #'(lambda (d)
            (cl-some
             #'(lambda (f) (string-match "\\.ncx$" f))
             (directory-files d))
            ))))))
  (cl-declare (special eww-data
                       emacsvox-xslt emacsvox-bookshare-directory
                       emacsvox-speak-directory-settings
                       emacsvox-bookshare-this-book))
  (let ((xsl (emacsvox-bookshare-xslt directory))
        (buffer (get-buffer-create "Full Text"))
        (command nil)
        (inhibit-read-only t))
    (with-current-buffer buffer
      (setq command
            (format
             "%s  --nonet --novalid %s %s "
             emacsvox-xslt xsl
             (shell-quote-argument
              (cl-first (directory-files directory 'full "\\.xml\\'")))))
      (erase-buffer)
      (setq buffer-undo-list  t)
      (shell-command command (current-buffer) nil)
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda nil
           (setq
            emacsvox-bookshare-this-book directory
            default-directory directory)
           (emacsvox-speak-load-directory-settings directory)
           (plist-put eww-data :source nil)
           (plist-put eww-data :dom nil)
           (emacsvox-icon 'open-object)
           (emacsvox-speak-mode-line)))
      (browse-url-of-buffer)
      (kill-buffer buffer))))

;;;  Navigation in  Bookshare Interaction

(defun emacsvox-bookshare-next-result ()
  "Move to next result."
  (interactive)
  (goto-char (line-end-position))
  (goto-char (next-single-property-change (point) 'id))
  (emacsvox-icon 'select-object)
  (forward-char 1)
  (emacsvox-speak-line))

(defun emacsvox-bookshare-previous-result()
  "Move to previous result."
  (interactive)
  (goto-char (previous-single-property-change (point) 'id))
  (beginning-of-line)
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(defun emacsvox-bookshare-flush-lines(regexp)
  "Flush lines matching regexp in Bookshare buffer."
  (interactive "sRegexp: ")
  (save-excursion
    (let ((inhibit-read-only t))
      (goto-char (next-single-property-change (point-min) 'face))
      (flush-lines regexp (point) (point-max)))))

(provide 'emacsvox-bookshare)
;;;  end of file

