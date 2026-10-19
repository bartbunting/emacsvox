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
(declare-function notmuch-search-first-thread "notmuch" ())
(declare-function notmuch-search-last-thread "notmuch" ())
(declare-function notmuch-show-clean-address "notmuch-show" (address))
(declare-function notmuch-show-get-message-id "notmuch-show" (&optional bare))
(declare-function notmuch-show-get-message-properties "notmuch-show" ())
(declare-function notmuch-show-get-part-properties "notmuch-show" ())
(declare-function notmuch-show-next-button "notmuch-show" ())
(declare-function notmuch-show-previous-button "notmuch-show" ())
(declare-function notmuch-show-toggle-message "notmuch-show" ())
(declare-function notmuch-show-mapc "notmuch-show" (function))
(declare-function notmuch-show-message-extent "notmuch-show" ())
(declare-function notmuch-show-move-to-message-top "notmuch-show" ())
(declare-function notmuch-tag-format-tags "notmuch-tag"
                  (tags orig-tags &optional face))
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
speaks the result at point as soon as it is available, while results are
still arriving.  Completion then sends only the final count to the notification
stream.  If no row was announced early, an untouched focused search speaks
its count and selected result together at completion.
After the user issues another command or leaves the search buffer, search
completion contains only a generic result count on the notification stream.
A user-owned refresh queues its generic count on the primary stream even after
leaving its buffer; navigation can interrupt it without competing speech.
`summary' sends only the generic count, `cue' sends only a task-completion cue,
and `silent' suppresses successful completion feedback.  These styles use the
same refresh stream selection.

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
    (text facts occasion compatibility-actions
          &optional delivery-policy interruption-policy)
  "Submit TEXT and COMPATIBILITY-ACTIONS under FACTS and OCCASION.
DELIVERY-POLICY and INTERRUPTION-POLICY, when non-nil, control delivery."
  (let ((text
         (and text
              (emacsvox-notmuch--limit-automatic-presentation text)))
        (arguments
         (append
          (list :facts facts :module 'notmuch :occasion occasion
                :compatibility-actions compatibility-actions)
          (when delivery-policy
            (list :delivery-policy delivery-policy))
          (when interruption-policy
            (list :interruption-policy interruption-policy)))))
    (if (and (stringp text) (not (string-empty-p text)))
        (apply #'emacsvox-aural-submit text arguments)
      (apply #'emacsvox-aural-submit-actions arguments))))

(defun emacsvox-notmuch--submit-text-feedback
    (facts occasion icon text &optional delivery-policy interruption-policy)
  "Submit explicit TEXT with FACTS, OCCASION, and leading ICON.
DELIVERY-POLICY and INTERRUPTION-POLICY, when non-nil, control delivery."
  (emacsvox-notmuch--submit-content
   text facts occasion
   (emacsvox-notmuch--leading-compatibility-actions icon)
   delivery-policy interruption-policy))

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
          (buffer-name) 'personality 'voice-lighten-medium))
        (mode
         (string-trim
          (downcase (format-mode-line mode-name)))))
    (if (string-empty-p mode)
        name
      (concat
       name ", "
       (propertize mode 'personality 'voice-animate)))))

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

(require 'emacsvox-notmuch-search)

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

;;;  Show Messages:

(require 'emacsvox-notmuch-show)

;;;  Interactive Commands:

(defvar emacsvox-notmuch--advice nil
  "Current Notmuch targets and their native advice functions.")
(setq emacsvox-notmuch--advice nil)

(push
 '(notmuch-show-get-part-properties
   :around emacsvox--advice-notmuch-show-get-part-properties-around)
 emacsvox-notmuch--advice)

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
   (emacsvox-notmuch--view-summary)
   'replaceable 'lane))

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

(defun emacsvox-notmuch--prefer-unread-message ()
  "Select the newest open, matching unread message in the current thread.
Keep Notmuch's initial position when no such message exists.  Inspecting
messages does not change their read state."
  (when (eq major-mode 'notmuch-show-mode)
    (let (position timestamp)
      (notmuch-show-mapc
       (lambda ()
         (let* ((message (notmuch-show-get-message-properties))
                (date (or (plist-get message :timestamp) 0)))
           (when (and (plist-get message :match)
                      (plist-get message :message-visible)
                      (member "unread" (plist-get message :tags))
                      (or (null position) (> date timestamp)))
             (setq position (point) timestamp date)))))
      (when position (goto-char position)))))

(defun emacsvox-notmuch--show-feedback ()
  "Prefer unread mail and speak the selected message in a newly opened thread."
  (emacsvox-notmuch--prefer-unread-message)
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
     facts 'state-change 'open-object 'replaceable 'lane)))

(defun emacsvox--advice-emacsvox-speak-line-notmuch-around
    (original &rest arguments)
  "Read the visible Notmuch row when point precedes it in folded text.
Physical line motion can leave point at the start of an invisible quote
whose final newline precedes the next message's sender.  Preserve point
and folding while presenting the visible row through the core path."
  (if (and (eq major-mode 'notmuch-show-mode) (invisible-p (point)))
      (save-excursion
        (let ((origin (point)))
          (while (and (< (point) (point-max)) (invisible-p (point)))
            (goto-char (next-char-property-change (point))))
          (when (eobp) (goto-char origin))
          (apply original arguments)))
    (apply original arguments)))

(push
 '(emacsvox-speak-line
   :around emacsvox--advice-emacsvox-speak-line-notmuch-around)
 emacsvox-notmuch--advice)

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

(defvar emacsvox-notmuch--part-default-feedback-owner nil
  "Non-nil while a part button owns feedback for its nested default action.")

(defun emacsvox-notmuch--part-action-around
    (target action original arguments)
  "Confirm ACTION performed by TARGET on the current MIME part.
Call ORIGINAL once with ARGUMENTS and preserve its result."
  (let ((part
         (or
          (ignore-errors (notmuch-show-get-part-properties))
          (emacsvox-notmuch--part-at-point (button-at (point)))))
        (result (apply original arguments)))
    (when (and part (not emacsvox-notmuch--part-default-feedback-owner)
               (ems-interactive-p target))
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
         (emacsvox-notmuch--part-default-feedback-owner
          (or emacsvox-notmuch--part-default-feedback-owner
              (eq ems--interactive-fn-name 'notmuch-show-part-button-default)))
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

(require 'emacsvox-notmuch-operations)

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

(push
 '(notmuch-tag-jump
   :around emacsvox--advice-notmuch-tag-jump-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-show-mark-read
   :around emacsvox--advice-notmuch-show-mark-read-around)
 emacsvox-notmuch--advice)

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

(push
 '(notmuch-search-archive-thread
   :around emacsvox--advice-notmuch-search-archive-thread-around)
 emacsvox-notmuch--advice)

(require 'emacsvox-notmuch-events)

(push
 '(notmuch-search
   :around emacsvox--advice-notmuch-search-around)
 emacsvox-notmuch--advice)

(push
 '(notmuch-search-process-filter
   :after emacsvox--advice-notmuch-search-process-filter-after)
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
   notmuch-search-mode-map (kbd "M-<") #'notmuch-search-first-thread)
  (define-key
   notmuch-search-mode-map (kbd "M->") #'notmuch-search-last-thread)
  (define-key
   notmuch-search-mode-map (kbd "C-c C-p")
   #'emacsvox-notmuch-speak-search-details))

(with-eval-after-load 'notmuch-show
  (define-key notmuch-show-mode-map [remap notmuch-show-toggle-message]
              #'emacsvox-notmuch--activate-part-row-or-toggle-message)
  ;; SHR's text keymap otherwise overrides only forward Tab navigation.
  (define-key notmuch-show-mode-map [remap shr-next-link]
              #'notmuch-show-next-button)
  (define-key notmuch-show-mode-map [remap shr-previous-link]
              #'notmuch-show-previous-button)
  (define-key notmuch-show-mode-map [remap forward-button]
              #'notmuch-show-next-button)
  (define-key notmuch-show-mode-map [remap backward-button]
              #'notmuch-show-previous-button)
  (define-key
   notmuch-show-mode-map (kbd "C-c C-p")
   #'emacsvox-notmuch-speak-show-position))

(provide 'emacsvox-notmuch)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-notmuch.el ends here
