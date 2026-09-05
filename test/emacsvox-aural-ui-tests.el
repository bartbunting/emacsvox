;;; emacsvox-aural-ui-tests.el --- Shared aural interface tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test common interface identity, spoken navigation, and refresh preservation.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-ui)

(defvar-local emacsvox-test-aural-ui-entries nil)

(defun emacsvox-test-aural-ui--populate ()
  "Populate a test interface from `emacsvox-test-aural-ui-entries'."
  (setq tabulated-list-entries
        (copy-tree emacsvox-test-aural-ui-entries)))

(define-derived-mode emacsvox-test-aural-ui-mode
    emacsvox-aural-tabulated-mode
  "Test-Aural-UI"
  "Test mode for the common aural tabulated interface."
  (emacsvox-aural-ui-configure-tabulated
   "test rows" nil #'emacsvox-test-aural-ui--populate)
  (setq tabulated-list-format
        [("Name" 16 nil)
         ("Value" 16 nil)])
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header))

(ert-deftest emacsvox-aural-ui-registers-new-interface-modes ()
  "Interface recognition should not require a central mode-name list."
  (with-temp-buffer
    (emacsvox-aural-interface-mode)
    (should (emacsvox-aural-ui-interface-buffer-p))
    (should emacsvox-aural-ui-interface-buffer))
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (should (emacsvox-aural-ui-interface-buffer-p)))
  (with-temp-buffer
    (special-mode)
    (should-not (emacsvox-aural-ui-interface-buffer-p))))

