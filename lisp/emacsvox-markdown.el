;;; emacsvox-markdown.el --- Speech-enable Markdown -*- lexical-binding: t; -*-
;;
;; Description: Speech-enable Markdown-Mode with heading announcements and reading mode
;; Keywords: Emacsvox, Audio Desktop, Markdown, documentation
;; Location https://github.com/robertmeta/emacsvox

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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; Speech-enables markdown-mode with smart heading and structure navigation.
;; Instead of hearing "three pounds space", users hear "heading level 3".
;;
;; Provides `emacsvox-markdown-reading-mode', a minor mode that strips
;; markup syntax when reading content, so you hear "car" instead of
;; "star star car star star" for **car**.
;;
;; Reading mode handles: images, links, task lists, code fences, tables,
;; footnotes, horizontal rules, HTML comments, and escaped characters.
;;
;; Keybindings (active in markdown-mode):
;; - C-c C-s h: Speak current heading with level
;; - C-c C-s r: Toggle reading mode

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-markdown)

;;;  Silence byte-compiler:

(defvar markdown-mode-map)
(declare-function markdown-heading-at-point "markdown-mode")
(declare-function markdown-outline-level "markdown-mode")

;;;  Customization:

(defcustom emacsvox-markdown-auto-reading-mode nil
  "When non-nil, automatically enable reading mode in markdown buffers."
  :type 'boolean
  :group 'emacsvox)

;;;  Map faces to voices:

(defconst emacsvox-markdown--face-voice-map
  '((markdown-blockquote-face voice-lighten)
   (markdown-bold-face voice-bolden)
   (markdown-code-face voice-monotone)
   (markdown-comment-face voice-monotone-extra)
   (markdown-footnote-marker-face voice-smoothen)
   (markdown-footnote-text-face voice-smoothen)
   (markdown-gfm-checkbox-face voice-annotate)
   (markdown-header-delimiter-face voice-lighten)
   (markdown-header-face voice-bolden)
   (markdown-header-face-1 voice-brighten)
   (markdown-header-face-2 voice-animate)
   (markdown-header-face-3 voice-lighten)
   (markdown-header-face-4 voice-smoothen)
   (markdown-header-face-5 voice-monotone)
   (markdown-header-face-6 voice-monotone-extra)
   (markdown-header-rule-face voice-bolden-medium)
   (markdown-highlight-face voice-animate)
   (markdown-highlighting-face voice-animate)
   (markdown-hr-face voice-bolden-medium)
   (markdown-html-attr-name-face voice-lighten)
   (markdown-html-attr-value-face voice-brighten)
   (markdown-html-entity-face voice-smoothen)
   (markdown-html-tag-delimiter-face voice-lighten)
   (markdown-html-tag-name-face voice-bolden)
   (markdown-inline-code-face voice-monotone-extra)
   (markdown-italic-face voice-animate)
   (markdown-language-info-face voice-smoothen)
   (markdown-language-keyword-face voice-smoothen)
   (markdown-line-break-face voice-monotone-extra)
   (markdown-link-face voice-bolden)
   (markdown-link-title-face voice-lighten)
   (markdown-list-face voice-animate)
   (markdown-markup-face voice-lighten)
   (markdown-math-face voice-animate)
   (markdown-metadata-key-face voice-smoothen)
   (markdown-metadata-value-face voice-smoothen-medium)
   (markdown-missing-link-face voice-animate)
   (markdown-plain-url-face voice-lighten)
   (markdown-pre-face voice-monotone-extra)
   (markdown-reference-face voice-lighten)
   (markdown-strike-through-face voice-smoothen)
   (markdown-table-face voice-monotone)
   (markdown-url-face voice-bolden-and-animate))
  "Voice personalities for faces defined by the current Markdown Mode.")

(voice-setup-add-map emacsvox-markdown--face-voice-map)

;;;  Heading helpers:

(defun emacsvox-markdown--heading-data ()
  "Return heading level and text at point, or nil outside a heading."
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at "^\\(#+\\)[ \t]+\\(.*?\\)[ \t]*#*[ \t]*$")
      (list
       :level (length (match-string 1))
       :text (string-trim (match-string-no-properties 2))))
     ((and
       (< (line-end-position) (point-max))
       (save-excursion
         (forward-line 1)
         (looking-at "^[ \t]*\\([=-]+\\)[ \t]*$")))
      (let ((text
             (string-trim
              (buffer-substring-no-properties
               (line-beginning-position) (line-end-position)))))
        (save-excursion
          (forward-line 1)
          (list
           :level (if (eq (char-after (match-beginning 1)) ?=) 1 2)
           :text text))))
     ((and (fboundp 'markdown-heading-at-point)
           (fboundp 'markdown-outline-level))
      (when-let* ((heading (markdown-heading-at-point)))
        (list
         :level (markdown-outline-level)
         :text (string-trim heading)))))))

(defun emacsvox-markdown--get-heading-info ()
  "Return heading information at point as \"heading level N: text\"."
  (when-let* ((heading (emacsvox-markdown--heading-data)))
    (format "heading level %d: %s"
            (plist-get heading :level)
            (plist-get heading :text))))

(defun emacsvox-markdown--merge-facts (facts additions)
  "Return a copy of FACTS with plist ADDITIONS applied."
  (let ((result (copy-tree facts)))
    (while additions
      (setq result (plist-put result (pop additions) (pop additions))))
    result))

(defun emacsvox-markdown--submit-text (text facts occasion)
  "Submit Markdown TEXT under FACTS and OCCASION."
  (emacsvox-aural-submit
   text :facts facts :module 'markdown :occasion occasion))

(defun emacsvox-markdown--submit-actions (facts occasion)
  "Submit action-only Markdown FACTS under OCCASION."
  (emacsvox-aural-submit-actions
   :facts facts :module 'markdown :occasion occasion))

(defun emacsvox-markdown--submit-message (text facts occasion)
  "Display and natively present Markdown TEXT under FACTS and OCCASION."
  (let ((emacsvox-speak-messages nil))
    (message "%s" text))
  (emacsvox-markdown--submit-text text facts occasion))

(defun emacsvox-markdown--remove-captured-source-icon
    (content icon source-offset source-length)
  "Return CONTENT without ICON captured at SOURCE-OFFSET.
SOURCE-LENGTH is the unprefixed selected line length.  Other text properties
and auditory icons are preserved."
  (if (null icon)
      content
    (let* ((result (copy-sequence content))
           (prefix-length (max 0 (- (length result) source-length)))
           (expected
            (min
             (max 0 (+ prefix-length source-offset))
             (max 0 (1- (length result)))))
           (position
            (and
             (<= 0 source-offset)
             (< source-offset source-length)
             (> (length result) 0)
             (eq
              (get-text-property expected 'auditory-icon result)
              icon)
             expected)))
      (when position
        (let ((start
               (or
                (previous-single-property-change
                 (1+ position) 'auditory-icon result)
                0))
              (end
               (or
                (next-single-property-change
                 position 'auditory-icon result)
                (length result))))
          (remove-text-properties start end '(auditory-icon nil) result)))
      result)))

(defun emacsvox-markdown--present-current-line
    (facts occasion &optional arg)
  "Present the current line as one Markdown transaction.
FACTS and OCCASION describe the object.  ARG has the same selection meaning
as the optional argument to `emacsvox-speak-line'."
  (let* ((normalized-arg (if (listp arg) (car arg) arg))
         (source-start
          (if (and normalized-arg (> normalized-arg 0))
              (point)
            (line-beginning-position)))
         (source-end
          (if (and normalized-arg (< normalized-arg 0))
              (point)
            (line-end-position)))
         (source-icon (get-char-property (point) 'auditory-icon))
         (source-offset (- (point) source-start))
         (source-length (- source-end source-start))
         (context (emacsvox-aural-capture-context 'markdown occasion))
         icons
         line-facts
         content)
    (let ((emacsvox-aural-submission-facts facts)
          (emacsvox-aural-submission-context context)
          (emacsvox-aural-submission-module 'markdown)
          (emacsvox-aural-submission-occasion occasion))
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (setq icons (append icons (list icon)))))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (setq
               line-facts
               (emacsvox-markdown--merge-facts
                line-facts
                (plist-get arguments :facts))))))
        (emacsvox-speak-line-with-speaker
         (lambda (text) (setq content text))
         arg)))
    (unless (or content line-facts)
      (when-let* ((condition
                   (emacsvox-speak--line-condition
                    (emacsvox-aural-source-substring
                     source-start source-end))))
        (setq line-facts (list :line-condition condition))))
    (setq facts (emacsvox-markdown--merge-facts facts line-facts))
    (if content
        (emacsvox-aural-submit
         (emacsvox-markdown--remove-captured-source-icon
          content source-icon source-offset source-length)
         :facts facts
         :context context
         :module 'markdown
         :occasion occasion
         :compatibility-actions
         (mapcar #'emacsvox-aural-compatibility-icon icons))
      (emacsvox-aural-submit-actions
       :facts facts
       :context context
       :module 'markdown
       :occasion occasion
       :compatibility-actions
       (mapcar #'emacsvox-aural-compatibility-icon icons)))))

(defun emacsvox-markdown-speak-heading ()
  "Speak the current heading with level information."
  (interactive)
  (let ((info (emacsvox-markdown--get-heading-info)))
    (if info
        (emacsvox-markdown--submit-text
         info (emacsvox-markdown-facts-at-point) 'inspection)
      (emacsvox-markdown--submit-message
       "Not at a heading"
       '(:role markdown-content :events (operation-failed))
       'inspection))))

;;;  Structure detection:

(defun emacsvox-markdown--at-list-item-p ()
  "Return non-nil if point is at a list item."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[ \t]*[-*+][ \t]+\\|^[ \t]*[0-9]+\\.[ \t]+")))

(defun emacsvox-markdown--at-task-list-p ()
  "Return `checked' or `unchecked' when point is at a task list item."
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at "^[ \t]*[-*+][ \t]+\\[\\([xX]\\)\\]") 'checked)
     ((looking-at "^[ \t]*[-*+][ \t]+\\[ \\]") 'unchecked))))

(defun emacsvox-markdown--at-horizontal-rule-p ()
  "Return non-nil if point is at a horizontal rule."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[ \t]*\\(---+\\|\\*\\*\\*+\\|___+\\)[ \t]*$")))

(defun emacsvox-markdown--at-code-fence-p ()
  "Return language name if at code fence start, nil otherwise."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^[ \t]*\\(```\\|~~~\\)\\([a-zA-Z0-9_+-]*\\)[ \t]*$")
      (let ((lang (match-string 2)))
        (if (string-empty-p lang) "code" lang)))))

(defun emacsvox-markdown--at-table-row-p ()
  "Return non-nil if point is at a table row."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[ \t]*|.*|[ \t]*$")))

(defun emacsvox-markdown--at-table-separator-p ()
  "Return non-nil if point is at a table separator line."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[ \t]*|[ \t]*[-:]+[ \t]*|")))

(defun emacsvox-markdown--at-reference-link-def-p ()
  "Return non-nil if point is at a reference link definition."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[ \t]*\\[.+\\]:[ \t]+\\S-")))

(defun emacsvox-markdown--at-footnote-def-p ()
  "Return footnote number if at footnote definition."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\[\\^\\([^]]+\\)\\]:[ \t]*")
      (match-string 1))))

(defun emacsvox-markdown--at-link-p ()
  "Return non-nil when the current line contains a Markdown link."
  (save-excursion
    (beginning-of-line)
    (re-search-forward
     "\\(?:!\\)?\\[[^]\n]+\\]\\(?:([^)\n]+)\\|\\[[^]\n]*\\]\\)"
     (line-end-position) t)))

(defun emacsvox-markdown--visibility ()
  "Return folded or expanded for the current heading."
  (when (emacsvox-markdown--heading-data)
    (if
        (and
         (fboundp 'outline-invisible-p)
         (< (line-end-position) (point-max))
         (outline-invisible-p (1+ (line-end-position))))
        'folded
      'expanded)))

(defun emacsvox-markdown-facts-at-point
    (&optional event navigation-kind)
  "Return registered Markdown facts at point.

EVENT describes the interaction.  NAVIGATION-KIND is `line' or `structural'
when the distinction is relevant to compatibility presentation."
  (let* ((heading (emacsvox-markdown--heading-data))
         (task (emacsvox-markdown--at-task-list-p))
         (fence (emacsvox-markdown--at-code-fence-p))
         (footnote (emacsvox-markdown--at-footnote-def-p))
         (list-kind
          (and
           (emacsvox-markdown--at-list-item-p)
           (save-excursion
             (beginning-of-line)
             (if (looking-at-p "^[ \t]*[0-9]+\\.[ \t]+")
                 'ordered
               'unordered))))
         (role
          (cond
           (heading 'heading)
           (task 'markdown-task)
           (fence 'markdown-code-block)
           (footnote 'markdown-footnote)
           ((emacsvox-markdown--at-horizontal-rule-p)
            'markdown-separator)
           ((emacsvox-markdown--at-table-separator-p)
            'markdown-separator)
           ((emacsvox-markdown--at-reference-link-def-p)
            'markdown-link)
           ((emacsvox-markdown--at-table-row-p) 'markdown-table-row)
           ((emacsvox-markdown--at-link-p) 'markdown-link)
           (list-kind 'markdown-list-item)
           (t 'markdown-content)))
         (visibility (and heading (emacsvox-markdown--visibility))))
    (append
     (list :role role)
     (when event (list :events (list event)))
     (when task (list :states (list task)))
     (when heading (list :level (plist-get heading :level)))
     (when visibility (list :visibility visibility))
     (when fence (list :markdown-language fence))
     (when list-kind (list :markdown-list-kind list-kind))
     (when task (list :markdown-task-state task))
     (when navigation-kind
       (list :markdown-navigation-kind navigation-kind)))))

;;;  Markup stripping for reading mode:

(defun emacsvox-markdown--strip-markup (text)
  "Remove markdown markup from TEXT for clean speech."
  (when text
    (let ((result text))
      (setq result (replace-regexp-in-string "^#+\\s-*" "" result))
      (setq result (replace-regexp-in-string "^[=-]+$" "" result))
      (setq result (replace-regexp-in-string "\\*\\*\\([^*]+\\)\\*\\*" "\\1" result))
      (setq result (replace-regexp-in-string "__\\([^_]+\\)__" "\\1" result))
      (setq result (replace-regexp-in-string "\\*\\([^*]+\\)\\*" "\\1" result))
      (setq result (replace-regexp-in-string "_\\([^_]+\\)_" "\\1" result))
      (setq result (replace-regexp-in-string "`\\([^`]+\\)`" "\\1" result))
      (setq result (replace-regexp-in-string "~~\\([^~]+\\)~~" "\\1" result))
      (setq result (replace-regexp-in-string "\\\\\\(.\\)" "\\1" result))
      (setq result (replace-regexp-in-string "!\\[\\([^]]+\\)\\](\\([^)]+\\))" "image: \\1" result))
      (setq result (replace-regexp-in-string "\\[\\([^]]+\\)\\](\\([^)]+\\))" "\\1 link" result))
      (setq result (replace-regexp-in-string "\\[\\([^]]+\\)\\]\\[[^]]*\\]" "\\1 link" result))
      (setq result (replace-regexp-in-string "<\\([^>]+\\)>" "\\1" result))
      (setq result (replace-regexp-in-string "\\[\\^\\([^]]+\\)\\]" "footnote \\1" result))
      (setq result (replace-regexp-in-string "^\\s-*[-*+]\\s-+\\[\\([xX]\\)\\]\\s-+" "checked: " result))
      (setq result (replace-regexp-in-string "^\\s-*[-*+]\\s-+\\[ \\]\\s-+" "unchecked: " result))
      (setq result (replace-regexp-in-string "^\\s-*[-*+]\\s-+" "" result))
      (setq result (replace-regexp-in-string "^\\s-*[0-9]+\\.\\s-+" "" result))
      (setq result (replace-regexp-in-string "^>+\\s-*" "" result))
      (setq result (replace-regexp-in-string "^    " "" result))
      (setq result (replace-regexp-in-string "^\\s-*|\\s-*" "" result))
      (setq result (replace-regexp-in-string "\\s-*|\\s-*$" "" result))
      (setq result (replace-regexp-in-string "\\s-*|\\s-*" " " result))
      result)))

;;;  Reading mode:

(defvar-local emacsvox-markdown-reading-mode nil
  "Non-nil when markdown reading mode is active.")

(defun emacsvox-markdown-reading-mode (&optional arg)
  "Toggle reading mode that strips markup syntax from speech.
ARG enables the mode when positive, disables it otherwise, and toggles it
when it is the symbol `toggle'.
When enabled, voice personalities still indicate emphasis, headings, etc.,
but you won't hear the literal markup characters."
  (interactive (list (or current-prefix-arg 'toggle)))
  (setq emacsvox-markdown-reading-mode
        (cond
         ((eq arg 'toggle) (not emacsvox-markdown-reading-mode))
         ((null arg) t)
         ((> (prefix-numeric-value arg) 0) t)
         (t nil)))
  (emacsvox-markdown--submit-message
   (if emacsvox-markdown-reading-mode
       "Markdown reading mode enabled"
     "Markdown reading mode disabled")
   (list
    :role 'markdown-content
    :events '(state-changed)
    :markdown-reading-mode-state
    (if emacsvox-markdown-reading-mode 'enabled 'disabled))
   'state-change))

(defun emacsvox-markdown--speak-line-clean ()
  "Present the current line with markup removed and structure announced."
  (let* ((text
          (emacsvox-aural-source-substring
           (line-beginning-position) (line-end-position)))
         (clean (emacsvox-markdown--strip-markup text))
         (heading (emacsvox-markdown--get-heading-info))
         (task (emacsvox-markdown--at-task-list-p))
         (fence (emacsvox-markdown--at-code-fence-p))
         (footnote (emacsvox-markdown--at-footnote-def-p))
         (table-separator (emacsvox-markdown--at-table-separator-p))
         (reference-definition
          (emacsvox-markdown--at-reference-link-def-p))
         (facts
          (emacsvox-markdown-facts-at-point 'focus-entered 'line))
         (content
          (cond
           ((emacsvox-markdown--at-horizontal-rule-p)
            "section separator")
           (table-separator nil)
           (reference-definition nil)
           (fence (format "code block: %s" fence))
           (footnote (format "footnote %s: %s" footnote clean))
           ((emacsvox-markdown--at-table-row-p) clean)
           (heading heading)
           (task clean)
           ((emacsvox-markdown--at-list-item-p)
            (concat "item " clean))
           (t (or clean "")))))
    (cond
     (table-separator
      (emacsvox-markdown--submit-actions
       (emacsvox-markdown--merge-facts
        facts '(:line-condition separator))
       'navigation))
     (reference-definition
      (emacsvox-markdown--submit-actions
       (emacsvox-markdown--merge-facts
        facts
        (list
         :events
         (delete-dups
          (append
           (copy-sequence (plist-get facts :events))
           '(markdown-link-navigated)))))
       'navigation))
     ((string-match-p "\\`[[:space:]]*\\'" content)
      (emacsvox-markdown--submit-actions
       (emacsvox-markdown--merge-facts
        facts '(:line-condition empty))
       'navigation))
     (t (emacsvox-markdown--submit-text content facts 'navigation)))))

(defun emacsvox-markdown--speak-table-row ()
  "Speak table row with column info."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^[ \t]*|\\(.*\\)|[ \t]*$")
      (let* ((cells (split-string (match-string 1) "|" t "[ \t]+"))
             (col 1)
             (parts nil))
        (dolist (cell cells)
          (push (format "column %d %s" col (string-trim cell)) parts)
          (cl-incf col))
        (mapconcat #'identity (nreverse parts) " ")))))

;;;  Advice for speak-line in markdown:

(defun emacsvox--advice-markdown-speak-line-around (original &rest arguments)
  "Present a Markdown line natively or call ORIGINAL with ARGUMENTS elsewhere.
When reading mode is active, strip markup from speech."
  (if (not (derived-mode-p 'markdown-mode))
      (apply original arguments)
    (cond
     (emacsvox-markdown-reading-mode
      (emacsvox-markdown--speak-line-clean))
     ((emacsvox-markdown--get-heading-info)
      (emacsvox-markdown--submit-text
       (emacsvox-markdown--get-heading-info)
       (emacsvox-markdown-facts-at-point 'focus-entered 'line)
       'navigation))
     (t
      (emacsvox-markdown--present-current-line
       (emacsvox-markdown-facts-at-point 'focus-entered 'line)
       'navigation
       (car arguments))))))

(defun emacsvox-markdown--present-heading-or-line (event)
  "Present the current heading or line under navigation EVENT."
  (if-let* ((info (emacsvox-markdown--get-heading-info)))
      (emacsvox-markdown--submit-text
       info
       (emacsvox-markdown-facts-at-point event 'structural)
       'navigation)
    (emacsvox-markdown--present-current-line
     (emacsvox-markdown-facts-at-point event 'structural)
     'navigation)))

(advice-add
 'emacsvox-speak-line :around
 #'emacsvox--advice-markdown-speak-line-around
 '((name . emacsvox-markdown)))

;;;  Advice navigation commands:

(defvar emacsvox-markdown--advice nil
  "Markdown Mode targets and their native advice functions.")

(cl-loop
 for target in
 '(markdown-next-heading markdown-previous-heading
   markdown-next-visible-heading markdown-previous-visible-heading
   markdown-outline-next markdown-outline-previous)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
 `(defun ,advice-function (&rest _)
     "Speak the heading we moved to."
     (when (ems-interactive-p ',target)
       (emacsvox-markdown--present-heading-or-line
        'markdown-heading-navigated))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

(cl-loop
 for target in
 '(markdown-next-link markdown-previous-link)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
 `(defun ,advice-function (&rest _)
     "Speak the link we moved to."
     (when (ems-interactive-p ',target)
       (emacsvox-markdown--present-current-line
        (emacsvox-markdown-facts-at-point
         'markdown-link-navigated 'structural)
        'navigation))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

;;;  Advice editing/movement commands:

(cl-loop
 for target in
 '(markdown-outdent-or-delete)
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
 `(defun ,advice-function (original &rest arguments)
     "Present a successful Markdown deletion or outdent."
     (if (not (ems-interactive-p ',target))
         (apply original arguments)
       (let* ((region (use-region-p))
              (character
               (and
                (not region)
                (> (point) (point-min))
                (preceding-char)))
              (modified-tick (buffer-chars-modified-tick))
              (result (apply original arguments)))
         (when (/= modified-tick (buffer-chars-modified-tick))
           (emacsvox-markdown--submit-text
            (cond
             (region "Deleted selection")
             ((memq character '(?\s ?\t)) "Outdented")
             (character (char-to-string character))
             (t "Deleted text"))
            (emacsvox-markdown--merge-facts
             (emacsvox-markdown-facts-at-point 'object-changed)
             '(:edit-operation deletion))
            'edit))
         result))))
 (push (list target :around advice-function) emacsvox-markdown--advice))

(defun emacsvox-markdown--command-presentation (command)
  "Return the event and occasion for Markdown COMMAND."
  (cond
   ((eq command 'markdown-edit-code-block)
    '(markdown-code-edit-opened . state-change))
   ((eq command 'markdown-cycle)
    (cond
     (current-prefix-arg '(visibility-changed . state-change))
     ((emacsvox-markdown--at-table-row-p)
      '(markdown-structure-navigated . navigation))
     ((emacsvox-markdown--heading-data)
      '(visibility-changed . state-change))
     (t '(object-changed . edit))))
   ((eq command 'markdown-shifttab)
    (if (emacsvox-markdown--at-table-row-p)
        '(markdown-structure-navigated . navigation)
      '(visibility-changed . state-change)))
   ((memq command '(markdown-indent-region markdown-blockquote-region))
    '(object-changed . edit))
   ((string-match-p
     "\\`markdown-\\(?:edit\\|enter\\|indent\\|insert\\|move\\|promote\\|demote\\)"
     (symbol-name command))
    '(object-changed . edit))
   (t '(markdown-structure-navigated . navigation))))

(cl-loop
 for target in
 '(markdown-back-to-heading
   markdown-backward-block markdown-backward-page
   markdown-beginning-of-list markdown-beginning-of-text-block
   markdown-edit-code-block markdown-end-of-list
   markdown-end-of-text-block markdown-forward-block markdown-forward-page
   markdown-insert-kbd markdown-insert-strike-through
   markdown-outline-next-same-level
   markdown-outline-previous-same-level markdown-outline-up
   markdown-reference-goto-link
   markdown-up-heading markdown-up-list
   markdown-demote-subtree markdown-demote markdown-demote-list-item
   markdown-promote-subtree markdown-move-subtree-up markdown-move-subtree-down
   markdown-backward-paragraph markdown-cycle
   markdown-enter-key markdown-beginning-of-defun
   markdown-insert-footnote markdown-insert-code
   markdown-insert-bold markdown-insert-blockquote
   markdown-forward-paragraph markdown-footnote-goto-text
   markdown-end-of-defun markdown-insert-gfm-code-block
   markdown-insert-header markdown-insert-header-atx-1
   markdown-insert-header-atx-2 markdown-insert-header-atx-3
   markdown-insert-header-atx-4 markdown-insert-header-atx-5
   markdown-insert-header-atx-6 markdown-insert-header-dwim
   markdown-insert-header-setext-1 markdown-insert-header-setext-2
   markdown-insert-header-setext-dwim
   markdown-insert-hr markdown-insert-image
   markdown-insert-italic markdown-insert-link
   markdown-insert-list-item markdown-insert-pre
   markdown-insert-reference-image
   markdown-insert-uri markdown-insert-wiki-link
   markdown-move-down markdown-move-list-item-down
   markdown-move-list-item-up markdown-move-up
   markdown-forward-same-level markdown-backward-same-level
   markdown-indent-line markdown-indent-region markdown-blockquote-region
   markdown-promote markdown-promote-list-item
   markdown-reference-goto-definition markdown-shifttab)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
 `(defun ,advice-function (&rest _)
     "Present the Markdown object affected by this command."
     (when (ems-interactive-p ',target)
       (pcase-let
         ((`(,event . ,occasion)
             (emacsvox-markdown--command-presentation ',target)))
         (emacsvox-markdown--present-current-line
          (emacsvox-markdown-facts-at-point event 'structural)
          occasion)))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

(defun emacsvox-markdown--operation-message (target)
  "Return the completion message for Markdown operation TARGET."
  (pcase target
    ('markdown-check-refs "Markdown reference check complete")
    ('markdown-preview "Markdown preview opened")
    ('markdown-export-and-preview "Markdown export and preview complete")
    (_ "Markdown export complete")))

(cl-loop
 for target in
 '(markdown-check-refs markdown-export markdown-export-and-preview
   markdown-preview)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
 `(defun ,advice-function (&rest _)
     "Present a completed Markdown operation."
     (when (ems-interactive-p ',target)
       (emacsvox-markdown--submit-message
        (emacsvox-markdown--operation-message ',target)
        (emacsvox-markdown-facts-at-point
         'markdown-operation-completed)
        'notification))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

(cl-loop
 for target in
 '(markdown-complete-region markdown-complete-buffer
   markdown-complete-at-point markdown-complete)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
 `(defun ,advice-function (&rest _)
     "Present completed Markdown content."
     (when (ems-interactive-p ',target)
       (emacsvox-markdown--present-current-line
        (emacsvox-markdown-facts-at-point
         'markdown-completion-completed)
        'edit))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

(defconst emacsvox-markdown--removed-targets
  '(markdown-beginning-of-block
    markdown-end-of-block
    markdown-end-of-block-element
    markdown-exdent-or-delete
    markdown-hide-body
    markdown-hide-sublevels
    markdown-hide-subtree
    markdown-insert-inline-link-dwim
    markdown-insert-reference-link-dwim
    markdown-jump)
  "Obsolete Markdown Mode commands no longer advised by Emacsvox.")

(defun emacsvox-markdown--install-advice ()
  "Install advice for commands present in the current Markdown Mode."
  (dolist (entry emacsvox-markdown--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

;;;  Setup:

(defun emacsvox-markdown-setup ()
  "Setup Emacsvox support for Markdown-Mode."
  (when (boundp 'markdown-mode-map)
    (define-key markdown-mode-map (kbd "C-c C-s h") #'emacsvox-markdown-speak-heading)
    (define-key markdown-mode-map (kbd "C-c C-s r") #'emacsvox-markdown-reading-mode)))

(defun emacsvox-markdown-mode-hook ()
  "Hook for markdown buffers."
  (setq-local emacsvox-aural-module 'markdown)
  (when emacsvox-markdown-auto-reading-mode
    (emacsvox-markdown-reading-mode 1)))

(eval-after-load "markdown-mode"
  (lambda ()
    (emacsvox-markdown--install-advice)
    (emacsvox-markdown-setup)
    (add-hook 'markdown-mode-hook #'emacsvox-markdown-mode-hook)))

(provide 'emacsvox-markdown)

;;; emacsvox-markdown.el ends here
