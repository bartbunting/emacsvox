;;; emacsvox-notmuch-search.el --- Notmuch search-result presentation -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop notmuch
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

;; Notmuch search-result presentation.
;; Load through `emacsvox-notmuch'.  The facade owns activation.

;;; Code:

(require 'cl-lib)

;; Cross-module declarations.
(declare-function emacsvox-notmuch--annotate-field "emacsvox-notmuch" (text field))
(defvar emacsvox-notmuch--automatic-presentation-p)
(declare-function emacsvox-notmuch--bounded-text "emacsvox-notmuch" (text character-limit byte-limit label &optional total-characters))
(declare-function emacsvox-notmuch--leading-compatibility-actions "emacsvox-notmuch" (icon))
(declare-function emacsvox-notmuch--positive-limit "emacsvox-notmuch" (value))
(declare-function emacsvox-notmuch--prepare-field-text "emacsvox-notmuch" (value label &optional transform))
(declare-function emacsvox-notmuch--status-compatibility-actions "emacsvox-notmuch" (result status-icons occasion &optional include-attachments))
(declare-function emacsvox-notmuch--submit-content "emacsvox-notmuch" (text facts occasion compatibility-actions &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch--submit-text-feedback "emacsvox-notmuch" (facts occasion icon text &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch--truncation-hint "emacsvox-notmuch" nil)
(declare-function emacsvox-notmuch--truncation-notice "emacsvox-notmuch" (label omitted))
(declare-function emacsvox-notmuch--utf8-byte-length "emacsvox-notmuch" (text))
(defvar emacsvox-notmuch-automatic-field-byte-limit)
(defvar emacsvox-notmuch-automatic-field-character-limit)
(declare-function emacsvox-notmuch-message-facts "emacsvox-notmuch" (message &optional event))
(defvar emacsvox-notmuch-search-field-separator)
(defvar emacsvox-notmuch-search-result-fields)
(defvar emacsvox-notmuch-search-status-icons)
(declare-function notmuch-sanitize "notmuch-lib" (str))
(declare-function notmuch-search-get-result "notmuch" (&optional pos))
(declare-function notmuch-tag-format-tags "notmuch-tag"
                  (tags orig-tags &optional face))
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defun emacsvox-notmuch--field-string
    (value face &optional label transform)
  "Return bounded VALUE as a non-empty string using FACE.
LABEL names the field in a truncation notice.  Apply TRANSFORM only after the
untrusted input has been bounded."
  (when-let* ((text
               (emacsvox-notmuch--prepare-field-text
                value (or label "field") transform)))
    (propertize text 'face face)))

(defun emacsvox-notmuch--format-authors (authors)
  "Format AUTHORS with Notmuch's matching-author personalities."
  (when-let* ((authors
               (emacsvox-notmuch--prepare-field-text
                authors "authors" #'notmuch-sanitize)))
    (emacsvox-notmuch--bounded-text
     (save-match-data
       (if (string-match "\\(.*\\)|\\(.*\\)" authors)
           (let ((matching
                  (emacsvox-notmuch--field-string
                   (match-string 1 authors)
                   'notmuch-search-matching-authors
                   "authors"))
                 (non-matching
                  (emacsvox-notmuch--field-string
                   (match-string 2 authors)
                   'notmuch-search-non-matching-authors
                   "authors")))
             (string-join (delq nil (list matching non-matching)) ", "))
         (emacsvox-notmuch--field-string
          authors 'notmuch-search-matching-authors "authors")))
     emacsvox-notmuch-automatic-field-character-limit
     emacsvox-notmuch-automatic-field-byte-limit
     "authors")))

(defun emacsvox-notmuch--status-tags (status-icons)
  "Return tags represented by STATUS-ICONS."
  (mapcar #'car status-icons))

(defun emacsvox-notmuch--ordinary-tags (tags status-icons)
  "Return TAGS excluding statuses represented by STATUS-ICONS."
  (let ((status-tags (emacsvox-notmuch--status-tags status-icons)))
    (cl-remove-if
     (lambda (tag) (member tag status-tags))
     tags)))

(defun emacsvox-notmuch--bounded-ordinary-tags (tags status-icons)
  "Return bounded ordinary TAGS and truncation metadata.

The result is (VALUES OMITTED COMPLETE).  Status tags represented by
STATUS-ICONS are deliberately excluded rather than counted as omissions.
Automatic preparation keeps whole tag names so it cannot manufacture a
partial trusted-status word."
  (if (not emacsvox-notmuch--automatic-presentation-p)
      (list (emacsvox-notmuch--ordinary-tags tags status-icons) 0 t)
    (let* ((character-limit
            (emacsvox-notmuch--positive-limit
             emacsvox-notmuch-automatic-field-character-limit))
           (byte-limit
            (emacsvox-notmuch--positive-limit
             emacsvox-notmuch-automatic-field-byte-limit))
           ;; Reserve ample room for the trusted omission notice.
           (character-budget (and character-limit (/ character-limit 2)))
           (byte-budget (and byte-limit (/ byte-limit 2)))
           (node-limit
            (max 1 (or character-limit 256)))
           (status-tags (emacsvox-notmuch--status-tags status-icons))
           (seen (make-hash-table :test #'eq))
           (cursor tags)
           (nodes 0)
           (characters 0)
           (bytes 0)
           (omitted 0)
           (accepting t)
           values
           complete)
      (while
          (and
           (consp cursor)
           (< nodes node-limit)
           (not (gethash cursor seen)))
        (puthash cursor t seen)
        (cl-incf nodes)
        (let ((tag (car cursor)))
          (when (and (stringp tag) (not (member tag status-tags)))
            (let* ((separator (if (or values (> omitted 0)) 1 0))
                   (tag-characters (length tag))
                   (additional-characters (+ separator tag-characters))
                   (fits-characters
                    (or
                     (null character-budget)
                     (<=
                      (+ characters additional-characters)
                      character-budget)))
                   (fits-bytes
                    (and
                     accepting
                     (or
                      (null byte-budget)
                      (and
                       (<= (+ bytes separator tag-characters) byte-budget)
                       (<=
                        (+
                         bytes separator
                         (emacsvox-notmuch--utf8-byte-length tag))
                        byte-budget))))))
              (if (and accepting fits-characters fits-bytes)
                  (progn
                    (push tag values)
                    (cl-incf characters additional-characters)
                    (cl-incf
                     bytes
                     (+
                      separator
                      (emacsvox-notmuch--utf8-byte-length tag))))
                (setq accepting nil)
                (cl-incf omitted additional-characters)))))
        (setq cursor (cdr cursor)))
      (setq complete (null cursor))
      (list (nreverse values) omitted complete))))

(defun emacsvox-notmuch--format-tags (result status-icons)
  "Format ordinary tags from Notmuch RESULT using STATUS-ICONS."
  (pcase-let*
      ((`(,tags ,omitted ,complete)
        (emacsvox-notmuch--bounded-ordinary-tags
         (plist-get result :tags) status-icons))
       (`(,orig-tags ,orig-omitted ,orig-complete)
        (emacsvox-notmuch--bounded-ordinary-tags
         (plist-get result :orig-tags) status-icons))
       (formatted
        (unless (and (null tags) (null orig-tags))
          (notmuch-tag-format-tags tags orig-tags)))
       (notice
        (cond
         ((or (not complete) (not orig-complete))
          (format
           " … [tags shortened: additional tags omitted; %s]"
           (emacsvox-notmuch--truncation-hint)))
         ((> (+ omitted orig-omitted) 0)
          (emacsvox-notmuch--truncation-notice
           "tags" (+ omitted orig-omitted)))))
       (text
        (cond
         ((and formatted notice) (concat formatted notice))
         (formatted formatted)
         (notice (string-trim-left notice)))))
    (and
     text
     (emacsvox-notmuch--bounded-text
      text
      emacsvox-notmuch-automatic-field-character-limit
      emacsvox-notmuch-automatic-field-byte-limit
      "tags"))))

(defun emacsvox-notmuch--format-search-field (field result)
  "Format FIELD from Notmuch search RESULT for speech."
  (emacsvox-notmuch--annotate-field
   (pcase field
     ('authors
      (emacsvox-notmuch--format-authors
       (or (plist-get result :authors) "")))
     ('subject
      (emacsvox-notmuch--field-string
       (or (plist-get result :subject) "[No subject]")
       'notmuch-search-subject "subject" #'notmuch-sanitize))
     ('date
      (emacsvox-notmuch--field-string
       (plist-get result :date_relative)
       'notmuch-search-date "date"))
     ('count
      (emacsvox-notmuch--field-string
       (format "%s of %s"
               (plist-get result :matched)
               (plist-get result :total))
       'notmuch-search-count "count"))
     ('tags
      (emacsvox-notmuch--format-tags
       result emacsvox-notmuch-search-status-icons))
     ((pred functionp)
      (emacsvox-notmuch--prepare-field-text
       (funcall field result) "custom field"))
     (_ nil))
   (if (symbolp field) field 'custom)))

(defun emacsvox-notmuch-format-search-result (result)
  "Return a voice-propertized summary of Notmuch search RESULT."
  (string-join
   (delq
    nil
    (mapcar
     (lambda (field)
       (emacsvox-notmuch--format-search-field field result))
     emacsvox-notmuch-search-result-fields))
   emacsvox-notmuch-search-field-separator))

(defun emacsvox-notmuch--submit-search-result
    (result facts occasion &optional icon)
  "Submit Notmuch search RESULT with FACTS, OCCASION, and leading ICON."
  (if result
      (let ((summary (emacsvox-notmuch-format-search-result result)))
        (emacsvox-notmuch--submit-content
         summary facts occasion
         (append
          (emacsvox-notmuch--leading-compatibility-actions icon)
          (emacsvox-notmuch--status-compatibility-actions
           result emacsvox-notmuch-search-status-icons occasion)))
        summary)
    (emacsvox-notmuch--submit-text-feedback
     facts occasion icon nil)))

(defun emacsvox-notmuch-speak-search-result (&optional result)
  "Speak Notmuch search RESULT, defaulting to the result at point."
  (interactive)
  (when-let* ((result (or result (notmuch-search-get-result))))
    (emacsvox-notmuch--submit-search-result
     result
     (emacsvox-notmuch-message-facts result 'focus-entered)
     'navigation)))

(defun emacsvox-notmuch-speak-search-details (&optional result)
  "Speak complete configured details for search RESULT at point.

Unlike automatic navigation feedback, this explicit inspection is not
truncated by Notmuch's automatic presentation limits."
  (interactive)
  (when (and (called-interactively-p 'interactive)
             (not (eq major-mode 'notmuch-search-mode)))
    (user-error "This command is only available in Notmuch Search"))
  (when-let* ((result (or result (notmuch-search-get-result))))
    (let ((emacsvox-notmuch--automatic-presentation-p nil))
      (emacsvox-notmuch--submit-search-result
       result
       (emacsvox-notmuch-message-facts result)
       'inspection))))

(provide 'emacsvox-notmuch-search)
;;; emacsvox-notmuch-search.el ends here
