;;; emacsvox-eat.el --- Speech-enable EAT  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Keywords: Emacsvox,  Audio Desktop eat
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;;
;; This file is not part of GNU Emacs, but the same permissions apply.
;;
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EAT ==  Emacs Terminal Emulator

;;; Code:

;;; Forward variable declarations:

(defvar eat-char-mode-map)
(defvar eat-line-mode-map)
(defvar eat-mode-map)
(defvar eat-semi-char-mode-map)
(defvar eat-terminal)

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(eval-when-compile (require 'eat "eat" 'no-error))
(declare-function eat-term-display-beginning "eat" (terminal))
(declare-function eat-term-cursor-type "eat" (terminal))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-end "eat" (terminal))
(declare-function eat-term-in-alternative-display-p "eat" (terminal))
(declare-function eat-term-live-p "eat" (object))
(declare-function eat-term-size "eat" (terminal))
(declare-function eat-term-title "eat" (terminal))

;;;  Lifecycle state:

(defvar-local emacsvox-eat--generation 0
  "Monotonic identity for the current EAT terminal presentation.")

(defvar-local emacsvox-eat--active-process nil
  "Process associated with the current EAT generation.")

(defvar-local emacsvox-eat--last-exited-process nil
  "Most recent EAT process whose exit was observed in this buffer.")

(defvar-local emacsvox-eat--completion-snapshot nil
  "Generation-scoped public screen state captured before terminal Tab input.")

(defvar-local emacsvox-eat--completion-timer nil
  "Timer that expires `emacsvox-eat--completion-snapshot'.")

(defvar-local emacsvox-eat--completion-serial 0
  "Monotonic identity for terminal completion transactions in this buffer.")

(defvar-local emacsvox-eat--screen-snapshot nil
  "Most recent public-API snapshot of the visible EAT screen.")

(defvar-local emacsvox-eat--pending-screen-baseline nil
  "Screen snapshot at the beginning of the current update burst.")

(defvar-local emacsvox-eat--pending-screen-diff nil
  "Aggregate screen diff waiting for the terminal to become quiescent.")

(defvar-local emacsvox-eat--quiescence-timer nil
  "Timer waiting to finish the current EAT update burst.")

(defvar-local emacsvox-eat--update-serial 0
  "Monotonic serial number for observed EAT screen updates.")

(defvar-local emacsvox-eat--recent-input nil
  "Generation, event, and deadline for one input-correlated screen update.")

(defvar-local emacsvox-eat--last-screen-diff nil
  "Most recent quiesced screen diff retained for explicit review.")

(defvar-local emacsvox-eat--last-changed-screen nil
  "Screen snapshot belonging to `emacsvox-eat--last-screen-diff'.")

(defvar-local emacsvox-eat--pending-user-input-p nil
  "Non-nil when the current update burst followed terminal input.")

(defvar-local emacsvox-eat--quiescence-started-at nil
  "Time at which the current bounded EAT update burst began.")

(defvar-local emacsvox-eat--last-status-text nil
  "Latest conservatively classified terminal status or progress row.")

(defvar-local emacsvox-eat--last-status-spoken-at 0.0
  "Time at which automatic EAT status speech was most recently submitted.")

(defvar-local emacsvox-eat--terminal-id nil
  "Process-local integer used in replaceable EAT delivery keys.")

(defvar emacsvox-eat--next-terminal-id 0
  "Next process-local identifier for an initialized EAT buffer.")

(defconst emacsvox-eat--quiescence-delay 0.06
  "Seconds of quiet that finish one EAT screen update burst.")

(defconst emacsvox-eat--maximum-output-lines 8
  "Maximum terminal output rows spoken in one automatic presentation.")

(defconst emacsvox-eat--maximum-output-characters 1000
  "Maximum terminal content characters before a bounded truncation notice.")

(defconst emacsvox-eat--status-minimum-interval 1.5
  "Minimum seconds between automatic in-progress terminal status updates.")

(defconst emacsvox-eat--quiescence-maximum-delay 0.25
  "Maximum seconds a continuous EAT update burst may postpone classification.")

(defconst emacsvox-eat--completion-timeout 2.0
  "Seconds a terminal-side completion may await compatible remote output.")

(defconst emacsvox-eat--face-attributes
  '(:foreground :background :weight :slant :underline :strike-through
    :inverse-video :overline :box)
  "Rendered face attributes retained in terminal style snapshots.")

