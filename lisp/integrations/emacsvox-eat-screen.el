;;; emacsvox-eat-screen.el --- EAT screen snapshots and differences  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop eat
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
;; EAT screen snapshots and differences.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

(require 'emacsvox-preamble)
(eval-when-compile (require 'cl-lib))
(defvar eat-terminal)
(defvar emacsvox-eat--generation)
(declare-function eat-term-live-p "eat" (object))
(declare-function eat-term-display-beginning "eat" (terminal))
(declare-function eat-term-end "eat" (terminal))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-in-alternative-display-p "eat" (terminal))
(declare-function eat-term-size "eat" (terminal))
(declare-function eat-term-title "eat" (terminal))
(declare-function eat-term-cursor-type "eat" (terminal))

(defconst emacsvox-eat--maximum-metadata-characters 256
  "Maximum characters retained from one terminal metadata value.")

(defconst emacsvox-eat--face-attributes
  '(:foreground :background :weight :slant :underline :strike-through
    :inverse-video :overline :box)
  "Rendered face attributes retained in terminal style snapshots.")

(defconst emacsvox-eat--style-signature-version 1
  "Version of normalized style signatures stored in EAT snapshots.")

(defconst emacsvox-eat--style-trait-order
  '(bold faint italic underline blink crossed-out inverse-like concealed
    foreground-color background-color alternate-font overline boxed
    mouse-highlight interactive)
  "Stable order of semantic traits in normalized EAT style signatures.")

(defconst emacsvox-eat--prompt-status-faces
  '((eat-shell-prompt-annotation-running . running)
    (eat-shell-prompt-annotation-success . success)
    (eat-shell-prompt-annotation-failure . failure))
  "Public EAT prompt annotation faces and their semantic status.")