(ert-deftest emacsvox-aural-ui-open-announces-semantic-interface-event ()
  "Opening an interface plays one remappable cue after displaying it."
  (let ((noninteractive nil)
        displayed
        events)
    (cl-letf
        (((symbol-function 'pop-to-buffer)
          (lambda (buffer)
            (setq displayed buffer)
            'selected-window))
         ((symbol-function 'emacsvox-aural-capture-context)
          (lambda (module occasion)
            (list :module module :occasion occasion)))
         ((symbol-function 'emacsvox-icon)
          (lambda (cue)
            (push
             (list
              cue
              (copy-tree emacsvox-aural-submission-facts)
              (copy-tree emacsvox-aural-submission-context)
              emacsvox-aural-submission-module
              emacsvox-aural-submission-occasion)
             events))))
      (should
       (eq
        (emacsvox-aural-ui-pop-to-buffer "*Aural Test*")
        'selected-window)))
    (should (equal displayed "*Aural Test*"))
    (should
     (equal
      events
      '((open-object
         (:role aural-interface :events (aural-interface-opened))
         (:module aural-tools :occasion state-change)
         aural-tools
         state-change))))))

(ert-deftest emacsvox-aural-ui-open-remains-silent-in-batch-sessions ()
  "Programmatic batch interface setup does not attempt audio output."
  (let ((noninteractive t))
    (cl-letf
        (((symbol-function 'pop-to-buffer) (lambda (_) 'selected-window))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _)
            (ert-fail "Batch interface opening must remain silent"))))
      (should
       (eq
        (emacsvox-aural-ui-pop-to-buffer "*Aural Test*")
        'selected-window)))))

(ert-deftest emacsvox-aural-ui-common-tabulated-bindings-are-consistent ()
  "All conventional row keys should use the spoken navigation commands."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (dolist (key '("n" "C-n" "<down>"))
      (should
       (eq (key-binding (kbd key))
           #'emacsvox-aural-ui-next-row)))
    (dolist (key '("p" "C-p" "<up>"))
      (should
       (eq (key-binding (kbd key))
           #'emacsvox-aural-ui-previous-row)))
    (should
     (eq (key-binding (kbd "<right>"))
         #'emacsvox-aural-ui-next-column))
    (should
     (eq (key-binding (kbd "<left>"))
         #'emacsvox-aural-ui-previous-column))
    (should
     (eq (key-binding (kbd "SPC"))
         #'emacsvox-aural-ui-speak-current-row))
    (should
     (eq (key-binding (kbd "q"))
         #'emacsvox-aural-quit))))

(ert-deftest emacsvox-aural-ui-help-quit-restores-exact-origin ()
  "Aural Help ignores stale window history and restores its invoking row."
  (save-window-excursion
    (let ((origin (generate-new-buffer " *Aural Help Origin*"))
          (home (generate-new-buffer " *Aural Help Wrong Return*")))
      (unwind-protect
          (let ((window (selected-window)))
            (switch-to-buffer origin)
            (insert "first\nsecond\nthird\n")
            (goto-char (point-min))
            (forward-line 1)
            (let ((origin-position (point)))
              (cl-letf
                  (((symbol-function 'emacsvox-speak-help)
                    (lambda ()
                      (pop-to-buffer (help-buffer))))
                   ((symbol-function 'quit-window)
                    (lambda (&optional _kill _window)
                      (set-window-buffer (selected-window) home)))
                   ((symbol-function 'emacsvox-icon) #'ignore)
                   ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
                (emacsvox-aural-ui-with-help-window
                  (princ "Aural help contents"))
                (emacsvox-speak-help)
                (should (eq (current-buffer) (get-buffer (help-buffer))))
                (should
                 (eq (key-binding (kbd "q"))
                     #'emacsvox-aural-ui-help-quit))
                (call-interactively #'emacsvox-aural-ui-help-quit))
              (should (= (point) origin-position)))
            (should (eq (window-buffer window) origin))
            (should (= (window-point window)
                       (with-current-buffer origin (point)))))
        (when (get-buffer "*Help*")
          (kill-buffer "*Help*"))
        (kill-buffer origin)
        (kill-buffer home)))))

(ert-deftest emacsvox-aural-ui-movement-preserves-column-and-runs-callbacks ()
  "Spoken row movement should preserve columns and run configured callbacks."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (setq emacsvox-test-aural-ui-entries
          '((first ["First" "one"])
            (second ["Second" "two"])))
    (emacsvox-aural-ui-refresh-tabulated
     #'emacsvox-test-aural-ui--populate)
    (let (spoken moved)
      (setq-local
       emacsvox-aural-ui-move-speaker
       (lambda () (push (tabulated-list-get-id) spoken)))
      (setq-local
       emacsvox-aural-ui-after-move-function
       (lambda () (push (tabulated-list-get-id) moved)))
      (emacsvox-aural-ui-goto-tabulated-column 1)
      (emacsvox-aural-ui-next-row)
      (should (eq (tabulated-list-get-id) 'second))
      (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
      (should (equal spoken '(second)))
      (should (equal moved '(second))))))

(ert-deftest emacsvox-aural-ui-cell-order-follows-movement-direction ()
  "Rows speak value first while columns and explicit cells speak title first."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (setq emacsvox-test-aural-ui-entries
          '((first ["First" "one"])
            (second ["Second" "two"])))
    (emacsvox-aural-ui-refresh-tabulated
     #'emacsvox-test-aural-ui--populate)
    (let (spoken)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text) (push text spoken)))
           ((symbol-function 'emacsvox-icon) #'ignore))
        (emacsvox-aural-ui-next-row)
        (emacsvox-aural-ui-next-column)
        (emacsvox-aural-ui-speak-current-cell)
        (emacsvox-aural-ui-previous-row))
      (should
       (equal
        (nreverse spoken)
        '("Second, Name"
          "Value, two"
          "Value, two"
          "one, Value"))))))

(ert-deftest emacsvox-aural-ui-supports-buffer-local-speech-renderers ()
  "Shared feedback can use a renderer confined to one interface buffer."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (let (spoken)
      (setq-local emacsvox-aural-ui-speech-function
                  (lambda (text) (push text spoken)))
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (_) (ert-fail "Used global speech")))
                ((symbol-function 'emacsvox-icon) #'ignore))
        (emacsvox-aural-ui-speak "Local feedback")
        (emacsvox-aural-ui-announce-boundary "Top of list."))
      (should (equal (nreverse spoken)
                     '("Local feedback" "Top of list."))))))

(ert-deftest emacsvox-aural-ui-refresh-preserves-compound-row-and-window-point ()
  "Refresh should preserve an equal row ID, column, and visible window point."
  (save-window-excursion
    (with-temp-buffer
      (emacsvox-test-aural-ui-mode)
      (setq emacsvox-test-aural-ui-entries
            '((first ["First" "one"])
              ((group . item) ["Grouped" "two"])
              (last ["Last" "three"])))
      (emacsvox-aural-ui-refresh-tabulated
       #'emacsvox-test-aural-ui--populate)
      (set-window-buffer (selected-window) (current-buffer))
      (emacsvox-aural-ui-goto-row '(group . item))
      (emacsvox-aural-ui-goto-tabulated-column 1)
      (setq emacsvox-test-aural-ui-entries
            '((last ["Last" "three"])
              ((group . item) ["Grouped again" "changed"])
              (first ["First" "one"])))
      (emacsvox-aural-ui-refresh-tabulated
       #'emacsvox-test-aural-ui--populate)
      (should (equal (tabulated-list-get-id) '(group . item)))
      (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
      (should (= (window-point (selected-window)) (point))))))

(ert-deftest emacsvox-aural-ui-boundary-keeps-row-and-announces-list ()
  "Moving beyond the list should retain point and announce the named boundary."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (setq emacsvox-test-aural-ui-entries
          '((only ["Only" "value"])))
    (emacsvox-aural-ui-refresh-tabulated
     #'emacsvox-test-aural-ui--populate)
    (let (spoken icons)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (push text spoken)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon icons))))
        (let ((position (point)))
          (should-not (emacsvox-aural-ui-next-row))
          (should (= (point) position))))
      (should (equal spoken '("Bottom of test rows.")))
      (should (equal icons '(warn-user))))))

(ert-deftest emacsvox-aural-ui-settings-movement-speaks-name-and-state ()
  "Moving down from a status cell names the new setting as well as its state."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (setq tabulated-list-format [("Name" 16 nil) ("Status" 16 nil)]
          emacsvox-test-aural-ui-entries
          '((first ["First" "on"]) (second ["Second" "off"]))
          emacsvox-aural-ui-move-speaker #'emacsvox-aural-ui-speak-name-and-state)
    (emacsvox-aural-ui-refresh-tabulated #'emacsvox-test-aural-ui--populate)
    (emacsvox-aural-ui-goto-tabulated-column 1)
    (let (spoken)
      (setq emacsvox-aural-ui-speech-function (lambda (text) (push text spoken)))
      (emacsvox-aural-ui-next-row)
      (should (equal spoken '("Second: off")))
      (should (= (emacsvox-aural-ui-tabulated-column-index) 1)))))

(ert-deftest emacsvox-aural-ui-actions-follow-effective-bindings-and-filter ()
  "Named actions honor shadowed bindings and row-specific applicability."
  (with-temp-buffer
    (emacsvox-test-aural-ui-mode)
    (use-local-map (copy-keymap (current-local-map)))
    (local-set-key (kbd "P") #'emacsvox-aural-ui-speak-current-row)
    (local-set-key (kbd "N") #'emacsvox-aural-ui-refresh)
    (should (eq (key-binding (kbd "C-c C-a")) #'emacsvox-aural-ui-actions))
    (should (eq (key-binding (kbd "S")) #'emacsvox-aural-ui-stop-preview))
    (let ((actions (mapcar #'cdr (emacsvox-aural-ui-action-candidates))))
      (should (memq 'emacsvox-aural-ui-refresh actions))
      (should-not (memq 'emacsvox-aural-ui-speak-current-row actions))
      (should-not (memq 'emacsvox-aural-ui-next-row actions)))
    (setq emacsvox-aural-ui-action-filter
          (lambda (command) (not (eq command 'emacsvox-aural-ui-refresh))))
    (should-not (memq 'emacsvox-aural-ui-refresh
                      (mapcar #'cdr (emacsvox-aural-ui-action-candidates))))))

(provide 'emacsvox-aural-ui-tests)

;;; emacsvox-aural-ui-tests.el ends here
