;;; table-reader-benchmark.el --- Measure logical table navigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run in a fresh Emacs with the project Lisp and dependency directories on
;; load-path.  Set EMACSVOX_TABLE_BENCHMARK_OUTPUT to a JSON output path.
;; EMACSVOX_TABLE_BENCHMARK_AGENT_LIBRARY may select retained baseline byte-code.
;; This measures logical navigation/formatting, not synthesis or acoustic latency.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'emacsvox-preamble)
(require 'agent-shell)
(require 'agent-shell-markdown)
(require 'emacsvox-markdown)
(require 'emacsvox-org)
(require 'emacsvox-table-reader)
(load (or (getenv "EMACSVOX_TABLE_BENCHMARK_AGENT_LIBRARY")
          (locate-library "emacsvox-agent-shell")) nil nil t)

(defun emacsvox-table-benchmark--measure (command origin)
  "Time 20 row moves by COMMAND from ORIGIN after five warm-up rounds."
  (let (samples)
    (dotimes (round 35)
      (goto-char origin)
      (let ((start (float-time)))
        (dotimes (_ 20) (funcall command))
        (when (>= round 5)
          (push (* 50.0 (- (float-time) start)) samples))))
    (vconcat (nreverse samples))))

(let ((gc-cons-threshold (* 64 1024 1024))
      (emacsvox-agent-shell-table-titles '(column))
      (emacsvox-agent-shell-table-data-position 'first)
      (emacsvox-table-reader-titles '(column))
      (emacsvox-table-reader-data-position 'first)
      records)
  (cl-letf (((symbol-function 'emacsvox-agent-shell--submit-text-feedback) #'ignore)
            ((symbol-function 'emacsvox-aural-submit) #'ignore))
    (dolist (rows '(32 256))
      (dolist (mode '(agent-shell markdown-mode org-mode))
        (with-temp-buffer
          (unless (eq mode 'agent-shell) (delay-mode-hooks (funcall mode)))
          (insert "| Name | Role | Notes |\n"
                  (if (eq mode 'org-mode) "|----+----+----|\n" "|---|---|---|\n"))
          (dotimes (row rows)
            (insert (format "| Person %d | Engineer | Complete logical content %d |\n" row row)))
          (when (eq mode 'agent-shell) (agent-shell-markdown-replace-markup))
          (goto-char (point-min))
          (search-forward "Name")
          (backward-char 4)
          (let ((origin (point)))
            (garbage-collect)
            (push (list :mode (symbol-name mode) :data_rows rows :moves_per_sample 20
                        :warmup_samples 5 :sample_unit "milliseconds_per_move"
                        :samples
                        (emacsvox-table-benchmark--measure
                         (if (eq mode 'agent-shell)
                             #'emacsvox-agent-shell-table-next-row
                           #'emacsvox-table-reader-next-row) origin)) records))))))
  (with-temp-file (or (getenv "EMACSVOX_TABLE_BENCHMARK_OUTPUT")
                     (error "Set EMACSVOX_TABLE_BENCHMARK_OUTPUT"))
    (insert (json-serialize
             (list :emacs emacs-version :gc_threshold gc-cons-threshold
                   :agent_library (symbol-file 'emacsvox-agent-shell-table-next-row 'defun)
                   :reader_library (symbol-file 'emacsvox-table-reader-next-row 'defun)
                   :markdown_library (symbol-file 'markdown-mode 'defun)
                   :agent_dependency (symbol-file 'agent-shell-mode 'defun)
                   :records (vconcat (nreverse records)))
             :null-object nil :false-object :false))))
