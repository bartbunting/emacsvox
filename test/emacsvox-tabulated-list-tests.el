;;; emacsvox-tabulated-list-tests.el --- Tabulated List advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tabulated List advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let* ((suffix (if (equal (getenv "EMACSVOX_TABULATED_TEST_LOAD") "compiled")
                   ".elc" ".el"))
       (directory (expand-file-name "../lisp/"
                                    (file-name-directory
                                     (or load-file-name buffer-file-name)))))
  (dolist (entry '(("emacsvox-table-reader" . emacsvox-table-reader-mode)
                   ("emacsvox-tabulated-list" . emacsvox-tabulated-list--snapshot)))
    (let ((file (expand-file-name (concat (car entry) suffix) directory)))
      (load file nil nil t)
      (should (equal (file-truename file)
                     (file-truename (symbol-file (cdr entry) 'defun)))))))

(defconst emacsvox-test--tabulated-list-after-advice
  '((tabulated-list-next-column
     emacsvox--advice-tabulated-list-next-column-after)
    (tabulated-list-previous-column
     emacsvox--advice-tabulated-list-previous-column-after))
  "Native after-advice registrations in the Tabulated List integration.")

(ert-deftest emacsvox-tabulated-list-advice-is-directly-registered ()
  "Tabulated List advice uses native advice directly."
  (dolist (entry emacsvox-test--tabulated-list-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-tabulated-list-empty-field-policy-uses-named-tone ()
  "Empty fields resolve the compatibility tone through aural policy."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:role field :states (empty))
             '(:module tabulated-list
               :mode tabulated-list-mode
               :occasion navigation)))
           (action (car (emacsvox-aural-render-plan-before plan))))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(tabulated-list-empty-field-tone)))
      (should (eq (emacsvox-aural-action-kind action) 'tone))
      (should (eq (emacsvox-aural-action-tone action) 'field-empty)))))

(ert-deftest emacsvox-tabulated-list-empty-cell-preserves-edge-order ()
  "Edge cues share the action-only presentation for an empty cell."
  (with-temp-buffer
    (insert (propertize "xy" 'tabulated-list-column-name "Only"
                        'tabulated-list-entry [""]))
    (goto-char 2)
    (let ((tabulated-list-format '(("Only" 10 t)))
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "An empty programmatic cell submitted text")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (push (cons 'submit-actions arguments) events))))
        (emacsvox-tabulated-list-speak-cell))
      (pcase-let* ((`((submit-actions . ,arguments)) events)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role field :states (empty))))
        (should (eq (plist-get arguments :module) 'tabulated-list))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(left right)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-phase actions)
          '(before before)))))))

(ert-deftest emacsvox-tabulated-list-nonempty-cell-submits-content ()
  "A nonempty cell is submitted once with field semantics."
  (with-temp-buffer
    (insert (propertize "xy" 'tabulated-list-column-name "Middle"
                        'tabulated-list-entry ["left" "value" "right"]))
    (goto-char 2)
    (let ((tabulated-list-format
           '(("Left" 10 t) ("Middle" 10 t) ("Right" 10 t)))
          submitted)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submitted (cons content arguments))))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _)
              (ert-fail "A nonempty cell submitted actions only"))))
        (emacsvox-tabulated-list-speak-cell))
      (should (equal (car submitted) "value"))
      (should
       (equal (plist-get (cdr submitted) :facts) '(:role field)))
      (should (eq (plist-get (cdr submitted) :module) 'tabulated-list))
      (should
       (eq (plist-get (cdr submitted) :occasion) 'navigation)))))

(ert-deftest emacsvox-tabulated-list-preserves-owning-module ()
  "Embedded tables submit under their integration's semantic module."
  (with-temp-buffer
    (setq-local emacsvox-aural-module 'magit)
    (let (arguments)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (_content &rest rest) (setq arguments rest))))
        (emacsvox-tabulated-list--submit-cell
         "repo" '(:role field) 'select-object))
      (should (eq (plist-get arguments :module) 'magit))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get arguments :compatibility-actions))
        '(select-object))))))

(ert-deftest emacsvox-tabulated-list-feedback-is-target-aware ()
  "Only the matching column movement cues and speaks the selected cell."
  (let ((ems--interactive-fn-name 'tabulated-list-next-column)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-tabulated-list-speak-cell)
          (lambda (&optional icon)
            (push (list 'speak-cell icon) events))))
      (emacsvox--advice-tabulated-list-previous-column-after)
      (emacsvox--advice-tabulated-list-next-column-after))
    (should
     (equal
      (nreverse events)
      '((speak-cell select-object))))))

(defmacro emacsvox-tabulated-list-test--with-reader (&rest body)
  "Run BODY in a real printed list, recording aural submissions in `spoken'."
  (declare (indent 0))
  `(with-temp-buffer
     (delay-mode-hooks (tabulated-list-mode))
     (setq tabulated-list-format [("Name" 6 t) ("Role" 10 t)]
           tabulated-list-sort-key nil
           tabulated-list-entries
           (copy-tree '((alice ["Alice, complete name" "Engineer"])
                        (bob ["Bob" ""])
                        (carol ["Carol" "Writer"])) t))
     (tabulated-list-init-header)
     (tabulated-list-print)
     (goto-char (point-min))
     (let ((emacsvox-table-reader-titles '(column))
           (emacsvox-table-reader-data-position 'first)
           (kill-ring nil) (kill-ring-yank-pointer nil) spoken)
       (cl-letf (((symbol-function 'emacsvox-aural-submit)
                  (lambda (text &rest args) (push (cons text args) spoken))))
         ,@body))))

(ert-deftest emacsvox-tabulated-list-reader-complete-values-and-blank ()
  "Read logical values, including truncated labels and empty final columns."
  (emacsvox-tabulated-list-test--with-reader
    (emacsvox-table-reader-mode 1)
    (should (string-match-p "Alice, complete name" (caar spoken)))
    (emacsvox-table-reader-next-column)
    (should (equal (caar spoken) "Engineer, Role."))
    (setq spoken nil)
    (emacsvox-table-reader-next-row)
    (should (= (length spoken) 1))
    (should (equal (caar spoken) "Bob, Name. blank, Role."))
    (emacsvox-table-reader-speak-cell)
    (should (equal (caar spoken) "blank, Role."))
    (should (equal (plist-get (cdar spoken) :facts) '(:role field :states (empty))))
    (emacsvox-table-reader-speak-context)
    (should (equal (caar spoken) "Row 2 of 3, column 2 of 2."))
    (emacsvox-table-reader-copy-row)
    (should (equal (car kill-ring) "Bob\t"))
    (emacsvox-table-reader-copy-column)
    (should (equal (car kill-ring) "Engineer\n\nWriter"))
    (should-not (buffer-modified-p))))

(ert-deftest emacsvox-tabulated-list-reader-buttons-retain-actions ()
  "Application and button actions win over printable shared-reader keys."
  (emacsvox-tabulated-list-test--with-reader
    (setq tabulated-list-entries
          `((button [,(list "Open item" 'action #'ignore) "Action"])))
    (tabulated-list-print)
    (goto-char (point-min))
    (use-local-map (copy-keymap (current-local-map)))
    (dolist (key '("r" "c" "k" "w" "a" "=" "." "t" "T" "g"))
      (local-set-key (kbd key) #'ignore))
    (let* ((keys '("RET" "SPC" "TAB" "r" "c" "k" "w" "a" "=" "." "g"))
           (bindings (mapcar (lambda (key) (key-binding (kbd key))) keys)))
      (emacsvox-table-reader-mode 1)
      (should (equal bindings (mapcar (lambda (key) (key-binding (kbd key))) keys))))
    (should (eq (key-binding (kbd "<down>")) #'emacsvox-table-reader-next-row))
    (should (eq (key-binding (kbd "<right>")) #'right-char))
    (emacsvox-table-reader-copy-cell)
    (should (equal (car kill-ring) "Open item"))
    (emacsvox-table-reader-mode -1)
    (should (eq (key-binding (kbd "<right>")) #'tabulated-list-next-column))
    (should-not emacsvox-table-reader--map-override)))

(ert-deftest emacsvox-tabulated-list-reader-display-order-and-refresh ()
  "Sorting and filtering use printed entries and refresh retires the reader."
  (emacsvox-tabulated-list-test--with-reader
    (setq tabulated-list-sort-key '("Name" . t))
    (tabulated-list-print)
    (goto-char (point-min))
    (emacsvox-table-reader-mode 1)
    (should (string-match-p "Carol" (caar spoken)))
    ;; A producer must not be called merely to inspect the visible table.
    (setq tabulated-list-entries (lambda () (ert-fail "Reader invoked producer")))
    (emacsvox-table-reader-next-row)
    (should (equal (tabulated-list-get-id) 'bob))
    (setq tabulated-list-entries '((new ["New" "Reader"])))
    (tabulated-list-print)
    (should-not emacsvox-table-reader-mode)
    (should-not emacsvox-table-reader--map-override)
    (goto-char (point-min))
    (emacsvox-table-reader-mode 1)
    (should (string-match-p "New" (caar spoken)))
    (emacsvox-table-reader-speak-dimensions)
    (should (equal (caar spoken) "Table, 1 row, 2 columns."))))

(ert-deftest emacsvox-tabulated-list-reader-hidden-rows-and-boundaries ()
  "Invisible rows are omitted, and standalone boundaries leave point intact."
  (emacsvox-tabulated-list-test--with-reader
    (save-excursion
      (forward-line 1)
      (overlay-put (make-overlay (point) (line-beginning-position 2)) 'invisible t))
    (emacsvox-table-reader-mode 1)
    (emacsvox-table-reader-next-row)
    (should (equal (tabulated-list-get-id) 'carol))
    (emacsvox-table-reader-speak-dimensions)
    (should (equal (caar spoken) "Table, 2 rows, 2 columns."))
    (let ((origin (point)))
      (emacsvox-table-reader-next-row)
      (should (= origin (point)))
      (should (equal (caar spoken) "No content after table.")))
    (emacsvox-table-reader-copy-column)
    (should (equal (car kill-ring) "Alice, complete name\nCarol"))))

(ert-deftest emacsvox-tabulated-list-reader-entry-and-empty-rejection ()
  "The first modified arrow enters once; empty tables retain application keys."
  (emacsvox-tabulated-list-test--with-reader
    (call-interactively (key-binding (kbd "C-M-<down>")))
    (should emacsvox-table-reader-mode)
    (should (= (length spoken) 1))
    (should (equal (caar spoken) "Table reading. Bob, Name. blank, Role."))
    (setq tabulated-list-entries nil)
    (tabulated-list-print)
    (should-not emacsvox-table-reader-mode)
    (should-error (emacsvox-table-reader-mode 1) :type 'user-error)
    (should-not emacsvox-table-reader-mode)
    (should-not (eq (key-binding (kbd "<down>")) #'emacsvox-table-reader-next-row))))

(ert-deftest emacsvox-tabulated-list-reader-aural-application-bindings ()
  "Aural editors retain actions and restore selected-cell navigation on exit."
  (require 'emacsvox-aural-ui)
  (emacsvox-tabulated-list-test--with-reader
    (use-local-map emacsvox-aural-tabulated-mode-map)
    (setq-local emacsvox-aural-module 'aural-tools)
    (let* ((keys '("SPC" "g" "S" "." "C-c C-a" "C-c C-i" "n" "p"))
           (bindings (mapcar (lambda (key) (key-binding (kbd key))) keys)))
      (emacsvox-table-reader-mode 1)
      (should (equal bindings (mapcar (lambda (key) (key-binding (kbd key))) keys)))
      (should (eq (plist-get (cdar spoken) :module) 'aural-tools))
      (emacsvox-table-reader-mode -1)
      (should (eq (key-binding (kbd "<down>")) #'emacsvox-aural-ui-next-row)))))

(ert-deftest emacsvox-tabulated-list-reader-graphical-navigation ()
  "Real displayed columns, truncation and buttons retain logical navigation."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-tabulated-list-test--with-reader
      (switch-to-buffer (current-buffer))
      (redisplay t)
      (should (pos-visible-in-window-p (point)))
      (emacsvox-table-reader-mode 1)
      (emacsvox-table-reader-next-column)
      (redisplay t)
      (should (equal (get-text-property (point) 'tabulated-list-column-name) "Role"))
      (should (pos-visible-in-window-p (point)))
      (emacsvox-table-reader-next-row)
      (emacsvox-table-reader-next-row)
      (redisplay t)
      (should (equal (tabulated-list-get-id) 'carol))
      (should (equal (get-text-property (point) 'tabulated-list-column-name) "Role"))
      (should (pos-visible-in-window-p (point)))
      (should-not (buffer-modified-p)))))

(provide 'emacsvox-tabulated-list-tests)
;;; emacsvox-tabulated-list-tests.el ends here