(defun emacsvox-eat--normalize-face-value (value)
  "Return a stable, data-only terminal style signature for face VALUE."
  (let (faces attributes)
    (cl-labels
        ((walk
          (item)
          (cond
           ((and (symbolp item) (facep item)) (push item faces))
           ((and (stringp item) (facep item))
            (when-let* ((face (intern-soft item))) (push face faces)))
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
    (when (or face mouse-face interactive-p)
      (append
       (when face (list :face face))
       (when mouse-face (list :mouse-face mouse-face))
       (when interactive-p (list :interactive t))))))

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

(defun emacsvox-eat--capture-screen ()
  "Return a data-only snapshot of the current visible EAT display.
Only public EAT terminal accessors and rendered buffer properties are used."
  (when (and eat-terminal (eat-term-live-p eat-terminal))
    (let* ((beginning
            (marker-position (eat-term-display-beginning eat-terminal)))
           (end (marker-position (eat-term-end eat-terminal)))
           (cursor-marker (eat-term-display-cursor eat-terminal))
           (cursor (and cursor-marker (marker-position cursor-marker)))
           (coordinates
            (emacsvox-eat--cursor-coordinates cursor beginning end))
           (size (eat-term-size eat-terminal))
           (title (eat-term-title eat-terminal))
           (text (buffer-substring-no-properties beginning end)))
      (list
       :generation emacsvox-eat--generation
       :display-beginning beginning
       :display-end end
       :text text
       :rows (emacsvox-eat--split-screen-rows text)
       :styles (emacsvox-eat--style-runs beginning end)
       :cursor-offset (and cursor (- cursor beginning))
       :cursor-row (car coordinates)
       :cursor-column (cdr coordinates)
       :cursor-type (eat-term-cursor-type eat-terminal)
       :size (cons (car size) (cdr size))
       :alternate-screen
       (not (null (eat-term-in-alternative-display-p eat-terminal)))
       :title (and title (substring-no-properties title))
       :cwd (and default-directory
                 (substring-no-properties default-directory))))))

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
     :title-changed title-changed
     :cwd-changed cwd-changed
     :changes changes
     :unchanged (null changes))))

(defun emacsvox-eat--row-prefix-table (rows)
  "Return the KMP prefix table for the row sequence ROWS."
  (let* ((sequence (vconcat rows))
         (table (make-vector (length sequence) 0))
         (index 1)
         matched)
    (while (< index (length sequence))
      (setq matched (aref table (1- index)))
      (while (and (> matched 0)
                  (not (equal (aref sequence index)
                              (aref sequence matched))))
        (setq matched (aref table (1- matched))))
      (when (equal (aref sequence index) (aref sequence matched))
        (setq matched (1+ matched)))
      (aset table index matched)
      (setq index (1+ index)))
    table))

(defun emacsvox-eat--suffix-prefix-row-overlap (old-rows new-rows)
  "Return how many leading NEW-ROWS are an unchanged suffix of OLD-ROWS."
  (let* ((old (vconcat old-rows))
         (new (vconcat new-rows))
         (new-length (length new))
         (table (emacsvox-eat--row-prefix-table new-rows))
         (matched 0)
         (index 0))
    (while (and (> new-length 0) (< index (length old)))
      (while (and (> matched 0)
                  (or (= matched new-length)
                      (not (equal (aref old index) (aref new matched)))))
        (setq matched (aref table (1- matched))))
      (when (and (< matched new-length)
                 (equal (aref old index) (aref new matched)))
        (setq matched (1+ matched)))
      (setq index (1+ index)))
    matched))

(defun emacsvox-eat--cancel-quiescence ()
  "Cancel and clear the pending EAT quiescence transaction."
  (when (timerp emacsvox-eat--quiescence-timer)
    (cancel-timer emacsvox-eat--quiescence-timer))
  (setq emacsvox-eat--quiescence-timer nil
        emacsvox-eat--pending-screen-baseline nil
        emacsvox-eat--pending-screen-diff nil
        emacsvox-eat--pending-user-input-p nil
        emacsvox-eat--quiescence-started-at nil))

(defun emacsvox-eat--complete-output-rows (diff snapshot)
  "Return conservative complete output rows represented by DIFF and SNAPSHOT.
Only newly inserted main-screen rows before the terminal cursor qualify."
  (when (and (plist-get diff :text-changed)
             (not (plist-get diff :size-changed))
             (not (plist-get diff :alternate-screen-changed))
             (not (plist-get snapshot :alternate-screen)))
    (when-let* ((change (plist-get diff :row-change))
                (cursor-row (plist-get snapshot :cursor-row)))
      (let* ((old-rows (plist-get diff :old-rows))
             (new-rows (plist-get diff :new-rows))
             (overlap
              (and old-rows new-rows
                   (emacsvox-eat--suffix-prefix-row-overlap
                    old-rows new-rows)))
             (start
              (cond
               ((and overlap (> overlap 0)) overlap)
               ((null (plist-get change :old-rows))
                (plist-get change :start))))
             (end (and start (min cursor-row (length new-rows)))))
        (when (and start end (> end start))
          (emacsvox-eat--list-slice new-rows start end))))))

(defun emacsvox-eat--status-row (diff snapshot)
  "Return a conservative same-row status represented by DIFF and SNAPSHOT."
  (when (and (plist-get diff :text-changed)
             (not (plist-get diff :user-input))
             (not (plist-get diff :size-changed))
             (not (plist-get diff :alternate-screen-changed))
             (not (plist-get snapshot :alternate-screen)))
    (when-let* ((change (plist-get diff :row-change))
                (cursor-row (plist-get snapshot :cursor-row))
                (old-rows (plist-get change :old-rows))
                (new-rows (plist-get change :new-rows))
                ((= (length old-rows) 1))
                ((= (length new-rows) 1))
                ((= (plist-get change :start) cursor-row))
                (row (car new-rows))
                ((let ((case-fold-search t))
                   (string-match-p
                    (concat
                     "[0-9]+\\(?:\\.[0-9]+\\)?%"
                     "\\|\\_<\\(?:progress\\|loading\\|downloading"
                     "\\|uploading\\|processing\\|complete\\|completed"
                     "\\|done\\|failed\\|error\\)\\_>")
                    row))))
      row)))

(defun emacsvox-eat--terminal-delivery-key (kind)
  "Return a stable replacement key for terminal presentation KIND."
  (unless emacsvox-eat--terminal-id
    (setq emacsvox-eat--next-terminal-id
          (1+ emacsvox-eat--next-terminal-id)
          emacsvox-eat--terminal-id emacsvox-eat--next-terminal-id))
  (list 'eat kind emacsvox-eat--terminal-id emacsvox-eat--generation))

(defun emacsvox-eat--final-status-p (text)
  "Return non-nil when status TEXT describes completion or failure."
  (let ((case-fold-search t))
    (or
     (and
      (string-match "\\([0-9]+\\(?:\\.[0-9]+\\)?\\)%" text)
      (>= (string-to-number (match-string 1 text)) 100))
     (string-match-p
      "\\_<\\(?:complete\\|completed\\|done\\|failed\\|error\\)\\_>"
      text))))

(defun emacsvox-eat--present-status (text)
  "Retain and, when due, present terminal status TEXT."
  (let ((now (float-time)))
    (setq emacsvox-eat--last-status-text text)
    (when (or (emacsvox-eat--final-status-p text)
              (>= (- now emacsvox-eat--last-status-spoken-at)
                  emacsvox-eat--status-minimum-interval))
      (setq emacsvox-eat--last-status-spoken-at now)
      (when-let* ((content (emacsvox-eat--bounded-output (list text))))
        (emacsvox-eat--submit
         content
         (emacsvox-eat--facts 'command-output 'command-output-received)
         'continuous nil 'replaceable
         (emacsvox-eat--terminal-delivery-key 'status))))))

(defun emacsvox-eat--retain-screen-change (diff snapshot)
  "Retain terminal DIFF ending at SNAPSHOT for explicit review."
  (setq emacsvox-eat--last-screen-diff diff
        emacsvox-eat--last-changed-screen snapshot)
  (when-let* ((status (emacsvox-eat--status-row diff snapshot)))
    (setq emacsvox-eat--last-status-text status)))

(defun emacsvox-eat--screen-quiesced (diff snapshot)
  "Retain and present the selected terminal DIFF ending at SNAPSHOT."
  (if-let* ((completion
             (emacsvox-eat--pending-inline-completion snapshot)))
      (progn
        (emacsvox-eat--retain-screen-change
         (plist-get completion :diff) snapshot)
        (emacsvox-eat--cancel-completion)
        (emacsvox-eat--present-inline-completion
         (plist-get completion :text)))
    (emacsvox-eat--retain-screen-change diff snapshot)
    (if-let* ((rows (emacsvox-eat--complete-output-rows diff snapshot)))
        (emacsvox-eat--present-output-rows rows)
      (when-let* ((status (emacsvox-eat--status-row diff snapshot)))
        (emacsvox-eat--present-status status)))))

(defun emacsvox-eat--finish-quiescence (buffer generation serial)
  "Finish BUFFER's update burst identified by GENERATION and SERIAL."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and emacsvox-eat--quiescence-timer
                 (= generation emacsvox-eat--generation)
                 (= serial emacsvox-eat--update-serial))
        (setq emacsvox-eat--quiescence-timer nil)
        (let ((diff emacsvox-eat--pending-screen-diff)
              (snapshot emacsvox-eat--screen-snapshot)
              (user-input-p emacsvox-eat--pending-user-input-p))
          (setq emacsvox-eat--pending-screen-baseline nil
                emacsvox-eat--pending-screen-diff nil
                emacsvox-eat--pending-user-input-p nil
                emacsvox-eat--quiescence-started-at nil)
          (when (and diff
                     (emacsvox-eat--selected-buffer-p))
            (setq diff (plist-put diff :user-input user-input-p))
            (if (emacsvox-eat--following-live-p)
                (emacsvox-eat--screen-quiesced diff snapshot)
              (emacsvox-eat--retain-screen-change diff snapshot))))))))

(defun emacsvox-eat--schedule-quiescence ()
  "Restart the timer for the current selected EAT update burst."
  (when (timerp emacsvox-eat--quiescence-timer)
    (cancel-timer emacsvox-eat--quiescence-timer))
  (let* ((elapsed
          (max 0.0
               (- (float-time)
                  (or emacsvox-eat--quiescence-started-at (float-time)))))
         (deadline-delay
          (max 0.0 (- emacsvox-eat--quiescence-maximum-delay elapsed)))
         (delay (min emacsvox-eat--quiescence-delay deadline-delay)))
    (setq emacsvox-eat--quiescence-timer
          (run-at-time
           delay nil #'emacsvox-eat--finish-quiescence
           (current-buffer) emacsvox-eat--generation
           emacsvox-eat--update-serial))))

(defun emacsvox-eat--observe-screen ()
  "Capture and aggregate the current EAT screen without producing speech."
  (when-let* ((new (emacsvox-eat--capture-screen)))
    (let ((old emacsvox-eat--screen-snapshot))
      (setq emacsvox-eat--update-serial
            (1+ emacsvox-eat--update-serial)
            emacsvox-eat--screen-snapshot new)
      (if (or (not (emacsvox-eat--selected-buffer-p))
              (null old)
              (not
               (equal
                (plist-get old :generation)
                (plist-get new :generation))))
          (emacsvox-eat--cancel-quiescence)
        (unless emacsvox-eat--pending-screen-baseline
          (setq emacsvox-eat--pending-screen-baseline old
                emacsvox-eat--quiescence-started-at (float-time)))
        (setq emacsvox-eat--pending-user-input-p
              (or emacsvox-eat--pending-user-input-p
                  emacsvox-eat--recent-input
                  emacsvox-eat--completion-snapshot))
        (setq emacsvox-eat--pending-screen-diff
              (emacsvox-eat--screen-diff
               emacsvox-eat--pending-screen-baseline new))
        (if (plist-get emacsvox-eat--pending-screen-diff :unchanged)
            (emacsvox-eat--cancel-quiescence)
          (emacsvox-eat--schedule-quiescence))))))

(defun emacsvox-eat--clear-transient-state ()
  "Clear asynchronous EAT interaction state in the current buffer."
  (emacsvox-eat--cancel-quiescence)
  (emacsvox-eat--cancel-completion)
  (setq emacsvox-eat--screen-snapshot nil
        emacsvox-eat--recent-input nil
        emacsvox-eat--last-screen-diff nil
        emacsvox-eat--last-changed-screen nil
        emacsvox-eat--last-status-text nil
        emacsvox-eat--last-status-spoken-at 0.0))

(defun emacsvox-eat--advance-generation ()
  "Invalidate asynchronous state and advance the current EAT generation."
  (setq emacsvox-eat--generation (1+ emacsvox-eat--generation))
  (emacsvox-eat--clear-transient-state)
  emacsvox-eat--generation)

(defun emacsvox-eat--facts (role event &optional operation properties)
  "Return terminal command-interaction facts for ROLE and EVENT.
OPERATION and additional PROPERTIES are optional."
  (append
   (list :role role
         :command-interaction-kind 'shell
         :events (list event))
   (when operation (list :command-operation operation))
   properties))

(defun emacsvox-eat--submit
    (content facts occasion &optional icon delivery-policy replacement-key)
  "Submit terminal CONTENT with semantic and delivery metadata.
FACTS, OCCASION, and compatibility ICON describe presentation.  Optional
DELIVERY-POLICY and REPLACEMENT-KEY control whole-transaction delivery."
  (apply
   #'emacsvox-aural-submit content
   (append
    (list :facts facts :module 'eat :occasion occasion)
    (when delivery-policy (list :delivery-policy delivery-policy))
    (when replacement-key (list :replacement-key replacement-key))
    (list
     :compatibility-actions
     (when icon
       (list (emacsvox-aural-compatibility-icon icon)))))))

(defun emacsvox-eat--sanitize-output-row (row)
  "Return ROW with untrusted C0 controls and DEL replaced by spaces."
  (apply
   #'string
   (mapcar
    (lambda (character)
      (if (or (< character 32) (= character 127)) ?\s character))
    (string-to-list (substring-no-properties row)))))

(defun emacsvox-eat--bounded-output (rows)
  "Return a bounded spoken representation of terminal output ROWS."
  (let* ((total-lines (length rows))
         (shown-count (min total-lines emacsvox-eat--maximum-output-lines))
         (shown-rows
          (mapcar
           #'emacsvox-eat--sanitize-output-row
           (emacsvox-eat--list-slice rows 0 shown-count)))
         (text (string-join shown-rows "\n"))
         (characters-truncated
          (> (length text) emacsvox-eat--maximum-output-characters)))
    (when characters-truncated
      (setq text
            (concat
             (substring text 0 emacsvox-eat--maximum-output-characters)
             " … output truncated")))
    (when (> total-lines shown-count)
      (setq text
            (concat
             text "\n"
             (format "%d additional lines not spoken"
                     (- total-lines shown-count)))))
    (unless (string-empty-p (string-trim text)) text)))

(defun emacsvox-eat--present-output-rows (rows)
  "Present bounded terminal output ROWS as one native aural transaction."
  (when-let* ((content (emacsvox-eat--bounded-output rows)))
    (emacsvox-eat--submit
     content
     (emacsvox-eat--facts 'command-output 'command-output-received)
     'continuous)))

(defun emacsvox-eat--process-started (process)
  "Start a new EAT generation for PROCESS."
  (let ((restart-p (> emacsvox-eat--generation 0)))
    (emacsvox-eat--advance-generation)
    (setq emacsvox-eat--active-process process
          emacsvox-eat--last-exited-process nil)
    ;; Initial creation already has the `eat' opening announcement.  A later
    ;; exec in the same terminal needs its own lifecycle boundary.
    (when (and restart-p (emacsvox-eat--selected-buffer-p))
      (emacsvox-eat--submit
       "Terminal process restarted"
       (emacsvox-eat--facts 'command-interaction 'operation-started)
       'state-change 'open-object))))

(defun emacsvox-eat--process-exited (process)
  "End the EAT generation belonging to PROCESS.
Ignore a stale or duplicate exit after another process has become active."
  (when
      (and
       (not (eq process emacsvox-eat--last-exited-process))
       (or
        (null emacsvox-eat--active-process)
        (eq process emacsvox-eat--active-process)))
    (emacsvox-eat--advance-generation)
    (setq emacsvox-eat--active-process nil
          emacsvox-eat--last-exited-process process)
    (when (emacsvox-eat--selected-buffer-p)
      (let* ((status (process-status process))
             (exit-status
              (and
               (memq status '(exit signal))
               (process-exit-status process)))
             (normal-p
              (or
               (eq status 'closed)
               (and
                (eq status 'exit)
                (integerp exit-status)
                (zerop exit-status))))
             (content
              (cond
               (normal-p "Terminal process exited")
               ((eq status 'signal)
                (if (integerp exit-status)
                    (format "Terminal process ended by signal %d" exit-status)
                  "Terminal process ended by signal"))
               ((integerp exit-status)
                (format "Terminal process exited with status %d" exit-status))
               (t "Terminal process ended"))))
        (emacsvox-eat--submit
         content
         (emacsvox-eat--facts
          'command-interaction 'command-process-exited 'process-exit
          (when (integerp exit-status)
            (list :command-exit-status exit-status)))
         'notification
         (if normal-p 'close-object 'warn-user))))))

(defun emacsvox-eat--invalidate-all-buffer-state ()
  "Advance the generation of every initialized EAT speech buffer."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (local-variable-p 'emacsvox-eat--generation)
          (emacsvox-eat--advance-generation))))))

(defun emacsvox--advice-eat-reset-before (&rest _)
  "Invalidate pending EAT speech state before resetting the terminal."
  (emacsvox-eat--advance-generation))

(defun emacsvox--advice-eat-reload-before (&rest _)
  "Invalidate pending speech state in every EAT buffer before reload."
  (emacsvox-eat--invalidate-all-buffer-state))

;;;  Map Faces:

(voice-setup-add-map
 '(
   (eat-shell-prompt-annotation-failure voice-lighten)
   (eat-shell-prompt-annotation-running voice-monotone)
   (eat-shell-prompt-annotation-success voice-animate)
   (eat-term-bold voice-bolden)
   (eat-term-italic voice-smoothen)))
;;; Eat Setup:

(defun emacsvox-eat-mode-setup ()
  "Placed on eat-mode-hook to do Emacsvox setup."
  (setq-local emacsvox-aural-module 'eat)
  (unless (local-variable-p 'emacsvox-eat--generation)
    (setq-local emacsvox-eat--generation 0
                emacsvox-eat--active-process
                (get-buffer-process (current-buffer))
                emacsvox-eat--last-exited-process nil))
  (define-key eat-semi-char-mode-map emacsvox-prefix 'emacsvox-keymap)
  (cl-loop
   for map in
   '(eat-line-mode-map eat-mode-map eat-char-mode-map)
   do
   (when (keymapp map) (define-key map emacsvox-prefix  'emacsvox-keymap))))

(add-hook 'eat-mode-hook 'emacsvox-eat-mode-setup)

;;;  Interactive Commands:

'(

  eat-input-char
  eat-kill-process
  eat-line-delchar-or-eof
  eat-line-find-input
  eat-line-history-isearch-backward
  eat-line-history-isearch-backward-regexp
  eat-line-load-input-history-from-file
  eat-line-next-input
  eat-line-next-matching-input
  eat-line-next-matching-input-from-input
  eat-line-previous-input
  eat-line-previous-matching-input
  eat-line-previous-matching-input-from-input
  eat-line-restore-input
  eat-line-send-input
  eat-line-send-interrupt
  eat-mouse-yank-primary
  eat-mouse-yank-secondary
  eat-narrow-to-shell-prompt
  eat-next-shell-prompt
  eat-other-window
  eat-previous-shell-prompt
  eat-project
  eat-project-other-window
  eat-quoted-input
  eat-reload
  eat-reset
  eat-self-input
  eat-send-password
  eat-trace-replay
  eat-trace-replay-next-frame
  eat-xterm-paste
  )

(defconst emacsvox-eat--yank-targets
  '(eat-yank eat-yank-from-kill-ring)
  "Eat commands that yank terminal input.")

(cl-loop
 for target in emacsvox-eat--yank-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Play a yank icon after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'yank-object)))))

(defun emacsvox--advice-eat-reload-after (&rest _)
  "Speak after reloading Eat."
  (emacsvox-eat--install-advice)
  (when (ems-interactive-p 'eat-reload)
    (emacsvox-icon 'task-done) (tts-speak "Reloaded Eat")))

(defun emacsvox--advice-eat-reset-after (&rest _)
  "Speak after resetting Eat."
  (when (ems-interactive-p 'eat-reset)
    (emacsvox-icon 'task-done) (tts-speak "Reset Eat")))

(defconst emacsvox-eat--mode-targets
  '(eat-blink-mode eat-char-mode eat-emacs-mode
    eat-eshell-char-mode eat-eshell-emacs-mode eat-eshell-mode
    eat-eshell-semi-char-mode eat-eshell-visual-command-mode
    eat-line-mode eat-mode eat-semi-char-mode
    eat-trace-mode eat-trace-replay-mode)
  "Eat mode-switching commands that receive speech feedback.")

(cl-loop
 for target in emacsvox-eat--mode-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'button)
       (message "%s " ,(symbol-name target))))))

(defun emacsvox--advice-eat-after (&rest _)
  "Speak after opening Eat."
  (when (ems-interactive-p 'eat)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defconst emacsvox-eat--advice-targets
  (append emacsvox-eat--yank-targets
          '(eat-reload eat-reset)
          emacsvox-eat--mode-targets
          '(eat))
  "Current Eat targets that receive native after advice.")

(defconst emacsvox-eat--before-advice
  '((eat-reset . emacsvox--advice-eat-reset-before)
    (eat-reload . emacsvox--advice-eat-reload-before))
  "EAT targets and native before-advice used for state invalidation.")

(defun emacsvox-eat--install-advice ()
  "Install native advice after the optional Eat package loads."
  (dolist (target emacsvox-eat--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (dolist (entry emacsvox-eat--before-advice)
    (let ((target (car entry))
          (function (cdr entry)))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :before function '((name . emacsvox-state))))))
  (when
      (and
       (fboundp 'eat-self-input)
       (not
        (advice-member-p
         #'emacsvox--advice-eat-self-input-before 'eat-self-input)))
    (advice-add
     'eat-self-input :before #'emacsvox--advice-eat-self-input-before
     '((name . emacsvox)))))

(defun emacsvox-eat--tab-event-p (event)
  "Return non-nil when EVENT is a Tab key event."
  (and event
       (or (eq event 9)
           (memq (event-basic-type event) '(9 tab)))))

(defun emacsvox-eat--capture-completion (cursor)
  "Start a terminal completion transaction at EAT terminal CURSOR."
  (emacsvox-eat--cancel-completion)
  (setq emacsvox-eat--completion-serial
        (1+ emacsvox-eat--completion-serial))
  (when-let* ((cursor)
              (screen (emacsvox-eat--capture-screen)))
    (let* ((started-at (float-time))
           (deadline (+ started-at emacsvox-eat--completion-timeout)))
      (setq emacsvox-eat--completion-snapshot
            (list
             :generation emacsvox-eat--generation
             :serial emacsvox-eat--completion-serial
             :started-at started-at
             :deadline deadline
             :screen screen)
            emacsvox-eat--completion-timer
            (run-at-time
             emacsvox-eat--completion-timeout nil
             #'emacsvox-eat--expire-completion
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--completion-serial)))))

(defun emacsvox-eat--cancel-completion ()
  "Cancel and forget the current terminal completion transaction."
  (when (timerp emacsvox-eat--completion-timer)
    (cancel-timer emacsvox-eat--completion-timer))
  (setq emacsvox-eat--completion-snapshot nil
        emacsvox-eat--completion-timer nil))

(defun emacsvox-eat--expire-completion (buffer generation serial)
  "Expire BUFFER's terminal completion identified by GENERATION and SERIAL."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and emacsvox-eat--completion-snapshot
                 (= generation emacsvox-eat--generation)
                 (= serial emacsvox-eat--completion-serial)
                 (= serial
                    (plist-get emacsvox-eat--completion-snapshot :serial)))
        (setq emacsvox-eat--completion-snapshot nil
              emacsvox-eat--completion-timer nil)))))

(defun emacsvox-eat--completion-current-p ()
  "Return non-nil when the terminal completion transaction is current."
  (let ((snapshot emacsvox-eat--completion-snapshot))
    (if (and snapshot
             (= (plist-get snapshot :generation)
                emacsvox-eat--generation)
             (<= (float-time) (plist-get snapshot :deadline)))
        t
      (emacsvox-eat--cancel-completion)
      nil)))

(defun emacsvox-eat--record-input (event)
  "Record one non-completion terminal input EVENT for correlated feedback."
  (let* ((basic (and event (event-basic-type event)))
         (recordable-p
          (or
           (and (integerp event)
                (or (= event 8) (= event 127) (>= event 32)))
           (and (symbolp basic)
                (not (memq basic '(tab return linefeed escape)))))))
    (setq emacsvox-eat--recent-input
          (when recordable-p
            (list emacsvox-eat--generation basic
                  (+ (float-time) 0.5))))))

(defun emacsvox--advice-eat-self-input-before (_count &optional event)
  "Capture terminal completion context before EAT sends Tab EVENT."
  (let ((event (or event last-command-event)))
    (if (and eat-terminal (emacsvox-eat--tab-event-p event))
        (progn
          (setq emacsvox-eat--recent-input nil)
          (emacsvox-eat--capture-completion
           (eat-term-display-cursor eat-terminal)))
      (emacsvox-eat--cancel-completion)
      (emacsvox-eat--record-input event))))

(defun emacsvox-eat--screen-cursor-input (snapshot)
  "Return SNAPSHOT's wrapped visual input facts through the terminal cursor.
Full-width rows immediately before the cursor row are treated as visual wraps.
This is a conservative public-screen inference; no EAT wrap property is read."
  (when-let* ((text (plist-get snapshot :text))
              (offset (plist-get snapshot :cursor-offset))
              (cursor-row (plist-get snapshot :cursor-row))
              (size (plist-get snapshot :size))
              (width (car size))
              ((integerp offset))
              ((<= 0 offset (length text)))
              ((integerp cursor-row))
              ((> width 0)))
    (let* ((rows (plist-get snapshot :rows))
           (prefix-rows
            (emacsvox-eat--split-screen-rows (substring text 0 offset)))
           (start cursor-row))
      (when (and (< cursor-row (length rows))
                 (= (length prefix-rows) (1+ cursor-row)))
        (while (and (> start 0)
                    (>= (string-width (nth (1- start) rows)) width))
          (setq start (1- start)))
        (list :text (mapconcat #'identity (nthcdr start prefix-rows) "")
              :start-row start)))))

(defun emacsvox-eat--screen-cursor-prefix (snapshot)
  "Return SNAPSHOT's wrapped visual input through the terminal cursor."
  (plist-get (emacsvox-eat--screen-cursor-input snapshot) :text))

(defun emacsvox-eat--completion-leading-rows-compatible-p
    (old old-input new new-input)
  "Return non-nil when OLD and NEW added no rows before their cursor inputs."
  (let* ((old-leading
          (emacsvox-eat--list-slice
           (plist-get old :rows) 0 (plist-get old-input :start-row)))
         (new-leading
          (emacsvox-eat--list-slice
           (plist-get new :rows) 0 (plist-get new-input :start-row)))
         (overlap
          (emacsvox-eat--suffix-prefix-row-overlap old-leading new-leading)))
    (or (equal old-leading new-leading)
        (and (> overlap 0) (<= (length new-leading) overlap)))))

(defun emacsvox-eat--escaped-character-p (text index)
  "Return non-nil when the character at TEXT INDEX is backslash-escaped."
  (let ((backslashes 0)
        (position (1- index)))
    (while (and (>= position 0) (= (aref text position) ?\\))
      (setq backslashes (1+ backslashes)
            position (1- position)))
    (= (% backslashes 2) 1)))

(defun emacsvox-eat--completion-display-field (prefix)
  "Return a conservative final displayed field from cursor PREFIX.
Backslash-escaped whitespace remains part of the field.  Quote-bearing input
returns nil because recognizing its logical word would require shell grammar."
  (unless (string-match-p "['\"]" prefix)
    (let* ((end (string-match-p "[[:space:]]*\\'" prefix))
           (start end))
      (while
          (and (> start 0)
               (let* ((index (1- start))
                      (character (aref prefix index)))
                 (or (not (memq character '(?\s ?\t ?\n ?\r)))
                     (emacsvox-eat--escaped-character-p prefix index))))
        (setq start (1- start)))
      (and (< start end) (substring prefix start end)))))

(defun emacsvox-eat--completion-label (displayed-field)
  "Return a concise path-aware label for DISPLAYED-FIELD."
  (let* ((length (length displayed-field))
         (directory-p
          (and (> length 0) (= (aref displayed-field (1- length)) ?/)))
         (trimmed
          (if directory-p (substring displayed-field 0 -1) displayed-field))
         (component (file-name-nondirectory trimmed)))
    (concat (if (zerop (length component)) trimmed component)
            (if directory-p "/" ""))))

(defun emacsvox-eat--inline-completion-change (old new)
  "Return conservative inline completion facts between OLD and NEW screens."
  (when (and old new
             (equal (plist-get old :generation)
                    (plist-get new :generation))
             (not (plist-get old :alternate-screen))
             (not (plist-get new :alternate-screen)))
    (let* ((diff (emacsvox-eat--screen-diff old new))
           (old-input (emacsvox-eat--screen-cursor-input old))
           (new-input (emacsvox-eat--screen-cursor-input new))
           (old-prefix (plist-get old-input :text))
           (new-prefix (plist-get new-input :text))
           (change
            (and old-prefix new-prefix
                 (emacsvox-eat--sequence-change old-prefix new-prefix))))
      (when (and change
                 (> (plist-get change :start) 0)
                 (>= (length new-prefix) (length old-prefix))
                 (emacsvox-eat--completion-leading-rows-compatible-p
                  old old-input new new-input)
                 (not (emacsvox-eat--complete-output-rows diff new)))
        (let* ((trimmed (string-trim-right new-prefix))
               (field (emacsvox-eat--completion-display-field new-prefix))
               (text
                (if field
                    (emacsvox-eat--completion-label field)
                  trimmed)))
          (when (and (stringp text) (not (string-empty-p text)))
            (list :text text :old old-prefix :new new-prefix
                  :change change :diff (plist-put diff :user-input t))))))))

(defun emacsvox-eat--pending-inline-completion (snapshot)
  "Return inline completion facts for pending transaction at SNAPSHOT."
  (when (emacsvox-eat--completion-current-p)
    (emacsvox-eat--inline-completion-change
     (plist-get emacsvox-eat--completion-snapshot :screen) snapshot)))

(defun emacsvox-eat--present-inline-completion (text)
  "Present inline terminal completion TEXT as one semantic transaction."
  (when-let* ((content (emacsvox-eat--bounded-output (list text))))
    (emacsvox-eat--submit
     content '(:role candidate :events (completion-input-updated))
     'state-change)))

(defun emacsvox-eat--speak-input-correlated-update (cursor)
  "Provide the legacy cursor feedback for one recent terminal input at CURSOR."
  (let ((input emacsvox-eat--recent-input))
    (setq emacsvox-eat--recent-input nil)
    (when (and input cursor
               (= (car input) emacsvox-eat--generation)
               (<= (float-time) (caddr input))
               emacsvox-eat--pending-screen-diff)
      (let ((char (char-before cursor)))
        (cond
         ((eq char ?\s) (emacsvox-speak-line) t)
         (char (emacsvox-speak-this-char char) t))))))

(defun emacsvox-eat--selected-buffer-p ()
  "Return non-nil when the current EAT buffer is selected."
  (eq (current-buffer) (window-buffer (selected-window))))

(defun emacsvox-eat--following-live-p ()
  "Return non-nil when the selected EAT window follows its live cursor.
This mirrors EAT's window synchronization condition using only the public
terminal cursor accessor."
  (and (emacsvox-eat--selected-buffer-p)
       (eat-term-live-p eat-terminal)
       (= (eat-term-display-cursor eat-terminal)
          (window-point (selected-window)))))

(with-eval-after-load 'eat
  (emacsvox-eat--install-advice))

;;; Speech-Enable Terminal Emulation:

(defun emacsvox-eat-update-hook ()
  "Speak an EAT update when its buffer is selected."
  (emacsvox-eat--observe-screen)
  (if (not (emacsvox-eat--selected-buffer-p))
      (progn
        (emacsvox-eat--cancel-completion)
        (setq emacsvox-eat--recent-input nil))
    (let* ((emacsvox-show-point t)
           (cursor (eat-term-display-cursor eat-terminal)))
      (emacsvox-eat--speak-input-correlated-update cursor))))

(add-hook 'eat-update-hook #'emacsvox-eat-update-hook)
(add-hook 'eat-exec-hook #'emacsvox-eat--process-started)
(add-hook 'eat-exit-hook #'emacsvox-eat--process-exited)
(provide 'emacsvox-eat)
;;;  end of file
