;;; emacsvox-ocr.el --- ocr Front-end desktop  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for OCR
;; Keywords: Emacsvox, ocr
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4448 $ |
;; Location https://github.com/tvraman/emacsvox
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

;; This module defines Emacsvox front-end to OCR.
;; This module assumes that sane is installed and working
;; for image acquisition,
;; and that there is an OCR engine that can take acquired
;; images and produce text.
;;; Prerequisites:
;; Sane installed and working.
;; scanimage to generate tiff files from scanner.
;; tiffcp to compress the tiff file.
;; working ocr executable 
;; by default this module assumes that the OCR executable
;; is named "ocr"

;;; Code:

;;  required modules
(require 'emacsvox-preamble)

;;;   Customization variables
(defgroup emacsvox-ocr nil
  "Emacsvox front end for scanning and OCR.
Pre-requisites:
SANE for image acquisition.
OCR engine for optical character recognition."
  :group 'emacsvox
  :prefix "emacsvox-ocr-")

(defvar emacsvox-ocr-scan-image (executable-find "scanimage")
  "Name of image acquisition program.")

(defcustom emacsvox-ocr-scan-image-options 
  "--resolution 300 --mode lineart --format=tiff"
  "Command line options to pass to image acquisition program."
  :type 'string 
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-compress-image nil
  "Command used to compress the scanned tiff file."
  :type '(choice
          (const :tag "None" nil)
          (string :tag "Command"))
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-image-extension ".tif"
  "Filename extension used for acquired image."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-compress-image-options   
  "-c g3 "
  "Options used for compressing tiff image."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-engine
  (expand-file-name "tesseract.pl" emacsvox-etc-directory)
  "OCR engine to process acquired image."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-engine-options nil
  "Command line options to pass to OCR engine."
  :type'(repeat
         (string :tag "Option"))
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-working-directory
  (expand-file-name "ocr/"
                    emacsvox-user-directory)
  "Directory where images and OCR results
will be placed."
  :group 'emacsvox-ocr
  :type 'string)

