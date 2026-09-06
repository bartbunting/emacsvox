;;; emacsvox-ocr.el --- ocr Front-end desktop  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, ocr
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

;; This module defines the Emacsvox front end to OCR.  PaddleOCR
;; PP-StructureV3 is the default engine and accepts images and PDFs.  SANE
;; remains available as an optional image-acquisition route.

;;; Code:

;;; Forward variable declarations:

(defvar buffer-read-only)
(defvar emacsvox-ocr-compress-image)
(defvar emacsvox-ocr-compress-image-options)
(defvar emacsvox-ocr-compress-photo)
(defvar emacsvox-ocr-current-page-number)
(defvar emacsvox-ocr-document-name)
(defvar emacsvox-ocr-engine)
(defvar emacsvox-ocr-error-buffer)
(defvar emacsvox-ocr-engine-options)
(defvar emacsvox-ocr-image-extension)
(defvar emacsvox-ocr-image-flipflop)
(defvar emacsvox-ocr-jpeg-metadata-writer)
(defvar emacsvox-ocr-keep-uncompressed-image)
(defvar emacsvox-ocr-last-page-number)
(defvar emacsvox-ocr-page-positions)
(defvar emacsvox-ocr-photo-compress-options)
(defvar emacsvox-ocr-process)
(defvar emacsvox-ocr-scan-image)
(defvar emacsvox-ocr-scan-image-options)
(defvar emacsvox-ocr-scan-photo-options)
(defvar emacsvox-ocr-working-directory)
(defvar emacsvox-speak-messages)
(defvar major-mode)
(defvar mode-line-format)

;;  required modules
(require 'emacsvox-preamble)

;;;   Customization variables
(defgroup emacsvox-ocr nil
  "Emacsvox front end for image and PDF OCR.
PaddleOCR PP-StructureV3 is the default recognition engine."
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

(defconst emacsvox-ocr-paddleocr-engine
  (expand-file-name "bin/emacsvox-paddleocr" emacsvox-directory)
  "Bundled PaddleOCR adapter executable.")

(defcustom emacsvox-ocr-engine
  emacsvox-ocr-paddleocr-engine
  "OCR engine used to process an image or PDF."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-python nil
  "Python executable used by the bundled PaddleOCR adapter.
When nil, the launcher uses its default isolated environment.  This option has
no effect when `emacsvox-ocr-engine' selects another OCR engine."
  :type '(choice
          (const :tag "Default isolated environment" nil)
          (file :tag "Python executable"))
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-language "en"
  "Language used by the bundled PaddleOCR adapter."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-device "cpu"
  "Paddle device used by the bundled adapter.
Examples include `cpu', `gpu', and `gpu:0'."
  :type 'string
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-use-document-orientation t
  "Whether PaddleOCR should classify document orientation."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-use-document-unwarping t
  "Whether PaddleOCR should correct warped document images."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-use-text-line-orientation t
  "Whether PaddleOCR should classify individual text-line orientation."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-use-table-recognition t
  "Whether PaddleOCR should recognize and preserve tables."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-use-formula-recognition t
  "Whether PaddleOCR should recognize mathematical formulas."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-paddleocr-enable-mkldnn nil
  "Whether to enable oneDNN/MKL-DNN acceleration for PaddleOCR.
Keep this disabled for the tested PaddlePaddle 3.3.0 CPU setup on WSL."
  :type 'boolean
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-engine-options nil
  "Additional command-line arguments passed literally to the OCR engine.
For the bundled PaddleOCR adapter, these follow the typed customization
options and can override them."
  :type'(repeat
         (string :tag "Option"))
  :group 'emacsvox-ocr)

(defcustom emacsvox-ocr-error-buffer "*Emacsvox OCR Errors*"
  "Buffer that receives diagnostics from the OCR engine."
  :type 'string
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
  (format "%s-p%s%s"
          emacsvox-ocr-document-name
          (1+ emacsvox-ocr-last-page-number)
          extension))

(defun emacsvox-ocr-get-page-name ()
  "Return name of current page."
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
  "An OCR front end for the Emacsvox desktop.

The default engine is PaddleOCR PP-StructureV3.  It recognizes images and
PDFs, preserves reading order, and represents detected tables in Markdown.
Install it as described in the Emacsvox user manual, then use `o' to choose a
file.  OCR runs asynchronously; engine diagnostics go to the buffer named by
`emacsvox-ocr-error-buffer'.

The optional scanner commands require a working scanner back end such as SANE
on Linux.  `emacsvox-ocr-scan-image' uses `scanimage' to acquire a TIFF file;
customize `emacsvox-ocr-scan-image' and its related options if necessary.

Launch this front end with `emacsvox-ocr', bound to \\[emacsvox-ocr].  The
result buffer uses single-keystroke commands; see the key-binding list below.
Recognized text and optional acquired images are saved under
`emacsvox-ocr-working-directory'.  Command
`emacsvox-ocr-open-working-directory', bound to
\\[emacsvox-ocr-open-working-directory], opens that directory.

By default, the document is named from the current date.
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
          (make-vector 32 nil))
    (emacsvox-ocr-update-mode-line)))

