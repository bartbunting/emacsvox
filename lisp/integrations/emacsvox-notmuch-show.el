;;; emacsvox-notmuch-show.el --- Notmuch message and attachment reading -*- lexical-binding: t; -*-

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

;; Notmuch message and attachment reading.
;; Load through `emacsvox-notmuch'.  The facade owns activation.

;;; Code:

(require 'cl-lib)
(require 'button)

;; Cross-module declarations.
(declare-function emacsvox-notmuch--annotate-field "emacsvox-notmuch" (text field))
(defvar emacsvox-notmuch--automatic-presentation-p)
(defvar ems--voiceify-overlays)
(declare-function emacsvox-notmuch--bounded-source-substring "emacsvox-notmuch" (start end label))
(declare-function emacsvox-notmuch--field-string "emacsvox-notmuch-search" (value face &optional label transform))
(declare-function emacsvox-notmuch--format-tags "emacsvox-notmuch-search" (result status-icons))
(declare-function emacsvox-notmuch--leading-compatibility-actions "emacsvox-notmuch" (icon))
(declare-function emacsvox-notmuch--positive-limit "emacsvox-notmuch" (value))
(declare-function emacsvox-notmuch--prepare-field-text "emacsvox-notmuch" (value label &optional transform))
(declare-function emacsvox-notmuch--status-compatibility-actions "emacsvox-notmuch" (result status-icons occasion &optional include-attachments))
(declare-function emacsvox-notmuch--submit-content "emacsvox-notmuch" (text facts occasion compatibility-actions &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch--submit-text-feedback "emacsvox-notmuch" (facts occasion icon text &optional delivery-policy interruption-policy))
(declare-function emacsvox-notmuch-message-facts "emacsvox-notmuch" (message &optional event))
(defvar emacsvox-notmuch-mime-depth-limit)
(defvar emacsvox-notmuch-mime-node-limit)
(declare-function emacsvox-notmuch-part-facts "emacsvox-notmuch" (part action event))
(defvar emacsvox-notmuch-show-field-separator)
(defvar emacsvox-notmuch-show-message-fields)
(defvar emacsvox-notmuch-show-status-icons)
(declare-function notmuch-sanitize "notmuch-lib" (str))
(declare-function notmuch-show-clean-address "notmuch-show" (address))
(declare-function notmuch-show-get-message-id "notmuch-show" (&optional bare))
(declare-function notmuch-show-get-message-properties "notmuch-show" ())
(declare-function notmuch-show-mapc "notmuch-show" (function))
(declare-function notmuch-show-message-extent "notmuch-show" ())
(declare-function notmuch-show-toggle-message "notmuch-show" ())
;; End cross-module declarations.
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-shr)

(defvar emacsvox-notmuch--table-reading-map
  (let ((map (copy-keymap emacsvox-table-reader-mode-map)))
    ;; Links and MIME controls keep the same actions inside and outside tables.
    (dolist (key '("TAB" "<backtab>" "S-<tab>" "RET"))
      (define-key map (kbd key) nil))
    map)
  "Shared reading keys with native Notmuch link and button actions preserved.")

(defun emacsvox-notmuch--table-submit (text occasion _presentation icon)
  "Read table TEXT as foreground mail content for OCCASION, with ICON."
  (emacsvox-aural-submit
   text :module 'notmuch :occasion occasion
   :facts '(:role message-part :message-part-kind body
            :events (focus-entered))
   :compatibility-actions (list (emacsvox-aural-compatibility-icon icon))))

(setf (alist-get 'notmuch-show-mode emacsvox-table-reader--adapters)
      (list #'emacsvox-shr--table-snapshot #'emacsvox-notmuch--table-submit
            emacsvox-notmuch--table-reading-map))

(defun emacsvox-notmuch--mark-blockquote (renderer dom)
  "Mark the quotation text produced by RENDERER for DOM."
  (let ((start (point)))
    (funcall renderer dom)
    (let ((end (point)))
      (save-excursion
        (goto-char start)
        (skip-chars-forward "\n" end)
        (put-text-property (point) end 'emacsvox-notmuch-quotation t)))))

(defun emacsvox-notmuch--render-html-quotations (original &rest args)
  "Keep blockquote boundaries when ORIGINAL renders an HTML mail part."
  (let* ((renderer (or (cdr (assq 'blockquote shr-external-rendering-functions))
                       #'shr-tag-blockquote))
         (shr-external-rendering-functions
          (if (derived-mode-p 'notmuch-show-mode)
              (cons (cons 'blockquote (apply-partially
                                       #'emacsvox-notmuch--mark-blockquote renderer))
                    shr-external-rendering-functions)
            shr-external-rendering-functions)))
    (apply original args)))

(defun emacsvox-notmuch--quotation-ranges ()
  "Find visible quotation ranges in the narrowed message."
  (let (ranges)
    (goto-char (point-min))
    (while (re-search-forward "^[ \t]*>" nil t)
      (let ((part (get-text-property (1- (point)) :notmuch-part)))
        (when (and (equal (plist-get part :content-type) "text/plain")
                   (not (plist-get part :filename))
                   (not (invisible-p (1- (point)))))
          (push (cons (line-beginning-position) (line-beginning-position 2))
                ranges))))
    ;; Include the button and excerpt together. Its native overlay retains
    ;; the reader's choice of whether the excerpt itself is open.
    (dolist (overlay (overlays-in (point-min) (point-max)))
      (when-let* ((button (overlay-get overlay 'notmuch-wash-button))
                  ((equal (overlay-get overlay 'type) "citation"))
                  (start (button-start button))
                  ((not (plist-get (get-text-property start :notmuch-part) :filename)))
                  ((not (invisible-p start))))
        (goto-char start)
        (push (cons (line-beginning-position) (overlay-end overlay)) ranges)))
    (goto-char (point-min))
    (while-let ((match (text-property-search-forward 'emacsvox-notmuch-quotation t t)))
      (let ((beg (prop-match-beginning match))
            (end (prop-match-end match)))
        (unless (or (invisible-p beg)
                    (plist-get (get-text-property beg :notmuch-part) :filename))
          ;; Notmuch can insert unmarked indentation after SHR fills the part.
          (save-excursion
            (goto-char beg)
            (skip-chars-backward " \t" (line-beginning-position))
            (setq beg (point))
            (goto-char end)
            (skip-chars-backward " \t" (max beg (line-beginning-position)))
            (unless (bolp)
              (skip-chars-forward " \t" (line-end-position))
              (when (eq (char-after) ?\n) (forward-char)))
            (when (< beg (point))
              (push (cons beg (point)) ranges))))))
    (let (merged)
      (dolist (range (sort ranges :key #'car :lessp #'<))
        (if (and merged (<= (car range) (cdar merged)))
            (setcdr (car merged) (max (cdar merged) (cdr range)))
          (push range merged)))
      merged)))

(defun emacsvox-notmuch--fold-range (beg end)
  "Hide the rendered quotation from BEG to END and return its overlay."
  (let ((overlay (make-overlay beg end)))
    (overlay-put overlay 'evaporate t)
    (overlay-put overlay 'invisible t)
    overlay))

(defun emacsvox-notmuch--fold-at-point (range)
  "Leave a readable handle at RANGE and fold its quotation."
  (pcase-let* ((`(,beg . ,end) range)
               (extent (get-text-property beg :notmuch-message-extent))
               (part (get-text-property beg :notmuch-part))
               (label (if (eq (char-before end) ?\n) "[Quoted text]\n" "[Quoted text]"))
               (button (button-at beg)))
    (goto-char beg)
    (with-silent-modifications
      (insert (propertize label :notmuch-message-extent extent :notmuch-part part))
      ;; A native citation button can begin at the same position. Keep its
      ;; mouse and Return actions on its original label.
      (when (and (overlayp button) (= (overlay-start button) beg))
        (move-overlay button (point) (overlay-end button)))
      (let ((fold (emacsvox-notmuch--fold-range (point) (+ end (length label)))))
        (put-text-property beg (point) 'emacsvox-notmuch-quote-handle fold)))
    (goto-char beg)
    "Quotation hidden"))

(defun emacsvox-notmuch--toggle-current-quotation ()
  "Fold or restore the quotation at point in the narrowed message."
  (if-let* ((fold (get-text-property (point) 'emacsvox-notmuch-quote-handle)))
      (let* ((end (overlay-start fold))
             (beg (previous-single-property-change
                   end 'emacsvox-notmuch-quote-handle nil (point-min))))
        (delete-overlay fold)
        (with-silent-modifications (delete-region beg end))
        (goto-char beg)
        "Quotation restored")
    (let* ((position (point))
           (range (seq-find (lambda (r) (and (<= (car r) position) (< position (cdr r))))
                            (save-excursion (emacsvox-notmuch--quotation-ranges)))))
      (if range (emacsvox-notmuch--fold-at-point range) "No quotation here"))))

(defun emacsvox-notmuch--toggle-message-quotations ()
  "Toggle quotations in the narrowed message and return spoken feedback."
  (let* ((folds (seq-filter (lambda (ov) (overlay-get ov 'emacsvox-notmuch-fold))
                            (overlays-in (point-min) (point-max))))
         (ranges (unless folds (save-excursion (emacsvox-notmuch--quotation-ranges)))))
    (cond
     (folds
      (mapc #'delete-overlay folds)
      "Previous quotation view restored")
     (ranges
      (dolist (range ranges)
        (overlay-put (emacsvox-notmuch--fold-range (car range) (cdr range))
                     'emacsvox-notmuch-fold t))
      (when (invisible-p (point))
        (while (and (not (eobp)) (invisible-p (point)))
          (goto-char (next-char-property-change (point))))
        (when (eobp) (goto-char (point-min))))
      "Quoted text hidden")
     (t "No visible quotations"))))

(defun emacsvox-notmuch--quotation-command (action)
  "Apply ACTION to one open message and announce its result."
  (unless (derived-mode-p 'notmuch-show-mode)
    (user-error "Open a Notmuch message first"))
  ;; Line reading captures effective overlay visibility. Mirroring this
  ;; temporary fold to text properties would overwrite native MIME visibility.
  (let ((message (notmuch-show-get-message-properties))
        (ems--voiceify-overlays nil))
    (emacsvox-notmuch--submit-text-feedback
     (emacsvox-notmuch-message-facts message 'operation-completed)
     'state-change nil
     (if (plist-get message :message-visible)
         (save-restriction
           (pcase-let ((`(,beg . ,end) (notmuch-show-message-extent)))
             (narrow-to-region beg end))
           (funcall action))
       "Message is closed"))))

(defun emacsvox-notmuch-toggle-quotation ()
  "Hide the quotation at point, or restore it from its quoted-text label."
  (interactive)
  (emacsvox-notmuch--quotation-command #'emacsvox-notmuch--toggle-current-quotation))

(defun emacsvox-notmuch-toggle-quotations ()
  "Hide visible quotations in this open message or restore its previous view."
  (interactive)
  (emacsvox-notmuch--quotation-command #'emacsvox-notmuch--toggle-message-quotations))

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
    (message body-line facts occasion
             &optional icon delivery-policy interruption-policy)
  "Submit Notmuch MESSAGE and BODY-LINE under FACTS and OCCASION.

ICON is a leading compatibility cue.  Status and attachment cues join the
same transaction instead of creating a nested message presentation.
DELIVERY-POLICY and INTERRUPTION-POLICY, when non-nil, control delivery."
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
           message emacsvox-notmuch-show-status-icons occasion t))
         delivery-policy interruption-policy)
        speech)
    (emacsvox-notmuch--submit-text-feedback
     facts occasion icon nil delivery-policy interruption-policy)))

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

(defun emacsvox-notmuch--part-button-on-row ()
  "Return the sole visible MIME control beside point on a whitespace-only row.
Direct button targets retain their own actions.  Never search another line
or infer a control from MIME metadata covering a rendered body."
  (when (and (eq major-mode 'notmuch-show-mode)
             (not (button-at (point)))
             (not (invisible-p (point))))
    (save-excursion
      (let ((end (line-end-position)))
        (beginning-of-line)
        (skip-chars-forward " \t" end)
        (when-let* ((button (button-at (point)))
                    ((eq (button-type button) 'notmuch-show-part-button-type))
                    ((<= (button-end button) end)))
          (let ((position (button-start button))
                (visible t))
            (while (and visible (< position (button-end button)))
              (when (invisible-p position) (setq visible nil))
              (setq position (next-char-property-change position (button-end button))))
            (goto-char (button-end button))
            (skip-chars-forward " \t" end)
            (when (and visible (= (point) end)) button)))))))

(defun emacsvox-notmuch--activate-part-row-or-toggle-message ()
  "Activate a MIME control from its row, or toggle the current message."
  (interactive)
  (if-let* ((button (emacsvox-notmuch--part-button-on-row)))
      (save-excursion
        (goto-char (button-start button))
        (let ((ems--interactive-fn-name (button-get button 'action)))
          (button-activate button)))
    (call-interactively #'notmuch-show-toggle-message)))

(defun emacsvox--advice-notmuch-show-get-part-properties-around
    (original &rest arguments)
  "Resolve the MIME control beside point before calling ORIGINAL with ARGUMENTS."
  (if-let* ((button (emacsvox-notmuch--part-button-on-row)))
      (save-excursion
        (goto-char (button-start button))
        (apply original arguments))
    (apply original arguments)))

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
    ;; MIME metadata covers the body too, including rendered HTML links.
    (if-let* (((eq (button-type button) 'notmuch-show-part-button-type))
              (part (emacsvox-notmuch--part-at-point button)))
        (emacsvox-notmuch--submit-text-feedback
         (emacsvox-notmuch-part-facts part 'select 'focus-entered)
         'navigation
         (if (plist-get part :filename) 'item 'button)
         (emacsvox-notmuch-format-part part))
      (if (button-get button 'shr-url)
          (emacsvox-notmuch--submit-text-feedback
           '(:role message-part :message-part-kind button
             :mail-action-kind select :events (focus-entered))
           'navigation nil
           (emacsvox-notmuch--bounded-source-substring
            (button-start button) (button-end button) "link label"))
        (emacsvox-notmuch--submit-text-feedback
         '(:role message-part :message-part-kind button
           :mail-action-kind select :events (focus-entered))
         'navigation 'large-movement
         (emacsvox-notmuch--prepare-field-text
          (button-label button) "button label"))))))

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

(provide 'emacsvox-notmuch-show)
;;; emacsvox-notmuch-show.el ends here
