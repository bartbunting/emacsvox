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

(voice-setup-add-map
 '((markdown-blockquote-face voice-lighten)
   (markdown-bold-face voice-bolden)
   (markdown-code-face voice-monotone)
   (markdown-comment-face voice-monotone-extra)
   (markdown-footnote-marker-face voice-smoothen)
   (markdown-footnote-text-face voice-smoothen)
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
   (markdown-html-attr-name-face voice-lighten)
   (markdown-html-attr-value-face voice-brighten)
   (markdown-html-entity-face voice-smoothen)
   (markdown-html-tag-name-face voice-bolden)
   (markdown-inline-code-face voice-monotone-extra)
   (markdown-italic-face voice-animate)
   (markdown-language-keyword-face voice-smoothen)
   (markdown-line-break-face voice-monotone-extra)
   (markdown-link-face voice-bolden)
   (markdown-link-title-face voice-lighten)
   (markdown-list-face voice-animate)
   (markdown-math-face voice-animate)
   (markdown-metadata-key-face voice-smoothen)
   (markdown-metadata-value-face voice-smoothen-medium)
   (markdown-missing-link-face voice-animate)
   (markdown-plain-url-face voice-lighten)
   (markdown-pre-face voice-monotone-extra)
   (markdown-reference-face voice-lighten)
   (markdown-strike-through-face voice-smoothen)
   (markdown-table-face voice-monotone)
   (markdown-url-face voice-bolden-and-animate)))

;;;  Heading helpers:

(defun emacsvox-markdown--get-heading-info ()
  "Return heading info at point as 'heading level N: text'."
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at "^\\(#+\\)[ \t]+\\(.*\\)$")
      (format "heading level %d: %s"
              (length (match-string 1))
              (string-trim (match-string 2))))
     ((and (fboundp 'markdown-heading-at-point)
           (fboundp 'markdown-outline-level))
      (let ((heading (markdown-heading-at-point)))
        (when heading
          (format "heading level %d: %s"
                  (markdown-outline-level)
                  (string-trim heading))))))))

(defun emacsvox-markdown-speak-heading ()
  "Speak the current heading with level information."
  (interactive)
  (let ((info (emacsvox-markdown--get-heading-info)))
    (if info (tts-speak info)
      (message "Not at a heading"))))

;;;  Structure detection:

(defun emacsvox-markdown--at-list-item-p ()
  "Return non-nil if point is at a list item."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "^[ \t]*[-*+][ \t]+\\|^[ \t]*[0-9]+\\.[ \t]+")))