(define-key emacsvox-ocr-mode-map "?" 'describe-mode)
(define-key emacsvox-ocr-mode-map "c" 'emacsvox-ocr-customize)
(define-key emacsvox-ocr-mode-map "q" 'bury-buffer)
(define-key emacsvox-ocr-mode-map "w" 'emacsvox-ocr-write-document)
(define-key emacsvox-ocr-mode-map "\C-m"  'emacsvox-ocr-scan-and-recognize)
(define-key emacsvox-ocr-mode-map "i" 'emacsvox-ocr-scan-image)
(define-key emacsvox-ocr-mode-map "j" 'emacsvox-ocr-scan-photo)
(define-key emacsvox-ocr-mode-map "o" 'emacsvox-ocr-recognize-file)
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
  "Open the Emacsvox front end for image and PDF OCR.

The selected file is run through `emacsvox-ocr-engine' and the result is
placed in a buffer suitable for reading and saving.  Optional image
acquisition commands use tools from the SANE package.

For detailed help, invoke command emacsvox-ocr bound to
\\[emacsvox-ocr] to launch emacsvox-ocr-mode, and press
`?' to display mode-specific help for emacsvox-ocr-mode."
  (interactive)
  (let  ((buffer (emacsvox-ocr-get-buffer)))
    (with-current-buffer buffer
      (emacsvox-ocr-mode)
      (make-directory emacsvox-ocr-working-directory t)
      (cd emacsvox-ocr-working-directory)
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
  (setq emacsvox-ocr-document-name name)
  (rename-buffer
   (format "*%s-ocr*" name)
   'unique)
  (emacsvox-ocr-update-mode-line)
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(defun emacsvox-ocr--acquisition-step (command output label)
  "Run acquisition COMMAND and require a nonempty OUTPUT for LABEL."
  (let ((emacsvox-speak-messages nil)
        (inhibit-read-only t)
        (errors (get-buffer-create emacsvox-ocr-error-buffer)))
    (let ((status (shell-command command errors errors)))
      (unless (eql status 0)
        (user-error "%s failed (exit %s); see %s"
                    label status emacsvox-ocr-error-buffer)))
    (unless (and (file-regular-p output)
                 (> (file-attribute-size (file-attributes output)) 0))
      (user-error "%s produced no image; see %s" label emacsvox-ocr-error-buffer))))

(defun emacsvox-ocr-scan-image ()
  "Acquire a page image, publishing it only after successful processing.
With compression and `emacsvox-ocr-keep-uncompressed-image', retain the
original with -uncompressed before its extension.  On processing failure,
report the recovery path and leave the page number unchanged."
  (interactive)
  (unless emacsvox-ocr-scan-image
    (user-error "Configure emacsvox-ocr-scan-image with an acquisition program"))
  (let* ((image-name (expand-file-name
                      (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension)))
         (original-name (concat (file-name-sans-extension image-name)
                                "-uncompressed" emacsvox-ocr-image-extension))
         stage source output acquired complete)
    (when (file-exists-p image-name)
      (user-error "Image already exists: %s" image-name))
    (when (and emacsvox-ocr-compress-image emacsvox-ocr-keep-uncompressed-image
               (file-exists-p original-name))
      (user-error "Uncompressed image already exists: %s" original-name))
    (setq stage (make-temp-file
                 (expand-file-name ".emacsvox-scan-" (file-name-directory image-name)) t)
          source (expand-file-name (concat "source" emacsvox-ocr-image-extension) stage)
          output (if emacsvox-ocr-compress-image
                     (expand-file-name (concat "result" emacsvox-ocr-image-extension) stage)
                   source))
    (unwind-protect
        (condition-case failure
            (progn
              (emacsvox-ocr--acquisition-step
               (format "%s %s > %s"
                       (shell-quote-argument emacsvox-ocr-scan-image)
                       emacsvox-ocr-scan-image-options
                       (shell-quote-argument source))
               source "Scanner")
              (setq acquired t)
              (when emacsvox-ocr-compress-image
                (emacsvox-ocr--acquisition-step
                 (format "%s %s %s %s"
                         ;; Preserve intentionally configured shell commands,
                         ;; while also accepting an executable path with spaces.
                         (if (file-executable-p emacsvox-ocr-compress-image)
                             (shell-quote-argument emacsvox-ocr-compress-image)
                           emacsvox-ocr-compress-image)
                         emacsvox-ocr-compress-image-options
                         (shell-quote-argument source)
                         (shell-quote-argument output))
                 output "Image compression")
                (when emacsvox-ocr-keep-uncompressed-image
                  (rename-file source original-name)))
              (rename-file output image-name)
              (setq complete t)
              (when (called-interactively-p 'interactive)
                (cl-incf emacsvox-ocr-last-page-number))
              (message "Acquired image to file %s%s" image-name
                       (if (and emacsvox-ocr-compress-image
                                emacsvox-ocr-keep-uncompressed-image)
                           (format "; original retained at %s" original-name)
                         "")))
          (error
           (if (and acquired (not complete))
               (user-error "%s; recovery path: %s"
                           (error-message-string failure)
                           (cond ((file-exists-p source) source)
                                 ((file-exists-p original-name) original-name)
                                 (t stage)))
             (signal (car failure) (cdr failure)))))
      ;; A complete acquisition is valuable even if compression or publication
      ;; failed.  Incomplete scanner output and successful staging are disposable.
      (unless (and acquired (not complete))
        (delete-directory stage t)))))

(defun emacsvox-ocr-scan-photo (&optional metadata)
  "Scan in a photograph.
The scanned image is converted to JPEG."
  (interactive "P")
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

(make-variable-buffer-local 'emacsvox-ocr-process)

(defun emacsvox-ocr--ensure-page-capacity (page)
  "Ensure that the page position vector can hold PAGE."
  (when (>= page (length emacsvox-ocr-page-positions))
    (let* ((old-length (length emacsvox-ocr-page-positions))
           (new-length (max (1+ page) (* 2 old-length) 32)))
      (setq emacsvox-ocr-page-positions
            (vconcat emacsvox-ocr-page-positions
                     (make-vector (- new-length old-length) nil))))))

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

(defun emacsvox-ocr-process-sentinel (process _state)
  "Update the OCR buffer after PROCESS exits."
  (when (and (memq (process-status process) '(exit signal))
             (not (process-get process 'emacsvox-ocr-handled)))
    (process-put process 'emacsvox-ocr-handled t)
    (let ((buffer (process-buffer process))
          (page (process-get process 'emacsvox-ocr-page))
          (header-start (process-get process 'emacsvox-ocr-header-start)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (setq emacsvox-ocr-process nil)
          (if (= 0 (process-exit-status process))
              (progn
                (setq emacsvox-ocr-current-page-number page)
                (emacsvox-icon 'task-done)
                (goto-char (aref emacsvox-ocr-page-positions page))
                (emacsvox-ocr-save-current-page)
                (emacsvox-ocr-update-mode-line)
                (emacsvox-speak-line))
            (let ((inhibit-read-only t))
              (delete-region header-start (point-max)))
            (aset emacsvox-ocr-page-positions page nil)
            (setq emacsvox-ocr-last-page-number (1- page)
                  emacsvox-ocr-current-page-number
                  (min emacsvox-ocr-current-page-number
                       emacsvox-ocr-last-page-number))
            (emacsvox-ocr-update-mode-line)
            (emacsvox-icon 'warn-user)
            (message
             "OCR failed; see %s"
             emacsvox-ocr-error-buffer)))))))

(defun emacsvox-ocr--default-input-file ()
  "Return the expected page image, or prompt for an image or PDF."
  (let ((expected
         (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension)))
    (if (file-exists-p expected)
        (expand-file-name expected)
      (expand-file-name
       (read-file-name "Image or PDF to recognize: ")))))

(defun emacsvox-ocr--using-paddleocr-p ()
  "Return non-nil when the bundled PaddleOCR adapter is selected."
  (equal (expand-file-name emacsvox-ocr-engine)
         emacsvox-ocr-paddleocr-engine))

(defun emacsvox-ocr--paddleocr-arguments ()
  "Return arguments derived from the typed PaddleOCR options."
  (append
   (list "--lang" emacsvox-ocr-paddleocr-language
         "--device" emacsvox-ocr-paddleocr-device)
   (unless emacsvox-ocr-paddleocr-use-document-orientation
     '("--no-doc-orientation"))
   (unless emacsvox-ocr-paddleocr-use-document-unwarping
     '("--no-doc-unwarping"))
   (unless emacsvox-ocr-paddleocr-use-text-line-orientation
     '("--no-textline-orientation"))
   (unless emacsvox-ocr-paddleocr-use-table-recognition
     '("--no-tables"))
   (unless emacsvox-ocr-paddleocr-use-formula-recognition
     '("--no-formulas"))
   (when emacsvox-ocr-paddleocr-enable-mkldnn
     '("--enable-mkldnn"))))

(defun emacsvox-ocr--engine-command (input-file)
  "Return the OCR command list for INPUT-FILE."
  (append
   (list emacsvox-ocr-engine input-file)
   (when (emacsvox-ocr--using-paddleocr-p)
     (emacsvox-ocr--paddleocr-arguments))
   emacsvox-ocr-engine-options))

(defun emacsvox-ocr--engine-process-environment ()
  "Return the environment to use for the selected OCR engine."
  (let ((process-environment (copy-sequence process-environment)))
    (when (and (emacsvox-ocr--using-paddleocr-p)
               emacsvox-ocr-paddleocr-python)
      (setenv "EMACSVOX_PADDLEOCR_PYTHON"
              (expand-file-name emacsvox-ocr-paddleocr-python)))
    process-environment))

(defun emacsvox-ocr-recognize-file (input-file)
  "Run the OCR engine asynchronously on image or PDF INPUT-FILE."
  (interactive (list (emacsvox-ocr--default-input-file)))
  (when (process-live-p emacsvox-ocr-process)
    (user-error "OCR is already running in this buffer"))
  (unless (file-readable-p input-file)
    (user-error "Cannot read OCR input: %s" input-file))
  (unless (or (file-executable-p emacsvox-ocr-engine)
              (executable-find emacsvox-ocr-engine))
    (user-error "OCR engine is not executable: %s" emacsvox-ocr-engine))
  (let* ((inhibit-read-only t)
         (process-environment (emacsvox-ocr--engine-process-environment))
         (header-start (point-max))
         (page (1+ emacsvox-ocr-last-page-number))
         (error-buffer (get-buffer-create emacsvox-ocr-error-buffer)))
    (with-current-buffer error-buffer
      (let ((inhibit-read-only t))
        (erase-buffer)))
    (goto-char header-start)
    (emacsvox-icon 'select-object)
    (emacsvox-ocr--ensure-page-capacity page)
    (setq emacsvox-ocr-last-page-number page)
    (insert (format "\n%c\nPage %s\n" 12 page))
    (aset emacsvox-ocr-page-positions page (+ 3 header-start))
    (setq emacsvox-ocr-process
          (make-process
           :name "emacsvox-ocr"
           :buffer (current-buffer)
           :command (emacsvox-ocr--engine-command input-file)
           :connection-type 'pipe
           :noquery t
           :stderr error-buffer
           :sentinel #'ignore))
    (let ((process emacsvox-ocr-process))
      (process-put process 'emacsvox-ocr-page page)
      (process-put process 'emacsvox-ocr-header-start header-start)
      (set-process-sentinel process #'emacsvox-ocr-process-sentinel)
      (when (memq (process-status process) '(exit signal))
        (emacsvox-ocr-process-sentinel process "finished\n")))
    (message "Launched OCR engine.")))

(defun emacsvox-ocr-recognize-image ()
  "Compatibility command that recognizes an image or PDF."
  (interactive)
  (call-interactively #'emacsvox-ocr-recognize-file))

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
  (let ((image-name
         (if
             (file-exists-p
              (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension))
             (emacsvox-ocr-get-image-name emacsvox-ocr-image-extension)
           (expand-file-name 
            (read-file-name "Image file to recognize: ")))))
    (unless emacsvox-ocr-image-flipflop
      (user-error "ImageMagick mogrify is not installed"))
    (unless (= 0 (process-file emacsvox-ocr-image-flipflop nil nil nil
                               "-flip" "-flop" image-name))
      (user-error "Could not rotate image: %s" image-name))
    (emacsvox-ocr-recognize-file image-name)))

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

;;; emacsvox-ocr.el ends here
