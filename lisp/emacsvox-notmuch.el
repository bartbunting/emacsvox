;;; emacsvox-notmuch.el --- Speech-enable NOTMUCH  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Description:  Speech-enable NOTMUCH An Emacs Interface to notmuch
;;; Keywords: Emacsvox,  Audio Desktop notmuch
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

;;;   Copyright:
;;;Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;;; All Rights Reserved.
;;;
;;; This file is not part of GNU Emacs, but the same permissions apply.
;;;
;;; GNU Emacs is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 2, or (at your option)
;;; any later version.
;;;
;;; GNU Emacs is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNNOTMUCH FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Emacs; see the file COPYING.  If not, write to
;;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;; NOTMUCH ==  Emacs interface to notmuch mail

;;; Code:

;;   Required modules:

(require 'cl-lib)
(require 'button)
(require 'emacsvox-preamble)
(require 'subr-x)
(require 'wid-edit)

(declare-function notmuch-sanitize "notmuch-lib" (str))
(declare-function notmuch-search-get-result "notmuch" (&optional pos))
(declare-function notmuch-show-clean-address "notmuch-show" (address))
(declare-function notmuch-show-get-message-id "notmuch-show" (&optional bare))
(declare-function notmuch-show-get-message-properties "notmuch-show" ())
(declare-function notmuch-show-get-part-properties "notmuch-show" ())
(declare-function notmuch-show-mapc "notmuch-show" (function))
(declare-function notmuch-show-message-extent "notmuch-show" ())
(declare-function notmuch-show-move-to-message-top "notmuch-show" ())
(declare-function notmuch-tag-format-tags "notmuch-tag"
                  (tags orig-tags &optional face))

(defvar notmuch-archive-tags)
(defvar notmuch-show-mode-map)
(defvar notmuch-show-part-button-default-action)

;;;  Customization:

(defgroup emacsvox-notmuch nil
  "Speech feedback for the Notmuch mail interface."
  :group 'emacsvox)

(defcustom emacsvox-notmuch-search-result-fields
  '(authors subject date count tags)
  "Ordered fields spoken for the current Notmuch search result.

The built-in fields are `authors', `subject', `date', `count',
and `tags'.  A function may also be used as a field; it receives
the Notmuch result plist and should return the string to speak.
Remove a field to silence it, or reorder the list to change when
it is spoken."
  :type '(repeat
          (choice
           (const :tag "Authors" authors)
           (const :tag "Subject" subject)
           (const :tag "Date" date)
           (const :tag "Matched and total count" count)
           (const :tag "Tags" tags)
           (function :tag "Custom formatter")))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-search-field-separator ", "
  "String placed between spoken Notmuch search-result fields."
  :type 'string
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-search-status-icons
  '(("unread" . new-mail)
    ("flagged" . mark-object))
  "Map Notmuch status tags to auditory icons.

Entries are checked in order and every matching non-nil icon is
played.  Tags present in this alist are omitted from the spoken
`tags' field.  Remove an entry to speak that status as an ordinary
tag, or give it a nil icon to keep the status silent."
  :type '(alist
          :key-type (string :tag "Status tag")
          :value-type
          (choice
           (const :tag "No sound" nil)
           (symbol :tag "Auditory icon")))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-show-message-fields
  '(from date to cc tags attachments)
  "Ordered fields spoken for the current Notmuch message.

The built-in fields are `from', `subject', `date', `to', `cc',
`tags', and `attachments'.  A function may also be used as a
field; it receives the Notmuch message plist and should return the
string to speak.  Remove a field to silence it, or reorder the
list to change when it is spoken."
  :type '(repeat
          (choice
           (const :tag "Sender" from)
           (const :tag "Subject" subject)
           (const :tag "Date" date)
           (const :tag "To recipients" to)
           (const :tag "Cc recipients" cc)
           (const :tag "Tags" tags)
           (const :tag "Attachment count" attachments)
           (function :tag "Custom formatter")))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-show-field-separator ", "
  "String placed between spoken fields for a Notmuch message."
  :type 'string
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-show-status-icons
  '(("unread" . new-mail)
    ("flagged" . mark-object))
  "Map Notmuch message status tags to auditory icons.

Entries are checked in order and every matching non-nil icon is
played.  Tags present in this alist are omitted from the spoken
`tags' field.  Remove an entry to speak that status as an ordinary
tag, or give it a nil icon to keep the status silent."
  :type '(alist
          :key-type (string :tag "Status tag")
          :value-type
          (choice
           (const :tag "No sound" nil)
           (symbol :tag "Auditory icon")))
  :group 'emacsvox-notmuch)

;;;  Message Faces:

(defface emacsvox-notmuch-message-from
  '((t :inherit message-header-other))
  "Face used to voice the sender of a Notmuch message."
  :group 'emacsvox-notmuch)

(defface emacsvox-notmuch-message-subject
  '((t :inherit message-header-subject))
  "Face used to voice the subject of a Notmuch message."
  :group 'emacsvox-notmuch)

(defface emacsvox-notmuch-message-date
  '((t :inherit message-header-other))
  "Face used to voice the date of a Notmuch message."
  :group 'emacsvox-notmuch)

(defface emacsvox-notmuch-message-to
  '((t :inherit message-header-to))
  "Face used to voice the To recipients of a Notmuch message."
  :group 'emacsvox-notmuch)

(defface emacsvox-notmuch-message-cc
  '((t :inherit message-header-cc))
  "Face used to voice the Cc recipients of a Notmuch message."
  :group 'emacsvox-notmuch)

(defface emacsvox-notmuch-message-attachments
  '((t :inherit message-mml))
  "Face used to voice the attachment count of a Notmuch message."
  :group 'emacsvox-notmuch)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (emacsvox-notmuch-message-attachments voice-annotate)
   (emacsvox-notmuch-message-cc voice-smoothen)
   (emacsvox-notmuch-message-date voice-monotone)
   (emacsvox-notmuch-message-from voice-lighten)
   (emacsvox-notmuch-message-subject voice-bolden)
   (emacsvox-notmuch-message-to voice-brighten)
   (notmuch-crypto-decryption voice-smoothen)
   (notmuch-crypto-part-header voice-smoothen-extra)
   (notmuch-crypto-signature-bad voice-smoothen-medium)
   (notmuch-crypto-signature-good voice-animate)
   (notmuch-crypto-signature-good-key voice-animate-extra)
   (notmuch-crypto-signature-unknown voice-animate-medium)
   (notmuch-jump-key voice-lighten)
   (notmuch-message-summary-face voice-annotate)
   (notmuch-search-count voice-bolden)
   (notmuch-search-date voice-bolden )
   (notmuch-search-flagged-face voice-lighten)
   (notmuch-search-matching-authors voice-lighten)
   (notmuch-search-non-matching-authors voice-monotone)
   (notmuch-search-subject voice-bolden)
   (notmuch-search-unread-face voice-animate)
   (notmuch-tag-face voice-bolden)
   (notmuch-wash-cited-text voice-smoothen)))

;;;  Search Results:

(defun emacsvox-notmuch--field-string (value face)
  "Return VALUE as a non-empty string using FACE."
  (when value
    (let ((text (string-trim (format "%s" value))))
      (unless (string-empty-p text)
        (propertize text 'face face)))))

(defun emacsvox-notmuch--format-authors (authors)
  "Format AUTHORS with Notmuch's matching-author personalities."
  (when authors
    (save-match-data
      (if (string-match "\\(.*\\)|\\(.*\\)" authors)
          (let ((matching
                 (emacsvox-notmuch--field-string
                  (match-string 1 authors)
                  'notmuch-search-matching-authors))
                (non-matching
                 (emacsvox-notmuch--field-string
                  (match-string 2 authors)
                  'notmuch-search-non-matching-authors)))
            (string-join (delq nil (list matching non-matching)) ", "))
        (emacsvox-notmuch--field-string
         authors 'notmuch-search-matching-authors)))))

(defun emacsvox-notmuch--status-tags (status-icons)
  "Return tags represented by STATUS-ICONS."
  (mapcar #'car status-icons))

(defun emacsvox-notmuch--ordinary-tags (tags status-icons)
  "Return TAGS excluding statuses represented by STATUS-ICONS."
  (let ((status-tags (emacsvox-notmuch--status-tags status-icons)))
    (cl-remove-if
     (lambda (tag) (member tag status-tags))
     tags)))

(defun emacsvox-notmuch--format-tags (result status-icons)
  "Format ordinary tags from Notmuch RESULT using STATUS-ICONS."
  (let ((tags
         (emacsvox-notmuch--ordinary-tags
          (plist-get result :tags)
          status-icons))
        (orig-tags
         (emacsvox-notmuch--ordinary-tags
          (plist-get result :orig-tags)
          status-icons)))
    (unless (and (null tags) (null orig-tags))
      (notmuch-tag-format-tags tags orig-tags))))

(defun emacsvox-notmuch--format-search-field (field result)
  "Format FIELD from Notmuch search RESULT for speech."
  (pcase field
    ('authors
     (emacsvox-notmuch--format-authors
      (notmuch-sanitize (or (plist-get result :authors) ""))))
    ('subject
     (emacsvox-notmuch--field-string
      (notmuch-sanitize (or (plist-get result :subject) "[No subject]"))
      'notmuch-search-subject))
    ('date
     (emacsvox-notmuch--field-string
      (plist-get result :date_relative)
      'notmuch-search-date))
    ('count
     (emacsvox-notmuch--field-string
      (format "%s of %s"
              (plist-get result :matched)
              (plist-get result :total))
      'notmuch-search-count))
    ('tags
     (emacsvox-notmuch--format-tags
      result emacsvox-notmuch-search-status-icons))
    ((pred functionp) (funcall field result))
    (_ nil)))

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

(defun emacsvox-notmuch--play-status-icons (result status-icons)
  "Play STATUS-ICONS for statuses present in Notmuch RESULT."
  (let ((tags (plist-get result :tags)))
    (dolist (entry status-icons)
      (when (and (cdr entry) (member (car entry) tags))
        (emacsvox-icon (cdr entry))))))

(defun emacsvox-notmuch-speak-search-result (&optional result)
  "Speak Notmuch search RESULT, defaulting to the result at point."
  (interactive)
  (when-let* ((result (or result (notmuch-search-get-result)))
              (summary (emacsvox-notmuch-format-search-result result)))
    (emacsvox-notmuch--play-status-icons
     result emacsvox-notmuch-search-status-icons)
    (tts-speak summary)
    summary))

;;;  Show Messages:

(defun emacsvox-notmuch--attachment-count (body)
  "Return the number of named MIME attachments below BODY."
  (cl-labels
      ((count-node
        (node)
        (cond
         ((and (listp node) (keywordp (car node)))
          (+
           (if (and
                (plist-get node :content-type)
                (plist-get node :filename))
               1
             0)
           (count-node (plist-get node :content))
           (count-node (plist-get node :body))))
         ((listp node)
          (cl-loop for child in node sum (count-node child)))
         (t 0))))
    (count-node body)))

(defun emacsvox-notmuch--format-show-header (message header face)
  "Format HEADER from MESSAGE using FACE."
  (emacsvox-notmuch--field-string
   (notmuch-sanitize
    (or (plist-get (plist-get message :headers) header) ""))
   face))

(defun emacsvox-notmuch--format-show-field (field message)
  "Format FIELD from Notmuch MESSAGE for speech."
  (pcase field
    ('from
     (let ((from
            (plist-get (plist-get message :headers) :From)))
       (emacsvox-notmuch--field-string
        (notmuch-sanitize
         (if from (notmuch-show-clean-address from) ""))
        'emacsvox-notmuch-message-from)))
    ('subject
     (emacsvox-notmuch--format-show-header
      message :Subject 'emacsvox-notmuch-message-subject))
    ('date
     (emacsvox-notmuch--field-string
      (or
       (plist-get message :date_relative)
       (plist-get (plist-get message :headers) :Date))
      'emacsvox-notmuch-message-date))
    ('to
     (emacsvox-notmuch--format-show-header
      message :To 'emacsvox-notmuch-message-to))
    ('cc
     (emacsvox-notmuch--format-show-header
      message :Cc 'emacsvox-notmuch-message-cc))
    ('tags
     (emacsvox-notmuch--format-tags
      message emacsvox-notmuch-show-status-icons))
    ('attachments
     (let ((count
            (emacsvox-notmuch--attachment-count
             (plist-get message :body))))
       (when (> count 0)
         (emacsvox-notmuch--field-string
          (format "%d %s"
                  count
                  (if (= count 1) "attachment" "attachments"))
          'emacsvox-notmuch-message-attachments))))
    ((pred functionp) (funcall field message))
    (_ nil)))

(defun emacsvox-notmuch-format-show-message (message)
  "Return a voice-propertized summary of Notmuch MESSAGE."
  (string-join
   (delq
    nil
    (mapcar
     (lambda (field)
       (emacsvox-notmuch--format-show-field field message))
     emacsvox-notmuch-show-message-fields))
   emacsvox-notmuch-show-field-separator))

(defun emacsvox-notmuch-speak-show-message (&optional message)
  "Speak Notmuch MESSAGE, defaulting to the message at point."
  (interactive)
  (when-let* ((message
               (or
                message
                (and
                 (eq major-mode 'notmuch-show-mode)
                 (notmuch-show-get-message-properties))))
              (summary (emacsvox-notmuch-format-show-message message)))
    (emacsvox-notmuch--play-status-icons
     message emacsvox-notmuch-show-status-icons)
    (tts-speak summary)
    summary))

(defun emacsvox-notmuch--show-message-position ()
  "Return the current message position and thread size as a cons cell."
  (when (eq major-mode 'notmuch-show-mode)
    (let ((current-id (notmuch-show-get-message-id))
          (position 0)
          (total 0))
      (notmuch-show-mapc
       (lambda ()
         (cl-incf total)
         (when (equal current-id (notmuch-show-get-message-id))
           (setq position total))))
      (when (> position 0)
        (cons position total)))))

(defun emacsvox-notmuch-speak-show-position ()
  "Speak the current position in the thread and semantic message details."
  (interactive)
  (unless (eq major-mode 'notmuch-show-mode)
    (user-error "This command is only available in Notmuch Show"))
  (when-let* ((message (notmuch-show-get-message-properties))
              (position (emacsvox-notmuch--show-message-position)))
    (let* ((details (emacsvox-notmuch-format-show-message message))
           (position-summary
            (format "Message %d of %d" (car position) (cdr position)))
           (summary
            (if (string-empty-p details)
                position-summary
              (concat position-summary ", " details))))
      (emacsvox-notmuch--play-status-icons
       message emacsvox-notmuch-show-status-icons)
      (tts-speak summary)
      summary)))

(defun emacsvox-notmuch--current-show-message-id ()
  "Return the current Notmuch show message ID, if available."
  (when (eq major-mode 'notmuch-show-mode)
    (ignore-errors
      (plist-get (notmuch-show-get-message-properties) :id))))

(defun emacsvox-notmuch--move-to-message-body ()
  "Move point to the first visible leaf content in the current message."
  (when (eq major-mode 'notmuch-show-mode)
    (when-let* ((message (notmuch-show-get-message-properties))
                (headers-overlay (plist-get message :headers-overlay)))
      (let ((limit (1- (cdr (notmuch-show-message-extent))))
            first-part-button
            first-leaf-button
            found)
        (goto-char (overlay-end headers-overlay))
        (forward-line 1)
        (while (and (< (point) limit) (not found))
          (skip-chars-forward " \t\n" limit)
          (cond
           ((>= (point) limit))
           ((invisible-p (point))
            (goto-char
             (min
              limit
              (next-overlay-change (point))
              (or
               (next-single-property-change
                (point) 'invisible nil limit)
               limit))))
           ((let ((button (button-at (point))))
              (when
                  (and
                   button
                   (eq
                    (button-type button)
                    'notmuch-show-part-button-type))
                (let ((part
                       (emacsvox-notmuch--part-at-point button)))
                  (unless first-part-button
                    (setq first-part-button (button-start button)))
                  (unless
                      (or
                       first-leaf-button
                       (string-prefix-p
                        "multipart/"
                        (or (plist-get part :content-type) "")))
                    (setq first-leaf-button (button-start button))))
                (goto-char (button-end button))
                t)))
           (t (setq found t))))
        (unless found
          (when-let* ((fallback
                       (or first-leaf-button first-part-button)))
            (goto-char fallback)))
        (point)))))

(defun emacsvox-notmuch--part-at-point (&optional button)
  "Return the Notmuch MIME part at point or on BUTTON."
  (ignore-errors
    (get-text-property
     (if button (button-start button) (point))
     :notmuch-part)))

(defun emacsvox-notmuch--part-content-length (part)
  "Return PART's content length as an integer, when available."
  (let ((length (plist-get part :content-length)))
    (cond
     ((numberp length) length)
     ((and (stringp length)
           (string-match-p "\\`[0-9]+\\'" length))
      (string-to-number length)))))

