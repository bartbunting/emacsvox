;;; emacsvox-aural-voice-menu-tests.el --- Focused tuning tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Exercise real menu keys, shared drafts, private previews and explicit saving.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-voice-editor-tests)
(require 'emacsvox-indentation-tests)
(require 'emacsvox-aural-voice-menu)

(defmacro emacsvox-test--with-voice-menu (&rest body)
  "Run BODY with a real graphical menu and an isolated named-voice draft."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (display-graphic-p))
     (save-window-excursion
       (emacsvox-test--with-indentation-menu
         (emacsvox-test--with-voice-editor
           (switch-to-buffer source)
           (insert "Source text")
           (goto-char 4)
           (emacsvox-aural-voice-editor-open 'reading-owned 'bolden source "Same sample")
           (let ((editor (current-buffer))
                 (context emacsvox-aural-voice-editor--context)
                 (transient--prefix nil) (transient-show-menu t)
                 (before (emacsvox-aural-read-user-data)))
             (unwind-protect
                 (progn (execute-kbd-macro (kbd "m")) ,@body)
               (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))))

(ert-deftest emacsvox-aural-voice-menu-graphical-adjust-reset-and-retain ()
  "Shift adjusts, plain arrows navigate, and leaving retains the same draft."
  (emacsvox-test--with-voice-menu
    (execute-kbd-macro (kbd "<down> <down>"))
    (let (announced)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (push text announced))))
        (execute-kbd-macro (kbd "S-<right> S-<right> S-<left>")))
      (should (equal (reverse announced) '("1" "2" "1"))))
    (should (= (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch) 1))
    (execute-kbd-macro (kbd "<right> <left>"))
    (should (= (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch) 1))
    (execute-kbd-macro (kbd "<down>"))
    (should (eq (emacsvox-aural-voice-menu--selected-dimension) 'average-pitch))
    (execute-kbd-macro (kbd "RET 8 RET S-<right> S-<right>"))
    (should (= (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch) 9))
    (execute-kbd-macro (kbd "d"))
    (should-not (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch))
    (execute-kbd-macro (kbd "u"))
    (should (= (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch) 9))
    (with-selected-window transient--window
      (transient--goto-button (transient-suffix-object 'emacsvox-aural-voice-menu--default)))
    (execute-kbd-macro (kbd "RET A TAB RET"))
    (should-not (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch))
    (execute-kbd-macro (kbd "u"))
    (should (emacsvox-aural-voice-editor--get :automatic-sample))
    (should-not requests)
    (should (equal before (emacsvox-aural-read-user-data)))
    (execute-kbd-macro (kbd "q"))
    (should (eq (current-buffer) editor))
    (should-not transient--prefix)
    (should (eq context emacsvox-aural-voice-editor--context))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Keep draft and return")))
      (execute-kbd-macro (kbd "q")))
    (should (eq (current-buffer) source))
    (should (= (point) 4))
    (emacsvox-aural-voice-editor-open 'reading-owned 'bolden source)
    (should (eq context emacsvox-aural-voice-editor--context))
    (should (= (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch) 9))))

(ert-deftest emacsvox-aural-voice-menu-graphical-compare-save-and-stop ()
  "Preview is private; comparison shares text, and only explicit save publishes."
  (emacsvox-test--with-voice-menu
    (execute-kbd-macro (kbd "p 8 RET T C-a C-k N e w SPC s a m p l e RET P B"))
    (should (= (length requests) 2))
    (let ((entries (car requests)))
      (should (= (length entries) 4))
      (should (equal (plist-get (nth 1 entries) :text) "New sample"))
      (should (equal (plist-get (nth 3 entries) :text) "New sample"))
      (should (= (plist-get (plist-get (nth 1 entries) :acss) :average-pitch) 0))
      (should (= (plist-get (plist-get (nth 3 entries) :acss) :average-pitch) (/ 8.0 9))))
    (should (equal before (emacsvox-aural-read-user-data)))
    (should-not callbacks)
    (execute-kbd-macro (kbd "w"))
    (should (= (length callbacks) 1))
    (should-not (equal before (emacsvox-aural-read-user-data)))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-voice-menu))
    (funcall (car callbacks) '(:status applied))
    (should-not (emacsvox-aural-voice-drafts--dirty-fields (emacsvox-aural-voice-editor--draft)))
    (cl-letf (((symbol-function 'emacsvox-aural-voice-editor--submit-preview)
               (lambda (_entries _callback _current) 'pending)))
      (execute-kbd-macro (kbd "P"))
      (should (eq emacsvox-aural-voice-editor--preview-owner context))
      (execute-kbd-macro (kbd "S"))
      (should-not emacsvox-aural-voice-editor--preview-owner)
      (execute-kbd-macro (kbd "P q"))
      (should-not emacsvox-aural-voice-editor--preview-owner))
    (should (eq (current-buffer) editor))))

(ert-deftest emacsvox-aural-voice-menu-graphical-collection-keeps-active-palette ()
  "Saving an inactive inherited voice creates its local entry without selection."
  (emacsvox-test--with-voice-menu
    (execute-kbd-macro (kbd "q"))
    (emacsvox-aural-voice-editor-open 'source-child 'bolden source)
    (execute-kbd-macro (kbd "m p 7 RET c"))
    (should (eq emacsvox-aural-voice-palette-override 'reading-owned))
    (should (= (plist-get (plist-get (emacsvox-aural-voice-runtime--resolve 'bolden 'source-child) :definition) :average-pitch) 7))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-voice-menu))))

(ert-deftest emacsvox-aural-voice-menu-graphical-cancel-and-scope-guard ()
  "Cancelled entry preserves values; a changed editor scope cannot be edited."
  (emacsvox-test--with-voice-menu
    (let ((original (emacsvox-aural-voice-editor--working)) cancelled)
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil))))
        (condition-case nil (emacsvox-aural-voice-menu--pitch) (quit (setq cancelled t))))
      (should cancelled)
      (should (equal original (emacsvox-aural-voice-editor--working)))
      (should (emacsvox-aural-voice-editor--get :automatic-sample))
      (emacsvox-aural-voice-editor--put :tuning-choice "changed-scope")
      (should-error (emacsvox-aural-voice-menu--edit 'average-pitch 1) :type 'user-error)
      (should (equal original (emacsvox-aural-voice-editor--working)))
      (emacsvox-aural-voice-editor--put :tuning-choice nil))))

(provide 'emacsvox-aural-voice-menu-tests)
;;; emacsvox-aural-voice-menu-tests.el ends here
