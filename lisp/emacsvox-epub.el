;;; emacsvox-epub.el --- epubs for  desktop -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, epubs Digital Talking Books
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

;; @subsection Introduction
;; 
;; This module implements the Emacsvox EPub
;; Bookshelf --- a unified interface for organizing, locating and
;; reading EPub EBooks on the emacsvox Audio Desktop. The epub
;; reader is built using the Emacs Web Browser (EWW), and all of
;; emacsvox's EWW conveniences are available when reading EBooks ---
;; see @xref{emacsvox-eww} for useful tools including bookmarking
;; and structured navigation. For now it supports epub2 --- it will
;; support epub3 some time in the future.

;; The main entry point is command @command{emacsvox-epub} bound to
;; @kbd{C-e g}. This command opens a new bookshelf buffer unless the
;; user has previously opened a specific bookshelf. A
;; @strong{bookshelf} is a buffer that lists books placed on a given
;; bookshelf --- these are listed by @strong{title} and
;; @strong{author}. The bookshelf buffer is in a special mode that
;; provides single-key commands for adding, removing and finding
;; books, as well as for opening the selected book using Emacs'
;; built-in Web browser (@command{eww}).
;; 
;; The next few sections give a high-level overview of the emacsvox
;; Bookshelf and EPub interaction, followed by detailed documentation
;; on the various commands and user options.

;; @subsection Organizing EBooks On The Emacsvox Desktop
;; 
;; In the simplest case, EBooks can be placed under a specific
;; directory (with sub-directories as needed).
;; Customize   user option @code{emacsvox-epub-library-directory}
;; to point to this location.
;; Here is  a quick summary of commands for
;; organizing, saving and opening  a bookshelf:
;; 
;; @table @kbd
;; @item a
;; emacsvox-epub-bookshelf-add-epub
;; @item b
;; emacsvox-epub-bookshelf-open
;; @item c
;; emacsvox-epub-bookshelf-clear
;; @item d
;; emacsvox-epub-bookshelf-remove-this-book
;; @item r
;; emacsvox-epub-bookshelf-rename
;; @item l
;; emacsvox-epub-locate-epubs
;; @item C-a
;; emacsvox-epub-bookshelf-add-directory
;; @item C-d
;; emacsvox-epub-bookshelf-remove-directory
;; @item C-l
;; emacsvox-epub-bookshelf-redraw
;; @item C-o
;; emacsvox-epub-bookshelf-open-epub
;; @item M-s
;; emacsvox-epub-bookshelf-save
;; @item C-x C-q
;; emacsvox-epub-bookshelf-refresh
;; @item C-x C-s
;; emacsvox-epub-bookshelf-save
;; @end table
;; 
;; @subsection Integrating With Project Gutenberg
;; 
;; Gutenberg integration provides one-shot commands for downloading
;; the latest copy of the Gutenberg catalog and  finding and downloading
;; the desired epub for offline reading.
;; 
;; @table @kbd
;; @item C
;; emacsvox-epub-gutenberg-catalog
;; @item g
;; emacsvox-epub-gutenberg-download
;; @end table
;; Once downloaded, these EBooks can be
;; organized under  @code{emacsvox-epub-library-directory}
;; For  more advanced usage, see the next section
;; on integrating with Calibre catalogs.
;; 
;; @subsection Calibre Integration
;; 
;; Project Calibre enables the indexing and searching of large EBook
;; collections.  Read the Calibre documentation for organizing and
;; indexing your EBook library.  See user options named
;; @code{emacsvox-epub-calibre-*} for customizing emacsvox to work
;; with Calibre.  Once set up, Calibre integration provides the
;; following commands from the @strong{bookshelf} buffer:
;; 
;; @table @kbd
;; @item /
;; emacsvox-epub-calibre-results
;; @item A
;; emacsvox-epub-bookshelf-calibre-author
;; @item S
;; emacsvox-epub-bookshelf-calibre-search
;; @item T
;; emacsvox-epub-bookshelf-calibre-title
;; @end table
;; 
;; @subsection Reading EBooks From The Bookshelf
;; 
;; The most efficient means to read an EBook is to have EWW render
;; the entire book --- this works well even for very large EBooks
;; given that EWW is efficient at rendering HTML. Rendering the
;; entire book means that all of the contents are available for
;; searching. To view an EBook in its entirety, use command
;; @code{emacsvox-epub-eww}. You can open the EPub table of contents
;; with command @code{emacsvox-epub-open}; for a
;; well-constructed epub, this TOC should provide hyperlinks to each
;; section listed in the table of contents.
;; 
;; @table @kbd
;; @item RET
;; emacsvox-epub-eww
;; @item e
;; emacsvox-epub-eww
;; @item f
;; emacsvox-epub-browse-files
;; @item o
;; emacsvox-epub-open
;; @end table

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-epub-calibre-results)
(defvar emacsvox-epub-calibre-root-dir)
(defvar emacsvox-epub-db)
(defvar emacsvox-epub-db-file)
(defvar emacsvox-epub-gutenberg-cat)
(defvar emacsvox-epub-gutenberg-catalog-url)
(defvar emacsvox-epub-gutenberg-mirror)
(defvar emacsvox-epub-gutenberg-suffix)
(defvar emacsvox-epub-interaction-buffer)
(defvar emacsvox-epub-library-directory)
(defvar emacsvox-epub-scratch)
(defvar emacsvox-epub-this-epub)
(defvar emacsvox-epub-unzip)
(defvar emacsvox-epub-wget)
(defvar emacsvox-epub-zipinfo)
(defvar emacsvox-speak-directory-settings)
(defvar emacsvox-we-url-executor)
(defvar epub-this-epub)
(defvar eww-data)
(defvar locate-command)
(defvar locate-make-command-line)