(defun emacsvox-markdown--at-task-list-p ()
  "Return 'checked or 'unchecked if at a task list item."
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
When enabled, voice personalities still indicate emphasis, headings, etc.,
but you won't hear the literal markup characters."
  (interactive (list (or current-prefix-arg 'toggle)))
  (setq emacsvox-markdown-reading-mode
        (cond
         ((eq arg 'toggle) (not emacsvox-markdown-reading-mode))
         ((null arg) t)
         ((> (prefix-numeric-value arg) 0) t)
         (t nil)))
  (message (if emacsvox-markdown-reading-mode
               "Markdown reading mode enabled"
             "Markdown reading mode disabled")))

(defun emacsvox-markdown--speak-line-clean ()
  "Speak current line with markup removed and structure announced."
  (let* ((text (buffer-substring (line-beginning-position) (line-end-position)))
         (clean (emacsvox-markdown--strip-markup text))
         (heading (emacsvox-markdown--get-heading-info))
         (task (emacsvox-markdown--at-task-list-p))
         (fence (emacsvox-markdown--at-code-fence-p))
         (footnote (emacsvox-markdown--at-footnote-def-p)))
    (cond
     ((emacsvox-markdown--at-horizontal-rule-p)
      (emacsvox-icon 'item)
      (tts-speak "section separator"))
     ((emacsvox-markdown--at-table-separator-p) nil)
     ((emacsvox-markdown--at-reference-link-def-p) nil)
     (fence
      (emacsvox-icon 'open-object)
      (tts-speak (format "code block: %s" fence)))
     (footnote
      (tts-speak (format "footnote %s: %s" footnote clean)))
     ((emacsvox-markdown--at-table-row-p)
      (tts-speak clean))
     (heading
      (emacsvox-icon 'section)
      (tts-speak heading))
     (task
      (emacsvox-icon 'mark-object)
      (tts-speak clean))
     ((emacsvox-markdown--at-list-item-p)
      (tts-speak (concat "item " clean)))
     (t (tts-speak (or clean ""))))))

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
  "In markdown mode with reading mode, strip markup from speech."
  (if (and (eq major-mode 'markdown-mode)
           emacsvox-markdown-reading-mode)
      (emacsvox-markdown--speak-line-clean)
    (if (and (eq major-mode 'markdown-mode)
             (emacsvox-markdown--get-heading-info))
        (progn
          (emacsvox-icon 'section)
          (tts-speak (emacsvox-markdown--get-heading-info)))
      (apply original arguments))))

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
       (emacsvox-icon 'large-movement)
       (let ((info (emacsvox-markdown--get-heading-info)))
         (if info (tts-speak info) (emacsvox-speak-line))))))
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
       (emacsvox-icon 'button)
       (emacsvox-speak-line))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

;;;  Advice editing/movement commands:

(cl-loop
 for target in
 '(markdown-outdent-or-delete markdown-exdent-or-delete)
 for advice-function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest arguments)
     "Speak character you're deleting."
     (when (ems-interactive-p ',target)
       (tts-tone 500 100 'force)
       (emacsvox-speak-this-char (preceding-char)))
     (apply original arguments)))
 (push (list target :around advice-function) emacsvox-markdown--advice))

(cl-loop
 for target in
 '(markdown-back-to-heading
   markdown-backward-block markdown-backward-page
   markdown-beginning-of-list markdown-beginning-of-text-block
   markdown-edit-code-block markdown-end-of-list
   markdown-end-of-text-block markdown-forward-block markdown-forward-page
   markdown-insert-inline-link-dwim markdown-insert-kbd
   markdown-insert-strike-through
   markdown-outline-next-same-level
   markdown-outline-previous-same-level markdown-outline-up
   markdown-reference-goto-link
   markdown-up-heading markdown-up-list
   markdown-demote-subtree markdown-demote markdown-demote-list-item
   markdown-promote-subtree markdown-move-subtree-up markdown-move-subtree-down
   markdown-backward-paragraph markdown-cycle
   markdown-enter-key
   markdown-beginning-of-block markdown-beginning-of-defun
   markdown-end-of-block markdown-end-of-block-element
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
   markdown-insert-reference-image markdown-insert-reference-link-dwim
   markdown-insert-uri markdown-insert-wiki-link
   markdown-jump
   markdown-move-down markdown-move-list-item-down
   markdown-move-list-item-up markdown-move-up
   markdown-forward-same-level markdown-backward-same-level
   markdown-hide-subtree markdown-hide-body markdown-hide-sublevels
   markdown-indent-line
   markdown-promote markdown-promote-list-item
   markdown-reference-goto-definition)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

(cl-loop
 for target in
 '(markdown-check-refs markdown-export markdown-export-and-preview
   markdown-indent-region markdown-blockquote-region)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

(cl-loop
 for target in
 '(markdown-complete-region markdown-complete-buffer
   markdown-complete-at-point markdown-complete)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'complete)
       (emacsvox-speak-line))))
 (push (list target :after advice-function) emacsvox-markdown--advice))

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
  (when emacsvox-markdown-auto-reading-mode
    (emacsvox-markdown-reading-mode 1)))

(eval-after-load "markdown-mode"
  (lambda ()
    (emacsvox-markdown--install-advice)
    (emacsvox-markdown-setup)
    (add-hook 'markdown-mode-hook #'emacsvox-markdown-mode-hook)))

(provide 'emacsvox-markdown)

;;; emacsvox-markdown.el ends here
