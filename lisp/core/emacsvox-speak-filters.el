;;; emacsvox-speak-filters.el --- Reading column filters -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Spoken Output
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

;; Own column selection, inversion and saved per-file or per-mode filters.
;; The core speech library loads these definitions at the original filter
;; setup point.  Saved settings are loaded and the exit hook is installed only
;; when requested by the existing filter commands.

;;; Code:

(require 'cl-lib)
(require 'tts-speak)

(defvar emacsvox-user-directory)
(declare-function emacsvox--persist-variable "emacsvox-speak" (var file))

;;;  filtering columns

(defvar-local emacsvox-speak-line-column-filter nil
  "List that specifies columns to be filtered.
The list when set holds pairs of start-col.end-col pairs
that specifies the columns that should not be spoken.
Each column contains a single character --this is inspired
by cut -c on UNIX.")

(defvar emacsvox-speak-filter-table (make-hash-table)
  "Hash table holding persistent filters.")

(defvar-local emacsvox-speak-line-invert-filter nil
  "Non-nil means the sense of `filter' is inverted when filtering
columns in a line --see
command emacsvox-speak-line-set-column-filter.")

(ems-generate-switcher 'emacsvox-toggle-speak-line-invert-filter
                       'emacsvox-speak-line-invert-filter
                       "Toggle state of   how column filter is interpreted.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defun emacsvox-speak-line-apply-column-filter (line &optional invert)
  "Apply column filter."

  (let ((filter emacsvox-speak-line-column-filter)
        (l (length line))
        (pair nil)
        (personality (if invert nil
                       'inaudible)))
    (with-silent-modifications
      (when invert
        (put-text-property 0 l
                           'personality 'inaudible line))
      (while filter
        (setq pair (pop filter))
        (when (and (<= (cl-first pair) l)
                   (<= (cl-second pair) l))
          (put-text-property
           (cl-first pair) (cl-second pair)
           'personality personality line))))
    line))

(defun emacsvox-speak-persist-filter-entry (k v)
  (insert
   (format
    "(puthash
(intern \"%s\")
'%s
emacsvox-speak-filter-table)\n" k v)))

(defvar emacsvox-speak-filter-persistent-store
  (expand-file-name ".filters" emacsvox-user-directory)
  "File where emacsvox filters are persisted.")

(defvar emacsvox-speak-filters-loaded-p nil
  "Records if we    have loaded filters in this session.")

(defun emacsvox-speak-lookup-persistent-filter (key)
  "Lookup a filter setting we may have persisted."

  (or
   (gethash
    (if (symbolp key) key (intern key))
    emacsvox-speak-filter-table)
   (list (list 0 (current-column)))))

(defun emacsvox-speak-set-persistent-filter (key value)
  "Persist filter setting for future use."

  (setf (gethash (intern key) emacsvox-speak-filter-table)
        value))

(defun emacsvox-speak-persist-filter-settings ()
  "Persist emacsvox filter settings for future sessions."
  (interactive)
  (emacsvox--persist-variable
   'emacsvox-speak-filter-table
   emacsvox-speak-filter-persistent-store))

(defun emacsvox-speak-load-filter-settings ()
  "Load emacsvox filter settings."
  (interactive)
  (unless emacsvox-speak-filters-loaded-p
    ;; `ems--fastload' is defined in `emacsvox-preamble' which requires
    ;; us, so we can't require it at top-level.
    (require 'emacsvox-preamble)
    (declare-function ems--fastload "emacsvox-preamble" (file))
    (ems--fastload emacsvox-speak-filter-persistent-store)
    (setq emacsvox-speak-filters-loaded-p t)
    (add-hook 'kill-emacs-hook 'emacsvox-speak-persist-filter-settings)))

(defun emacsvox-speak-line-set-column-filter (filter)
  "Set up filter for selectively speaking or ignoring portions of lines.
The filter is specified as a list of pairs.
For example, to filter  columns 1 -- 10 and 20 -- 25,
specify filter as
((0 9) (20 25)). Filter settings are persisted across sessions.  A
persisted filter is used as the default when prompting for a filter.
This allows one to accumulate a set of filters for specific files like
/var/adm/messages and /var/adm/maillog over time.
Option emacsvox-speak-line-invert-filter determines
the sense of the filter. "
  (interactive
   (list
    (progn
      (emacsvox-speak-load-filter-settings)
      (read-minibuffer
       (format
        "Specify columns to %s: "
        (if emacsvox-speak-line-invert-filter " speak" "filter out"))
       (format
        "%s"
        (emacsvox-speak-lookup-persistent-filter
         (or (buffer-file-name) (symbol-name major-mode))))))))
  (cond
   ((and (listp filter)
         (cl-every
          #'(lambda (l)
              (and (listp l)
                   (= 2 (length l))))
          filter))
    (setq emacsvox-speak-line-column-filter filter)
    (when (or (buffer-file-name) major-mode)
      (emacsvox-speak-set-persistent-filter
       (or (buffer-file-name) (symbol-name major-mode))
       filter)))
   (t
    (setq emacsvox-speak-line-column-filter nil))))

(provide 'emacsvox-speak-filters)

;;; emacsvox-speak-filters.el ends here
