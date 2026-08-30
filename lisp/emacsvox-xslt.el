;;; emacsvox-xslt.el --- XSLT -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop XSLT
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
;; libxml and libxsl are XML libraries for GNOME.
;; xsltproc is a  xslt processor using libxsl
;; this module defines routines for applying xsl transformations
;; using xsltproc
;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-xslt)
(defvar emacsvox-xslt-keep-errors)
(defvar emacsvox-xslt-options)
(defvar modification-flag)

;;   Required modules:

(require 'emacsvox-preamble)

(defun emacsvox-xslt-params-from-xpath (path base)
  "Return params suitable for passing to  emacsvox-xslt-region"
  (list
   (cons "path"
         (format "\"'%s'\""
                 (shell-quote-argument path)))
   (cons "locator"
         (format "'%s'"
                 path))
   (cons "base"
         (format "\"'%s'\""
                 base))))

(defun emacsvox-xslt-read ()
  "Read XSLT transformation name from minibuffer."
  
  (expand-file-name
   (read-file-name "XSL Transformation: "
                   emacsvox-xslt-directory
                   emacsvox-we-xsl-transform)))

(defvar emacsvox-xslt-options
  "--html --nonet --novalid --encoding utf-8"
  "Options passed to xsltproc.")

(defvar emacsvox-xslt-keep-errors  nil
  "If non-nil, xslt errors will be preserved in an errors buffer.")

(defvar emacsvox-xslt-nuke-null-char t
  "If T null chars in the region will be nuked.
This is useful when handling bad HTML.")

;;; Macro: without-xsl
(defmacro emacsvox-xslt-without-xsl (&rest body)
  "Execute body with XSL turned off."
  (declare (indent 1) (debug t))
  `(progn
     
     (when emacsvox-we-xsl-p
       (setq emacsvox-we-xsl-p nil)
       (add-hook 'emacsvox-eww-post-hook
                 #'(lambda ()
                     
                     (setq emacsvox-we-xsl-p t))
                 'append))
     ,@body))

;;; XSLT Transformer functions:

(defun emacsvox-xslt-make-xsl-transformer  (xsl &optional params)
  "Return a function that can be attached to
emacsvox-eww-pre-process-hook to apply required xslt transform."
  (cond
   ((null params)
    (eval
     `#'(lambda ()
          (emacsvox-xslt-region ,xsl (point) (point-max)))))
   (t
    (eval
     `#'(lambda ()
          (emacsvox-xslt-region ,xsl (point) (point-max) ',params))))))

(defun emacsvox-xslt-make-xsl-transformer-pipeline   (specs url)
  "Return a function that can be attached to
emacsvox-eww-pre-process-hook to apply required xslt transformation
pipeline. Argument `specs' is a list of elements of the form `(xsl params)'."
  (eval
   `#'(lambda ()
        (cl-loop
         for s in ',specs do
         (emacsvox-xslt-region
          (cl-first s)
          (point) (point-max)
          (emacsvox-xslt-params-from-xpath (cl-second s) ,url))))))

;;;  Functions:

;;;###autoload
(defun emacsvox-xslt-region (xsl start end &optional params no-comment)
  "Apply XSLT transformation to region and replace it with the result.  "
  (save-excursion
    (with-silent-modifications
      (let ((command nil)
            (parameters (when params
                          (mapconcat
                           #'(lambda (pair)
                               (format "--param %s %s "
                                       (car pair)
                                       (cdr pair)))
                           params
                           " ")))
            (coding-system-for-write 'utf-8)
            (coding-system-for-read 'utf-8)
            (buffer-file-coding-system 'utf-8))
        (setq command
              (format
               "%s %s  %s  %s - %s"
               emacsvox-xslt
               (or emacsvox-xslt-options "")
               (or parameters "")
               xsl
               (unless  emacsvox-xslt-keep-errors " 2>/dev/null ")))
        (shell-command-on-region
         start end
         command
         (current-buffer)
         'replace
         (when emacsvox-xslt-keep-errors "*xslt errors*"))
        (when (get-buffer  "*xslt errors*")
          (bury-buffer "*xslt errors*"))
        (unless no-comment
          (goto-char (point-max))
          (insert
           (format "<!--\n %s \n-->\n"
                   command)))
        (set-buffer-multibyte t)
        (current-buffer)))))

(defun emacsvox-xslt-run (xsl &optional start end)
  "Run xslt on region, and return output filtered by sort -u.
Region defaults to entire buffer."
  
  (or start (setq start (point-min)))
  (or end (setq end (point-max)))
  (let ((coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8)
        (buffer-file-coding-system 'utf-8))
    (shell-command-on-region
     start end
     (format "%s %s %s - 2>/dev/null | sort -u"
             emacsvox-xslt emacsvox-xslt-options xsl)
     (current-buffer) 'replace)
    (set-buffer-multibyte t)
    (current-buffer)))

;;;###autoload
(defun emacsvox-xslt-url (xsl url &optional params no-comment)
  "Apply XSLT transformation to url
and return the results in a newly created buffer. "
  (let ((result (get-buffer-create " *xslt result*"))
        (command nil)
        (parameters (when params
                      (mapconcat
                       #'(lambda (pair)
                           (format "--param %s %s "
                                   (car pair)
                                   (cdr pair)))
                       params
                       " "))))
    (setq command
          (format
           "curl --silent %s | %s %s --html --novalid %s - %s"
           url
           emacsvox-xslt
           (or parameters "")
           xsl
           (unless emacsvox-xslt-keep-errors " 2>/dev/null ")))
    (with-current-buffer result 
      (kill-all-local-variables)
      (erase-buffer)
      (setq buffer-undo-list  t)
      (let ((coding-system-for-write 'utf-8)
            (coding-system-for-read 'utf-8)
            (buffer-file-coding-system 'utf-8))
        (shell-command
         command (current-buffer)
         (when emacsvox-xslt-keep-errors "*xslt errors*"))
        (when emacsvox-xslt-nuke-null-char
          (goto-char (point-min))
          (while (search-forward
                  (format "%c" 0)
                  nil  t)
            (replace-match " "))))
      (when (get-buffer  "*xslt errors*")
        (bury-buffer "*xslt errors*"))
      (goto-char (point-max))
      (unless no-comment
        (insert
         (format "<!--\n %s \n-->\n"
                 command)))
      (setq modification-flag nil)
      (set-buffer-multibyte t)
      (goto-char (point-min))
      result)))

(defun emacsvox-xslt-pipeline-url (specs url &optional  no-comment)
  "Apply XSLT transformation to url
and browse the results.
Argument `specs' is a list of elements of the form
`(xsl xpath)'.
  This uses XSLT processor xsltproc available as
part of the libxslt package."
  (let ((result (url-retrieve-synchronously url))
        (command ""))
    (setq command
          (apply
           #'concat
           (cl-loop
            for s in specs
            and i from 0 collect 
            (format
             "%s %s %s %s %s - 2>/dev/null  "
             (if (= i 0)  "" "|")
             emacsvox-xslt
             (or emacsvox-xslt-options "")
             (mapconcat
              #'(lambda (pair)
                  (format "--param %s %s "
                          (car pair) (cdr pair)))
              (emacsvox-xslt-params-from-xpath (cl-second s) url)
              "")
             (cl-first s)))))
    (with-silent-modifications
      (with-current-buffer result 
        (let ((coding-system-for-write 'utf-8)
              (coding-system-for-read 'utf-8)
              (buffer-file-coding-system 'utf-8))
          (goto-char (point-min))
          (search-forward "\n\n")
          (delete-region (point-min) (point))
          (shell-command-on-region
           (point-min) (point-max)
           command (current-buffer) 'replace
           (when emacsvox-xslt-keep-errors "*xslt errors*")))
        (when (get-buffer  "*xslt errors*")
          (bury-buffer "*xslt errors*"))
        (goto-char (point-max))
        (unless no-comment
          (insert
           (format "<!--\n %s \n-->\n"
                   command)))
        (set-buffer-multibyte t)
        (goto-char (point-min))
        (browse-url-of-buffer)))))

;;;###autoload
(defun emacsvox-xslt-xml-url (xsl url &optional params)
  "Apply XSLT transformation to XML url
and return the results in a newly created buffer. "
  (let ((result (get-buffer-create " *xslt result*"))
        (command nil)
        (parameters
         (when params
           (mapconcat
            #'(lambda (pair)
                (format "--param %s %s " (car pair) (cdr pair)))
            params " "))))
    (setq command
          (format
           "%s %s --novalid %s '%s' %s"
           emacsvox-xslt
           (or parameters "")
           xsl url
           (unless emacsvox-xslt-keep-errors " 2>/dev/null ")))
    (save-current-buffer
      (set-buffer result)
      (kill-all-local-variables)
      (erase-buffer)
      (let ((coding-system-for-write 'utf-8)
            (coding-system-for-read 'utf-8)
            (buffer-file-coding-system 'utf-8))
        (shell-command
         command (current-buffer)
         (when emacsvox-xslt-keep-errors
           "xslt errors*")))
      (when (get-buffer  "*xslt errors*")
        (bury-buffer "*xslt errors*"))
      (goto-char (point-max))
      (insert
       (format "<!--\n %s \n-->\n"
               command))
      (setq modification-flag nil)
      (goto-char (point-min))
      (set-buffer-multibyte t)
      result)))

;;; handle charent
(defvar emacsvox-xslt-charent-alist
  '(("&lt;" . "<")
    ("&gt;" . ">")
    ("&quot;" . "\"")
    ("&apos;" . "'")
    ("&amp;" . "&"))
  "Entities to unescape when treating badly escaped XML.")

(defun emacsvox-xslt-unescape-charent (start end)
  "Clean up charents in XML."
  
  (cl-loop for entry in emacsvox-xslt-charent-alist
           do
           (let ((entity (car  entry))
                 (replacement (cdr entry)))
             (goto-char start)
             (while (search-forward entity end t)
               (replace-match replacement nil t)))))

;;;  interactive commands:

;;;###autoload
(defun emacsvox-xslt-view-file(style file)
  "Transform `file' using `style' and preview via browse-url."
  (interactive
   (list
    (read-file-name "Style File: " emacsvox-xslt-directory)
    (read-file-name "File:")))
  
  (with-temp-buffer
    (let ((browse-url-browser-function  'eww-browse-url)
          (coding-system-for-read 'utf-8)
          (coding-system-for-write 'utf-8)
          (buffer-file-coding-system 'utf-8))
      (insert-file-contents file)
      (shell-command
       (format
        "%s   --novalid --nonet --param base %s  %s  \"%s\"  2>/dev/null"
        emacsvox-xslt 
        (format "\"'file://%s'\"" file)
        style file)
       (current-buffer) 'replace)
      (browse-url-of-buffer))))
;;;###autoload
(defun emacsvox-xslt-view-rss-file (file)
  "View RSS file."
  (interactive "fRSS File:")
  
  (funcall-interactively
   'emacsvox-xslt-view-file
   emacsvox-rss-xsl file))

;;;###autoload
(defun emacsvox-xslt-view-atom-file (file)
  "View Atom file."
  (interactive "fAtom File:")
  
  (funcall-interactively
   'emacsvox-xslt-view-file
   emacsvox-atom-xsl file))

;;;###autoload
(defun emacsvox-xslt-view (style url)
  "Browse URL with specified XSL style."
  (interactive
   (list
    (expand-file-name
     (read-file-name "XSL Transformation: "))
    (ems--read-url)))
  
  (add-hook
   'emacsvox-eww-pre-process-hook
   (emacsvox-xslt-make-xsl-transformer style))
  (browse-url url))

(defun emacsvox-xslt-view-xml (style url &optional unescape-charent)
  "Browse XML URL with specified XSL style."
  (interactive
   (list
    (emacsvox-xslt-read)
    (ems--read-url)
    current-prefix-arg))
  (let ((browse-url-browser-function  'eww-browse-url)
        (src-buffer
         (emacsvox-xslt-xml-url
          style
          url
          (list
           (cons "base"
                 (format "\"'%s'\""
                         url))))))
    (when (called-interactively-p 'interactive) (emacsvox-eww-autospeak))
    (save-current-buffer
      (set-buffer src-buffer)
      (when unescape-charent
        (emacsvox-xslt-unescape-charent (point-min) (point-max)))
      (emacsvox-xslt-without-xsl
       (browse-url-of-buffer)))
    (kill-buffer src-buffer)))

(defun emacsvox-xslt-view-region (style start end &optional unescape-charent)
  "Browse XML region with specified XSL style."
  (interactive
   (list
    (emacsvox-xslt-read)
    (point)
    (mark)
    current-prefix-arg))
  (let ((browse-url-browser-function  'eww-browse-url)
        (src-buffer
         (with-silent-modifications
           (emacsvox-xslt-region style start end))))
    (save-current-buffer
      (set-buffer src-buffer)
      (when unescape-charent
        (emacsvox-xslt-unescape-charent (point-min) (point-max)))
      (emacsvox-xslt-without-xsl
       (browse-url-of-buffer)))
    (kill-buffer src-buffer)))

(provide 'emacsvox-xslt)

;;; emacsvox-xslt.el ends here
