;;; emacsvox-calibredb.el --- CALIBREDB  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop calibredb
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
;; CALIBREDB == Browse And Search Local Calibre Library

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'calibredb nil 'no-error)
(require 'emacsvox-epub)
(declare-function calibredb-getattr "calibredb" t)
(declare-function calibredb-find-candidate-at-point "calibredb" t)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (calibredb-archive-face voice-smoothen)
   (calibredb-author-face voice-animate)
   (calibredb-comment-face voice-monotone)
   (calibredb-date-face voice-lighten)
   (calibredb-edit-annotation-header-title-face voice-brighten)
   (calibredb-favorite-face (voice-bolden))
   (calibredb-file-face voice-smoothen)
   (calibredb-format-face voice-monotone)
   (calibredb-highlight-face voice-animate)
   (calibredb-id-face voice-monotone)
   (calibredb-ids-face voice-monotone-extra)
   (calibredb-language-face voice-monotone-medium)
   (calibredb-mark-face voice-lighten-medium)
   (calibredb-pubdate-face voice-lighten)
   (calibredb-publisher-face voice-monotone-medium)
   (calibredb-search-header-highlight-face voice-bolden-medium)
   (calibredb-series-face voice-bolden-medium)
   (calibredb-size-face voice-monotone-medium)
   (calibredb-tag-face voice-annotate)
   (calibredb-title-detail-view-face voice-bolden-medium)
   (calibredb-title-face voice-bolden)))

;;;  Advice Interactive Commands:

'(
  calibredb-add
  calibredb-add-dir
  calibredb-add-format
  calibredb-annotation-quit
  calibredb-auto-detect-isbn
  calibredb-capture-at-point
  calibredb-catalog
  calibredb-catalog-bib--transient
  calibredb-catalog-bib-dispatch
  calibredb-clone
  calibredb-convert
  calibredb-convert-to-epub-dispatch
  calibredb-copy-as-org-link
  calibredb-edit-annotation
  calibredb-entry-dispatch
  calibredb-entry-quit
  calibredb-export
  calibredb-fetch-and-set-metadata-by-author-and-title
  calibredb-fetch-and-set-metadata-by-id
  calibredb-fetch-and-set-metadata-by-isbn
  calibredb-filter-by-author-sort
  calibredb-filter-by-book-format
  calibredb-filter-by-last_modified
  calibredb-filter-by-tag
  calibredb-filter-dispatch
  calibredb-find-bib
  calibredb-find-candidate-at-point
  calibredb-library-list
  calibredb-library-next
  calibredb-library-previous
  calibredb-mark-and-forward
  calibredb-mark-at-point
  calibredb-open-dired
  calibredb-org-link-copy
  calibredb-remove
  calibredb-remove-format
  calibredb-remove-marked-items
  calibredb-rga
  calibredb-search-clear-filter
  calibredb-search-live-filter
  calibredb-search-ret
  calibredb-search-toggle-view-refresh
  calibredb-search-update
  calibredb-send-edited-annotation
  calibredb-set-metadata--author_sort
  calibredb-set-metadata--authors
  calibredb-set-metadata--comments
  calibredb-set-metadata--comments-1
  calibredb-set-metadata--list-fields
  calibredb-set-metadata--tags
  calibredb-set-metadata--tags-1
  calibredb-set-metadata--title
  calibredb-set-metadata--transient
  calibredb-set-metadata-dispatch
  calibredb-show-metadata
  calibredb-show-mode
  calibredb-show-next-entry
  calibredb-show-previous-entry
  calibredb-show-refresh
  calibredb-sort-by-author
  calibredb-sort-by-date
  calibredb-sort-by-format
  calibredb-sort-by-id
  calibredb-sort-by-language
  calibredb-sort-by-pubdate
  calibredb-sort-by-size
  calibredb-sort-by-tag
  calibredb-sort-by-title
  calibredb-sort-dispatch
  calibredb-switch-library
  calibredb-tag-mouse-1
  calibredb-toggle-archive-at-point
  calibredb-toggle-favorite-at-point
  calibredb-toggle-highlight-at-point
  calibredb-toggle-order

  calibredb-unmark-and-backward
  calibredb-unmark-and-forward
  calibredb-unmark-at-point
  calibredb-virtual-library-list
  calibredb-virtual-library-next
  calibredb-virtual-library-previous
  calibredb-yank-dispatch
  )

(defun emacsvox--advice-calibredb-toggle-view-at-point-after (&rest _)
  "Speak after toggling the view at point."
  (when (ems-interactive-p 'calibredb-toggle-view-at-point)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-line)))

(defconst emacsvox-calibredb--view-targets
  '(calibredb-view
    calibredb-show-next-entry
    calibredb-show-previous-entry)
  "Calibredb commands that display an entry.")

(cl-loop
 for target in emacsvox-calibredb--view-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak the displayed Calibredb entry."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-predefined-window 1)))))

(defun emacsvox--advice-calibredb-search-refresh-and-clear-filter-after
    (&rest _)
  "Speak after refreshing Calibredb and clearing its filter."
  (when (ems-interactive-p 'calibredb-search-refresh-and-clear-filter)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-calibredb-search-quit-after (&rest _)
  "Speak after quitting a Calibredb search."
  (when (ems-interactive-p 'calibredb-search-quit)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-calibredb--movement-targets
  '(calibredb-previous-entry calibredb-next-entry)
  "Calibredb entry movement commands.")

(cl-loop
 for target in emacsvox-calibredb--movement-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak the selected Calibredb entry."
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(defun emacsvox--advice-calibredb-after (&rest _)
  "Speak after opening Calibredb."
  (when (ems-interactive-p 'calibredb)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-mode-line)))

(defconst emacsvox-calibredb--advice
  (append
   '((calibredb-toggle-view-at-point :after
      emacsvox--advice-calibredb-toggle-view-at-point-after)
     (calibredb-search-refresh-and-clear-filter :after
      emacsvox--advice-calibredb-search-refresh-and-clear-filter-after)
     (calibredb-search-quit :after
      emacsvox--advice-calibredb-search-quit-after)
     (calibredb :after emacsvox--advice-calibredb-after))
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    (append emacsvox-calibredb--view-targets
            emacsvox-calibredb--movement-targets)))
  "Current Calibredb targets and their native advice functions.")

(defun emacsvox-calibredb--install-advice ()
  "Install advice after the optional Calibredb package loads."
  (dolist (entry emacsvox-calibredb--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'calibredb
  (emacsvox-calibredb--install-advice))

;;; Emacsvox Commands:

(defun emacsvox-calibredb-epub-eww (&optional broken-ncx)
  "Open EPub at point in EWW.
Optional prefix arg uses alternative renderer that handles epubs
with broken NCX files."
  (interactive "P" )
  (funcall-interactively
   #'emacsvox-epub-eww
   (shell-quote-argument
    (calibredb-getattr (car (calibredb-find-candidate-at-point))
                       :file-path))
   broken-ncx))

;;; setup:

(defun emacsvox-calibredb-setup ()
  "Setup Emacsvox for Calibredb."
  
  (define-key calibredb-search-mode-map "E" 'emacsvox-calibredb-epub-eww))

(add-hook 'calibredb-search-mode-hook 'emacsvox-calibredb-setup)

(provide 'emacsvox-calibredb)

;;; emacsvox-calibredb.el ends here
