;;; emacsvox-manual-workflow-tests.el --- Manual interaction contracts -*- lexical-binding: t; -*-

;;; Commentary:

;; Command-level regressions for the maintained reading, recovery and Help
;; instructions.  Real editing and window commands run with output and the
;; external clipboard isolated.  The command helper models last-command and
;; mark deactivation; it is not a keyboard-event loop or a listening test.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-speak)
(require 'emacsvox-advice)
(require 'help-mode)

(defmacro emacsvox-manual-tests--without-output (&rest body)
  "Run BODY without speech processes, external clipboard writes or shared kills."
  (declare (indent 0) (debug t))
  `(let ((kill-ring nil)
         (kill-ring-yank-pointer nil)
         (interprogram-cut-function nil)
         (interprogram-paste-function nil)
         (select-enable-clipboard nil)
         (select-enable-primary nil)
         (select-active-regions nil)
         (transient-mark-mode t)
         (mark-even-if-inactive nil)
         (last-command nil)
         (real-last-command nil)
         (emacsvox-last-message nil)
         (emacsvox-delayed-phonetic-mode nil))
     (cl-letf (((symbol-function 'tts-speak) #'ignore)
               ((symbol-function 'tts-notify) #'ignore)
               ((symbol-function 'tts-letter) #'ignore)
               ((symbol-function 'tts-stop) #'ignore)
               ((symbol-function 'emacsvox-icon) #'ignore)
               ((symbol-function 'emacsvox-aural-submit) #'ignore)
               ((symbol-function 'emacsvox-aural-submit-actions) #'ignore))
       (save-window-excursion
         ,@body))))

(defun emacsvox-manual-tests--command (command &rest arguments)
  "Invoke COMMAND with ARGUMENTS and retain its resulting command identity.
Model the command-loop mark-deactivation boundary, but do not run global hooks.
ARGUMENTS are explicit: this helper does not test interactive prompt parsing."
  (let ((this-command command)
        (real-this-command command)
        (current-prefix-arg nil)
        (deactivate-mark nil))
    (prog1 (apply #'funcall-interactively command arguments)
      (when deactivate-mark (deactivate-mark))
      (setq last-command this-command
            real-last-command real-this-command))))

(ert-deftest emacsvox-manual-region-inspection-keeps-copy-boundaries ()
  "Reading a small active region preserves its endpoints and final newline."
  (emacsvox-manual-tests--without-output
    (with-temp-buffer
      (insert "First paragraph.\n\nSecond paragraph.\n")
      (goto-char (point-min))
      (push-mark (point) t t)
      (forward-line 1)
      (let ((source (buffer-string))
            (start (mark))
            (end (point))
            spoken)
        (cl-letf (((symbol-function 'tts-speak)
                   (lambda (text) (setq spoken (substring-no-properties text)))))
          (emacsvox-manual-tests--command #'emacsvox-speak-region start end))
        (should (equal spoken "First paragraph.\n"))
        (should (= (point) end))
        (should (= (mark) start))
        (should mark-active)
        (should (use-region-p))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       (substring-no-properties source)))
        (emacsvox-manual-tests--command #'kill-ring-save
                                        (region-beginning) (region-end))
        (should (equal (current-kill 0 t) "First paragraph.\n"))
        (with-temp-buffer
          (emacsvox-manual-tests--command #'yank nil)
          (should (equal (buffer-string) "First paragraph.\n")))))))

(ert-deftest emacsvox-manual-undo-only-survives-spoken-inspection ()
  "Two undo-only commands undo two edits even when line inspection intervenes."
  (emacsvox-manual-tests--without-output
    (with-temp-buffer
      (insert "Original.")
      (buffer-enable-undo)
      (insert " one")
      (undo-boundary)
      (insert " two")
      (undo-boundary)
      (emacsvox-manual-tests--command #'undo-only 1)
      (should (equal (buffer-string) "Original. one"))
      (emacsvox-manual-tests--command #'emacsvox-speak-line)
      (should (eq last-command 'emacsvox-speak-line))
      (emacsvox-manual-tests--command #'undo-only 1)
      (should (equal (buffer-string) "Original."))
      (emacsvox-manual-tests--command #'emacsvox-speak-line)
      (should (equal (buffer-string) "Original.")))))

(ert-deftest emacsvox-manual-yank-pop-after-inspection-inserts-a-new-choice ()
  "Immediate yank-pop replaces; yank-pop after reading asks for another insert."
  (emacsvox-manual-tests--without-output
    (with-temp-buffer
      (kill-new "older")
      (kill-new "newer")
      (emacsvox-manual-tests--command #'yank nil)
      (should (equal (buffer-string) "newer"))
      (emacsvox-manual-tests--command #'yank-pop 1)
      (should (equal (buffer-string) "older"))
      (should (eq last-command 'yank))
      (emacsvox-manual-tests--command #'emacsvox-speak-line)
      (let (prompted)
        (cl-letf (((symbol-function 'read-from-kill-ring)
                   (lambda (&rest _)
                     (setq prompted t)
                     "newer")))
          (emacsvox-manual-tests--command #'yank-pop 1))
        (should prompted)
        (should (equal (buffer-string) "oldernewer"))))))

(ert-deftest emacsvox-manual-help-selects-help-without-killing-work ()
  "Windowful Help removes splits, but both documents and unsaved text survive."
  (emacsvox-manual-tests--without-output
    (let ((draft (generate-new-buffer " *manual-draft*"))
          (reference (generate-new-buffer " *manual-reference*"))
          (help (generate-new-buffer " *manual-help*"))
          (real-get-buffer (symbol-function 'get-buffer)))
      (unwind-protect
          (save-window-excursion
            (with-current-buffer draft (insert "Unsaved draft.\n"))
            (with-current-buffer reference (insert "Reference passage.\n"))
            (with-current-buffer help
              (insert "Help heading.\nRead this explanation.\n")
              (goto-char (point-min))
              (help-mode))
            (switch-to-buffer draft)
            (delete-other-windows)
            (set-window-buffer (split-window-below) reference)
            (should (= (length (window-list)) 2))
            ;; Never rename, replace or erase a pre-existing *Help* buffer.
            (cl-letf (((symbol-function 'get-buffer)
                       (lambda (name)
                         (if (equal name "*Help*") help
                           (funcall real-get-buffer name)))))
              (emacsvox-manual-tests--command #'emacsvox-speak-help))
            (should (eq (window-buffer (selected-window)) help))
            (should (= (length (window-list)) 1))
            (should (buffer-live-p draft))
            (should (buffer-live-p reference))
            (should (buffer-modified-p draft))
            (should (equal (with-current-buffer draft (buffer-string))
                           "Unsaved draft.\n"))
            (should (equal (with-current-buffer reference (buffer-string))
                           "Reference passage.\n"))
            (emacsvox-manual-tests--command #'switch-to-buffer draft)
            (should (eq (window-buffer (selected-window)) draft)))
        (dolist (buffer (list help reference draft))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-manual-filename-inspection-changes-the-next-paste ()
  "Filename speech adds its path to the kill ring; the earlier copy remains."
  (emacsvox-manual-tests--without-output
    (with-temp-buffer
      (let ((buffer-file-name nil)
            (default-directory temporary-file-directory))
        (kill-new "Previously copied passage")
        (emacsvox-manual-tests--command #'emacsvox-speak-buffer-filename nil)
        (should (equal (current-kill 0 t) temporary-file-directory))
        (should (member "Previously copied passage" kill-ring))
        (emacsvox-manual-tests--command #'yank nil)
        (should (equal (buffer-string) temporary-file-directory))))))

(provide 'emacsvox-manual-workflow-tests)
;;; emacsvox-manual-workflow-tests.el ends here