(defun emacsvox-notmuch-format-part (part)
  "Return a concise description of Notmuch MIME PART."
  (let* ((filename (plist-get part :filename))
         (content-type
          (or
           (plist-get part :computed-type)
           (plist-get part :content-type)))
         (length (emacsvox-notmuch--part-content-length part))
         (description
          (string-join
           (delq
            nil
            (list
             (if filename
                 (format "Attachment %s" filename)
               "MIME part")
             content-type
             (when length
               (file-size-human-readable length 'iec " "))))
           ", ")))
    (propertize description
                'face 'emacsvox-notmuch-message-attachments)))

(defun emacsvox-notmuch--part-action-object (part)
  "Return a concise action-oriented name for Notmuch MIME PART."
  (if-let* ((filename (plist-get part :filename)))
      (format "attachment %s" filename)
    (if-let* ((content-type
               (or
                (plist-get part :computed-type)
                (plist-get part :content-type))))
        (format "%s part" content-type)
      "MIME part")))

(defun emacsvox-notmuch--speak-show-button ()
  "Cue and identify the current button in a Notmuch Show buffer."
  (when-let* ((button (button-at (point))))
    (if-let* ((part (emacsvox-notmuch--part-at-point button)))
        (progn
          (emacsvox-icon
           (if (plist-get part :filename) 'item 'button))
          (tts-speak (emacsvox-notmuch-format-part part)))
      (emacsvox-icon 'large-movement)
      (tts-speak (button-label button)))))

(defun emacsvox-notmuch--part-action-feedback (action part)
  "Confirm ACTION on Notmuch MIME PART."
  (let ((save-p (eq action 'save)))
    (emacsvox-icon (if save-p 'save-object 'open-object))
    (tts-speak
     (format "%s %s"
             (if save-p "Saved" "Opened")
             (emacsvox-notmuch--part-action-object part)))))

;;;  Interactive Commands:

'(
  notmuch-cycle-notmuch-buffers
  notmuch-jump-search
  notmuch-message-mode
  notmuch-poll
  notmuch-poll-and-refresh-this-buffer
  notmuch-refresh-all-buffers
  notmuch-refresh-this-buffer
  notmuch-search
  notmuch-search-add-tag
  notmuch-search-archive-thread
  notmuch-search-by-tag
  notmuch-search-filter
  notmuch-search-filter-by-tag
  notmuch-search-first-thread
  notmuch-search-from-tree-current-query
  notmuch-search-last-thread
  notmuch-search-mode
  notmuch-search-mode-transient
  notmuch-search-next-thread
  notmuch-search-previous-thread
  notmuch-search-refresh-view
  notmuch-search-remove-tag
  notmuch-search-reply-to-thread
  notmuch-search-reply-to-thread-sender
  notmuch-search-scroll-down
  notmuch-search-scroll-up
  notmuch-search-show-thread
  notmuch-search-stash-thread-id
  notmuch-search-stash-transient
  notmuch-search-tag
  notmuch-search-tag-all
  notmuch-search-toggle-order
  notmuch-search-transient
  notmuch-show
  notmuch-show-add-tag
  notmuch-show-advance
  notmuch-show-advance-and-archive
  notmuch-show-archive-message
  notmuch-show-archive-message-then-next-or-exit
  notmuch-show-archive-message-then-next-or-next-thread
  notmuch-show-archive-thread
  notmuch-show-archive-thread-then-exit
  notmuch-show-archive-thread-then-next
  notmuch-show-browse-urls
  notmuch-show-choose-mime-of-part
  notmuch-show-filter-thread
  notmuch-show-forward-message
  notmuch-show-forward-open-messages
  notmuch-show-interactively-view-part
  notmuch-show-mark-read
  notmuch-show-mode
  notmuch-show-mode-transient
  notmuch-show-next-button
  notmuch-show-next-matching-message
  notmuch-show-next-message
  notmuch-show-next-open-message
  notmuch-show-next-thread
  notmuch-show-next-thread-show
  notmuch-show-open-or-close-all
  notmuch-show-part-button-default
  notmuch-show-part-transient
  notmuch-show-pipe-message
  notmuch-show-pipe-part
  notmuch-show-previous-button
  notmuch-show-previous-message
  notmuch-show-previous-open-message
  notmuch-show-previous-thread-show
  notmuch-show-print-message
  notmuch-show-refresh-view
  notmuch-show-remove-tag
  notmuch-show-reply
  notmuch-show-reply-sender
  notmuch-show-resend-message
  notmuch-show-resume-message
  notmuch-show-rewind
  notmuch-show-save-attachments
  notmuch-show-save-part
  notmuch-show-setup-w3m
  notmuch-show-stash-cc
  notmuch-show-stash-date
  notmuch-show-stash-filename
  notmuch-show-stash-from
  notmuch-show-stash-git-send-email
  notmuch-show-stash-message-id
  notmuch-show-stash-message-id-stripped
  notmuch-show-stash-mlarchive-link
  notmuch-show-stash-mlarchive-link-and-go
  notmuch-show-stash-subject
  notmuch-show-stash-tags
  notmuch-show-stash-to
  notmuch-show-stash-transient
  notmuch-show-tag
  notmuch-show-tag-all
  notmuch-show-toggle-elide-non-matching
  notmuch-show-toggle-message
  notmuch-show-toggle-part-invisibility
  notmuch-show-toggle-process-crypto
  notmuch-show-toggle-thread-indentation
  notmuch-show-toggle-visibility-headers
  notmuch-show-view-all-mime-parts
  notmuch-show-view-part
  notmuch-show-view-raw-message
  notmuch-stash-query
  notmuch-subkeymap-help
  notmuch-tag-jump
  notmuch-tag-transient
  notmuch-tag-undo
  notmuch-tree
  notmuch-tree-add-tag
  notmuch-tree-archive-message
  notmuch-tree-archive-message-then-next
  notmuch-tree-archive-message-then-next-or-exit
  notmuch-tree-archive-thread
  notmuch-tree-archive-thread-then-exit
  notmuch-tree-archive-thread-then-next
  notmuch-tree-close-message-window
  notmuch-tree-filter
  notmuch-tree-filter-by-tag
  notmuch-tree-forward-message
  notmuch-tree-from-search-current-query
  notmuch-tree-from-search-thread
  notmuch-tree-from-show-current-query
  notmuch-tree-from-unthreaded-current-query
  notmuch-tree-help
  notmuch-tree-jump-search
  notmuch-tree-matching-message
  notmuch-tree-mode
  notmuch-tree-mode-transient
  notmuch-tree-new-mail
  notmuch-tree-next-matching-message
  notmuch-tree-next-message
  notmuch-tree-next-message-button
  notmuch-tree-next-thread
  notmuch-tree-next-thread-from-search
  notmuch-tree-next-thread-in-tree
  notmuch-tree-prev-matching-message
  notmuch-tree-prev-message
  notmuch-tree-prev-thread
  notmuch-tree-prev-thread-in-tree
  notmuch-tree-previous-message-button
  notmuch-tree-quit
  notmuch-tree-refresh-view
  notmuch-tree-remove-tag
  notmuch-tree-reply
  notmuch-tree-reply-sender
  notmuch-tree-resume-message
  notmuch-tree-scroll-message-window
  notmuch-tree-scroll-message-window-back
  notmuch-tree-scroll-or-next
  notmuch-tree-show-message
  notmuch-tree-show-message-in
  notmuch-tree-show-message-out
  notmuch-tree-tag
  notmuch-tree-tag-thread
  notmuch-tree-to-search
  notmuch-tree-to-tree
  notmuch-tree-toggle-message-process-crypto
  notmuch-tree-toggle-order
  notmuch-tree-view-raw-message
  notmuch-tree-worker
  notmuch-unthreaded
  notmuch-unthreaded-from-search-current-query
  notmuch-unthreaded-from-show-current-query
  notmuch-unthreaded-from-tree-current-query
  )
(defvar emacsvox-notmuch--advice nil
  "Current Notmuch targets and their native advice functions.")
(setq emacsvox-notmuch--advice nil)

(defun emacsvox-notmuch--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-notmuch--advice))))

(defun emacsvox-notmuch--open-feedback ()
  "Speak a newly opened Notmuch view."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(defun emacsvox-notmuch--hello-widget-count (widget)
  "Return the displayed result count preceding saved-search WIDGET."
  (when-let* ((start (widget-get widget :from)))
    (save-excursion
      (goto-char start)
      (skip-chars-backward " \t")
      (let ((end (point)))
        (skip-chars-backward "^ \t\n")
        (unless (= (point) end)
          (buffer-substring-no-properties (point) end))))))

(defun emacsvox-notmuch--hello-widget-summary ()
  "Speak the Notmuch Hello widget at point."
  (when-let* ((widget (widget-at (point)))
              (value (widget-value widget))
              (label (string-trim (format "%s" value))))
    (let* ((count
            (and
             (widget-get widget :notmuch-search-terms)
             (emacsvox-notmuch--hello-widget-count widget)))
           (summary
            (cond
             (count
              (format
               "%s, %s %s"
               label count
               (if (string= count "1") "message" "messages")))
             ((eq (widget-type widget) 'push-button)
              (format "%s button" label))
             ((eq (widget-type widget) 'link)
              (format "%s link" label))
             (t label))))
      (emacsvox-icon 'item)
      (tts-speak summary))))

(defun emacsvox-notmuch--hello-widget-navigation-around
    (target original arguments)
  "Speak Notmuch Hello widgets reached by TARGET.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (if (and
       (eq major-mode 'notmuch-hello-mode)
       (ems-interactive-p target))
      (let ((result (apply original arguments)))
        (emacsvox-notmuch--hello-widget-summary)
        result)
    (apply original arguments)))

(defun emacsvox--advice-widget-forward-notmuch-around (original &rest arguments)
  "Speak the Notmuch Hello widget reached by `widget-forward'."
  (emacsvox-notmuch--hello-widget-navigation-around
   'widget-forward original arguments))

(defun emacsvox--advice-widget-backward-notmuch-around (original &rest arguments)
  "Speak the Notmuch Hello widget reached by `widget-backward'."
  (emacsvox-notmuch--hello-widget-navigation-around
   'widget-backward original arguments))

(push
 '(widget-forward :around emacsvox--advice-widget-forward-notmuch-around)
 emacsvox-notmuch--advice)

(push
 '(widget-backward :around emacsvox--advice-widget-backward-notmuch-around)
 emacsvox-notmuch--advice)

(emacsvox-notmuch--register-after-group
 '(notmuch notmuch-hello notmuch-hello-update)
 #'emacsvox-notmuch--open-feedback)

(defun emacsvox-notmuch--close-feedback ()
  "Speak after closing a Notmuch view."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-notmuch--register-after-group
 '(notmuch-bury-or-kill-this-buffer)
 #'emacsvox-notmuch--close-feedback)

(defun emacsvox-notmuch--search-feedback ()
  "Speak a Notmuch search result."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-notmuch--register-after-group
 '(notmuch-search)
 #'emacsvox-notmuch--search-feedback)

(defun emacsvox-notmuch--show-feedback ()
  "Speak the first message in a newly opened Notmuch thread."
  (emacsvox-notmuch--move-to-message-body)
  (emacsvox-icon 'open-object)
  (emacsvox-notmuch-speak-show-message))

(defun emacsvox-notmuch--blank-visual-line-pitch ()
  "Return the Emacsvox blank-line pitch in Notmuch Show.
Return nil outside `notmuch-show-mode' or when the current visual
line contains non-whitespace text."
  (when (eq major-mode 'notmuch-show-mode)
    (save-excursion
      (beginning-of-visual-line)
      (let ((start (point)))
        (end-of-visual-line)
        (let ((line (buffer-substring-no-properties start (point))))
          (cond
           ((string-empty-p line)
            (let ((physical-line
                   (buffer-substring-no-properties
                    (line-beginning-position) (line-end-position))))
              (cond
               ((string-empty-p physical-line) 130.8)
               ((string-match-p "\\`[[:space:]]+\\'" physical-line)
                261.6))))
           ((string-match-p "\\`[[:space:]]+\\'" line) 261.6)))))))

(defun emacsvox--advice-emacsvox-speak-visual-line-notmuch-around
    (original &rest arguments)
  "Add standard blank-line tones to visual-line speech in Notmuch Show."
  (let ((pitch (emacsvox-notmuch--blank-visual-line-pitch)))
    (when pitch
      (tts-stop 'all))
    (prog1
        (apply original arguments)
      (when pitch
        (tts-tone pitch 150 'force)))))

(push
 '(emacsvox-speak-visual-line
   :around emacsvox--advice-emacsvox-speak-visual-line-notmuch-around)
 emacsvox-notmuch--advice)

(emacsvox-notmuch--register-after-group
 '(notmuch-show notmuch-search-show-thread)
 #'emacsvox-notmuch--show-feedback)

(defun emacsvox-notmuch--navigation-feedback ()
  "Speak the Notmuch search result selected by navigation."
  (emacsvox-notmuch-speak-search-result))

(emacsvox-notmuch--register-after-group
 '(notmuch-search-next-thread
   notmuch-search-previous-thread
   notmuch-search-first-thread
   notmuch-search-last-thread)
 #'emacsvox-notmuch--navigation-feedback)

(defun emacsvox-notmuch--show-navigation-feedback ()
  "Select and speak the Notmuch message body reached by navigation."
  (emacsvox-notmuch--move-to-message-body)
  (emacsvox-notmuch-speak-show-message))

(defun emacsvox-notmuch--previous-navigation-around
    (target original arguments)
  "Navigate to the previous message for interactive TARGET.
Call ORIGINAL once with ARGUMENTS, then select and speak the body."
  (if (and
       (eq major-mode 'notmuch-show-mode)
       (ems-interactive-p target))
      (progn
        (notmuch-show-move-to-message-top)
        (let ((result (apply original arguments)))
          (emacsvox-notmuch--show-navigation-feedback)
          result))
    (apply original arguments)))

(defun emacsvox--advice-notmuch-show-previous-message-around
    (original &rest arguments)
  "Navigate backward from a body with `notmuch-show-previous-message'."
  (emacsvox-notmuch--previous-navigation-around
   'notmuch-show-previous-message original arguments))

(defun emacsvox--advice-notmuch-show-previous-open-message-around
    (original &rest arguments)
  "Navigate backward from a body with `notmuch-show-previous-open-message'."
  (emacsvox-notmuch--previous-navigation-around
   'notmuch-show-previous-open-message original arguments))

(push
 '(notmuch-show-previous-message
   :around emacsvox--advice-notmuch-show-previous-message-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-previous-open-message
   :around emacsvox--advice-notmuch-show-previous-open-message-around)
 emacsvox-notmuch--advice)

(emacsvox-notmuch--register-after-group
 '(notmuch-show-next-message
   notmuch-show-next-open-message
   notmuch-show-next-matching-message)
 #'emacsvox-notmuch--show-navigation-feedback)

(emacsvox-notmuch--register-after-group
 '(notmuch-show-next-button
   notmuch-show-previous-button)
 #'emacsvox-notmuch--speak-show-button)

(defun emacsvox-notmuch--part-action-around
    (target action original arguments)
  "Confirm ACTION performed by TARGET on the current MIME part.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (let ((part
         (or
          (emacsvox-notmuch--part-at-point (button-at (point)))
          (ignore-errors (notmuch-show-get-part-properties))))
        (result (apply original arguments)))
    (when (and part (ems-interactive-p target))
      (emacsvox-notmuch--part-action-feedback action part))
    result))

(defun emacsvox--advice-notmuch-show-save-part-around
    (original &rest arguments)
  "Confirm saving the current Notmuch MIME part."
  (emacsvox-notmuch--part-action-around
   'notmuch-show-save-part 'save original arguments))

(defun emacsvox--advice-notmuch-show-view-part-around
    (original &rest arguments)
  "Confirm viewing the current Notmuch MIME part."
  (emacsvox-notmuch--part-action-around
   'notmuch-show-view-part 'view original arguments))

(defun emacsvox--advice-notmuch-show-interactively-view-part-around
    (original &rest arguments)
  "Confirm interactively viewing the current Notmuch MIME part."
  (emacsvox-notmuch--part-action-around
   'notmuch-show-interactively-view-part 'view original arguments))

(defun emacsvox--advice-notmuch-show-choose-mime-of-part-around
    (original &rest arguments)
  "Confirm viewing the current Notmuch part with a chosen MIME type."
  (emacsvox-notmuch--part-action-around
   'notmuch-show-choose-mime-of-part 'view original arguments))

(push
 '(notmuch-show-save-part
   :around emacsvox--advice-notmuch-show-save-part-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-view-part
   :around emacsvox--advice-notmuch-show-view-part-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-interactively-view-part
   :around emacsvox--advice-notmuch-show-interactively-view-part-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-choose-mime-of-part
   :around emacsvox--advice-notmuch-show-choose-mime-of-part-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--part-visibility-feedback (hidden part)
  "Report whether Notmuch MIME PART is HIDDEN."
  (emacsvox-icon (if hidden 'close-object 'open-object))
  (tts-speak
   (format "%s %s"
           (emacsvox-notmuch--part-action-object part)
           (if hidden "hidden" "shown"))))

(defun emacsvox--advice-notmuch-show-part-button-default-around
    (original &rest arguments)
  "Confirm the default action on a Notmuch MIME-part button."
  (let* ((button (or (car arguments) (button-at (point))))
         (part (emacsvox-notmuch--part-at-point button))
         (hidden-before
          (and button (button-get button :notmuch-part-hidden)))
         (action notmuch-show-part-button-default-action)
         (result (apply original arguments)))
    (when (and part
               (ems-interactive-p 'notmuch-show-part-button-default))
      (let ((hidden-after
             (and button (button-get button :notmuch-part-hidden))))
        (cond
         ((not (eq hidden-before hidden-after))
          (emacsvox-notmuch--part-visibility-feedback
           hidden-after part))
         ((eq action 'notmuch-show-save-part)
          (emacsvox-notmuch--part-action-feedback 'save part))
         ((memq action
                '(notmuch-show-view-part
                  notmuch-show-interactively-view-part))
          (emacsvox-notmuch--part-action-feedback 'view part)))))
    result))

(push
 '(notmuch-show-part-button-default
   :around emacsvox--advice-notmuch-show-part-button-default-around)
 emacsvox-notmuch--advice)

(defun emacsvox--advice-notmuch-show-save-attachments-around
    (original &rest arguments)
  "Confirm saving attachments from the current Notmuch message."
  (let* ((message
          (ignore-errors (notmuch-show-get-message-properties)))
         (count
          (and
           message
           (emacsvox-notmuch--attachment-count
            (plist-get message :body))))
         (result (apply original arguments)))
    (when (ems-interactive-p 'notmuch-show-save-attachments)
      (if (and count (> count 0))
          (progn
            (emacsvox-icon 'save-object)
            (tts-speak "Finished saving attachments"))
        (emacsvox-icon 'select-object)
        (tts-speak "No attachments to save")))
    result))

(push
 '(notmuch-show-save-attachments
   :around emacsvox--advice-notmuch-show-save-attachments-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--show-reading-around (target original arguments)
  "Provide state-aware reading feedback for TARGET.
Call ORIGINAL once with ARGUMENTS.  Speak a semantic summary when
the selected message changes; otherwise speak the visible window."
  (let ((before-message (emacsvox-notmuch--current-show-message-id))
        (result (apply original arguments)))
    (when (ems-interactive-p target)
      (when (eq major-mode 'notmuch-show-mode)
        (let ((after-message
               (emacsvox-notmuch--current-show-message-id)))
          (cond
           ((not (equal before-message after-message))
            (emacsvox-notmuch-speak-show-message))
           ((and (eq target 'notmuch-show-advance) (eobp))
            (emacsvox-icon 'select-object)
            (tts-speak "End of thread"))
           (t
            (emacsvox-icon 'scroll)
            (emacsvox-speak-current-window))))))
    result))

(defun emacsvox--advice-notmuch-show-advance-around
    (original &rest arguments)
  "Provide state-aware reading feedback around Show advance."
  (emacsvox-notmuch--show-reading-around
   'notmuch-show-advance original arguments))

(defun emacsvox--advice-notmuch-show-rewind-around
    (original &rest arguments)
  "Provide state-aware reading feedback around Show rewind."
  (emacsvox-notmuch--show-reading-around
   'notmuch-show-rewind original arguments))

(push
 '(notmuch-show-advance
   :around emacsvox--advice-notmuch-show-advance-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-rewind
   :around emacsvox--advice-notmuch-show-rewind-around)
 emacsvox-notmuch--advice)

(defun emacsvox--advice-notmuch-show-advance-and-archive-around
    (original &rest arguments)
  "Provide reading or archive feedback for the Space-bound command."
  (let ((at-thread-end
         (and (eq major-mode 'notmuch-show-mode) (eobp))))
    (if at-thread-end
        (let ((will-archive notmuch-archive-tags)
              (result (apply original arguments)))
          (when (ems-interactive-p 'notmuch-show-advance-and-archive)
            (if will-archive
                (emacsvox-notmuch--show-archive-feedback
                 'thread nil t)
              (emacsvox-notmuch--speak-current-item)))
          result)
      (emacsvox-notmuch--show-reading-around
       'notmuch-show-advance-and-archive original arguments))))

(push
 '(notmuch-show-advance-and-archive
   :around emacsvox--advice-notmuch-show-advance-and-archive-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--show-visibility-feedback ()
  "Indicate whether the current Notmuch message body is visible."
  (if (plist-get
       (notmuch-show-get-message-properties)
       :message-visible)
      (progn
        (emacsvox-icon 'open-object)
        (emacsvox-notmuch-speak-show-message))
    (emacsvox-icon 'close-object)))

(emacsvox-notmuch--register-after-group
 '(notmuch-show-toggle-message
   notmuch-show-open-or-close-all)
 #'emacsvox-notmuch--show-visibility-feedback)

(defun emacsvox-notmuch--tag-change-summary (tag-changes)
  "Return a concise description of Notmuch TAG-CHANGES."
  (let (added removed changed)
    (dolist (change tag-changes)
      (cond
       ((string-prefix-p "+" change)
        (push (substring change 1) added))
       ((string-prefix-p "-" change)
        (push (substring change 1) removed))
       (t (push change changed))))
    (string-join
     (delq
      nil
      (list
       (when added
         (format "Added %s" (string-join (nreverse added) ", ")))
       (when removed
         (format "Removed %s" (string-join (nreverse removed) ", ")))
       (when changed
         (format "Changed %s" (string-join (nreverse changed) ", ")))))
     "; ")))

(defun emacsvox-notmuch--tag-change-name (tag-change)
  "Return the bare tag name from TAG-CHANGE."
  (if (string-match-p "\\`[+-]" tag-change)
      (substring tag-change 1)
    tag-change))

(defun emacsvox-notmuch--ordinary-tag-changes (tag-changes status-icons)
  "Return TAG-CHANGES not represented by STATUS-ICONS."
  (cl-remove-if
   (lambda (change)
     (assoc
      (emacsvox-notmuch--tag-change-name change)
      status-icons))
   tag-changes))

(defun emacsvox-notmuch--removed-status-p (tag-changes status-icons)
  "Return non-nil when TAG-CHANGES removes a status in STATUS-ICONS."
  (cl-some
   (lambda (change)
     (and
      (string-prefix-p "-" change)
      (assoc (substring change 1) status-icons)))
   tag-changes))

(defun emacsvox-notmuch--tag-operation-feedback
    (tag-changes status-icons speaker)
  "Confirm TAG-CHANGES and call SPEAKER for the updated item.
Statuses represented by STATUS-ICONS remain nonverbal."
  (when tag-changes
    (let ((ordinary
           (emacsvox-notmuch--ordinary-tag-changes
            tag-changes status-icons)))
      (when ordinary
        (emacsvox-icon 'task-done)
        (tts-speak (emacsvox-notmuch--tag-change-summary ordinary)))
      (when
          (emacsvox-notmuch--removed-status-p
           tag-changes status-icons)
        (emacsvox-icon 'deselect-object))
      (funcall speaker))))

(defun emacsvox-notmuch--tag-feedback (tag-changes)
  "Confirm TAG-CHANGES and speak the updated Notmuch result."
  (emacsvox-notmuch--tag-operation-feedback
   tag-changes
   emacsvox-notmuch-search-status-icons
   #'emacsvox-notmuch-speak-search-result))

(defun emacsvox-notmuch--show-tag-feedback (tag-changes)
  "Confirm TAG-CHANGES and speak the updated Notmuch message."
  (emacsvox-notmuch--tag-operation-feedback
   tag-changes
   emacsvox-notmuch-show-status-icons
   #'emacsvox-notmuch-speak-show-message))

(defun emacsvox-notmuch--register-tag-group (targets feedback)
  "Register tag-operation FEEDBACK for TARGETS."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (tag-changes &rest _)
          ,(format "Confirm tag changes after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback tag-changes))))
      (push (list target :after advice-function) emacsvox-notmuch--advice))))

(emacsvox-notmuch--register-tag-group
 '(notmuch-search-tag
   notmuch-search-add-tag
   notmuch-search-remove-tag
   notmuch-search-tag-all)
 #'emacsvox-notmuch--tag-feedback)

(emacsvox-notmuch--register-tag-group
 '(notmuch-show-tag
   notmuch-show-add-tag
   notmuch-show-remove-tag
   notmuch-show-tag-all)
 #'emacsvox-notmuch--show-tag-feedback)

(defun emacsvox-notmuch--current-tags ()
  "Return a copy of the tags at point in a Notmuch search or Show buffer."
  (let ((tags
         (pcase major-mode
           ('notmuch-search-mode
            (plist-get (notmuch-search-get-result) :tags))
           ('notmuch-show-mode
            (plist-get
             (notmuch-show-get-message-properties)
             :tags)))))
    (and tags (copy-sequence tags))))

(defun emacsvox-notmuch--tag-differences (before after)
  "Return Notmuch tag operations that transform BEFORE into AFTER."
  (append
   (mapcar
    (lambda (tag) (concat "+" tag))
    (cl-remove-if (lambda (tag) (member tag before)) after))
   (mapcar
    (lambda (tag) (concat "-" tag))
    (cl-remove-if (lambda (tag) (member tag after)) before))))

(defun emacsvox-notmuch--tag-state-around (target original arguments)
  "Report structured tag changes made by TARGET.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (let ((mode major-mode)
        (before (emacsvox-notmuch--current-tags))
        (result (apply original arguments)))
    (when (ems-interactive-p target)
      (let ((changes
             (emacsvox-notmuch--tag-differences
              before
              (emacsvox-notmuch--current-tags))))
        (when changes
          (pcase mode
            ('notmuch-search-mode
             (emacsvox-notmuch--tag-feedback changes))
            ('notmuch-show-mode
             (emacsvox-notmuch--show-tag-feedback changes))))))
    result))

(defun emacsvox--advice-notmuch-tag-jump-around
    (original &rest arguments)
  "Report the tag operation selected from Notmuch's tag menu."
  (emacsvox-notmuch--tag-state-around
   'notmuch-tag-jump original arguments))

(defun emacsvox--advice-notmuch-show-mark-read-around
    (original &rest arguments)
  "Report an interactive Notmuch read-state change."
  (emacsvox-notmuch--tag-state-around
   'notmuch-show-mark-read original arguments))

(push
 '(notmuch-tag-jump
   :around emacsvox--advice-notmuch-tag-jump-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-mark-read
   :around emacsvox--advice-notmuch-show-mark-read-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--speak-current-item ()
  "Speak the current structured item in a Notmuch Show or search buffer."
  (pcase major-mode
    ('notmuch-show-mode
     (emacsvox-notmuch-speak-show-message))
    ('notmuch-search-mode
     (emacsvox-notmuch-speak-search-result))))

(defun emacsvox-notmuch--show-archive-feedback
    (object unarchive speak-destination)
  "Confirm archiving OBJECT and optionally SPEAK-DESTINATION.
When UNARCHIVE is non-nil, confirm the reverse operation."
  (emacsvox-icon (if unarchive 'open-object 'close-object))
  (tts-speak
   (format
    "%s %s"
    (if unarchive "Unarchived" "Archived")
    (symbol-name object)))
  (when speak-destination
    (emacsvox-notmuch--speak-current-item)))

(defun emacsvox--advice-notmuch-show-archive-message-after
    (&optional unarchive &rest _)
  "Confirm an interactive message archive operation."
  (when (ems-interactive-p 'notmuch-show-archive-message)
    (emacsvox-notmuch--show-archive-feedback
     'message unarchive t)))

(defun emacsvox--advice-notmuch-show-archive-thread-after
    (&optional unarchive &rest _)
  "Confirm an interactive thread archive operation."
  (when (ems-interactive-p 'notmuch-show-archive-thread)
    (emacsvox-notmuch--show-archive-feedback
     'thread unarchive t)))

(push
 '(notmuch-show-archive-message
   :after emacsvox--advice-notmuch-show-archive-message-after)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-archive-thread
   :after emacsvox--advice-notmuch-show-archive-thread-after)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--register-show-archive-group (targets object)
  "Register archive feedback for TARGETS operating on OBJECT."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Confirm archiving after `%s'." target)
          (when (ems-interactive-p ',target)
            (emacsvox-notmuch--show-archive-feedback
             ',object nil t))))
      (push (list target :after advice-function) emacsvox-notmuch--advice))))

(emacsvox-notmuch--register-show-archive-group
 '(notmuch-show-archive-message-then-next-or-exit
   notmuch-show-archive-message-then-next-or-next-thread)
 'message)

(emacsvox-notmuch--register-show-archive-group
 '(notmuch-show-archive-thread-then-next
   notmuch-show-archive-thread-then-exit)
 'thread)

(defun emacsvox--advice-notmuch-search-archive-thread-after
    (&optional unarchive &rest _)
  "Confirm an archive operation and speak the current result."
  (when (ems-interactive-p 'notmuch-search-archive-thread)
    (emacsvox-icon 'close-object)
    (tts-speak (if unarchive "Unarchived" "Archived"))
    (emacsvox-notmuch-speak-search-result)))

(push
 '(notmuch-search-archive-thread
   :after emacsvox--advice-notmuch-search-archive-thread-after)
 emacsvox-notmuch--advice)

(defconst emacsvox-notmuch--refresh-process-property
  'emacsvox-notmuch-announce-refresh
  "Process property requesting refresh-completion feedback.")

(defun emacsvox-notmuch--search-result-count (&optional buffer)
  "Count structured Notmuch search results in BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (let ((position (point-min))
          (limit (point-max))
          (count 0))
      (while (< position limit)
        (when (get-text-property position 'notmuch-search-result)
          (cl-incf count))
        (setq position
              (or
               (next-single-property-change
                position 'notmuch-search-result nil limit)
               limit)))
      count)))

(defun emacsvox-notmuch--announce-refresh-complete (&optional buffer)
  "Announce completed Notmuch search refresh for BUFFER."
  (let* ((count (emacsvox-notmuch--search-result-count buffer))
         (noun (if (= count 1) "thread" "threads")))
    (emacsvox-icon 'task-done)
    (tts-speak (format "Search refreshed, %d %s" count noun))))

(defun emacsvox-notmuch--mark-refresh-process ()
  "Mark the current Notmuch search process for completion feedback."
  (when-let* ((process (get-buffer-process (current-buffer))))
    (process-put process emacsvox-notmuch--refresh-process-property t)
    ;; A very small search can finish before the command's after advice runs.
    (unless (process-live-p process)
      (emacsvox--advice-notmuch-search-process-sentinel-after process nil))))

(defun emacsvox--advice-notmuch-search-refresh-view-after (&rest _)
  "Arrange feedback after an interactive search refresh completes."
  (when (ems-interactive-p 'notmuch-search-refresh-view)
    ;; `notmuch-refresh-all-buffers' deliberately refreshes silently.
    (unless (eq this-command 'notmuch-refresh-all-buffers)
      (emacsvox-notmuch--mark-refresh-process))))

(defun emacsvox--advice-notmuch-search-process-sentinel-after (process _event)
  "Announce completion of a marked Notmuch search PROCESS."
  (when (and
         (process-get process emacsvox-notmuch--refresh-process-property)
         (memq (process-status process) '(exit signal)))
    (process-put process emacsvox-notmuch--refresh-process-property nil)
    (let ((buffer (process-buffer process)))
      (if (and
           (eq (process-status process) 'exit)
           (zerop (process-exit-status process))
           (buffer-live-p buffer))
          (emacsvox-notmuch--announce-refresh-complete buffer)
        (emacsvox-icon 'warn-user)
        (tts-speak "Search refresh failed")))))

(push
 '(notmuch-search-refresh-view
   :after emacsvox--advice-notmuch-search-refresh-view-after)
 emacsvox-notmuch--advice)

(push
 '(notmuch-search-process-sentinel
   :after emacsvox--advice-notmuch-search-process-sentinel-after)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--install-advice ()
  "Install advice for Notmuch features loaded so far."
  (dolist (entry emacsvox-notmuch--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature
         '(notmuch notmuch-hello notmuch-lib notmuch-search notmuch-show))
  (eval `(with-eval-after-load ',feature
           (emacsvox-notmuch--install-advice))))

(with-eval-after-load 'notmuch-show
  (define-key
   notmuch-show-mode-map (kbd "C-c C-p")
   #'emacsvox-notmuch-speak-show-position))

;;; MUA:

'(notmuch-mua-kill-buffer
  notmuch-mua-mail
  notmuch-mua-new-mail
  notmuch-mua-send
  notmuch-mua-send-and-exit
  notmuch-mua-send-common)

(provide 'emacsvox-notmuch)
;;;  end of file

                                        ; 
                                        ; 
                                        ; 
