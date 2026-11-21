;;; emacsvox-mermaid.el --- Explore Mermaid flowcharts with speech -*- lexical-binding: t; -*-

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
;; Experimental flowchart explorer using Mermaid's pinned v13 language parser.
;; Run `make mermaid-deps' once with Node 20 or newer, then invoke
;; `emacsvox-mermaid-explore' in a Mermaid block, region or source buffer.
;; Parsing is asynchronous.  All navigation uses a local graph snapshot.
;; No renderer, browser, source callbacks or Omnivox changes are involved.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defgroup emacsvox-mermaid nil
  "Spoken exploration of Mermaid flowcharts."
  :group 'emacsvox)

(defcustom emacsvox-mermaid-node-program "node"
  "Node executable for the optional Mermaid helper; version 20 or newer."
  :type 'string :group 'emacsvox-mermaid)

(defcustom emacsvox-mermaid-timeout 10
  "Maximum seconds to wait for a Mermaid parse before restarting the helper."
  :type 'number :group 'emacsvox-mermaid)

(defcustom emacsvox-mermaid-connection-speech-limit 3
  "Maximum connections named in a summary, separately for each direction.
Larger sets are announced by count.  Zero always uses counts.  This applies
to node details, arrival summaries, branch explanations and direction commands;
browsing a list always speaks the selected connection's name.  Changes affect
subsequent speech in every explorer without refreshing its diagram."
  :type 'natnum :group 'emacsvox-mermaid)

(defcustom emacsvox-mermaid-explanation-path-limit 5
  "Maximum arrows traced per incoming or outgoing path in an explanation.
Used by `emacsvox-mermaid-explain'.  Trace through nodes with one incoming
and one outgoing arrow, including the boundary where a path starts, splits
or joins.  Speak the result in forward order and announce when earlier steps
were omitted.  Zero disables tracing and keeps immediate connection summaries.
This does not change navigation or the number of connections named, which
`emacsvox-mermaid-connection-speech-limit' controls.  Changes affect subsequent
explanations in every explorer without refreshing."
  :type 'natnum :group 'emacsvox-mermaid)

