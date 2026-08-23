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
(defvar eat-blink-mode)
(defvar eat-eshell-mode)
(defvar eat-eshell-visual-command-mode)
(defvar eat-line-mode-map)
(defvar eat-mode-map)
(defvar eat-semi-char-mode-map)
(defvar eat-terminal)
(defvar eat-trace-mode)

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
(declare-function eat-term-parameter "eat" (terminal parameter))
(declare-function eat-term-set-parameter "eat" (terminal parameter value))
(declare-function eat-term-size "eat" (terminal))
(declare-function eat-term-title "eat" (terminal))

;;;  Customization:

(defgroup emacsvox-eat nil
  "Speech access to EAT terminals."
  :group 'emacsvox
  :prefix "emacsvox-eat-")

(defcustom emacsvox-eat-verbosity 'normal
  "Amount of automatic feedback produced for EAT terminals.
At `terse', retain routine output and metadata for review but do not speak
them automatically.  `normal' speaks bounded command output and status, while
`verbose' additionally announces bounded terminal title and directory changes.
Lifecycle, bell, paste, and completion feedback remains available at every
level.  This option may be set buffer-locally for an individual terminal."
  :type '(choice
          (const :tag "Terse" terse)
          (const :tag "Normal" normal)
          (const :tag "Verbose" verbose))
  :group 'emacsvox-eat)

(make-variable-buffer-local 'emacsvox-eat-verbosity)

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

(defvar-local emacsvox-eat--pending-alternate-screen-transitions nil
  "Alternate-screen states crossed during the pending update burst.")

(defvar-local emacsvox-eat--quiescence-timer nil
  "Timer waiting to finish the current EAT update burst.")

(defvar-local emacsvox-eat--update-serial 0
  "Monotonic serial number for observed EAT screen updates.")

(defvar-local emacsvox-eat--recent-input nil
  "Generation, event, and deadline for one input-correlated screen update.")

(defvar-local emacsvox-eat--secure-input-active-p nil
  "Non-nil while EAT is reading and sending protected terminal input.")

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

(defvar-local emacsvox-eat--last-completion-output nil
  "Latest quiesced terminal candidate/help-row presentation.")

(defvar-local emacsvox-eat--last-bell-at nil
  "Time at which EAT most recently delivered a terminal bell.")

(defvar-local emacsvox-eat--last-bell-spoken-at nil
  "Time at which Emacsvox most recently announced an EAT terminal bell.")

(defvar-local emacsvox-eat--last-metadata-change nil
  "Latest bounded title or working-directory change retained for review.")

(defvar-local emacsvox-eat--last-metadata-spoken-at nil
  "Time at which EAT metadata was most recently announced automatically.")

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

(defconst emacsvox-eat--bell-minimum-interval 0.5
  "Minimum seconds between spoken bells from one EAT terminal.")

(defconst emacsvox-eat--metadata-minimum-interval 1.0
  "Minimum seconds between automatic EAT metadata announcements.")

(defconst emacsvox-eat--maximum-metadata-characters 256
  "Maximum characters retained from one terminal metadata value.")

(defconst emacsvox-eat--maximum-spoken-candidates 8
  "Maximum inferred terminal candidates spoken automatically at once.")

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
        emacsvox-eat--pending-alternate-screen-transitions nil
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

(defun emacsvox-eat--metadata-change (diff snapshot)
  "Return bounded changed terminal metadata from DIFF and SNAPSHOT."
  (when (or (plist-get diff :title-changed)
            (plist-get diff :cwd-changed))
    (list
     :generation (plist-get snapshot :generation)
     :observed-at (float-time)
     :title-changed (not (null (plist-get diff :title-changed)))
     :title (plist-get snapshot :title)
     :cwd-changed (not (null (plist-get diff :cwd-changed)))
     :cwd (plist-get snapshot :cwd))))

(defun emacsvox-eat--metadata-lines (diff snapshot)
  "Return human descriptions of metadata changed in DIFF at SNAPSHOT."
  (let (lines)
    (when (plist-get diff :title-changed)
      (push
       (if-let* ((title (plist-get snapshot :title))
                 ((not (string-empty-p title))))
           (format "Terminal title: %s" title)
         "Terminal title cleared")
       lines))
    (when (plist-get diff :cwd-changed)
      (push
       (if-let* ((cwd (plist-get snapshot :cwd))
                 ((not (string-empty-p cwd))))
           (format "Working directory: %s" cwd)
         "Working directory unavailable")
       lines))
    (nreverse lines)))

(defun emacsvox-eat--retain-metadata-change (diff snapshot)
  "Retain bounded terminal metadata changed in DIFF at SNAPSHOT."
  (when-let* ((change (emacsvox-eat--metadata-change diff snapshot)))
    (setq emacsvox-eat--last-metadata-change change)))

(defun emacsvox-eat--present-metadata-change (diff snapshot)
  "Present verbose terminal metadata changed in DIFF at SNAPSHOT when due."
  (when (eq emacsvox-eat-verbosity 'verbose)
    (when-let* ((lines (emacsvox-eat--metadata-lines diff snapshot)))
      (let ((now (float-time)))
        (when (or (null emacsvox-eat--last-metadata-spoken-at)
                  (>= (- now emacsvox-eat--last-metadata-spoken-at)
                      emacsvox-eat--metadata-minimum-interval))
          (setq emacsvox-eat--last-metadata-spoken-at now)
          (emacsvox-eat--submit
           (string-join lines "\n")
           (emacsvox-eat--facts 'command-interaction 'state-changed)
           'state-change nil 'replaceable
           (emacsvox-eat--terminal-delivery-key 'metadata)))))))

(defun emacsvox-eat--retain-screen-change (diff snapshot)
  "Retain terminal DIFF ending at SNAPSHOT for explicit review."
  (setq emacsvox-eat--last-screen-diff diff
        emacsvox-eat--last-changed-screen snapshot)
  (emacsvox-eat--retain-metadata-change diff snapshot)
  (when-let* ((status (emacsvox-eat--status-row diff snapshot)))
    (setq emacsvox-eat--last-status-text status)))

(defun emacsvox-eat--alternate-screen-transitions (diff snapshot)
  "Return chronological alternate-screen states represented by DIFF.
SNAPSHOT supplies the final state when DIFF was not produced by the observer."
  (or (plist-get diff :alternate-screen-transitions)
      (and (plist-get diff :alternate-screen-changed)
           (list (not (null (plist-get snapshot :alternate-screen)))))))

(defun emacsvox-eat--present-alternate-screen-transitions (states)
  "Present each alternate-screen state in chronological STATES once."
  (dolist (entered-p states)
    (emacsvox-eat--submit
     (if entered-p
         "Terminal application screen entered"
       "Terminal application screen exited")
     (emacsvox-eat--facts
      'command-interaction
      (if entered-p 'operation-started 'operation-completed))
     'state-change
     (if entered-p 'open-object 'close-object))))

(defun emacsvox-eat--screen-quiesced (diff snapshot)
  "Retain and present the selected terminal DIFF ending at SNAPSHOT."
  (prog1
      (cond
       ((when-let* ((states
                     (emacsvox-eat--alternate-screen-transitions
                      diff snapshot)))
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--recent-input nil
                emacsvox-eat--last-status-text nil
                emacsvox-eat--last-status-spoken-at 0.0
                emacsvox-eat--last-completion-output nil)
          (emacsvox-eat--retain-screen-change diff snapshot)
          (emacsvox-eat--present-alternate-screen-transitions states)
          t))
       ((when-let* ((completion
                     (emacsvox-eat--pending-inline-completion snapshot)))
          (emacsvox-eat--retain-screen-change
           (plist-get completion :diff) snapshot)
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--last-completion-output nil)
          (emacsvox-eat--present-inline-completion
           (plist-get completion :text))
          t))
       ((when-let* ((completion
                     (emacsvox-eat--pending-completion-output snapshot)))
          (setq completion
                (plist-put
                 completion :repeated
                 (emacsvox-eat--completion-repeated-p completion)))
          (emacsvox-eat--retain-screen-change
           (plist-get completion :diff) snapshot)
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--last-completion-output completion)
          (emacsvox-eat--present-completion-output completion)
          t))
       ((emacsvox-eat--completion-current-p)
        ;; Candidate/help output can pause on a completed row before the peer
        ;; redraws its input.  Retain that partial screen without letting the
        ;; ordinary output path announce it and then repeat it at completion.
        (emacsvox-eat--retain-screen-change diff snapshot))
       (t
        (emacsvox-eat--retain-screen-change diff snapshot)
        (unless (eq emacsvox-eat-verbosity 'terse)
          (if-let* ((rows (emacsvox-eat--complete-output-rows diff snapshot)))
              (emacsvox-eat--present-output-rows rows)
            (when-let* ((status (emacsvox-eat--status-row diff snapshot)))
              (emacsvox-eat--present-status status))))))
    (emacsvox-eat--present-metadata-change diff snapshot)))

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
              (alternate-screen-transitions
               (nreverse emacsvox-eat--pending-alternate-screen-transitions))
              (user-input-p emacsvox-eat--pending-user-input-p))
          (setq emacsvox-eat--pending-screen-baseline nil
                emacsvox-eat--pending-screen-diff nil
                emacsvox-eat--pending-alternate-screen-transitions nil
                emacsvox-eat--pending-user-input-p nil
                emacsvox-eat--quiescence-started-at nil)
          (when (and diff
                     (emacsvox-eat--selected-buffer-p))
            (setq diff (plist-put diff :user-input user-input-p))
            (when alternate-screen-transitions
              (setq diff
                    (plist-put
                     diff :alternate-screen-transitions
                     alternate-screen-transitions)))
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
        (when (not (eq (plist-get old :alternate-screen)
                       (plist-get new :alternate-screen)))
          (push (not (null (plist-get new :alternate-screen)))
                emacsvox-eat--pending-alternate-screen-transitions)
          ;; Terminal completion and replaceable status state cannot span a
          ;; change to or from an application's independent screen.
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--recent-input nil
                emacsvox-eat--last-status-text nil
                emacsvox-eat--last-status-spoken-at 0.0
                emacsvox-eat--last-completion-output nil))
        (setq emacsvox-eat--pending-user-input-p
              (or emacsvox-eat--pending-user-input-p
                  emacsvox-eat--recent-input
                  emacsvox-eat--completion-snapshot))
        (setq emacsvox-eat--pending-screen-diff
              (emacsvox-eat--screen-diff
               emacsvox-eat--pending-screen-baseline new))
        (if (and (plist-get emacsvox-eat--pending-screen-diff :unchanged)
                 (null emacsvox-eat--pending-alternate-screen-transitions))
            (emacsvox-eat--cancel-quiescence)
          (emacsvox-eat--schedule-quiescence))))))

(defun emacsvox-eat--clear-sensitive-screen-state ()
  "Forget content-bearing EAT observation state in the current buffer."
  (emacsvox-eat--cancel-quiescence)
  (emacsvox-eat--cancel-completion)
  (setq emacsvox-eat--screen-snapshot nil
        emacsvox-eat--recent-input nil
        emacsvox-eat--last-screen-diff nil
        emacsvox-eat--last-changed-screen nil
        emacsvox-eat--last-status-text nil
        emacsvox-eat--last-status-spoken-at 0.0
        emacsvox-eat--last-completion-output nil
        emacsvox-eat--last-metadata-change nil
        emacsvox-eat--last-metadata-spoken-at nil))

(defun emacsvox-eat--clear-transient-state ()
  "Clear asynchronous EAT interaction state in the current buffer."
  (emacsvox-eat--clear-sensitive-screen-state)
  (setq emacsvox-eat--secure-input-active-p nil
        emacsvox-eat--last-bell-at nil
        emacsvox-eat--last-bell-spoken-at nil))

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

(defun emacsvox-eat--observe-bell (terminal)
  "Record and, when appropriate, announce a bell from TERMINAL.
The terminal's original bell callback has already run."
  (when-let* ((buffer
               (ignore-errors
                 (eat-term-parameter terminal 'emacsvox-eat-buffer)))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (when (eq terminal eat-terminal)
        (let ((now (float-time)))
          (setq emacsvox-eat--last-bell-at now
                ;; A bell is its own input response; do not also speak the
                ;; adjacent prompt character through legacy echo feedback.
                emacsvox-eat--recent-input nil)
          (when (and (not emacsvox-eat--secure-input-active-p)
                     (emacsvox-eat--selected-buffer-p)
                     (emacsvox-eat--following-live-p)
                     (or (null emacsvox-eat--last-bell-spoken-at)
                         (>= (- now emacsvox-eat--last-bell-spoken-at)
                             emacsvox-eat--bell-minimum-interval)))
            (setq emacsvox-eat--last-bell-spoken-at now)
            ;; EAT's original callback already provides the configured bell;
            ;; do not add a second compatibility cue.
            (emacsvox-eat--submit
             "Terminal bell"
             (emacsvox-eat--facts 'command-interaction 'object-changed)
             'notification)))))))

(defun emacsvox-eat--ring-bell (terminal)
  "Preserve TERMINAL's original bell callback, then notify Emacsvox safely."
  (let ((original
         (ignore-errors
           (eat-term-parameter
            terminal 'emacsvox-eat-original-ring-bell-function))))
    (prog1
        (when (and (functionp original)
                   (not (eq original #'emacsvox-eat--ring-bell)))
          (funcall original terminal))
      ;; Accessibility feedback must never break terminal escape processing.
      (condition-case nil
          (emacsvox-eat--observe-bell terminal)
        (error nil)))))

(defun emacsvox-eat--install-bell-observer ()
  "Wrap the current terminal's public bell callback exactly once."
  (when (and eat-terminal (eat-term-live-p eat-terminal))
    (let ((current
           (eat-term-parameter eat-terminal 'ring-bell-function)))
      (unless (eq current #'emacsvox-eat--ring-bell)
        (setf
         (eat-term-parameter
          eat-terminal 'emacsvox-eat-original-ring-bell-function)
         current)
        (setf
         (eat-term-parameter eat-terminal 'emacsvox-eat-buffer)
         (current-buffer))
        (setf (eat-term-parameter eat-terminal 'ring-bell-function)
              #'emacsvox-eat--ring-bell)))))

(defun emacsvox-eat--process-started (process)
  "Start a new EAT generation for PROCESS."
  (let ((restart-p (> emacsvox-eat--generation 0)))
    (emacsvox-eat--advance-generation)
    (setq emacsvox-eat--active-process process
          emacsvox-eat--last-exited-process nil)
    (emacsvox-eat--install-bell-observer)
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
  (emacsvox-eat--install-bell-observer)
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
  '(eat-yank eat-yank-from-kill-ring eat-xterm-paste
    eat-mouse-yank-primary eat-mouse-yank-secondary)
  "EAT commands that paste saved or selected terminal input.")

(defconst emacsvox-eat--yank-labels
  '((eat-yank . "Pasted terminal input")
    (eat-yank-from-kill-ring . "Pasted selected kill-ring input")
    (eat-xterm-paste . "Pasted clipboard input")
    (eat-mouse-yank-primary . "Pasted primary selection")
    (eat-mouse-yank-secondary . "Pasted secondary selection"))
  "Content-free human feedback for EAT terminal paste commands.")

(defun emacsvox-eat--before-terminal-paste (&rest _)
  "Invalidate input-correlated state before sending terminal paste content."
  (emacsvox-eat--cancel-completion)
  (setq emacsvox-eat--recent-input nil))

(defun emacsvox-eat--present-terminal-paste (target)
  "Present a content-free terminal paste performed by EAT command TARGET."
  (emacsvox-eat--submit
   (or (alist-get target emacsvox-eat--yank-labels)
       "Pasted terminal input")
   (emacsvox-eat--facts
    'command-input 'object-changed nil '(:command-input-origin copied))
   'edit 'yank-object))

(cl-loop
 for target in emacsvox-eat--yank-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present content-free paste feedback after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-eat--present-terminal-paste ',target)))))

(defun emacsvox-eat--present-secure-input-result (completed-p)
  "Present a content-free EAT secure-input result for COMPLETED-P."
  (emacsvox-eat--submit
   (if completed-p
       "Secure terminal input sent"
     "Secure terminal input cancelled")
   (emacsvox-eat--facts
    'command-interaction
    (if completed-p 'operation-completed 'state-changed))
   'state-change
   (if completed-p 'task-done 'close-object)))

(defun emacsvox--advice-eat-send-password-around (original &rest arguments)
  "Protect EAT observation state while calling password command ORIGINAL.
ARGUMENTS are passed through without inspection so password content never
reaches this advice."
  (let ((terminal-buffer (current-buffer))
        (interactive-p (ems-interactive-p 'eat-send-password))
        completed-p)
    (with-current-buffer terminal-buffer
      (emacsvox-eat--clear-sensitive-screen-state)
      (setq emacsvox-eat--secure-input-active-p t))
    (unwind-protect
        (prog1 (apply original arguments)
          (setq completed-p t))
      (when (buffer-live-p terminal-buffer)
        (with-current-buffer terminal-buffer
          (emacsvox-eat--clear-sensitive-screen-state)
          (setq emacsvox-eat--secure-input-active-p nil)
          (when (and interactive-p (emacsvox-eat--selected-buffer-p))
            ;; Feedback must not prevent a password send or mask its error.
            (condition-case nil
                (emacsvox-eat--present-secure-input-result completed-p)
              (error nil))))))))

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

(defconst emacsvox-eat--mode-labels
  '((eat-blink-mode . "Terminal blinking")
    (eat-char-mode . "Character input mode")
    (eat-emacs-mode . "Emacs input mode")
    (eat-eshell-char-mode . "Eshell character input mode")
    (eat-eshell-emacs-mode . "Eshell Emacs input mode")
    (eat-eshell-mode . "EAT Eshell integration")
    (eat-eshell-semi-char-mode . "Eshell semi-character input mode")
    (eat-eshell-visual-command-mode . "EAT Eshell visual commands")
    (eat-line-mode . "Line input mode")
    (eat-mode . "EAT terminal mode")
    (eat-semi-char-mode . "Semi-character input mode")
    (eat-trace-mode . "EAT tracing")
    (eat-trace-replay-mode . "EAT trace replay mode"))
  "Human descriptions of interactive EAT mode commands.")

(defun emacsvox-eat--mode-feedback (target)
  "Return concise human feedback for EAT mode command TARGET."
  (let ((label (or (alist-get target emacsvox-eat--mode-labels)
                   (symbol-name target))))
    (pcase target
      ('eat-blink-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-blink-mode)
                   "enabled" "disabled")))
      ('eat-eshell-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-eshell-mode)
                   "enabled" "disabled")))
      ('eat-eshell-visual-command-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-eshell-visual-command-mode)
                   "enabled" "disabled")))
      ('eat-trace-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-trace-mode)
                   "enabled" "disabled")))
      (_ label))))

(defun emacsvox-eat--present-mode-feedback (target)
  "Present the human mode state produced by EAT command TARGET."
  (emacsvox-eat--submit
   (emacsvox-eat--mode-feedback target)
   (emacsvox-eat--facts 'command-interaction 'state-changed)
   'state-change 'button))

(cl-loop
 for target in emacsvox-eat--mode-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-eat--present-mode-feedback ',target)))))

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
  (append
   '((eat-reset . emacsvox--advice-eat-reset-before)
     (eat-reload . emacsvox--advice-eat-reload-before))
   (mapcar
    (lambda (target)
      (cons target #'emacsvox-eat--before-terminal-paste))
    emacsvox-eat--yank-targets))
  "EAT targets and native before-advice used for state invalidation.")

(defconst emacsvox-eat--around-advice
  '((eat-send-password . emacsvox--advice-eat-send-password-around))
  "EAT targets and native around-advice used for protected interaction.")

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
  (dolist (entry emacsvox-eat--around-advice)
    (let ((target (car entry))
          (function (cdr entry)))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox-state))))))
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

(defun emacsvox-eat--completion-input-compatible-p (old-input new-input)
  "Return non-nil when NEW-INPUT can be a redraw of OLD-INPUT."
  (or (equal old-input new-input)
      (when-let* ((change
                   (and old-input new-input
                        (emacsvox-eat--sequence-change old-input new-input))))
        (and (> (plist-get change :start) 0)
             (>= (length new-input) (length old-input))))))

(defun emacsvox-eat--completion-row-items (row)
  "Return conservatively inferred candidate items from terminal ROW.
Two or more spaces may separate columns.  A resulting cell containing any
whitespace is treated as descriptive or ambiguous, so the row is not split."
  (let* ((trimmed (string-trim row))
         (items (and (not (string-empty-p trimmed))
                     (split-string trimmed "[ \t]\\{2,\\}" t))))
    (when (and items
               (cl-every
                (lambda (item) (not (string-match-p "[[:space:]]" item)))
                items))
      items)))

(defun emacsvox-eat--completion-items (rows)
  "Return inferred candidate items from ROWS, or nil for row-oriented output."
  (let ((nonempty
         (cl-remove-if
          (lambda (row) (string-empty-p (string-trim row))) rows))
        items
        valid-p)
    (setq valid-p (not (null nonempty)))
    (dolist (row nonempty)
      (if-let* ((row-items (emacsvox-eat--completion-row-items row)))
          (setq items (append items row-items))
        (setq valid-p nil)))
    (and valid-p items)))

(defun emacsvox-eat--completion-signature (layout rows &optional items)
  "Return a stable normalized signature for completion LAYOUT, ROWS, and ITEMS."
  (list
   layout
   (mapcar
    (lambda (text)
      (string-trim-right (emacsvox-eat--sanitize-output-row text)))
    (if (eq layout 'items) items rows))))

(defun emacsvox-eat--completion-repeated-p (completion)
  "Return non-nil when COMPLETION repeats the retained completion output."
  (and emacsvox-eat--last-completion-output
       (equal (plist-get completion :signature)
              (plist-get emacsvox-eat--last-completion-output :signature))))

(defun emacsvox-eat--completion-output-change (old new)
  "Return candidate/help-row facts between OLD and NEW terminal screens.
Rows are preserved exactly.  `:confidence' is `anchored' when the old screen
through its input row remains as a prefix after scroll alignment, and
`unanchored' when only the redrawn cursor input provides an association."
  (when (and old new
             (equal (plist-get old :generation)
                    (plist-get new :generation))
             (not (plist-get old :alternate-screen))
             (not (plist-get new :alternate-screen)))
    (when-let* ((old-input (emacsvox-eat--screen-cursor-input old))
                (new-input (emacsvox-eat--screen-cursor-input new))
                ((emacsvox-eat--completion-input-compatible-p
                  (plist-get old-input :text) (plist-get new-input :text)))
                (old-cursor-row (plist-get old :cursor-row))
                (new-start-row (plist-get new-input :start-row))
                ((integerp old-cursor-row))
                ((integerp new-start-row)))
      (let* ((old-through-input
              (emacsvox-eat--list-slice
               (plist-get old :rows) 0
               (min (length (plist-get old :rows))
                    (1+ old-cursor-row))))
             (new-leading
              (emacsvox-eat--list-slice
               (plist-get new :rows) 0
               (min (length (plist-get new :rows)) new-start-row)))
             (overlap
              (emacsvox-eat--suffix-prefix-row-overlap
               old-through-input new-leading))
             (rows
              (if (> overlap 0)
                  (nthcdr overlap new-leading)
                new-leading)))
        (when (cl-some
               (lambda (row) (not (string-empty-p (string-trim row))))
               rows)
          (let* ((diff (emacsvox-eat--screen-diff old new))
                 (retained-rows (copy-sequence rows))
                 (content-rows
                  (cl-remove-if
                   (lambda (row) (string-empty-p (string-trim row)))
                   retained-rows))
                 (items (emacsvox-eat--completion-items retained-rows))
                 (layout (if items 'items 'rows)))
            (list
             :rows retained-rows
             :row-count (length content-rows)
             :items items
             :item-count (and items (length items))
             :layout layout
             :signature
             (emacsvox-eat--completion-signature
              layout retained-rows items)
             :confidence (if (> overlap 0) 'anchored 'unanchored)
             :old-input (plist-get old-input :text)
             :new-input (plist-get new-input :text)
             :diff (plist-put diff :user-input t))))))))

(defun emacsvox-eat--pending-completion-output (snapshot)
  "Return candidate/help rows for the pending transaction at SNAPSHOT."
  (when (emacsvox-eat--completion-current-p)
    (emacsvox-eat--completion-output-change
     (plist-get emacsvox-eat--completion-snapshot :screen) snapshot)))

(defun emacsvox-eat--present-inline-completion (text)
  "Present inline terminal completion TEXT as one semantic transaction."
  (when-let* ((content (emacsvox-eat--bounded-output (list text))))
    (emacsvox-eat--submit
     content '(:role candidate :events (completion-input-updated))
     'state-change)))

(defun emacsvox-eat--completion-count-text (completion)
  "Return an accurate count announcement for terminal COMPLETION."
  (let* ((item-count (plist-get completion :item-count))
         (row-count (plist-get completion :row-count))
         (items-p (integerp item-count))
         (count (if items-p item-count row-count))
         (noun (if items-p "candidate" "completion row"))
         (unanchored-p
          (eq (plist-get completion :confidence) 'unanchored)))
    (concat
     (cond
      ((plist-get completion :repeated) "Same ")
      (unanchored-p "At least ")
      (t ""))
     (number-to-string count)
     (if unanchored-p " visible " " ")
     noun
     (if (= count 1) "" "s"))))

(defun emacsvox-eat--bounded-completion-items (items)
  "Return bounded automatic speech for inferred candidate ITEMS."
  (let* ((total (length items))
         (shown-count (min total emacsvox-eat--maximum-spoken-candidates))
         (text
          (emacsvox-eat--bounded-output
           (emacsvox-eat--list-slice items 0 shown-count))))
    (when (> total shown-count)
      (setq text
            (concat
             text "\n"
             (format "%d additional candidates not spoken"
                     (- total shown-count)))))
    text))

(defun emacsvox-eat--present-completion-output (completion)
  "Present terminal candidate/help-row COMPLETION as one transaction."
  (let* ((count (emacsvox-eat--completion-count-text completion))
         (body
          (unless (plist-get completion :repeated)
            (if (eq (plist-get completion :layout) 'items)
                (emacsvox-eat--bounded-completion-items
                 (plist-get completion :items))
              (emacsvox-eat--bounded-output
               (plist-get completion :rows)))))
         (content (if body (concat count "\n" body) count)))
    (when (not (string-empty-p content))
    (emacsvox-eat--submit
     content '(:role candidate :events (operation-completed))
     'state-change))))

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
  (emacsvox-eat--install-bell-observer)
  (if emacsvox-eat--secure-input-active-p
      (emacsvox-eat--clear-sensitive-screen-state)
    (emacsvox-eat--observe-screen)
    (if (not (emacsvox-eat--selected-buffer-p))
        (progn
          (emacsvox-eat--cancel-completion)
          (setq emacsvox-eat--recent-input nil))
      (let* ((emacsvox-show-point t)
             (cursor (eat-term-display-cursor eat-terminal)))
        (emacsvox-eat--speak-input-correlated-update cursor)))))

(add-hook 'eat-update-hook #'emacsvox-eat-update-hook)
(add-hook 'eat-exec-hook #'emacsvox-eat--process-started)
(add-hook 'eat-exit-hook #'emacsvox-eat--process-exited)
(provide 'emacsvox-eat)
;;;  end of file
