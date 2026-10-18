;;; emacsvox-we.el --- Transform WebUsing XSLT  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop Web, XSLT
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
;; we is for webedit
;; Invoke XSLT to edit/transform Web pages before they get
;; rendered.
;; we makes emacsvox's webedit layer independent of a given
;; Emacs web browser  EWW
;; This module will use the abstraction provided by browse-url
;; to handle Web pages.

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-we-filters-rename-buffer)
(defvar emacsvox-we-id-filter)
(defvar emacsvox-we-recent-xpath-junk)
(defvar emacsvox-we-url-rewrite-rule)
(defvar emacsvox-we-xpath-junk)
(defvar emacsvox-we-xsl-filter)
(defvar emacsvox-we-xsl-junk)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-xslt)

;;; Helper:

(defun emacsvox-we-rename-buffer (key)
  "Setup emacsvox-eww-post-hook  to rename result buffer"
  (add-hook
   'emacsvox-eww-post-hook
   (eval
    `#'(lambda nil
         (rename-buffer
          (format "%s %s"
                  (buffer-name) ,key)
          'unique)))))

;;;  URL Rewrite:
;; forward decl to help compiler 
(defvar emacsvox-eww-url-at-point)

(defun emacsvox-we-url-rewrite-and-follow (&optional prompt)
  "Apply a url rewrite rule as specified in the current buffer
before following link under point.  If no rewrite rule is
defined, first prompt for one.  Rewrite rules are of the
form `(from to)' where from and to are strings.  Typically, the
rewrite rule is automatically set up by Emacsvox tools like
websearch where a rewrite rule is known.  Rewrite rules are
useful in jumping directly to the printer friendly version of an
article for example.  Optional interactive prefix arg prompts for
a rewrite rule even if one is already defined."
  (interactive "P")
  
  (emacsvox-eww-browser-check)
  (let ((url (funcall emacsvox-eww-url-at-point))
        (redirect nil))
    (unless url (error "Not on a link."))
    (when (or prompt (null emacsvox-we-url-rewrite-rule))
      (setq emacsvox-we-url-rewrite-rule
            (read-minibuffer  "Specify rewrite rule: " "(")))
    (setq redirect
          (replace-regexp-in-string
           (cl-first emacsvox-we-url-rewrite-rule)
           (cl-second emacsvox-we-url-rewrite-rule)
           url))
    (emacsvox-icon 'select-object)
    (browse-url (or redirect url))))

;;;  url expand and execute
(defvar emacsvox-we-url-executor nil
  "URL expand/execute function  to use in current buffer.")

(make-variable-buffer-local 'emacsvox-we-url-executor)

(defun emacsvox-we-url-expand-and-execute (&optional prefix)
  "Applies buffer-specific URL expander/executor function."
  (interactive "P")
  
  (emacsvox-eww-browser-check)
  (let ((url (funcall emacsvox-eww-url-at-point)))
    (unless url (error "Not on a link."))
    (emacsvox-icon 'button)
    (cond
     ((functionp emacsvox-we-url-executor)
      (if prefix
          (funcall emacsvox-we-url-executor url prefix)
        (funcall emacsvox-we-url-executor url)))
     ((string-match "reddit" url)       ; use reddit url template
      (emacsvox-url-template-open
       (emacsvox-url-template-get "Reddit At Point")))
     ((string-match "wikipedia" url) ; Use wikipedia url template
      (emacsvox-url-template-open
       (emacsvox-url-template-get "Wikipedia At Point")))
     (t
      (setq emacsvox-we-url-executor
            (intern
             (completing-read
              "Executor function: "
              obarray 'fboundp t
              "emacsvox-" nil)))
      (if (functionp emacsvox-we-url-executor)
          (funcall emacsvox-we-url-executor url)
        (error "Invalid executor %s"
               emacsvox-we-url-executor))))))

;;;  applying XSL transforms before displaying
(define-prefix-command 'emacsvox-we-xsl-map)

(defvar emacsvox-we-xsl-filter
  (emacsvox-xslt-get "xpath-filter.xsl")
  "XSL to extract  elements matching a specified XPath locator.")

(defvar emacsvox-we-xsl-junk
  (emacsvox-xslt-get "xpath-junk.xsl")
  "XSL to junk  elements matching a specified XPath locator.")
(defgroup emacsvox-we nil
  "Emacsvox WebEdit"
  :group 'emacsvox)
(defvar emacsvox-we-xsl-p nil
  "T means we apply XSL before displaying HTML.")
(defvar emacsvox-we-xsl-transform
  nil
  "Specifies transform to use before displaying a page.
Default is to apply sort-tables.")

(defvar emacsvox-we-xsl-params nil
  "XSL params if any to pass to emacsvox-xslt-region.")

;; Note that emacsvox-we-xsl-transform, emacsvox-we-xsl-params
;; and emacsvox-we-xsl-p
;; need to be set at top-level since the page-rendering code is
;; called asynchronously.

(defvar emacsvox-we-cleanup-bogus-quotes t
  "Clean up bogus Unicode chars for magic quotes.")

(declare-function eww-current-url "eww" nil)

(defun emacsvox-we-xslt-apply (xsl)
  "Apply specified transformation to current Web page."
  (interactive (list (emacsvox-xslt-read)))
  (emacsvox-eww-browser-check)
  (add-hook
   'emacsvox-eww-pre-process-hook
   (emacsvox-xslt-make-xsl-transformer  xsl))
  (browse-url (eww-current-url)))

(defun emacsvox-we-xslt-select (xsl)
  "Select XSL transformation applied to Web pages before they are displayed ."
  (interactive (list (emacsvox-xslt-read)))
  
  (setq emacsvox-we-xsl-transform xsl)
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'select-object)
    (message "Will apply %s before displaying HTML pages."
             (file-name-sans-extension
              (file-name-nondirectory xsl)))))

(defun emacsvox-we-xsl-toggle ()
  "Toggle  application of XSL transformations."
  (interactive)
  
  (setq emacsvox-we-xsl-p (not emacsvox-we-xsl-p))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon
     (if emacsvox-we-xsl-p 'on 'off))
    (message "Turned %s XSL"
             (if emacsvox-we-xsl-p 'on 'off))))

(defun emacsvox-we-count-matches (url locator)
  "Count matches for locator  in Web page."
  (interactive
   (list
    (ems--read-url)
    (read-from-minibuffer "XPath locator: ")))
  (read
   (emacsvox-xslt-url
    (emacsvox-xslt-get "count-matches.xsl")
    url
    (emacsvox-xslt-params-from-xpath locator url)
    'no-comment)))

(defun emacsvox-we-count-nested-tables (url)
  "Count nested tables in Web page."
  (interactive (list (ems--read-url)))
  (emacsvox-we-count-matches url "'//table//table'"))

(defun emacsvox-we-count-tables (url)
  "Count  tables in Web page."
  (interactive (list (ems--read-url)))
  (emacsvox-we-count-matches url "//table"))

(defvar emacsvox-we-xsl-keep-result nil
  "Toggle via command \\[emacsvox-we-toggle-xsl-keep-result].")

(defun emacsvox-we-toggle-xsl-keep-result ()
  "Toggle xsl keep result flag."
  (interactive)
  
  (setq emacsvox-we-xsl-keep-result
        (not emacsvox-we-xsl-keep-result))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon (if emacsvox-we-xsl-keep-result 'on 'off))
    (message "Turned %s xslt keep results."
             (if emacsvox-we-xsl-keep-result
                 'on 'off))))
(defcustom emacsvox-we-filters-rename-buffer nil
  "Set to T  if you want the buffer name to contain the applied filter."
  :type  'boolean
  :group 'emacsvox-we)
(declare-function emacsvox-eww-reading-settings "emacsvox-eww")

(defun emacsvox-we-xslt-filter (path    url  &optional _speak)
  "Extract elements matching specified XPath path locator
from Web page -- default is the current page being viewed."
  (interactive
   (list
    (read-from-minibuffer "XPath: ")
    (ems--read-url)
    current-prefix-arg))
  (let ((params (emacsvox-xslt-params-from-xpath  path url)))
    (when emacsvox-we-filters-rename-buffer
      (emacsvox-we-rename-buffer (format "Filtered %s" path)))
    (add-hook
     'emacsvox-eww-pre-process-hook
     (emacsvox-xslt-make-xsl-transformer emacsvox-we-xsl-filter params))
    (browse-url url)))

(defun emacsvox-we-xslt-pipeline-filter (specs    url  &optional _speak)
  "Apply a pipeline of filters specified in `specs', a list.
Each filter is a list of the form
 `(xsl-stylesheet-name xpath)'."
  
  (when emacsvox-we-filters-rename-buffer
    (emacsvox-we-rename-buffer (format "Pipeline filtered ")))
  (add-hook
   'emacsvox-eww-pre-process-hook
   (emacsvox-xslt-make-xsl-transformer-pipeline specs url))
  (add-hook
   'emacsvox-eww-post-hook
   #'emacsvox-eww-reading-settings 'at-end)
  (browse-url url))

(defun emacsvox-we-xslt-junk (path    url &optional speak)
  "Junk elements matching specified locator."
  (interactive
   (list
    (read-from-minibuffer "XPath: ")
    (ems--read-url)
    (called-interactively-p 'interactive)))
  
  (let ((params (emacsvox-xslt-params-from-xpath  path url)))
    (emacsvox-we-rename-buffer (format "Filtered %s" path))
    (when speak (emacsvox-eww-autospeak))
    (add-hook
     'emacsvox-eww-pre-process-hook
     (emacsvox-xslt-make-xsl-transformer emacsvox-we-xsl-junk params))
    (browse-url url)))

(defun emacsvox-we-follow-and-extract-main (&optional speak)
  "Follow URL, then extract role=main."
  (interactive
   (list
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (emacsvox-we-extract-by-role "main"
                               (funcall emacsvox-eww-url-at-point) speak))

(defun emacsvox-we-extract-matching-urls (pattern url &optional speak)
  "Extracts links whose URL matches pattern."
  (interactive
   (list
    (read-from-minibuffer "Pattern: ")
    (ems--read-url)
    (called-interactively-p 'interactive)))
  (let ((filter
         (format
          "//a[contains(@href,\"%s\")]"
          pattern)))
    (emacsvox-we-xslt-filter filter url speak)))

(defun emacsvox-we-extract-nested-table (index   url &optional speak)
  "Extract nested table specified by `table-index'. Default is to
operate on current web page when in a browser buffer; otherwise
prompt for URL. Optional arg `speak' specifies if the result should be
spoken automatically."
  (interactive
   (list
    (read-from-minibuffer "Table Index: ")
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (emacsvox-we-xslt-filter
   (format "(//table//table)[%s]" index)
   url speak))

(defun  emacsvox-we-get-table-list (&optional bound)
  "Collect a list of numbers less than bound
 by prompting repeatedly in the
minibuffer.
Empty value finishes the list."
  (let ((result nil)
        (i nil)
        (done nil))
    (while (not done)
      (setq i
            (read-from-minibuffer
             (format "Index%s"
                     (if bound
                         (format " less than  %s" bound)
                       ":"))))
      (if (> (length i) 0)
          (push i result)
        (setq done t)))
    result))

(defun  emacsvox-we-get-table-match-list ()
  "Collect a list of matches by prompting repeatedly in the
minibuffer.
Empty value finishes the list."
  (let ((result nil)
        (i nil)
        (done nil))
    (while (not done)
      (setq i
            (read-from-minibuffer "Match: "))
      (if (> (length i) 0)
          (push i result)
        (setq done t)))
    result))

(defun emacsvox-we-extract-nested-table-list (tables url &optional speak)
  "Extract specified list of tables from a Web page."
  (interactive
   (list
    (emacsvox-we-get-table-list)
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter
         (mapconcat
          #'(lambda  (i)
              (format "((//table//table)[%s])" i))
          tables
          " | ")))
    (emacsvox-we-xslt-filter filter url speak)))

(defun emacsvox-we-extract-table-by-position (pos   url
                                                    &optional speak)
  "Extract table at specified pos.
Default is to extract from current page."
  (interactive
   (list
    (read-from-minibuffer "Extract Table: ")
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (emacsvox-we-xslt-filter
   (format "/descendant::table[%s]"
           pos)
   url
   speak))

(defun emacsvox-we-extract-tables-by-position-list (positions url
                                                              &optional speak)
  "Extract specified list of nested tables from a WWW page.
Tables are specified by their position in the list
 of nested tables found in the page."
  (interactive
   (list
    (emacsvox-we-get-table-list)
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter
         (mapconcat
          #'(lambda  (i)
              (format "(/descendant::table[%s])" i))
          positions
          " | ")))
    (emacsvox-we-xslt-filter
     filter
     url
     (or (called-interactively-p 'interactive)
         speak))))

(defun emacsvox-we-extract-table-by-match (match   url &optional speak)
  "Extract table containing  specified match.
 Optional arg url specifies the page to extract content from."
  (interactive
   (list
    (read-from-minibuffer "Tables Matching: ")
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (emacsvox-we-xslt-filter
   (format "(/descendant::table[contains(., \"%s\")])[last()]"
           match)
   url
   (or (called-interactively-p 'interactive)
       speak)))

(defun emacsvox-we-extract-tables-by-match-list (match-list
                                                 url &optional speak)
  "Extract specified  tables from a WWW page.
Tables are specified by containing  match pattern
 found in the match list."
  (interactive
   (list
    (emacsvox-we-get-table-match-list)
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter
         (mapconcat
          #'(lambda  (i)
              (format "((/descendant::table[contains(.,\"%s\")])[last()])" i))
          match-list
          " | ")))
    (emacsvox-we-xslt-filter
     filter
     url
     (or (called-interactively-p 'interactive)
         speak))))

(defvar emacsvox-we-buffer-class-cache nil
  "Caches class attribute values for current buffer.")

(make-variable-buffer-local 'emacsvox-we-buffer-class-cache)
(declare-function
 emacsvox-xslt-run "emacsvox-xslt" (xsl &optional start end))

(defun emacsvox-we-build-class-cache ()
  "Build class cache and forward it to rendered page."
  (let ((values nil)
        (content (clone-buffer)))
    (with-current-buffer content
      (setq buffer-undo-list  t)
      (emacsvox-xslt-run
       (emacsvox-xslt-get "class-values.xsl")
       (point-min) (point-max))
      (goto-char (point-min))
      (skip-syntax-forward " ")
      (delete-region (point-min) (point))
      (setq values (split-string (buffer-string))))
    (add-hook
     'emacsvox-eww-post-hook
     (eval
      `#'(lambda nil
           
           (setq emacsvox-we-buffer-class-cache
                 ',(copy-sequence values)))))
    (kill-buffer content)))

(defvar emacsvox-we-buffer-id-cache nil
  "Caches id attribute values for current buffer.")

(make-variable-buffer-local 'emacsvox-we-buffer-id-cache)

(defun emacsvox-we-build-id-cache ()
  "Build id cache and forward it to rendered page."
  (let ((values nil)
        (content (clone-buffer)))
    (with-current-buffer content
      (setq buffer-undo-list  t)
      (emacsvox-xslt-run
       (emacsvox-xslt-get "id-values.xsl")
       (point-min) (point-max))
      (setq values (split-string (buffer-string))))
    (add-hook
     'emacsvox-eww-post-hook
     (eval
      `#'(lambda nil
           
           (setq emacsvox-we-buffer-id-cache
                 ',(copy-sequence values)))))
    (kill-buffer content)))

(defvar emacsvox-we-buffer-role-cache nil
  "Caches role attribute values for current buffer.")

(make-variable-buffer-local 'emacsvox-we-buffer-role-cache)

(defun emacsvox-we-build-role-cache ()
  "Build role cache and forward it to rendered page."
  (let ((values nil)
        (content (clone-buffer)))
    (with-current-buffer content
      (setq buffer-undo-list  t)
      (emacsvox-xslt-run
       (emacsvox-xslt-get "role-values.xsl")
       (point-min) (point-max))
      (setq values (split-string (buffer-string))))
    (add-hook
     'emacsvox-eww-post-hook
     (eval
      `#'(lambda nil
           
           (setq emacsvox-we-buffer-role-cache
                 ',(copy-sequence values)))))
    (kill-buffer content)))

(defun emacsvox-we-extract-by-class (class    url &optional speak)
  "Extract elements having specified class attribute from HTML. Extracts
specified elements from current WWW page and displays it in a separate
buffer. Interactive use provides list of class values as completion."
  (interactive
   (list
    (completing-read "Class: "
                     emacsvox-we-buffer-class-cache)
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter (format "//*[contains(@class,\"%s\")]" class)))
    (emacsvox-we-xslt-filter filter
                             url
                             (or (called-interactively-p 'interactive)
                                 speak))))

(defun emacsvox-we-extract-speakable (url &optional speak)
  "Extract elements having class`speakable' from HTML. "
  (interactive
   (list
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (emacsvox-we-extract-by-class "speakable" url speak))

(defun emacsvox-we-extract-by-role (role    url &optional speak)
  "Extract elements having specified role attribute from HTML. Extracts
specified elements from current WWW page and displays it in a separate
buffer. Interactive use provides list of role values as completion."
  (interactive
   (list
    (completing-read "Role: "
                     emacsvox-we-buffer-role-cache)
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter (format "//*[contains(@role,\"%s\")]" role)))
    (emacsvox-we-xslt-filter filter
                             url
                             (or (called-interactively-p 'interactive)
                                 speak))))

(defun emacsvox-we-junk-by-class (class    url &optional speak)
  "Extract elements not having specified class attribute from HTML. Extracts
specified elements from current WWW page and displays it in a separate
buffer. Interactive use provides list of class values as completion."
  (interactive
   (list
    (completing-read "Class: "
                     emacsvox-we-buffer-class-cache)
    (ems--read-url)
    current-prefix-arg))
  (let ((filter (format "//*[contains(@class,\"%s\")]" class)))
    (emacsvox-we-xslt-junk filter
                           url
                           (or (called-interactively-p 'interactive)
                               speak))))

(defun  emacsvox-we-get-id-list ()
  "Collect a list of ids by prompting repeatedly in the
minibuffer.
Empty value finishes the list."
  (let ((ids emacsvox-we-buffer-id-cache)
        (result nil)
        (c nil)
        (done nil))
    (while (not done)
      (setq c
            (completing-read "Id: "
                             ids
                             nil 'must-match))
      (if (> (length c) 0)
          (push c result)
        (setq done t)))
    result))

(defun  emacsvox-we-css-get-class-list ()
  "Collect a list of classes by prompting repeatedly in the
minibuffer.
Empty value finishes the list."
  (let ((classes emacsvox-we-buffer-class-cache)
        (result nil)
        (c nil)
        (done nil))
    (while (not done)
      (setq c
            (completing-read "Class: "
                             classes
                             nil 'must-match))
      (if (> (length c) 0)
          (push c result)
        (setq done t)))
    result))

(defun emacsvox-we-extract-by-class-list(classes   url &optional
                                                   speak)
  "Extract elements having class specified in list `classes' from HTML.
Extracts specified elements from current WWW page and displays it
in a separate buffer.  Interactive use provides list of class
values as completion. "
  (interactive
   (list
    (let ((completion-ignore-case t))
      (emacsvox-we-css-get-class-list))
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter
         (mapconcat
          #'(lambda  (c)
              (format "(@class=\"%s\")" c))
          classes
          " or ")))
    (emacsvox-we-xslt-filter
     (format "//*[%s]" filter)
     url
     (or (called-interactively-p 'interactive) speak))))
(defun emacsvox-we-junk-by-class-list(classes   url &optional
                                                speak)
  "Extract elements not having class specified in list `classes' from HTML.
Extracts specified elements from current WWW page and displays it
in a separate buffer.  Interactive use provides list of class
values as completion. "
  (interactive
   (list
    (let ((completion-ignore-case t))
      (emacsvox-we-css-get-class-list))
    (ems--read-url)
    current-prefix-arg))
  (let ((filter
         (mapconcat
          #'(lambda  (c)
              (format "(@class=\"%s\")" c))
          classes
          " or ")))
    (emacsvox-we-xslt-junk
     (format "//*[%s]" filter)
     url
     (or (called-interactively-p 'interactive) speak))))
(defun emacsvox-we-extract-by-id (id   url &optional speak)
  "Extract elements having specified id attribute from HTML. Extracts
specified elements from current WWW page and displays it in a
separate buffer.  Interactive use prompts for   id values using
completion."
  (interactive
   (list
    (let ((completion-ignore-case t))
      (completing-read "Id: " emacsvox-we-buffer-id-cache))
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg))
   current-prefix-arg)
  (emacsvox-we-xslt-filter
   (format "//*[@id=\"%s\"]"
           id)
   url
   speak))
(defun emacsvox-we-extract-by-id-list(ids   url &optional speak)
  "Extract elements having id specified in list `ids' from HTML.
Extracts specified elements from current WWW page and displays it in a
separate buffer. Interactive use provides list of id values as completion. "
  (interactive
   (list
    (emacsvox-we-get-id-list)
    (ems--read-url)
    (or (called-interactively-p 'interactive) current-prefix-arg)))
  (let ((filter
         (mapconcat
          #'(lambda  (c)
              (format "(@id=\"%s\")" c))
          ids
          " or ")))
    (emacsvox-we-xslt-filter
     (format "//*[%s]" filter)
     url
     (or (called-interactively-p 'interactive)
         speak))))

(defvar emacsvox-we-url-rewrite-rule nil
  "URL rewrite rule to use in current buffer.")

(make-variable-buffer-local 'emacsvox-we-url-rewrite-rule)
(defvar emacsvox-we-class-filter nil
  "Buffer local class filter.")

(make-variable-buffer-local 'emacsvox-we-class-filter)

(defun emacsvox-we-class-follow-and-filter (class url &optional _prompt)
  "Follow url and point, and filter the result by specified class.
Class can be set locally for a buffer, and overridden with an
interactive prefix arg. If there is a known rewrite url rule, that is
used as well."
  (interactive
   (list
    (cond
     ((and (not current-prefix-arg)emacsvox-we-class-filter)
      emacsvox-we-class-filter)
     (t
      (setq emacsvox-we-class-filter
            (read-from-minibuffer
             "Class: "
             nil nil nil nil
             "article"))))
    (ems--read-url)
    current-prefix-arg))
  (let ((redirect nil))
    (when emacsvox-we-url-rewrite-rule
      (setq redirect
            (replace-regexp-in-string
             (cl-first emacsvox-we-url-rewrite-rule)
             (cl-second emacsvox-we-url-rewrite-rule)
             url)))
    (emacsvox-we-extract-by-class
     class
     (or redirect url)
     'speak)
    (emacsvox-icon 'open-object)))

(defvar emacsvox-we-id-filter nil
  "Buffer local id filter.")

(make-variable-buffer-local 'emacsvox-we-id-filter)

(defun emacsvox-we-follow-and-filter-by-id (id _prompt)
  "Follow url and point, and filter the result by specified id.
Id can be set locally for a buffer, and overridden with an
interactive prefix arg. If there is a known rewrite url rule, that is
used as well."
  (interactive
   (list
    (cond
     ((and (not current-prefix-arg)emacsvox-we-id-filter)
      emacsvox-we-id-filter)
     (t
      (setq emacsvox-we-id-filter
            (read-from-minibuffer "Id: "))))
    current-prefix-arg))
  (emacsvox-eww-browser-check)
  (let ((url (funcall emacsvox-eww-url-at-point))
        (redirect nil))
    (unless url
      (error "Not on a link."))
    (when emacsvox-we-url-rewrite-rule
      (setq redirect
            (replace-regexp-in-string
             (cl-first emacsvox-we-url-rewrite-rule)
             (cl-second emacsvox-we-url-rewrite-rule)
             url)))
    (emacsvox-we-extract-by-id
     id
     (or redirect url)
     'speak)))

(defun emacsvox-we-style-filter (style   url &optional speak)
  "Extract elements matching specified style
from HTML.  Extracts specified elements from current WWW
page and displays it in a separate buffer.  Optional arg url
specifies the page to extract contents  from."
  (interactive
   (list
    (read-from-minibuffer "Style: ")
    (ems--read-url)
    current-prefix-arg))
  (emacsvox-we-xslt-filter
   (format "//*[contains(@style,  \"%s\")]" style)
   url
   (or (called-interactively-p 'interactive) speak)))

;;;  xpath  filter
(defvar emacsvox-we-recent-xpath-filter
  "//p"
  "Caches most recently used xpath filter.")

(defvar emacsvox-we-xpath-history 
  (list
   emacsvox-we-recent-xpath-filter
   "//p|//div"
   "//p|//ol|//ul|//dl|//h1|//h2|//h3|//h4|//h5|//h6|//blockquote")
  "History list recording XPath filters we've used.")

(put 'emacsvox-we-xpath-history 'history-length 10)

(defvar emacsvox-we-xpath-filter nil
  "Buffer local variable specifying a XPath filter for following
urls.")

(make-variable-buffer-local 'emacsvox-we-xpath-filter)

(defvar emacsvox-we-paragraphs-xpath-filter
  "//p"
  "Filter paragraphs.")

(defun emacsvox-we-xpath-follow-and-filter (&optional prompt)
  "Follow url and point, and filter the result by specified xpath.
XPath can be set locally for a buffer, and overridden with an
interactive prefix arg. If there is a known rewrite url rule, that is
used as well."
  (interactive "P")
  (emacsvox-eww-browser-check)
  (let ((url (funcall emacsvox-eww-url-at-point))
        (redirect nil))
    (unless url (error "Not on a link."))
    (when emacsvox-we-url-rewrite-rule
      (setq redirect
            (replace-regexp-in-string
             (cl-first emacsvox-we-url-rewrite-rule)
             (cl-second emacsvox-we-url-rewrite-rule)
             url)))
    (when (or prompt (null emacsvox-we-xpath-filter)
              (= 0 (length emacsvox-we-xpath-filter)))
      (setq emacsvox-we-xpath-filter
            (read-from-minibuffer
             "Specify XPath: "
             nil nil nil
             'emacsvox-we-xpath-history
             emacsvox-we-recent-xpath-filter))
      (cl-pushnew
       emacsvox-we-xpath-filter emacsvox-we-xpath-history
       :test #'string=)
      (setq emacsvox-we-recent-xpath-filter emacsvox-we-xpath-filter))
    (emacsvox-we-xslt-filter emacsvox-we-xpath-filter
                             (or redirect url)
                             'speak)))

(defvar emacsvox-we-class-history 
  nil
  "History list recording Class filters we've used.")

(put 'emacsvox-we-class-history 'history-length 10)

(defvar emacsvox-we-class-filter nil
  "Buffer local variable specifying a Class filter for following
urls.")

(make-variable-buffer-local 'emacsvox-we-class-filter)
(defvar emacsvox-we-recent-class-filter
  nil
  "Caches most recently used class filter.")

(defun emacsvox-we-class-follow-and-filter-link (&optional prompt)
  "Follow url and point, and filter the result by specified class.
Class can be set locally for a buffer, and overridden with an
interactive prefix arg. If there is a known rewrite url rule, that is
used as well."
  (interactive "P")
  (emacsvox-eww-browser-check)
  (let ((url (funcall emacsvox-eww-url-at-point))
        (redirect nil))
    (unless url (error "Not on a link."))
    (when emacsvox-we-url-rewrite-rule
      (setq redirect
            (replace-regexp-in-string
             (cl-first emacsvox-we-url-rewrite-rule)
             (cl-second emacsvox-we-url-rewrite-rule)
             url)))
    (when (or prompt (null emacsvox-we-class-filter))
      (setq emacsvox-we-class-filter
            (read-from-minibuffer
             "Specify Class: "
             nil nil nil
             'emacsvox-we-class-history
             emacsvox-we-recent-class-filter))
      (cl-pushnew
       emacsvox-we-class-filter emacsvox-we-class-history
       :test #'string=)
      (setq emacsvox-we-recent-class-filter
            emacsvox-we-class-filter))
    (emacsvox-we-xslt-filter
     (format "//*[@class=\"%s\"]"emacsvox-we-class-filter)
     (or redirect url)
     'speak)))

(defvar emacsvox-we-xpath-junk nil
  "Records XPath pattern used to junk elements.")

(make-variable-buffer-local 'emacsvox-we-xpath-junk)

(defvar emacsvox-we-recent-xpath-junk
  nil
  "Caches last XPath used to junk elements.")
(defun emacsvox-we-xpath-junk-and-follow (&optional prompt)
  "Follow url and point, and filter the result by junking
elements specified by xpath.
XPath can be set locally for a buffer, and overridden with an
interactive prefix arg. If there is a known rewrite url rule, that is
used as well."
  (interactive "P")
  (emacsvox-eww-browser-check)
  (let ((url (funcall emacsvox-eww-url-at-point))
        (redirect nil))
    (unless url
      (error "Not on a link."))
    (when emacsvox-we-url-rewrite-rule
      (setq redirect
            (replace-regexp-in-string
             (cl-first emacsvox-we-url-rewrite-rule)
             (cl-second emacsvox-we-url-rewrite-rule)
             url)))
    (when (or prompt
              (null emacsvox-we-xpath-junk))
      (setq emacsvox-we-xpath-junk
            (read-from-minibuffer  "Specify XPath: "
                                   emacsvox-we-recent-xpath-junk))
      (setq emacsvox-we-recent-xpath-junk
            emacsvox-we-xpath-junk))
    (emacsvox-we-xslt-junk
     emacsvox-we-xpath-junk
     (or redirect url)
     'speak)))

;;;  Property filter

;;;   xsl keymap

(cl-declaim (special emacsvox-we-xsl-map))

(cl-loop for binding in
         '(
           ("C" emacsvox-we-extract-by-class-list)
           ("C-c" emacsvox-we-junk-by-class-list)
           ("C-f" emacsvox-we-count-matches)
           ("C-p" emacsvox-we-xpath-junk-and-follow)
           ("C-t" emacsvox-we-count-tables)
           ("C-x" emacsvox-we-count-nested-tables)
           ("D" emacsvox-we-junk-by-class-list)
           ("I" emacsvox-we-extract-by-id-list)
           ("M" emacsvox-we-extract-tables-by-match-list)
           ("P" emacsvox-we-follow-and-extract-main)
           ("S" emacsvox-we-style-filter)
           ("T" emacsvox-we-extract-tables-by-position-list)
           ("X" emacsvox-we-extract-nested-table-list)
           ("]" emacsvox-we-url-rewrite-and-follow)
           ("a" emacsvox-we-xslt-apply)
           ("b" emacsvox-we-follow-and-filter-by-id)
           ("c" emacsvox-we-extract-by-class)
           ("d" emacsvox-we-junk-by-class)
           ("e" emacsvox-we-url-expand-and-execute)
           ("f" emacsvox-we-xslt-filter)
           ("i" emacsvox-we-extract-by-id)
           ("j" emacsvox-we-xslt-junk)
           ("k" emacsvox-we-toggle-xsl-keep-result)
           ("m" emacsvox-we-extract-table-by-match)
           ("o" emacsvox-we-xsl-toggle)
           ("p" emacsvox-we-xpath-follow-and-filter)
           ("r" emacsvox-we-extract-by-role)
           ("s" emacsvox-we-xslt-select)
           ("t" emacsvox-we-extract-table-by-position)
           ("u" emacsvox-we-extract-matching-urls)
           ("v" emacsvox-we-class-follow-and-filter-link)
                                        ;("w" emacsvox-we-extract-by-property)
           ("x" emacsvox-we-extract-nested-table)
           ("y" emacsvox-we-class-follow-and-filter)
           ("z" emacsvox-we-extract-speakable)
           )
         do
         (emacsvox-keymap-update emacsvox-we-xsl-map binding))

;;;   URL Advice: 

(defconst emacsvox-we--url-advice-targets
  '(url-history-save-history
    url-http-chunked-encoding-after-change-function
    url-cookie-handle-set-cookie url-retrieve-internal
    url-lazy-message url-cookie-write-file)
  "Current URL functions whose routine messages are silenced.")

(dolist (target emacsvox-we--url-advice-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-around" target))))
    (eval
     `(defun ,advice-function (orig-fun &rest args)
        ,(format "Call `%s' while silencing routine URL messages." target)
        (let ((url-show-status nil))
          (ems-with-messages-silenced
           (apply orig-fun args)))))))

(defun emacsvox-we--install-url-advice ()
  "Install native advice for URL features loaded so far."
  (dolist (target emacsvox-we--url-advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox)))))))

(dolist (feature '(url url-cookie url-history url-http))
  (eval `(with-eval-after-load ',feature
           (emacsvox-we--install-url-advice))))

(provide 'emacsvox-we)

;;; emacsvox-we.el ends here