(defvar emacsvox-mermaid--process nil)
(defvar emacsvox-mermaid--sequence 0)
(defvar emacsvox-mermaid--pending (make-hash-table :test #'eql))

(cl-defstruct (emacsvox-mermaid--view (:constructor emacsvox-mermaid--view-create))
  source start end text graph index current history visited diagnostics analysis places
  (section 'connections) (selection 0) request)

(defvar-local emacsvox-mermaid--view nil)
(defvar-local emacsvox-mermaid--panels nil)
(defvar-local emacsvox-mermaid--panel nil)

(defun emacsvox-mermaid--say (text)
  "Speak TEXT as interruptible navigation feedback."
  (emacsvox-aural-submit
   text :module 'mermaid :occasion 'navigation :lane 'main
   :delivery-policy 'replaceable :interruption-policy 'lane))

(defun emacsvox-mermaid--finish (id response)
  "Complete pending request ID with RESPONSE exactly once."
  (when-let* ((entry (gethash id emacsvox-mermaid--pending)))
    (remhash id emacsvox-mermaid--pending)
    (cancel-timer (car entry))
    (condition-case err
        (funcall (cdr entry) response)
      (error (message "Mermaid response: %s" (error-message-string err))))))

(defun emacsvox-mermaid--fail (reason)
  "Stop the helper and fail its outstanding requests with REASON."
  (when emacsvox-mermaid--process
    (set-process-sentinel emacsvox-mermaid--process #'ignore)
    (set-process-filter emacsvox-mermaid--process #'ignore)
    (when (process-live-p emacsvox-mermaid--process)
      (delete-process emacsvox-mermaid--process))
    (setq emacsvox-mermaid--process nil))
  (let (ids)
    (maphash (lambda (id _entry) (push id ids)) emacsvox-mermaid--pending)
    (dolist (id ids) (emacsvox-mermaid--finish id `((error . ,reason))))))

(defun emacsvox-mermaid--filter (process chunk)
  "Collect complete JSON replies from PROCESS output CHUNK."
  (let ((text (concat (process-get process 'fragment) chunk)))
    (condition-case err
        (progn
          (when (> (length text) (* 8 1024 1024))
            (error "Helper response exceeds 8 MiB"))
          (while (string-match "\n" text)
            (let* ((end (match-beginning 0))
                   (response (json-parse-string
                              (substring text 0 end) :object-type 'alist
                              :array-type 'list :null-object nil :false-object nil)))
              (setq text (substring text (1+ end)))
              (unless (equal 1 (alist-get 'schema response))
                (error "Unsupported helper response"))
              (emacsvox-mermaid--finish (alist-get 'id response) response)))
          (process-put process 'fragment text))
      (error (emacsvox-mermaid--fail (error-message-string err))))))

(defun emacsvox-mermaid--ensure-process ()
  "Return the persistent local parser process, starting it if needed."
  (unless (process-live-p emacsvox-mermaid--process)
    (let* ((directory (expand-file-name "js/mermaid/" emacsvox-directory))
           (default-directory directory)
           (node (executable-find emacsvox-mermaid-node-program)))
      (unless node (user-error "Mermaid needs Node 20 or newer on PATH"))
      (unless (file-exists-p (expand-file-name "node_modules/@mermaid-js/diagram-flowchart/package.json" directory))
        (user-error "Install the optional parser with make mermaid-deps in %s" emacsvox-directory))
      (setq emacsvox-mermaid--process
            (make-process
             :name "emacsvox-mermaid" :buffer nil :noquery t
             :connection-type 'pipe :coding 'utf-8-unix
             :command (list node (expand-file-name "server.mjs" directory))
             :stderr (get-buffer-create " *emacsvox-mermaid-errors*")
             :filter #'emacsvox-mermaid--filter
             :sentinel
             (lambda (process event)
               (when (and (eq process emacsvox-mermaid--process)
                          (not (process-live-p process)))
                 (emacsvox-mermaid--fail
                  (format "Parser stopped: %s. See buffer *emacsvox-mermaid-errors*; check Node 20 or newer"
                          (string-trim event)))))))))
  emacsvox-mermaid--process)

(defun emacsvox-mermaid--request (source callback)
  "Parse SOURCE asynchronously, calling CALLBACK with a JSON alist."
  (when (> (string-bytes source) (* 256 1024))
    (user-error "Mermaid diagrams are limited to 256 KiB in this prototype"))
  (let* ((process (emacsvox-mermaid--ensure-process))
         (id (cl-incf emacsvox-mermaid--sequence))
         (timer (run-at-time
                 emacsvox-mermaid-timeout nil
                 (lambda ()
                   (when (gethash id emacsvox-mermaid--pending)
                     (emacsvox-mermaid--fail "Parsing timed out; press g to retry"))))))
    (puthash id (cons timer callback) emacsvox-mermaid--pending)
    (condition-case err
        (process-send-string
         process (concat (json-serialize `((schema . 1) (id . ,id) (source . ,source))) "\n"))
      (error (emacsvox-mermaid--fail (error-message-string err))))
    id))

(defun emacsvox-mermaid--bounds ()
  "Return the active region, containing Mermaid block, or whole buffer bounds."
  (if (use-region-p) (cons (region-beginning) (region-end))
    (let ((origin (point)) (case-fold-search t) found)
      (save-excursion
        (goto-char (point-min))
        ;; Scan complete fenced blocks, so a nested example inside another
        ;; language's fence is not mistaken for an active Mermaid diagram.
        (while (and (not found)
                    (re-search-forward
                     "^[ \t]*\\(`\\{3,\\}\\|~\\{3,\\}\\|#\\+begin_src\\)[ \t]*\\([^ \t\n]*\\).*" nil t))
          (let* ((opening (match-beginning 0))
                 (fence (match-string-no-properties 1))
                 (language (downcase (match-string-no-properties 2)))
                 (org (string-prefix-p "#" fence))
                 (closing (if org "^[ \t]*#\\+end_src[ \t]*$"
                            (format "^[ \t]*%c\\{%d,\\}[ \t]*$"
                                    (aref fence 0) (length fence))))
                 (start (progn (forward-line 1) (point))))
            (if (re-search-forward closing nil t)
                (when (and (string= language "mermaid")
                           (<= opening origin) (<= origin (line-end-position)))
                  (setq found (cons start (match-beginning 0))))
              (when (and (string= language "mermaid") (>= origin opening))
                (user-error "Mermaid block has no closing delimiter"))))))
      (or found (cons (point-min) (point-max))))))

(defun emacsvox-mermaid--source-text (view)
  "Return VIEW's current marked source, or nil if its buffer is gone."
  (when (buffer-live-p (emacsvox-mermaid--view-source view))
    (with-current-buffer (emacsvox-mermaid--view-source view)
      (save-restriction
        (widen)
        (buffer-substring-no-properties
         (emacsvox-mermaid--view-start view) (emacsvox-mermaid--view-end view))))))

(defun emacsvox-mermaid--node (id)
  "Look up ID in the current explorer."
  (gethash id (emacsvox-mermaid--view-index emacsvox-mermaid--view)))

(defun emacsvox-mermaid--name (id &optional include-id)
  "Return ID's label, adding its identifier only to distinguish duplicates.
With INCLUDE-ID, retain the identifier for explicit searches as well."
  (let* ((node (emacsvox-mermaid--node id))
         (label (alist-get 'label node)))
    (if (or (and include-id (not (equal label id)))
            (cl-some
             (lambda (other)
               (and (not (equal id (alist-get 'id other)))
                    (equal label (alist-get 'label other))))
             (alist-get 'nodes (emacsvox-mermaid--view-graph emacsvox-mermaid--view))))
        (format "%s, %s %s" label
                (if (equal "group" (alist-get 'kind node)) "group" "node") id)
      label)))

(defun emacsvox-mermaid--relations (id section)
  "Return edge and destination pairs for ID in SECTION."
  (let (items)
    (dolist (edge (alist-get 'edges (emacsvox-mermaid--view-graph emacsvox-mermaid--view)))
      (let* ((from (alist-get 'from edge)) (to (alist-get 'to edge))
             (forward (equal "forward" (alist-get 'direction edge)))
             (outgoing (eq section 'outgoing)))
        (cond
         ((and (equal id from) (or outgoing (not forward)))
          (push (cons edge to) items))
         ((and (equal id to) (or (not outgoing) (not forward)))
          (push (cons edge from) items)))))
    (nreverse items)))

(defun emacsvox-mermaid--sentence (text)
  "Finish TEXT as a sentence without doubling its final punctuation."
  (concat text (unless (string-match-p "[.!?]\\'" text) ".")))

(defun emacsvox-mermaid--cycle-p (nodes edges)
  "Return non-nil if NODES and EDGES contain a cycle following arrows.
A two-way connection alone is not a cycle.  Ignore undirected links and
group containment.  Contract two-way trees, then test the remaining arrows."
  (let ((parents (make-hash-table :test #'equal))
        (out (make-hash-table :test #'equal))
        (degree (make-hash-table :test #'equal)) cycle queue (removed 0))
    (dolist (node nodes)
      (let ((id (alist-get 'id node))) (puthash id id parents)))
    (cl-labels ((root (id)
                 (let ((parent (gethash id parents)))
                   (while (not (equal id parent))
                     (setq id parent parent (gethash parent parents)))
                   id)))
      (dolist (edge edges)
        (when (equal "both" (alist-get 'direction edge))
          (let ((from (root (alist-get 'from edge)))
                (to (root (alist-get 'to edge))))
            (if (equal from to) (setq cycle t) (puthash from to parents)))))
      (dolist (node nodes) (puthash (root (alist-get 'id node)) 0 degree))
      (dolist (edge edges)
        (when (equal "forward" (alist-get 'direction edge))
          (let ((from (root (alist-get 'from edge)))
                (to (root (alist-get 'to edge))))
            (if (equal from to) (setq cycle t)
              (push to (gethash from out))
              (puthash to (1+ (gethash to degree)) degree)))))
      (maphash (lambda (id n) (when (zerop n) (push id queue))) degree)
      (while queue
        (let ((id (pop queue)))
          (cl-incf removed)
          (dolist (next (gethash id out))
            (puthash next (1- (gethash next degree)) degree)
            (when (zerop (gethash next degree)) (push next queue)))))
      (or cycle (< removed (hash-table-count degree))))))

(defun emacsvox-mermaid--analyse (graph)
  "Cache adjacency and structural facts for GRAPH without inferring workflow."
  (let ((out (make-hash-table :test #'equal))
        (in (make-hash-table :test #'equal))
        (neighbors (make-hash-table :test #'equal))
        (undirected (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        (nodes (alist-get 'nodes graph)) (edges (alist-get 'edges graph))
        (parts 0) (isolated 0))
    (dolist (edge edges)
      (let ((from (alist-get 'from edge)) (to (alist-get 'to edge)))
        (push to (gethash from neighbors))
        (push from (gethash to neighbors))
        (if (equal "none" (alist-get 'direction edge))
            (progn (puthash from t undirected) (puthash to t undirected))
          (push to (gethash from out))
          (push from (gethash to in))
          (when (equal "both" (alist-get 'direction edge))
            (push from (gethash to out))
            (push to (gethash from in))))))
    ;; Containment joins a diagram's parts, but is never a directed edge.
    (dolist (node nodes)
      (dolist (member (alist-get 'members node))
        (push member (gethash (alist-get 'id node) neighbors))
        (push (alist-get 'id node) (gethash member neighbors))))
    (dolist (node nodes)
      (let ((id (alist-get 'id node)))
        (when (and (equal "node" (alist-get 'kind node))
                   (null (gethash id neighbors)))
          (cl-incf isolated))
        (unless (gethash id seen)
          (cl-incf parts)
          (let ((pending (list id)))
            (while pending
              (let ((next (pop pending)))
                (unless (gethash next seen)
                  (puthash next t seen)
                  (setq pending (append (gethash next neighbors) pending)))))))))
    (list :out out :in in :neighbors neighbors :undirected undirected
          :parts parts :isolated isolated :cycle (emacsvox-mermaid--cycle-p nodes edges))))

(defun emacsvox-mermaid--contexts (id)
  "Return containing groups for ID, outermost first, including ID if a group."
  (let ((seen (make-hash-table :test #'equal)) groups)
    (cl-labels ((walk (key)
                 (unless (gethash key seen)
                   (puthash key t seen)
                   (let ((node (emacsvox-mermaid--node key)))
                     (dolist (parent (alist-get 'groups node)) (walk parent))
                     (when (equal "group" (alist-get 'kind node))
                       (push key groups))))))
      (walk id))
    (nreverse groups)))

(defun emacsvox-mermaid--crossing-text (from to)
  "Describe group boundaries crossed from FROM to TO."
  (let ((old (emacsvox-mermaid--contexts from))
        (new (emacsvox-mermaid--contexts to)))
    (concat
     (mapconcat (lambda (id) (concat (emacsvox-mermaid--sentence
                                     (concat "Leaving " (emacsvox-mermaid--name id))) " "))
                (reverse (cl-remove-if (lambda (id) (member id new)) old)) "")
     (mapconcat (lambda (id) (concat (emacsvox-mermaid--sentence
                                     (concat "Entering " (emacsvox-mermaid--name id))) " "))
                (cl-remove-if (lambda (id) (or (member id old) (equal id to))) new) ""))))

(defun emacsvox-mermaid--items ()
  "Return selectable edge/destination pairs for the current section."
  (let* ((view emacsvox-mermaid--view)
         (id (emacsvox-mermaid--view-current view)))
    (pcase (emacsvox-mermaid--view-section view)
      ('connections
       (let* ((out (emacsvox-mermaid--relations id 'outgoing))
              (out-edges (make-hash-table :test #'eq))
              (undirected (cl-remove-if-not
                           (lambda (item) (equal "none" (alist-get 'direction (car item)))) out))
              (directed (cl-remove-if
                         (lambda (item) (equal "none" (alist-get 'direction (car item)))) out)))
         (dolist (item out) (puthash (car item) t out-edges))
         ;; Each physical connection occurs once, including self and two-way links.
         (append directed
                 (cl-remove-if (lambda (item) (gethash (car item) out-edges))
                               (emacsvox-mermaid--relations id 'incoming))
                 undirected)))
      ('all (mapcar (lambda (n) (cons nil (alist-get 'id n)))
                    (alist-get 'nodes (emacsvox-mermaid--view-graph view))))
      ('members (mapcar (lambda (member) (cons nil member))
                       (alist-get 'members (emacsvox-mermaid--node id))))
      (section (let ((items (emacsvox-mermaid--relations id section)))
                 (append (cl-remove-if (lambda (item) (equal "none" (alist-get 'direction (car item)))) items)
                         (cl-remove-if-not (lambda (item) (equal "none" (alist-get 'direction (car item)))) items)))))))

(defun emacsvox-mermaid--item-section (item)
  "Return ITEM's direction in the combined list."
  (cond
   ((equal "none" (alist-get 'direction (car item))) 'undirected)
   ((or (equal "both" (alist-get 'direction (car item)))
        (equal (alist-get 'from (car item))
               (emacsvox-mermaid--view-current emacsvox-mermaid--view))) 'outgoing)
   (t 'incoming)))

(defun emacsvox-mermaid--item-text (item &optional summary)
  "Describe ITEM without following it; omit repeated direction/style in SUMMARY."
  (let* ((edge (car item)) (id (cdr item))
         (label (alist-get 'label edge)) (stroke (alist-get 'stroke edge))
         (arrow (alist-get 'arrow edge)))
    (if (not edge) (emacsvox-mermaid--name id)
      (string-join
       (delq nil
             (list
              (concat
               (unless (string-empty-p label) (concat label ": "))
               (pcase (alist-get 'direction edge)
                 ("both" "Both directions to ")
                 ("none" (unless summary "Undirected connection to "))
                 (_ (when (and (not summary)
                               (or (eq 'incoming (emacsvox-mermaid--view-section emacsvox-mermaid--view))
                                   (eq 'incoming (emacsvox-mermaid--item-section item))))
                      "From ")))
               (emacsvox-mermaid--name id))
              (unless (or summary (equal stroke "normal")) stroke)
              (unless (or summary (member arrow '("arrow_point" "double_arrow_point" "arrow_open")))
                (concat "marker " (replace-regexp-in-string "_" " " arrow)))
              (when (equal id (emacsvox-mermaid--view-current emacsvox-mermaid--view)) "self link")))
       ". "))))

(defun emacsvox-mermaid--connection-summary (section)
  "Summarize SECTION's connections by name or count using the speech limit."
  (let* ((id (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (items (cl-remove-if
                 (lambda (item) (if (eq section 'undirected)
                                    (not (equal "none" (alist-get 'direction (car item))))
                                  (equal "none" (alist-get 'direction (car item)))))
                 (emacsvox-mermaid--relations id (if (eq section 'undirected) 'outgoing section))))
         (count (length items)) (label (symbol-name section)))
    (cond
     ((zerop count) (format "No %s." label))
     ((> count emacsvox-mermaid-connection-speech-limit) (format "%d %s." count label))
     (t (emacsvox-mermaid--sentence
         (concat (capitalize label) ": "
                 (mapconcat (lambda (item) (emacsvox-mermaid--item-text item t)) items "; ")))))))

(defun emacsvox-mermaid--undirected-summary ()
  "Return an undirected summary with a leading space when links exist."
  (when (cl-some (lambda (item) (equal "none" (alist-get 'direction (car item))))
                 (emacsvox-mermaid--relations
                  (emacsvox-mermaid--view-current emacsvox-mermaid--view) 'outgoing))
    (concat " " (emacsvox-mermaid--connection-summary 'undirected))))

(defun emacsvox-mermaid--selection-info (&optional index)
  "Return the selected section, zero-based position and section size at INDEX."
  (let* ((view emacsvox-mermaid--view)
         (items (emacsvox-mermaid--items))
         (index (or index (emacsvox-mermaid--view-selection view)))
         (section (emacsvox-mermaid--view-section view)))
    (if (and items (eq section 'connections))
        (let* ((item (nth index items))
               (direction (emacsvox-mermaid--item-section item))
               (matches (cl-remove-if-not
                         (lambda (other) (eq direction (emacsvox-mermaid--item-section other))) items)))
          (list direction (cl-position item matches :test #'equal) (length matches)))
      (list section index (length items)))))

(defun emacsvox-mermaid--selection-heading ()
  "Return the spoken section name for the current selection."
  (capitalize (symbol-name (car (emacsvox-mermaid--selection-info)))))

(defun emacsvox-mermaid--selection-text ()
  "Describe the selected item and its position in the current section."
  (let* ((items (emacsvox-mermaid--items))
         (index (emacsvox-mermaid--view-selection emacsvox-mermaid--view))
         (info (emacsvox-mermaid--selection-info)))
    (if items
        (format "%s %d of %d."
                (emacsvox-mermaid--sentence (emacsvox-mermaid--item-text (nth index items)))
                (1+ (cadr info)) (caddr info))
      "None.")))

(defun emacsvox-mermaid--brief-text ()
  "Describe arrival without repeating full node details."
  (let* ((id (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (node (emacsvox-mermaid--node id)))
    (concat (emacsvox-mermaid--sentence (emacsvox-mermaid--name id)) " "
            (if (equal "group" (alist-get 'kind node))
                (format "Group. %d members. " (length (alist-get 'members node)))
              (pcase (alist-get 'shape node)
                ("diamond" "Decision. ") ("cyl" "Database. ") ("stadium" "Terminal. ")))
            (emacsvox-mermaid--connection-summary 'outgoing)
            (emacsvox-mermaid--undirected-summary))))

(defun emacsvox-mermaid--current-text ()
  "Describe the current node and its immediate context."
  (let* ((id (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (node (emacsvox-mermaid--node id))
         (groups (alist-get 'groups node)))
    (format "%s %s. %s %s%s%s%s"
            (emacsvox-mermaid--sentence (emacsvox-mermaid--name id)) (alist-get 'shape node)
            (emacsvox-mermaid--connection-summary 'outgoing)
            (emacsvox-mermaid--connection-summary 'incoming)
            (or (emacsvox-mermaid--undirected-summary) "")
            (if (equal "group" (alist-get 'kind node))
                (format " %d members." (length (alist-get 'members node))) "")
            (if groups (concat " In " (mapconcat #'emacsvox-mermaid--name groups "; ") ".") ""))))

(defun emacsvox-mermaid--overview-text ()
  "Describe the graph without enumerating every node."
  (let* ((graph (emacsvox-mermaid--view-graph emacsvox-mermaid--view))
         (nodes (alist-get 'nodes graph))
         (groups (cl-count "group" nodes :key (lambda (n) (alist-get 'kind n)) :test #'equal))
         (analysis (emacsvox-mermaid--view-analysis emacsvox-mermaid--view))
         (hidden (alist-get 'hiddenEdges graph)))
    (format "%s %d nodes, %d groups, %d connections. Layout %s.%s%s%s%s%s"
            (emacsvox-mermaid--sentence (alist-get 'title graph)) (- (length nodes) groups) groups
            (length (alist-get 'edges graph))
            (pcase (alist-get 'direction graph)
              ("TB" "top to bottom") ("BT" "bottom to top")
              ("LR" "left to right") (_ "right to left"))
            (if (> hidden 0) (format " %d invisible layout links omitted." hidden) "")
            (if (> (plist-get analysis :parts) 1)
                (format " %d separate parts." (plist-get analysis :parts)) "")
            (if (> (plist-get analysis :isolated) 0)
                (format " %d isolated node%s." (plist-get analysis :isolated)
                        (if (= 1 (plist-get analysis :isolated)) "" "s")) "")
            (if (plist-get analysis :cycle) " Contains a directed cycle." "")
            (if (string-empty-p (alist-get 'description graph)) ""
              (concat " " (alist-get 'description graph))))))

(defun emacsvox-mermaid--branch-reach (start origin first-edge arcs)
  "Find arrow distances from START, stopping at ORIGIN, using ARCS.
Return distances and whether the branch can return to ORIGIN.  Do not
reverse FIRST-EDGE: a two-way connection alone does not make a loop."
  (let ((distances (make-hash-table :test #'equal))
        (front (unless (equal start origin) (list start)))
        (distance 0) (returns (equal start origin)))
    (when front (puthash start 0 distances))
    (while front
      (let (next)
        (dolist (id front)
          (dolist (arc (gethash id arcs))
            (unless (eq first-edge (car arc))
              (let ((target (cdr arc)))
                (if (equal target origin) (setq returns t)
                  (unless (gethash target distances)
                    (puthash target (1+ distance) distances)
                    (push target next)))))))
        (setq front (nreverse next))
        (cl-incf distance)))
    (list :distances distances :returns returns)))

(defun emacsvox-mermaid--common-branch-node (searches nodes)
  "Choose a nearby node in NODES reached by every branch in SEARCHES.
Minimize the longest branch distance, then the total distance; source order
breaks ties.  Distances stop at the original fork, so it cannot create a join."
  (let (best best-longest best-total)
    (dolist (node nodes)
      (let* ((id (alist-get 'id node))
             (distances (mapcar (lambda (search)
                                  (gethash id (plist-get search :distances))) searches)))
        (when (cl-every #'numberp distances)
          (let ((longest (apply #'max distances)) (total (apply #'+ distances)))
            (when (or (null best) (< longest best-longest)
                      (and (= longest best-longest) (< total best-total)))
              (setq best id best-longest longest best-total total))))))
    best))

(defun emacsvox-mermaid--must-reach (destination origin analysis)
  "Find nodes whose every arrow path reaches DESTINATION before ORIGIN.
Starting at DESTINATION, admit a predecessor only after all its outgoing
arrows lead to admitted nodes.  Other endpoints and cycles remain outside
the result: reaching a shared node is not guaranteed by reachability alone."
  (let ((remaining (make-hash-table :test #'equal))
        (certain (make-hash-table :test #'equal))
        (pending (list destination)))
    (maphash (lambda (id next) (puthash id (length next) remaining))
             (plist-get analysis :out))
    (puthash destination t certain)
    (while pending
      (dolist (previous (gethash (pop pending) (plist-get analysis :in)))
        (unless (or (equal previous origin) (gethash previous certain))
          (let ((left (1- (gethash previous remaining))))
            (puthash previous left remaining)
            (when (zerop left)
              (puthash previous t certain)
              (push previous pending))))))
    certain))

(defun emacsvox-mermaid--incoming-path (edge origin analysis)
  "Trace backward from forward EDGE into ORIGIN using ANALYSIS.
Return edges in forward order and the reason tracing stopped.  Include the
nearest structural boundary, but never repeat a node or cross a two-way link."
  (let ((edges (list edge)) (id (alist-get 'from edge)) (count 1)
        (seen (make-hash-table :test #'equal)) stop)
    (puthash origin t seen)
    (while (not stop)
      (puthash id t seen)
      (let ((previous (cl-remove-if
                       (lambda (item) (equal "none" (alist-get 'direction (car item))))
                       (emacsvox-mermaid--relations id 'incoming))))
        (cond
         ((cl-some (lambda (item) (equal "both" (alist-get 'direction (car item)))) previous)
          (setq stop 'two-way))
         ((not (and (= 1 (length (gethash id (plist-get analysis :in))))
                    (= 1 (length (gethash id (plist-get analysis :out))))))
          (setq stop 'boundary))
         ((>= count emacsvox-mermaid-explanation-path-limit) (setq stop 'limit))
         (t (let* ((next (caar previous)) (source (alist-get 'from next)))
              (if (gethash source seen) (setq stop 'loop)
                (push next edges)
                (setq id source)
                (cl-incf count)))))))
    (list :edges edges :stop stop)))

(defun emacsvox-mermaid--incoming-path-text (path prefix common named)
  "Describe PATH in forward order with PREFIX and optional COMMON source.
When NAMED is non-nil, a unique branch label supplies context for otherwise
duplicated node labels.  Retain IDs for duplicates within this path and groups."
  (let* ((edges (plist-get path :edges))
         (ids (mapcar (lambda (edge) (alist-get 'from edge)) edges))
         (labels (mapcar (lambda (id) (alist-get 'label (emacsvox-mermaid--node id))) ids))
         (last-label (alist-get 'label (car (last edges))))
         parts)
    (cl-labels ((name (id)
                  (let* ((node (emacsvox-mermaid--node id)) (label (alist-get 'label node)))
                    (if (and named (equal "node" (alist-get 'kind node))
                             (= 1 (cl-count label labels :test #'equal)))
                        label (emacsvox-mermaid--name id)))))
      (unless common (push (name (car ids)) parts))
      (dolist (edge (butlast edges))
        (let ((label (alist-get 'label edge)))
          (push (concat (unless (or (string-empty-p label) (and named (eq edge (car edges))))
                          (concat label ": "))
                        (name (alist-get 'to edge))) parts)))
      (unless (or (string-empty-p last-label) (and named (= 1 (length edges))))
        (push (concat last-label ": here") parts)))
    (concat
     (emacsvox-mermaid--sentence
      (if parts (concat prefix ": " (string-join (nreverse parts) ", then "))
        (concat prefix " leads directly here")))
     (pcase (plist-get path :stop)
       ('limit " Earlier steps omitted.")
       ('loop " Backward trace stopped at a loop.")
       ('two-way " Backward trace stopped at a two-way connection.")
       (_ "")))))

(defun emacsvox-mermaid--outgoing-path (item origin analysis)
  "Trace forward ITEM from ORIGIN through straight sequences in ANALYSIS."
  (let ((edges (list (car item))) (id (cdr item)) (count 1)
        (seen (make-hash-table :test #'equal)) stop)
    (puthash origin t seen)
    (while (not stop)
      (let ((next (cl-remove-if
                   (lambda (entry) (equal "none" (alist-get 'direction (car entry))))
                   (emacsvox-mermaid--relations id 'outgoing))))
        (cond
         ((gethash id seen) (setq stop 'loop))
         ((cl-some (lambda (entry) (equal "both" (alist-get 'direction (car entry)))) next)
          (setq stop 'two-way))
         ((not (and (= 1 (length (gethash id (plist-get analysis :in))))
                    (= 1 (length (gethash id (plist-get analysis :out))))))
          (setq stop 'boundary))
         ((>= count emacsvox-mermaid-explanation-path-limit) (setq stop 'limit))
         ((gethash (cdar next) seen) (setq stop 'loop))
         (t (puthash id t seen)
            (push (caar next) edges)
            (setq id (cdar next))
            (cl-incf count)))))
    (list :edges (nreverse edges) :stop stop)))

(defun emacsvox-mermaid--outgoing-path-text (item prefix &optional common)
  "Describe forward ITEM with PREFIX.
Leave COMMON to the join summary when it follows intermediate steps."
  (let* ((origin (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (edge (car item)) (target (cdr item)) (label (alist-get 'label edge))
         (path (and (> emacsvox-mermaid-explanation-path-limit 0)
                    (equal "forward" (alist-get 'direction edge))
                    (not (equal origin target))
                    (emacsvox-mermaid--outgoing-path
                     item origin (emacsvox-mermaid--view-analysis emacsvox-mermaid--view))))
         (edges (plist-get path :edges))
         (named (and (not (string-empty-p label))
                     (= 1 (cl-count (downcase label) (emacsvox-mermaid--relations origin 'outgoing)
                                    :key (lambda (entry) (downcase (alist-get 'label (car entry))))
                                    :test #'equal))))
         parts)
    (when (and (> (length edges) 1) (equal common (alist-get 'to (car (last edges)))))
      (setq edges (butlast edges)))
    (if (> (length edges) 1)
        (let ((labels (mapcar (lambda (entry) (alist-get 'label (emacsvox-mermaid--node (alist-get 'to entry)))) edges)))
          (dolist (entry edges)
            (let* ((id (alist-get 'to entry)) (node (emacsvox-mermaid--node id))
                   (node-label (alist-get 'label node)) (edge-label (alist-get 'label entry)))
              (push (concat
                     (unless (or (eq entry edge) (string-empty-p edge-label)) (concat edge-label ": "))
                     (if (and named (equal "node" (alist-get 'kind node))
                              (= 1 (cl-count node-label labels :test #'equal)))
                         node-label (emacsvox-mermaid--name id))) parts)))
          (concat (emacsvox-mermaid--sentence
                   (format "%s: %s" (if named (format "The %s path" label) prefix)
                           (string-join (nreverse parts) ", then ")))
                  (when (eq 'limit (plist-get path :stop)) " Later steps omitted.")))
      (concat
       (emacsvox-mermaid--sentence
        (cond ((equal target origin) (concat prefix " is a self loop"))
              ((equal "both" (alist-get 'direction edge))
               (format "%s is a two-way connection to %s" prefix (emacsvox-mermaid--name target)))
              ((equal "none" (alist-get 'direction edge))
               (format "%s is an undirected connection to %s" prefix (emacsvox-mermaid--name target)))
              (t (format "%s leads to %s" prefix (emacsvox-mermaid--name target)))))
       (when (eq 'limit (plist-get path :stop)) " Later steps omitted.")))))

(defun emacsvox-mermaid--incoming-explanation (incoming origin analysis)
  "Describe INCOMING paths to ORIGIN using ANALYSIS and the speech limits."
  (let ((count (length incoming)) (parents (delete-dups (mapcar #'cdr incoming))))
    (cond
     ((zerop count) nil)
     ((> count emacsvox-mermaid-connection-speech-limit)
      (format "%d incoming connection%s%s" count (if (= count 1) "" "s")
              (if (> (length parents) 1) " meet here." ".")))
     ((or (zerop emacsvox-mermaid-explanation-path-limit)
          (cl-some (lambda (item) (not (equal "forward" (alist-get 'direction (car item))))) incoming))
      (when (> (length parents) 1)
        (format "Arrows from %s and %s meet here."
                (mapconcat #'emacsvox-mermaid--name (butlast parents) ", ")
                (emacsvox-mermaid--name (car (last parents))))))
     (t
      (let* ((paths (mapcar (lambda (item) (emacsvox-mermaid--incoming-path (car item) origin analysis)) incoming))
             (start (alist-get 'from (car (plist-get (car paths) :edges))))
             (common (and (> count 1)
                          (cl-every (lambda (path)
                                      (and (not (memq (plist-get path :stop) '(limit loop)))
                                           (equal start (alist-get 'from (car (plist-get path :edges)))))) paths)))
             (branch-labels (when common
                              (mapcar (lambda (item) (downcase (alist-get 'label (car item))))
                                      (emacsvox-mermaid--relations start 'outgoing))))
             parts)
        (when (> count 1)
          (push (format "%s%s meet here."
                        (if (= count 2) "Two" (number-to-string count))
                        (if common (concat " paths from " (emacsvox-mermaid--name start))
                          " incoming paths")) parts))
        (cl-loop for path in paths for index from 1 do
                 (let* ((label (alist-get 'label (car (plist-get path :edges))))
                        (named (and common (not (string-empty-p label))
                                    (= 1 (cl-count (downcase label) branch-labels :test #'equal))))
                        (prefix (cond (named (format "The %s path" label))
                                      ((= count 1) "Incoming path")
                                      (t (format "Path %d" index)))))
                   (push (emacsvox-mermaid--incoming-path-text path prefix common named) parts)))
        (string-join (nreverse parts) " "))))))

(defun emacsvox-mermaid--explanation-text ()
  "Describe the current node's branches, joins and reachable arrow cycles."
  (let* ((view emacsvox-mermaid--view)
         (graph (emacsvox-mermaid--view-graph view))
         (analysis (emacsvox-mermaid--view-analysis view))
         (origin (emacsvox-mermaid--view-current view))
         (nodes (alist-get 'nodes graph)) (edges (alist-get 'edges graph))
         (outgoing (cl-remove-if
                    (lambda (item) (equal "none" (alist-get 'direction (car item))))
                    (emacsvox-mermaid--relations origin 'outgoing)))
         (incoming (cl-remove-if
                    (lambda (item) (or (equal "none" (alist-get 'direction (car item)))
                                       (equal origin (cdr item))))
                    (emacsvox-mermaid--relations origin 'incoming)))
         (count (length outgoing))
         (named (<= count emacsvox-mermaid-connection-speech-limit))
         (arcs (make-hash-table :test #'equal))
         (reachable (make-hash-table :test #'equal))
         searches parts)
    (dolist (edge edges)
      (unless (equal "none" (alist-get 'direction edge))
        (push (cons edge (alist-get 'to edge)) (gethash (alist-get 'from edge) arcs))
        (when (equal "both" (alist-get 'direction edge))
          (push (cons edge (alist-get 'from edge)) (gethash (alist-get 'to edge) arcs)))))
    (setq searches (mapcar (lambda (item)
                            (emacsvox-mermaid--branch-reach (cdr item) origin (car item) arcs))
                          outgoing))
    (push (emacsvox-mermaid--sentence (emacsvox-mermaid--name origin)) parts)
    (when-let* ((description (emacsvox-mermaid--incoming-explanation incoming origin analysis)))
      (push description parts))
    (cond
     ((zerop count) (push "No outgoing arrows." parts))
     ((not named) (push (format "%d outgoing connections." count) parts))
     (t (let ((common (and (> count 1) (emacsvox-mermaid--common-branch-node searches nodes))))
          (cl-loop for item in outgoing for search in searches for index from 1 do
                 (let* ((edge (car item)) (target (cdr item)) (label (alist-get 'label edge))
                        (name (if (not (string-empty-p label)) label
                                (if (= count 1) "The outgoing connection"
                                  (format "Connection %d" index)))))
                   (push (emacsvox-mermaid--outgoing-path-text item name common) parts)
                   (when (and (plist-get search :returns) (not (equal target origin)))
                     (push "That branch can loop back here." parts)))))))
    (when (> count 1)
      (let* ((common (emacsvox-mermaid--common-branch-node searches nodes))
             (subject (if (= count 2) "both branches" (format "all %d branches" count))))
        (push
         (cond
          ((cl-every (lambda (item) (equal (cdr item) (cdar outgoing))) outgoing)
           (emacsvox-mermaid--sentence
            (format "%s connections lead to %s"
                    (if (= count 2) "Both" (format "All %d" count))
                    (emacsvox-mermaid--name (cdar outgoing)))))
          ((null common) "No shared destination is reachable along arrows without returning here.")
          (t (let* ((certain (emacsvox-mermaid--must-reach common origin analysis))
                    (guaranteed (cl-every (lambda (item) (gethash (cdr item) certain)) outgoing)))
               (concat (emacsvox-mermaid--sentence
                        (format "Following arrows, %s %s %s"
                                subject (if guaranteed "rejoin at" "can reach")
                                (emacsvox-mermaid--name common)))
                       (unless guaranteed " Other paths can avoid it."))))) parts)))
    (when (and (plist-get analysis :cycle)
               (not (and named (cl-some (lambda (search) (plist-get search :returns)) searches))))
      (puthash origin t reachable)
      (dolist (search searches)
        (maphash (lambda (id _distance) (puthash id t reachable)) (plist-get search :distances)))
      (when (emacsvox-mermaid--cycle-p
             (cl-remove-if-not (lambda (node) (gethash (alist-get 'id node) reachable)) nodes)
             (cl-remove-if-not (lambda (edge)
                                 (and (gethash (alist-get 'from edge) reachable)
                                      (gethash (alist-get 'to edge) reachable))) edges))
        (push "A directed cycle is reachable from here." parts)))
    (when-let* ((undirected (emacsvox-mermaid--undirected-summary)))
      (push (string-trim undirected) parts))
    (string-join (nreverse parts) " ")))

(defun emacsvox-mermaid--require-graph ()
  "Reject navigation before a successful parse."
  (when (and emacsvox-mermaid--view
             (emacsvox-mermaid--view-request emacsvox-mermaid--view))
    (user-error "Parsing is still in progress"))
  (unless (and emacsvox-mermaid--view
               (emacsvox-mermaid--view-current emacsvox-mermaid--view))
    (user-error "No graph available; press g to retry parsing")))

(defun emacsvox-mermaid--panel-parent ()
  "Return this panel's explorer, rejecting closed or replaced snapshots."
  (let ((parent (plist-get emacsvox-mermaid--panel :parent))
        (owner (plist-get emacsvox-mermaid--panel :owner))
        (snapshot (plist-get emacsvox-mermaid--panel :snapshot)))
    (unless (buffer-live-p parent) (user-error "The diagram explorer is closed"))
    (unless (and (eq owner (buffer-local-value 'emacsvox-mermaid--view parent))
                 (eq (emacsvox-mermaid--view-graph owner) (emacsvox-mermaid--view-graph snapshot))
                 (not (emacsvox-mermaid--view-request owner))
                 (emacsvox-mermaid--view-current owner))
      (user-error "Diagram refreshed; reopen this explanation or route"))
    parent))

(defun emacsvox-mermaid--panel-index ()
  "Return the selected row, including selection made by ordinary point movement."
  (or (get-text-property (point) 'emacsvox-mermaid-panel-item)
      (plist-get emacsvox-mermaid--panel :index)))

(defun emacsvox-mermaid--panel-text (row)
  "Describe ROW using the panel's captured diagram and its own path limit."
  (let* ((emacsvox-mermaid--view (plist-get emacsvox-mermaid--panel :snapshot))
         (emacsvox-mermaid-explanation-path-limit (or (plist-get row :limit) 1))
         (item (plist-get row :item)) (edge (car item))
         (origin (emacsvox-mermaid--view-current emacsvox-mermaid--view)))
    (pcase (plist-get row :kind)
      ('summary (plist-get row :text))
      ('outgoing
       (emacsvox-mermaid--outgoing-path-text
        item (if (string-empty-p (alist-get 'label edge)) "Outgoing path" (alist-get 'label edge))))
      ('incoming
       (let* ((path (emacsvox-mermaid--incoming-path edge origin (emacsvox-mermaid--view-analysis emacsvox-mermaid--view)))
              (first (car (plist-get path :edges))) (label (alist-get 'label first))
              (start (alist-get 'from first))
              (named (and (not (memq (plist-get path :stop) '(limit loop)))
                          (not (string-empty-p label))
                          (= 1 (cl-count (downcase label) (emacsvox-mermaid--relations start 'outgoing)
                                         :key (lambda (entry) (downcase (alist-get 'label (car entry))))
                                         :test #'equal)))))
         (emacsvox-mermaid--incoming-path-text
          path (if named (format "Incoming %s path from %s" label (emacsvox-mermaid--name start)) "Incoming path")
          named named)))
      ('link (emacsvox-mermaid--item-text item))
      ('step
       (emacsvox-mermaid--sentence
        (concat (unless (string-empty-p (alist-get 'label edge)) (concat (alist-get 'label edge) ": "))
                (emacsvox-mermaid--name (plist-get row :from)) " to " (emacsvox-mermaid--name (cdr item))
                (when (equal "both" (alist-get 'direction edge)) ". Two-way connection")))))))

(defun emacsvox-mermaid--panel-render ()
  "Render explanation rows or route steps without changing the explorer."
  (let ((inhibit-read-only t) (index (plist-get emacsvox-mermaid--panel :index))
        (route (eq 'route (plist-get emacsvox-mermaid--panel :kind))))
    (erase-buffer)
    (insert (plist-get emacsvox-mermaid--panel :title) "\n\n")
    (if route
        (insert (format "%d of %d steps followed. One route along arrows; conditions are not evaluated.\n"
                        (plist-get emacsvox-mermaid--panel :progress)
                        (length (plist-get emacsvox-mermaid--panel :items)))
                "Up/down preview. Return/right follow the next step. b/left retrace.\n")
      (insert "Up/down browse. Return, right or + expand the selected path.\n"))
    (insert ". repeats the selected item. q returns to the explorer.\n\n")
    (cl-loop for row in (plist-get emacsvox-mermaid--panel :items) for n from 0 do
             (insert (propertize (concat (emacsvox-mermaid--panel-text row) "\n\n")
                                 'emacsvox-mermaid-panel-item n)))
    (goto-char (point-min))
    (when-let* ((position (text-property-any (point-min) (point-max) 'emacsvox-mermaid-panel-item index)))
      (goto-char position))))

(defun emacsvox-mermaid-panel-current ()
  "Speak the selected explanation row or route step."
  (interactive)
  (emacsvox-mermaid--panel-parent)
  (let* ((index (emacsvox-mermaid--panel-index)) (rows (plist-get emacsvox-mermaid--panel :items)))
    (setf (plist-get emacsvox-mermaid--panel :index) index)
    (emacsvox-mermaid--say (format "%s %d of %d." (emacsvox-mermaid--panel-text (nth index rows))
                                  (1+ index) (length rows)))))

(defun emacsvox-mermaid-panel-next (&optional previous)
  "Browse the next panel row, or the preceding one with PREVIOUS."
  (interactive)
  (emacsvox-mermaid--panel-parent)
  (let* ((rows (plist-get emacsvox-mermaid--panel :items))
         (old (emacsvox-mermaid--panel-index)) (index (+ old (if previous -1 1)))
         (kind (plist-get (nth index rows) :kind)))
    (unless (<= 0 index (1- (length rows))) (user-error "End of available items"))
    (setf (plist-get emacsvox-mermaid--panel :index) index)
    (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-panel-item index))
    (emacsvox-mermaid--say
     (format "%s%s %d of %d."
             (if (eq kind (plist-get (nth old rows) :kind)) "" (concat (capitalize (symbol-name kind)) ". "))
             (emacsvox-mermaid--panel-text (nth index rows)) (1+ index) (length rows)))))

(defun emacsvox-mermaid-panel-previous ()
  "Browse the preceding explanation row or route step."
  (interactive) (emacsvox-mermaid-panel-next t))

(defun emacsvox-mermaid-panel-expand ()
  "Extend only the selected explanation path, preserving global speech limits."
  (interactive)
  (emacsvox-mermaid--panel-parent)
  (let* ((index (emacsvox-mermaid--panel-index))
         (row (nth index (plist-get emacsvox-mermaid--panel :items)))
         (kind (plist-get row :kind))
         (emacsvox-mermaid--view (plist-get emacsvox-mermaid--panel :snapshot))
         (origin (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (analysis (emacsvox-mermaid--view-analysis emacsvox-mermaid--view))
         (item (plist-get row :item))
         (emacsvox-mermaid-explanation-path-limit (or (plist-get row :limit) 1)))
    (unless (and (memq kind '(incoming outgoing)) (equal "forward" (alist-get 'direction (car item))))
      (user-error "Select an incoming or outgoing path to expand"))
    (let ((path (if (eq kind 'incoming) (emacsvox-mermaid--incoming-path (car item) origin analysis)
                  (emacsvox-mermaid--outgoing-path item origin analysis))))
      (unless (eq 'limit (plist-get path :stop))
        (user-error "No omitted straight steps; this path has reached a boundary")))
    (setf (plist-get row :limit) (min (1+ (length (alist-get 'nodes (emacsvox-mermaid--view-graph emacsvox-mermaid--view))))
                                    (* 2 emacsvox-mermaid-explanation-path-limit))
          (plist-get emacsvox-mermaid--panel :index) index)
    (emacsvox-mermaid--panel-render)
    (emacsvox-mermaid-panel-current)))

(defun emacsvox-mermaid--route-steps (origin destination)
  "Return a shortest arrow route from ORIGIN to DESTINATION, or nil.
Preserve physical edges and their labels.  Source order breaks ties."
  (let ((arcs (make-hash-table :test #'equal)) (seen (make-hash-table :test #'equal))
        (previous (make-hash-table :test #'equal)) (front (list origin)) back steps)
    (dolist (edge (alist-get 'edges (emacsvox-mermaid--view-graph emacsvox-mermaid--view)))
      (unless (equal "none" (alist-get 'direction edge))
        (push (cons edge (alist-get 'to edge)) (gethash (alist-get 'from edge) arcs))
        (when (equal "both" (alist-get 'direction edge))
          (push (cons edge (alist-get 'from edge)) (gethash (alist-get 'to edge) arcs)))))
    (maphash (lambda (id items) (puthash id (nreverse items) arcs)) arcs)
    (puthash origin t seen)
    (while (and (or front back) (not (gethash destination seen)))
      (unless front (setq front (nreverse back) back nil))
      (let ((id (pop front)))
        (dolist (item (gethash id arcs))
          (unless (gethash (cdr item) seen)
            (puthash (cdr item) t seen)
            (puthash (cdr item) (cons id item) previous)
            (push (cdr item) back)))))
    (when (gethash destination seen)
      (let ((id destination))
        (while (not (equal id origin))
          (let ((entry (gethash id previous)))
            (push (list :kind 'step :from (car entry) :item (cdr entry)) steps)
            (setq id (car entry))))))
    steps))

(defun emacsvox-mermaid-panel-step (&optional back)
  "Follow the next route step, or retrace the last followed step with BACK."
  (interactive)
  (let* ((parent (emacsvox-mermaid--panel-parent))
         (panel emacsvox-mermaid--panel) (owner (plist-get panel :owner))
         (steps (plist-get panel :items)) (progress (plist-get panel :progress)) speech)
    (unless (eq 'route (plist-get panel :kind)) (user-error "This is not a route"))
    (unless (and (equal (emacsvox-mermaid--view-current owner)
                        (if (zerop progress) (plist-get panel :origin)
                          (cdr (plist-get (nth (1- progress) steps) :item))))
                 (eq (emacsvox-mermaid--view-history owner) (plist-get panel :history)))
      (user-error "Explorer moved outside this route; use q, then r to choose a new route"))
    (when (if back (zerop progress) (= progress (length steps)))
      (user-error (if back "At the route's starting point" "Route complete")))
    (cl-letf (((symbol-function 'emacsvox-mermaid--say) (lambda (text) (setq speech text))))
      (with-current-buffer parent
        (if back (emacsvox-mermaid-back)
          (emacsvox-mermaid--traverse (plist-get (nth progress steps) :item)))
        (dolist (window (get-buffer-window-list parent nil t)) (set-window-point window (point)))))
    (setq progress (+ progress (if back -1 1)))
    (setf (plist-get panel :progress) progress
          (plist-get panel :history) (emacsvox-mermaid--view-history owner)
          (plist-get panel :index) (min progress (1- (length steps))))
    (emacsvox-mermaid--panel-render)
    (emacsvox-mermaid--say
     (format "%s %s" speech (if (= progress (length steps)) "Route complete."
                              (format "%d of %d route steps followed." progress (length steps)))))))

(defun emacsvox-mermaid-panel-back ()
  "Retrace one step followed through this route."
  (interactive) (emacsvox-mermaid-panel-step t))

(defun emacsvox-mermaid-panel-activate ()
  "Expand an explanation path or follow the next route step."
  (interactive)
  (if (eq 'route (plist-get emacsvox-mermaid--panel :kind))
      (emacsvox-mermaid-panel-step) (emacsvox-mermaid-panel-expand)))

(defun emacsvox-mermaid--open-panel (kind title rows &optional state)
  "Open a companion panel of KIND with TITLE, ROWS and extra STATE."
  (let* ((parent (current-buffer)) (owner emacsvox-mermaid--view)
         (buffer (or (cl-find-if (lambda (candidate)
                                  (and (buffer-live-p candidate)
                                       (eq kind (plist-get (buffer-local-value 'emacsvox-mermaid--panel candidate) :kind))))
                                emacsvox-mermaid--panels)
                     (generate-new-buffer (format "*Mermaid %s: %s*" kind (buffer-name))))))
    (cl-pushnew buffer emacsvox-mermaid--panels)
    (with-current-buffer buffer
      (emacsvox-mermaid-panel-mode)
      (setq emacsvox-mermaid--panel
            (append (list :kind kind :parent parent :owner owner :snapshot (copy-emacsvox-mermaid--view owner)
                          :origin (emacsvox-mermaid--view-current owner) :title title :items rows :index 0) state))
      (emacsvox-mermaid--panel-render))
    (pop-to-buffer buffer)
    (emacsvox-mermaid--say
     (concat title ". "
             (if (eq kind 'route)
                 (concat (format "%d steps. One route along arrows; conditions are not evaluated. " (length rows))
                         (emacsvox-mermaid--panel-text (car rows))
                         " Up and down preview; Return follows the next step.")
               (format "Summary. %d paths available. Up and down browse; Return expands a path. Period reads the selected item."
                       (1- (length rows))))))
    buffer))

(defun emacsvox-mermaid-browse-explanation ()
  "Browse the explanation and expand individual paths without moving the explorer."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let* ((origin (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (out (emacsvox-mermaid--relations origin 'outgoing))
         (incoming (cl-remove-if (lambda (item) (assq (car item) out)) (emacsvox-mermaid--relations origin 'incoming)))
         (limit (max 1 emacsvox-mermaid-explanation-path-limit))
         (rows (list (list :kind 'summary :text (emacsvox-mermaid--explanation-text)))))
    (dolist (section '(outgoing incoming link))
      (dolist (item (if (eq section 'incoming) incoming out))
        (when (eq (equal "none" (alist-get 'direction (car item))) (eq section 'link))
          (setq rows (append rows (list (list :kind section :item item :limit limit)))))))
    (emacsvox-mermaid--open-panel 'explanation (concat "Explanation of " (emacsvox-mermaid--name origin)) rows)))

(defun emacsvox-mermaid-route (&optional destination)
  "Choose DESTINATION and preview one arrow route, then follow it step by step.
Use the fewest arrows, breaking ties in source order.  Conditions are not
evaluated; undirected links and group containment do not create routes."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let* ((owner emacsvox-mermaid--view) (origin (emacsvox-mermaid--view-current owner))
         (choices (mapcar (lambda (node) (let ((id (alist-get 'id node))) (cons (emacsvox-mermaid--name id t) id)))
                          (alist-get 'nodes (emacsvox-mermaid--view-graph owner)))))
    (unless destination (setq destination (cdr (assoc (completing-read "Route to: " choices nil t) choices))))
    (when destination
      (unless (and (eq owner emacsvox-mermaid--view) (equal origin (emacsvox-mermaid--view-current owner)))
        (user-error "Diagram changed while choosing the destination; try r again"))
      (when (equal origin destination) (user-error "Already at that destination"))
      (unless (emacsvox-mermaid--node destination) (user-error "Unknown route destination"))
      (let ((steps (emacsvox-mermaid--route-steps origin destination)))
        (unless steps (user-error "No route to that destination following arrows"))
        (emacsvox-mermaid--open-panel
         'route (format "Route from %s to %s" (emacsvox-mermaid--name origin) (emacsvox-mermaid--name destination))
         steps (list :progress 0 :history (emacsvox-mermaid--view-history owner)))))))

(defun emacsvox-mermaid--close-panels ()
  "Close companion buffers belonging to this explorer."
  (dolist (buffer emacsvox-mermaid--panels) (when (buffer-live-p buffer) (kill-buffer buffer))))

(defun emacsvox-mermaid--render ()
  "Render the current graph selection in the read-only explorer."
  (let ((inhibit-read-only t)
        (items (emacsvox-mermaid--items))
        (selection (emacsvox-mermaid--view-selection emacsvox-mermaid--view))
        previous)
    (erase-buffer)
    (insert (emacsvox-mermaid--overview-text) "\n\n"
            (emacsvox-mermaid--current-text) "\n\n"
            (capitalize (symbol-name (emacsvox-mermaid--view-section emacsvox-mermaid--view))) "\n")
    (if (null items) (insert "No connections or members in this section.\n")
      (cl-loop for item in items for index from 0 do
               (when (eq 'connections (emacsvox-mermaid--view-section emacsvox-mermaid--view))
                 (let ((section (emacsvox-mermaid--item-section item)))
                   (unless (eq section previous)
                     (insert (capitalize (symbol-name section)) "\n")
                     (setq previous section))))
               (insert (propertize (concat (emacsvox-mermaid--item-text item) "\n")
                                   'emacsvox-mermaid-item index))))
    (insert "\no outgoing, i incoming, a all, m members, u containing group\n"
            "up/down or n/p select, left incoming, right outgoing, RET follow\n"
            "C-g combined connections, b back, f find, F filtered find\n"
            ". details, e explain, E browse explanation, r route, w where, v overview\n"
            "s source, g refresh, ? help, q quit\n")
    (when (emacsvox-mermaid--view-diagnostics emacsvox-mermaid--view)
      (insert "\nParser warnings:\n")
      (dolist (diagnostic (emacsvox-mermaid--view-diagnostics emacsvox-mermaid--view))
        (insert (alist-get 'message diagnostic) "\n")))
    (goto-char (point-min))
    (when items
      (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item selection)))))

(defun emacsvox-mermaid--select-section (section &optional summary)
  "Show SECTION and speak its name and selection, starting at the first item.
Keep the selection when SECTION is already current.
With SUMMARY, start at the first item and speak the direction's names or count."
  (emacsvox-mermaid--require-graph)
  (setf (emacsvox-mermaid--view-selection emacsvox-mermaid--view)
        (if (and (not summary) (eq section (emacsvox-mermaid--view-section emacsvox-mermaid--view)))
            (plist-get (emacsvox-mermaid--location) :selection) 0)
        (emacsvox-mermaid--view-section emacsvox-mermaid--view) section)
  (emacsvox-mermaid--render)
  (emacsvox-mermaid--say
   (if summary
       (concat (emacsvox-mermaid--connection-summary section)
               (emacsvox-mermaid--undirected-summary))
     (format "%s. %s" (emacsvox-mermaid--selection-heading)
             (emacsvox-mermaid--selection-text)))))

(defun emacsvox-mermaid-outgoing ()
  "Summarize outgoing connections and select the first without following it."
  (interactive) (emacsvox-mermaid--select-section 'outgoing t))

(defun emacsvox-mermaid-incoming ()
  "Summarize incoming connections and select the first without following it."
  (interactive) (emacsvox-mermaid--select-section 'incoming t))

(defun emacsvox-mermaid-connections ()
  "Return to the combined connection list, outgoing first."
  (interactive) (emacsvox-mermaid--select-section 'connections))

(defun emacsvox-mermaid--direction (section)
  "Follow the selected connection in SECTION, or offer that direction.
Without a matching selection, follow a sole connection or show the choices."
  (emacsvox-mermaid--require-graph)
  (let* ((view emacsvox-mermaid--view)
         (items (emacsvox-mermaid--relations (emacsvox-mermaid--view-current view) section))
         (index (get-text-property (point) 'emacsvox-mermaid-item))
         (selected (and index (nth index (emacsvox-mermaid--items)))))
    (cond
     ((and selected (member selected items)) (emacsvox-mermaid--traverse selected))
     ((null items) (emacsvox-mermaid--select-section section t))
     ((= 1 (length items)) (emacsvox-mermaid--traverse (car items)))
     (t (emacsvox-mermaid--select-section section)))))

(defun emacsvox-mermaid-left ()
  "Follow the sole incoming connection, or choose and follow an incoming item."
  (interactive) (emacsvox-mermaid--direction 'incoming))

(defun emacsvox-mermaid-right ()
  "Follow the sole outgoing connection, or choose and follow an outgoing item."
  (interactive) (emacsvox-mermaid--direction 'outgoing))

(defun emacsvox-mermaid-all ()
  "Browse all nodes and groups, including disconnected components."
  (interactive) (emacsvox-mermaid--select-section 'all))

(defun emacsvox-mermaid-members ()
  "Browse the members of the current group."
  (interactive) (emacsvox-mermaid--select-section 'members))

(defun emacsvox-mermaid-next (&optional previous)
  "Select the next relation without following it; PREVIOUS reverses direction."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let* ((view emacsvox-mermaid--view) (items (emacsvox-mermaid--items))
         (old-index (or (get-text-property (point) 'emacsvox-mermaid-item)
                        (emacsvox-mermaid--view-selection view)))
         (old-section (car (emacsvox-mermaid--selection-info old-index)))
         (index (+ old-index (if previous -1 1))))
    (unless items (user-error "This section is empty"))
    (unless (<= 0 index (1- (length items)))
      (user-error (if previous "Start of section" "End of section")))
    (setf (emacsvox-mermaid--view-selection view) index)
    (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item index))
    (emacsvox-mermaid--say
     (concat (unless (eq old-section (car (emacsvox-mermaid--selection-info)))
               (concat (emacsvox-mermaid--selection-heading) ". "))
             (emacsvox-mermaid--selection-text)))))

(defun emacsvox-mermaid-previous ()
  "Select the previous relation without following it."
  (interactive) (emacsvox-mermaid-next t))

(defun emacsvox-mermaid--location ()
  "Capture the current node, section and actual selection at point."
  (list :node (emacsvox-mermaid--view-current emacsvox-mermaid--view)
        :section (emacsvox-mermaid--view-section emacsvox-mermaid--view)
        :selection (or (get-text-property (point) 'emacsvox-mermaid-item)
                       (emacsvox-mermaid--view-selection emacsvox-mermaid--view))))

(defun emacsvox-mermaid--visit (id &optional back location)
  "Move to ID and restore LOCATION or its remembered place.
Record the place being left in traversal history unless BACK is non-nil."
  (unless (emacsvox-mermaid--node id) (user-error "Node is no longer available"))
  (let* ((view emacsvox-mermaid--view)
         (origin (emacsvox-mermaid--location))
         (crossing (emacsvox-mermaid--crossing-text (plist-get origin :node) id))
         (entering (and (equal "group" (alist-get 'kind (emacsvox-mermaid--node id)))
                        (not (member id (emacsvox-mermaid--contexts (plist-get origin :node))))))
         (seen (member id (emacsvox-mermaid--view-visited view))))
    (puthash (plist-get origin :node) origin (emacsvox-mermaid--view-places view))
    (unless location
      (let ((remembered (gethash id (emacsvox-mermaid--view-places view))))
        ;; A direction chooser is restored by Back, not armed on a new visit.
        (unless (memq (plist-get remembered :section) '(outgoing incoming))
          (setq location remembered))))
    (unless back (push origin (emacsvox-mermaid--view-history view)))
    (cl-pushnew id (emacsvox-mermaid--view-visited view) :test #'equal)
    (setf (emacsvox-mermaid--view-current view) id
          (emacsvox-mermaid--view-section view) (or (plist-get location :section) 'connections)
          (emacsvox-mermaid--view-selection view) (or (plist-get location :selection) 0))
    (emacsvox-mermaid--render)
    (emacsvox-mermaid--say
     (concat (when seen "Revisited. ") crossing (when entering "Entering ")
             (emacsvox-mermaid--brief-text)
             (when (and location (not (plist-get location :fresh)))
               (format " %s. %s" (emacsvox-mermaid--selection-heading)
                       (emacsvox-mermaid--selection-text)))))))

(defun emacsvox-mermaid--traverse (item)
  "Follow ITEM, starting a fresh combined list after crossing a connection."
  (let ((id (cdr item)))
    (emacsvox-mermaid--visit
     id nil (when (car item) (list :node id :section 'connections :selection 0 :fresh t)))))

(defun emacsvox-mermaid-follow ()
  "Follow the selected relation or open the selected node or group."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let ((index (get-text-property (point) 'emacsvox-mermaid-item)))
    (unless index (user-error "Select a connection or node first"))
    (emacsvox-mermaid--traverse (nth index (emacsvox-mermaid--items)))))

(defun emacsvox-mermaid-back ()
  "Restore the previous node, section and connection selection."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (unless (emacsvox-mermaid--view-history emacsvox-mermaid--view)
    (user-error "No previous node"))
  (let ((location (pop (emacsvox-mermaid--view-history emacsvox-mermaid--view))))
    (emacsvox-mermaid--visit (plist-get location :node) t location)))

(defun emacsvox-mermaid-parent ()
  "Visit a containing group, selecting the member being left."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let* ((id (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (groups (alist-get 'groups (emacsvox-mermaid--node id))))
    (unless groups (user-error "No containing group; already at top level"))
    (let* ((choices (mapcar (lambda (key) (cons (emacsvox-mermaid--name key t) key)) groups))
           (parent (if (= 1 (length groups)) (car groups)
                     (cdr (assoc (completing-read "Containing group: " choices nil t) choices)))))
      (when parent
        (emacsvox-mermaid--visit
         parent nil (list :node parent :section 'members
                          :selection (or (cl-position id (alist-get 'members (emacsvox-mermaid--node parent))
                                                      :test #'equal) 0)))))))

(defun emacsvox-mermaid-where ()
  "Speak the current node, group context, section and selected connection."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let* ((id (emacsvox-mermaid--view-current emacsvox-mermaid--view))
         (groups (remove id (emacsvox-mermaid--contexts id))))
    (setf (emacsvox-mermaid--view-selection emacsvox-mermaid--view)
          (plist-get (emacsvox-mermaid--location) :selection))
    (emacsvox-mermaid--say
     (concat (emacsvox-mermaid--sentence (emacsvox-mermaid--name id)) " "
             (if groups (concat "In " (mapconcat #'emacsvox-mermaid--name groups ", ") ". ") "Top level. ")
             (emacsvox-mermaid--selection-heading)
             ". " (emacsvox-mermaid--selection-text)))))

(defconst emacsvox-mermaid--filters
  '(("All nodes and groups" . all) ("Entry points" . entries)
    ("Exit points" . exits) ("Branch points" . branches) ("Joins" . joins)
    ("Disconnected nodes" . disconnected) ("Upstream" . upstream)
    ("Downstream" . downstream) ("Unvisited" . unvisited) ("Groups" . groups))
  "Structural filters offered by filtered Find.")

(defun emacsvox-mermaid--matching-ids (filter)
  "Return graph identities matching FILTER in source order.
Reachability follows arrows, including both directions of two-way links.
Entry and exit points exclude undirected links and isolated items."
  (let* ((view emacsvox-mermaid--view)
         (analysis (emacsvox-mermaid--view-analysis view))
         (out (plist-get analysis :out)) (in (plist-get analysis :in))
         (current (emacsvox-mermaid--view-current view))
         (reachable (make-hash-table :test #'equal)))
    (when (memq filter '(upstream downstream))
      (let ((adjacency (if (eq filter 'upstream) in out))
            (pending (list current)))
        (while pending
          (let ((id (pop pending)))
            (unless (gethash id reachable)
              (puthash id t reachable)
              (setq pending (append (gethash id adjacency) pending))))))
      (remhash current reachable))
    (cl-loop for node in (alist-get 'nodes (emacsvox-mermaid--view-graph view))
             for id = (alist-get 'id node)
             when
             (pcase filter
               ('all t)
               ('entries (and (gethash id out) (not (gethash id in))
                              (not (gethash id (plist-get analysis :undirected)))))
               ('exits (and (gethash id in) (not (gethash id out))
                            (not (gethash id (plist-get analysis :undirected)))))
               ('branches (> (length (gethash id out)) 1))
               ('joins (> (length (gethash id in)) 1))
               ('disconnected (and (equal "node" (alist-get 'kind node))
                                   (not (gethash id (plist-get analysis :neighbors)))))
               ((or 'upstream 'downstream) (gethash id reachable))
               ('unvisited (not (member id (emacsvox-mermaid--view-visited view))))
               ('groups (equal "group" (alist-get 'kind node))))
             collect id)))

(defun emacsvox-mermaid--find (filter)
  "Choose and visit an object matching FILTER without moving on cancellation."
  (let* ((ids (emacsvox-mermaid--matching-ids filter))
         (label (car (rassq filter emacsvox-mermaid--filters)))
         (choices (mapcar (lambda (id) (cons (emacsvox-mermaid--name id t) id)) ids)))
    (unless choices (user-error "No matches for %s" (downcase label)))
    (when-let* ((id (cdr (assoc (completing-read (concat label ": ") choices nil t) choices))))
      (emacsvox-mermaid--visit id))))

(defun emacsvox-mermaid-find ()
  "Find a node or group by label or ID using completion."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (emacsvox-mermaid--find 'all))

(defun emacsvox-mermaid-find-filtered ()
  "Choose a structural filter, then find a matching node or group."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (when-let* ((filter (cdr (assoc (completing-read "Find filter: " emacsvox-mermaid--filters nil t)
                                emacsvox-mermaid--filters))))
    (emacsvox-mermaid--find filter)))

(defun emacsvox-mermaid-current ()
  "Speak the current node, its shape, connections and group membership."
  (interactive) (emacsvox-mermaid--require-graph)
  (emacsvox-mermaid--say (emacsvox-mermaid--current-text)))

(defun emacsvox-mermaid-explain ()
  "Explain this node's branches, joins and loops without changing position.
Follow explicit arrows only.  Distinguish a guaranteed join from a node that
all branches can reach along some paths.  Trace straight sequences in both
directions, bounded by `emacsvox-mermaid-explanation-path-limit'.  Use the
connection speech limit when naming branches."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (emacsvox-mermaid--say (emacsvox-mermaid--explanation-text)))

(defun emacsvox-mermaid-overview ()
  "Speak the diagram's title, description and graph counts."
  (interactive) (emacsvox-mermaid--require-graph)
  (emacsvox-mermaid--say (emacsvox-mermaid--overview-text)))

(defun emacsvox-mermaid-source ()
  "Visit the current node's source, refusing stale source offsets."
  (interactive)
  (emacsvox-mermaid--require-graph)
  (let* ((view emacsvox-mermaid--view)
         (range (alist-get 'range (emacsvox-mermaid--node (emacsvox-mermaid--view-current view)))))
    (unless (equal (emacsvox-mermaid--view-text view) (emacsvox-mermaid--source-text view))
      (user-error "Source changed or closed; refresh with g before jumping"))
    (unless range (user-error "Mermaid did not supply a source location for this node"))
    (pop-to-buffer (emacsvox-mermaid--view-source view))
    (widen)
    (goto-char (+ (marker-position (emacsvox-mermaid--view-start view)) (alist-get 'start range)))
    (emacsvox-mermaid--say (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))

(defun emacsvox-mermaid-help ()
  "Explain the explorer's navigation and snapshot behaviour."
  (interactive)
  (emacsvox-mermaid--say
   (concat "Up and down, or n and p, browse connections, outgoing first. "
           "Right follows the selected outgoing connection; Left follows the selected incoming connection. "
           "This also works in the combined list. Either arrow follows a selected two-way or undirected link. "
           "Without a matching selection, an arrow follows a sole connection or opens its direction's choices. "
           "Up and down select; Return or the same arrow follows. "
           "o summarizes outgoing connections; i summarizes incoming connections. "
           "Each selects its first item without following. Undirected links are included and named. "
           "Control g returns to the combined connection list. "
           "b restores your previous node and connection selection. f finds by label or ID. "
           "Capital F first filters by structure, including entries, exits, branches, joins, "
           "disconnected nodes, upstream, downstream, unvisited nodes or groups. "
           "Reachability follows arrows; group membership does not create arrows. "
           "a lists all nodes and groups. m lists group members. u visits a containing group. "
           "Period gives full node details. e explains branches, joins and loops along arrows. "
           "Capital E browses that explanation and expands individual paths. r previews a route to a chosen node. "
           "w says where you are. v gives an overview. "
           "s visits source. g refreshes after edits. q leaves the explorer. "
           "Navigation uses a snapshot until you refresh. Layout direction is visual order, "
           "not a statement about execution. Links and callbacks are never opened.")))

(defun emacsvox-mermaid--accept (buffer view text response)
  "Install RESPONSE for TEXT into BUFFER if VIEW is still current."
  (when (and (buffer-live-p buffer)
             (eq view (buffer-local-value 'emacsvox-mermaid--view buffer)))
    (with-current-buffer buffer
      (let* ((graph (alist-get 'graph response))
             (diagnostics (alist-get 'diagnostics response))
             (reason (or (alist-get 'error response)
                         (unless (equal text (emacsvox-mermaid--source-text view))
                           "Source changed or closed while parsing; press g to retry")
                         (unless graph
                           (mapconcat
                            (lambda (d)
                              (let* ((offset (alist-get 'start (alist-get 'range d)))
                                     (line (and offset (1+ (cl-count ?\n text :end offset)))))
                                (format "%s%s" (if line (format "Diagram line %d: " line) "")
                                        (alist-get 'message d)))) diagnostics "\n"))
                         (unless (alist-get 'nodes graph) "The flowchart has no nodes"))))
        (setf (emacsvox-mermaid--view-request view) nil)
        (if reason
            (let ((inhibit-read-only t))
              (setf (emacsvox-mermaid--view-current view) nil)
              (erase-buffer) (insert "Mermaid could not be explored.\n\n" reason "\n\nPress g to retry, q to leave.\n")
              (goto-char (point-min))
              (when (eq buffer (window-buffer (selected-window)))
                (emacsvox-mermaid--say reason)))
          (setf (emacsvox-mermaid--view-graph view) graph
                (emacsvox-mermaid--view-text view) text
                (emacsvox-mermaid--view-analysis view) (emacsvox-mermaid--analyse graph)
                (emacsvox-mermaid--view-places view) (make-hash-table :test #'equal)
                (emacsvox-mermaid--view-index view) (make-hash-table :test #'equal))
          (dolist (node (alist-get 'nodes graph))
            (puthash (alist-get 'id node) node (emacsvox-mermaid--view-index view)))
          (unless (emacsvox-mermaid--node (emacsvox-mermaid--view-current view))
            (setf (emacsvox-mermaid--view-current view) (alist-get 'id (car (alist-get 'nodes graph)))))
          (setf (emacsvox-mermaid--view-history view) nil
                (emacsvox-mermaid--view-diagnostics view) diagnostics
                (emacsvox-mermaid--view-visited view) (list (emacsvox-mermaid--view-current view)))
          (emacsvox-mermaid--render)
          (when (eq buffer (window-buffer (selected-window)))
            (emacsvox-mermaid--say
             (concat (emacsvox-mermaid--overview-text) " " (emacsvox-mermaid--brief-text)
                     (when diagnostics (format " %d parser warnings at end of buffer." (length diagnostics)))
                     " Press up or down to browse connections, question mark for help."))))))))

(defun emacsvox-mermaid--cancel-request ()
  "Cancel delivery of this explorer's outstanding request."
  (when-let* ((view emacsvox-mermaid--view)
              (id (emacsvox-mermaid--view-request view))
              (entry (gethash id emacsvox-mermaid--pending)))
    (cancel-timer (car entry))
    (remhash id emacsvox-mermaid--pending)))

(defun emacsvox-mermaid-refresh ()
  "Parse the marked source again, preserving the current node if it remains."
  (interactive)
  (unless emacsvox-mermaid--view (user-error "Not in a Mermaid explorer"))
  (let* ((old emacsvox-mermaid--view)
         (text (emacsvox-mermaid--source-text old))
         (buffer (current-buffer))
         (view (copy-emacsvox-mermaid--view old)))
    (unless text (user-error "The source buffer has been closed"))
    (emacsvox-mermaid--ensure-process)
    (emacsvox-mermaid--cancel-request)
    (setf (emacsvox-mermaid--view-section view) 'connections
          (emacsvox-mermaid--view-selection view) 0)
    (setq emacsvox-mermaid--view view)
    (setf (emacsvox-mermaid--view-request view)
          (emacsvox-mermaid--request text (lambda (response) (emacsvox-mermaid--accept buffer view text response))))
    (message "Parsing Mermaid flowchart…")))

(defun emacsvox-mermaid-quit ()
  "Dismiss the explorer with the standard close cue and destination feedback."
  (interactive)
  ;; Own the feedback so unrelated quit advice cannot consume its interactive
  ;; marker or report twice.  Preserve Emacs's normal window restoration.
  (let* ((ems--interactive-fn-name nil)
         (parent (plist-get emacsvox-mermaid--panel :parent))
         (position (when (buffer-live-p parent) (with-current-buffer parent (point)))))
    (quit-window)
    ;; A route can redraw a hidden explorer.  Its old quit-restore marker then
    ;; points into obsolete contents, so retain its most recent selection.
    (when (and position (eq (current-buffer) parent)) (goto-char position))
    (tts-stop 'all)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(defun emacsvox-mermaid-panel-help ()
  "Explain the companion buffer's controls."
  (interactive)
  (emacsvox-mermaid--say
   (concat "Up and down, or n and p, browse items. Period repeats the current item. "
           (if (eq 'route (plist-get emacsvox-mermaid--panel :kind))
               "Return or right follows the next uncompleted route step, regardless of the preview selection. b or left retraces a followed step. Conditions are not evaluated. "
             "Return, right or plus expands just the selected path. Expansion stops at a split, join, endpoint, loop or two-way connection. Global speech limits stay unchanged. ")
           "q returns to the explorer. A diagram refresh requires reopening this buffer.")))

(defvar emacsvox-mermaid-panel-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (dolist (binding '(("<down>" . emacsvox-mermaid-panel-next) ("n" . emacsvox-mermaid-panel-next)
                       ("<up>" . emacsvox-mermaid-panel-previous) ("p" . emacsvox-mermaid-panel-previous)
                       ("." . emacsvox-mermaid-panel-current) ("+" . emacsvox-mermaid-panel-expand)
                       ("RET" . emacsvox-mermaid-panel-activate) ("<right>" . emacsvox-mermaid-panel-activate)
                       ("b" . emacsvox-mermaid-panel-back) ("<left>" . emacsvox-mermaid-panel-back)
                       ("q" . emacsvox-mermaid-quit) ("?" . emacsvox-mermaid-panel-help)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Keys local to Mermaid explanation and route buffers.")

(define-derived-mode emacsvox-mermaid-panel-mode special-mode "Mermaid Details"
  "Browse paths and routes associated with a Mermaid diagram snapshot."
  (setq-local truncate-lines nil))

(defvar emacsvox-mermaid-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (dolist (binding '(("o" . emacsvox-mermaid-outgoing) ("i" . emacsvox-mermaid-incoming)
                       ("a" . emacsvox-mermaid-all) ("m" . emacsvox-mermaid-members)
                       ("n" . emacsvox-mermaid-next) ("p" . emacsvox-mermaid-previous)
                       ("<down>" . emacsvox-mermaid-next) ("<up>" . emacsvox-mermaid-previous)
                       ("<left>" . emacsvox-mermaid-left) ("<right>" . emacsvox-mermaid-right)
                       ("C-g" . emacsvox-mermaid-connections) ("q" . emacsvox-mermaid-quit)
                       ("RET" . emacsvox-mermaid-follow) ("b" . emacsvox-mermaid-back)
                       ("f" . emacsvox-mermaid-find) ("." . emacsvox-mermaid-current)
                       ("e" . emacsvox-mermaid-explain) ("E" . emacsvox-mermaid-browse-explanation)
                       ("r" . emacsvox-mermaid-route)
                       ("F" . emacsvox-mermaid-find-filtered) ("u" . emacsvox-mermaid-parent)
                       ("w" . emacsvox-mermaid-where)
                       ("v" . emacsvox-mermaid-overview) ("s" . emacsvox-mermaid-source)
                       ("g" . emacsvox-mermaid-refresh) ("?" . emacsvox-mermaid-help)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Keys used only in Mermaid explorer buffers.")

(define-derived-mode emacsvox-mermaid-mode special-mode "Mermaid Explorer"
  "Read-only spoken navigation through a snapshot of a Mermaid flowchart."
  (setq-local truncate-lines t)
  (add-hook 'kill-buffer-hook #'emacsvox-mermaid--cancel-request nil t)
  (add-hook 'kill-buffer-hook #'emacsvox-mermaid--close-panels nil t))

;;;###autoload
(defun emacsvox-mermaid-explore ()
  "Explore the Mermaid block at point, active region, or entire source buffer.
Supports flowcharts through an optional, pinned Mermaid v13 alpha parser.
Install it once with `make mermaid-deps' in the Emacsvox checkout."
  (interactive)
  (emacsvox-mermaid--ensure-process)
  (let* ((bounds (emacsvox-mermaid--bounds))
         (view (emacsvox-mermaid--view-create
                :source (current-buffer)
                :start (copy-marker (car bounds)) :end (copy-marker (cdr bounds) t)))
         (buffer (generate-new-buffer (format "*Mermaid: %s*" (buffer-name)))))
    (with-current-buffer buffer
      (emacsvox-mermaid-mode)
      (setq emacsvox-mermaid--view view)
      (let ((inhibit-read-only t)) (insert "Parsing Mermaid flowchart…\n")))
    (pop-to-buffer buffer)
    (emacsvox-mermaid-refresh)))

(provide 'emacsvox-mermaid)
;;; emacsvox-mermaid.el ends here
