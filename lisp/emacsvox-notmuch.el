;;; emacsvox-notmuch.el --- Speech-enable NOTMUCH  -*- lexical-binding: t; -*-

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
;;
;; Speech access for Notmuch Hello, Search, and Show workflows.  The
;; integration presents saved searches, asynchronous completion, semantic
;; result rows and messages, MIME parts, tag and archive outcomes, and message
;; visibility while leaving database and mail operations to Notmuch.
;;
;; Customize `emacsvox-notmuch' for fields, status cues, automatic content
;; limits, and search-completion policy.  See the
;; @ref{Notmuch Mail,,,emacsvox,Emacsvox User Manual} chapter for setup, keys,
;; privacy, inspection, support boundaries, and troubleshooting; the generated
;; emacsvox-notmuch section is the exhaustive command and option reference.
;; Tree buffers receive semantic module context only.  Message composition is
;; speech-enabled separately by `emacsvox-message'.
;; See https://notmuchmail.org/doc/latest/notmuch-emacs.html for Notmuch itself.

;;; Code:

;;   Required modules:

(require 'cl-lib)
(require 'button)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-notmuch)
(require 'subr-x)
(require 'wid-edit)

(declare-function notmuch-sanitize "notmuch-lib" (str))
(declare-function notmuch-interactive-region "notmuch-lib" ())
(declare-function notmuch-search-foreach-result "notmuch" (beg end fn))
(declare-function notmuch-search-get-result "notmuch" (&optional pos))
(declare-function notmuch-search-next-thread "notmuch" ())
(declare-function notmuch-search-previous-thread "notmuch" ())
(declare-function notmuch-show-clean-address "notmuch-show" (address))
(declare-function notmuch-show-get-message-id "notmuch-show" (&optional bare))
(declare-function notmuch-show-get-message-properties "notmuch-show" ())
(declare-function notmuch-show-get-part-properties "notmuch-show" ())
(declare-function notmuch-show-mapc "notmuch-show" (function))
(declare-function notmuch-show-message-extent "notmuch-show" ())
(declare-function notmuch-show-move-to-message-top "notmuch-show" ())
(declare-function notmuch-tag-format-tags "notmuch-tag"
                  (tags orig-tags &optional face))
(declare-function tts-notify "tts-speak" (text &optional dont-log))
(declare-function tts-notify-icon "tts-speak" (icon))

(defvar notmuch-archive-tags)
(defvar notmuch-search-mode-map)
(defvar notmuch-show-mode-map)
(defvar notmuch-show-part-button-default-action)

;;; Semantic module context:

(defun emacsvox-notmuch-enable-aural-context ()
  "Identify the current Notmuch buffer to Aural Presentation."
  (setq-local emacsvox-aural-module 'notmuch))

(dolist
    (hook
     '(notmuch-hello-mode-hook notmuch-search-mode-hook
       notmuch-show-mode-hook notmuch-tree-mode-hook))
  (add-hook hook #'emacsvox-notmuch-enable-aural-context))

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

(defcustom emacsvox-notmuch-search-completion-style 'adaptive
  "Control successful asynchronous Notmuch search completion feedback.

With `adaptive', a user-owned search that remains selected and untouched
speaks its final count and the result at point on the primary speech stream.
After the user issues another command, leaves the search buffer, or refreshes
an existing search, completion contains only a generic result count and uses
the notification stream.  `summary' always sends the generic count to the
notification stream, `cue' sends only a task-completion cue there, and
`silent' suppresses successful completion feedback.

Failures remain audible for every style.  Notification feedback contains no
query or message metadata and may be retained in the notifications log.  A
separate notification process is controlled globally by
`tts-notification-device'; when none is available, notification speech falls
back to the primary process."
  :type '(choice
          (const :tag "Adapt to focus and interaction" adaptive)
          (const :tag "Result count only" summary)
          (const :tag "Completion cue only" cue)
          (const :tag "No successful completion feedback" silent))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-automatic-field-character-limit 256
  "Maximum characters spoken from one automatic Notmuch field.

This limit applies to mail-controlled fields before automatic navigation,
opening, action, and widget feedback is submitted.  A truncation notice uses
part of the limit.  Set this to nil to disable the per-field character limit;
the total automatic-presentation limits still apply."
  :type '(choice
          (const :tag "No per-field character limit" nil)
          (integer :tag "Characters"))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-automatic-field-byte-limit 1024
  "Maximum UTF-8 bytes spoken from one automatic Notmuch field.

This is a preparation bound as well as a speech bound.  A truncation notice
uses part of the limit.  Set this to nil to disable the per-field byte limit;
the total automatic-presentation limits still apply."
  :type '(choice
          (const :tag "No per-field byte limit" nil)
          (integer :tag "UTF-8 bytes"))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-automatic-total-character-limit 1000
  "Maximum characters in one automatic Notmuch presentation.

The limit includes the explicit truncation notice.  Set this to nil to disable
the total character limit; the total byte limit still applies."
  :type '(choice
          (const :tag "No total character limit" nil)
          (integer :tag "Characters"))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-automatic-total-byte-limit 4096
  "Maximum UTF-8 bytes in one automatic Notmuch presentation.

The limit includes the explicit truncation notice.  Set this to nil to disable
the total byte limit; the total character limit still applies."
  :type '(choice
          (const :tag "No total byte limit" nil)
          (integer :tag "UTF-8 bytes"))
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-mime-node-limit 4096
  "Maximum cons nodes inspected while scanning a Notmuch MIME body."
  :type 'integer
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-mime-depth-limit 64
  "Maximum nesting depth inspected while scanning a Notmuch MIME body."
  :type 'integer
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-search-field-separator ", "
  "String placed between spoken Notmuch search-result fields."
  :type 'string
  :group 'emacsvox-notmuch)

(defcustom emacsvox-notmuch-search-status-icons
  '(("unread" . mail-unread)
    ("replied" . mail-replied)
    ("forwarded" . mail-forwarded)
    ("flagged" . mark-object))
  "Map Notmuch status tags to auditory icons.

Entries are checked in order and every matching non-nil icon is
played.  Tags present in this alist are omitted from the spoken
`tags' field.  Remove an entry to speak that status as an ordinary
tag, or give it a nil icon to keep the status silent.  When the
`mail-message-status-cues' presentation option is enabled, its semantic
rules own unread, replied, forwarded, and flagged cues while these entries
still suppress words."
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
  '(("unread" . mail-unread)
    ("replied" . mail-replied)
    ("forwarded" . mail-forwarded)
    ("flagged" . mark-object))
  "Map Notmuch message status tags to auditory icons.

Entries are checked in order and every matching non-nil icon is
played.  Tags present in this alist are omitted from the spoken
`tags' field.  Remove an entry to speak that status as an ordinary
tag, or give it a nil icon to keep the status silent.  When the
`mail-message-status-cues' presentation option is enabled, its semantic
rules own unread, replied, forwarded, and flagged cues while these entries
still suppress words."
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

;;;  Semantic aural presentation:

(defvar emacsvox-notmuch--automatic-presentation-p t
  "Non-nil while Notmuch content must obey automatic speech budgets.")

(defun emacsvox-notmuch--positive-limit (value)
  "Normalize optional budget VALUE without turning invalid input unlimited."
  (cond
   ((null value) nil)
   ((integerp value) (max 1 value))
   (t 1)))

(defun emacsvox-notmuch--utf8-byte-length (text)
  "Return the number of UTF-8 bytes needed to encode TEXT."
  (string-bytes
   (encode-coding-string (substring-no-properties text) 'utf-8 t)))

(defun emacsvox-notmuch--text-within-limits-p
    (text character-limit byte-limit)
  "Return non-nil when TEXT fits CHARACTER-LIMIT and BYTE-LIMIT.
Nil limits are unbounded.  Avoid encoding text already too long to fit."
  (let ((characters (length text)))
    (and
     (or (null character-limit) (<= characters character-limit))
     (or
      (null byte-limit)
      (and
       (<= characters byte-limit)
       (<= (emacsvox-notmuch--utf8-byte-length text) byte-limit))))))

(defun emacsvox-notmuch--truncation-hint ()
  "Return the concise full-detail hint appropriate to the current view."
  (pcase major-mode
    ((or 'notmuch-search-mode 'notmuch-show-mode)
     "C-c C-p gives full details")
    ('notmuch-hello-mode "RET opens full details")
    (_ "full details are available on demand")))

(defun emacsvox-notmuch--truncation-notice (label omitted)
  "Return a trusted truncation notice for LABEL and OMITTED characters."
  (format
   " … [%s shortened: %d characters omitted; %s]"
   label omitted (emacsvox-notmuch--truncation-hint)))

(defun emacsvox-notmuch--safe-prefix-end (text end)
  "Move END backward when it splits a non-whitespace token in TEXT."
  (if
      (or
       (zerop end)
       (= end (length text))
       (memq (aref text (1- end)) '(?\s ?\t ?\n ?\r))
       (memq (aref text end) '(?\s ?\t ?\n ?\r)))
      end
    (let ((position end))
      (while
          (and
           (> position 0)
           (not
            (memq
             (aref text (1- position))
             '(?\s ?\t ?\n ?\r))))
        (cl-decf position))
      (while
          (and
           (> position 0)
           (memq
            (aref text (1- position))
            '(?\s ?\t ?\n ?\r)))
        (cl-decf position))
      position)))

(defun emacsvox-notmuch--bounded-text-components
    (text character-limit byte-limit label &optional total-characters)
  "Return bounded TEXT components under character and UTF-8 byte limits.

The result is (PREFIX NOTICE OMITTED).  LABEL identifies the shortened field.
TOTAL-CHARACTERS may exceed the supplied TEXT length when TEXT is an early,
bounded copy of a larger source buffer."
  (let* ((character-limit
          (emacsvox-notmuch--positive-limit character-limit))
         (byte-limit (emacsvox-notmuch--positive-limit byte-limit))
         (available (length text))
         (total (or total-characters available)))
    (if
        (or
         (not emacsvox-notmuch--automatic-presentation-p)
         (and
          (= available total)
          (emacsvox-notmuch--text-within-limits-p
           text character-limit byte-limit)))
        (list text nil 0)
      (let ((low 0)
            (high
             (min
              available
              (or character-limit available)
              ;; Every character occupies at least one UTF-8 byte.
              (or byte-limit available)))
            (best 0))
        (while (<= low high)
          (let* ((middle (/ (+ low high) 2))
                 (notice
                  (emacsvox-notmuch--truncation-notice
                   label (- total middle)))
                 (candidate (concat (substring text 0 middle) notice)))
            (if
                (emacsvox-notmuch--text-within-limits-p
                 candidate character-limit byte-limit)
                (setq best middle
                      low (1+ middle))
              (setq high (1- middle)))))
        (setq best (emacsvox-notmuch--safe-prefix-end text best))
        (let ((notice
               (emacsvox-notmuch--truncation-notice
                label (- total best))))
          ;; Extremely small custom limits may not fit the full trusted notice.
          ;; Preserve a visible marker while respecting those limits.
          (unless
              (emacsvox-notmuch--text-within-limits-p
               (concat (substring text 0 best) notice)
               character-limit byte-limit)
            (setq best 0
                  notice "… [shortened]"))
          (while
              (and
               (> (length notice) 0)
               (not
                (emacsvox-notmuch--text-within-limits-p
                 notice character-limit byte-limit)))
            (setq notice (substring notice 0 -1)))
          (list (substring text 0 best) notice (- total best)))))))

(defun emacsvox-notmuch--bounded-text
    (text character-limit byte-limit label &optional total-characters)
  "Return TEXT bounded for LABEL, including an explicit omission notice."
  (when text
    (pcase-let
        ((`(,prefix ,notice ,_omitted)
          (emacsvox-notmuch--bounded-text-components
           text character-limit byte-limit label total-characters)))
      (concat prefix notice))))

(defun emacsvox-notmuch--prepare-field-text
    (value label &optional transform)
  "Bound VALUE as mail field LABEL, then apply optional TRANSFORM to its prefix."
  (when value
    (let ((raw (if (stringp value) value (format "%s" value))))
      (pcase-let
          ((`(,prefix ,notice ,_omitted)
            (emacsvox-notmuch--bounded-text-components
             raw
             emacsvox-notmuch-automatic-field-character-limit
             emacsvox-notmuch-automatic-field-byte-limit
             label)))
        (let* ((prepared (if transform (funcall transform prefix) prefix))
               (trimmed (string-trim prepared))
               (text
                (cond
                 ((and (string-empty-p trimmed) notice)
                  (string-trim-left notice))
                 (notice (concat trimmed notice))
                 (t trimmed))))
          (unless (string-empty-p text)
            (emacsvox-notmuch--bounded-text
             text
             emacsvox-notmuch-automatic-field-character-limit
             emacsvox-notmuch-automatic-field-byte-limit
             label)))))))

(defun emacsvox-notmuch--bounded-source-range
    (start end label character-limit byte-limit)
  "Copy source START through END early-bounded for LABEL under given limits."
  (if (not emacsvox-notmuch--automatic-presentation-p)
      (emacsvox-aural-source-substring start end)
    (let* ((character-limit (emacsvox-notmuch--positive-limit character-limit))
           (byte-limit (emacsvox-notmuch--positive-limit byte-limit))
           (copy-limit
            (min
             (- end start)
             (or character-limit (- end start))
             (or byte-limit (- end start))))
           (text
            (emacsvox-aural-source-substring
             start (+ start copy-limit))))
      (pcase-let
          ((`(,prefix ,notice ,_omitted)
            (emacsvox-notmuch--bounded-text-components
             text character-limit byte-limit label (- end start))))
        (if (and notice (string-empty-p prefix))
            (string-trim-left notice)
          (concat prefix notice))))))

(defun emacsvox-notmuch--bounded-source-substring (start end label)
  "Copy source START through END early-bounded as field LABEL."
  (emacsvox-notmuch--bounded-source-range
   start end label
   emacsvox-notmuch-automatic-field-character-limit
   emacsvox-notmuch-automatic-field-byte-limit))

(defun emacsvox-notmuch--limit-automatic-presentation (text)
  "Apply the total automatic Notmuch presentation budget to TEXT."
  (emacsvox-notmuch--bounded-text
   text
   emacsvox-notmuch-automatic-total-character-limit
   emacsvox-notmuch-automatic-total-byte-limit
   "automatic Notmuch speech"))

(defun emacsvox-notmuch--submit-content
    (text facts occasion compatibility-actions &optional delivery-policy)
  "Submit TEXT and COMPATIBILITY-ACTIONS under FACTS and OCCASION.
DELIVERY-POLICY, when non-nil, controls whole-transaction delivery."
  (let ((text
         (and text
              (emacsvox-notmuch--limit-automatic-presentation text)))
        (arguments
         (append
          (list :facts facts :module 'notmuch :occasion occasion
                :compatibility-actions compatibility-actions)
          (when delivery-policy
            (list :delivery-policy delivery-policy)))))
    (if (and (stringp text) (not (string-empty-p text)))
        (apply #'emacsvox-aural-submit text arguments)
      (apply #'emacsvox-aural-submit-actions arguments))))

(defun emacsvox-notmuch--submit-text-feedback
    (facts occasion icon text &optional delivery-policy)
  "Submit explicit TEXT with FACTS, OCCASION, and leading ICON.
DELIVERY-POLICY, when non-nil, controls whole-transaction delivery."
  (emacsvox-notmuch--submit-content
   text facts occasion
   (emacsvox-notmuch--leading-compatibility-actions icon)
   delivery-policy))

(defun emacsvox-notmuch--leading-compatibility-actions (icon)
  "Return a leading compatibility action for ICON, when non-nil."
  (when icon
    (list (emacsvox-aural-compatibility-icon icon))))

(defun emacsvox-notmuch-view-facts (kind action event)
  "Return semantic facts for Notmuch view KIND, ACTION, and EVENT."
  (append
   (list :role 'mail-view :mail-view-kind kind)
   (when action (list :mail-action-kind action))
   (when event (list :events (list event)))))

(defun emacsvox-notmuch--view-summary ()
  "Return a concise voiced summary of the current buffer and mode."
  (let ((name
         (propertize
          (buffer-name) 'personality voice-lighten-medium))
        (mode
         (string-trim
          (downcase (format-mode-line mode-name)))))
    (if (string-empty-p mode)
        name
      (concat
       name ", "
       (propertize mode 'personality voice-animate)))))

(defun emacsvox-notmuch--current-line-content ()
  "Return the current source-aware line without its newline."
  (emacsvox-notmuch--bounded-source-substring
   (line-beginning-position) (line-end-position) "line"))

(defun emacsvox-notmuch-thread-facts (action event)
  "Return semantic facts for a Notmuch thread ACTION and EVENT."
  (append
   '(:role message-thread)
   (when action (list :mail-action-kind action))
   (when event (list :events (list event)))))

(defun emacsvox-notmuch-part-facts (part action event)
  "Return semantic facts for Notmuch PART, ACTION, and EVENT."
  (append
   (list
    :role 'message-part
    :message-part-kind
    (if (plist-get part :filename) 'attachment 'mime-part))
   (when action (list :mail-action-kind action))
   (when event (list :events (list event)))))

(defun emacsvox-notmuch--annotate-field (text field)
  "Return TEXT annotated as semantic Notmuch FIELD content."
  (when text
    (let ((annotated (copy-sequence text)))
      (add-text-properties
       0 (length annotated)
       (list
        emacsvox-aural-facts-property
        (list :role 'field :field-kind field)
        emacsvox-aural-module-property
        'notmuch)
       annotated)
      annotated)))

(defun emacsvox-notmuch-message-facts (message &optional event)
  "Return semantic facts for Notmuch MESSAGE and optional EVENT."
  (let ((tags (plist-get message :tags))
        (attachment-scan
         (and
          (plist-member message :body)
          (emacsvox-notmuch--attachment-scan
           (plist-get message :body))))
        states)
    (when (member "unread" tags) (push 'unread states))
    (when (member "replied" tags) (push 'replied states))
    (when (member "forwarded" tags) (push 'forwarded states))
    (when (member "flagged" tags) (push 'flagged states))
    (when (> (or (plist-get attachment-scan :count) 0) 0)
      (push 'has-attachments states))
    (append
     (list :role 'message)
     (when event (list :events (list event)))
     (when states (list :states (nreverse states))))))

;;;  Search Results:

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

(defun emacsvox-notmuch--status-compatibility-actions
    (result status-icons occasion &optional include-attachments)
  "Return ordered status adapters present in Notmuch RESULT.

STATUS-ICONS maps tags to compatibility cues.  OCCASION identifies the
presentation being prepared.  When INCLUDE-ATTACHMENTS is non-nil, append an
after-content attachment cue when RESULT contains a named MIME attachment."
  (let* ((tags (plist-get result :tags))
         (semantic-navigation
          (and
           (eq occasion 'navigation)
           (emacsvox-aural-feature-fragment-enabled-p
            'mail-message-status-cues)))
         (actions
          (cl-loop
           for (tag . icon) in status-icons
           when
           (and
            icon
            (member tag tags)
            (not
             (and
              semantic-navigation
              (member tag '("unread" "replied" "forwarded" "flagged")))))
           collect (emacsvox-aural-compatibility-icon icon))))
    (when
        (and
         include-attachments
         (not semantic-navigation)
         (> (plist-get
             (emacsvox-notmuch--attachment-scan
              (plist-get result :body))
             :count)
            0))
      (setq
       actions
       (append
        actions
        (list
         (emacsvox-aural-compatibility-icon
          'mail-has-attachment 'after)))))
    actions))

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

;;;  Show Messages:

(defun emacsvox-notmuch--attachment-scan (body)
  "Return a bounded attachment scan plist for MIME BODY.

The result contains :count, :complete, and :nodes.  Traverse iteratively so a
deep, broad, cyclic, improper, or malformed MIME value cannot exhaust Lisp's
call stack.  A non-nil :complete value means the configured node and depth
budgets covered the entire well-formed graph."
  (let* ((node-limit
          (max 1 (or
                  (emacsvox-notmuch--positive-limit
                   emacsvox-notmuch-mime-node-limit)
                  1)))
         (depth-limit
          (max 0 (if (integerp emacsvox-notmuch-mime-depth-limit)
                     emacsvox-notmuch-mime-depth-limit
                   0)))
         (stack (list (cons body 0)))
         (seen (make-hash-table :test #'eq))
         (nodes 0)
         (count 0)
         (complete t))
    (cl-labels
        ((claim
          (cell)
          (cond
           ((gethash cell seen)
            (setq complete nil)
            nil)
           ((>= nodes node-limit)
            (setq complete nil
                  stack nil)
            nil)
           (t
            (puthash cell t seen)
            (cl-incf nodes)
            t))))
      (while stack
        (pcase-let* ((`(,node . ,depth) (pop stack)))
          (cond
           ((not (consp node)))
           ((> depth depth-limit)
            (setq complete nil))
           ((claim node)
            (if (keywordp (car node))
                (let ((cursor node)
                      content-type filename content body-value
                      (valid t)
                      (first t))
                  (while (and valid (consp cursor))
                    (unless first
                      (setq valid (claim cursor)))
                    (setq first nil)
                    (when valid
                      (let ((value-cell (cdr cursor)))
                        (if (not (consp value-cell))
                            (setq valid nil
                                  complete nil)
                          (if (claim value-cell)
                              (progn
                                (pcase (car cursor)
                                  (:content-type
                                   (setq content-type (car value-cell)))
                                  (:filename
                                   (setq filename (car value-cell)))
                                  (:content
                                   (setq content (car value-cell)))
                                  (:body
                                   (setq body-value (car value-cell))))
                                (setq cursor (cdr value-cell)))
                            (setq valid nil))))))
                  (when (and valid (not (null cursor)))
                    (setq complete nil))
                  (when (and content-type filename)
                    (cl-incf count))
                  (when body-value
                    (push (cons body-value (1+ depth)) stack))
                  (when content
                    (push (cons content (1+ depth)) stack)))
              (let ((cursor node)
                    (first t)
                    (valid t))
                (while (and valid (consp cursor))
                  (unless first
                    (setq valid (claim cursor)))
                  (setq first nil)
                  (when valid
                    (push (cons (car cursor) (1+ depth)) stack)
                    (setq cursor (cdr cursor))))
                (when (and valid (not (null cursor)))
                  (setq complete nil))))))))
    (list :count count :complete complete :nodes nodes))))

(defun emacsvox-notmuch--attachment-count (body)
  "Return the safely observed number of named MIME attachments below BODY."
  (plist-get (emacsvox-notmuch--attachment-scan body) :count))

(defun emacsvox-notmuch--attachment-summary (scan)
  "Return a truthful spoken attachment summary for bounded SCAN."
  (let ((count (plist-get scan :count))
        (complete (plist-get scan :complete)))
    (cond
     ((and complete (zerop count)) nil)
     (complete
      (format "%d %s"
              count
              (if (= count 1) "attachment" "attachments")))
     ((> count 0)
      (format "at least %d %s"
              count
              (if (= count 1) "attachment" "attachments")))
     (t "attachment scan incomplete"))))

(defun emacsvox-notmuch--format-show-header (message header face)
  "Format HEADER from MESSAGE using FACE."
  (emacsvox-notmuch--field-string
   (or (plist-get (plist-get message :headers) header) "")
   face
   (downcase (substring (symbol-name header) 1))
   #'notmuch-sanitize))

(defun emacsvox-notmuch--format-show-field (field message)
  "Format FIELD from Notmuch MESSAGE for speech."
  (emacsvox-notmuch--annotate-field
   (pcase field
     ('from
      (let ((from
             (plist-get (plist-get message :headers) :From)))
        (emacsvox-notmuch--field-string
         (or from "")
         'emacsvox-notmuch-message-from
         "from"
         (lambda (text)
           (notmuch-sanitize (notmuch-show-clean-address text))))))
     ('subject
      (emacsvox-notmuch--format-show-header
       message :Subject 'emacsvox-notmuch-message-subject))
     ('date
      (emacsvox-notmuch--field-string
       (or
        (plist-get message :date_relative)
        (plist-get (plist-get message :headers) :Date))
       'emacsvox-notmuch-message-date "date"))
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
      (let ((summary
             (emacsvox-notmuch--attachment-summary
              (emacsvox-notmuch--attachment-scan
               (plist-get message :body)))))
        (when summary
          (emacsvox-notmuch--field-string
           summary
           'emacsvox-notmuch-message-attachments
           "attachments"))))
     ((pred functionp)
      (emacsvox-notmuch--prepare-field-text
       (funcall field message) "custom field"))
     (_ nil))
   (if (symbolp field) field 'custom)))

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

(defun emacsvox-notmuch--submit-show-message
    (message body-line facts occasion &optional icon)
  "Submit Notmuch MESSAGE and BODY-LINE under FACTS and OCCASION.

ICON is a leading compatibility cue.  Status and attachment cues join the
same transaction instead of creating a nested message presentation."
  (if message
      (let* ((summary (emacsvox-notmuch-format-show-message message))
             (speech
              (if (and body-line (not (string-empty-p body-line)))
                  (concat summary "\n" body-line)
                summary)))
        (emacsvox-notmuch--submit-content
         speech facts occasion
         (append
          (emacsvox-notmuch--leading-compatibility-actions icon)
          (emacsvox-notmuch--status-compatibility-actions
           message emacsvox-notmuch-show-status-icons occasion t)))
        speech)
    (emacsvox-notmuch--submit-text-feedback
     facts occasion icon nil)))

(defun emacsvox-notmuch-speak-show-message (&optional message body-line)
  "Speak Notmuch MESSAGE, defaulting to the message at point.
When BODY-LINE is non-nil, speak it after the semantic message summary."
  (interactive)
  (when-let* ((message
               (or
                message
                (and
                 (eq major-mode 'notmuch-show-mode)
                 (notmuch-show-get-message-properties)))))
    (emacsvox-notmuch--submit-show-message
     message body-line
     (emacsvox-notmuch-message-facts message 'focus-entered)
     'navigation)))

(defun emacsvox-notmuch--landed-body-line ()
  "Return the first visible body line after the current landing position."
  (when (eq major-mode 'notmuch-show-mode)
    (when-let* ((extent (ignore-errors (notmuch-show-message-extent)))
                (limit (cdr extent)))
      (save-excursion
        (forward-line 1)
        (when (< (point) limit)
          (let* ((start (line-beginning-position))
                 (end (min limit (line-end-position)))
                 (line
                  (emacsvox-notmuch--bounded-source-substring
                   start end "body line")))
            (unless
                (or
                 (invisible-p start)
                 (string-match-p
                  "\\`[[:space:]]*\\'"
                  (substring-no-properties line)))
              line)))))))

(defun emacsvox-notmuch--speak-landed-message (&optional message)
  "Speak MESSAGE summary and the visible body text reached at point."
  (emacsvox-notmuch-speak-show-message
   message (emacsvox-notmuch--landed-body-line)))

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
  "Speak thread position and complete details for the current Show item."
  (interactive)
  (unless (eq major-mode 'notmuch-show-mode)
    (user-error "This command is only available in Notmuch Show"))
  (when-let* ((message (notmuch-show-get-message-properties))
              (position (emacsvox-notmuch--show-message-position)))
    (let* ((emacsvox-notmuch--automatic-presentation-p nil)
           (part (emacsvox-notmuch--part-at-point))
           (details
            (if part
                (emacsvox-notmuch-format-part part)
              (emacsvox-notmuch-format-show-message message)))
           (position-summary
            (format "Message %d of %d" (car position) (cdr position)))
           (summary
            (if (string-empty-p details)
                position-summary
              (concat position-summary ", " details))))
      (emacsvox-aural-submit
       summary
       :facts
       (if part
           (emacsvox-notmuch-part-facts part 'select nil)
         (emacsvox-notmuch-message-facts message))
       :module 'notmuch
       :occasion 'inspection
       :compatibility-actions
       (unless part
         (emacsvox-notmuch--status-compatibility-actions
          message emacsvox-notmuch-show-status-icons 'inspection t)))
      summary)))

(defun emacsvox-notmuch--current-show-message-id ()
  "Return the current Notmuch show message ID, if available."
  (when (eq major-mode 'notmuch-show-mode)
    (ignore-errors
      (plist-get (notmuch-show-get-message-properties) :id))))

(defun emacsvox-notmuch--move-to-message-body ()
  "Move point to the line before visible leaf content in the current message."
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
        (if found
            (forward-line -1)
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
  (let* ((filename
          (emacsvox-notmuch--prepare-field-text
           (plist-get part :filename) "filename"))
         (content-type
          (emacsvox-notmuch--prepare-field-text
           (or
            (plist-get part :computed-type)
            (plist-get part :content-type))
           "content type"))
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
  (if-let* ((filename
             (emacsvox-notmuch--prepare-field-text
              (plist-get part :filename) "filename")))
      (format "attachment %s" filename)
    (if-let* ((content-type
               (emacsvox-notmuch--prepare-field-text
                (or
                 (plist-get part :computed-type)
                 (plist-get part :content-type))
                "content type")))
        (format "%s part" content-type)
      "MIME part")))

(defun emacsvox-notmuch--speak-show-button ()
  "Cue and identify the current button in a Notmuch Show buffer."
  (when-let* ((button (button-at (point))))
    (if-let* ((part (emacsvox-notmuch--part-at-point button)))
        (emacsvox-notmuch--submit-text-feedback
         (emacsvox-notmuch-part-facts part 'select 'focus-entered)
         'navigation
         (if (plist-get part :filename) 'item 'button)
         (emacsvox-notmuch-format-part part))
      (emacsvox-notmuch--submit-text-feedback
       '(:role message-part :message-part-kind button
         :mail-action-kind select :events (focus-entered))
       'navigation 'large-movement
       (emacsvox-notmuch--prepare-field-text
        (button-label button) "button label")))))

(defun emacsvox-notmuch--part-action-feedback (action part)
  "Confirm ACTION on Notmuch MIME PART."
  (let ((save-p (eq action 'save)))
    (emacsvox-notmuch--submit-text-feedback
     (emacsvox-notmuch-part-facts
      part (if save-p 'save 'show) 'operation-completed)
     'state-change
     (if save-p 'save-object 'open-object)
     (format "%s %s"
             (if save-p "Saved" "Opened")
             (emacsvox-notmuch--part-action-object part)))))

;;;  Interactive Commands:

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
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-view-facts
    (pcase major-mode
      ('notmuch-hello-mode 'group)
      ('notmuch-search-mode 'search)
      ('notmuch-show-mode 'thread)
      (_ 'other))
    'open 'mail-view-opened)
   'state-change 'open-object
   (emacsvox-notmuch--view-summary)))

(defun emacsvox-notmuch--hello-widget-count (widget)
  "Return the displayed result count preceding saved-search WIDGET."
  (when-let* ((start (widget-get widget :from)))
    (save-excursion
      (goto-char start)
      (skip-chars-backward " \t")
      (let ((end (point)))
        (skip-chars-backward "^ \t\n")
        (unless (= (point) end)
          (substring-no-properties
           (emacsvox-notmuch--bounded-source-substring
            (point) end "message count")))))))

(defun emacsvox-notmuch--hello-widget-summary ()
  "Speak the Notmuch Hello widget at point."
  (when-let* ((widget (widget-at (point)))
              (value (widget-value widget))
              (label
               (emacsvox-notmuch--prepare-field-text
                value "widget label")))
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
      (emacsvox-notmuch--submit-text-feedback
       (list
        :role 'message-part
        :message-part-kind
        (if (eq (widget-type widget) 'link) 'link 'button)
        :mail-action-kind 'select
        :events '(focus-entered))
       'navigation 'item summary))))

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
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-view-facts 'other 'close 'mail-view-closed)
   'state-change 'close-object
   (emacsvox-notmuch--view-summary)
   'urgent))

(emacsvox-notmuch--register-after-group
 '(notmuch-bury-or-kill-this-buffer)
 #'emacsvox-notmuch--close-feedback)

(defun emacsvox-notmuch--show-feedback ()
  "Speak the first message in a newly opened Notmuch thread."
  (emacsvox-notmuch--move-to-message-body)
  (let* ((message
          (and
           (eq major-mode 'notmuch-show-mode)
           (notmuch-show-get-message-properties)))
         (facts
         (and
           message
           (emacsvox-notmuch-message-facts message 'message-opened))))
    (emacsvox-notmuch--submit-show-message
     message
     (emacsvox-notmuch--landed-body-line)
     facts 'state-change 'open-object)))

(defun emacsvox--advice-emacsvox-speak-visual-line-notmuch-around
    (original &rest arguments)
  "Delegate Notmuch visual-line presentation to the atomic core path."
  (apply original arguments))

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
 '(notmuch-search-first-thread
   notmuch-search-last-thread)
 #'emacsvox-notmuch--navigation-feedback)

(defun emacsvox-notmuch--current-search-thread-id ()
  "Return the thread ID of the Notmuch search result at point."
  (plist-get (notmuch-search-get-result) :thread))

(defun emacsvox-notmuch--search-boundary-feedback (direction)
  "Announce the Notmuch search boundary reached in DIRECTION."
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-view-facts 'search 'select 'operation-failed)
   'navigation 'warn-user
   (if (eq direction 'forward)
       "End of search results"
     "Beginning of search results")))

(defun emacsvox-notmuch--search-navigation-around
    (target direction original arguments)
  "Provide boundary-aware search navigation feedback for TARGET.
DIRECTION is `forward' or `backward'.  Call ORIGINAL once with
ARGUMENTS, speak a newly selected thread, and announce the search
boundary when the selected thread does not change."
  (if (and
       (eq major-mode 'notmuch-search-mode)
       (ems-interactive-p target))
      (let ((before-thread
             (emacsvox-notmuch--current-search-thread-id))
            (result (apply original arguments)))
        (when (eq major-mode 'notmuch-search-mode)
          (let ((after-thread
                 (emacsvox-notmuch--current-search-thread-id)))
            (if (and after-thread
                     (not (equal before-thread after-thread)))
                (emacsvox-notmuch-speak-search-result)
              (emacsvox-notmuch--search-boundary-feedback direction))))
        result)
    (apply original arguments)))

(defun emacsvox--advice-notmuch-search-next-thread-around
    (original &rest arguments)
  "Provide boundary-aware feedback for `notmuch-search-next-thread'."
  (emacsvox-notmuch--search-navigation-around
   'notmuch-search-next-thread 'forward original arguments))

(defun emacsvox--advice-notmuch-search-previous-thread-around
    (original &rest arguments)
  "Provide boundary-aware feedback for `notmuch-search-previous-thread'."
  (emacsvox-notmuch--search-navigation-around
   'notmuch-search-previous-thread 'backward original arguments))

(push
 '(notmuch-search-next-thread
   :around emacsvox--advice-notmuch-search-next-thread-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-search-previous-thread
   :around emacsvox--advice-notmuch-search-previous-thread-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--show-navigation-feedback ()
  "Select and speak the Notmuch message body reached by navigation."
  (emacsvox-notmuch--move-to-message-body)
  (emacsvox-notmuch--speak-landed-message))

(defun emacsvox-notmuch--end-of-thread-feedback ()
  "Select the current body and announce the end of its thread."
  (emacsvox-notmuch--move-to-message-body)
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-thread-facts 'select 'focus-entered)
   'navigation 'select-object "End of thread"))

(defun emacsvox-notmuch--beginning-of-thread-feedback ()
  "Select the current body and announce the beginning of its thread."
  (emacsvox-notmuch--move-to-message-body)
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-thread-facts 'select 'focus-entered)
   'navigation 'select-object "Beginning of thread"))

(defun emacsvox-notmuch--next-navigation-around
    (target original arguments)
  "Provide state-aware feedback for next-message TARGET.
Call ORIGINAL once with ARGUMENTS.  Speak the newly selected
message, or announce the end of the thread when it does not change."
  (if (and
       (eq major-mode 'notmuch-show-mode)
       (ems-interactive-p target))
      (let ((before-message (emacsvox-notmuch--current-show-message-id))
            (result (apply original arguments)))
        (when (eq major-mode 'notmuch-show-mode)
          (if (equal
               before-message
               (emacsvox-notmuch--current-show-message-id))
              (emacsvox-notmuch--end-of-thread-feedback)
            (emacsvox-notmuch--show-navigation-feedback)))
        result)
    (apply original arguments)))

(defun emacsvox--advice-notmuch-show-next-message-around
    (original &rest arguments)
  "Provide state-aware feedback for `notmuch-show-next-message'."
  (emacsvox-notmuch--next-navigation-around
   'notmuch-show-next-message original arguments))

(defun emacsvox--advice-notmuch-show-next-open-message-around
    (original &rest arguments)
  "Provide state-aware feedback for `notmuch-show-next-open-message'."
  (emacsvox-notmuch--next-navigation-around
   'notmuch-show-next-open-message original arguments))

(defun emacsvox--advice-notmuch-show-next-matching-message-around
    (original &rest arguments)
  "Provide state-aware feedback for `notmuch-show-next-matching-message'."
  (emacsvox-notmuch--next-navigation-around
   'notmuch-show-next-matching-message original arguments))

(push
 '(notmuch-show-next-message
   :around emacsvox--advice-notmuch-show-next-message-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-next-open-message
   :around emacsvox--advice-notmuch-show-next-open-message-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-next-matching-message
   :around emacsvox--advice-notmuch-show-next-matching-message-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--previous-navigation-around
    (target original arguments)
  "Navigate to the previous message for interactive TARGET.
Call ORIGINAL once with ARGUMENTS.  Speak the newly selected
message, or announce the beginning of the thread when it does not change."
  (if (and
       (eq major-mode 'notmuch-show-mode)
       (ems-interactive-p target))
      (let ((before-message (emacsvox-notmuch--current-show-message-id)))
        (notmuch-show-move-to-message-top)
        (let ((result (apply original arguments)))
          (when (eq major-mode 'notmuch-show-mode)
            (if (equal
                 before-message
                 (emacsvox-notmuch--current-show-message-id))
                (emacsvox-notmuch--beginning-of-thread-feedback)
              (emacsvox-notmuch--show-navigation-feedback)))
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
  (emacsvox-notmuch--submit-text-feedback
   (append
    (emacsvox-notmuch-part-facts
     part (if hidden 'hide 'show) 'visibility-changed)
    (list :visibility (if hidden 'folded 'expanded)))
   'state-change
   (if hidden 'close-object 'open-object)
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
         (scan
          (and
           message
           (emacsvox-notmuch--attachment-scan
            (plist-get message :body))))
         (count (and scan (plist-get scan :count)))
         (complete (and scan (plist-get scan :complete)))
         (result (apply original arguments)))
    (when (ems-interactive-p 'notmuch-show-save-attachments)
      (emacsvox-notmuch--submit-text-feedback
       (append
        (if message
            (emacsvox-notmuch-message-facts message)
          '(:role message))
        '(:mail-action-kind save :events (operation-completed)))
       'state-change
       (if (and count (> count 0)) 'save-object 'select-object)
       (cond
        ((and count (> count 0)) "Finished saving attachments")
        (complete "No attachments to save")
        (t "Finished saving attachments; attachment scan incomplete"))))
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
            (emacsvox-notmuch--submit-text-feedback
             (emacsvox-notmuch-thread-facts 'select 'focus-entered)
             'navigation 'select-object "End of thread"))
           (t
            (emacsvox-notmuch--submit-content
             (emacsvox-notmuch--bounded-source-range
              (window-start (selected-window))
              (window-end (selected-window) 'update)
              "visible page"
              emacsvox-notmuch-automatic-total-character-limit
              emacsvox-notmuch-automatic-total-byte-limit)
             '(:role message-part :message-part-kind page
               :mail-action-kind scroll :events (focus-entered))
             'navigation
             (emacsvox-notmuch--leading-compatibility-actions
              'scroll)))))))
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
        (emacsvox-notmuch--archive-state-around
         'notmuch-show-advance-and-archive
         'thread original arguments t nil)
      (emacsvox-notmuch--show-reading-around
       'notmuch-show-advance-and-archive original arguments))))

(push
 '(notmuch-show-advance-and-archive
   :around emacsvox--advice-notmuch-show-advance-and-archive-around)
 emacsvox-notmuch--advice)

(defun emacsvox-notmuch--show-visibility-feedback ()
  "Indicate whether the current Notmuch message body is visible."
  (let* ((message (notmuch-show-get-message-properties))
         (visible (plist-get message :message-visible))
         (facts
          (append
           (emacsvox-notmuch-message-facts message 'visibility-changed)
           (list
            :mail-action-kind (if visible 'show 'hide)
            :visibility (if visible 'expanded 'folded)))))
    (if visible
        (emacsvox-notmuch--submit-show-message
         message nil facts 'state-change 'open-object)
      (emacsvox-notmuch--submit-text-feedback
       facts 'state-change 'close-object nil))))

(emacsvox-notmuch--register-after-group
 '(notmuch-show-toggle-message)
 #'emacsvox-notmuch--show-visibility-feedback)

(defun emacsvox-notmuch--show-thread-visibility-state ()
  "Return the current Show thread's total and visible message counts."
  (let ((count 0)
        (visible 0))
    (notmuch-show-mapc
     (lambda ()
       (cl-incf count)
       (when
           (plist-get
            (notmuch-show-get-message-properties) :message-visible)
         (cl-incf visible))))
    (list :count count :visible visible)))

(defun emacsvox-notmuch--show-all-visibility-feedback (open-p)
  "Report whether all Show messages reached requested visibility OPEN-P."
  (let* ((state (emacsvox-notmuch--show-thread-visibility-state))
         (count (plist-get state :count))
         (visible (plist-get state :visible))
         (expected-visible (if open-p count 0))
         (complete (and (> count 0) (= visible expected-visible))))
    (if complete
        (emacsvox-notmuch--submit-text-feedback
         (append
          (emacsvox-notmuch-thread-facts
           (if open-p 'show 'hide) nil)
          (list :visibility (if open-p 'expanded 'folded)))
         'state-change
         (if open-p 'open-object 'close-object)
         (format
          "%s all %d %s"
          (if open-p "Opened" "Closed")
          count
          (if (= count 1) "message" "messages")))
      (emacsvox-notmuch--submit-text-feedback
       (emacsvox-notmuch-thread-facts
        (if open-p 'show 'hide) 'operation-failed)
       'state-change 'warn-user
       (if (zerop count)
           "No messages in thread"
         (format
          "Message visibility incomplete: %d of %d messages open"
          visible count))))))

(defun emacsvox--advice-notmuch-show-open-or-close-all-after (&rest _)
  "Report thread-scoped visibility after opening or closing all messages."
  (when (ems-interactive-p 'notmuch-show-open-or-close-all)
    (emacsvox-notmuch--show-all-visibility-feedback
     (not current-prefix-arg))))

(push
 '(notmuch-show-open-or-close-all
   :after emacsvox--advice-notmuch-show-open-or-close-all-after)
 emacsvox-notmuch--advice)

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
         (format
          "Added %s"
          (string-join
           (mapcar
            (lambda (tag)
              (emacsvox-notmuch--prepare-field-text tag "tag"))
            (nreverse added))
           ", ")))
       (when removed
         (format
          "Removed %s"
          (string-join
           (mapcar
            (lambda (tag)
              (emacsvox-notmuch--prepare-field-text tag "tag"))
            (nreverse removed))
           ", ")))
       (when changed
         (format
          "Changed %s"
          (string-join
           (mapcar
            (lambda (tag)
              (emacsvox-notmuch--prepare-field-text tag "tag"))
            (nreverse changed))
           ", ")))))
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
    (tag-changes status-icons item &optional show-message-p)
  "Submit TAG-CHANGES and updated Notmuch ITEM as one transaction.

STATUS-ICONS keeps represented statuses nonverbal.  When SHOW-MESSAGE-P is
non-nil, ITEM is a Show message with attachment state; otherwise it is a
search result."
  (when tag-changes
    (let* ((ordinary
            (emacsvox-notmuch--ordinary-tag-changes
             tag-changes status-icons))
           (change-summary
            (and ordinary
                 (emacsvox-notmuch--tag-change-summary ordinary)))
           (item-summary
            (and item
                 (if show-message-p
                     (emacsvox-notmuch-format-show-message item)
                   (emacsvox-notmuch-format-search-result item))))
           (content
            (string-join
             (delq nil (list change-summary item-summary))
             "\n"))
           (facts
            (append
             (if item
                 (emacsvox-notmuch-message-facts
                  item 'message-marked)
               '(:role message :events (message-marked)))
             '(:mail-action-kind tag)))
           (actions
            (append
             (when ordinary
               (list
                (emacsvox-aural-compatibility-icon 'task-done)))
             (when
                 (emacsvox-notmuch--removed-status-p
                  tag-changes status-icons)
               (list
                (emacsvox-aural-compatibility-icon
                 'deselect-object)))
             (and
              item
              (emacsvox-notmuch--status-compatibility-actions
               item status-icons 'state-change show-message-p)))))
      (emacsvox-notmuch--submit-content
       content facts 'state-change actions))))

(defun emacsvox-notmuch--tag-feedback (tag-changes)
  "Confirm TAG-CHANGES and speak the updated Notmuch result."
  (emacsvox-notmuch--tag-operation-feedback
   tag-changes
   emacsvox-notmuch-search-status-icons
   (notmuch-search-get-result)))

(defun emacsvox-notmuch--show-tag-feedback (tag-changes)
  "Confirm TAG-CHANGES and speak the updated Notmuch message."
  (emacsvox-notmuch--tag-operation-feedback
   tag-changes
   emacsvox-notmuch-show-status-icons
   (and
    (eq major-mode 'notmuch-show-mode)
    (notmuch-show-get-message-properties))
   t))

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

(defun emacsvox-notmuch--search-tag-bounds (target arguments)
  "Return the Search bounds targeted by TARGET with ARGUMENTS."
  (if (eq target 'notmuch-search-tag-all)
      (cons (point-min) (point-max))
    (let ((beginning (nth 1 arguments))
          (end (nth 2 arguments)))
      (if (and beginning end)
          (cons beginning end)
        (pcase-let ((`(,region-beginning ,region-end)
                      (notmuch-interactive-region)))
          (cons region-beginning region-end))))))

(defun emacsvox-notmuch--search-tag-snapshot-entry (position)
  "Capture the Search result at POSITION for tag-state comparison."
  (when-let* ((result (notmuch-search-get-result position)))
    (list
     :id (plist-get result :thread)
     :tags (copy-sequence (plist-get result :tags)))))

(defun emacsvox-notmuch--show-tag-snapshot-entry ()
  "Capture the current Show message for tag-state comparison."
  (save-excursion
    (notmuch-show-move-to-message-top)
    (when-let* ((message (notmuch-show-get-message-properties)))
      (list
       :id (plist-get message :id)
       :tags (copy-sequence (plist-get message :tags))))))

(defun emacsvox-notmuch--capture-tag-snapshot
    (target arguments &optional all-show-messages)
  "Capture the items whose tags TARGET will change using ARGUMENTS.
When ALL-SHOW-MESSAGES is non-nil, capture every message in a Show buffer."
  (pcase major-mode
    ('notmuch-search-mode
     (pcase-let ((`(,beginning . ,end)
                   (emacsvox-notmuch--search-tag-bounds target arguments))
                  (entries nil))
       (notmuch-search-foreach-result beginning end
         (lambda (position)
           (when-let* ((entry
                        (emacsvox-notmuch--search-tag-snapshot-entry
                         position)))
             (push entry entries))))
       (setq entries (nreverse entries))
       (list
        :buffer (current-buffer)
        :kind 'search
        :identifiable
        (cl-every (lambda (entry) (plist-get entry :id)) entries)
        :entries entries)))
    ('notmuch-show-mode
     (let (entries)
       (if (or all-show-messages
               (eq target 'notmuch-show-tag-all))
           (notmuch-show-mapc
            (lambda ()
              (when-let* ((entry
                           (emacsvox-notmuch--show-tag-snapshot-entry)))
                (push entry entries))))
         (when-let* ((entry (emacsvox-notmuch--show-tag-snapshot-entry)))
           (push entry entries)))
       (setq entries (nreverse entries))
       (list
        :buffer (current-buffer)
        :kind 'show
        :identifiable
        (cl-every (lambda (entry) (plist-get entry :id)) entries)
        :entries entries)))))

(defun emacsvox-notmuch--current-tag-state (snapshot)
  "Return an ID-to-tags table for the buffer in SNAPSHOT."
  (when-let* ((buffer (plist-get snapshot :buffer))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (let ((state (make-hash-table :test #'equal)))
        (pcase (plist-get snapshot :kind)
          ('search
           (notmuch-search-foreach-result (point-min) (point-max)
             (lambda (position)
               (when-let* ((result (notmuch-search-get-result position))
                           (id (plist-get result :thread)))
                 (puthash
                  id (copy-sequence (plist-get result :tags)) state)))))
          ('show
           (notmuch-show-mapc
            (lambda ()
              (when-let* ((message (notmuch-show-get-message-properties))
                          (id (plist-get message :id)))
                (puthash
                 id (copy-sequence (plist-get message :tags)) state))))))
        state))))

(defun emacsvox-notmuch--tag-snapshot-result (snapshot)
  "Return authoritative tag differences and availability for SNAPSHOT."
  (let ((state
         (and
          (plist-get snapshot :identifiable)
          (emacsvox-notmuch--current-tag-state snapshot)))
        (missing (make-symbol "missing-tag-target"))
        (available t)
        changes)
    (if (not state)
        (setq available nil)
      (dolist (entry (plist-get snapshot :entries))
        (let ((current (gethash (plist-get entry :id) state missing)))
          (if (eq current missing)
              (setq available nil)
            (setq changes
                  (append
                   changes
                   (emacsvox-notmuch--tag-differences
                    (plist-get entry :tags) current)))))))
    (list :available available :changes (delete-dups changes))))

(defun emacsvox-notmuch--tag-unchanged-feedback ()
  "Report that an interactive Notmuch tag command changed no tags."
  (emacsvox-notmuch--submit-text-feedback
   '(:role message :mail-action-kind tag)
   'state-change nil "Tags unchanged"))

(defun emacsvox-notmuch--direct-tag-state-around
    (target original arguments)
  "Report actual tag changes made by direct TARGET.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (if (not (eq ems--interactive-fn-name target))
      (apply original arguments)
    (let ((mode major-mode)
          (snapshot (emacsvox-notmuch--capture-tag-snapshot target arguments)))
      (let ((result (apply original arguments)))
        (when (ems-interactive-p target)
          (when snapshot
            (let* ((outcome
                    (emacsvox-notmuch--tag-snapshot-result snapshot))
                   (changes (plist-get outcome :changes)))
              (when (plist-get outcome :available)
                (if changes
                    (pcase mode
                      ('notmuch-search-mode
                       (emacsvox-notmuch--tag-feedback changes))
                      ('notmuch-show-mode
                       (emacsvox-notmuch--show-tag-feedback changes)))
                  (emacsvox-notmuch--tag-unchanged-feedback))))))
        result))))

(defun emacsvox-notmuch--register-direct-tag-group (targets)
  "Register actual-state tag feedback around direct TARGETS."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-around" target))))
      (eval
       `(defun ,advice-function (original &rest arguments)
          ,(format "Report actual tag changes made by `%s'." target)
          (emacsvox-notmuch--direct-tag-state-around
           ',target original arguments)))
      (push (list target :around advice-function) emacsvox-notmuch--advice))))

(emacsvox-notmuch--register-direct-tag-group
 '(notmuch-search-tag
   notmuch-search-add-tag
   notmuch-search-remove-tag
   notmuch-search-tag-all))

(emacsvox-notmuch--register-direct-tag-group
 '(notmuch-show-tag
   notmuch-show-add-tag
   notmuch-show-remove-tag
   notmuch-show-tag-all))

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

(defvar emacsvox-notmuch--archive-context nil
  "Dynamically bound state for one user-owned archive operation.")

(defun emacsvox-notmuch--archive-location ()
  "Return the current Notmuch location for movement comparison."
  (let ((mode major-mode))
    (list
     :buffer (current-buffer)
     :mode mode
     :id
     (ignore-errors
       (pcase mode
         ('notmuch-show-mode
          (plist-get (notmuch-show-get-message-properties) :id))
         ('notmuch-search-mode
          (plist-get (notmuch-search-get-result) :thread))))
     :point (point))))

(defun emacsvox-notmuch--archive-location-changed-p (before after)
  "Return non-nil when archive locations BEFORE and AFTER differ."
  (or
   (not (eq (plist-get before :buffer) (plist-get after :buffer)))
   (not (eq (plist-get before :mode) (plist-get after :mode)))
   (let ((before-id (plist-get before :id))
         (after-id (plist-get after :id)))
     (if (or before-id after-id)
         (not (equal before-id after-id))
       (/= (plist-get before :point) (plist-get after :point))))))

(defun emacsvox-notmuch--record-archive-snapshot (snapshot)
  "Record the actual result of SNAPSHOT in the active archive context."
  (when (and emacsvox-notmuch--archive-context snapshot)
    (let ((outcome (emacsvox-notmuch--tag-snapshot-result snapshot)))
      (setf (alist-get 'observed emacsvox-notmuch--archive-context) t)
      (unless (plist-get outcome :available)
        (setf (alist-get 'complete emacsvox-notmuch--archive-context) nil))
      (when (plist-get outcome :changes)
        (setf (alist-get 'changed emacsvox-notmuch--archive-context) t)))))

(defun emacsvox-notmuch--archive-outcome (context)
  "Return the truthful archive outcome represented by CONTEXT."
  (cond
   ((not (alist-get 'configured context)) 'not-configured)
   ((alist-get 'changed context) 'changed)
   ((and (alist-get 'observed context)
         (alist-get 'complete context))
    'unchanged)))

(defun emacsvox-notmuch--archive-feedback
    (object unarchive outcome moved)
  "Report OUTCOME for archiving OBJECT and any destination MOVED to.
When UNARCHIVE is non-nil, report the reverse operation."
  (let* ((show-message-p (eq major-mode 'notmuch-show-mode))
         (item
          (and
           (or (eq outcome 'changed) moved)
           (pcase major-mode
             ('notmuch-show-mode
              (notmuch-show-get-message-properties))
             ('notmuch-search-mode
              (notmuch-search-get-result)))))
         (confirmation
          (pcase outcome
            ('changed
             (format
              "%s %s"
              (if unarchive "Unarchived" "Archived")
              (symbol-name object)))
            ('unchanged "Archive tags unchanged")
            ('not-configured "Archive tags are not configured")))
         (item-summary
          (and
           item
           (if show-message-p
               (emacsvox-notmuch-format-show-message item)
             (emacsvox-notmuch-format-search-result item))))
         (destination-summary
          (or
           item-summary
           (and moved
                (if (eq major-mode 'notmuch-search-mode)
                    "End of search results"
                  (emacsvox-notmuch--view-summary)))))
         (facts
          (append
           (if (eq object 'thread)
               '(:role message-thread)
             '(:role message))
           '(:mail-action-kind archive)
           (and (eq outcome 'changed)
                '(:events (operation-completed)))))
         (actions
          (append
           (and
            (eq outcome 'changed)
            (emacsvox-notmuch--leading-compatibility-actions
             (if unarchive 'open-object 'close-object)))
           (and
            item
            (emacsvox-notmuch--status-compatibility-actions
             item
             (if show-message-p
                 emacsvox-notmuch-show-status-icons
               emacsvox-notmuch-search-status-icons)
             'state-change
             show-message-p)))))
    (when (or confirmation destination-summary)
      (emacsvox-notmuch--submit-content
       (string-join
        (delq nil (list confirmation destination-summary))
        "\n")
       facts 'state-change actions))))

(defun emacsvox-notmuch--archive-state-around
    (target object original arguments all-show-messages observe-state)
  "Report the actual archive state change made by TARGET on OBJECT.
Call ORIGINAL once with ARGUMENTS.  ALL-SHOW-MESSAGES means OBJECT spans the
whole Show buffer.  When OBSERVE-STATE is non-nil, compare the targeted tags.
Nested archive commands contribute state to the outer interactive owner
instead of producing their own feedback."
  (let* ((owner
          (and
           (null emacsvox-notmuch--archive-context)
           (eq ems--interactive-fn-name target)))
         (context
          (or
           emacsvox-notmuch--archive-context
           (and
            owner
            (list
             (cons 'configured (and notmuch-archive-tags t))
             (cons 'observed nil)
             (cons 'complete t)
             (cons 'changed nil))))))
    (if (not context)
        (apply original arguments)
      (let* ((configured (alist-get 'configured context))
             (snapshot
              (and
               configured observe-state
               (emacsvox-notmuch--capture-tag-snapshot
                target arguments all-show-messages)))
             (before-location
              (and owner (emacsvox-notmuch--archive-location)))
             (emacsvox-notmuch--archive-context context)
             (result (apply original arguments)))
        (when
            (and
             configured snapshot
             (or
              (not owner)
              (not (alist-get 'observed context))))
          (emacsvox-notmuch--record-archive-snapshot snapshot))
        (when (and owner (ems-interactive-p target))
          (emacsvox-notmuch--archive-feedback
           object (car arguments)
           (emacsvox-notmuch--archive-outcome context)
           (emacsvox-notmuch--archive-location-changed-p
            before-location (emacsvox-notmuch--archive-location))))
        result))))

(defun emacsvox-notmuch--register-show-archive-group
    (targets object observe-state)
  "Register archive feedback for TARGETS operating on OBJECT.
When OBSERVE-STATE is non-nil, each target directly changes tags."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-around" target))))
      (eval
       `(defun ,advice-function (original &rest arguments)
          ,(format "Report actual archive state around `%s'." target)
          (emacsvox-notmuch--archive-state-around
           ',target ',object original arguments ,(eq object 'thread)
           ,observe-state)))
      (push (list target :around advice-function) emacsvox-notmuch--advice))))

(emacsvox-notmuch--register-show-archive-group
 '(notmuch-show-archive-message)
 'message t)

(emacsvox-notmuch--register-show-archive-group
 '(notmuch-show-archive-message-then-next-or-exit
   notmuch-show-archive-message-then-next-or-next-thread)
 'message nil)

(emacsvox-notmuch--register-show-archive-group
 '(notmuch-show-archive-thread)
 'thread t)

(emacsvox-notmuch--register-show-archive-group
 '(notmuch-show-archive-thread-then-next
   notmuch-show-archive-thread-then-exit)
 'thread nil)

(defun emacsvox--advice-notmuch-search-archive-thread-around
    (original &rest arguments)
  "Report actual Search archive state around ORIGINAL with ARGUMENTS."
  (emacsvox-notmuch--archive-state-around
   'notmuch-search-archive-thread 'thread original arguments nil t))

(push
 '(notmuch-search-archive-thread
   :around emacsvox--advice-notmuch-search-archive-thread-around)
 emacsvox-notmuch--advice)

(defconst emacsvox-notmuch--search-process-property
  'emacsvox-notmuch-search-completion
  "Process property holding user-owned search completion state.")

(defconst emacsvox-notmuch--search-sentinel-finished-property
  'emacsvox-notmuch-search-sentinel-finished
  "Process property recording that Notmuch finished its search sentinel.")

(defvar-local emacsvox-notmuch--tracked-search-process nil
  "User-owned Notmuch process currently tracked in this search buffer.")

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

(defun emacsvox-notmuch--search-request-kind ()
  "Return the completion kind for the current user-owned search request.
Return nil for programmatic searches and the deliberately silent global
refresh command."
  (let ((owner ems--interactive-fn-name))
    (cond
     ((or
       (null owner)
       (eq owner 'notmuch-refresh-all-buffers)
       (eq this-command 'notmuch-refresh-all-buffers))
      nil)
     ((memq
       owner
       '(notmuch-search-refresh-view
         notmuch-refresh-this-buffer
         notmuch-poll-and-refresh-this-buffer))
      'refresh)
     (t 'search))))

(defun emacsvox-notmuch--search-buffer-focused-p (buffer)
  "Return non-nil when BUFFER is displayed in the selected window."
  (and
   (buffer-live-p buffer)
   (window-live-p (selected-window))
   (eq buffer (window-buffer (selected-window)))))

(defun emacsvox-notmuch--search-summary (kind count)
  "Return a generic completed-search summary for KIND with COUNT results."
  (format
   "%s, %d %s"
   (if (eq kind 'refresh) "Search refreshed" "Search complete")
   count
   (if (= count 1) "thread" "threads")))

(defun emacsvox-notmuch--search-completion-facts (kind event)
  "Return completion facts for search KIND and EVENT."
  (emacsvox-notmuch-view-facts
   'search (if (eq kind 'refresh) 'refresh 'search) event))

(defun emacsvox-notmuch--notify-search-feedback (facts icon &optional text)
  "Send generic Notmuch search feedback through the notification stream.
FACTS describe the event, ICON is its leading cue, and TEXT is optional."
  (emacsvox-aural-call-with-submission
   (lambda ()
     (when icon (tts-notify-icon icon))
     (when text (tts-notify text)))
   :facts facts :module 'notmuch :occasion 'notification))

(defun emacsvox-notmuch--announce-search-start ()
  "Signal that a user-owned non-refresh Notmuch search has started."
  (emacsvox-notmuch--submit-text-feedback
   (emacsvox-notmuch-view-facts 'search 'search nil)
   'state-change 'progress nil))

(defun emacsvox-notmuch--announce-foreground-search-complete
    (buffer count)
  "Present completed focused search BUFFER with final result COUNT."
  (with-current-buffer buffer
    (let* ((summary (emacsvox-notmuch--search-summary 'search count))
           (result (notmuch-search-get-result))
           (view-facts
            (emacsvox-notmuch--search-completion-facts
             'search 'mail-view-opened)))
      (if result
          (let* ((summary-content (concat summary "\n"))
                 (result-content
                  (emacsvox-notmuch-format-search-result result))
                 (shared-facts
                  (cl-loop
                   for (key value) on view-facts by #'cddr
                   unless (memq key '(:role :mail-view-kind))
                   append (list key value))))
            (add-text-properties
             0 (length summary-content)
             (list
              emacsvox-aural-object-property 'search-summary
              emacsvox-aural-facts-property view-facts)
             summary-content)
            (add-text-properties
             0 (length result-content)
             (list emacsvox-aural-object-property 'search-result)
             result-content)
            (emacsvox-notmuch--submit-content
             (concat summary-content result-content)
             shared-facts 'state-change
             (append
              (emacsvox-notmuch--leading-compatibility-actions 'task-done)
              (emacsvox-notmuch--status-compatibility-actions
               result emacsvox-notmuch-search-status-icons 'state-change))))
        (emacsvox-notmuch--submit-text-feedback
         view-facts 'state-change 'task-done summary)))))

(defun emacsvox-notmuch--announce-search-complete (state buffer)
  "Announce a successful completed search described by STATE in BUFFER."
  (let* ((kind (plist-get state :kind))
         (count (emacsvox-notmuch--search-result-count buffer))
         (summary (emacsvox-notmuch--search-summary kind count))
         (focused (emacsvox-notmuch--search-buffer-focused-p buffer))
         (interacted (plist-get state :interacted))
         (facts
          (emacsvox-notmuch--search-completion-facts
           kind 'refresh-completed)))
    (pcase emacsvox-notmuch-search-completion-style
      ('silent nil)
      ('cue
       (emacsvox-notmuch--notify-search-feedback facts 'task-done))
      ('summary
       (emacsvox-notmuch--notify-search-feedback
        facts 'task-done summary))
      ('adaptive
       (if (and
            (eq kind 'search)
            focused
            (not interacted)
            (not (input-pending-p)))
           (emacsvox-notmuch--announce-foreground-search-complete
            buffer count)
         (emacsvox-notmuch--notify-search-feedback
          facts 'task-done summary)))
      (_
       (emacsvox-notmuch--notify-search-feedback
        facts 'task-done summary)))))

(defun emacsvox-notmuch--note-search-interaction ()
  "Record a command issued while this Notmuch search is still running."
  (if-let* ((process emacsvox-notmuch--tracked-search-process)
            (state
             (process-get process emacsvox-notmuch--search-process-property)))
      (process-put
       process emacsvox-notmuch--search-process-property
       (plist-put (copy-sequence state) :interacted t))
    (setq emacsvox-notmuch--tracked-search-process nil)
    (remove-hook
     'pre-command-hook #'emacsvox-notmuch--note-search-interaction t)))

(defun emacsvox-notmuch--clear-tracked-search (process buffer)
  "Stop tracking completed search PROCESS in BUFFER when it still owns it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (eq emacsvox-notmuch--tracked-search-process process)
        (setq emacsvox-notmuch--tracked-search-process nil)
        (remove-hook
         'pre-command-hook #'emacsvox-notmuch--note-search-interaction t)))))

(defun emacsvox-notmuch--finish-search-process (process)
  "Deliver one terminal presentation for tracked Notmuch search PROCESS."
  (when-let* ((state
               (process-get process emacsvox-notmuch--search-process-property)))
    (process-put process emacsvox-notmuch--search-process-property nil)
    (let ((buffer (process-buffer process))
          (status (process-status process)))
      (emacsvox-notmuch--clear-tracked-search process buffer)
      (cond
       ((not (buffer-live-p buffer)) nil)
       ((and
         (eq status 'exit)
         (zerop (process-exit-status process)))
        (emacsvox-notmuch--announce-search-complete state buffer))
       (t
        (emacsvox-notmuch--notify-search-feedback
         (emacsvox-notmuch--search-completion-facts
          (plist-get state :kind) 'refresh-failed)
         'warn-user
         (if (eq (plist-get state :kind) 'refresh)
             "Search refresh failed"
           "Search failed")))))))

(defun emacsvox-notmuch--track-search-process (kind)
  "Track the current buffer's user-owned Notmuch process as KIND."
  (when-let* ((process (get-buffer-process (current-buffer))))
    (let ((state (list :kind kind :interacted nil)))
      (process-put process emacsvox-notmuch--search-process-property state)
      (setq-local emacsvox-notmuch--tracked-search-process process)
      (add-hook
       'pre-command-hook #'emacsvox-notmuch--note-search-interaction nil t)
      ;; A small search can run its sentinel before `notmuch-search' returns.
      (if
          (process-get
           process emacsvox-notmuch--search-sentinel-finished-property)
          (emacsvox-notmuch--finish-search-process process)
        (when (and
               (eq kind 'search)
               (emacsvox-notmuch--search-buffer-focused-p (current-buffer)))
          (emacsvox-notmuch--announce-search-start))))))

(defun emacsvox--advice-notmuch-search-around (original &rest arguments)
  "Track completion of a user-owned call to `notmuch-search'."
  (let ((kind (emacsvox-notmuch--search-request-kind)))
    (prog1 (apply original arguments)
      (when kind
        (emacsvox-notmuch--track-search-process kind)))))

(defun emacsvox--advice-notmuch-search-process-sentinel-after (process _event)
  "Record and announce completion after Notmuch's sentinel for PROCESS."
  (process-put
   process emacsvox-notmuch--search-sentinel-finished-property t)
  (when (memq (process-status process) '(exit signal))
    (emacsvox-notmuch--finish-search-process process)))

(push
 '(notmuch-search
   :around emacsvox--advice-notmuch-search-around)
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
        (advice-add target where function
                    '((name . emacsvox-notmuch)))))))

(dolist (feature
         '(notmuch notmuch-hello notmuch-lib notmuch-search notmuch-show))
  (eval `(with-eval-after-load ',feature
           (emacsvox-notmuch--install-advice))))

(with-eval-after-load 'notmuch
  (define-key
   notmuch-search-mode-map (kbd "<down>") #'notmuch-search-next-thread)
  (define-key
   notmuch-search-mode-map (kbd "<up>") #'notmuch-search-previous-thread)
  (define-key
   notmuch-search-mode-map (kbd "C-c C-p")
   #'emacsvox-notmuch-speak-search-details))

(with-eval-after-load 'notmuch-show
  (define-key
   notmuch-show-mode-map (kbd "C-c C-p")
   #'emacsvox-notmuch-speak-show-position))

(provide 'emacsvox-notmuch)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-notmuch.el ends here
