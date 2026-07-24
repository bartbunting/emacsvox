;;; emacsvox-eww.el --- Speech-enable EWW Browser  -*- lexical-binding: t; -*-
;; $Id: emacsvox-eww.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description: Speech-enable EWW An Emacs Interface to eww
;; Keywords: Emacsvox, Audio Desktop eww
;;;  LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;; $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;  Copyright:

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
;; MERCHANTABILITY or FITNEWW FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Commentary:

;; EWW == Emacs Web Browser
;;
;; EWW is a light-weight Web browser built into Emacs starting with
;; Emacs-24.4 . This module speech-enables EWW.
;;
;; It implements additional interactive commands for navigating the
;; DOM. It also provides a set of filters for interactively filtering
;; the DOM by various attributes such as id, class and role.
;; Finally, this module updates EWW's built-in key-bindings with
;; Emacsvox conveniences --- for a complete list of key-bindings,
;;invoke  command @code{describe-bindings} in an @code{EWW} buffer by
;;pressing @kbd{C-h b}.

;; @subsection Structured Navigation
;;
;; These commands move through section headers as defined in HTML.
;; @table @kbd
;; @item       1
;; @command{emacsvox-eww-next-h1}
;; Move to next @code{H1} heading.
;; @item       2
;; @command{emacsvox-eww-next-h2}
;; Move to next @code{H2} heading.
;; @item       3
;; @command{emacsvox-eww-next-h3}
;; Move to next @code{H3} heading.
;; @item       4
;; @command{emacsvox-eww-next-h4}
;; Move to next @code{H4} heading.
;; @item       .
;; @command{emacsvox-eww-next-h}
;; Move to next heading. (@code{H1}...@code{H4}).
;; @item       M-1
;; @command{emacsvox-eww-previous-h1}
;; Move to previous @code{H1} heading.
;; @item       M-2
;; @command{emacsvox-eww-previous-h2}
;; Move to previous @code{H2} heading.
;; @item       M-3
;; @command{emacsvox-eww-previous-h3}
;; Move to previous @code{H3} heading.
;; @item       M-4
;; @command{emacsvox-eww-previous-h4}
;; Move to previous @code{H4} heading.
;; @item  ,
;; @command{emacsvox-eww-previous-h}
;; Move to previous heading (@code{H1}...@code{H4}).
;; @end table
;;
;; This next set of DOM commands enable navigating by HTML elements.
;; @table @kbd
;; @item       M-SPC
;; @command{emacsvox-eww-speak-this-element}
;; Speak contents of current element.
;; @item       J
;; @command{emacsvox-eww-next-element-like-this}
;; Jump to next element that is the same as the one under point.
;; If there are multiple HTML elements under point,
;; prompts for element-name using completion.
;; @item       K
;; @command{emacsvox-eww-previous-element-like-this}
;; Jump to previous element that is the same as the one under point.
;; If there are multiple HTML elements under point,
;; prompts for element-name using completion.
;; @item  N
;; @command{emacsvox-eww-next-element-from-history}
;; Jump to next element based on  previous J/K command history.
;; @item       P
;; @command{emacsvox-eww-previous-element-from-history}
;; Jump to previous element based on  previous J/K history.
;; @item       O
;; @command{emacsvox-eww-previous-li}
;; Jump to previous list item.
;; @item       o
;; @command{emacsvox-eww-next-li}
;; Jump to next list item.
;; @item       T
;; @command{emacsvox-eww-previous-table}
;; Jump to previous table in page.
;; @item  t
;; @command{emacsvox-eww-next-table}
;; Jump to next table.
;; @item       [
;;             @command{emacsvox-eww-previous-p}
;;             Jump to previous paragraph.
;;             @item  ]
;; @command{emacsvox-eww-next-p}
;; Jump to next paragraph.
;; @item       b
;; @command{shr-previous-link}
;; Jump to previous link.
;; @item  f
;; @command{shr-next-link}
;; Jump to next link.
;; @item  n
;; @command{emacsvox-eww-next-element}
;; Jump to next element.
;; @item       p
;; @command{emacsvox-eww-previous-element}
;; Jump to previous element.
;; @item       s
;; @command{eww-readable}
;; Use EWW's built-in readable tool.
;; @item :
;; @command{emacsvox-eww-tags-at-point}
;; Display  currently active HTML tags at point.
;; @end table
;;

;; @subsection Filtering Content Using The DOM
;; These commands use EWW's HTML DOM to display different filtered
;; views of the Web page.
;; With an interactive prefix argument, these commands prompt for a
;; list of filters.
;; Command @command{emacsvox-eww-restore} bound to @kbd{DEL} can be used
;; to restore the previous view.
;;
;; @table @kbd
;; @item  A
;; @command{eww-view-dom-having-attribute}
;; Display DOM nodes having specified attribute. Valid attributes
;; are available via completion.
;; @item       C
;; @command{eww-view-dom-having-class}
;; Display DOM nodes having specified class. Valid classes
;; are available via completion.
;; @item  E
;; @command{eww-view-dom-having-elements}
;; Display specified elements from the Dom. Valid element names
;; are available via completion.
;; @item  I
;; @command{eww-view-dom-having-id}
;; Display DOM nodes having specified ID. Valid id values
;; are available via completion.

;; @item  M
;; @command{eww-view-dom-element-having-text}
;; lines containing pattern. Useful to filter down RSS feeds.
;; @item  R
;; @command{eww-view-dom-having-role}
;; Display DOM nodes having specified role. Valid roles
;; are available via completion.
;; @item       M-a
;; @command{eww-view-dom-not-having-attribute}
;; Filter out DOM nodes having specified attribute. Valid attribute values
;; are available via completion.
;; @item       M-c
;; @command{eww-view-dom-not-having-class}
;; Filter out DOM nodes having specified class. Valid class values
;; are available via completion.
;; @item       M-e
;; @command{eww-view-dom-not-having-elements}
;; Filter out  specified element DOM nodes. Valid element names
;; are available via completion.
;; @item       M-i
;; @command{eww-view-dom-not-having-id}
;; Dfilter out Display DOM nodes having specified ID. Valid id values
;; are available via completion.
;; @item       M-r
;; @command{eww-view-dom-not-having-role}
;; Filter out  DOM nodes having specified role. Valid role values
;; are available via completion.
;; @end table
;; @subsection Diving Into (Focusing) On Specific Content
;;
;; Contrast this with filtering described in the previous section.
;; There, we discussed commands that @strong{filter} the DOM to render
;; specific types of elements. For HTML as spoken on the Web, there
;; is a separate use-case that is helpful as a dual to filtering,
;; namely, displaying a specific portion of a page, typically the
;; contents of a @code{div} element.
;; These elements often appear many times on a page, and can be
;; deeply nested, making it difficult to focus on the relevant
;; content on the page, e.g. news sites.
;; Commands @code{emacsvox-eww-dive-into-div}
;; help  in such cases, @kbd{C-d} renders the @code{div} containing
;; point in a separate buffer
;;  As with the filtering commands, @kbd{l} returns to the
;; buffer where these commands were executed.
;; Long-term users of Emacsvox who still remember Emacs-W3 will
;; recognize this as the @strong{focus} command implemented by
;; Emacsvox for W3.
;; @subsection Updated  Commands For Following  Links

;; These key-bindings are available when point is on a link. They
;; enable context-specific actions for following links, e.g., to play
;; media streams, or to open various feed-types such as @code{ATOM},
;; @code{RSS}, or @code{OPML}.
;;
;;
;; @table @kbd
;; @item k
;; @command{shr-copy-url}
;; Copy URL under point to the kill-ring.
;; @item ;
;; @command{emacsvox-eww-play-media-at-point}
;; Play media URL under point using @code{emacs-m-player}.
;; Handles URL fragment as time-stamp where we resume; use @kbd{J} in
;; M-Player to jump to that offset.
;; @item u
;; @command{emacsvox-eww-url-to-register}
;;Accumulate url under point to register@code{u}.
;; Sample use-cases include building up a playlist of links in the
;; right sort order after a YT search.
;; @item x
;; @command{emacsvox-feeds-select-feed}
;; Display link under point as an @code{ATOM}, @code{OPML} or @code{RSS} feed.
;; @item y
;; @command{empv-play}
;; Play link -under point as a Youtube stream.
;; @end table
;;
;; @subsection Table Browsing

;; Summary Of Keyboard Commands:
;; @itemize
;; @item @kbd{M-<left>} emacsvox-eww-table-previous-cell@MDash{}
;; Speak previous cell.
;; @item @kbd{M-<right>} emacsvox-eww-table-next-cell @MDash{}
;; Speak previous cell.
;; @item @kbd{M-<up>} emacsvox-eww-table-previous-row @MDash{}
;; Speak cell above.
;; @item @kbd{M-<down>} emacsvox-eww-table-next-row @MDash{}
;; Speak  cell below.
;; @item @kbd{M-.} emacsvox-eww-table-speak-cell @MDash{}
;; Speak current cell.
;; @item @kbd{M-,} emacsvox-eww-table-speak-dimensions @MDash{}
;; Speak number of rows and columns.
;; @item @kbd{C-t} emacsvox-eww-table-data @MDash{}
;; Browse this table in Emacsvox's Table UI
;;  @MDash{} @xref{emacsvox-table-ui}.
;; @end itemize

;; Emacsvox EWW supports table navigation via keys @kbd{M-.},
;; @kbd{M-LEFT} and @kbd{M-RIGHT}, to speak the current, previous and
;; next table cell respectively. The latter commands also move to the
;; cell being spoken.  You can get a sense of the table's size via
;; @kbd{M-,} which speaks the number of rows and cells in the
;; table. This works for plain tables, not nested tables; for nested
;; tables, first have then @strong{unnested} using one of the XSLT
;; transforms like @code{sort-tables}.

;; @subsection Miscellaneous Commands

;; @table @kbd
;; @item ;
;;  @command{emacsvox-eww-play-audio/video}
;; When on an audio element, plays audio under point.
;; @item  C-RET
;; @command {emacsvox-eww-fillin-field}
;; When on an input field, insert  username/password information
;; accessed via auth-source.
;; @item '
;; @command{emacsvox-speak-rest-of-buffer}
;; Speak rest of current Web page starting from point.
;; @item *
;; @command{eww-add-bookmark}
;; Bookmark current Web page.
;; @item = @command{tts-toggle-punctuation-mode}
;; Toggle punctuation mode.
;; @item ?
;; @command{emacsvox-google-similar-to-this-page}
;; Google similarity search.
;; @item C-t
;; @item G @command{emacsvox-google-command}
;; Prefix key to invoke Google-specific commands.
;; @item L
;; @command{emacsvox-eww-links-rel}
;; Display any related links discovered via the document's @code{meta} tag.
;; @item Q
;; @command{emacsvox-kill-buffer-quietly}
;; Delete this buffer.
;; @item V
;; @command{eww-view-source}
;; Display Web page source.
;; @item e
;; @command{emacsvox-we-xsl-map}
;; Prefix key for invoking XSLT-based filters.
;; @item k
;; @command{eww-copy-page-url}
;; Copy page URL to kill-ring.
;; @end table
;;
;; In addition, see commands in
;; @xref{emacsvox-google},  for Google-Search specific commands, many of
;; which are available via prefix-key @kbd{G}.

;; @subsection Filtering Content Using XSLT And XPath

