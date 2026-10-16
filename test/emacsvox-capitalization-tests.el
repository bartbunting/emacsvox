;;; emacsvox-capitalization-tests.el --- Capitalization menu tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Exercise scope, real menu focus, private cue drafts, and saved rule output.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-menu-tests)
(require 'emacsvox-aural-schemes-tests)
(require 'emacsvox-capitalization)

(defmacro emacsvox-test--with-capitalization (&rest body)
  "Run BODY with isolated settings, rule stores, and a real menu source."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-aural-menu
     (emacsvox-test--with-isolated-schemes
       (let* ((directory (make-temp-file "capitalization-menu-" t))
              (custom-file (expand-file-name "custom.el" directory))
              (user-init-file custom-file)
              (emacsvox-aural-schemes-file (expand-file-name "aural.el" directory))
              (emacsvox-capitalization--drafts (make-hash-table :test #'eq))
              (symbols '(tts-caps tts-split-caps emacsvox-capitalization-presentation))
              (defaults (mapcar (lambda (s) (cons s (default-value s))) symbols))
              (properties (mapcar (lambda (s) (cons s (copy-tree (symbol-plist s)))) symbols)))
         (unwind-protect
             (progn
               (set-default 'tts-caps nil)
               (set-default 'tts-split-caps t)
               (set-default 'emacsvox-capitalization-presentation 'tone)
               (setq-local tts-caps nil tts-split-caps t emacsvox-capitalization-presentation 'tone)
               ,@body)
           (dolist (entry defaults) (set-default (car entry) (cdr entry)))
           (dolist (entry properties) (setplist (car entry) (cdr entry)))
           (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
           (delete-directory directory t))))))

(defmacro emacsvox-test--with-capitalization-gui (&rest body)
  "Open Capitalization from the root in a real graphical frame for BODY."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (display-graphic-p))
     (save-window-excursion
       (emacsvox-test--with-capitalization
         (switch-to-buffer source)
         (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
         (let ((transient--prefix nil) (transient-show-menu t))
           (unwind-protect
               (progn (execute-kbd-macro (kbd "<f8> s c")) ,@body)
             (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-capitalization-menu-graphical-scope-preview-and-defaults ()
  "Options retain scope; preview reads displayed values and Save survives startup."
  (emacsvox-test--with-capitalization-gui
    (execute-kbd-macro (kbd "i c p S p o k e n TAB RET"))
    (should tts-caps)
    (should-not tts-split-caps)
    (should (eq emacsvox-capitalization-presentation 'spoken))
    (should-not (default-value 'tts-caps))
    (should (default-value 'tts-split-caps))
    (execute-kbd-macro (kbd "g"))
    (let (seen)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq seen (list text tts-caps tts-split-caps emacsvox-capitalization-presentation)))))
        (execute-kbd-macro (kbd "SPC")))
      (should (equal seen '("Capital camelCase NASA" nil t tone))))
    ;; A global toggle starts from the displayed global value, not the override.
    (execute-kbd-macro (kbd "i"))
    (should (default-value 'tts-caps))
    (should tts-caps)
    (execute-kbd-macro (kbd "g S"))
    (should-not (file-exists-p emacsvox-aural-schemes-file))
    (with-temp-buffer
      (let ((program (expand-file-name invocation-name invocation-directory)))
        (should (zerop (call-process program nil t nil "-Q" "--batch"
                                     "--eval" (format "(load %S nil t)" custom-file)
                                     "-L" emacsvox-lisp-directory "-l" "emacsvox-preamble"
                                     "--eval" "(prin1 (list (default-value 'tts-caps) (default-value 'tts-split-caps) (default-value 'emacsvox-capitalization-presentation)))")))
        (should (string-match-p "(t nil spoken)" (buffer-string)))))
    (execute-kbd-macro (kbd "q q q"))
    (should-not transient--prefix)
    (should (eq (current-buffer) source))
    (should (= (point) 3))))

(ert-deftest emacsvox-capitalization-menu-graphical-cue-drafts-and-focus ()
  "Cue drafts are separate, adjustable with shifted arrows, and retained on return."
  (emacsvox-test--with-capitalization-gui
    (execute-kbd-macro (kbd "g l <down> S-<right>"))
    (should (equal (emacsvox-capitalization--cue-values) '(465 . 20)))
    (execute-kbd-macro (kbd "RET 5 0 0 RET S-<left> <down> S-<right>"))
    (should (equal (emacsvox-capitalization--cue-values) '(475 . 25)))
    (let (plan)
      (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan)
                 (lambda (value) (setq plan value))))
        (execute-kbd-macro (kbd "SPC")))
      (should (= (emacsvox-aural-concrete-action-pitch (car (emacsvox-aural-concrete-plan-before plan))) 475))
      (should (= (emacsvox-aural-concrete-action-duration (car (emacsvox-aural-concrete-plan-before plan))) 25)))
    (should-not emacsvox-aural-user-rules)
    (should-not (file-exists-p emacsvox-aural-schemes-file))
    (let (stopped)
      (cl-letf (((symbol-function 'tts-stop) (lambda () (setq stopped t))))
        (execute-kbd-macro (kbd "s")))
      (should stopped))
    (execute-kbd-macro (kbd "d 0 RET"))
    (let (spoken)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (setq spoken text))))
        (execute-kbd-macro (kbd "S-<left>")))
      (should (equal spoken "Minimum. 0 milliseconds")))
    (execute-kbd-macro (kbd "d 2 5 RET"))
    (execute-kbd-macro (kbd "q a"))
    (should (equal (emacsvox-capitalization--cue-values) '(1300 . 20)))
    (execute-kbd-macro (kbd "q l"))
    (should (equal (emacsvox-capitalization--cue-values) '(475 . 25)))
    (execute-kbd-macro (kbd "D"))
    (should (equal (emacsvox-capitalization--cue-values) '(440 . 20)))
    (execute-kbd-macro (kbd "q"))
    (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))))

(defun emacsvox-test--capitalization-plan (kind presentation)
  "Resolve KIND and PRESENTATION with actual rule precedence and compilation."
  (let* ((facts (let ((tts-caps t) (emacsvox-capitalization-presentation presentation))
                  (append (tts--capitalization-facts kind) '(:content "Sample"))))
         (context (emacsvox-aural-context-at-point)))
    (emacsvox-aural-compile-plan (emacsvox-aural-resolve-active facts context) facts context)))

(ert-deftest emacsvox-capitalization-menu-graphical-save-rules-reload-and-reset ()
  "Saving replaces only this cue, preserves spoken labels, and loads from disk."
  (emacsvox-test--with-capitalization-gui
    (setq emacsvox-aural-user-rules
          '((:id unrelated-cap-test :match (:mode text-mode) :render (:content (:voice bolden)))))
    (let ((unrelated (copy-tree emacsvox-aural-user-rules)))
      (execute-kbd-macro (kbd "l p 6 0 0 RET d 3 0 RET S"))
      (should (equal (car emacsvox-aural-user-rules) (car unrelated)))
      (setq emacsvox-aural-user-rules nil)
      (emacsvox-aural-load-user-data)
      (dolist (presentation '(tone spoken-tone))
        (let* ((plan (emacsvox-test--capitalization-plan 'capital presentation))
               (actions (emacsvox-aural-concrete-plan-before plan))
               (tone (cl-find 'tone actions :key #'emacsvox-aural-concrete-action-kind)))
          (should tone)
          (should (= (emacsvox-aural-concrete-action-pitch tone) 600))
          (should (= (emacsvox-aural-concrete-action-duration tone) 30))
          (should (= (length actions) (if (eq presentation 'tone) 1 2)))))
      (let* ((plan (emacsvox-test--capitalization-plan 'all-caps 'tone))
             (tone (car (emacsvox-aural-concrete-plan-before plan))))
        (should (= (emacsvox-aural-concrete-action-pitch tone) 1300)))
      (dolist (presentation '(spoken custom none))
        (should-not (cl-find 'tone (emacsvox-aural-concrete-plan-before
                                   (emacsvox-test--capitalization-plan 'capital presentation))
                             :key #'emacsvox-aural-concrete-action-kind)))
      (execute-kbd-macro (kbd "r S"))
      (should (equal emacsvox-aural-user-rules unrelated))
      (should (equal (plist-get (emacsvox-aural-read-user-data) :user-rules) unrelated)))))

(ert-deftest emacsvox-capitalization-menu-graphical-save-conflicts-and-failure ()
  "Failed writes and conflicting personal edits keep the saved rules and draft."
  (emacsvox-test--with-capitalization-gui
    (execute-kbd-macro (kbd "l p 5 0 0 RET"))
    (cl-letf (((symbol-function 'emacsvox-aural-save-user-data)
               (lambda (&rest _) (error "Injected write failure"))))
      (should-error (emacsvox-capitalization--cue-save)))
    (should-not emacsvox-aural-user-rules)
    (should (equal (emacsvox-capitalization--cue-values) '(500 . 20)))
    (with-temp-buffer
      (setq-local emacsvox-aural-editor-scope 'personal emacsvox-aural-editor-dirty t)
      (should-error (emacsvox-capitalization--cue-save) :type 'user-error))
    (setq emacsvox-aural-user-rules (emacsvox-capitalization--rules 'capital '(700 . 20)))
    (should-error (emacsvox-capitalization--cue-save) :type 'user-error)
    (execute-kbd-macro (kbd "D"))
    (should (equal (emacsvox-capitalization--cue-values) '(700 . 20)))
    (let ((before (copy-tree emacsvox-aural-user-rules)))
      (cl-letf (((symbol-function 'read-number) (lambda (&rest _) -1)))
        (should-error (emacsvox-capitalization--cue-edit 'pitch) :type 'user-error))
      (should (equal before emacsvox-aural-user-rules)))))

(provide 'emacsvox-capitalization-tests)
;;; emacsvox-capitalization-tests.el ends here
