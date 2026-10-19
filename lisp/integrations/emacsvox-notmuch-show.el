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
