;;; emacsvox-text-tree.el --- Recognize text trees for speech -*- lexical-binding: t; -*-

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
;; Shared, conservative interpretation of complete text trees.  Callers own
;; the decision that a region is eligible: this library installs no hooks,
;; reads no renderer properties and starts no speech.  Node offsets and depth
;; are retained independently of speech cleanup for later navigation adapters.

;;; Code:

(require 'subr-x)

(defun emacsvox-text-tree--parse (text)
  "Return node plists for a complete tree or forest in TEXT, or nil.
Each node has zero-based :start, :label-start, :end and :depth entries.
Roots have depth zero.  Every root needs at least two branch lines.
Accept consistent Unicode or ASCII branches with fixed-width indentation.
Reject missing roots, depth jumps, mixed branch styles,
tab indentation and unrelated lines.
TEXT and its properties are never changed."
  (save-match-data
    (catch 'invalid
      (let ((offset 0) nodes root (count 0) (previous-depth 0) width style)
        (dolist (line (split-string text "\n"))
          (let ((end (+ offset (length line))))
            (cond
             ((string-match-p "\\` *\\'" line))
             ((string-match "\\`\\([ │|]*\\)\\([├└]─\\{1,2\\} \\|[|+`]--\\{1,2\\} \\)\\([^ \t].*\\)\\'" line)
              (let* ((indent (match-string 1 line))
                     (branch (match-string 2 line))
                     (label (match-beginning 3))
                     (unit (length branch))
                     (kind (if (memq (aref branch 0) '(?├ ?└)) 'unicode 'ascii))
                     (depth (1+ (/ (length indent) unit))))
                (unless (and root
                             (or (null width) (= width unit))
                             (or (null style) (eq style kind))
                             (zerop (% (length indent) unit))
                             (<= depth (1+ previous-depth))
                             (string-match-p
                              (concat "\\`\\(?:[ " (if (eq kind 'unicode) "│" "|")
                                      "]" (make-string (1- unit) ?\s) "\\)*\\'")
                              indent))
                  (throw 'invalid nil))
                (setq width unit style kind previous-depth depth count (1+ count))
                (push (list :start offset :label-start (+ offset label)
                            :end end :depth depth) nodes)))
             ((and (not (string-match-p "\\`[ \t│├└─|+`]" line))
                   (or (not root) (>= count 2)))
              (setq root t count 0 previous-depth 0 width nil style nil)
              (push (list :start offset :label-start offset :end end :depth 0) nodes))
             (t (throw 'invalid nil)))
            (setq offset (1+ end))))
        (when (and root (>= count 2)) (nreverse nodes))))))

(defun emacsvox-text-tree--parse-paragraphs (text)
  "Return tree nodes from complete blank-separated paragraphs in TEXT.
An ambiguous paragraph remains literal in its entirety.  Separate prose
before or after a tree does not invalidate that tree.  Offsets refer to TEXT."
  (save-match-data
    (let ((start 0) nodes)
      (while (< start (length text))
        (let* ((separator (string-match "\n[ ]*\n" text start))
               (end (or separator (length text)))
               (next (if separator (match-end 0) end)))
          (dolist (node (emacsvox-text-tree--parse (substring text start end)))
            (dolist (key '(:start :label-start :end))
              (plist-put node key (+ start (plist-get node key))))
            (push node nodes))
          (setq start next)))
      (nreverse nodes))))

(defun emacsvox-text-tree--mark-region (start end)
  "Mark confirmed tree paragraphs between START and END without changing text.
Return parsed nodes, or nil if no paragraph is a confirmed tree.
Replace previous tree annotations, including when recognition fails.
Keep depth on labels and prefixes, so copies and line speech retain context.
Callers must supply a complete eligible region, not an arbitrary selection."
  (let ((nodes (emacsvox-text-tree--parse-paragraphs
                (buffer-substring-no-properties start end)))
        identity)
    (dolist (node nodes)
      (when (zerop (plist-get node :depth))
        (setq identity (or (get-text-property (+ start (plist-get node :start))
                                             'emacsvox-text-tree-id)
                           (make-symbol "text-tree"))))
      (plist-put node :tree-id identity))
    (with-silent-modifications
      (remove-text-properties start end
                              '(emacsvox-text-tree-depth nil
                                emacsvox-text-tree-id nil
                                emacsvox-text-tree-prefix nil))
      (dolist (node nodes)
        (let ((begin (+ start (plist-get node :start)))
              (label (+ start (plist-get node :label-start)))
              (finish (+ start (plist-get node :end))))
          (put-text-property begin (min end (1+ finish)) 'emacsvox-text-tree-id
                             (plist-get node :tree-id))
          (put-text-property begin finish 'emacsvox-text-tree-depth
                             (plist-get node :depth))
          (when (< begin label)
            (put-text-property begin label 'emacsvox-text-tree-prefix t)))))
    nodes))

(defun emacsvox-text-tree--speech-text (text)
  "Return TEXT with confirmed tree prefixes omitted from a speech copy.
Preserve label properties, depth and newlines.  Unmarked text is unchanged;
recognition belongs to the caller that has the complete source region."
  (if (not (text-property-not-all
            0 (length text) 'emacsvox-text-tree-prefix nil text))
      text
    (let ((position 0) parts)
      (while (< position (length text))
        (let ((next (next-single-property-change
                     position 'emacsvox-text-tree-prefix text (length text))))
          (unless (get-text-property position 'emacsvox-text-tree-prefix text)
            (push (substring text position next) parts))
          (setq position next)))
      (apply #'concat (nreverse parts)))))

(defun emacsvox-text-tree--indicator (event text &optional depth)
  "Return TEXT annotated as tree feedback EVENT at optional DEPTH.
Only the indicator carries these semantic facts; item labels remain separate.
The presentation layer can change its speech, voice, sound or tone without
changing the label.  This helper constructs data without loading speech."
  (propertize text
              'emacsvox-aural-facts
              (append (list :role 'tree-indicator :events (list event))
                      (when depth (list :tree-depth depth))
                      (when (and (eq event 'tree-level-changed) (natnump depth))
                        ;; Three semitones per level, bounded to three octaves.
                        (list :tree-tone-pitch (* 220.0 (expt 2.0 (/ (min depth 12) 4.0))))))))

(defun emacsvox-text-tree--describe (text &optional previous)
  "Return (SPEECH . CONTEXT) for tree TEXT following PREVIOUS context.
Announce entry, exit and changed depths, omitting branch prefixes.  CONTEXT
is a pair of tree identity and depth, or nil outside a tree.  Callers may
retain it for successive line navigation; continuous reading starts at nil.
Indicators carry separate semantic facts for presentation customization.
This function has no state and leaves TEXT and its properties unchanged."
  (if (not (text-property-not-all
            0 (length text) 'emacsvox-text-tree-id nil text))
      (cons (if previous
                (concat (emacsvox-text-tree--indicator 'tree-exited "End of tree. ") text)
              text) nil)
    (let* ((clean (emacsvox-text-tree--speech-text text))
           (position 0) (context previous) parts)
      (while (< position (length clean))
        (let* ((id (get-text-property position 'emacsvox-text-tree-id clean))
               (depth (get-text-property position 'emacsvox-text-tree-depth clean))
               (next (min (next-single-property-change
                           position 'emacsvox-text-tree-id clean (length clean))
                          (next-single-property-change
                           position 'emacsvox-text-tree-depth clean (length clean))))
               (span (substring clean position next)))
          (cond
           ((and id (integerp depth))
            (unless (eq id (car context))
              (when context
                (push (emacsvox-text-tree--indicator 'tree-exited "End of tree. ") parts))
              (push (emacsvox-text-tree--indicator 'tree-entered "Tree. " depth) parts))
            (when (and (not (equal (cons id depth) context))
                       (or (> depth 0) (eq id (car context))))
              (push (emacsvox-text-tree--indicator
                     'tree-level-changed
                     (if (zerop depth) "Root. " (format "Level %d. " depth)) depth) parts))
            (setq context (cons id depth)))
           ((and context (not id))
            (push (emacsvox-text-tree--indicator 'tree-exited "End of tree. ") parts)
            (setq context nil)))
          (push span parts)
          (setq position next)))
      (cons (apply #'concat (nreverse parts)) context))))

(provide 'emacsvox-text-tree)
;;; emacsvox-text-tree.el ends here
