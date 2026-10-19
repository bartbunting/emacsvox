;;; emacsvox-eat-output.el --- EAT rendered output collection  -*- lexical-binding: t; -*-

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
;; EAT rendered output collection.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

(require 'emacsvox-eat-screen)
(eval-when-compile (require 'cl-lib))
(defvar eat-terminal)

;; Core owns terminal generations, foreground eligibility and observation timing.
(defvar emacsvox-eat-autospeak)
(defvar emacsvox-eat--generation)
(defvar emacsvox-eat--update-serial)
(defvar emacsvox-eat--terminal-id)
(defvar emacsvox-eat--secure-input-active-p)
(declare-function emacsvox-eat--foreground-p "emacsvox-eat-core" ())
(declare-function eat-term-live-p "eat" (object))
(declare-function eat-term-beginning "eat" (terminal))
(declare-function eat-term-display-beginning "eat" (terminal))
(declare-function eat-term-end "eat" (terminal))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-in-alternative-display-p "eat" (terminal))
(declare-function eat-term-size "eat" (terminal))
(declare-function eat-term-parameter "eat" (terminal parameter))

(defconst emacsvox-eat--maximum-output-lines 8
  "Maximum terminal output rows spoken in one automatic presentation.")

(defconst emacsvox-eat--maximum-output-characters 1000
  "Maximum terminal content characters before a bounded truncation notice.")

(defvar-local emacsvox-eat--output-frontier nil
  "Owned marker at the first unfinished rendered output row.")

(defvar-local emacsvox-eat--output-skip-row-p nil
  "Non-nil when the unfinished rendered row belongs to terminal input.")

(defvar-local emacsvox-eat--output-partial ""
  "Bounded redacted soft-wrapped prefix of the unfinished logical line.")

(defvar-local emacsvox-eat--output-partial-truncated-p nil
  "Non-nil when the unfinished logical line exceeded the collection budget.")

(defvar-local emacsvox-eat--collected-output nil
  "Bounded redacted output rows, in reverse order, awaiting presentation.")

(defvar-local emacsvox-eat--collected-output-lines 0
  "Number of completed output rows observed in the pending burst.")

(defvar-local emacsvox-eat--collected-output-characters 0
  "Number of output characters retained in the pending burst.")

(defvar-local emacsvox-eat--collected-output-truncated-p nil
  "Non-nil when the pending burst exceeded its character budget.")

(defvar-local emacsvox-eat--unfinished-output nil
  "Cached unfinished output: bounded redacted text, truncation flag, end marker.")

(defvar-local emacsvox-eat--output-observed-p nil
  "Non-nil when the pending burst has a rendered-output observation.")

(defvar-local emacsvox-eat--output-continuity-lost-p nil
  "Non-nil when the pending burst can no longer be collected as appended output.")

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

(defun emacsvox-eat--clear-collected-output ()
  "Discard the pending bounded output collection."
  (emacsvox-eat--clear-unfinished-output)
  (setq emacsvox-eat--collected-output nil
        emacsvox-eat--collected-output-lines 0
        emacsvox-eat--collected-output-characters 0
        emacsvox-eat--collected-output-truncated-p nil
        emacsvox-eat--output-continuity-lost-p nil
        emacsvox-eat--output-observed-p nil))

(defun emacsvox-eat--clear-output-frontier ()
  "Discard rendered-output continuity and its pending collection."
  (when (markerp emacsvox-eat--output-frontier)
    (set-marker emacsvox-eat--output-frontier nil))
  (setq emacsvox-eat--output-frontier nil
        emacsvox-eat--output-skip-row-p nil
        emacsvox-eat--output-partial ""
        emacsvox-eat--output-partial-truncated-p nil)
  (emacsvox-eat--clear-collected-output))

(defun emacsvox-eat--output-input-boundary (&rest _)
  "Exclude the current unfinished terminal row from output collection."
  (emacsvox-eat--clear-unfinished-output)
  (setq emacsvox-eat--output-skip-row-p t
        emacsvox-eat--output-partial ""
        emacsvox-eat--output-partial-truncated-p nil))

(defvar-local emacsvox-eat--prompt-ranges nil
  "Bounded rendered prompt ranges, newest first, as owned marker pairs.
An unfinished prompt has a nil end marker.")

(defvar-local emacsvox-eat--prompt-overflow-p nil
  "Non-nil when too many prompts make the current output burst ambiguous.")

(defvar-local emacsvox-eat--prompt-eligible-p nil
  "Non-nil when the current shell prompt began in eligible foreground state.")

(defvar-local emacsvox-eat--pending-prompt nil
  "Bounded, redacted ready prompt awaiting foreground presentation.")

(defvar-local emacsvox-eat--last-prompt nil
  "Most recently identified prompt, bounded and concealed-redacted.")

(defvar-local emacsvox-eat--prompt-identity nil
  "Owned start marker and redacted text for deduplicating prompt redraws.")

(defun emacsvox-eat--forget-prompt-range (range)
  "Release owned markers in prompt RANGE."
  (set-marker (car range) nil)
  (when (cdr range) (set-marker (cdr range) nil)))

(defun emacsvox-eat--clear-prompt-state ()
  "Discard retained prompt content and owned marker ranges."
  (mapc #'emacsvox-eat--forget-prompt-range emacsvox-eat--prompt-ranges)
  (when emacsvox-eat--prompt-identity
    (set-marker (car emacsvox-eat--prompt-identity) nil))
  (setq emacsvox-eat--prompt-identity nil
        emacsvox-eat--prompt-ranges nil
        emacsvox-eat--prompt-overflow-p nil
        emacsvox-eat--prompt-eligible-p nil
        emacsvox-eat--pending-prompt nil
        emacsvox-eat--last-prompt nil))

(defun emacsvox-eat--prune-prompt-ranges ()
  "Release completed prompt ranges already passed by the output frontier."
  (setq emacsvox-eat--prompt-ranges
        (cl-delete-if
         (lambda (range)
           (when (and (cdr range)
                      (or (not (marker-buffer (car range)))
                          (and emacsvox-eat--output-frontier
                               (<= (cdr range) emacsvox-eat--output-frontier))))
             (emacsvox-eat--forget-prompt-range range)
             t))
         emacsvox-eat--prompt-ranges)))

(defun emacsvox-eat--observe-prompt-command (command)
  "Observe a parsed EAT shell-integration COMMAND at the rendered cursor.
B and C are EAT's prompt-start and prompt-end UI commands.  No terminal
escape parsing or shell-prompt guessing is performed here."
  (unless (or emacsvox-eat--secure-input-active-p
              (eat-term-in-alternative-display-p eat-terminal))
    (pcase command
      ("e;J"
       ;; A new shell cycle differs from Readline repainting the same prompt.
       (when emacsvox-eat--prompt-identity
         (set-marker (car emacsvox-eat--prompt-identity) nil))
       (setq emacsvox-eat--prompt-identity nil))
      ("e;B"
       (emacsvox-eat--prune-prompt-ranges)
       (when (>= (length emacsvox-eat--prompt-ranges)
                 emacsvox-eat--maximum-output-lines)
         (mapc #'emacsvox-eat--forget-prompt-range emacsvox-eat--prompt-ranges)
         (setq emacsvox-eat--prompt-ranges nil
               emacsvox-eat--prompt-overflow-p t))
       (push (cons (point-marker) nil) emacsvox-eat--prompt-ranges)
       (setq emacsvox-eat--last-prompt nil
             emacsvox-eat--prompt-eligible-p
             (and emacsvox-eat-autospeak (emacsvox-eat--foreground-p))))
      ("e;C"
       (when-let* ((range (car emacsvox-eat--prompt-ranges))
                   ((null (cdr range)))
                   ((<= (car range) (point))))
         (setcdr range (point-marker))
         (let* ((begin (car range))
                (end (min (point) (+ begin emacsvox-eat--maximum-output-characters)))
                (text (emacsvox-eat--redact-concealed-text
                       (buffer-substring-no-properties begin end)
                       (emacsvox-eat--style-runs begin end))))
           (setq text
                 (apply #'string
                        (cl-loop for character across text for position from begin
                                 unless (and (= character ?\n)
                                             (get-text-property position 'eat--t-wrap-line))
                                 collect character)))
           (setq emacsvox-eat--last-prompt
                 (emacsvox-eat--bounded-output
                  (split-string (concat text (when (< end (point)) " … prompt truncated"))
                                "\n")))
           (let ((repeated
                  (and emacsvox-eat--prompt-identity
                       (= begin (car emacsvox-eat--prompt-identity))
                       (equal emacsvox-eat--last-prompt
                              (cdr emacsvox-eat--prompt-identity)))))
             (when emacsvox-eat--prompt-identity
               (set-marker (car emacsvox-eat--prompt-identity) nil))
             (setq emacsvox-eat--prompt-identity
                   (cons (copy-marker begin) emacsvox-eat--last-prompt))
             (when (and (not repeated) emacsvox-eat--prompt-eligible-p
                        emacsvox-eat-autospeak (emacsvox-eat--foreground-p))
               (setq emacsvox-eat--pending-prompt
                     (or emacsvox-eat--last-prompt ""))))))))))

(defun emacsvox-eat--prompt-ui-command (terminal command)
  "Preserve TERMINAL's UI callback and observe its parsed prompt COMMAND."
  (let ((original (eat-term-parameter terminal 'emacsvox-eat-original-ui-command)))
    (prog1 (funcall original terminal command)
      (when (and (eq terminal eat-terminal)
                 (local-variable-p 'emacsvox-eat--generation))
        (condition-case nil
            (emacsvox-eat--observe-prompt-command command)
          (error
           (emacsvox-eat--clear-prompt-state)
           (emacsvox-aural-diagnostic-log-event
            'eat-prompt-observation :decision 'discarded :reason 'observation-error
            :generation emacsvox-eat--generation)))))))

(defun emacsvox-eat--output-pieces (begin end)
  "Return BEGIN through END with known prompt ranges removed.
The result contains buffer-bound pairs only, with at most one more piece than
the bounded prompt-range list.  Text is redacted separately before retention."
  (let ((cursor begin) pieces)
    (dolist (range (reverse emacsvox-eat--prompt-ranges))
      (let ((start (max begin (min end (car range))))
            (finish (max begin (min end (or (cdr range) end)))))
        (when (> start cursor) (push (cons cursor start) pieces))
        (setq cursor (max cursor finish))))
    (when (< cursor end) (push (cons cursor end) pieces))
    (nreverse pieces)))

(defun emacsvox-eat--clear-unfinished-output ()
  "Discard the bounded unfinished row and its owned end marker."
  (when emacsvox-eat--unfinished-output
    (set-marker (nth 2 emacsvox-eat--unfinished-output) nil))
  (setq emacsvox-eat--unfinished-output nil))

(defun emacsvox-eat--capture-unfinished-output ()
  "Cache bounded, redacted unfinished output before redisplay can trim it."
  (emacsvox-eat--clear-unfinished-output)
  (when (and emacsvox-eat--output-frontier
             (not emacsvox-eat--prompt-overflow-p)
             (not emacsvox-eat--output-skip-row-p)
             (not (eat-term-in-alternative-display-p eat-terminal)))
    (let ((end (eat-term-display-cursor eat-terminal)))
      (when (and (<= (eat-term-beginning eat-terminal)
                     emacsvox-eat--output-frontier end)
                 (or (< emacsvox-eat--output-frontier end)
                     (not (string-empty-p emacsvox-eat--output-partial))))
        ;; Reuse the collector's redaction and remaining character budget,
        ;; without completing the row until the burst actually settles.
        (let ((emacsvox-eat--collected-output nil)
              (emacsvox-eat--collected-output-lines 0)
              (emacsvox-eat--collected-output-characters
               emacsvox-eat--collected-output-characters)
              (emacsvox-eat--collected-output-truncated-p nil)
              (emacsvox-eat--output-partial emacsvox-eat--output-partial)
              (emacsvox-eat--output-partial-truncated-p
               emacsvox-eat--output-partial-truncated-p))
          (emacsvox-eat--collect-output-row emacsvox-eat--output-frontier end nil)
          (unless emacsvox-eat--collected-output
            ;; An identified prompt occupied the whole tail.  Advance past
            ;; it even though there is no ordinary text to retain.
            (set-marker emacsvox-eat--output-frontier end))
          (when emacsvox-eat--collected-output
            (setq emacsvox-eat--unfinished-output
                  (list (car emacsvox-eat--collected-output)
                        emacsvox-eat--collected-output-truncated-p
                        (copy-marker end)))))))))

(defun emacsvox-eat--collect-unfinished-output ()
  "Finish the cached unfinished row once, even after trim or terminal exit."
  (when emacsvox-eat--unfinished-output
    (cl-incf emacsvox-eat--collected-output-lines)
    (when (<= emacsvox-eat--collected-output-lines emacsvox-eat--maximum-output-lines)
      (push (car emacsvox-eat--unfinished-output) emacsvox-eat--collected-output)
      (cl-incf emacsvox-eat--collected-output-characters
               (1+ (length (car emacsvox-eat--unfinished-output))))
      (setq emacsvox-eat--collected-output-truncated-p
            (or emacsvox-eat--collected-output-truncated-p
                (cadr emacsvox-eat--unfinished-output))))
    (when emacsvox-eat--output-frontier
      (set-marker emacsvox-eat--output-frontier
                  (nth 2 emacsvox-eat--unfinished-output)))
    (setq emacsvox-eat--output-partial ""
          emacsvox-eat--output-partial-truncated-p nil)
    (emacsvox-eat--clear-unfinished-output))
  (emacsvox-eat--prune-prompt-ranges))

(defun emacsvox-eat--collect-output-row (begin end wrapped)
  "Collect rendered BEGIN through END; WRAPPED means a soft line break.
EAT marks inserted wrap newlines in the rendered buffer.  Read this property
before redisplay joins scrollback lines, without parsing terminal escapes."
  (let* ((pieces (emacsvox-eat--output-pieces begin end))
         (room (max 0 (- emacsvox-eat--maximum-output-characters
                         emacsvox-eat--collected-output-characters
                         (length emacsvox-eat--output-partial)))))
    (when (or pieces (not (string-empty-p emacsvox-eat--output-partial))
              ;; Preserve genuine empty output rows, but never count a row
              ;; occupied solely by an identified prompt.
              (and (= begin end) (null emacsvox-eat--prompt-ranges)))
      (dolist (piece pieces)
        (let* ((start (car piece)) (finish (cdr piece))
               (limit (min finish (+ start room)))
               (text (emacsvox-eat--redact-concealed-text
                      (buffer-substring-no-properties start limit)
                      (emacsvox-eat--style-runs start limit))))
          (setq emacsvox-eat--output-partial
                (concat emacsvox-eat--output-partial
                        (emacsvox-eat--sanitize-output-row text))
                emacsvox-eat--output-partial-truncated-p
                (or emacsvox-eat--output-partial-truncated-p (< limit finish))
                room (max 0 (- room (- limit start))))))
      (unless wrapped
        (cl-incf emacsvox-eat--collected-output-lines)
        (when (<= emacsvox-eat--collected-output-lines emacsvox-eat--maximum-output-lines)
          (push emacsvox-eat--output-partial emacsvox-eat--collected-output)
          (cl-incf emacsvox-eat--collected-output-characters
                   (1+ (length emacsvox-eat--output-partial)))
          (setq emacsvox-eat--collected-output-truncated-p
                (or emacsvox-eat--collected-output-truncated-p
                    emacsvox-eat--output-partial-truncated-p)))
        (setq emacsvox-eat--output-partial ""
              emacsvox-eat--output-partial-truncated-p nil)))))

(defun emacsvox-eat--collected-output-text ()
  "Return the bounded pending output, including any omission notice."
  (let ((text (string-join (reverse emacsvox-eat--collected-output) "\n"))
        (omitted (- emacsvox-eat--collected-output-lines
                    (length emacsvox-eat--collected-output))))
    (when emacsvox-eat--collected-output-truncated-p
      (setq text (concat text " … output truncated")))
    (when (> omitted 0)
      (setq text (concat text "\n"
                         (format "%d additional lines not spoken" omitted))))
    (unless (string-empty-p (string-trim text)) text)))

(defun emacsvox-eat--diagnose-output (decision reason)
  "Record content-free output DECISION and REASON when diagnostics are enabled.
These adapter decisions establish neither successful transport nor playback."
  (emacsvox-aural-diagnostic-log-event
   'eat-output-decision :decision decision :reason reason
   :terminal-id emacsvox-eat--terminal-id
   :generation emacsvox-eat--generation :update-serial emacsvox-eat--update-serial))

(defun emacsvox-eat--process-rendered-output (original terminal output)
  "Call ORIGINAL on TERMINAL and OUTPUT, collecting before redisplay trims.
Use only rendered text and fresh public terminal bounds.  A copied tail
marker must survive unchanged: destructive edits before that boundary cannot
be mistaken for appended output, even when the replacement text is identical."
  (if (or (not (eq terminal eat-terminal))
          (not (local-variable-p 'emacsvox-eat--generation))
          emacsvox-eat--secure-input-active-p)
      (funcall original terminal output)
    (save-restriction
      (widen)
      (let* ((cursor (+ 0 (eat-term-end terminal)))
             (anchor (copy-marker cursor))
             (display (eat-term-display-beginning terminal))
             (size (eat-term-size terminal))
             (eligible (and emacsvox-eat-autospeak
                            (emacsvox-eat--foreground-p)
                            (not (eat-term-in-alternative-display-p terminal))
                            (save-excursion
                              (goto-char (eat-term-display-cursor terminal))
                              ;; Line-mode draft text can follow the terminal
                              ;; extent on this same physical buffer row.
                              (>= (line-end-position) cursor))))
             (generation emacsvox-eat--generation))
        (unless emacsvox-eat--output-frontier
          (setq emacsvox-eat--output-frontier (copy-marker cursor)))
        (unwind-protect
            (prog1 (funcall original terminal output)
              (condition-case nil
                  (when (= generation emacsvox-eat--generation)
                    (setq emacsvox-eat--output-observed-p t)
                    (if (not (and eligible
                                  (not emacsvox-eat--output-continuity-lost-p)
                                  (not emacsvox-eat--prompt-overflow-p)
                                  (= anchor cursor)
                                  (eq display (eat-term-display-beginning terminal))
                                  (equal size (eat-term-size terminal))
                                  (not (eat-term-in-alternative-display-p terminal))
                                  (<= (eat-term-beginning terminal)
                                      emacsvox-eat--output-frontier
                                      (eat-term-end terminal))))
                        (progn
                          (emacsvox-eat--diagnose-output
                           'discarded (if eligible 'continuity-unproven
                                        'collection-ineligible))
                          (emacsvox-eat--clear-collected-output)
                          (setq emacsvox-eat--output-observed-p t
                                ;; A redraw may arrive in several chunks.  Its
                                ;; tail stays untrusted until this burst settles.
                                emacsvox-eat--output-continuity-lost-p t
                                emacsvox-eat--output-partial ""
                                emacsvox-eat--output-partial-truncated-p nil)
                          (set-marker emacsvox-eat--output-frontier
                                      (eat-term-display-cursor terminal)))
                      (save-excursion
                        (goto-char emacsvox-eat--output-frontier)
                        (let ((limit (eat-term-display-cursor terminal)))
                          (while (and (<= (point) limit)
                                      (search-forward "\n" limit t))
                            (let ((wrapped (get-text-property
                                            (1- (point)) 'eat--t-wrap-line)))
                              (if emacsvox-eat--output-skip-row-p
                                  (unless wrapped
                                    (setq emacsvox-eat--output-skip-row-p nil))
                                (unless (and (= emacsvox-eat--output-frontier
                                                (1- (point)))
                                             (string-empty-p emacsvox-eat--output-partial)
                                             (zerop emacsvox-eat--collected-output-lines))
                                  (emacsvox-eat--collect-output-row
                                   emacsvox-eat--output-frontier (1- (point)) wrapped))))
                            (set-marker emacsvox-eat--output-frontier (point))))))
                    (emacsvox-eat--capture-unfinished-output))
                (error
                 ;; Observation must never interrupt terminal rendering.
                 (emacsvox-eat--clear-output-frontier)
                 (setq emacsvox-eat--output-observed-p t)
                 (emacsvox-aural-diagnostic-log-event
                  'eat-output-observation :decision 'discarded
                  :reason 'observation-error :generation generation
                  :terminal-id emacsvox-eat--terminal-id))))
          (set-marker anchor nil)
          (when emacsvox-eat--prompt-overflow-p
            (setq emacsvox-eat--prompt-overflow-p nil)
            (emacsvox-eat--prune-prompt-ranges)))))))

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
             (changed-old-rows (plist-get change :old-rows))
             (changed-new-rows (plist-get change :new-rows))
             (overlap
              (and old-rows new-rows
                   (emacsvox-eat--suffix-prefix-row-overlap
                    old-rows new-rows)))
             (start
              (cond
               ((null changed-old-rows)
                (plist-get change :start))
               ;; Some terminals append output by replacing one trailing
               ;; empty placeholder.  Its match with a leading empty screen
               ;; row is not useful evidence of scrolling.
               ((and
                 (= (length changed-old-rows) 1)
                 (> (length changed-new-rows) 1)
                 (string-empty-p (car changed-old-rows)))
                (plist-get change :start))
               ;; A final echoed input character and the command output can
               ;; arrive in the same burst.  Skip only that continued row.
               ((and
                 (plist-get diff :user-input)
                 (= (length changed-old-rows) 1)
                 (> (length changed-new-rows) 1)
                 (not (string-empty-p (car changed-old-rows)))
                 (string-prefix-p
                  (car changed-old-rows) (car changed-new-rows)))
                (1+ (plist-get change :start)))
               ((and overlap (> overlap 0)) overlap)))
             (end (and start (min cursor-row (length new-rows)))))
        (when (and start end (> end start))
          (emacsvox-eat--list-slice new-rows start end))))))

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

(provide 'emacsvox-eat-output)
;;; emacsvox-eat-output.el ends here
