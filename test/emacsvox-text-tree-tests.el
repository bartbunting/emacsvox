;;; emacsvox-text-tree-tests.el --- Text tree contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise shared recognition and speech copies without an integration.

;;; Code:
(require 'ert)
(let ((path (expand-file-name
             (concat "../lisp/core/emacsvox-text-tree"
                     (if (equal (getenv "EMACSVOX_AGENT_SHELL_TEST_LOAD") "compiled")
                         ".elc" ".el"))
             (file-name-directory (or load-file-name buffer-file-name)))))
  (load path nil nil t)
  (unless (equal (file-truename path)
                 (file-truename (symbol-file 'emacsvox-text-tree--parse 'defun)))
    (error "Tree tests loaded the wrong implementation")))

(ert-deftest emacsvox-text-tree-depth-and-preservation ()
  "Both branch alphabets retain depth, annotations, voices and source text."
  (dolist (text '("Root\n├─ One\n│  └─ Child\n└─ Two [opens another page]\n"
                  "Root\n├── One\n│   └── Child\n└── Two [opens another page]\n"
                  "Root\n|-- One\n|   `-- Child\n`-- Two [opens another page]\n"
                  "Root\n+-- One\n|   +-- Child\n+-- Two [opens another page]\n"))
    (with-temp-buffer
      (insert text)
      (put-text-property (point-min) (point-max) 'personality 'voice-bolden)
      (setq buffer-undo-list nil)
      (set-buffer-modified-p nil)
      (let ((point-before (point))
            (nodes (emacsvox-text-tree--mark-region (point-min) (point-max))))
        (should (equal '(0 1 2 1) (mapcar (lambda (node) (plist-get node :depth)) nodes)))
        (should (= (point) point-before))
        (should-not (buffer-modified-p))
        (should-not buffer-undo-list))
      (let* ((source (buffer-string))
             (spoken (emacsvox-text-tree--speech-text source)))
        (should (equal (substring-no-properties spoken)
                       "Root\nOne\nChild\nTwo [opens another page]\n"))
        (should (eq (get-text-property 0 'personality spoken) 'voice-bolden))
        (should (= 2 (get-text-property 9 'emacsvox-text-tree-depth spoken)))
        (should (equal-including-properties source (buffer-string)))
        (should (equal (substring-no-properties source) text))
        (should (equal-including-properties spoken (emacsvox-text-tree--speech-text spoken)))))))

(ert-deftest emacsvox-text-tree-rejects-ambiguous-layouts ()
  "Partial, inconsistent and unrelated input remains literal."
  (dolist (text '("├─ One\n└─ Two\n" "Root\n└─ One\n"
                  "Root\n├─ One\n└─ " "Root\n├─ One\n|-- Two\n"
                  "Root\n├─ One\n      └─ Jump\n"
                  "Root\n├─ One\n │ └─ Bad spacing\n"
                  "Root\n├─ One\n\t└─ Tab\n"
                  "Root\n├─ One\n└── Different width\n"
                  "Root\n├─ One\n└─ Two\nordinary trailing prose\n"
                  "| Name | Value |\n|------|-------|\n| One | Two |\n"
                  "╭───╮\n│ x │\n╰───╯\n" "x | y\na -- b\n"))
    (should-not (emacsvox-text-tree--parse text))
    (should (eq text (emacsvox-text-tree--speech-text text)))))

(ert-deftest emacsvox-text-tree-forest-and-label-symbols ()
  "Each root is checked separately and symbols inside labels remain speech."
  (with-temp-buffer
    (insert "First\n├─ A │ B\n└─ C\n\nSecond\n|-- D\n`-- E\n")
    (should (emacsvox-text-tree--mark-region (point-min) (point-max)))
    (should (equal "First\nA │ B\nC\n\nSecond\nD\nE\n"
                   (substring-no-properties (emacsvox-text-tree--speech-text (buffer-string)))))))

(ert-deftest emacsvox-text-tree-rechecking-removes-stale-marks ()
  "An edited region that is no longer a tree regains literal speech."
  (with-temp-buffer
    (insert "Root\n├─ One\n└─ Two\n")
    (should (emacsvox-text-tree--mark-region (point-min) (point-max)))
    (goto-char (point-max))
    (insert "Trailing prose\n")
    (should-not (emacsvox-text-tree--mark-region (point-min) (point-max)))
    (should (equal-including-properties
             (buffer-string) (emacsvox-text-tree--speech-text (buffer-string))))))

(ert-deftest emacsvox-text-tree-prose-after-tree ()
  "A separate closing note does not invalidate a complete tree paragraph."
  (with-temp-buffer
    (insert "Finance\n├─ Cash forecast\n│  └─ Overview\n└─ Planning\n\nUtilities: unchanged")
    (should (emacsvox-text-tree--mark-region (point-min) (point-max)))
    (let ((spoken (car (emacsvox-text-tree--describe (buffer-string)))))
      (should (equal spoken "Tree. Finance\nLevel 1. Cash forecast\nLevel 2. Overview\nLevel 1. Planning\nEnd of tree. \nUtilities: unchanged")))))

(ert-deftest emacsvox-text-tree-entry-depth-and-siblings ()
  "Line reading announces entry and depth changes, including reverse movement."
  (with-temp-buffer
    (insert "Root\n├─ One\n│  ├─ Child\n│  └─ Sibling\n└─ Two\n")
    (emacsvox-text-tree--mark-region (point-min) (point-max))
    (let ((lines (split-string (buffer-string) "\n")) context)
      (dolist (step '((0 . "Tree. Root") (1 . "Level 1. One")
                      (2 . "Level 2. Child") (3 . "Sibling")
                      (4 . "Level 1. Two") (3 . "Level 2. Sibling")
                      (0 . "Root. Root")))
        (let ((result (emacsvox-text-tree--describe (nth (car step) lines) context)))
          (should (equal (substring-no-properties (car result)) (cdr step)))
          (setq context (cdr result))))
      (let ((outside (emacsvox-text-tree--describe "Outside" context)))
        (should (equal "End of tree. Outside" (car outside)))
        (should-not (cdr outside))
        (should (equal "Still outside"
                       (car (emacsvox-text-tree--describe "Still outside" (cdr outside))))))
      (should (equal "Tree. Level 2. Child"
                     (substring-no-properties
                      (car (emacsvox-text-tree--describe (nth 2 lines)))))))))

(ert-deftest emacsvox-text-tree-depth-tone-is-bounded-and-isolated ()
  "Depth facts encode pitch without adding tones to boundaries or labels."
  (let ((pitches (mapcar
                  (lambda (depth)
                    (plist-get (get-text-property
                                0 'emacsvox-aural-facts
                                (emacsvox-text-tree--indicator 'tree-level-changed "Level. " depth))
                               :tree-tone-pitch))
                  '(0 1 2 12 100))))
    (should (= 220 (car pitches)))
    (should (< (nth 0 pitches) (nth 1 pitches) (nth 2 pitches) (nth 3 pitches)))
    (should (= 1760 (nth 3 pitches) (nth 4 pitches))))
  (dolist (event '(tree-entered tree-exited))
    (should-not (plist-get (get-text-property
                           0 'emacsvox-aural-facts
                           (emacsvox-text-tree--indicator event "Boundary. " 0))
                          :tree-tone-pitch))))

(provide 'emacsvox-text-tree-tests)
;;; emacsvox-text-tree-tests.el ends here
