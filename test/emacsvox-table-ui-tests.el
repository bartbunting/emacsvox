;;; emacsvox-table-ui-tests.el --- Table browser tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'cl-lib)
(require 'ert)
(load (expand-file-name "../lisp/emacsvox-table-ui.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil t)

(ert-deftest emacsvox-table-ui-csv-keeps-logical-fields ()
  "CSV quoting does not split cells or create rows from embedded newlines."
  (dolist (ending '("\n" "\r\n" ""))
    (with-temp-buffer
      (insert "Name,Note,Empty\r\nAlice,\"Hello, \"\"world\"\"\",\r\n"
              "Bob,\"First line\n\nSecond line\",\"\"" ending)
      (goto-char 4)
      (set-buffer-modified-p nil)
      (let ((text (buffer-string)) table
            (point (point)))
        (cl-letf (((symbol-function 'emacsvox-table-prepare-table-buffer)
                   (lambda (value buffer) (setq table value) (kill-buffer buffer)))
                  ((symbol-function 'emacsvox-icon) #'ignore))
          (emacsvox-table-view-csv-buffer))
        (should (equal (emacsvox-table-elements table)
                       [["Name" "Note" "Empty"]
                        ["Alice" "Hello, \"world\"" ""]
                        ["Bob" "First line\n\nSecond line" ""]]))
        (should (equal text (buffer-string)))
        (should (= point (point)))
        (should-not (buffer-modified-p))))))

(ert-deftest emacsvox-table-ui-csv-distinguishes-empty-fields-and-blank-records ()
  "Blank records are skipped; empty fields and quoted whitespace are data."
  (with-temp-buffer
    (insert "\n \t\r\n,,\n\"\",\" \"\n last ,field,\n")
    (should (equal (emacsvox-table-ui--csv-records)
                   [["" "" ""] ["" " "] [" last " "field" ""]]))))

(ert-deftest emacsvox-table-ui-csv-view-retains-multiline-cell-positions ()
  "The real browser navigates multiline CSV fields as single logical cells."
  (save-window-excursion
    (let ((source (generate-new-buffer " *csv-source-test*")) view)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'emacsvox-speak-mode-line) #'ignore)
                    ((symbol-function 'message) #'ignore))
            (with-current-buffer source
              (insert "Name,Note\nAlice,\"First\nSecond\"\nBob,Last\n")
              (set-buffer-modified-p nil))
            (emacsvox-table-view-csv-buffer source)
            (setq view (current-buffer))
            (should (derived-mode-p 'emacsvox-table-mode))
            (should buffer-read-only)
            (emacsvox-table-goto-cell emacsvox-table 1 1)
            (emacsvox-table-synchronize-display)
            (should (looking-at "First\nSecond"))
            (should (= 1 (get-text-property (point) 'row)))
            (emacsvox-table-next-row)
            (should (looking-at "Last"))
            (should (= 2 (get-text-property (point) 'row)))
            (should-not (with-current-buffer source (buffer-modified-p))))
        (when (buffer-live-p view) (kill-buffer view))
        (when (buffer-live-p source) (kill-buffer source))))))

(ert-deftest emacsvox-table-ui-csv-rejects-empty-and-malformed-input ()
  "Invalid input reports a user error before creating or replacing a view."
  (dolist (text '("" " \n\t\r\n" "a,\"unfinished" "a,\"closed\"extra\n"
                  "a,unquoted\"quote\n"))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (let ((point (point)) displayed)
        (cl-letf (((symbol-function 'emacsvox-table-prepare-table-buffer)
                   (lambda (&rest _) (setq displayed t))))
          (should-error (emacsvox-table-view-csv-buffer) :type 'user-error))
        (should-not displayed)
        (should (equal text (buffer-string)))
        (should (= point (point)))))))

(ert-deftest emacsvox-table-ui-csv-preserves-unrelated-scratch ()
  "Browsing CSV never borrows or kills a user's named scratch buffer."
  (let* ((existing (get-buffer "*csv-scratch*"))
         (scratch (or existing (get-buffer-create "*csv-scratch*")))
         (before (with-current-buffer scratch (buffer-string))))
    (unwind-protect
        (with-temp-buffer
          (insert "Name,Value\nAlice,one\n")
          (cl-letf (((symbol-function 'emacsvox-table-prepare-table-buffer)
                     (lambda (_ buffer) (kill-buffer buffer)))
                    ((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-table-view-csv-buffer))
          (should (buffer-live-p scratch))
          (should (equal before (with-current-buffer scratch (buffer-string)))))
      (unless existing
        (when (buffer-live-p scratch) (kill-buffer scratch))))))

(ert-deftest emacsvox-table-ui-csv-file-preserves-open-unsaved-source ()
  "Opening a CSV view preserves an already visited file and its unsaved edits."
  (let ((file (make-temp-file "emacsvox-csv-" nil ".txt" "Name,Value\nAlice,old\n"))
        source table)
    (unwind-protect
        (progn
          (setq source (find-file-noselect file))
          (with-current-buffer source
            (goto-char (point-max)) (insert "Bob,new\n"))
          (cl-letf (((symbol-function 'emacsvox-table-prepare-table-buffer)
                     (lambda (value buffer) (setq table value) (kill-buffer buffer)))
                    ((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-table-find-csv-file file))
          (should (buffer-live-p source))
          (should (with-current-buffer source (buffer-modified-p)))
          (should (equal (emacsvox-table-elements table)
                         [["Name" "Value"] ["Alice" "old"] ["Bob" "new"]]))
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         "Name,Value\nAlice,old\n")))
      (when (buffer-live-p source)
        (with-current-buffer source (set-buffer-modified-p nil))
        (kill-buffer source))
      (delete-file file))))

(provide 'emacsvox-table-ui-tests)
;;; emacsvox-table-ui-tests.el ends here