;; Required Modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'dired)
(require 'emacsvox-xslt)
(require 'eww)
(require 'emacsvox-eww)
(eval-when-compile
  (require 'derived)
  (require 'subr-x))
(require 'dom)
;;; Executables:
;; unzip, wget, zipinfo
(defconst emacsvox-epub-find (executable-find "find") "Find utility")

(defconst emacsvox-epub-wget (executable-find "wget")
  "WGet Executable.")

(defconst emacsvox-epub-unzip (executable-find "unzip")
  "Unzip Executable.")

(defconst emacsvox-epub-zipinfo (executable-find "zipinfo")
  "Zipinfo Executable.")

;;;   Customizations, Variables:

(defgroup emacsvox-epub nil
  "Epubs Digital  Books  for the Emacsvox desktop."
  :group 'emacsvox)

(defcustom emacsvox-epub-library-directory
  (expand-file-name "~/EBooks/")
  "Directory under which we store Epubs."
  :type 'directory
  :group 'emacsvox-epub)

;;;  EPub Implementation:
;; Helper: dom from file in archive
(defsubst emacsvox-epub-dom-from-archive (epub-file file &optional xml-p)
  "Return DOM from specified file in epub archive."
  
  (with-temp-buffer
    (setq buffer-undo-list  t)
    (shell-command
     (format
      "%s -c -qq %s %s "
      emacsvox-epub-unzip
      epub-file
      (shell-quote-argument file))
     (current-buffer))
    (cond
     (xml-p (libxml-parse-xml-region (point-min) (point-max)))
     (t (libxml-parse-html-region (point-min) (point-max))))))

(defvar emacsvox-epub-toc-path-pattern
  ".ncx$"
  "Pattern match for path component  to table of contents in an Epub.")

(defvar emacsvox-epub-toc-command
  (format "%s -1 %%s | grep %s"
          emacsvox-epub-zipinfo
          emacsvox-epub-toc-path-pattern)
  "Command that returns location of .ncx file in an epub archive.")

(defun emacsvox-epub-do-toc (file)
  "Return location of .ncx file within epub archive."
  
  (let ((result
         (shell-command-to-string (format emacsvox-epub-toc-command  file))))
    (cond
     ((= 0 (length result)) nil)
     (t (substring result 0 -1)))))

(defun emacsvox-epub-get-contents (epub element)
  "Return buffer containing contents of element from epub."
  
  (unless   (emacsvox-epub-p epub) (error "Not an EPub object."))
  (unless (member element (emacsvox-epub-ls epub))
    (error "Element not found in EPub. "))
  (let ((buffer (get-buffer-create emacsvox-epub-scratch)))
    (with-current-buffer buffer
      (setq buffer-undo-list  t)
      (erase-buffer)
      (call-process emacsvox-epub-unzip
                    nil t nil
                    "-c" "-qq"
                    (emacsvox-epub-shell-unquote (emacsvox-epub-path epub))
                    element))
    buffer))

(defun emacsvox-epub-nav-files (this-epub)
  "Return ordered list of content files from navMap."
  (let* ((navs nil)
         (hash (make-hash-table :test 'equal))
         (value nil)
         (toc (emacsvox-epub-toc this-epub))
         (base (emacsvox-epub-base this-epub))
         (ncx nil))
    (with-current-buffer (emacsvox-epub-get-contents this-epub toc)
      (setq ncx (libxml-parse-xml-region (point-min) (point-max)))
      (kill-buffer))
    (cl-loop
     for n in (dom-by-tag ncx 'content)
     do
     (setq value
           (concat base (cl-first (split-string (dom-attr n 'src) "#"))))
     (unless (gethash value hash)
       (puthash value 1 hash)
       (push value navs)))
    (nreverse navs)))

(defvar emacsvox-epub-opf-path-pattern
  ".opf$"
  "Pattern match for path component  to table of contents in an Epub.")

(defvar emacsvox-epub-opf-command
  (format "%s -1 %%s | grep %s"
          emacsvox-epub-zipinfo
          emacsvox-epub-opf-path-pattern)
  "Command that returns location of .opf file in an epub archive.")

(defun emacsvox-epub-do-opf (file)
  "Return location of .opf file within epub archive."
  
  (substring
   (shell-command-to-string (format emacsvox-epub-opf-command file))
   0 -1))

(defvar emacsvox-epub-ls-command
  (format "%s -1 %%s | sort" emacsvox-epub-zipinfo)
  "Shell command that returns sorted list of files in an epub archive.")

(defun emacsvox-epub-do-ls (file)
  "Return sorted list of files in an epub archive."
  
  (split-string
   (shell-command-to-string (format emacsvox-epub-ls-command file))))

(cl-defstruct emacsvox-epub
  path                       ; path to .epub file
  toc                        ; path to .ncx file in archive
  base                       ; directory in archive that holds toc.ncx
  opf                        ; path to content.opf
  opf-dom ; parsed content of content.opf
  ls                                 ; list of files in archive
  html                               ; html files in archive
  navs                               ; content files found from navMap
  title  author
  )

(defun emacsvox-epub-make-epub  (epub-file)
  "Construct an epub object given an epub filename."
  (let ((path (expand-file-name epub-file))
        (this nil)
        (ls (emacsvox-epub-do-ls epub-file))
        (toc (emacsvox-epub-do-toc epub-file))
        (opf (emacsvox-epub-do-opf epub-file))
        (opf-dom nil)
        (title nil)
        (author nil))
    (unless (> (length opf) 0) (error "No Package --- Not a valid EPub?"))
    (unless (> (length toc) 0) (error "No TOC --- Not a valid EPub?"))
    (setq opf-dom (emacsvox-epub-dom-from-archive path opf 'xml))
    (setq title (dom-inner-text (dom-by-tag opf-dom 'title))
          author (dom-inner-text (dom-by-tag opf-dom 'creator)))
    (when (zerop (length author)) (setq author "Unknown"))
    (when (zerop (length title)) (setq title "Untitled"))
    (setq this 
          (make-emacsvox-epub
           :path path
           :title title
           :author author
           :toc toc
           :base (file-name-directory toc)
           :opf opf
           :opf-dom opf-dom
           :ls ls
           :html
           (cl-remove-if-not #'(lambda (s) (string-match "\\.x?html$" s)) ls)))
    (setf (emacsvox-epub-navs this)  (emacsvox-epub-nav-files this))
    this))

(defvar emacsvox-epub-scratch " *epub-scratch*"
  "Scratch buffer used to process epub.")

(defun emacsvox-epub-shell-unquote (f)
  "Reverse effect of shell-quote-argument."
  (shell-command-to-string (format "echo -n %s" f)))

(defvar-local emacsvox-epub-this-epub nil
  "EPub associated with current buffer.")

(defun emacsvox-epub-browse-content (epub element _ffragment &optional style)
  "Browse content in specified element of EPub."
  
  (unless   (emacsvox-epub-p epub) (error "Invalid epub"))
  (let ((base (emacsvox-epub-base epub))
        (content nil)
        (emacsvox-xslt-options "--nonet --novalid")
        (emacsvox-we-xsl-p nil))
    (unless (string-match (format "^%s" base) element)
      (setq element (concat base element)))
    (setq content (emacsvox-epub-get-contents epub element))
    (add-hook
     'emacsvox-eww-post-hook
     #'(lambda nil
         (emacsvox-speak-load-directory-settings)
         (setq emacsvox-epub-this-epub epub
               emacsvox-we-url-executor 'emacsvox-epub-url-executor)
         (emacsvox-speak-rest-of-buffer))
     'at-end)
    (with-current-buffer content
      (when style
        (emacsvox-xslt-region style   (point-min) (point-max)))
      (browse-url-of-buffer))))

(defun emacsvox-epub-browse-files (epub)
  "Browse list of HTML files in  EPub.
Useful if table of contents in toc.ncx is empty."
  (interactive
   (list
    (emacsvox-epub-make-epub
     (or
      (get-text-property (point) 'epub)
      (read-file-name "EPub File: ")))))
  
  (let ((files (emacsvox-epub-html epub)))
    (with-current-buffer (get-buffer-create emacsvox-epub-scratch)
      (erase-buffer)
      (insert  "<ol>\n")
      (cl-loop for f in files
               do
               (insert
                (format "<li><a href=\"%s\">%s</a></li>\n" f f)))
      (insert "</ol>\n")
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda nil
           (setq emacsvox-epub-this-epub epub
                 emacsvox-we-url-executor 'emacsvox-epub-url-executor)
           (emacsvox-speak-buffer))
       'at-end)
      (browse-url-of-buffer))))

(defconst epub-toc-xsl (emacsvox-xslt-get "epub-toc.xsl")
  "XSL to process .ncx file.")

(defun emacsvox-epub-browse-toc (epub)
  "Browse table of contents from an EPub."
  
  (unless   (emacsvox-epub-p epub) (error "Invalid epub"))
  (let ((toc (emacsvox-epub-toc epub)))
    (emacsvox-epub-browse-content epub toc nil epub-toc-xsl)))

(defun emacsvox-epub-url-executor (url)
  "Custom URL executor for use in EPub Mode."
  (interactive "sURL: ")
  (unless emacsvox-epub-this-epub (error "Not an EPub document."))
  (cond
   ((not (string-match "^http://" url)) ; relative url
    (when (string-match "^cid:" url) (setq url (substring url 4)))
    (when (string-match "^file:" url)
      (setq url  (cl-second (split-string url  "/tmp/"))))
    (let* ((fields (split-string url "#"))
           (locator (cl-first fields))
           (fragment (cl-second fields)))
      (when fragment (setq fragment (format "#%s" fragment)))
      (add-hook
       'emacsvox-eww-post-hook
       #'(lambda nil (ems--fastload emacsvox-speak-directory-settings)))
      (emacsvox-epub-browse-content
       emacsvox-epub-this-epub locator fragment)))
   (t (browse-url url))))

;;;  Epub Mode:

(defun emacsvox-epub-format-author (name)
  "Format author name, abbreviating if needed."
  (let ((len (length name))
        (fields nil))
    (cond
     ((< len 16))
     (t (setq  fields (split-string name))
        (let ((count (length fields))
              (result nil))
          (cond
           ((= 1 count))
           (t
            (setq result
                  (cl-loop for i from 0 to(- count 2)
                           collect
                           (upcase (aref  (nth i fields) 0))))
            (setq result
                  (mapconcat
                   #'(lambda (c) (format "%c" c))
                   result ". "))
            (setq name (format "%s. %s"
                               result
                               (nth (1- count) fields))))))))
    (propertize name 'face 'font-lock-type-face)))

(defun emacsvox-epub-insert-title-author (key epub)
  "Insert a formatted line of the bookshelf of the form Title --- Author."
  (let ((start (point)))
    (insert
     (format
      "%-60s%s\n"
      (propertize (emacsvox-epub-metadata-title epub) 'face 'italic)
      (emacsvox-epub-format-author (emacsvox-epub-metadata-author epub))))
    (put-text-property start (point) 'epub key)))

(defun emacsvox-epub-insert-author-title (key epub)
  "Insert a formatted line of the bookshelf of the form Author --- Title ."
  (let ((start (point)))
    (insert
     (format
      "%-20s%s\n"
      (emacsvox-epub-format-author (emacsvox-epub-metadata-author epub))
      (propertize (emacsvox-epub-metadata-title epub) 'face 'italic)))
    (put-text-property start (point) 'epub key)))

(defun emacsvox-epub-bookshelf-redraw (&optional author-first)
  "Redraw Bookshelf.
Optional interactive prefix arg author-first prints author at the
  left."
  (interactive "P")
  
  (let ((inhibit-read-only t)
        (formatter (if author-first
                       #'emacsvox-epub-insert-author-title
                     #'emacsvox-epub-insert-title-author)))
    (erase-buffer)
    (maphash formatter emacsvox-epub-db)
    (sort-lines nil (point-min) (point-max))
    (goto-char (point-min)))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'task-done)))

(defun emacsvox-epub-bookshelf-refresh ()
  "Refresh and redraw bookshelf."
  (interactive)
  (unless (eq major-mode 'emacsvox-epub-mode)
    (error "Not in the EPub Bookshelf."))
  (emacsvox-epub-bookshelf-load)
  (emacsvox-epub-bookshelf-update)
  (emacsvox-epub-bookshelf-redraw)
  (emacsvox-epub-bookshelf-save)
  (emacsvox-icon 'task-done))

(define-derived-mode emacsvox-epub-mode special-mode
  "EPub Bookshelf"
  "An EPub Front-end.
Letters do not insert themselves; instead, they are commands.
\\{emacsvox-epub-mode-map}"
  (setq buffer-undo-list  t)
  (setq header-line-format
        (propertize "EPub Bookshelf" 'face 'bold))
  (goto-char (point-min))
  (cd-absolute emacsvox-epub-library-directory)
  (emacsvox-epub-bookshelf-refresh))

(cl-declaim (special emacsvox-epub-mode-map))
(cl-loop
 for k in
 '(
   ("/" emacsvox-epub-calibre-results)
   ("O" emacsvox-epub-open-with-nov)
   ("A" emacsvox-epub-bookshelf-calibre-author)
   ("S" emacsvox-epub-bookshelf-calibre-search)
   ("T" emacsvox-epub-bookshelf-calibre-title)
   ("C" emacsvox-epub-gutenberg-catalog)
   ("G" emacsvox-epub-google)
   ("\C-a" emacsvox-epub-bookshelf-add-directory)
   ("\C-d" emacsvox-epub-bookshelf-remove-directory)
   ("\C-k" emacsvox-epub-delete)
   ("C-l" emacsvox-epub-bookshelf-redraw)
   ("\C-m" emacsvox-epub-eww)
   ("\C-o" emacsvox-epub-bookshelf-open-epub)
   ("\C-x\C-q" emacsvox-epub-bookshelf-refresh)
   ("\C-x\C-s" emacsvox-epub-bookshelf-save)
   ("M-s" emacsvox-epub-bookshelf-save)
   ("a" emacsvox-epub-bookshelf-add-epub)
   ("b" emacsvox-epub-bookshelf-open)
   ("c" emacsvox-epub-bookshelf-clear)
   ("d" emacsvox-epub-bookshelf-remove-this-book)
   ("e" emacsvox-epub-eww)
   ("f" emacsvox-epub-browse-files)
   ("g" emacsvox-epub-gutenberg-download)
   ("l" emacsvox-epub-locate-epubs)
   ("n" next-line)
   ("o" emacsvox-epub-open)
   ("p" previous-line)
   ("r" emacsvox-epub-bookshelf-rename)
   ("RET" emacsvox-epub-eww)
   )
 do
 (emacsvox-keymap-update emacsvox-epub-mode-map k))

;;;  Bookshelf Implementation:
(defcustom emacsvox-epub-bookshelf-directory
  (file-name-as-directory
   (expand-file-name "bsf" emacsvox-epub-library-directory))
  "Directory where we keep .bsf files defining various bookshelves."
  :type 'directory
  :group 'emacsvox-epub)

(defvar emacsvox-epub-db-file
  (expand-file-name ".bookshelf.bsf" emacsvox-epub-library-directory)
  "Cache of bookshelf metadata.")

(defvar emacsvox-epub-db (make-hash-table :test  #'equal)
  "In memory cache of epub bookshelf.")

(cl-defstruct emacsvox-epub-metadata
  title
  author)

(defun emacsvox-epub-bookshelf-update ()
  "Update bookshelf metadata."
  (let ((updated nil)
        (filename nil))
    (cl-loop
     for f in
     (directory-files emacsvox-epub-library-directory  'full "\\.epub\\'")
     do
     (setq filename (shell-quote-argument f))
     (unless
         (gethash filename emacsvox-epub-db)
       (setq updated t)
       (let* ((epub (emacsvox-epub-make-epub filename))
              (title (emacsvox-epub-title epub))
              (author  (emacsvox-epub-author epub)))
         (setf (gethash filename emacsvox-epub-db)
               (make-emacsvox-epub-metadata :title title :author author)))))
    (cl-loop for f being the hash-keys of emacsvox-epub-db
             do
             (setq filename (emacsvox-epub-shell-unquote f))
             (unless (file-exists-p filename) (remhash f emacsvox-epub-db)))
    (when updated (emacsvox-epub-bookshelf-save))))

(defun emacsvox-epub-find-epubs-in-directory (directory)
  "Return a list of all epub files under directory dir."
  
  (with-temp-buffer
    (call-process emacsvox-epub-find
                  nil t nil
                  (expand-file-name directory)
                  "-type" "f"
                  "-name" "*.epub")
    (delete ""
            (split-string (buffer-substring (point-min)
                                            (point-max))
                          "\n"))))
(defun emacsvox-epub-bookshelf-rename (name &optional overwrite)
  "Saves current bookshelf to  specified name.
Interactive prefix arg `overwrite' will overwrite existing file."
  (interactive "sBookshelf Name: \nP")
  
  (setq name (format "%s.bsf" name))
  (let ((bookshelf
         (expand-file-name ".bookshelf.bsf" emacsvox-epub-library-directory))
        (bsf (expand-file-name name emacsvox-epub-bookshelf-directory)))
    (when (and overwrite (file-exists-p bsf)) (delete-file bsf))
    (copy-file bookshelf bsf)
    (message "Copied current bookshelf to %s" name)))

(defun emacsvox-epub-bookshelf-add-directory (directory &optional recursive)
  "Add EPubs found in specified directory to the bookshelf.
Interactive prefix arg searches recursively in directory."
  (interactive "DAdd books from Directory: \nP")
  
  (let ((updated 0)
        (filename nil))
    (cl-loop
     for f in
     (if recursive
         (emacsvox-epub-find-epubs-in-directory directory)
       (directory-files directory  'full "epub"))
     do
     (setq filename (shell-quote-argument f))
     (unless
         (gethash filename emacsvox-epub-db)
       (cl-incf updated)
       (let* ((epub (emacsvox-epub-make-epub filename))
              (title (emacsvox-epub-title epub))
              (author  (emacsvox-epub-author epub)))
         (setf (gethash filename emacsvox-epub-db)
               (make-emacsvox-epub-metadata :title title :author author)))))
    (unless (zerop updated)
      (emacsvox-epub-bookshelf-save)
      (emacsvox-epub-bookshelf-redraw)
      (message "Added %d books. " updated))))

(defun emacsvox-epub-bookshelf-add-epub (epub-file)
  "Add epub file to current bookshelf."
  (interactive "fAdd Book: ")
  
  (let* ((filename (shell-quote-argument (expand-file-name epub-file)))
         
         (epub (emacsvox-epub-make-epub filename))
         (title (emacsvox-epub-title epub))
         (author  (emacsvox-epub-author epub)))
    (setf (gethash filename emacsvox-epub-db)
          (make-emacsvox-epub-metadata :title title :author author))
    (emacsvox-epub-bookshelf-save)
    (emacsvox-epub-bookshelf-redraw)
    (goto-char (point-min))
    (search-forward title)
    (emacsvox-speak-line)))

(defun emacsvox-epub-bookshelf-open-epub (epub-file)
  "Open epub file and add it to current bookshelf."
  (interactive "fAdd Book: ")
  
  (let* ((filename (shell-quote-argument epub-file))
         (epub (emacsvox-epub-make-epub filename))
         (title (emacsvox-epub-title epub))
         (author  (emacsvox-epub-author epub)))
    (setf (gethash filename emacsvox-epub-db)
          (make-emacsvox-epub-metadata :title title :author author))
    (emacsvox-epub-bookshelf-save)
    (emacsvox-epub-bookshelf-redraw)
    (goto-char (point-min))
    (search-forward title)
    (call-interactively 'emacsvox-epub-open)))

(defun emacsvox-epub-bookshelf-remove-directory (directory &optional recursive)
  "Remove EPubs found in specified directory from the bookshelf.
Interactive prefix arg searches recursively in directory."
  (interactive "DRemove Directory: \nP")
  
  (let ((updated 0)
        (filename nil))
    (cl-loop
     for f in
     (if recursive
         (emacsvox-epub-find-epubs-in-directory directory)
       (directory-files directory  'full "epub"))
     do
     (setq filename (shell-quote-argument f))
     (when (gethash filename emacsvox-epub-db)
       (cl-incf updated)
       (remhash filename emacsvox-epub-db)))
    (unless (zerop updated)
      (emacsvox-epub-bookshelf-save)
      (emacsvox-epub-bookshelf-redraw)
      (message "Removed %d books. " updated))))

(defun emacsvox-epub-bookshelf-remove-this-book ()
  "Remove the book on current line from this bookshelf.
No book files are deleted."
  (interactive)
  
  (let ((epub (get-text-property (point) 'epub))
        (orig (point)))
    (when epub
      (remhash epub emacsvox-epub-db)
      (emacsvox-epub-bookshelf-save)
      (emacsvox-epub-bookshelf-redraw)
      (emacsvox-icon 'task-done)
      (goto-char orig)
      (emacsvox-speak-line))))

(defun emacsvox-epub-bookshelf-clear ()
  "Clear all books from bookshelf."
  (interactive)
  
  (when
      (or (not (called-interactively-p 'interactive))
          (y-or-n-p "Clear bookshelf?"))
    (clrhash emacsvox-epub-db)
    (setq header-line-format
          (propertize "EPub Bookshelf" 'face 'bold))
    (emacsvox-epub-bookshelf-save)
    (emacsvox-epub-bookshelf-redraw)
    (message "Cleared bookshelf.")))

(defun emacsvox-epub-bookshelf-save ()
  "Save bookshelf metadata."
  (interactive)
  
  (let ((buff (find-file-noselect emacsvox-epub-db-file))
        (emacsvox-speak-messages nil)
        (print-length  nil)
        (print-level nil))
    (save-current-buffer
      (set-buffer buff)
      (setq buffer-undo-list  t)
      (erase-buffer)
      (print  emacsvox-epub-db  buff)
      (save-buffer buff)
      (kill-buffer buff)
      (when (called-interactively-p 'interactive)
        (emacsvox-icon 'save-object)))))

(defun emacsvox-epub-bookshelf-load ()
  "Load bookshelf metadata from disk."
  (interactive)
  
  (when (file-exists-p emacsvox-epub-db-file)
    (let ((buffer (find-file-noselect emacsvox-epub-db-file)))
      (with-current-buffer buffer
        (goto-char (point-min))
        (setq emacsvox-epub-db (read buffer)))
      (kill-buffer buffer))))

(defun emacsvox-epub-bookshelf-open (bookshelf)
  "Load bookshelf metadata from specified bookshelf."
  (interactive
   (list
    (read-file-name "BookShelf: "
                    (expand-file-name emacsvox-epub-bookshelf-directory)
                    nil t nil
                    #'(lambda (s) (string-match "\\.bsf\\'" s)))))
  
  (let ((buffer (find-file-noselect bookshelf))
        (bookshelf-name  (substring (file-name-nondirectory bookshelf) 0 -4)))
    (with-current-buffer buffer
      (goto-char (point-min))
      (setq emacsvox-epub-db (read buffer)))
    (kill-buffer buffer)
    (emacsvox-epub-bookshelf-redraw)
    (setq header-line-format
          (propertize
           (format "EPub Bookshelf: %s" bookshelf-name)
           'face 'bold))
    (emacsvox-icon 'open-object)
    (emacsvox-speak-header-line)))

;;;  Interactive Commands:

(defvar emacsvox-epub-interaction-buffer "*EPub*"
  "Buffer for EPub interaction.")

;;;###autoload
(defun emacsvox-epub ()
  "EPub  Interaction.
When opened, displays a bookshelf consisting of  epubs found at the
root directory,see \\[emacsvox-epub-mode]"
  (interactive)
  (unless emacsvox-epub-unzip
    (error "Please install unzip."))
  (unless emacsvox-epub-zipinfo
    (error "Please install zipinfo. "))
  (let ((buffer (get-buffer emacsvox-epub-interaction-buffer)))
    (unless (buffer-live-p buffer)
      (with-current-buffer
          (get-buffer-create emacsvox-epub-interaction-buffer)
        (emacsvox-epub-mode)))
    (pop-to-buffer emacsvox-epub-interaction-buffer)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(defun emacsvox-epub-open (epub-file)
  "Open specified Epub.
Filename may need to  be shell-quoted when called from Lisp."
  (interactive
   (list
    (or
     (get-text-property (point) 'epub)
     (read-file-name "EPub: " emacsvox-epub-library-directory))))
  (let ((e (emacsvox-epub-make-epub epub-file)))
    (emacsvox-epub-browse-toc e)))

(defvar-local epub-this-epub nil
  "EPub handle.")

(declare-function eww-update-header-line-format "eww" nil)
;;;###autoload
(defun emacsvox-epub-eww (epub-file &optional use-ncx)
  "Display entire book  using EWW from EPub.
Use content listed in toc.ncx  if prefix-arg use-ncx is true.
Default is to  use   the sorted list of html files
in the epub file."
  (interactive
   (list
    (or
     (get-text-property (point) 'epub)
     (when (eq major-mode 'dired-mode) (dired-get-filename))
     (let ((completion-ignore-case t)
           (emacsvox-speak-messages nil)
           (read-file-name-completion-ignore-case t))
       (shell-quote-argument
        (completing-read
         "Book: "
         (directory-files-recursively
          emacsvox-epub-library-directory
          "\\.epub$" 'include-dirs)))))
    current-prefix-arg))
  (let* ((emacsvox-speak-messages nil)
         (directory
          (string-trim
           (shell-command-to-string
            (format "cd %s; pwd"
                    (file-name-directory epub-file)))))
         (eww-epub (get-buffer-create "Full Text EPub"))
         (this-epub (emacsvox-epub-make-epub epub-file))
         (navs (emacsvox-epub-navs this-epub))
         (html (emacsvox-epub-html this-epub))
         (dom nil)
         (inhibit-read-only t))
    (cl-loop
     for f in
     (if use-ncx navs html)
     do
     (setq dom (emacsvox-epub-dom-from-archive epub-file f))
     (with-current-buffer eww-epub
       (setq buffer-undo-list  t)
       (shr-insert-document (dom-by-tag dom 'body))))
    (with-current-buffer eww-epub
      (eww-mode)
      (setq
       emacsvox-epub-this-epub epub-file
       epub-this-epub this-epub
       default-directory directory)
      (emacsvox-speak-load-directory-settings directory)
      (rename-buffer
       (format
        "%s: %s"
        (emacsvox-epub-title this-epub) (emacsvox-epub-author this-epub))
       'unique)
      (plist-put eww-data :author (emacsvox-epub-author this-epub))
      (plist-put eww-data :title (emacsvox-epub-title this-epub))
      (eww-update-header-line-format)
      (plist-put eww-data :source nil)
      (plist-put eww-data :dom nil)
      (when emacsvox-eww-post-hook
        (emacsvox-eww-run-post-process-hook))
      (goto-char (point-min))
      (emacsvox-icon 'open-object))
    (funcall-interactively #'switch-to-buffer eww-epub)))

(defvar emacsvox-epub-google-search-template
  (concat  "http://books.google.com/books/feeds/volumes?"
           "min-viewability=full&epub=epub&q=%s")
  "REST  end-point for performing Google Books Search
to find Epubs  having full viewability.")

(defun emacsvox-epub-google (query)
  "Search for Epubs from Google Books."
  (interactive "sGoogle Books Query: ")
  
  (emacsvox-feeds-atom-display
   (format emacsvox-epub-google-search-template
           (url-hexify-string query))))

(defun emacsvox-epub-next ()
  "Move to next book."
  (interactive)
  (end-of-line)
  (goto-char (next-single-property-change (point) 'epub))
  (beginning-of-line)
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(defun emacsvox-epub-previous ()
  "Move to previous book."
  (interactive)
  (beginning-of-line)
  (goto-char (previous-single-property-change (point) 'epub))
  (beginning-of-line)
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(defun emacsvox-epub-delete ()
  "Delete EPub under point."
  (interactive)
  (let ((file (get-text-property (point) 'epub)))
    (cond
     ((null file) (error "No EPub under point."))
     (t (when (y-or-n-p
               (format "Delete %s" file))
          (delete-file file)
          (emacsvox-epub-bookshelf-refresh)
          (emacsvox-icon 'delete-object))))))

;;;  Gutenberg Hookup:

;; Offline Catalog:
;; http://www.gutenberg.org/wiki/Gutenberg:Offline_Catalogs
;;; Goal:
;; Snapshot catalog, enable local searches, and pull desired book to local cache
;; using appropriate recipe.
;; http://www.gutenberg.org/ebooks/<bookid>.epub.?noimages?
(defcustom emacsvox-epub-gutenberg-mirror
  "http://www.gutenberg.org/ebooks/"
  "Base URL  for Gutenberg mirror."
  :type 'string
  :group 'emacsvox-epub)

(defcustom emacsvox-epub-gutenberg-suffix ".epub.noimages"
  "Suffix of book type we retrieve."
  :type 'string
  :group 'emacsvox-epub)

(defun emacsvox-epub-gutenberg-download-uri (book-id)
  "Return URL  for downloading Gutenberg EBook."
  (format "%s%s%s"
          emacsvox-epub-gutenberg-mirror
          book-id
          emacsvox-epub-gutenberg-suffix))

(defun emacsvox-epub-gutenberg-browse-uri (book-id)
  "Return URL  for browsing Gutenberg EBook."
  (format "%s%s"
          emacsvox-epub-gutenberg-mirror book-id))

(defun emacsvox-epub-gutenberg-download (book-id &optional download)
  "Open web page for specified book.
Place download url for epub in kill ring.
With interactive prefix arg `download', download the epub."
  (interactive
   (list (read-from-minibuffer "Book-Id:")
         current-prefix-arg))
  (let ((file
         (expand-file-name
          (format "%s%s" book-id emacsvox-epub-gutenberg-suffix)
          emacsvox-epub-library-directory))
        (browse (emacsvox-epub-gutenberg-browse-uri book-id))
        (url (emacsvox-epub-gutenberg-download-uri book-id)))
    (cond
     ((file-exists-p file)
      (browse-url browse)
      (message "Book available locally as %s" file))
     (t (kill-new   url)
        (browse-url browse)
        (when download
          (shell-command
           (format"%s -O %s '%s'"
                  emacsvox-epub-wget file url))
          (message "Downloaded content to %s" file))))))

(defvar emacsvox-epub-gutenberg-catalog-url
  "http://www.gutenberg.org/dirs/GUTINDEX.ALL"
  "URL to Gutenberg index.")

(defvar emacsvox-epub-gutenberg-cat
  (expand-file-name "catalog/GUTINDEX.ALL" emacsvox-epub-library-directory)
  "Local filename of catalog.")

(defun emacsvox-epub-gutenberg-catalog (&optional refresh)
  "Open Gutenberg catalog.
Fetch if needed, or if refresh is T."
  (interactive "P")
  (unless emacsvox-epub-wget
    (error "Please install wget. "))
  (unless
      (file-exists-p (file-name-directory emacsvox-epub-gutenberg-cat))
    (make-directory
     (file-name-directory emacsvox-epub-gutenberg-cat) 'parents))
  (when (or refresh
            (not (file-exists-p emacsvox-epub-gutenberg-cat)))
    (call-process
     emacsvox-epub-wget
     nil nil nil
     "-O"
     emacsvox-epub-gutenberg-cat
     emacsvox-epub-gutenberg-catalog-url))
  (view-file-other-window emacsvox-epub-gutenberg-cat)
  (emacsvox-icon 'task-done))

;;;  Calibre Hookup:

;; Inspired by https://github.com/whacked/calibre-mode.git

(defcustom emacsvox-epub-calibre-root-dir
  (expand-file-name "calibre" emacsvox-epub-library-directory)
  "Root of Calibre library."
  :type 'directory
  :group 'emacsvox-epub)

(defconst   emacsvox-epub-sqlite
  (eval-when-compile (executable-find "sqlite3"))
  "Path to sqlite3.")

(defvar emacsvox-epub-calibre-db
  (expand-file-name "metadata.db" emacsvox-epub-calibre-root-dir)
  "Calibre database.")

;; Record returned by queries:

(cl-defstruct emacsvox-epub-calibre-record
  ;; "b.title,  b.author_sort, b.path,  d.format"
  title author  path format)

;; Helper: Construct query
(defun emacsvox-epub-calibre-build-query (where &optional limit)
  "Build a Calibre query as SQL statement.
Argument  `where' is a simple SQL where clause."
  (concat
   "select "
   "b.title,  b.author_sort, b.path,  d.format"
   " from data as d "
   "left outer join books as b on d.book = b.id "
   " where "
   where
   (when limit (format "limit %s" limit))))

(defun emacsvox-epub-calibre-query (pattern)
  "Return  search query matching `pattern'.
Searches for matches in both  Title and Author."
  (emacsvox-epub-calibre-build-query
   (format
    "lower(b.author_sort) LIKE '%%%s%%' OR lower(b.title) LIKE '%%%s%%' "
    (downcase pattern) (downcase pattern))))

(defun emacsvox-epub-calibre-title-query (pattern)
  "Return title search query matching `pattern'."
  (emacsvox-epub-calibre-build-query
   (format "lower(b.title) like '%%%s%%' "
           (downcase pattern))))

(defun emacsvox-epub-calibre-author-query (pattern)
  "Return author search query matching `pattern'."
  (emacsvox-epub-calibre-build-query
   (format "lower(b.author_sort) like '%%%s%%' "
           (downcase pattern))))

(defun emacsvox-epub-calibre-get-results (query)
  "Execute query against Calibre DB, and return parsed results."
  
  (let ((fields nil)
        (result nil)
        (calibre (get-buffer-create " *Calibre Results *")))
    (with-current-buffer  calibre
      (erase-buffer)
      (setq buffer-undo-list  t)
      (shell-command
       (format
        "%s -list -separator '@@' %s \"%s\" 2>/dev/null"
        emacsvox-epub-sqlite emacsvox-epub-calibre-db query)
       calibre)
      (goto-char (point-min))
      (while (not (eobp))
        (setq fields
              (split-string
               (buffer-substring-no-properties
                (line-beginning-position)  (line-end-position))
               "@@"))
        (when (= (length fields) 4)
          (push
           (make-emacsvox-epub-calibre-record
            :title (cl-first fields)
            :author (cl-second fields)
            :path (cl-third fields)
            :format (cl-fourth fields))
           result))
        (forward-line 1)))
    result))

;;;  Add  to bookshelf using calibre search:

(defvar emacsvox-epub-calibre-results nil
  "Results from most recent Calibre search.")

(defun emacsvox-epub-bookshelf-calibre-search (pattern)
  "Add results of an title/author search to current bookshelf."
  (interactive "sSearch For: ")
  (unless (eq major-mode 'emacsvox-epub-mode)
    (error "Not in an Emacsvox Epub Bookshelf."))
  (let ((emacsvox-speak-messages nil)
        (results
         (emacsvox-epub-calibre-get-results
          (emacsvox-epub-calibre-query pattern))))
    (when (= 0 (length results)) (error "No results found, check query."))
    (cl-loop
     for r in results
     do
     (emacsvox-epub-bookshelf-add-directory
      (expand-file-name (emacsvox-epub-calibre-record-path r)
                        emacsvox-epub-calibre-root-dir)))
    (setq emacsvox-epub-calibre-results results)
    (message  (format "Added %d books" (length results)))))

(defun emacsvox-epub-bookshelf-calibre-author (pattern)
  "Add results of an author search to current bookshelf."
  (interactive "sAuthor: ")
  (unless (eq major-mode 'emacsvox-epub-mode)
    (error "Not in an Emacsvox Epub Bookshelf."))
  (let ((emacsvox-speak-messages nil)
        (results
         (emacsvox-epub-calibre-get-results
          (emacsvox-epub-calibre-author-query pattern))))
    (when (= 0 (length results)) (error "No results found, check query."))
    (cl-loop
     for r in results
     do
     (emacsvox-epub-bookshelf-add-directory
      (expand-file-name (emacsvox-epub-calibre-record-path r)
                        emacsvox-epub-calibre-root-dir)))
    (setq emacsvox-epub-calibre-results results)
    (message  (format "Added %d books" (length results)))))

(defun emacsvox-epub-bookshelf-calibre-title (pattern)
  "Add results of an title search to current bookshelf."
  (interactive "sTitle: ")
  (unless (eq major-mode 'emacsvox-epub-mode)
    (error "Not in an Emacsvox Epub Bookshelf."))
  (let ((emacsvox-speak-messages nil)
        (results
         (emacsvox-epub-calibre-get-results
          (emacsvox-epub-calibre-title-query pattern))))
    (when (= 0 (length results)) (error "No results found, check query."))
    (cl-loop
     for r in results
     do
     (emacsvox-epub-bookshelf-add-directory
      (expand-file-name (emacsvox-epub-calibre-record-path r)
                        emacsvox-epub-calibre-root-dir)))
    (setq emacsvox-epub-calibre-results results)
    (message  (format "Added %d books" (length results)))))

(define-derived-mode emacsvox-calibre-mode special-mode
  "Calibre Interaction On The Emacsvox Audio Desktop"
  "A Calibre Front-end.
Letters do not insert themselves; instead, they are commands.
\\<emacsvox-calibre-mode-map>
\\{emacsvox-calibre-mode-map}"
  (setq buffer-undo-list  t)
  (setq header-line-format
        (propertize "Calibre Results" 'face 'bold))
  (goto-char (point-min))
  (cd-absolute emacsvox-epub-library-directory))

(defun emacsvox-epub-calibre-dired-at-point ()
  "Open directory containing current result."
  (interactive)
  (unless (eq major-mode 'emacsvox-calibre-mode)
    (error "Not in a Calibre Results buffer"))
  (let ((path (get-text-property (point) 'path)))
    (unless path (error "No valid result here"))
    (dired (expand-file-name path emacsvox-epub-calibre-root-dir))
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(cl-declaim (special emacsvox-calibre-mode-map))
(define-key emacsvox-calibre-mode-map "\C-m"
            'emacsvox-epub-calibre-dired-at-point)

(defun emacsvox-epub-calibre-results ()
  "Show most recent Calibre search results."
  (interactive)
  
  (let ((inhibit-read-only  t)
        (buffer (get-buffer-create "*Calibre Results*"))
        (start nil))
    (with-current-buffer buffer
      (erase-buffer)
      (setq buffer-undo-list  t)
      (goto-char (point-min))
      (insert "Calibre Results\n\n")
      (cl-loop
       for r in emacsvox-epub-calibre-results
       do
       (setq start (point))
       (insert
        (format "%s\t%s\t%s"
                (emacsvox-epub-calibre-record-title r)
                (emacsvox-epub-calibre-record-author r)
                (emacsvox-epub-calibre-record-format r)))
       (put-text-property start (point)
                          'path (emacsvox-epub-calibre-record-path r))
       (insert "\n"))
      (setq buffer-read-only t)
      (emacsvox-calibre-mode)
      (goto-char (point-min))
      (forward-line 2))
    (switch-to-buffer buffer)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-line)))

;;;  Locate epub using Locate:
(defun emacsvox-epub-locate-epubs (pattern)
  "Locate epub files using locate."  (interactive "sSearch Pattern: ")
  
  (let ((locate-make-command-line #'(lambda (s) (list locate-command "-i" s))))
    (locate-with-filter pattern "\\.epub\\'")))

;;;  nov Integration:

(defun emacsvox-epub-open-with-nov ()
  "Open ebook at point in nov-mode."
  (interactive)
  (cl-assert (eq major-mode 'emacsvox-epub-mode)  nil  "Buffer is not
in emacsvox-epub-mode")
  (let ((epub (emacsvox-epub-shell-unquote (get-text-property (point) 'epub))))
    (cl-assert epub nil "No epub  at point.")
    (cl-assert (file-exists-p epub) nil "File does not exist")
    (unless (locate-library "nov") nil "Package nov is  not installed.")
    (funcall-interactively #'find-file epub)))

(provide 'emacsvox-epub)

;;; emacsvox-epub.el ends here