;; @table @kbd
;; @item C-c
;; @command{emacsvox-we-junk-by-class-list}
;; Prompts for list of class-names with completion,
;; and filters out matching elements.
;; @item C-f
;; @command{emacsvox-we-count-matches}
;; Prompts for XPath expression, and returns count of matching elements.
;; @item C-p
;; @command{emacsvox-we-xpath-junk-and-follow}
;; Follows link under point, and displays that page
;; after filtering by a specified XPath expression.
;; @item C-t
;; @command{emacsvox-we-count-tables}
;; Display a count of tables in the page.
;; @item C-x
;; @command{emacsvox-we-count-nested-tables}
;; Counts nested tables.
;; @item C
;; @command{emacsvox-we-extract-by-class-list}
;; Prompts for a list of class-names, and displays matching elements.
;; @item D
;; @command{emacsvox-we-junk-by-class-list}
;; Filters out elements  having specified class attributes.
;; @item I
;; @command{emacsvox-we-extract-by-id-list}
;; Extracts elements by specified list of ID values.
;; @item M
;; @command{emacsvox-we-extract-tables-by-match-list}
;; Extracts tables that match specified selection pattern.
;; @item P
;; @command{emacsvox-we-follow-and-extract-main}
;; Follows link under point, and extracts readable content,
;; by default, this is all paragraphs and headings.
;; @item S
;; @command{emacsvox-we-style-filter}
;; Filters content by style attribute.
;; @item T
;; @command{emacsvox-we-extract-tables-by-position-list}
;; Extracts tables by their position on the page.
;; @item X
;; @command{emacsvox-we-extract-nested-table-list}
;; Extracts nested tables.
;; @item a
;; @command{emacsvox-we-xslt-apply}
;; Prompt for and apply specified XSLT transform to current page.
;; @item b
;; @command{emacsvox-we-follow-and-filter-by-id}
;; Follow link under point, and filter by specified id value.
;; @item c
;; @command{emacsvox-we-extract-by-class}
;; Extracts elements by class.
;; @item d
;; @command{emacsvox-we-junk-by-class}
;; Filters out elements having specified class value.
;; @item e
;; @command{emacsvox-we-url-expand-and-execute}
;; Follow link under point, but pass the result to a custom executor.
;; Availability of special executors for link under point is indicated
;; by auditory icon @strong{item} instead of @strong{button}
;; You can then experiment by pressing @code{RET} or @code {e e}.
;; Special executors are available for Reddit Links, Wikipedia Links etc.
;; @item f
;; @command{emacsvox-we-xslt-filter}
;; Apply a specified XSLT filter (XPath) to current page.
;; @item i
;; @command{emacsvox-we-extract-by-id}
;; Extract elements by id value.
;; @item j
;; @command{emacsvox-we-xslt-junk}
;; Filter out elements matching specified pattern.
;; @item k
;; @command{emacsvox-we-toggle-xsl-keep-result}
;; Debugging tool  --- retains the  HTML source after XSLT.
;; @item m
;; @command{emacsvox-we-extract-table-by-match}
;; Extract matching table.
;; @item p
;; @command{emacsvox-we-xpath-follow-and-filter}
;; Follow link under point, and filter results by a specified XPath filter.
;; @item r
;; @command{emacsvox-we-extract-by-role}
;; Extract elements by specified role value.
;; @item s
;; @command{emacsvox-we-xslt-select}
;; Select default XSLT transform that is applied before rendering the page.
;; @item t
;; @command{emacsvox-we-extract-table-by-position}
;; Extracts tables by their position on the page.
;; @item u
;; @command{emacsvox-we-extract-matching-urls}
;; Display matching links on the page.
;; @item v
;; @command{emacsvox-we-class-follow-and-filter-link}
;; Follow link under point, and filter by specified class value.
;; @item w
;; @command{emacsvox-we-extract-by-property}
;; Extract element using a combination of DOM attributes.
;; @item x
;; @command{emacsvox-we-extract-nested-table}
;; Extract a nested table using a match-list.
;; @item y
;; @command{emacsvox-we-class-follow-and-filter}
;; Follow link under point and filter by class values.
;; @end table
;; @subsection EWW And EBooks On The Emacsvox Audio Desktop
;; Modules emacsvox-epub and emacsvox-bookshare provide EBook
;; front-ends to EPub-2 and Daisy EBooks. Both modules now use EWW to
;; render these EBooks. Module emacsvox-eww provides a simple
;; bookmarking facility --- called eww-marks (to avoid confusion with
;; EWW's Web Bookmarks). When reading an EBook, you can use @code{m}
;; to create an EWW-mark at that position. These marks are
;; automatically saved across Emacs sessions. To open a previously
;; created eww-mark, use command @code{emacsvox-eww-open-mark} bound
;; to @code{C-x r e}. This command reads a eww-mark name with
;; completion. Use this command with an interactive prefix arg to
;; delete a previously created eww-mark.
;;
;; @subsection Extracting Readable Content
;; By default, EWW includes a  simple @strong{readability} filter,
;; @code {eww-readable}   bound to @code{s}.
;; Emacsvox extends this facility with
;; @code{rdrview[ -- see @url{https://github.com/eafer/rdrview }]},
;; a command-line tool that extracts page contents using a
;; @strong{simplified view} filter that mirrors the implementation in Firefox.

;; You can use Emacsvox commands @code{emacsvox-eww-rdr- follow}
;; and @code{emacsvox-eww-rdr-reload} both bound to @code{S}  with
;; variable levels of success on various Web sites.
;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-eww-autospeak)
(defvar emacsvox-eww-el-cache)
(defvar emacsvox-eww-el-nav-history)
(defvar emacsvox-eww-filter-renderers)
(defvar emacsvox-eww-pre-process-hook)
(defvar emacsvox-eww-rename-buffer)
(defvar emacsvox-we-xsl-p)
(defvar emacsvox-we-xsl-transform)
(defvar eww-class-cache)
(defvar eww-id-cache)
(defvar eww-itemprop-cache)
(defvar eww-property-cache)
(defvar eww-role-cache)

;;  Required modules:

(eval-when-compile (require 'cl-lib))
(eval-when-compile(require 'subr-x))
(require 'emacsvox-preamble)
(require 'eww  )
(require 'dom)
(require 'dom-addons)
(require 'emacsvox-we)
(require 'emacsvox-google)
(require 'empv "empv" 'no-error)
(declare-function emacsvox-epub-eww
                  "emacsvox-epub" (epub-file &optional broken-ncx))
(declare-function
 emacsvox-m-player "emacsvox-m-player" (resource &optional play-list))

;;; Appease Emacs-30:

(declare-function iimage-recenter "iimage" (&optional arg))

;;;  Helpers:

;;;###autoload
(defsubst emacsvox-eww-browser-check ()
  "Browser check"
  (cl-assert  (eq major-mode 'eww-mode) t (error "Not in EWW")))

;; Return URL under point or URL read from minibuffer.

;; Generate functions emacsvox-eww-current-title and friends:

(cl-loop
 for name in
 '(title  source url dom)
 do
 (eval
  `(defun
       ,(intern (format "emacsvox-eww-current-%s" name)) ()
     , (format "Return eww-current-%s." name)
     
     (plist-get eww-data
                ,(intern (format ":%s" name)))))
 (eval
  `(defun
       ,(intern (format "emacsvox-eww-set-%s" name)) (value)
     , (format "Set eww-current-%s." name)
     (cl-assert (boundp 'eww-data) nil "Not a EWW rendered page.")
     (plist-put eww-data
                ,(intern (format ":%s" name))
                value))))

;;;  Declare generated functions:

(declare-function emacsvox-eww-current-dom "emacsvox-eww" nil)
(declare-function emacsvox-eww-current-title "emacsvox-eww" nil)
(declare-function emacsvox-eww-set-dom "emacsvox-eww" (dom))
(declare-function emacsvox-eww-set-url "emacsvox-eww" (url))
(declare-function emacsvox-eww-set-title "emacsvox-eww" (title))

;;;  Setup EWW Initialization:

(defvar emacsvox-eww-url-at-point
  #'(lambda ()
      (ems-with-messages-silenced
       (let ((url (shr-url-at-point nil)))
         (cond
          ((and url ;;; google  Result
                (stringp url)
                (string-prefix-p (emacsvox-google-result-url-prefix) url))
           (emacsvox-google-canonicalize-result-url url))
          ((and url (stringp url))url)
          (t (error "No URL under point."))))))
  "EWW Url At point that also handle google specialities.")

(add-hook
 'eww-mode-hook
 #'(lambda ()
     
     (outline-minor-mode)
     (emacsvox-pronounce-toggle-dictionaries t)))

(defun emacsvox-eww-shr-outline-toggle ()
  "Toggle between shr and native outliner."
  (interactive)
  
  (cond
   (outline-search-function             ;turn off emacs 30 version:
    (setq-local outline-regexp "^ *[•0-9]+\\.? "
                outline-level 'outline-level
                outline-search-function nil)
    (emacsvox-icon 'off)
    (message "Turned off SHR specific outliner"))
   (t                                   ; Turn on emacs 30 version:
    (setq outline-regexp nil
          outline-level 'shr-outline-level
          outline-search-function 'shr-outline-search)
    (emacsvox-icon 'on)
    (message "Turned on SHR specific outliner"))))

(defvar emacsvox-eww-masquerade t
  "Masquerade flag")

(defun emacsvox-eww-masquerade ()
  "Toggle masquerade."
  (interactive)
  
  (setq emacsvox-eww-masquerade (not emacsvox-eww-masquerade))
  (message "Turned %s masquerade"
           (if emacsvox-eww-masquerade "on" "off"))
  (emacsvox-icon (if emacsvox-eww-masquerade 'on 'off)))

(defvar  emacsvox-eww-masquerade-as
  (format "User-Agent: %s\r\n"
          "Mozilla/5.0 (X11; Linux x86_64) \
AppleWebKit/537.36 (KHTML, like Gecko) \
Chrome/117.0.0.0 \
Safari/537.36"
          )
  "User Agent string sent when masquerading.")

(defun emacsvox--advice-url-http-user-agent-string-filter-return (_)
  "Return the configured EWW user-agent header."
  (if emacsvox-eww-masquerade
      emacsvox-eww-masquerade-as
    "User-Agent: URL/Emacs \r\n"))

(advice-add
 'url-http-user-agent-string :filter-return
 #'emacsvox--advice-url-http-user-agent-string-filter-return
 '((name . emacsvox)))

(defcustom emacsvox-eww-inhibit-images nil
  "Turn this on to avoid rendering images."
  :type 'boolean

  :group 'emacsvox)

(declare-function emacsvox-feeds-feed-display
                  "emacsvox-feeds" (feed-url style &optional speak))

(defun emacsvox-eww-setup ()
  "Setup keymaps etc."
  (setq eww-header-line-format "%t ")
  (emacsvox-pronounce-augment 'eww-mode emacsvox-pronounce-xml-ns)
  (emacsvox-pronounce-add-dictionary-entry
   'eww-mode
   emacsvox-pronounce-rfc-3339-datetime-pattern
   (cons 're-search-forward 'emacsvox-speak-decode-rfc-3339-datetime))
  ;; turn off images on request
  (setq shr-inhibit-images emacsvox-eww-inhibit-images)
  ;; remove "I" "o" from eww-link-keymap
  (cl-loop
   for c in
   '("I" "o")
   do
   (keymap-unset eww-link-keymap c 'remove))
  (define-key eww-text-map  [C-return] 'emacsvox-eww-fillin-field)
  (define-key eww-link-keymap  "S" 'emacsvox-eww-rdr-follow)
  (define-key eww-link-keymap  "u" 'emacsvox-eww-url-to-register)
  (define-key eww-link-keymap  "!" 'emacsvox-eww-shell-cmd-on-url-at-point)
  (define-key eww-link-keymap  "k" 'shr-copy-url)
  (define-key eww-link-keymap ";" 'emacsvox-m-player-url)
  (define-key eww-link-keymap "Y" 'emacsvox-eww-yt-dl)
  (define-key eww-link-keymap "x" 'emacsvox-feeds-select-feed)
  (define-key eww-link-keymap  "y" 'emacsvox-empv-play-url)
  (cl-loop
   for binding  in
   '(

     ( "0" emacsvox-eww-shr-outline-toggle)
     ("'" emacsvox-speak-rest-of-buffer)
     ("*" eww-add-bookmark)
     ("," emacsvox-eww-previous-h)
     ("." emacsvox-eww-next-h)
     ("/" tts-toggle-punctuation-mode)
     ("1" emacsvox-eww-next-h1)
     ("2" emacsvox-eww-next-h2)
     ("3" emacsvox-eww-next-h3)
     ("4" emacsvox-eww-next-h4)
     (":" emacsvox-eww-tags-at-point)
     (";" emacsvox-eww-next-audio/video)
     ("?" emacsvox-google-similar-to-this-page)
     ("A" eww-view-dom-having-attribute)
     ("C" eww-view-dom-having-class)
     ("C-d" emacsvox-eww-dive-into-div)
     ("C-e" emacsvox-keymap)
     ("C-t" emacsvox-eww-table-data)
     ("DEL" emacsvox-eww-restore)
     ("E" eww-view-dom-having-elements)
     ("G" emacsvox-google-command)
     ("I" eww-view-dom-having-id)
     ("J" emacsvox-eww-next-element-like-this)
     ("K" emacsvox-eww-previous-element-like-this)
     ("L" emacsvox-eww-links-rel)
     ("M" eww-view-dom-element-having-text)
     ("M-," emacsvox-eww-table-speak-dimensions)
     ("M-." emacsvox-eww-table-speak-cell)
     ("M-0" emacsvox-eww-previous-h)
     ("M-1" emacsvox-eww-previous-h1)
     ("M-2" emacsvox-eww-previous-h2)
     ("M-3" emacsvox-eww-previous-h3)
     ("M-4" emacsvox-eww-previous-h4)
     ("M-;" emacsvox-eww-previous-audio/video)
     ("M-<down>"  emacsvox-eww-table-next-row)
     ("M-<left>" emacsvox-eww-table-previous-cell)
     ("M-<right>"  emacsvox-eww-table-next-cell)
     ("M-<up>"  emacsvox-eww-table-previous-row)
     ("M-SPC" emacsvox-eww-speak-this-element)
     ("M-a" eww-view-dom-not-having-attribute)
     ("M-c" eww-view-dom-not-having-class)
     ("M-e" eww-view-dom-not-having-elements)
     ("M-i" eww-view-dom-not-having-id)
     ("M-o" org-eww-copy-for-org-mode)
     ("M-r" eww-view-dom-not-having-role)
     ("N" emacsvox-eww-next-element-from-history)
     ("O" emacsvox-eww-previous-li)
     ("P" emacsvox-eww-previous-element-from-history)
     ("Q" emacsvox-kill-buffer-quietly)
     ("R" eww-view-dom-having-role)
     ("S" emacsvox-eww-rdr-reload)
     ("T" emacsvox-eww-previous-table)
     ("V" eww-view-source)
     ("[" emacsvox-eww-previous-p)
     ("\"" emacsvox-eww-reading-settings)
     ("]" emacsvox-eww-next-p)
     ("b" shr-previous-link)
     ("c" emacsvox-eww-browse-chrome)
     ("e" emacsvox-we-xsl-map)
     ("f" shr-next-link)
     ("k" eww-copy-page-url)
     ("m" emacsvox-eww-add-mark)
     ("n" emacsvox-eww-next-element)
     ("o" emacsvox-eww-next-li)
     ("p" emacsvox-eww-previous-element)
     ("s" eww-readable)
     ("t" emacsvox-eww-next-table)
     )
   do
   (emacsvox-keymap-update eww-mode-map binding))
  (setq shr-external-rendering-functions emacsvox-eww-filter-renderers))

;;; play media:

(defun emacsvox-eww-play-media-at-point (&optional  playlist-p)
  "Play media url under point.
Interprets url-fragment identifier #nnn as time-offset in
seconds.   Optional
interactive prefix arg `playlist-p' treats link as a playlist.  A
second interactive prefix arg adds mplayer option
-allow-dangerous-playlist-parsing"
  (interactive "P")
  (let ((url (browse-url-url-at-point)))
    (cl-assert (stringp url) t "No URL under point." )
    (kill-new url)
    (cl-pushnew                         ; strip #target
     (cl-first (split-string url "#"))
     emacsvox-m-player-media-history :test #'string=)
    (message " Playing url under point")
    (emacsvox-m-player-url url playlist-p)))

;;;  Inline Helpers:

(defun emacsvox-eww-prepare-eww ()
  "Ensure that we are in an EWW buffer."
  
  (unless (eq major-mode 'eww-mode) (error "Not in EWW buffer."))
  (unless (emacsvox-eww-current-dom) (error "No DOM!"))
  (unless emacsvox-eww-cache-updated
    (eww-update-cache (emacsvox-eww-current-dom))))

(defun emacsvox-eww-post-render-actions ()
  "Post-render actions."
  (emacsvox-eww-prepare-eww))

;;;  Viewing Page metadata: meta, links

(defun emacsvox-eww-links-rel ()
  "Display Link tags of type rel.  Web pages for which alternate links
are available are cued by an auditory icon on the header line."
  (interactive)
  (emacsvox-eww-prepare-eww)
  (let ((alt (dom-alternate-links (emacsvox-eww-current-dom)))
        (base (eww-current-url)))
    (cond
     ((null alt) (message "No alternate links."))
     (t
      (bury-buffer)
      (with-temp-buffer
        (insert "<ol>\n")
        (cl-loop
         for a in alt do
         (insert "<li>")
         (insert
          (format
           "<a href='%s'>%s</a>\n"
           (shr-expand-url (dom-attr a 'href) base)
           (or
            (dom-attr a 'title)
            (dom-attr a 'type)
            (dom-attr a 'media)
            (shr-expand-url (dom-attr a 'href) base))))
         (insert "</li>\n"))
        (insert "</ol>\n")
        (emacsvox-eww-autospeak)
        (browse-url-of-buffer))))))

;;;  Map Faces To Voices:

(voice-setup-add-map
 '(
   (shr-code  voice-monotone)
   (shr-sup  voice-animate)
   (shr-abbreviation  voice-bolden-extra)
   (shr-h1  voice-bolden)
   (shr-h2  voice-lighten)
   (shr-h3 voice-brighten)
   (shr-h4 voice-smoothen)
   (shr-h5 voice-animate)
   (shr-h6  voice-monotone)
   (eww-invalid-certificate  voice-lighten-extra)
   (eww-valid-certificate voice-bolden)
   (eww-form-submit voice-animate)
   (eww-form-checkbox voice-monotone-extra)
   (eww-form-select voice-animate)
   (eww-form-text voice-lighten)
   (eww-form-file voice-smoothen)
   (eww-form-textarea voice-brighten)
   (shr-selected-link  voice-animate)
   (shr-strike-through voice-annotate)))

;;;  Advice Interactive Commands:

(cl-loop
 for target in
 '(eww-up-url eww-top-url
              eww-next-url eww-previous-url
              eww-back-url eww-forward-url)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive EWW URL navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-speak-header-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defvar-local emacsvox-eww-style nil
  "Record if we applied an  xsl style in this buffer.")

(defvar-local emacsvox-eww-feed nil
  "Record if this eww buffer is displaying a feed.")

(defvar-local emacsvox-eww-url-template nil
  "Record if this eww buffer is displaying a url-template.")

;; Check cache if URL already open, otherwise cache.

(defun emacsvox--advice-eww-reload-around (original &rest arguments)
  "Check buffer local settings for feed buffers.\nIf buffer was result of displaying a feed, reload feed.\nIf we came from a url-template, reload that template.\nRetain previously set punctuations  mode."
  (add-hook 'emacsvox-eww-post-hook
            'emacsvox-eww-post-render-actions)
  (cond
   ((and (eww-current-url) emacsvox-eww-feed emacsvox-eww-style)
    (let
        ((r tts-speech-rate) (u (eww-current-url))
         (s emacsvox-eww-style))
      (kill-buffer)
      (add-hook 'emacsvox-eww-post-hook
                #'(lambda nil (tts-set-punctuations 'all)
                    (tts-set-rate r))
                'at-end)
      (emacsvox-feeds-feed-display u s 'speak)))
   ((and (eww-current-url) emacsvox-eww-url-template)
    (let ((n emacsvox-eww-url-template) (r tts-speech-rate))
      (add-hook 'emacsvox-eww-post-hook
                #'(lambda nil (tts-set-punctuations 'all)
                    (tts-set-rate r))
                'at-end)
      (kill-buffer)
      (emacsvox-url-template-open (emacsvox-url-template-get n))))
   (t
    (let ((result (apply original arguments)))
      (sox-sin 0.5 "%-2:%-1" "fade h .1 .5 .4 gain -8 ")
      result))))

(advice-add
 'eww-reload :around #'emacsvox--advice-eww-reload-around
 '((name . emacsvox-reload-wrapper)))

(cl-loop
 for target in
 '(eww eww-open-in-new-buffer eww-reload eww-open-file)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue after an interactive EWW open operation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defvar emacsvox-eww-rename-buffer t
  "Result buffer is renamed to document title.")

(defun emacsvox-eww-after-render-hook ()
  "Setup Emacsvox for rendered buffer. "
  
  (let ((title (emacsvox-eww-current-title))
        (alt (dom-alternate-links (emacsvox-eww-current-dom))))
    (when (= 0 (length title))
      (setq title "U")
      (sox-sin .5 "%-2:%-1""fade h .1 .5 .4 gain -8 "))
    (when emacsvox-eww-rename-buffer (rename-buffer title 'unique))
    (when alt
      (put-text-property 0 1 'auditory-icon 'mark-object  header-line-format))
    (emacsvox-speak-voice-annotate-paragraphs)
    (cond
     (emacsvox-eww-post-hook (emacsvox-eww-run-post-process-hook))
     (t (emacsvox-speak-header-line)))))

(add-hook 'eww-after-render-hook 'emacsvox-eww-after-render-hook)

(cl-loop
 for (target icon) in
 '((eww-add-bookmark mark-object)
   (eww-beginning-of-text large-movement)
   (eww-end-of-text mark-object)
   (eww-bookmark-browse open-object)
   (eww-bookmark-kill delete-object)
   (eww-bookmark-yank yank-object)
   (eww-list-bookmarks open-object))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue after an interactive EWW bookmark operation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon ',icon)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(eww-next-bookmark eww-previous-bookmark)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after EWW bookmark movement and cue interactive movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object))
       (emacsvox-speak-line))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;; Emacs 31 exits EWW through `quit-window'; `eww-quit' no longer exists.

(cl-loop
 for target in
 '(eww-change-select
   eww-toggle-checkbox
   eww-submit)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue after an interactive EWW form operation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'button)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))
(defvar-local emacsvox-eww-a-speaker nil
  "Specialized link speaker.")

(cl-loop
 for target in
 '(shr-next-link shr-previous-link)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive EWW link navigation."
       (when (ems-interactive-p ',target)
         (let ((host
                (condition-case nil
                    (url-host
                     (url-generic-parse-url
                      (funcall emacsvox-eww-url-at-point)))
                  (error ""))))
           (emacsvox-icon
            (if (or
                 emacsvox-we-url-executor
                 (string-match "reddit" host)
                 (string-match "wikipedia" host))
                'item
              'button)))
         (if emacsvox-eww-a-speaker
             (funcall emacsvox-eww-a-speaker)
           (emacsvox-speak-region
            (point)
            (next-single-property-change
             (point) 'help-echo nil (point-max))))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;; Handle emacsvox-we-url-executor

(defun emacsvox--advice-eww-follow-link-around (original &rest arguments)
  "Call ORIGINAL or offer the configured custom URL executor."
  (emacsvox-icon 'button)
  (let ((emacsvox-eww-masquerade t))
    (cond
     ((and (ems-interactive-p 'eww-follow-link)
           (functionp emacsvox-we-url-executor)
           (y-or-n-p "Use custom executor? "))
      (let ((url (get-text-property (point) 'shr-url)))
        (unless url (error "No URL  under point"))
        (funcall emacsvox-we-url-executor url)))
     (t (apply original arguments)))))

(advice-add
 'eww-follow-link :around
 #'emacsvox--advice-eww-follow-link-around
 '((name . emacsvox)))

;;;  web-pre-process

;;;###autoload
(defun emacsvox-eww-autospeak()
  "Setup post process hook to speak the first windowful . "
  (add-hook
   'emacsvox-eww-post-hook
   #'(lambda nil
       
       (setq emacsvox-we-xpath-filter
             emacsvox-we-paragraphs-xpath-filter)
       (tts-set-punctuations-to-some)
       (emacsvox-speak-windowful))
   'at-end))

;;;###autoload
(defvar emacsvox-eww-pre-process-hook nil
  "Pre-process hook -- to be used for XSL preprocessing etc.")

(defun emacsvox-eww-run-pre-process-hook (&rest _ignore)
  "Run web pre process hook."
  
  (when     emacsvox-eww-pre-process-hook
    (condition-case
        nil
        (let ((inhibit-read-only t))
          (run-hooks  'emacsvox-eww-pre-process-hook))
      ((debug error)  (message "Caught error  in pre-process hook.")
       (setq emacsvox-eww-pre-process-hook nil)))
    (setq emacsvox-eww-pre-process-hook nil)))

;;;  web-post-process

(defvar emacsvox-eww-post-hook nil
  "Set locally to a  site specific post processor.
Note that the Web browser should reset this hook after using it.")

(defun emacsvox-eww-run-post-process-hook (&rest _ignore)
  "Run web post process hook."
  
  (when     emacsvox-eww-post-hook
    (condition-case nil
        (let ((inhibit-read-only t))
          (run-hooks 'emacsvox-eww-post-hook))
      ((debug error)  (message "Caught error  in post-process hook.")
       (setq emacsvox-eww-post-hook nil)))
    (setq emacsvox-eww-post-hook nil)))

;;;  xslt transform on request:

(defun emacsvox--advice-eww-display-html-before (&rest _)
  "Apply XSLT transform if requested."
  (save-excursion
    (cond
     (emacsvox-eww-pre-process-hook
      (emacsvox-eww-run-pre-process-hook))
     ((and emacsvox-we-xsl-p emacsvox-we-xsl-transform)
      (emacsvox-xslt-region emacsvox-we-xsl-transform (point)
                            (point-max) emacsvox-we-xsl-params)))))

(advice-add
 'eww-display-html :before
 #'emacsvox--advice-eww-display-html-before
 '((name . emacsvox)))

;;;  DOM Structure In Rendered Buffer:

;; Handle MathML math element:

(defun shr-tag-math (dom)
  "Handle Math Nodes from MathML"
  (shr-ensure-newline)
  (shr-generic dom)
  (shr-ensure-newline))

(cl-loop
 for tag in
 '(h1 h2 h3 h4 h5 h6 div                ; sectioning
      math                              ; mathml
      ul ol dl                          ; Lists
      li dt dd p                        ; block-level: bullets, paras
      pre blockquote                    ; block-level
      a b i em span                     ; in-line
      table)
 for target = (intern (format "shr-tag-%s" tag))
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original dom)
       "Render DOM once, then add Emacsvox SHR navigation properties."
       (let ((origin (point))
             (result (funcall original dom)))
         (let ((start
                (if (char-equal (following-char) ?\n)
                    (min (point-max) (1+ origin))
                  origin))
               (end
                (if (> (point) origin)
                    (1- (point))
                  (point))))
           (put-text-property start end ',tag 'shr-tag)
           (when (memq ',tag '(h1 h2 h3 h4 h5 h6))
             (put-text-property start end 'h 'shr-tag)))
         result))
     (advice-add
      ',target :around #',function
      '((name . emacsvox-shr-tag))))))

;;;  Advice readable

(defun emacsvox--advice-eww-readable-around (original &rest arguments)
  "Call ORIGINAL once and speak the resulting readable contents."
  (let ((inhibit-read-only t))
    (let ((result (apply original arguments)))
      (emacsvox-icon 'open-object)
      (emacsvox-speak-buffer)
      result)))

(advice-add
 'eww-readable :around #'emacsvox--advice-eww-readable-around
 '((name . emacsvox)))

;;;   Customize image loading:

(defun emacsvox--advice-eww-display-image-around (original buffer)
  "Call ORIGINAL with BUFFER unless EWW image display is inhibited."
  (unless emacsvox-eww-inhibit-images
    (funcall original buffer)))

(advice-add
 'eww-display-image :around
 #'emacsvox--advice-eww-display-image-around
 '((name . emacsvox)))

;;;  element, class, role, id caches:

(defvar-local emacsvox-eww-cache-updated nil
  "Records if caches are updated.")

;; Mark cache to be dirty if we restore history:

(defun emacsvox--advice-eww-restore-history-after (&rest _)
  "Invalidate and rebuild EWW DOM caches after restoring history."
  (setq emacsvox-eww-cache-updated nil)
  (emacsvox-eww-prepare-eww))

(advice-add
 'eww-restore-history :after
 #'emacsvox--advice-eww-restore-history-after
 '((name . emacsvox)))

(defvar-local eww-id-cache nil
  "Cache of id values. Is buffer-local.")

(defvar-local eww-class-cache nil
  "Cache of class values. Is buffer-local.")

(defvar-local eww-role-cache nil
  "Cache of role values. Is buffer-local.")

(defvar-local eww-itemprop-cache nil
  "Cache of itemprop values. Is buffer-local.")

(defvar-local eww-property-cache nil
  "Cache of property values. Is buffer-local.")

;; Holds element names as strings.

(defvar-local emacsvox-eww-el-cache nil
  "Cache of element names. Is buffer-local.")

(defun eww-update-cache (dom)
  "Update element, role, class and id cache."
  (when (listp dom)                     ; build cache
    (let ((id (dom-attr dom 'id))
          (class (dom-attr dom 'class))
          (role (dom-attr dom 'role))
          (itemprop (dom-attr dom 'itemprop))
          (property (dom-attr dom 'property))
          (el (symbol-name (dom-tag dom)))
          (children (dom-children dom)))
      (when id (cl-pushnew id eww-id-cache :test #'string=))
      (when class
        (let ((classes (split-string class " ")))
          (cl-loop for c in classes do
                   (cl-pushnew c eww-class-cache :test #'string=))))
      (when itemprop (cl-pushnew itemprop eww-itemprop-cache :test #'string=))
      (when role (cl-pushnew role eww-role-cache :test #'string=))
      (when property (cl-pushnew property eww-property-cache :test #'string=))
      (when el (cl-pushnew el emacsvox-eww-el-cache :test #'string=))
      (when children (mapc #'eww-update-cache children)))
    (setq emacsvox-eww-cache-updated t)))

;;;  Filter DOM:
(defvar emacsvox-eww-audio-keymap
  (let  ((map (make-sparse-keymap)))
    (define-key map ";" 'emacsvox-eww-play-audio/video)
    map)
  "Keymap used on audio elements.")

(defun emacsvox-eww-tag-audio (dom)
  "Tag audio , then render."
  
  (let ((start (point)))
    (shr-tag-audio dom)
    (add-text-properties
     start (point)
     (list
      'keymap emacsvox-eww-audio-keymap
      'help-echo "; to play"
      'audio 'shr-tag))))

(defun emacsvox-eww-tag-video (dom)
  "Tag video tag, then render."
  
  (let ((start (point)))
    (shr-tag-video dom)
    (add-text-properties
     start (point)
     (list
      'keymap emacsvox-eww-audio-keymap
      'help-echo "; to play"
      'video 'shr-tag))))

(defun emacsvox-eww-tag-article (dom)
  "Tag article, then render."
  (let ((start (point)))
    (shr-generic dom)
    (put-text-property start (point) 'article 'shr-tag)))

(defun emacsvox-eww-tag-iframe (dom)
  "Iframe containing YT links"
  (let ((start (point))
        (src (dom-attr dom 'src)))
    (shr-generic dom)
    (insert (format "\nIFrame: %s\n\n" src))
    (shr-urlify  start src)
    (put-text-property start (point) 'iframe 'shr-tag)))

(defalias 'shr-tag-iframe 'emacsvox-eww-tag-iframe)

(defun emacsvox-eww-em-with-space  (dom)
  "render EM node but with space.."
  (insert " ")
  (shr-tag-em dom)
  (insert " "))

(defun emacsvox-eww-span-with-space  (dom)
  "render span  node but with space."
  (insert " ")
  (shr-tag-span dom)
  (insert " "))

(defun emacsvox-eww-strong-with-space  (dom)
  "render STRONG node but with space."
  (insert " ")
  (shr-tag-strong dom)
  (insert " "))
;;;###autoload
(defvar emacsvox-eww-shr-renderers
  '((article . emacsvox-eww-tag-article)
    (audio . emacsvox-eww-tag-audio)
    (iframe . emacsvox-eww-tag-iframe)
    (title . eww-tag-title)
    (video . emacsvox-eww-tag-video)
    (form . eww-tag-form)
    (input . eww-tag-input)
    (textarea . eww-tag-textarea)
    (math . shr-tag-math)
    (meta . eww-tag-meta)
    (button . eww-form-submit)
    (select . eww-tag-select)
    (link . eww-tag-link)
    (a . eww-tag-a))
  "Customize shr rendering for EWW.")
;; Create a special list of renderers to use when filtering
;;;###autoload
(defvar emacsvox-eww-filter-renderers
  (let ((copy (copy-sequence emacsvox-eww-shr-renderers)))
    (cl-pushnew (cons 'em 'emacsvox-eww-em-with-space) copy)
    (cl-pushnew (cons 'strong 'emacsvox-eww-strong-with-space) copy)
    (cl-pushnew (cons 'span 'emacsvox-eww-span-with-space) copy)
    copy)
  "Renderers used when filtering.")

(emacsvox-eww-setup)

(defun eww-dom-keep-if (dom predicate)
  "Return filtered DOM  keeping nodes that match  predicate.
 Predicate receives the node to test."
  (cond
   ((not (listp dom)) nil)
   ((funcall predicate dom) dom)
   (t
    (let ((filtered
           (delq nil
                 (mapcar
                  #'(lambda (node) (eww-dom-keep-if node predicate))
                  (dom-children dom)))))
      (when filtered
        (push (dom-attributes dom) filtered)
        (push (dom-tag dom) filtered))))))

(defun eww-dom-remove-if (dom predicate)
  "Return filtered DOM  dropping  nodes that match  predicate.
 Predicate receives the node to test."
  (cond
   ((not (listp dom)) dom)
   ((funcall predicate dom) nil)
   (t
    (let
        ((filtered
          (delq nil
                (mapcar #'(lambda (node) (eww-dom-remove-if  node predicate))
                        (dom-children dom)))))
      (when filtered
        (push (dom-attributes dom) filtered)
        (push (dom-tag dom) filtered) filtered)))))

(defun eww-attribute-list-tester (attr-list)
  "Return predicate that tests for attr=value from members of
attr-value list for use as a DOM filter."
  (eval
   `#'(lambda (node)
        (let (attr  value found)
          (cl-loop
           for pair in (quote ,attr-list)
           until found
           do
           (setq attr (cl-first pair)
                 value (cl-second pair))
           (setq found
                 (when (dom-attr  node attr)
                   (member value (split-string (dom-attr  node attr))))))
          (when found node)))))

(defun eww-attribute-tester (attr value)
  "Return predicate that tests for attr=value for use as a DOM filter."
  (eval
   `#'(lambda (node)
        (when
            (string= (dom-attr node (quote ,attr)) ,value) node))))

(defun eww-elements-tester (element-list)
  "Return predicate that tests for presence of element in element-list
for use as a DOM filter."
  (eval
   `#'(lambda (node)
        (when (memq (dom-tag node) (quote ,element-list)) node))))

(defun emacsvox-eww-view-helper  (filtered-dom)
  "View helper called by various filtering viewers."
  (let ((emacsvox-eww-rename-buffer nil)
        (url (eww-current-url))
        (title  (format "%s: Filtered" (emacsvox-eww-current-title)))
        (inhibit-read-only t)
        (shr-external-rendering-functions emacsvox-eww-filter-renderers))
    (eww-save-history)
    (erase-buffer)
    (goto-char (point-min))
    (condition-case
        nil
        (shr-insert-document filtered-dom)
      (error nil))
    (emacsvox-eww-set-dom filtered-dom)
    (emacsvox-eww-set-url url)
    (emacsvox-eww-set-title title)
    (set-buffer-modified-p nil)
    (goto-char (point-min))
    (setq buffer-read-only t))
  (setq eww-header-line-format "%t ")
  (eww-update-header-line-format)
  (emacsvox-icon 'open-object)
  (emacsvox-speak-buffer))

(defun emacsvox-eww-read-list (reader)
  "Return list of values  read using reader."
  (let (value-list  value done)
    (cl-loop
     until done
     do
     (setq value (funcall reader))
     (cond
      (value (cl-pushnew   value value-list :test #'string=))
      (t (setq done t))))
    value-list))

(defun emacsvox-eww-read-id ()
  "Return id value read from minibuffer."
  
  (unless eww-id-cache (error "No id to filter."))
  (let ((value (completing-read "Value: " eww-id-cache nil 'must-match)))
    (unless (zerop (length value)) value)))

(defun eww-view-dom-having-id (&optional multi)
  "Display DOM filtered by specified id=value test.
Optional interactive arg `multi' prompts for multiple ids."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom (emacsvox-eww-current-dom))
        (filter (if multi #'dom-by-id-list #'dom-by-id))
        (id  (if multi
                 (emacsvox-eww-read-list 'emacsvox-eww-read-id)
               (emacsvox-eww-read-id))))
    (setq dom (funcall filter dom id))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))))

(defun eww-view-dom-not-having-id (&optional multi)
  "Display DOM filtered by specified nodes not passing  id=value test.
Optional interactive arg `multi' prompts for multiple ids."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (emacsvox-eww-current-dom)
          (eww-attribute-list-tester
           (if multi
               (cl-loop
                for i in (emacsvox-eww-read-list 'emacsvox-eww-read-id)
                collect (list 'id i))
             (list (list 'id (emacsvox-eww-read-id))))))))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-add-base
        dom (eww-current-url))))))

(defun emacsvox-eww-read-attr-and-value ()
  "Read attr-value pair and return as a list."
  (unless (or eww-role-cache eww-id-cache eww-class-cache
              eww-itemprop-cache eww-property-cache)
    (error "No attributes to filter."))
  (let(attr-names attr value)
    (when eww-class-cache (push "class" attr-names))
    (when eww-id-cache (push "id" attr-names))
    (when eww-itemprop-cache (push "itemprop" attr-names))
    (when eww-property-cache (push "property" attr-names))
    (when eww-role-cache (push "role" attr-names))
    (setq attr (completing-read "Attr: " attr-names nil 'must-match))
    (unless (zerop (length attr))
      (setq attr (intern attr))
      (setq value
            (completing-read
             "Value: "
             (cond
              ((eq attr 'id) eww-id-cache)
              ((eq attr 'itemprop) eww-itemprop-cache)
              ((eq attr 'property) eww-property-cache)
              ((eq attr 'class)eww-class-cache)
              ((eq attr 'role)eww-role-cache))
             nil 'must-match))
      (list attr value))))

(defun eww-view-dom-having-attribute (&optional multi)
  "Display DOM filtered by specified attribute=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-keep-if
          (dom-child-by-tag (emacsvox-eww-current-dom) 'html)
          (eww-attribute-list-tester
           (if multi
               (emacsvox-eww-read-list 'emacsvox-eww-read-attr-and-value)
             (list  (emacsvox-eww-read-attr-and-value)))))))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-add-base dom   (eww-current-url))))))

(defun eww-view-dom-not-having-attribute (&optional multi)
  "Display DOM filtered by specified nodes not passing  attribute=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (dom-child-by-tag (emacsvox-eww-current-dom) 'html)
          (eww-attribute-list-tester
           (if multi
               (emacsvox-eww-read-list 'emacsvox-eww-read-attr-and-value)
             (list  (emacsvox-eww-read-attr-and-value)))))))
    (when dom
      (dom-html-add-base dom   (eww-current-url))
      (emacsvox-eww-view-helper dom))))

(defun emacsvox-eww-read-class ()
  "Return class value read from minibuffer."
  
  (unless eww-class-cache (error "No class to filter."))
  (let ((value (completing-read "Value: " eww-class-cache nil 'must-match)))
    (unless (zerop (length value)) value)))

(defun eww-view-dom-having-class (&optional multi)
  "Display DOM filtered by specified class=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom  (emacsvox-eww-current-dom))
        (filter (if multi #'dom-by-class-list #'dom-by-class))
        (class  (if multi
                    (emacsvox-eww-read-list 'emacsvox-eww-read-class)
                  (emacsvox-eww-read-class))))
    (setq dom (funcall filter dom class))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))))

(defun eww-view-dom-not-having-class (&optional multi)
  "Display DOM filtered by specified nodes not passing   class=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (emacsvox-eww-current-dom)
          (eww-attribute-list-tester
           (if multi
               (cl-loop
                for c in (emacsvox-eww-read-list 'emacsvox-eww-read-class)
                collect (list 'class c))
             (list (list 'class (emacsvox-eww-read-class))))))))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-add-base
        dom (eww-current-url))))))

(defun emacsvox-eww-read-role ()
  "Return role value read from minibuffer."
  
  (unless eww-role-cache (error "No role to filter."))
  (let ((value (completing-read "Value: " eww-role-cache nil 'must-match)))
    (unless (zerop (length value)) value)))

(defun emacsvox-eww-read-prop ()
  "Return property value read from minibuffer."
  
  (unless eww-property-cache (error "No property to filter."))
  (let ((value (completing-read "Value: " eww-property-cache nil 'must-match)))
    (unless (zerop (length value)) value)))

(defun emacsvox-eww-read-itemprop ()
  "Return itemprop value read from minibuffer."
  
  (unless eww-itemprop-cache (error "No itemprop to filter."))
  (let ((value (completing-read "Value: " eww-itemprop-cache nil 'must-match)))
    (unless (zerop (length value)) value)))

(defun eww-view-dom-having-role (multi)
  "Display DOM filtered by specified role=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom (emacsvox-eww-current-dom))
        (filter  (if multi #'dom-by-role-list #'dom-by-role))
        (role  (if multi
                   (emacsvox-eww-read-list 'emacsvox-eww-read-role)
                 (emacsvox-eww-read-role))))
    (setq dom (funcall filter dom role))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))))

(defun eww-view-dom-not-having-role (multi)
  "Display DOM filtered by specified  nodes not passing   role=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (emacsvox-eww-current-dom)
          (eww-attribute-list-tester
           (if multi
               (cl-loop
                for r in (emacsvox-eww-read-list 'emacsvox-eww-read-role)
                collect (list 'role r))
             (list (list 'role (emacsvox-eww-read-role))))))))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-add-base
        dom
        (eww-current-url))))))

(defun eww-view-dom-having-property (multi)
  "Display DOM filtered by specified property=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom (emacsvox-eww-current-dom))
        (filter  (if multi #'dom-by-property-list #'dom-by-property))
        (property  (if multi
                       (emacsvox-eww-read-list 'emacsvox-eww-read-prop)
                     (emacsvox-eww-read-prop))))
    (setq dom (funcall filter dom property))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))))

(defun eww-view-dom-not-having-property (multi)
  "Display DOM filtered by specified  nodes not passing   property=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (emacsvox-eww-current-dom)
          (eww-attribute-list-tester
           (if multi
               (cl-loop
                for r in (emacsvox-eww-read-list 'emacsvox-eww-read-prop)
                collect (list 'property r))
             (list (list 'property (emacsvox-eww-read-prop))))))))
    (when
        dom
      (emacsvox-eww-view-helper
       (dom-html-add-base dom
                          (eww-current-url))))))

(defun eww-view-dom-having-itemprop (multi)
  "Display DOM filtered by specified itemprop=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom (emacsvox-eww-current-dom))
        (filter  (if multi #'dom-by-itemprop-list #'dom-by-itemprop))
        (itemprop  (if multi
                       (emacsvox-eww-read-list 'emacsvox-eww-read-itemprop)
                     (emacsvox-eww-read-itemprop))))
    (setq dom (funcall filter dom itemprop))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))))

(defun eww-view-dom-not-having-itemprop (multi)
  "Display DOM filtered by specified  nodes not passing   itemprop=value test.
Optional interactive arg `multi' prompts for multiple classes."
  (interactive "P")
  
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (emacsvox-eww-current-dom)
          (eww-attribute-list-tester
           (if multi
               (cl-loop
                for r in
                (emacsvox-eww-read-list 'emacsvox-eww-read-itemprop)
                collect (list 'itemprop r))
             (list (list 'itemprop (emacsvox-eww-read-itemprop))))))))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-add-base
        dom (eww-current-url))))))
(defun emacsvox-eww-read-element ()
  "Return element  value read from minibuffer."
  
  (let ((value
         (completing-read "Value: " emacsvox-eww-el-cache nil 'must-match)))
    (unless (zerop (length value)) (intern value))))
(defun eww-view-dom-by-match (pattern)
  "Filter page keeping lines that match pattern."
  (interactive "sPattern:")
  (let ((inhibit-read-only  t))
    (keep-lines pattern)
    (goto-char (point-min))
    (emacsvox-speak-header-line)
    (emacsvox-icon 'open-object)))

(defun eww-view-dom-having-elements (&optional multi)
  "Display DOM filtered by specified elements.
Optional interactive prefix arg `multi' prompts for multiple elements."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom (emacsvox-eww-current-dom))
        (filter  (if multi #'dom-by-tag-list #'dom-by-tag))
        (tag (if multi
                 (emacsvox-eww-read-list 'emacsvox-eww-read-element)
               (emacsvox-eww-read-element))))
    (setq dom (funcall filter dom tag))
    (cond
     (dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))
     (t (message "Filtering failed.")))))

(defun eww-view-dom-element-having-text (element text &optional reverse )
  "Display DOM filtered by specific element instances  containing
  text. Optional interactive prefix arg `reverse'renders elements
  in reverse order."
  (interactive
   (progn
     (emacsvox-eww-prepare-eww)
     (list
      (emacsvox-eww-read-element)
      (read-from-minibuffer "Text:")
      current-prefix-arg)))
  
  (let ((dom (dom-by-tag  (emacsvox-eww-current-dom) element))
        (transform (if reverse 'nreverse 'identity)))
    (cond
     (                                 ; filter by text:
      (setq dom
            (funcall transform
                     (cl-remove-if-not
                      #'(lambda (node)
                          (string-match text (dom-inner-text node)))
                      dom)))
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url)))
      (emacsvox-icon 'open-object)
      (emacsvox-speak-header-line))
     (t (message "Filtering failed.")))))

(defun eww-view-dom-not-having-elements (multi)
  "Display DOM filtered by specified nodes not passing   el list.
Optional interactive prefix arg `multi' prompts for multiple elements."
  (interactive "P")
  (emacsvox-eww-prepare-eww)
  (let ((dom
         (eww-dom-remove-if
          (emacsvox-eww-current-dom)
          (eww-elements-tester
           (if multi
               (emacsvox-eww-read-list 'emacsvox-eww-read-element)
             (list  (emacsvox-eww-read-element)))))))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-add-base
        dom (eww-current-url))))))

(defun emacsvox-eww-restore ()
  "Restore buffer to pre-filtered canonical state."
  (interactive)
  
  (eww-restore-history(elt eww-history eww-history-position))
  (emacsvox-speak-header-line)
  (emacsvox-icon 'open-object))

;;;  Filters For Non-interactive  Use:

(defun eww-display-dom-filter-helper (filter arg)
  "Helper for display filters."
  (emacsvox-eww-prepare-eww)
  (let ((dom (funcall  filter  (emacsvox-eww-current-dom)arg)))
    (when dom
      (emacsvox-eww-view-helper
       (dom-html-from-nodes dom (eww-current-url))))))

(defun eww-display-dom-by-id (id)
  "Display DOM filtered by specified id."
  (eww-display-dom-filter-helper #'dom-by-id  id))

(defun eww-display-dom-by-id-list (id-list)
  "Display DOM filtered by specified id-list."

  (eww-display-dom-filter-helper #'dom-by-id-list  id-list))

(defun eww-display-dom-by-class (class)
  "Display DOM filtered by specified class."
  (eww-display-dom-filter-helper #'dom-by-class  class))

(defun eww-display-dom-by-class-list (class-list)
  "Display DOM filtered by specified class-list."

  (eww-display-dom-filter-helper #'dom-by-class-list  class-list))

(defun eww-display-dom-by-element (tag)
  "Display DOM filtered by specified tag."
  (eww-display-dom-filter-helper #'dom-by-tag  tag))

(defun eww-display-dom-by-element-list (tag-list)
  "Display DOM filtered by specified element-list."
  (eww-display-dom-filter-helper #'dom-by-tag-list  tag-list))

(defun eww-display-dom-by-role (role)
  "Display DOM filtered by specified role."
  (eww-display-dom-filter-helper #'dom-by-role  role))

(defun eww-display-dom-by-role-list (role-list)
  "Display DOM filtered by specified role-list."
  (eww-display-dom-filter-helper #'dom-by-role-list  role-list))

;;;  Element Navigation:

(defun emacsvox-eww-next-audio/video ()
  "Next audio element."
  (interactive)
  (let ((target
         (or (next-single-property-change (point) 'audio)
             (next-single-property-change (point) 'video))))
    (unless target  (user-error   "No  audio/video elements"))
    (goto-char target)
    (emacsvox-speak-line)
    (tts-notify "Press ; to play")
    (emacsvox-icon 'large-movement)))

(defun emacsvox-eww-previous-audio/video ()
  "Previous audio element."
  (interactive)
  (let ((target
         (or (previous-single-property-change (point) 'audio)
             (previous-single-property-change (point) 'video))))
    (unless target  (user-error   "No  audio/video elements"))
    (goto-char target)
    (emacsvox-speak-line)
    (tts-notify "Press ; to play")
    (emacsvox-icon 'large-movement)))

(defvar emacsvox-eww-el-nav-history nil
  "History for element navigation.")

(defun emacsvox-eww-next-element (el &optional speak)
  "Move forward to the next specified element."
  (interactive
   (list
    (progn
      (emacsvox-eww-prepare-eww)
      (intern
       (completing-read
        "Element: "
        emacsvox-eww-el-cache nil 'must-match
        nil 'emacsvox-eww-el-cache)))
    current-prefix-arg))
  (when (eq el 'li) ;; if element is li, use shr-indentation
    (setq el 'shr-continuation-indentation))
  (let* ((start (next-single-property-change (point) el))
         (next (next-single-property-change start el)))
    (cond
     ((and start next)
      (goto-char start)
      (setq emacsvox-eww-el-nav-history  el)
      (when (or emacsvox-eww-autospeak speak)
        (emacsvox-speak-region start next)))
     (t (message "Did not move.")))))

(defun emacsvox-eww-previous-element (el &optional speak)
  "Move backward  to the previous  specified element."
  (interactive
   (list
    (progn
      (emacsvox-eww-prepare-eww)
      (intern
       (completing-read
        "Element: " emacsvox-eww-el-cache nil 'must-match
        nil 'emacsvox-eww-ell-cache)))
    current-prefix-arg))
  (when (eq el 'li) ;; if element is li, use shr-indentation
    (setq el 'shr-continuation-indentation))
  (let* ((start (previous-single-property-change (point) el))
         (previous (previous-single-property-change  start  el)))
    (cond
     ((and start previous)
      (goto-char previous)
      (setq  emacsvox-eww-el-nav-history el)
      (when (or emacsvox-eww-autospeak speak)
        (emacsvox-speak-region start previous)))
     (t (message "Did not move.")))))

(defun emacsvox-eww-next-element-from-history ()
  "Uses element navigation history to decide where we jump."
  (interactive)
  
  (cond
   (emacsvox-eww-el-nav-history
    (funcall-interactively #'emacsvox-eww-next-element
                           emacsvox-eww-el-nav-history))
   (t (error "No elements in navigation history"))))

(defun emacsvox-eww-previous-element-from-history ()
  "Uses element navigation history to decide where we jump."
  (interactive)
  
  (cond
   (emacsvox-eww-el-nav-history
    (funcall-interactively #'emacsvox-eww-previous-element
                           emacsvox-eww-el-nav-history))
   (t (error "No elements in navigation history"))))

(defun emacsvox-eww-here-tags ()
  "Return list of enclosing tags at point."
  (let* ((eww-tags (text-properties-at (point))))
    (cl-loop
     for i from 0 to (1- (length eww-tags)) by 2
     if (eq (plist-get eww-tags (nth i eww-tags)) 'shr-tag)
     collect (nth i eww-tags))))

(defun emacsvox-eww-read-tags-like-this(&optional prompt)
  "Read tag for like-this navigation."
  (let ((tags (emacsvox-eww-here-tags)))
    (cond
     ((null tags) (error "No enclosing element here."))
     ((= 1 (length tags))  (cl-first tags))
     (t (intern
         (completing-read
          (or prompt "Jump to: ")
          (mapcar #'symbol-name tags)
          nil t
          nil emacsvox-eww-el-cache))))))

(defun emacsvox-eww-next-element-like-this (element)
  "Moves to next element like current.
Prompts if content at point is enclosed by multiple elements."
  (interactive
   (list (emacsvox-eww-read-tags-like-this)))
  (funcall-interactively #'emacsvox-eww-next-element  element))

(defun emacsvox-eww-previous-element-like-this (element)
  "Moves to next element like current.
Prompts if content at point is enclosed by multiple elements."
  (interactive
   (list (emacsvox-eww-read-tags-like-this)))
  (funcall-interactively #'emacsvox-eww-previous-element  element))

(defun emacsvox-eww-speak-this-element ()
  "Speak current ."
  (interactive)
  
  (cl-assert emacsvox-eww-el-nav-history t "No element here")
  (let  ((start
          (next-single-property-change (point) emacsvox-eww-el-nav-history)))
    (save-excursion
      (emacsvox-eww-next-element  emacsvox-eww-el-nav-history)
      (emacsvox-icon 'select-object)
      (emacsvox-speak-region start (point)))))

;; Generate next and previous structural navigators:
(defcustom emacsvox-eww-autospeak t
  "Turn this on to make section navigation autospeak.
This also reverses the meaning of the prefix-arg to section nav
  commands."
  :type 'boolean
  :group 'emacsvox-eww)

(cl-loop
 for  f in
 '(h h1 h2 h3 h4 h5 h6 li dt dd table ol ul dl p)
 do
 (eval
  `(defun ,(intern (format "emacsvox-eww-next-%s" f)) (&optional speak)
     ,(format
       "Move forward to the next %s.
Optional interactive prefix arg speaks the %s.  Second
interactive prefix toggles this flag.  See user option
`emacsvox-eww-autospeak' on how to reverse this behavior.
Second interactive prefix arg toggles default value of this flag.
The %s is automatically spoken if there is no user activity."
       f f f)
     (interactive "P")
     
     (let ((s (intern ,(format "%s" f))))
       (when (memq s '(h1 h2 h3 h4 h))
         (emacsvox-icon 'section))
       (when (eq s 'li)
         (emacsvox-icon 'item))
       (when (eq s 'p)
         (emacsvox-icon 'paragraph))
       (when (and speak (= 16 (car speak)))
         (setq emacsvox-eww-autospeak (not emacsvox-eww-autospeak)))
       (funcall-interactively #'emacsvox-eww-next-element s speak))))
 (eval
  `(defun ,(intern (format "emacsvox-eww-previous-%s" f)) (&optional speak)
     ,(format "Move backward to the next %s.
Optional interactive prefix arg speaks the %s.
Second interactive prefix toggles this flag.
See user option `emacsvox-eww-autospeak' on how to reverse this behavior.
The %s is automatically spoken if there is no user activity."
              f f f)
     (interactive "P")
     
     (let ((s (intern ,(format "%s" f))))
       (when (memq s '(h1 h2 h3 h4 h))
         (emacsvox-icon 'section))
       (when (eq s 'li)
         (emacsvox-icon 'item))
       (when (eq s 'p)
         (emacsvox-icon 'paragraph))
       (when (and speak (= 16 (car speak)))
         (setq emacsvox-eww-autospeak (not emacsvox-eww-autospeak)))
       (funcall-interactively #'emacsvox-eww-previous-element s)))))

(defun emacsvox--advice-google-url-filter-args (arguments)
  "Canonicalize a Google result URL in the first of ARGUMENTS."
  (let ((url (car arguments)))
    (if (and
         (stringp url)
         (string-prefix-p (emacsvox-google-result-url-prefix) url))
        (cons
         (emacsvox-google-canonicalize-result-url url)
         (cdr arguments))
      arguments)))

(dolist (target '(url-retrieve-internal url-truncate-url-for-viewing eww))
  (advice-add
   target :filter-args #'emacsvox--advice-google-url-filter-args
   '((name . emacsvox-cleanup-url))))

(cl-loop
 for target in
 '(shr-copy-url shr-maybe-probe-and-copy-url)
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original url)
       "Copy URL once, canonicalize Google results, and preserve the result."
       (ems-with-messages-silenced
         (let ((result (funcall original url)))
           (when (ems-interactive-p ',target)
             (emacsvox-icon 'delete-object)
             (let ((copied-url (car kill-ring)))
               (when
                   (and
                    (stringp copied-url)
                    (string-prefix-p
                     (emacsvox-google-result-url-prefix) copied-url))
                 (kill-new
                  (emacsvox-google-canonicalize-result-url copied-url))))
             (emacsvox-speak-current-kill))
           result)))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

;;;  Speech-enable EWW buffer list:

(defun emacsvox-eww-speak-buffer-line ()
  "Speak EWW buffer line."
  (cl-assert (eq major-mode 'eww-buffers-mode) nil
             "Not in an EWW buffer listing.")
  (let ((buffer (get-text-property (line-beginning-position) 'eww-buffer)))
    (if buffer
        (tts-speak (buffer-name buffer))
      (message "Can't find an EWW buffer for this line. "))))

(cl-loop
 for (target icon) in
 '((eww-list-buffers open-object)
   (eww-buffer-kill close-object))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive EWW buffer-list operation."
       (when (ems-interactive-p ',target)
         (emacsvox-icon ',icon)
         (emacsvox-eww-speak-buffer-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-eww-buffer-select-after (&rest _)
  "Cue and speak after interactively selecting an EWW buffer."
  (when (ems-interactive-p 'eww-buffer-select)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)
    (emacsvox-icon 'open-object)))

(advice-add
 'eww-buffer-select :after
 #'emacsvox--advice-eww-buffer-select-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(eww-buffer-show-next eww-buffer-show-previous)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive EWW buffer-list movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-eww-speak-buffer-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;   EWW Filtering shortcuts:

;;;  Tags At Point:

(defun emacsvox-eww-tags-at-point ()
  "Display tags at point."
  (interactive)
  (let ((tags (emacsvox-eww-here-tags)))
    (print tags)
    (tts-speak-list tags)))

;;;  Handling Media (audio/video)

;; This should ideally be handled through mailcap. At present, EWW
;; sets eww-use-external-browser-for-content-type to match
;; audio/video (only) and hands those off to
;; eww-browse-with-external-browser. Below, we advice
;; eww-browse-with-external-browser to use emacsvox-m-player
;; instead.

(defun emacsvox--advice-eww-browse-with-external-browser-around
    (original &optional url)
  "Send media URL to Emacsvox or call ORIGINAL for other URLs."
  (let ((url (or url ""))
        (case-fold-search t))
    (if (string-match emacsvox-media-extensions url)
        (emacsvox-m-player url)
      (funcall original url))))

(advice-add
 'eww-browse-with-external-browser :around
 #'emacsvox--advice-eww-browse-with-external-browser-around
 '((name . emacsvox)))

;;;  eww-marks:

;; Bookmarks for use in reading ebooks with EWW:
;; They are called eww-marks to distinguish them from web bookmarks

(defvar emacsvox-eww-marks-file
  (expand-file-name "eww-marks" emacsvox-user-directory)
  "File where we save EWW marks.")
(cl-defstruct emacsvox-eww-mark
  type                             ; daisy, epub, epub-3
  book                             ; pointer to book
  point                            ; location in book
  name                             ; name of mark
  )

(defun emacsvox-eww-marks-load ()
  "Load saved marks."
  (interactive)
  
  (when (file-exists-p emacsvox-eww-marks-file)
    (ems--fastload emacsvox-eww-marks-file)
    emacsvox-eww-marks))

(defvar emacsvox-eww-marks
  (cond
   ((file-exists-p emacsvox-eww-marks-file)
    (emacsvox-eww-marks-load))
   (t
    (make-hash-table :test #'equal)))
  "Stores   EWW-marks.")

(defun emacsvox-eww-add-mark (name)
  "Interactively add a mark with name title+`name' at current
  position.  Also store it as an org link for later insertion
into `notes'.`m"
  (interactive
   (list
    (concat
     (emacsvox-eww-current-title)": "
     (let ((input (read-from-minibuffer "Mark: " nil nil nil nil "current")))
       (if (zerop (length input))
           "current" input)))))
  (let ((bm
         (make-emacsvox-eww-mark
          :name name
          :type
          (cond
           ((bound-and-true-p emacsvox-epub-this-epub) 'epub)
           ((bound-and-true-p emacsvox-bookshare-this-book)'daisy)
           ((and (eww-current-url)
                 (string-match "^file:///" (eww-current-url))
                 (not (string-match "^file:///tmp" (eww-current-url))))
            'local-file)
           (t (error "EWW marks work in  EPub  and Bookshare buffers.")))
          :book
          (or
           (bound-and-true-p emacsvox-bookshare-this-book)
           (bound-and-true-p emacsvox-epub-this-epub)
           (substring (eww-current-url) 7))
          :point (point))))
    (puthash  name bm emacsvox-eww-marks)
    (emacsvox-eww-marks-save)
    (cl-pushnew `(,(concat "ebook:" name) ,name) org-stored-links)
    (emacsvox-icon 'mark-object)
    (message "Created  EWW mark %s." name)))

(defun emacsvox-eww-jump-to-mark (bm)
  "Jump to eww-mark `bm' if  there is a buffer displaying that content."
  (let ((book  (emacsvox-eww-mark-book bm))
        (type (emacsvox-eww-mark-type bm))
        (point (emacsvox-eww-mark-point bm))
        (buffer nil))
    (setq
     buffer
     (cond
      ((eq type 'local-file)
       (cl-find-if
        #'(lambda (b)
            (string= book (with-current-buffer b
                            (and (eww-current-url)
                                 (substring (eww-current-url) 7)))))
        (buffer-list)))
      ((eq type 'epub)
       (require 'emacsvox-epub)
       (cl-find-if
        #'(lambda (b)
            (string= book (with-current-buffer b emacsvox-epub-this-epub)))
        (buffer-list)))
      ((eq type 'daisy)
       (require 'emacsvox-bookshare)
       (cl-find-if
        #'(lambda (b)
            (string= book
                     (with-current-buffer b emacsvox-bookshare-this-book)))
        (buffer-list)))
      (t (error "Unknown book type %s" type))))
    (when buffer
      (funcall-interactively #'pop-to-buffer buffer)
      (when point (goto-char point))
      (emacsvox-icon 'large-movement)
      t)))

(defun emacsvox-eww-delete-mark (name)
  "Interactively delete a mark with name `name' at current position."
  (interactive "sMark Name: ")
  
  (remhash name emacsvox-eww-marks)
  (emacsvox-eww-marks-save)
  (emacsvox-icon 'delete-object)
  (message "Removed Emacsvox EWW mark %s" name))

(declare-function emacsvox-bookshare-eww "emacsvox-bookshare" (directory))

;;;###autoload
(defun emacsvox-eww-open-mark (name &optional delete)
  "Open EWW marked location.  With optional interactive prefix
arg `delete', delete that mark instead."
  (interactive
   (list
    (progn
      (when (hash-table-empty-p emacsvox-eww-marks)
        (error "No Emacsvox EWW Marks found."))
      (completing-read "Mark: " emacsvox-eww-marks))
    current-prefix-arg))
  
  (cond
   (delete (emacsvox-eww-delete-mark name)
           (emacsvox-icon 'delete-object))
   (t
    (let* ((bm (gethash name emacsvox-eww-marks))
           (handler nil)
           (type (emacsvox-eww-mark-type bm))
           (point (emacsvox-eww-mark-point bm))
           (book (emacsvox-eww-mark-book bm)))
      (cl-assert  type nil "Mark type is not set.")
      (cl-assert book nil "Book not set.")
      (cond
       ((emacsvox-eww-jump-to-mark bm) t) ;;; Found a buffer with
       ;; book open.
       (t ;;; so we need to first open the book:
        (setq handler
              (cond
               ((eq type 'daisy) #'emacsvox-bookshare-eww)
               ((eq type 'epub) #'emacsvox-epub-eww)
               ((eq type 'local-file) #'eww-open-file)
               (t (error "Unknown book type."))))
        (when point
          (add-hook
           'emacsvox-eww-post-hook
           #'(lambda ()
               (goto-char point)
               (delete-other-windows)
               (emacsvox-speak-windowful)
               (emacsvox-icon 'large-movement))
           'at-end)
          (when (eq type 'local-file)
            (add-hook 'emacsvox-eww-post-hook
                      #'emacsvox-speak-line
                      'at-end)))
        (funcall handler book)))))))

(defun emacsvox-eww-marks-save ()
  "Save Emacsvox EWW marks."
  (interactive)
  
  (when (hash-table-p emacsvox-eww-marks)
    (emacsvox--persist-variable 'emacsvox-eww-marks
                                emacsvox-eww-marks-file)))

(defvar emacsvox-eww-marks-save-timer
  (run-at-time 3600 3600  #'emacsvox-eww-marks-save)
  "Idle timer for saving EWW marks.")

(define-derived-mode emacsvox-eww-marks-mode special-mode
  "EWW Marks  Browser"
  "A light-weight mode for the `*Emacsvox EWW Marks Browser*'.
 1. Enables org integration via command
 `org-store-link' bound to \\[org-store-link].
 2. Stored links can be inserted into org files in the same directory
via command `org-insert-link' bound to \\[org-insert-link]."
  (setq header-line-format "EWW Marks Browser")
  t)

;;;###autoload
(defun emacsvox-eww-marks-browse ()
  "List EWW Marks as actionable buttons."
  (interactive)
  
  (let ((buffer (get-buffer-create "EWW Marks"))
        (inhibit-read-only t))
    (with-current-buffer buffer
      (emacsvox-eww-marks-mode)
      (erase-buffer)
      (setq buffer-undo-list  t)
      (cl-loop
       for k being the hash-keys of emacsvox-eww-marks do
       (insert-text-button
        (format "%s" k)
        'action
        #'(lambda (b) (emacsvox-eww-open-mark (button-label b))))
       (insert "\n"))
      (goto-char (point-min)))
    (funcall-interactively #'switch-to-buffer buffer)))

;;;  quick setup for reading:

(defun emacsvox-eww-reading-settings  ()
  "Setup speech-rate, punctuation and split-caps for reading prose."
  (interactive)
  
  (tts-set-rate (+ tts-speech-rate-base (* tts-speech-rate-step  3)))
  (tts-set-punctuations 'all)
  (when tts-split-caps(tts-toggle-split-caps))
  (emacsvox-speak-rest-of-buffer))

;;;  Shell Command On URL Under Point:
(defvar emacsvox-eww-url-shell-commands
  (delete nil
          (list
           (expand-file-name "cbox" emacsvox-etc-directory)))
  "Shell commands we permit on URL under point.")

(defun emacsvox-eww-shell-cmd-on-url-at-point (&optional prompt)
  "Run specified shell command on URL at point. "
  (interactive "P")
  
  (let ((url
         (or (shr-url-at-point nil)
             (browse-url-url-at-point)))
        (cmd
         (if prompt
             (completing-read "Shell Command: "
                              emacsvox-eww-url-shell-commands)
           (cl-first emacsvox-eww-url-shell-commands))))
    (cl-assert url t "No url found")
    (async-shell-command (format "%s '%s'" cmd url))
    (emacsvox-icon 'task-done)))

;;; Smart Tabs:

(defvar emacsvox-eww-smart-tabs
  (make-hash-table :test #'eq)
  "Cache of  URL->Tabs mappings.")

(defsubst emacsvox-eww-smart-tabs-put (key url)
  " Add a  `URL'tou our smart tabs cache. "
  
  (puthash key url emacsvox-eww-smart-tabs))

(defsubst emacsvox-eww-smart-tabs-get (key)
  "Retrieve URL stored in `KEY'"
  
  (gethash key  emacsvox-eww-smart-tabs))

(defun emacsvox-eww-smart-tabs-add (char url )
  "Add a URL to the specified location in smart tabs."
  (interactive
   (list
    (read-char-exclusive "Tab:")
    (read-from-minibuffer "URL:")))
  
  (emacsvox-eww-smart-tabs-put char url)
  (emacsvox-icon 'close-object))

;;;###autoload
(defun emacsvox-eww-smart-tabs (char &optional define)
  "Open URL in EWW keyed by  `char'.
To associate a URL with a char, use this command
with an interactive prefix arg. "
  (interactive
   (list
    (read-char-exclusive "EWWTab:")
    current-prefix-arg))
  
  (unless
      (and
       (bound-and-true-p emacsvox-eww-smart-tabs)
       (not (hash-table-empty-p emacsvox-eww-smart-tabs)))
    (emacsvox-eww-smart-tabs-load))
  (when define
    (emacsvox-eww-smart-tabs-add char (read-from-minibuffer "URL:")))
  (let ((url (emacsvox-eww-smart-tabs-get char)))
    (cl-assert (stringp url) t "No URL stored in this location.")
    (emacsvox-icon 'button)
    (eww url)))

(defun emacsvox-eww-smart-tabs-save ()
  "Save our smart tabs to a file for reloading."
  (interactive)
  (when
      (and
       (bound-and-true-p emacsvox-eww-smart-tabs)
       (not (hash-table-empty-p emacsvox-eww-smart-tabs)))
    (emacsvox--persist-variable
     'emacsvox-eww-smart-tabs
     (expand-file-name "smart-eww-tabs" emacsvox-user-directory))))

(add-hook
 'kill-emacs-hook
 #'emacsvox-eww-smart-tabs-save)

(defun emacsvox-eww-smart-tabs-load ()
  "Load our smart tabsfrom a file."
  (interactive)
  
  (when
      (file-exists-p
       (expand-file-name "smart-eww-tabs" emacsvox-user-directory))
    (ems--fastload
     (expand-file-name "smart-eww-tabs" emacsvox-user-directory))))

;;; Form filling:

(defun emacsvox-eww-fillin-field ()
  "Fill in user or passwd field using auth-source backend."
  (interactive)
  (emacsvox-eww-browser-check)
  (let ((url (eww-current-url))
        (result nil))
    (cl-assert url t "No current url")
    (setq result
          (cl-case
              (read-char "u  User, p Password")
            (?u  (url-user-for-url url))
            (?p  (url-password-for-url url))
            (otherwise nil)))
    (cl-assert result t "No value found to insert here")
    (when result (insert result))
    (emacsvox-speak-line)))

;;; Enable Table Browsing:

;; Only works for plain tables, not nested tables.
;; Point has to be within the displayed table.
;; Property values are part of the content,
;; And consequently the DOM ends up pointing back at itself.
;; This makes looking at the DOM hard, doesn't appear to have any
;; other negatives.
;; Overlays may avoid this problem.

(defun emacsvox--advice-shr-tag-table-1-around (original dom)
  "Render DOM once and cache its table metadata on the inserted text."
  (let ((start (point))
        (result (funcall original dom)))
    (unless (get-text-property start 'table-dom)
      (add-text-properties
       start (point)
       (list 'auditory-icon 'fill-object
             'table-start start
             'table-end (1- (point))
             'table-dom dom)))
    result))

(advice-add
 'shr-tag-table-1 :around
 #'emacsvox--advice-shr-tag-table-1-around
 '((name . emacsvox-table-dom)))

(defvar-local emacsvox-eww-table-cell 0
  "Track current table cell to enable table navigation.
Value is specified as a position in the list of table cells.")

(defsubst emacsvox-eww-table-table ()
  "Return table cells as a table, a 2d structure."
  (let* ((data nil)
         (table (get-text-property (point) 'table-dom))
         (head (dom-by-tag table 'th)))
    (cl-assert table t "No table here.")
    (setq data
          (cl-loop
           for r in (dom-by-tag table 'tr) collect
           (cl-loop
            for c in
            (append
             (dom-by-tag r 'th)
             (dom-by-tag r 'td))
            collect
            (string-trim (dom-node-as-text c)))))
    ;;; handle head case differently:
    (if head
        (apply #'vector (mapcar #'vconcat  (cdr data)))
      (apply #'vector (mapcar #'vconcat  data)))))

(defsubst emacsvox-eww-table-cells ()
  "Returns  table cells as a list."
  (let* ((table (get-text-property (point) 'table-dom))
         (head (dom-by-tag table 'th)))
    (cond
     (head (cdr (append head (dom-by-tag table 'td))))
     (t (dom-by-tag table 'td)))))

(defsubst emacsvox-eww-table-row-count ()
  "Returns number of table rows."
  (length (dom-by-tag (get-text-property (point) 'table-dom) 'tr)))

(defsubst emacsvox-eww-table-cell-count ()
  "Returns number of  table cells."
  (length (emacsvox-eww-table-cells)))

(defun emacsvox-eww-table-speak-dimensions ()
  "Speak number of rows and cells."
  (interactive)
  (tts-speak
   (format "Table with %s rows and %s cells"
           (emacsvox-eww-table-row-count) (emacsvox-eww-table-cell-count))))

(defsubst emacsvox-eww-table-speak-cell ()
  "Speak current cell."
  (interactive)
  
  (tts-speak
   (dom-node-as-text
    (elt (emacsvox-eww-table-cells) emacsvox-eww-table-cell))))

(defun emacsvox-eww-table-previous-row (&optional prefix)
  "Speak  cell after moving to previous row.
 Optional interactive prefix arg moves to start of table."
  (interactive "P")
  
  (emacsvox-eww-browser-check)
  (cond
   (prefix
    (goto-char (get-text-property (point) 'table-start))
    (setq emacsvox-eww-table-cell 0))
   (t
    (let* ((n-rows (emacsvox-eww-table-row-count))
           (n-cells (emacsvox-eww-table-cell-count))
           (quotient (/ n-cells n-rows)))
      (cl-assert
       (>= emacsvox-eww-table-cell quotient)
       t "On first row.")
      (cl-decf emacsvox-eww-table-cell quotient)
      (emacsvox-icon 'large-movement)
      (emacsvox-eww-table-speak-cell)))))

(defun emacsvox-eww-table-next-row (&optional prefix)
  "Speak  cell after moving to next row.
 Optional interactive prefix arg moves to end of table."
  (interactive "P")
  
  (emacsvox-eww-browser-check)
  (cond
   (prefix
    (goto-char (get-text-property (point) 'table-end))
    (setq
     emacsvox-eww-table-cell
     (1- (length (emacsvox-eww-table-cells)))))
   (t
    (let* ((n-rows (emacsvox-eww-table-row-count))
           (n-cells (emacsvox-eww-table-cell-count))
           (quotient (/ n-cells n-rows)))
      (cl-assert
       (< (+ emacsvox-eww-table-cell quotient) n-cells)
       t "On last row.")
      (cl-incf emacsvox-eww-table-cell quotient)
      (emacsvox-icon 'large-movement)
      (emacsvox-eww-table-speak-cell)))))

(defun emacsvox-eww-table-next-cell (&optional prefix)
  "Speak next cell after making it current.
Interactive prefix arg moves to the last cell in the table."
  (interactive "P")
  
  (emacsvox-eww-browser-check)
  (cl-assert
   (< (1+ emacsvox-eww-table-cell) (length (emacsvox-eww-table-cells)))
   t "On last cell.")
  (cond
   (prefix
    (goto-char (get-text-property (point) 'table-end))
    (cl-incf emacsvox-eww-table-cell
             (1- (length (emacsvox-eww-table-cells)))))
   (t
    (goto-char (next-single-property-change (point) 'display))
    (skip-syntax-forward " ")
    (cl-incf emacsvox-eww-table-cell 1)
    (goto-char (next-single-property-change (point) 'display))))
  (emacsvox-icon 'left)
  (emacsvox-eww-table-speak-cell))

(defun emacsvox-eww-table-previous-cell (&optional prefix)
  "Speak previous cell after making it current.
With interactive prefix arg, move to the start of the table."
  (interactive "P")
  
  (emacsvox-eww-browser-check)
  (when  (zerop emacsvox-eww-table-cell  ) (error  "On first cell."))
  (cond
   (prefix
    (goto-char (get-text-property (point) 'table-start))
    (setq emacsvox-eww-table-cell 0)
    (goto-char (get-text-property (point) 'table-start)))
   (t
    (goto-char (previous-single-property-change (point) 'display))
    (skip-syntax-backward " ")
    (cl-decf emacsvox-eww-table-cell 1)))
  (emacsvox-icon 'right)
  (emacsvox-eww-table-speak-cell))

(defun emacsvox-eww-table-data ()
  "View  table at point as a data table using Emacsvox Table UI."
  (interactive)
  (let ((data (emacsvox-eww-table-table))
        (data-table nil)
        (inhibit-read-only  t)
        (buffer
         (get-buffer-create
          (format  "Table: %s" (emacsvox-eww-current-title)))))
    (setq data-table (emacsvox-table-make-table data))
    (emacsvox-table-prepare-table-buffer data-table buffer)))

;;; Dive Into DOM: div

(defun emacsvox--advice-shr-tag-div-dom-around (original dom)
  "Render DOM once and cache it on the inserted div text."
  (let ((start (point))
        (result (funcall original dom)))
    (unless (get-text-property start 'eww-dom)
      (put-text-property start (point) 'eww-dom dom))
    result))

(advice-add
 'shr-tag-div :around
 #'emacsvox--advice-shr-tag-div-dom-around
 '((name . emacsvox-div-dom)))

(defun emacsvox-eww-dive-into-div ()
  "Focus on current div by rendering it in a new buffer."
  (interactive)
  (cl-assert (memq 'div (emacsvox-eww-here-tags) ) t "No div here.")
  (let ((dom (get-text-property (point) 'eww-dom)))
    (emacsvox-eww-view-helper
     (dom-html-from-nodes (list dom) (eww-current-url)))))

;;; Open With External Browser:  Chrome

(defun emacsvox-eww-browse-chrome (url)
  "Open with Chrome."
  (interactive (list (ems--read-url)))
  (browse-url-chrome url))

;;; Repeat Support:
(put 'emacsvox-eww-play-media-at-point
     'repeat-map  'emacsvox-m-player-mode-map)

;;; youtube-dl downloader:

(defun emacsvox-eww-yt-dl (url)
  "Download link at point   using youtube-dl --- works with BBC Sounds. "
  (interactive
   (list (car (browse-url-interactive-arg "Media URL: ")))
   eww-mode)
  
  (cl-assert emacsvox-ytdl t "Install youtube-dl first.")
  (let ((dir (funcall eww-download-directory)))
    (access-file dir "Cannot download here")
    (async-shell-command (format "cd %s;%s '%s'" dir emacsvox-ytdl url))))

(defun emacsvox-eww-url-to-register ()
  "Accumulate  URL in register `u'"
  (interactive)
  (emacsvox-accumulate-to-register ?u #'(lambda () (shr-url-at-point nil))))
;;; Audio element at point:

(defun emacsvox-eww-play-audio/video ()
  "Play audio/video tag at point"
  (interactive)
  (emacsvox-icon 'button)
  (let ((url (get-text-property (point ) 'shr-url)))
    (if url
        (emacsvox-empv-play-url url)
      (message "No URL here to play"))))

(put 'emacsvox-eww-play-audio/video 'repeat-map 'empv-map)

;;; RDR View:
;; inspired by
;; https://jiewawa.me/2024/04/\
;; another-way-of-integrating-mozilla-readability-in-emacs-eww/

(defconst emacsvox-eww-rdr (executable-find "rdrview")
  "Executable: rdrview.")

(defconst emacsvox-eww-rdr-cmd
  (when emacsvox-eww-rdr
    (list emacsvox-eww-rdr    "-T"   "title,sitename,body"   "-H"  ))
  "Command-line to invoke rdrview.")

(defun emacsvox-eww-rdr-reload ()
  "Reload current Web page using `emacsvox-eww-rdr'."
  (interactive)
  (cl-assert (eq major-mode 'eww-mode) t "Not in an EWW buffer.")
  (let ((eww-retrieve-command   emacsvox-eww-rdr-cmd))
    (emacsvox-eww-autospeak)
    (eww-reload)))

(defun emacsvox-eww-rdr-follow ()
  "Follow link under point, but use rdr to load page."
  (interactive)
  (cl-assert (eq major-mode 'eww-mode) t "Not in an EWW buffer.")
  (let ((eww-retrieve-command   emacsvox-eww-rdr-cmd))
    (emacsvox-eww-autospeak)
    (call-interactively #'eww-follow-link)))

(provide 'emacsvox-eww)

;;;  end of file