(defcustom emacsvox-ocr-scan-photo-options 
  "--mode color --format=pnm"
  "Options  used when scanning in photographs."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-photo-compress "cjpeg"
  "Program to create JPEG compressed images."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-compress-photo-options
  "-optimize -progressive"
  "Options used when created JPEG from  scanned photographs."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-keep-uncompressed-image nil
  "If set to T, uncompressed image is not removed."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-jpeg-metadata-writer "wrjpgcom"
  "Program to add metadata to JPEG files."
  :type 'string
  :group 'emacsvox-ocr)

;;;   helpers

(defvar emacsvox-ocr-current-page-number  nil
  "Number of current page in document.")

(make-variable-buffer-local
 'emacsvox-ocr-current-page-number)

(defvar emacsvox-ocr-last-page-number nil
  "Number of last page in document.")

(make-variable-buffer-local 'emacsvox-ocr-last-page-number)

(defvar emacsvox-ocr-page-positions nil
  "Vector holding page start positions.")

(make-variable-buffer-local 'emacsvox-ocr-page-positions)

(defvar emacsvox-ocr-buffer-name "*ocr*"
  "Name of OCR working buffer.")

(defun emacsvox-ocr-get-buffer ()
  "Return OCR working buffer."
  (get-buffer-create
   (format  "*%s-ocr*"
            (emacsvox-ocr-default-name))))

(defun emacsvox-ocr-get-text-name ()
  "Return name of current text document."
  
  (format "%s.text" emacsvox-ocr-document-name))

(defun emacsvox-ocr-get-image-name (extension)
  "Return name of current image."
  (cl-declare (special emacsvox-ocr-document-name
                       emacsvox-ocr-last-page-number))
  (format "%s-p%s%s"
          emacsvox-ocr-document-name
          (1+ emacsvox-ocr-last-page-number)
          extension))

(defun emacsvox-ocr-get-page-name ()
  "Return name of current page."
  (cl-declare (special emacsvox-ocr-document-name
                       emacsvox-ocr-current-page-number))
  (format "%s-p%s.txt"
          emacsvox-ocr-document-name
          emacsvox-ocr-current-page-number))

(defvar emacsvox-ocr-mode-line-format
  '(
    (buffer-name)
    " "
    "page-"
    emacsvox-ocr-current-page-number
    "/"
    emacsvox-ocr-last-page-number)
  "Mode line format for OCR buffer.")

(defun emacsvox-ocr-get-mode-line-format ()
  "Return string suitable for use as the mode line."
  (cl-declare (special major-mode
                       emacsvox-ocr-current-page-number))
  (format "%s Page-%s/%s %s"
          (buffer-name)
          emacsvox-ocr-current-page-number
          emacsvox-ocr-last-page-number
          major-mode))

(defun emacsvox-ocr-update-mode-line()
  "Update mode line for OCR mode."
  
  (setq mode-line-format
        (emacsvox-ocr-get-mode-line-format)))

;;;   emacsvox-ocr mode
(cl-declaim (special emacsvox-ocr-mode-map))

(define-derived-mode emacsvox-ocr-mode text-mode 
  "Major mode for document scanning and  OCR.\n"
  " An OCR front-end for the Emacsvox desktop.

Pre-requisites:

1) A working scanner back-end like SANE on Linux.

2) An OCR engine.

1: Make sure your scanner back-end works, and that you have
the utilities to scan a document and acquire an image as a
tiff file.  Then set variable
emacsvox-ocr-scan-image-program to point at this utility.
By default, this is set to `scanimage' which is the image
scanning utility provided by SANE.

By default, this front-end attempts to compress the acquired
tiff image; make sure you have a utility like tiffcp.
Variable emacsvox-ocr-compress-image is set to `tiffcp' by
default; if you use something else, you should customize
this variable.

2: Next, make sure you have an OCR engine installed and
working.  By default this front-end assumes that OCR is
available as /usr/bin/ocr.

Once you have ensured that acquiring an image and applying
OCR to it work independently of Emacs, you can use this
Emacsvox front-end to enable easy OCR access from within
Emacsvox.

The Emacsvox OCR front-end is launched by command
emacsvox-ocr bound to \\[emacsvox-ocr].  

This command switches to a special buffer that has OCR
commands bounds to single keystrokes-- see the key-binding
list at the end of this description.  Use Emacs online help
facility to look up help on these commands.

emacsvox-ocr-mode provides the necessary functionality to
scan, OCR, read and save documents.  By default, scanned
images and the resulting text are saved under directory
~/ocr; see variable emacsvox-ocr-working-directory.
Invoking command emacsvox-ocr-open-working-directory bound
to \\[emacsvox-ocr-open-working-directory] will open this directory.

By default, the document being scanned is named `untitled'.
You can name the document by using command
emacsvox-ocr-name-document bound to
\\[emacsvox-ocr-name-document].  The document name is used
in constructing the name of the image and text files.

Key Bindings: 

See \\{emacsvox-ocr-mode-map}.
"
  (progn
    (setq emacsvox-ocr-current-page-number 0
          emacsvox-ocr-last-page-number 0
          emacsvox-ocr-page-positions
          (make-vector 25 nil))
    (emacsvox-ocr-update-mode-line)))

(define-key emacsvox-ocr-mode-map "?" 'describe-mode)
(define-key emacsvox-ocr-mode-map "c" 'emacsvox-ocr-customize)
(define-key emacsvox-ocr-mode-map "q" 'bury-buffer)
(define-key emacsvox-ocr-mode-map "w" 'emacsvox-ocr-write-document)
(define-key emacsvox-ocr-mode-map "\C-m"  'emacsvox-ocr-scan-and-recognize)
(define-key emacsvox-ocr-mode-map "i" 'emacsvox-ocr-scan-image)
(define-key emacsvox-ocr-mode-map "j" 'emacsvox-ocr-scan-photo)
(define-key emacsvox-ocr-mode-map "o" 'emacsvox-ocr-recognize-image)
(define-key emacsvox-ocr-mode-map
            "f" 'emacsvox-ocr-flipflop-and-recognize-image)
(define-key emacsvox-ocr-mode-map "n" 'emacsvox-ocr-name-document)
(define-key emacsvox-ocr-mode-map "d" 'emacsvox-ocr-open-working-directory)
(define-key emacsvox-ocr-mode-map "[" 'emacsvox-ocr-backward-page)
(define-key emacsvox-ocr-mode-map "]"'emacsvox-ocr-forward-page)
(define-key emacsvox-ocr-mode-map "p" 'emacsvox-ocr-page)
(define-key emacsvox-ocr-mode-map "s" 'emacsvox-ocr-save-current-page)
(define-key emacsvox-ocr-mode-map " "
            'emacsvox-ocr-read-current-page)
(define-key emacsvox-ocr-mode-map "I"
            'emacsvox-ocr-set-scan-image-options)
(define-key emacsvox-ocr-mode-map
            "C" 'emacsvox-ocr-set-compress-image-options)
(cl-loop for i from 1 to 9
         do
         (define-key emacsvox-ocr-mode-map
                     (format "%s" i)
                     'emacsvox-ocr-page))

;;;  interactive commands

(defun emacsvox-ocr-customize ()
  "Customize OCR settings."
  (interactive)
  (customize-group 'emacsvox-ocr)
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defun emacsvox-ocr-default-name ()
  "Return a default name for OCR document."
  (format-time-string "%m-%d-%y"))

;;;###autoload
(defun emacsvox-ocr ()
  "An OCR front-end for the Emacsvox desktop.  

Page image is acquired using tools from the SANE package.
The acquired image is run through the OCR engine if one is
available, and the results placed in a buffer that is
suitable for browsing the results.

For detailed help, invoke command emacsvox-ocr bound to
\\[emacsvox-ocr] to launch emacsvox-ocr-mode, and press
`?' to display mode-specific help for emacsvox-ocr-mode."
  (interactive)
  (cl-declare (special emacsvox-ocr-working-directory
                       emacsvox-ocr-document-name
                       buffer-read-only))
  (let  ((buffer (emacsvox-ocr-get-buffer)))
    (with-current-buffer buffer
      (emacsvox-ocr-mode)
      (when (file-exists-p emacsvox-ocr-working-directory)
        (cd emacsvox-ocr-working-directory))
      (switch-to-buffer buffer)
      (setq buffer-read-only t)
      (emacsvox-icon 'open-object)
      (setq emacsvox-ocr-document-name (emacsvox-ocr-default-name))
      (emacsvox-speak-mode-line))))

(defvar emacsvox-ocr-document-name nil
  "Names document being scanned.
This name will be used as the prefix for naming image and
text files produced in this scan.")

(make-variable-buffer-local 'emacsvox-ocr-document-name)

(defun emacsvox-ocr-name-document (name)
  "Name document being scanned in the current OCR buffer.
Pick a short but meaningful name."
  (interactive
   (list
    (read-from-minibuffer "Document name: ")))
  (cl-declare (special emacsvox-ocr-document-name
                       mode-line-format))
  (setq emacsvox-ocr-document-name name)
  (rename-buffer
   (format "*%s-ocr*" name)
   'unique)
  (emacsvox-ocr-update-mode-line)
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(defun emacsvox-ocr-scan-image ()
  "Acquire page image."
  (interactive)
  (cl-declare (special emacsvox-speak-messages
                       emacsvox-ocr-last-page-number
                       emacsvox-ocr-image-extension
                       emacsvox-ocr-keep-uncompressed-image
                       emacsvox-ocr-scan-image
                       emacsvox-ocr-scan-image-options
                       emacsvox-ocr-compress-image
                       emacsvox-ocr-compress-image-options
                       emacsvox-ocr-document-name))
  (let ((image-name (emacsvox-ocr-get-image-name
                     emacsvox-ocr-image-extension)))
    (let ((emacsvox-speak-messages nil))
      (shell-command
       (concat
        (format
         "%s %s > %s;\n"
         emacsvox-ocr-scan-image
         emacsvox-ocr-scan-image-options 
         (cond
          ((not emacsvox-ocr-compress-image) image-name)
          (t (format "temp%s" emacsvox-ocr-image-extension))))
        (when emacsvox-ocr-compress-image
          (format "%s %s  temp%s %s ;\n"
                  emacsvox-ocr-compress-image
                  emacsvox-ocr-compress-image-options
                  emacsvox-ocr-image-extension
                  image-name))
        (when emacsvox-ocr-keep-uncompressed-image
          (format "rm -f temp%s"
                  emacsvox-ocr-image-extension))))
      (when (called-interactively-p 'interactive)
        (setq emacsvox-ocr-last-page-number
              (1+ emacsvox-ocr-last-page-number)))
      (message "Acquired  image to file %s"
               image-name))))

(defun emacsvox-ocr-scan-photo (&optional metadata)
  "Scan in a photograph.
The scanned image is converted to JPEG."
  (interactive "P")
  (cl-declare (special emacsvox-speak-messages
                       emacsvox-ocr-jpeg-metadata-writer
                       emacsvox-ocr-photo-compress-options
                       emacsvox-ocr-scan-photo-options
                       emacsvox-ocr-keep-uncompressed-image
                       emacsvox-ocr-scan-image
                       emacsvox-ocr-compress-photo
                       emacsvox-ocr-image-extension
                       emacsvox-ocr-document-name))
  (let (
        (jpg (emacsvox-ocr-get-image-name ".jpg"))
        (pnm (emacsvox-ocr-get-image-name ".pnm")))
    (shell-command
     (concat
      (format "%s %s > temp.pnm;\n"
              emacsvox-ocr-scan-image
              emacsvox-ocr-scan-photo-options)
      (format "%s %s  temp.pnm > %s ;\n"
              emacsvox-ocr-compress-photo
              emacsvox-ocr-compress-photo-options
              jpg)
      (if emacsvox-ocr-keep-uncompressed-image
          (format "mv temp.pnm %s"
                  pnm)
        (format "rm -f temp.pnm"))))
    (when (and metadata
               (called-interactively-p 'interactive))
      (setq metadata
            (read-from-minibuffer "Enter picture description: "))
      (let ((tempfile (format "temp%s.jpg" (gensym))))
        (shell-command
         (format  "mv %s %s; %s -c '%s' %s > %s; rm -f %s"
                  jpg  tempfile
                  emacsvox-ocr-jpeg-metadata-writer metadata 
                  tempfile jpg
                  tempfile))))
    (message "Acquired  image to file %s" jpg)
    (setq emacsvox-ocr-last-page-number
          (1+ emacsvox-ocr-last-page-number))))

(defvar emacsvox-ocr-process nil
  "Handle to OCR process.")

(defun emacsvox-ocr-write-document ()
  "Writes out recognized text from all pages in current document."
  (interactive)
  (cond
   ((= 0 emacsvox-ocr-current-page-number)
    (message "No pages in current document."))
   (t (write-region
       (point-min)
       (point-max)
       (emacsvox-ocr-get-text-name))
      (emacsvox-icon 'save-object))))

(defun emacsvox-ocr-save-current-page ()
  "Writes out recognized text from current page
to an appropriately named file."
  (interactive)
  (cl-declare (special emacsvox-ocr-current-page-number
                       emacsvox-ocr-page-positions))
  (cond
   ((= 0 emacsvox-ocr-current-page-number)
    (message "No pages in current document."))
   (t (write-region
       (aref emacsvox-ocr-page-positions
             emacsvox-ocr-current-page-number)
       (if (= emacsvox-ocr-current-page-number
              emacsvox-ocr-last-page-number)
           (point-max)
         (aref emacsvox-ocr-page-positions
               (1+ emacsvox-ocr-current-page-number)))
       (emacsvox-ocr-get-page-name))
      (emacsvox-icon 'save-object))))

(defun emacsvox-ocr-process-sentinel  (_process _state)
  "Alert user when OCR is complete."
  (cl-declare (special emacsvox-ocr-page-positions
                       emacsvox-ocr-last-page-number
                       emacsvox-ocr-current-page-number))
  (setq emacsvox-ocr-current-page-number
        emacsvox-ocr-last-page-number)
  (emacsvox-icon 'task-done)
  (goto-char (aref emacsvox-ocr-page-positions
                   emacsvox-ocr-current-page-number))
  (emacsvox-ocr-save-current-page)
  (emacsvox-ocr-update-mode-line)
  (emacsvox-speak-line))

(defun emacsvox-ocr-recognize-image ()
  "Run OCR engine on current image.
Prompts for image file if file corresponding to the expected
`current page' is not found."
  (interactive)
  (cl-declare (special emacsvox-ocr-engine
                       emacsvox-ocr-engine-options
                       emacsvox-ocr-process
                       emacsvox-ocr-last-page-number
                       emacsvox-ocr-page-positions
                       emacsvox-ocr-image-extension))
  (let ((inhibit-read-only t)
        (image-name
         (if
             (file-exists-p
              (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension))
             (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension)
           (expand-file-name 
            (read-file-name "Image file to recognize: ")))))
    (goto-char (point-max))
    (emacsvox-icon 'select-object)
    (setq emacsvox-ocr-last-page-number
          (1+ emacsvox-ocr-last-page-number))
    (aset emacsvox-ocr-page-positions
          emacsvox-ocr-last-page-number
          (+ 3 (point)))
    (insert
     (format "\n%c\nPage %s\n" 12
             emacsvox-ocr-last-page-number))
    (setq emacsvox-ocr-process
          (apply 'start-process 
                 "ocr"
                 (current-buffer)
                 emacsvox-ocr-engine
                 image-name
                 emacsvox-ocr-engine-options))
    (set-process-sentinel emacsvox-ocr-process
                          'emacsvox-ocr-process-sentinel)
    (message "Launched OCR engine.")))

(defconst emacsvox-ocr-image-flipflop
  (executable-find "mogrify")
  "Executable used to transform images.")

(defun emacsvox-ocr-flipflop-and-recognize-image ()
  "Run OCR engine on current image after flip-flopping it.
Useful if you've scanned a page upside down and are using an
engine that does not automatically flip the image for you.  You
need the imagemagik family of tools --- we use mogrify to
transform the image.  Prompts for image file if file
corresponding to the expected `current page' is not found."
  (interactive)
  (cl-declare (special emacsvox-ocr-engine
                       emacsvox-ocr-image-flipflop
                       emacsvox-ocr-engine-options
                       emacsvox-ocr-process
                       emacsvox-ocr-last-page-number
                       emacsvox-ocr-page-positions
                       emacsvox-ocr-image-extension))
  (let ((inhibit-read-only t)
        (image-name
         (if
             (file-exists-p
              (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension))
             (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension)
           (expand-file-name 
            (read-file-name "Image file to recognize: ")))))
    (goto-char (point-max))
    (emacsvox-icon 'select-object)
    (setq emacsvox-ocr-last-page-number
          (1+ emacsvox-ocr-last-page-number))
    (aset emacsvox-ocr-page-positions
          emacsvox-ocr-last-page-number
          (+ 3 (point)))
    (insert
     (format "\n%c\nPage %s\n" 12
             emacsvox-ocr-last-page-number))
    (shell-command
     (format "%s -flip -flop %s"
             emacsvox-ocr-image-flipflop image-name))
    (setq emacsvox-ocr-process
          (apply 'start-process 
                 "ocr"
                 (current-buffer)
                 emacsvox-ocr-engine
                 image-name
                 emacsvox-ocr-engine-options))
    (set-process-sentinel emacsvox-ocr-process
                          'emacsvox-ocr-process-sentinel)
    (message "Launched OCR engine.")))

(defun emacsvox-ocr-scan-and-recognize ()
  "Scan in a page and run OCR engine on it.
Use this command once you've verified that the separate
steps of acquiring an image and running the OCR engine work
correctly by themselves."
  (interactive)
  (emacsvox-ocr-scan-image)
  (emacsvox-ocr-recognize-image))

(defun emacsvox-ocr-open-working-directory ()
  "Launch dired on OCR working directory."
  (interactive)
  
  (switch-to-buffer
   (dired-noselect emacsvox-ocr-working-directory))
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defun emacsvox-ocr-forward-page (&optional _count-ignored)
  "Like forward page, but tracks page number of current document."
  (interactive "p")
  (cl-declare (special emacsvox-ocr-page-positions
                       emacsvox-ocr-last-page-number
                       emacsvox-ocr-current-page-number))
  (cond
   ((= 0 emacsvox-ocr-current-page-number)
    (message "No pages in current document."))
   ((= emacsvox-ocr-last-page-number
       emacsvox-ocr-current-page-number)
    (goto-char
     (point-max))
    (emacsvox-icon 'select-object)
    (message "This is the last page."))
   (t (setq emacsvox-ocr-current-page-number
            (1+ emacsvox-ocr-current-page-number))
      (goto-char (aref emacsvox-ocr-page-positions
                       emacsvox-ocr-current-page-number))
      (emacsvox-ocr-update-mode-line)
      (emacsvox-speak-line)
      (emacsvox-icon 'large-movement))))

(defun emacsvox-ocr-backward-page (&optional _count-ignored)
  "Like backward page, but tracks page number of current document."
  (interactive "p")
  (cl-declare (special emacsvox-ocr-page-positions
                       emacsvox-ocr-current-page-number))
  (cond
   ((= 0 emacsvox-ocr-current-page-number)
    (message "No pages in current document."))
   ((= 1
       emacsvox-ocr-current-page-number)
    (goto-char
     (aref emacsvox-ocr-page-positions
           emacsvox-ocr-current-page-number))
    (emacsvox-icon 'select-object)
    (message "This is the first page."))
   (t (setq emacsvox-ocr-current-page-number
            (1- emacsvox-ocr-current-page-number))
      (emacsvox-ocr-update-mode-line)
      (goto-char (aref emacsvox-ocr-page-positions
                       emacsvox-ocr-current-page-number))
      (emacsvox-speak-line)
      (emacsvox-icon 'large-movement))))

(defun emacsvox-ocr-goto-page (page)
  "Move to specified page."
  
  (goto-char
   (aref emacsvox-ocr-page-positions page))
  (emacsvox-ocr-update-mode-line)
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line)
  )

(defun emacsvox-ocr-page ()
  "Move to specified page."
  (interactive)
  (when (= 0 emacsvox-ocr-last-page-number)
    (error "No pages in current document."))
  (let ((page
         (condition-case nil
             (read (format "%c" last-input-event))
           (error nil))))
    (or (numberp page)
        (setq page
              (read-minibuffer
               (format "Page number between 1 and %s: "
                       emacsvox-ocr-last-page-number))))
    (cond
     ((> page emacsvox-ocr-last-page-number)
      (message "Not that many pages in document."))
     (t 
      (emacsvox-ocr-goto-page page)))))

(defun emacsvox-ocr-read-current-page ()
  "Speaks current page."
  (interactive)
  (cl-declare (special emacsvox-ocr-page-positions
                       emacsvox-ocr-current-page-number
                       emacsvox-ocr-last-page-number))
  (cond
   ((= emacsvox-ocr-current-page-number
       emacsvox-ocr-last-page-number)
    (emacsvox-speak-region
     (aref emacsvox-ocr-page-positions
           emacsvox-ocr-current-page-number)
     (point-max)))
   (t (emacsvox-speak-region
       (aref emacsvox-ocr-page-positions
             emacsvox-ocr-current-page-number)
       (aref emacsvox-ocr-page-positions
             (1+ emacsvox-ocr-current-page-number))))))

(defun emacsvox-ocr-set-scan-image-options  (setting)
  "Interactively update scan image options.
Prompts with current setting in the minibuffer.
Setting persists for current Emacs session."
  (interactive
   (list
    (read-from-minibuffer
     "Scan image settings:"
     emacsvox-ocr-scan-image-options)))
  
  (setq emacsvox-ocr-scan-image-options setting))

(defun emacsvox-ocr-set-compress-image-options  (setting)
  "Interactively update  image compression options.
Prompts with current setting in the minibuffer.
Setting persists for current Emacs session."
  (interactive
   (list
    (read-from-minibuffer
     "Image compression settings: "
     emacsvox-ocr-compress-image-options)))
  
  (setq emacsvox-ocr-compress-image-options setting))

(provide 'emacsvox-ocr)
;;;  end of file

