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

(provide 'emacsvox-aural-ui-tests)

;;; emacsvox-aural-ui-tests.el ends here
