;;; emacsvox-eat-focus.el --- EAT focus inference and navigation feedback  -*- lexical-binding: t; -*-

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
;; EAT focus inference and navigation feedback.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

(require 'emacsvox-eat-screen)
(eval-when-compile (require 'cl-lib))

;; Observation and presentation state is initialized and cleared by core.
(defvar emacsvox-eat--update-serial)
(defvar emacsvox-eat--last-focus-presentation-identity)
(declare-function emacsvox-eat--sanitize-output-row "emacsvox-eat-core" (row))
(declare-function emacsvox-eat--bounded-output "emacsvox-eat-core" (rows))
(declare-function emacsvox-eat--facts "emacsvox-eat-core"
                  (role event &optional operation properties))
(declare-function emacsvox-eat--submit "emacsvox-eat-core"
                  (content facts occasion &optional icon delivery-policy replacement-key))
(declare-function emacsvox-eat--terminal-delivery-key "emacsvox-eat-core" (kind))

(defconst emacsvox-eat--maximum-focus-characters 240
  "Maximum characters retained for one inferred terminal focus object.")

(defun emacsvox-eat--row-for-offset (starts offset)
  "Return the row in STARTS containing character OFFSET."
  (let ((low 0)
        (high (1- (length starts))))
    (while (< low high)
      (let ((middle (/ (+ low high 1) 2)))
        (if (<= (aref starts middle) offset)
            (setq low middle)
          (setq high (1- middle)))))
    low))

(defun emacsvox-eat--offset-coordinates (text starts offset)
  "Return zero-based row and display column for OFFSET in TEXT using STARTS."
  (let* ((bounded (max 0 (min offset (length text))))
         (row (emacsvox-eat--row-for-offset starts bounded))
         (row-start (aref starts row)))
    (cons row (string-width (substring text row-start bounded)))))

(defun emacsvox-eat--highlight-signature (style)
  "Return a conservative selection-like signature for rendered STYLE."
  (let* ((traits (plist-get style :traits))
         (attributes
          (plist-get (plist-get style :face) :attributes))
         (foreground (alist-get :foreground attributes))
         (background (alist-get :background attributes)))
    (unless (memq 'concealed traits)
      (cond
       ((memq 'inverse-like traits)
        (list :inverse-like t
              :foreground foreground :background background))
       ((and (memq 'background-color traits) background)
        (list :background background))))))

(defun emacsvox-eat--highlight-regions (snapshot)
  "Return compact selection-like rendered regions from SNAPSHOT."
  (let* ((text (or (plist-get snapshot :text) ""))
         (starts (emacsvox-eat--row-start-offsets text))
         regions)
    (dolist (run (plist-get snapshot :styles))
      (let* ((start (max 0 (car run)))
             (end (min (length text) (cadr run)))
             (style (caddr run))
             (signature (emacsvox-eat--highlight-signature style)))
        (when (and signature (< start end))
          (let* ((start-coordinates
                  (emacsvox-eat--offset-coordinates text starts start))
                 (end-coordinates
                  (emacsvox-eat--offset-coordinates
                   text starts (max start (1- end))))
                 (region
                  (list
                   :start start :end end
                   :row-start (car start-coordinates)
                   :row-end (car end-coordinates)
                   :column-start (cdr start-coordinates)
                   :column-end
                   (cdr
                    (emacsvox-eat--offset-coordinates text starts end))
                   :signature signature
                   :traits (copy-sequence (plist-get style :traits)))))
            (if-let* ((previous (car regions))
                      ((= (plist-get previous :end) start))
                      ((= (plist-get previous :row-end)
                          (plist-get region :row-start)))
                      ((equal (plist-get previous :signature) signature)))
                (setcar
                 regions
                 (plist-put
                  (plist-put
                   (plist-put
                    previous :end end)
                   :column-end (plist-get region :column-end))
                  :traits
                  (delete-dups
                   (append (plist-get previous :traits)
                           (plist-get region :traits)))))
              (push region regions))))))
    (mapcar
     (lambda (region)
       (plist-put
        region :text
        (string-trim
         (substring
          text (plist-get region :start) (plist-get region :end)))))
     (nreverse regions))))

(defun emacsvox-eat--same-highlight-region-p (left right)
  "Return non-nil when LEFT and RIGHT identify the same styled region."
  (and (= (plist-get left :start) (plist-get right :start))
       (= (plist-get left :end) (plist-get right :end))
       (equal (plist-get left :signature)
              (plist-get right :signature))))

(defun emacsvox-eat--coordinate-direction-p
    (direction old-row old-column new-row new-column)
  "Return non-nil when OLD to NEW coordinates agree with DIRECTION."
  (when (and (integerp old-row) (integerp old-column)
             (integerp new-row) (integerp new-column))
    (pcase direction
      ('up (< new-row old-row))
      ('down (> new-row old-row))
      ('left (and (= new-row old-row) (< new-column old-column)))
      ('right (and (= new-row old-row) (> new-column old-column)))
      ('forward
       (or (> new-row old-row)
           (and (= new-row old-row) (> new-column old-column))))
      ('backward
       (or (< new-row old-row)
           (and (= new-row old-row) (< new-column old-column)))))))

(defun emacsvox-eat--bounded-focus-text (text)
  "Return bounded, control-free terminal focus TEXT, or nil when unusable."
  (let ((sanitized
         (string-trim (emacsvox-eat--sanitize-output-row text))))
    (when (and (not (string-empty-p sanitized))
               (string-match-p "[[:alnum:]]" sanitized))
      (if (> (length sanitized) emacsvox-eat--maximum-focus-characters)
          (concat
           (substring sanitized 0 emacsvox-eat--maximum-focus-characters)
           "…")
        sanitized))))

(defun emacsvox-eat--style-focus-change (old new diff navigation)
  "Return a conservative paired-style focus change from OLD to NEW.
DIFF and content-free NAVIGATION provide causal evidence."
  (when (and old new navigation
             (plist-get diff :style-changed)
             (not (plist-get diff :text-changed))
             (not (plist-get diff :size-changed))
             (not (plist-get diff :alternate-screen-changed))
             (equal (plist-get old :generation)
                    (plist-get new :generation)))
    (let* ((old-regions (emacsvox-eat--highlight-regions old))
           (new-regions (emacsvox-eat--highlight-regions new))
           (gained
            (cl-remove-if
             (lambda (region)
               (cl-some
                (lambda (old-region)
                  (emacsvox-eat--same-highlight-region-p
                   region old-region))
                old-regions))
             new-regions))
           (lost
            (cl-remove-if
             (lambda (region)
               (cl-some
                (lambda (new-region)
                  (emacsvox-eat--same-highlight-region-p
                   region new-region))
                new-regions))
             old-regions)))
      (when (and (= (length gained) 1) (= (length lost) 1))
        (let* ((new-region (car gained))
               (old-region (car lost))
               (direction (plist-get navigation :direction))
               (signature (plist-get new-region :signature))
               (text (emacsvox-eat--bounded-focus-text
                      (plist-get new-region :text)))
               (row-span
                (1+ (- (plist-get new-region :row-end)
                       (plist-get new-region :row-start))))
               (region-direction-p
                (emacsvox-eat--coordinate-direction-p
                 direction
                 (plist-get old-region :row-start)
                 (plist-get old-region :column-start)
                 (plist-get new-region :row-start)
                 (plist-get new-region :column-start)))
               (cursor-row (plist-get new :cursor-row))
               (cursor-proximity
                (cond
                 ((and (integerp cursor-row)
                       (<= (plist-get new-region :row-start) cursor-row)
                       (<= cursor-row (plist-get new-region :row-end)))
                  'within)
                 ((and (integerp cursor-row)
                       (<=
                        (min
                         (abs (- cursor-row
                                 (plist-get new-region :row-start)))
                         (abs (- cursor-row
                                 (plist-get new-region :row-end))))
                        1))
                  'adjacent)))
               (cursor-direction-p
                (or
                 (not (plist-get diff :cursor-moved))
                 (emacsvox-eat--coordinate-direction-p
                  direction
                  (plist-get old :cursor-row)
                  (plist-get old :cursor-column)
                  (plist-get new :cursor-row)
                  (plist-get new :cursor-column))))
               (score
                (+ 4
                   (if (plist-get signature :inverse-like) 2 1)
                   (if (eq cursor-proximity 'within) 2
                     (if (eq cursor-proximity 'adjacent) 1 0))
                   (if region-direction-p 2 0)
                   (if (and (plist-get diff :cursor-moved)
                            cursor-direction-p)
                       1 0)
                   (if (<= row-span 2) 1 0))))
          (when (and text
                     (<= row-span 2)
                     region-direction-p
                     cursor-direction-p
                     (>= score 8))
            (list
             :kind 'highlight
             :text text
             :row-start (plist-get new-region :row-start)
             :row-end (plist-get new-region :row-end)
             :column-start (plist-get new-region :column-start)
             :column-end (plist-get new-region :column-end)
             :traits (plist-get new-region :traits)
             :direction direction
             :score score
             :confidence (if (>= score 10) 'high 'medium)
             :generation (plist-get new :generation)
             :screen-serial emacsvox-eat--update-serial
             :observed-at (float-time)
             :identity
             (list
              'highlight (plist-get new :generation)
              (plist-get new-region :row-start)
              (plist-get new-region :column-start)
              signature text))))))))

(defun emacsvox-eat--cursor-row-focus-change (old new diff navigation)
  "Return a conservative alternate-screen cursor-row change from OLD to NEW."
  (let ((direction (plist-get navigation :direction)))
    (when (and old new navigation
               (plist-get new :alternate-screen)
               (plist-get diff :cursor-moved)
               (not (plist-get diff :text-changed))
               (not (plist-get diff :style-changed))
               (not (plist-get diff :size-changed))
               (not (plist-get diff :alternate-screen-changed))
               (memq direction '(up down forward backward))
               (emacsvox-eat--coordinate-direction-p
                direction
                (plist-get old :cursor-row)
                (plist-get old :cursor-column)
                (plist-get new :cursor-row)
                (plist-get new :cursor-column)))
      (when-let* ((row (plist-get new :cursor-row))
                  ((< -1 row (length (plist-get new :rows))))
                  (text
                   (emacsvox-eat--bounded-focus-text
                    (nth row (plist-get new :rows)))))
        (list
         :kind 'cursor-row
         :text text
         :row-start row :row-end row
         :column-start 0 :column-end (string-width text)
         :direction direction
         :score 8 :confidence 'medium
         :generation (plist-get new :generation)
         :screen-serial emacsvox-eat--update-serial
         :observed-at (float-time)
         :identity
         (list 'cursor-row (plist-get new :generation) row text))))))

(defun emacsvox-eat--likely-focus-change (old new diff navigation)
  "Return the strongest conservative focus inference from OLD to NEW."
  (or (emacsvox-eat--style-focus-change old new diff navigation)
      (emacsvox-eat--cursor-row-focus-change old new diff navigation)))

(defun emacsvox-eat--main-screen-navigation-text (diff snapshot)
  "Return conservative main-screen navigation feedback for DIFF and SNAPSHOT.
Left and right movement name the rendered character reached.  Word movement
returns the exact rendered span crossed.  Up and down movement return the
resulting rendered input or history row without its observed prompt prefix."
  (when-let* ((navigation (plist-get diff :navigation))
              ((not (plist-get navigation :ambiguous)))
              ((not (plist-get snapshot :alternate-screen)))
              ((not (plist-get diff :size-changed)))
              ((not (plist-get diff :alternate-screen-changed)))
              (direction (plist-get navigation :direction))
              (old-row (plist-get navigation :cursor-row))
              (old-column (plist-get navigation :cursor-column))
              (new-row (plist-get snapshot :cursor-row))
              (new-column (plist-get snapshot :cursor-column)))
    (pcase direction
      ((or 'left 'right 'forward 'backward)
       (when (and
              (plist-get diff :cursor-moved)
              (emacsvox-eat--coordinate-direction-p
               (if (memq direction '(left backward)) 'backward 'forward)
               old-row old-column new-row new-column))
         (let* ((text (plist-get snapshot :text))
                (offset (plist-get snapshot :cursor-offset))
                (old-offset (plist-get navigation :cursor-offset))
                (word-movement-p (eq (plist-get navigation :unit) 'word))
                (word
                 (and word-movement-p
                      (integerp old-offset)
                      (integerp offset)
                      (<= 0 old-offset (length text))
                      (<= 0 offset (length text))
                      (< (min old-offset offset) (max old-offset offset))
                      (string-trim
                       (substring
                        text (min old-offset offset) (max old-offset offset)))))
                (character
                 (and (integerp offset)
                      (< -1 offset (length text))
                      (aref text offset))))
           (cond
            ((and word (not (string-empty-p word)))
             (emacsvox-eat--bounded-output
              (emacsvox-eat--split-screen-rows word)))
            (word-movement-p nil)
            (character
             (or (tts-char-to-speech character)
                 (char-to-string character)))
            ((and (integerp offset) (= offset (length text)))
             "End of terminal row")))))
      ((or 'up 'down)
       (when-let* ((rows (plist-get snapshot :rows))
                   ((< -1 new-row (length rows)))
                   (row-text (nth new-row rows))
                   (old-rows (plist-get diff :old-rows))
                   (old-row-text
                    (and (integerp old-row)
                         (< -1 old-row (length old-rows))
                         (nth old-row old-rows)))
                   (input-row-offset
                    (plist-get navigation :input-row-offset))
                   (input-start-row
                    (plist-get navigation :input-start-row))
                   ((or
                     (and
                      (plist-get diff :cursor-moved)
                      (emacsvox-eat--coordinate-direction-p
                       direction old-row old-column new-row new-column))
                     (not (equal old-row-text row-text)))))
         (let ((input
                (if (and (integerp input-start-row)
                         (= input-start-row old-row new-row)
                         (integerp input-row-offset)
                         (<= 0 input-row-offset (length row-text)))
                    (substring row-text input-row-offset)
                  row-text)))
           (or (emacsvox-eat--bounded-output (list input))
               "Empty terminal input")))))))

(defun emacsvox-eat--present-main-screen-navigation (diff snapshot)
  "Present observed main-screen navigation represented by DIFF and SNAPSHOT."
  (when-let* ((content
               (emacsvox-eat--main-screen-navigation-text diff snapshot)))
    (emacsvox-eat--submit
     content
     (emacsvox-eat--facts
      'command-input 'focus-entered 'command-navigation
      '(:command-input-origin current))
     'navigation nil 'replaceable
     (emacsvox-eat--terminal-delivery-key 'main-navigation))
    t))

(defun emacsvox-eat--automatic-focus-p (focus)
  "Return non-nil when FOCUS has enough evidence for automatic speech."
  (or (eq (plist-get focus :kind) 'cursor-row)
      (and (eq (plist-get focus :kind) 'highlight)
           (eq (plist-get focus :confidence) 'high))))

(defun emacsvox-eat--present-likely-focus (focus)
  "Present non-repeated FOCUS as replaceable terminal navigation."
  (let ((identity (plist-get focus :identity)))
    (when (and (emacsvox-eat--automatic-focus-p focus)
               identity
               (not
                (equal identity
                       emacsvox-eat--last-focus-presentation-identity)))
      (emacsvox-eat--submit
       (format
        (if (eq (plist-get focus :kind) 'highlight)
            "Highlight: %s"
          "Terminal row: %s")
        (plist-get focus :text))
       (emacsvox-eat--facts
        'command-output 'focus-entered 'output-navigation)
       'navigation nil 'replaceable
       (emacsvox-eat--terminal-delivery-key 'focus))
      (setq emacsvox-eat--last-focus-presentation-identity identity)
      t)))

(provide 'emacsvox-eat-focus)
;;; emacsvox-eat-focus.el ends here
