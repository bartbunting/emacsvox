;;; emacsvox-emoji.el --- Conservative emoji speech names -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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

;; Optional speech naming uses exact entries from Emacs's bundled emoji data.
;; Keep the private upstream table behind this adapter; never use the picker
;; helper, which can fall back to naming the first character of a sequence.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar emoji--names)

(defun emacsvox-emoji--lookup (sequence)
  "Return a bundled name and data evidence for SEQUENCE, or a diagnostic.
The text right arrow also accepts the corresponding emoji's bundled name.
Failures are data, never speech errors.  No network or display is involved."
  (condition-case nil
      (if (and (stringp sequence)
               (require 'emoji-labels nil t)
               (boundp 'emoji--names)
               (hash-table-p emoji--names)
               (eq (hash-table-test emoji--names) 'equal))
          (let* ((lookup-sequence
                  (if (and (equal sequence "→")
                           (not (gethash sequence emoji--names)))
                      "➡"
                    sequence))
                 (name (gethash lookup-sequence emoji--names)))
            (if (and (stringp name) (not (string-empty-p name)))
                (list :name (substring-no-properties name)
                      :name-sequence lookup-sequence
                      :emacs-version emacs-version
                      :data-file (symbol-file 'emoji--names 'defvar))
              (list :diagnostic 'missing-name)))
        (list :diagnostic 'unavailable-data))
    (error (list :diagnostic 'unavailable-data))))

(defgroup emacsvox-emoji nil
  "Optional names for occasional emoji in speech."
  :group 'emacsvox)

(defcustom emacsvox-emoji-naming-enabled t
  "Whether speech names occasional emoji, regardless of engine.
This option and the other emoji options can be set buffer-locally or in a
mode hook.  Source buffers keep their original text."
  :type 'boolean :group 'emacsvox-emoji)

(defcustom emacsvox-emoji-approved-sequences t
  "Complete sequences eligible for automatic speech naming.
The default t uses every exact name in Emacs's emoji table, plus custom
names and the text right arrow →.  A list of strings restricts naming to those
complete sequences;
inclusion does not imply that this Emacs version supplies a name."
  :type '(choice (const :tag "All named emoji" t)
                 (repeat :tag "Only these sequences" string))
  :group 'emacsvox-emoji)

(defcustom emacsvox-emoji-maximum-count 2
  "Maximum eligible occurrences per speech object or preview sample.
Above this limit, the entire item retains its emoji."
  :type 'natnum :group 'emacsvox-emoji)

(defcustom emacsvox-emoji-custom-names nil
  "Spoken names overriding Emacs data for eligible complete sequences.
Names must contain 1 to 80 characters with no control characters.  Empty
names are invalid; use an explicit pronunciation to omit a symbol."
  :type '(alist :key-type string :value-type string) :group 'emacsvox-emoji)

(defun emacsvox-emoji--copy-policy-value (value)
  "Copy policy VALUE, including mutable configuration strings."
  (cond ((stringp value) (substring-no-properties value))
        ((consp value) (cons (emacsvox-emoji--copy-policy-value (car value))
                             (emacsvox-emoji--copy-policy-value (cdr value))))
        (t value)))

(defun emacsvox-emoji--snapshot ()
  "Copy the current source's naming policy for one operation."
  (list :enabled emacsvox-emoji-naming-enabled
        :approved (emacsvox-emoji--copy-policy-value emacsvox-emoji-approved-sequences)
        :maximum emacsvox-emoji-maximum-count
        :names (emacsvox-emoji--copy-policy-value emacsvox-emoji-custom-names)))

(defun emacsvox-emoji--valid-name-p (name)
  "Whether NAME is a bounded nonempty spoken expansion."
  (and (stringp name) (<= 1 (length name) 80)
       (not (string-match-p "[[:cntrl:]]" name))
       (not (string-empty-p (string-trim name)))))

(defun emacsvox-emoji--valid-policy-p (policy)
  "Whether POLICY is safe to use without unbounded expansion."
  (let ((approved (plist-get policy :approved)) (names (plist-get policy :names))
        (maximum (plist-get policy :maximum)))
    (and (integerp maximum) (<= 0 maximum 64)
         (or (eq approved t)
             (and (proper-list-p approved) (<= (length approved) 64)
                  (cl-every (lambda (s) (and (stringp s) (<= 1 (length s) 32))) approved)))
         (proper-list-p names) (<= (length names) 64)
         (cl-every (lambda (entry)
                     (and (consp entry) (stringp (car entry))
                          (<= 1 (length (car entry)) 32)
                          (emacsvox-emoji--valid-name-p (cdr entry)))) names))))

(defun emacsvox-emoji--extension-p (char)
  "Whether CHAR must stay attached to its preceding base."
  (and char
       (or (memq (get-char-code-property char 'general-category) '(Mn Mc Me))
           (<= #xFE00 char #xFE0F) (<= #xE0100 char #xE01EF)
           (<= #x1F3FB char #x1F3FF) (<= #xE0020 char #xE007F))))

(defun emacsvox-emoji--sequence-end (text start)
  "Find a conservative complete sequence in TEXT at START.
Keep unknown joined sequences intact without depending on font composition."
  (let ((end (1+ start)) (length (length text)))
    (when (and (<= #x1F1E6 (aref text start) #x1F1FF)
               (< end length) (<= #x1F1E6 (aref text end) #x1F1FF))
      (cl-incf end))
    (while (and (< end length)
                (or (emacsvox-emoji--extension-p (aref text end))
                    (= (aref text end) #x200D)
                    (= (aref text (1- end)) #x200D)))
      (cl-incf end))
    end))

(defconst emacsvox-emoji--anchor-properties
  '(emacsvox-aural-positioned-facts emacsvox-aural-concrete-positioned-actions)
  "Properties that belong only to the first character of an expansion.")

(defun emacsvox-emoji--ordinary-properties (text position)
  "Copy TEXT properties at POSITION, excluding positioned anchors."
  (let ((properties (copy-sequence (text-properties-at position text))))
    (dolist (property emacsvox-emoji--anchor-properties)
      (cl-remf properties property))
    properties))

(defun emacsvox-emoji--replaceable-p (text start end)
  "Whether a sequence has uniform ownership and no internal positioned cue."
  (and (not (get-text-property start 'emacsvox-emoji-blocked text))
       (not (get-text-property start 'emacsvox-emoji-prepared text))
       (not (get-text-property start 'emacsvox-emoji-pronounced text))
       (let ((properties (emacsvox-emoji--ordinary-properties text start))
             (position (1+ start)) (valid t))
         (while (and valid (< position end))
           (setq valid
                 (and (equal properties (emacsvox-emoji--ordinary-properties text position))
                      (not (cl-some (lambda (p) (get-text-property position p text))
                                    emacsvox-emoji--anchor-properties))))
           (cl-incf position))
         valid)))

(defun emacsvox-emoji--eligible-p (sequence policy)
  "Whether complete SEQUENCE is eligible for naming under POLICY.
The full-table policy requires a bundled name (including the text right arrow)
or custom name, never a general Unicode name or a name for part of a sequence."
  (if (eq (plist-get policy :approved) t)
      (or (assoc sequence (plist-get policy :names))
          (plist-get (emacsvox-emoji--lookup sequence) :name))
    (member sequence (plist-get policy :approved))))

(defun emacsvox-emoji--item-policy (text policy)
  "Freeze the original eligible occurrence limit for TEXT under POLICY."
  (let ((policy (copy-tree policy)) (position 0) (count 0))
    (when (and (plist-get policy :enabled) (emacsvox-emoji--valid-policy-p policy))
      (while (and (< position (length text)) (<= count (plist-get policy :maximum)))
        (let ((end (emacsvox-emoji--sequence-end text position)))
          (when (emacsvox-emoji--eligible-p (substring-no-properties text position end) policy)
            (cl-incf count))
          (setq position end)))
      (setq policy (plist-put policy :count-exceeded (> count (plist-get policy :maximum)))))
    policy))

(defun emacsvox-emoji--prepare (text policy)
  "Prepare one original TEXT item under explicit frozen POLICY.
Return :text, bounded :replacements and :diagnostics.  Replacement evidence
contains zero-based source and output boundaries.  Never modify TEXT or POLICY.
Unknown sequences and mixed-property candidates remain intact."
  (cond
   ((not (plist-get policy :enabled)) (list :text text))
   ((not (emacsvox-emoji--valid-policy-p policy))
    (list :text text :diagnostics '(invalid-policy)))
   ((plist-get policy :count-exceeded) (list :text text :diagnostics '(count-exceeded)))
   (t
    (let ((position 0) (count 0) candidates diagnostics)
      ;; Missing individual names are ordinary text in full-table mode.
      ;; Still report a broken table once, even with no eligible candidates.
      (when (and (eq (plist-get policy :approved) t)
                 (eq (plist-get (emacsvox-emoji--lookup "") :diagnostic) 'unavailable-data))
        (push 'unavailable-data diagnostics))
      (while (< position (length text))
        (let* ((end (emacsvox-emoji--sequence-end text position))
               (sequence (substring-no-properties text position end)))
          (when (and (emacsvox-emoji--eligible-p sequence policy)
                     (not (get-text-property position 'emacsvox-emoji-pronounced text))
                     (not (get-text-property position 'emacsvox-emoji-prepared text)))
            (cl-incf count)
            ;; Never retain more candidates than can be expanded.
            (when (<= count (plist-get policy :maximum))
              (if (emacsvox-emoji--replaceable-p text position end)
                  (push (list position end sequence) candidates)
                (cl-pushnew 'property-boundary diagnostics))))
          (setq position end)))
      (if (> count (plist-get policy :maximum))
          (list :text text :diagnostics '(count-exceeded))
        (let ((source 0) (output 0) pieces replacements)
          (dolist (candidate (nreverse candidates))
            (pcase-let* ((`(,start ,end ,sequence) candidate)
                         (custom (assoc sequence (plist-get policy :names)))
                         (data (if custom (list :name (cdr custom) :source 'custom)
                                 (emacsvox-emoji--lookup sequence)))
                         (name (plist-get data :name)))
              (if (not (emacsvox-emoji--valid-name-p name))
                  (cl-pushnew (or (plist-get data :diagnostic) 'invalid-name) diagnostics)
                (let* ((before (substring text source start))
                       (prefix (if (and (> start 0)
                                        (not (and (= start source) pieces
                                                  (string-suffix-p " " (car pieces))))
                                        (or (memq (char-syntax (aref text (1- start))) '(?w ?_))
                                            (eq (get-char-code-property (aref text (1- start))
                                                                        'general-category) 'So))) " " ""))
                       (suffix (if (and (< end (length text))
                                        (memq (char-syntax (aref text end)) '(?w ?_))) " " ""))
                       (spoken (concat prefix name suffix)))
                  (set-text-properties 0 (length spoken)
                                       (emacsvox-emoji--ordinary-properties text start) spoken)
                  (put-text-property 0 (length spoken) 'emacsvox-emoji-prepared t spoken)
                  (dolist (property emacsvox-emoji--anchor-properties)
                    (when-let* ((value (get-text-property start property text)))
                      (put-text-property 0 1 property value spoken)))
                  (push before pieces) (cl-incf output (length before))
                  (push (append (list :sequence sequence :name name
                                      :source-start start :source-end end
                                      :output-start output :output-end (+ output (length spoken)))
                                (copy-tree data)) replacements)
                  (push spoken pieces) (cl-incf output (length spoken))
                  (setq source end)))))
          (push (substring text source) pieces)
          (list :text (apply #'concat (nreverse pieces))
                :replacements (nreverse replacements) :diagnostics diagnostics)))))))

(defun emacsvox-emoji--retained-text (text evidence)
  "Mark retained TEXT with its original naming EVIDENCE for voice auditions."
  (if (and evidence (stringp text))
      (propertize (copy-sequence text) 'emacsvox-emoji-retained t
                  'emacsvox-emoji-evidence (copy-tree evidence))
    text))

(defun emacsvox-emoji--explanation (evidence)
  "Describe bounded preparation EVIDENCE without claiming playback."
  (append
   (mapcar (lambda (entry)
             (format "Speech text: %s spoken as %s."
                     (plist-get entry :sequence) (plist-get entry :name)))
           (plist-get evidence :replacements))
   (mapcar (lambda (diagnostic)
             (concat "Emoji naming skipped: "
                     (pcase diagnostic
                       ('count-exceeded "the original item exceeds the occurrence limit")
                       ('property-boundary "a sequence crosses a style or cue boundary")
                       ('invalid-policy "invalid emoji settings")
                       ('missing-name "this Emacs has no exact name")
                       ('invalid-name "the name is empty, too long, or contains controls")
                       (_ "Emacs emoji data is unavailable")) "."))
           (plist-get evidence :diagnostics))))

(provide 'emacsvox-emoji)
;;; emacsvox-emoji.el ends here
