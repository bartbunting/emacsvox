;;; emacsvox-table-ui-tests.el --- Table browser tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'cl-lib)
(require 'ert)
(let ((file (expand-file-name
             (if (equal (getenv "EMACSVOX_TABLE_UI_TEST_LOAD") "compiled")
                 "../lisp/emacsvox-table-ui.elc" "../lisp/emacsvox-table-ui.el")
             (file-name-directory (or load-file-name buffer-file-name)))))
  (load file nil nil t)
  (should (equal (file-truename file)
                 (file-truename (symbol-file 'emacsvox-table-ui--move 'defun)))))

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
                    ((symbol-function 'emacsvox-aural-submit) #'ignore)
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

(defmacro emacsvox-table-ui-test--with-view (data &rest body)
  "Browse DATA and run BODY with native submissions captured in `spoken'."
  (declare (indent 1) (debug t))
  `(save-window-excursion
     (let ((view (generate-new-buffer " *table-browser-test*"))
           (emacsvox-table-reader-titles '(column))
           (emacsvox-table-reader-data-position 'first)
           (kill-ring nil) (kill-ring-yank-pointer nil) spoken)
       (unwind-protect
           (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                     ((symbol-function 'emacsvox-speak-mode-line) #'ignore)
                     ((symbol-function 'message) #'ignore)
                     ((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest args) (push (cons text args) spoken))))
             (emacsvox-table-prepare-table-buffer
              (emacsvox-table-make-table ,data) view)
             ,@body)
         (when (buffer-live-p view) (kill-buffer view))))))

(ert-deftest emacsvox-table-ui-shared-navigation-and-boundaries ()
  "Real keys read logical rows/cells once, including multiline and blank data."
  (emacsvox-table-ui-test--with-view
      [["Name" "Note"] ["Alice" "First\nSecond"] ["Bob" ""]]
    (let ((text (buffer-string)))
      (dolist (step '(("<down>" "Alice, Name. First\nSecond, Note." 1 0)
                       ("C-M-<right>" "First\nSecond, Note." 1 1)
                       ("C-M-<down>" "Bob, Name. blank, Note." 2 1)
                       ("<down>" "Bottom of table." 2 1)
                       ("C-M-<right>" "Right edge of table." 2 1)
                       ("C-M-<up>" "Alice, Name. First\nSecond, Note." 1 1)
                       ("C-M-<left>" "Alice, Name." 1 0)
                       ("<up>" "Header row. Name. Note." 0 0)
                       ("<up>" "Top of table." 0 0)))
        (setq spoken nil)
        (execute-kbd-macro (kbd (car step)))
        (should (= 1 (length spoken)))
        (should (equal (caar spoken) (nth 1 step)))
        (should (= (emacsvox-table-current-row emacsvox-table) (nth 2 step)))
        (should (= (emacsvox-table-current-column emacsvox-table) (nth 3 step)))
        (should (eq (plist-get (cdar spoken) :lane) 'main))
        (should (eq (plist-get (cdar spoken) :occasion) 'navigation)))
      (should (equal text (buffer-string))))))

(ert-deftest emacsvox-table-ui-character-motion-keeps-model-current ()
  "Character movement across delimiters and embedded newlines tracks the cell."
  (emacsvox-table-ui-test--with-view [["Name" "Note"] ["Alice" "First\nSecond"]]
    (execute-kbd-macro (kbd "<down>"))
    (execute-kbd-macro (kbd "C-u 6 <right>"))
    (should (looking-at "First"))
    (should (= 1 (emacsvox-table-current-column emacsvox-table)))
    (execute-kbd-macro (kbd "C-u 6 C-f"))
    (should (looking-at "Second"))
    (should (= 1 (emacsvox-table-current-row emacsvox-table)))
    (execute-kbd-macro (kbd "w"))
    (should (equal (car kill-ring) "First\nSecond"))
    (goto-char (point-max))
    (execute-kbd-macro (kbd "w"))
    (should (equal (car kill-ring) "First\nSecond"))
    (goto-char (point-min))
    (execute-kbd-macro (kbd "TAB"))
    (should (looking-at "Note"))
    (execute-kbd-macro (kbd "<backtab>"))
    (should (looking-at "Name"))))

(ert-deftest emacsvox-table-ui-inspection-copy-and-preferences ()
  "Shared inspection, copying, and local title preferences use complete data."
  (emacsvox-table-ui-test--with-view
      [["Name" "Note"] ["Alice" "First\nSecond"] ["Bob" ""]]
    (emacsvox-table-ui-next-row)
    (emacsvox-table-ui-next-column)
    (dolist (step '(("r" "Alice, Name. First\nSecond, Note.")
                     ("c" "Note. First\nSecond. blank.")
                     ("." "Data row 1 of 2, column 2 of 2.")
                     ("=" "Table, 2 data rows, 2 columns.")
                     ("RET" "First\nSecond, Note.")))
      (setq spoken nil)
      (execute-kbd-macro (kbd (car step)))
      (should (= 1 (length spoken)))
      (should (equal (caar spoken) (cadr step))))
    (dolist (step '(("k k" "First\nSecond")
                     ("k r" "Alice\tFirst\nSecond")
                     ("k c" "Note\nFirst\nSecond\n")))
      (execute-kbd-macro (kbd (car step)))
      (should (equal (car kill-ring) (cadr step))))
    (let ((emacsvox-table-clipboard nil))
      (execute-kbd-macro "K")
      (should (eq emacsvox-table-clipboard emacsvox-table)))
    (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) ?o)))
      (execute-kbd-macro "a"))
    (execute-kbd-macro (kbd "SPC"))
    (should (equal (caar spoken) "Note, First\nSecond."))
    (should (local-variable-p 'emacsvox-table-reader-data-position))
    (with-temp-buffer
      (should (eq emacsvox-table-reader-data-position 'first)))))

(ert-deftest emacsvox-table-ui-old-local-bindings-removed-prefix-preserved ()
  "The browser replaces its old controls without changing speech-prefix keys."
  (emacsvox-table-ui-test--with-view [["Name" "Note"] ["Alice" "Text"]]
    (dolist (key '("b" "n" "p" "A" "B" "E" "T"))
      (should-not (lookup-key emacsvox-table-mode-map (kbd key))))
    (should (eq (key-binding (kbd "C-f")) 'forward-char))
    (should (eq (key-binding (kbd "<left>")) 'left-char))
    (should (eq (lookup-key emacsvox-table-submap "r")
                'emacsvox-table-speak-row-header-and-element))
    (should (eq (lookup-key emacsvox-table-submap "k")
                'emacsvox-table-copy-to-clipboard))
    (should (eq (key-binding "q") 'quit-window))
    (should-not emacsvox-table-reader-mode)))

(ert-deftest emacsvox-table-ui-search-filters-and-sort-after-motion ()
  "Retained tools use the current cell after character motion and re-rendering."
  (emacsvox-table-ui-test--with-view
      [["Name" "Number"] ["Bob" "2"] ["Alice" "1"]]
    (execute-kbd-macro (kbd "<down> C-u 4 <right>"))
    (should (= 1 (emacsvox-table-current-column emacsvox-table)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "1")))
      (execute-kbd-macro "C"))
    (should (= 2 (emacsvox-table-current-row emacsvox-table)))
    (should (looking-at "1"))
    (let (filtered)
      (setq emacsvox-table-speak-row-filter '(0 "value" 1)
            emacsvox-table-speak-column-filter '(1 2))
      (cl-letf (((symbol-function 'message)
                 (lambda (text &rest _) (setq filtered text))))
        (execute-kbd-macro "f")
        (should (string-match-p "Alice.*value.*1" filtered))
        (execute-kbd-macro "g")
        (should (string-match-p "2.*1" filtered))))
    (setq-local emacsvox-table-reader-data-position 'last)
    (let ((sorted (generate-new-buffer " *sorted-table-test*")))
      (unwind-protect
          (cl-letf (((symbol-function 'get-buffer-create) (lambda (_) sorted)))
            (execute-kbd-macro "#")
            (should (eq (current-buffer) sorted))
            (should (looking-at "1"))
            (should (equal (plist-get (emacsvox-table-ui--snapshot) :row-title)
                           "Alice"))
            (execute-kbd-macro (kbd "<down>"))
            (should (equal (caar spoken) "Name, Bob. Number, 2."))
            (should (equal emacsvox-table-speak-row-filter '(0 "value" 1)))
            (should (equal emacsvox-table-speak-column-filter '(1 2))))
        (when (buffer-live-p sorted) (kill-buffer sorted))))))

(ert-deftest emacsvox-table-ui-native-plans ()
  "Browser submissions resolve with native policy and a foreground lane."
  (emacsvox-table-ui-test--with-view [["Name" "Note"] ["Alice" ""]]
    (execute-kbd-macro (kbd "<down> TAB SPC r c . = k r a c"))
    (dolist (submission spoken)
      (let* ((args (cdr submission))
             (facts (plist-get args :facts))
             (context (list :module 'table-ui :occasion (plist-get args :occasion)
                            :mode major-mode
                            :mode-lineage (list major-mode)))
             (plan (emacsvox-aural-resolve-active facts context)))
        (should (eq (plist-get args :module) 'table-ui))
        (should (emacsvox-aural-content-style-speak
                 (emacsvox-aural-render-plan-content plan)))
        (should (emacsvox-aural-compile-plan plan facts context))))))

(ert-deftest emacsvox-table-ui-graphical-multiline-navigation ()
  "A displayed wrapped multiline cell remains one logical cell and row."
  (skip-unless (display-graphic-p))
  (emacsvox-table-ui-test--with-view
      (vector ["Name" "Note"]
              (vector "Alice" (concat (make-string 200 ?x) "\nSecond line"))
              ["Bob" "Last"])
    (setq truncate-lines nil)
    (execute-kbd-macro (kbd "<down> TAB"))
    (set-window-hscroll nil 0)
    (redisplay t)
    (let ((start (point)))
      (vertical-motion 1)
      (should (> (point) start))
      (should (< (point) (+ start 200)))
      (execute-kbd-macro (kbd "w"))
      (should (equal (car kill-ring) (concat (make-string 200 ?x) "\nSecond line")))
      (execute-kbd-macro (kbd "<down>"))
      (should (looking-at "Last"))
      (should (equal (caar spoken) "Bob, Name. Last, Note."))
      (execute-kbd-macro (kbd "<up>"))
      (should (= start (point))))))

(provide 'emacsvox-table-ui-tests)
;;; emacsvox-table-ui-tests.el ends here
