;;; summarize.el --- Normalize performance fix samples -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Run with the selected Emacs in batch mode after the benchmark drivers.
;;; Code:
(require 'cl-lib)
(require 'json)
(defvar read-eval)
(let* ((directory (file-name-directory load-file-name))
       (read-eval nil) rows)
  (dolist (name '("interaction-probes.eld" "tables.eld" "library.eld"
                  "comint-stream.eld" "agent-suspended.eld" "speech-input.eld"
                  "matching-paired.eld"))
    (let ((data (with-temp-buffer
                  (insert-file-contents (expand-file-name name directory))
                  (read (current-buffer)))))
      (dolist (row (plist-get data :results))
        (when-let* ((samples (plist-get row :samples-ms)))
          (let* ((sorted (sort (copy-sequence samples) #'<))
                 (n (length sorted))
                 (result
                  (list :artifact name :case (symbol-name (plist-get row :case))
                        :iterations n
                        :median_ms (if (cl-oddp n) (nth (/ n 2) sorted)
                                     (/ (+ (nth (1- (/ n 2)) sorted) (nth (/ n 2) sorted)) 2.0))
                        :minimum_ms (car sorted) :maximum_ms (car (last sorted))
                        :p95_ms (nth (1- (ceiling (* 0.95 n))) sorted)
                        :gc_count (plist-get row :gc-count)
                        :gc_seconds (plist-get row :gc-seconds)
                        :allocation_counts (vconcat (plist-get row :allocation-counts))
                        :samples_ms (vconcat samples))))
            (dolist (key '(:mode :rows :files :lines :bytes :chunks :round :cache
                           :cold-ms :document-sha256 :input-sha256 :retained-owners))
              (when (plist-member row key)
                (let ((value (plist-get row key)))
                  (setq result (append result
                                       (list key (cond ((null value) :false)
                                                       ((or (eq value t) (not (symbolp value))) value)
                                                       (t (symbol-name value)))))))))
            (push result rows))))))
  (with-temp-file (expand-file-name "measurements.json" directory)
    (insert (json-serialize
             (list :median_convention "mean of the central two samples for even N"
                   :percentile_convention "nearest rank" :results (vconcat (nreverse rows)))
             :null-object nil :false-object :false) "\n")))
;;; summarize.el ends here