(defun emacsvox-eat--normalize-face-value (value)
  "Return a stable, data-only terminal style signature for face VALUE."
  (let (faces attributes)
    (cl-labels
        ((walk
          (item)
          (cond
           ((and (symbolp item) (facep item))
            (unless (eq item 'eat-term-font-0) (push item faces)))
           ((and (stringp item) (facep item))
            (when-let* ((face (intern-soft item))
                        ((not (eq face 'eat-term-font-0))))
              (push face faces)))
           ((and (proper-list-p item) (keywordp (car item)))
            (walk (plist-get item :inherit))
            (dolist (attribute emacsvox-eat--face-attributes)
              (when (plist-member item attribute)
                (setf (alist-get attribute attributes)
                      (copy-tree (plist-get item attribute))))))
           ((proper-list-p item) (mapc #'walk item)))))
      (walk value))
    (setq faces (delete-dups (nreverse faces))
          attributes (nreverse attributes))
    (when (or faces attributes)
      (append
       (when faces (list :faces faces))
       (when attributes (list :attributes attributes))))))

(defun emacsvox-eat--style-traits (face mouse-face interactive-p)
  "Return stable semantic traits for FACE, MOUSE-FACE, and INTERACTIVE-P."
  (let* ((faces (plist-get face :faces))
         (attributes (plist-get face :attributes))
         (foreground-entry (assq :foreground attributes))
         (background-entry (assq :background attributes))
         (foreground (cdr foreground-entry))
         (background (cdr background-entry))
         (default-foreground (face-foreground 'default nil t))
         (default-background (face-background 'default nil t))
         traits)
    (dolist (named-face faces)
      (pcase named-face
        ((or 'bold 'eat-term-bold) (push 'bold traits))
        ('eat-term-faint (push 'faint traits))
        ((or 'italic 'eat-term-italic) (push 'italic traits))
        ((or 'eat-term-slow-blink 'eat-term-fast-blink)
         (push 'blink traits))
        ((and (pred symbolp) name)
         (when (string-match-p
                "\\`eat-term-font-[1-9][0-9]*\\'" (symbol-name name))
           (push 'alternate-font traits)))))
    (pcase (alist-get :weight attributes)
      ((or 'semi-bold 'bold 'extra-bold 'ultra-bold) (push 'bold traits))
      ((or 'ultra-light 'extra-light 'light 'semi-light)
       (push 'faint traits)))
    (when (memq (alist-get :slant attributes)
                '(italic oblique reverse-italic reverse-oblique))
      (push 'italic traits))
    (when-let* ((underline (alist-get :underline attributes))
                ((not (eq underline 'unspecified))))
      (push 'underline traits))
    (when-let* ((crossed (alist-get :strike-through attributes))
                ((not (eq crossed 'unspecified))))
      (push 'crossed-out traits))
    (when (or
           (let ((inverse (alist-get :inverse-video attributes)))
             (and inverse (not (eq inverse 'unspecified))))
           (and foreground-entry background-entry
                (equal foreground default-background)
                (equal background default-foreground)))
      (push 'inverse-like traits))
    (when (and foreground-entry
               (or
                (and background-entry (equal foreground background))
                (and (null background-entry)
                     (equal foreground default-background))))
      (push 'concealed traits))
    (when foreground-entry (push 'foreground-color traits))
    (when background-entry (push 'background-color traits))
    (when-let* ((overline (alist-get :overline attributes))
                ((not (eq overline 'unspecified))))
      (push 'overline traits))
    (when-let* ((box (alist-get :box attributes))
                ((not (eq box 'unspecified))))
      (push 'boxed traits))
    (when mouse-face (push 'mouse-highlight traits))
    (when interactive-p (push 'interactive traits))
    (setq traits (delete-dups traits))
    (seq-filter (lambda (trait) (memq trait traits))
                emacsvox-eat--style-trait-order)))

(defun emacsvox-eat--style-at (position)
  "Return normalized terminal style facts at buffer POSITION."
  (let ((face
         (emacsvox-eat--normalize-face-value
          (list
           (get-char-property position 'face)
           (get-char-property position 'font-lock-face))))
        (mouse-face
         (emacsvox-eat--normalize-face-value
          (get-char-property position 'mouse-face)))
        (interactive-p
         (or
          (get-char-property position 'keymap)
          (get-char-property position 'help-echo))))
    (let ((traits
           (emacsvox-eat--style-traits face mouse-face interactive-p)))
      (when (or face mouse-face interactive-p traits)
        (append
         (when face (list :face face))
         (when mouse-face (list :mouse-face mouse-face))
         (when interactive-p (list :interactive t))
         (when traits (list :traits traits)))))))

(defun emacsvox-eat--style-runs (beginning end)
  "Return non-default style runs between BEGINNING and END.
Run bounds are offsets from BEGINNING."
  (let ((position beginning)
        runs)
    (while (< position end)
      (let* ((next
              (min
               end
               (or (next-char-property-change position end) end)))
             (style (emacsvox-eat--style-at position)))
        (when style
          (push
           (list (- position beginning) (- next beginning) style)
           runs))
        (setq position next)))
    (nreverse runs)))

(defun emacsvox-eat--redact-concealed-text (text styles)
  "Return a same-length copy of TEXT with concealed STYLE cells blanked.
Newlines remain intact so row and cursor offsets continue to describe the
rendered terminal screen."
  (let ((redacted (copy-sequence text))
        (length (length text)))
    (dolist (run styles)
      (when (memq 'concealed (plist-get (caddr run) :traits))
        (let ((position (max 0 (car run)))
              (end (min length (cadr run))))
          (while (< position end)
            (unless (= (aref redacted position) ?\n)
              (aset redacted position ?\s))
            (setq position (1+ position))))))
    redacted))

(defun emacsvox-eat--split-screen-rows (text)
  "Split terminal TEXT into rows while preserving empty rows."
  (let ((start 0)
        rows)
    (while (string-match "\n" text start)
      (push (substring text start (match-beginning 0)) rows)
      (setq start (match-end 0)))
    (push (substring text start) rows)
    (nreverse rows)))

(defun emacsvox-eat--cursor-coordinates (cursor beginning end)
  "Return zero-based cursor coordinates for CURSOR in BEGINNING..END."
  (when (and cursor (<= beginning cursor) (<= cursor end))
    (save-restriction
      (narrow-to-region beginning end)
      (save-excursion
        (goto-char cursor)
        (cons (1- (line-number-at-pos cursor)) (current-column))))))

(defun emacsvox-eat--sanitize-metadata-value (value)
  "Return a bounded, control-free copy of terminal metadata VALUE."
  (when (stringp value)
    (let* ((length (length value))
           (limit emacsvox-eat--maximum-metadata-characters)
           (truncated-p (> length limit))
           (text
            (substring-no-properties value 0 (min length limit))))
      (setq text
            (string-trim
             (replace-regexp-in-string
              "[[:cntrl:]]+" " " text nil 'literal)))
      (if truncated-p (concat text "…") text))))

(defun emacsvox-eat--prompt-status-in-display (value &optional depth)
  "Return an EAT prompt status represented inside display VALUE.
DEPTH bounds traversal of standard face, string-property, list, and vector
display data.  Only EAT's public prompt annotation faces are recognized."
  (let ((depth (or depth 0)))
    (when (< depth 8)
      (cond
       ((symbolp value)
        (alist-get value emacsvox-eat--prompt-status-faces))
       ((stringp value)
        (let ((position 0)
              (length (length value))
              status)
          (while (and (< position length) (null status))
            (setq status
                  (or
                   (emacsvox-eat--prompt-status-in-display
                    (get-text-property position 'face value) (1+ depth))
                   (emacsvox-eat--prompt-status-in-display
                    (get-text-property position 'font-lock-face value)
                    (1+ depth))
                   (emacsvox-eat--prompt-status-in-display
                    (get-text-property position 'display value) (1+ depth))))
            (setq position
                  (or (next-property-change position value length)
                      length)))
          status))
       ((consp value)
        (or
         (emacsvox-eat--prompt-status-in-display (car value) (1+ depth))
         (emacsvox-eat--prompt-status-in-display (cdr value) (1+ depth))))
       ((vectorp value)
        (seq-some
         (lambda (item)
           (emacsvox-eat--prompt-status-in-display item (1+ depth)))
         value))))))

(defun emacsvox-eat--capture-prompt-status
    (beginning end cursor alternate-screen-p)
  "Return the latest public EAT prompt status in BEGINNING through END.
CURSOR bounds the search to annotations at or before the terminal cursor.
No main-screen prompt annotation is inferred on ALTERNATE-SCREEN-P."
  (unless alternate-screen-p
    (let ((limit (or cursor end))
          best-position
          best-status)
      (dolist (overlay (overlays-in beginning end))
        (when-let* ((position (overlay-start overlay))
                    ((<= beginning position limit))
                    (status
                     (emacsvox-eat--prompt-status-in-display
                      (overlay-get overlay 'before-string))))
          (when (or (null best-position) (>= position best-position))
            (setq best-position position
                  best-status status))))
      best-status)))

(defun emacsvox-eat--capture-screen ()
  "Return a data-only snapshot of the current visible EAT display.
Only public EAT terminal accessors and rendered buffer properties are used."
  (when (and eat-terminal (eat-term-live-p eat-terminal))
    (let* ((beginning
            (marker-position (eat-term-display-beginning eat-terminal)))
           (end (marker-position (eat-term-end eat-terminal)))
           (cursor-marker (eat-term-display-cursor eat-terminal))
           ;; EAT returns an integer when its logical cursor is past the
           ;; right margin, and a marker at other positions.
           (cursor (and cursor-marker (+ 0 cursor-marker)))
           (alternate-screen
            (not (null (eat-term-in-alternative-display-p eat-terminal))))
           (coordinates
            (emacsvox-eat--cursor-coordinates cursor beginning end))
           (size (eat-term-size eat-terminal))
           (title (eat-term-title eat-terminal))
           (styles (emacsvox-eat--style-runs beginning end))
           (text
            (emacsvox-eat--redact-concealed-text
             (buffer-substring-no-properties beginning end) styles))
           (prompt-status
            (emacsvox-eat--capture-prompt-status
             beginning end cursor alternate-screen)))
      (list
       :generation emacsvox-eat--generation
       :style-version emacsvox-eat--style-signature-version
       :display-beginning beginning
       :display-end end
       :text text
       :rows (emacsvox-eat--split-screen-rows text)
       :styles styles
       :cursor-offset (and cursor (- cursor beginning))
       :cursor-row (car coordinates)
       :cursor-column (cdr coordinates)
       :cursor-type (eat-term-cursor-type eat-terminal)
       :size (cons (car size) (cdr size))
       :alternate-screen alternate-screen
       :prompt-status prompt-status
       :title (emacsvox-eat--sanitize-metadata-value title)
       :cwd (emacsvox-eat--sanitize-metadata-value default-directory)))))

(defun emacsvox-eat--sequence-change (old new)
  "Return the smallest changed span between OLD and NEW sequences.
The returned start and end offsets are zero-based and end-exclusive."
  (let* ((old-sequence (if (listp old) (vconcat old) old))
         (new-sequence (if (listp new) (vconcat new) new))
         (old-length (length old-sequence))
         (new-length (length new-sequence))
         (shared-length (min old-length new-length))
         (start 0)
         (suffix 0))
    (while (and (< start shared-length)
                (equal (aref old-sequence start)
                       (aref new-sequence start)))
      (setq start (1+ start)))
    (while (and (< suffix (- old-length start))
                (< suffix (- new-length start))
                (equal (aref old-sequence (- old-length suffix 1))
                       (aref new-sequence (- new-length suffix 1))))
      (setq suffix (1+ suffix)))
    (unless (and (= start old-length) (= start new-length))
      (list
       :start start
       :old-end (- old-length suffix)
       :new-end (- new-length suffix)))))

(defun emacsvox-eat--list-slice (items start end)
  "Return the elements of ITEMS from START through END, excluding END."
  (let ((tail (nthcdr start items))
        (remaining (- end start))
        result)
    (while (> remaining 0)
      (push (car tail) result)
      (setq tail (cdr tail)
            remaining (1- remaining)))
    (nreverse result)))

(defun emacsvox-eat--row-change (old-rows new-rows)
  "Return the smallest changed row window between OLD-ROWS and NEW-ROWS."
  (when-let* ((span (emacsvox-eat--sequence-change old-rows new-rows)))
    (let ((start (plist-get span :start))
          (old-end (plist-get span :old-end))
          (new-end (plist-get span :new-end)))
      (append
       span
       (list
        :old-rows (emacsvox-eat--list-slice old-rows start old-end)
        :new-rows (emacsvox-eat--list-slice new-rows start new-end))))))

(defun emacsvox-eat--style-cells (snapshot)
  "Expand SNAPSHOT's sparse style runs into a bounded cell vector."
  (let* ((length (length (plist-get snapshot :text)))
         (cells (make-vector length nil)))
    (dolist (run (plist-get snapshot :styles))
      (let ((start (max 0 (car run)))
            (end (min length (cadr run)))
            (style (caddr run)))
        (while (< start end)
          (aset cells start style)
          (setq start (1+ start)))))
    cells))

(defun emacsvox-eat--screen-diff (old new)
  "Return a pure, data-only classification of OLD and NEW screen snapshots.
Snapshots from different terminal generations are intentionally not compared."
  (let* ((initial-p (null old))
         (generation-changed
          (and old
               (not
                (equal
                 (plist-get old :generation)
                 (plist-get new :generation)))))
         (comparable-p (and old (not generation-changed)))
         (text-changed
          (and comparable-p
               (not (equal (plist-get old :text)
                           (plist-get new :text)))))
         (style-changed
          (and comparable-p
               (not (equal (plist-get old :styles)
                           (plist-get new :styles)))))
         (cursor-moved
          (and comparable-p
               (not
                (equal
                 (list (plist-get old :cursor-row)
                       (plist-get old :cursor-column))
                 (list (plist-get new :cursor-row)
                       (plist-get new :cursor-column))))))
         (cursor-type-changed
          (and comparable-p
               (not (equal (plist-get old :cursor-type)
                           (plist-get new :cursor-type)))))
         (size-changed
          (and comparable-p
               (not (equal (plist-get old :size)
                           (plist-get new :size)))))
         (alternate-screen-changed
          (and comparable-p
               (not (eq (plist-get old :alternate-screen)
                        (plist-get new :alternate-screen)))))
         (prompt-status-changed
          (and comparable-p
               (not (eq (plist-get old :prompt-status)
                        (plist-get new :prompt-status)))))
         (title-changed
          (and comparable-p
               (not (equal (plist-get old :title)
                           (plist-get new :title)))))
         (cwd-changed
          (and comparable-p
               (not (equal (plist-get old :cwd)
                           (plist-get new :cwd)))))
         changes)
    (dolist (change
             `((initial . ,initial-p)
               (generation . ,generation-changed)
               (text . ,text-changed)
               (style . ,style-changed)
               (cursor . ,cursor-moved)
               (cursor-type . ,cursor-type-changed)
               (size . ,size-changed)
               (alternate-screen . ,alternate-screen-changed)
               (prompt-status . ,prompt-status-changed)
               (title . ,title-changed)
               (cwd . ,cwd-changed)))
      (when (cdr change) (push (car change) changes)))
    (setq changes (nreverse changes))
    (list
     :initial initial-p
     :comparable comparable-p
     :generation-changed generation-changed
     :text-changed text-changed
     :text-change
     (and text-changed
          (emacsvox-eat--sequence-change
           (plist-get old :text) (plist-get new :text)))
     :old-rows (and comparable-p (plist-get old :rows))
     :old-cursor-row (and comparable-p (plist-get old :cursor-row))
     :new-rows (and comparable-p (plist-get new :rows))
     :row-change
     (and text-changed
          (emacsvox-eat--row-change
           (plist-get old :rows) (plist-get new :rows)))
     :style-changed style-changed
     :style-change
     (and style-changed
          (emacsvox-eat--sequence-change
           (emacsvox-eat--style-cells old)
           (emacsvox-eat--style-cells new)))
     :cursor-moved cursor-moved
     :cursor-type-changed cursor-type-changed
     :size-changed size-changed
     :alternate-screen-changed alternate-screen-changed
     :prompt-status-changed prompt-status-changed
     :old-prompt-status (and comparable-p (plist-get old :prompt-status))
     :new-prompt-status (and comparable-p (plist-get new :prompt-status))
     :title-changed title-changed
     :cwd-changed cwd-changed
     :changes changes
     :unchanged (null changes))))

(defun emacsvox-eat--row-start-offsets (text)
  "Return a vector containing each logical row start offset in TEXT."
  (let ((position 0)
        (starts (list 0)))
    (while (string-match "\n" text position)
      (setq position (match-end 0))
      (push position starts))
    (vconcat (nreverse starts))))

(provide 'emacsvox-eat-screen)
;;; emacsvox-eat-screen.el ends here
