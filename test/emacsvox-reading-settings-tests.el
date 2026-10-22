;;; emacsvox-reading-settings-tests.el --- Line reading interaction tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Exercise drafts, persistence, complete previews and real menu navigation.
;;; Code:
(require 'ert)
(require 'emacsvox-reading-settings)
(require 'emacsvox-speak)

(defmacro emacsvox-test--with-reading-settings (&rest body)
  "Run BODY with private reading settings, source and Customize destination."
  (declare (indent 0) (debug t))
  `(let* ((emacsvox-reading-lines-defaults nil)
          (emacsvox-reading-lines-modes nil)
          (custom-file (make-temp-file "reading-custom-"))
          (user-init-file custom-file)
          (properties (mapcar (lambda (symbol) (cons symbol (copy-tree (symbol-plist symbol))))
                              '(emacsvox-reading-lines-defaults emacsvox-reading-lines-modes))))
     (unwind-protect
         (with-temp-buffer
           (let* ((source (current-buffer))
                  (transient--prefix
                   (transient-prefix :command 'emacsvox-reading-settings
                                     :scope (list :source source :position (copy-marker (point))
                                                  :settings (cons source nil)))))
             (cl-letf (((symbol-function 'emacsvox-reading-settings--say) #'ignore)
                       ((symbol-function 'emacsvox-transient--submit-text) #'ignore)
                       ((symbol-function 'tts-stop) #'ignore)
                       ((symbol-function 'emacsvox-icon) #'ignore))
               ,@body)))
       (dolist (entry properties) (setplist (car entry) (cdr entry)))
       (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
       (delete-file custom-file))))

(ert-deftest emacsvox-reading-settings-drafts-apply-and-discard ()
  "Menu entry and drafts preserve navigation; Apply targets the captured buffer."
  (emacsvox-test--with-reading-settings
    (should-not (plist-get (emacsvox-reading-settings--state) :values))
    (emacsvox-reading-settings--stage :mode 'visual)
    (should-not visual-line-mode)
    (with-temp-buffer
      (emacsvox-reading-settings--apply)
      (should-not visual-line-mode))
    (should visual-line-mode)
    (should line-move-visual)
    (emacsvox-reading-settings--stage :mode 'source)
    (emacsvox-reading-settings--discard)
    (should (eq 'visual (plist-get (emacsvox-reading-settings--values) :mode)))
    (should-error (emacsvox-reading-settings--save) :type 'user-error)
    (should (= 0 (file-attribute-size (file-attributes custom-file))))
    (emacsvox-reading-settings--inherit)
    (emacsvox-reading-settings--apply)
    (should-not visual-line-mode)))

(ert-deftest emacsvox-reading-settings-save-reloads-in-fresh-emacs ()
  "Mode and global choices survive restart without saving buffer overrides."
  (emacsvox-test--with-reading-settings
    (setf (plist-get (emacsvox-reading-settings--state) :scope) 'global)
    (emacsvox-reading-settings--discard)
    (emacsvox-reading-settings--stage :speech 'explicit)
    (emacsvox-reading-settings--save)
    (setf (plist-get (emacsvox-reading-settings--state) :scope) 'mode)
    (emacsvox-reading-settings--discard)
    (emacsvox-reading-settings--stage :mode 'visual)
    (emacsvox-reading-settings--save)
    (let ((emacs (expand-file-name invocation-name invocation-directory))
          (lisp (expand-file-name "../" (file-name-directory (locate-library "emacsvox-reading-lines")))))
      (with-temp-buffer
        (let* ((form `(progn
                        (require 'emacsvox-speak)
                        (load ,custom-file nil t)
                        (with-temp-buffer
                          (fundamental-mode)
                          (emacsvox-reading-lines--apply-mode)
                          (unless (and visual-line-mode line-move-visual
                                       (eq 'explicit (plist-get (emacsvox-reading-lines--values) :speech)))
                            (error "Saved preferences were not restored: %S" (emacsvox-reading-lines--values))))))
               (status (call-process emacs nil t nil "-Q" "--batch" "-L" lisp
                                     "-l" "emacsvox-preamble" "--eval" (prin1-to-string form))))
          (unless (zerop status) (ert-fail (buffer-string))))))))

(ert-deftest emacsvox-reading-settings-tone-editor-stages-correct-units ()
  "The shared tone editor converts gain and shaping and never saves the parent."
  (emacsvox-test--with-reading-settings
    (oset transient--prefix scope (plist-put (emacsvox-reading-settings--context) :reading-row 'middle))
    (let (provider)
      (cl-letf (((symbol-function 'emacsvox-tone-editor--open)
                 (lambda (_context value) (setq provider value))))
        (emacsvox-reading-settings--tone))
      (let ((data (funcall (plist-get provider :read))))
        (should (= 60 (plist-get data :volume)))
        (setq data (plist-put data :volume 35)
              data (plist-put data :pitch 700)
              data (plist-put data :waveform 'triangle))
        (funcall (plist-get provider :apply) data t)
        (should-not emacsvox-reading-lines-overrides)
        (should (= 0.35 (plist-get (emacsvox-reading-settings--values) :middle-volume)))
        (should (equal '(:waveform triangle)
                       (plist-get (plist-get (emacsvox-reading-settings--values) :middle-tone) :shape)))
        (should (eq 'earcon (plist-get (emacsvox-reading-settings--values) :middle-sound)))
        (should (eq 'earcon (plist-get (emacsvox-reading-settings--values) :first-sound)))))))

(ert-deftest emacsvox-reading-settings-preview-is-one-unsaved-sequence ()
  "Four preview objects and their independent rules enter one main transaction."
  (emacsvox-test--with-reading-settings
    (emacsvox-reading-settings--stage :speech 'brief)
    (emacsvox-reading-settings--tones)
    (emacsvox-reading-settings--stage :first-placement 'before)
    (emacsvox-reading-settings--stage :middle-placement 'alongside)
    (emacsvox-reading-settings--stage :last-placement 'after)
    (let (submissions)
      (cl-letf (((symbol-function 'process-live-p) (lambda (&rest _) t))
                ((symbol-function 'emacsvox-reading-lines--sound-unavailable) (lambda (&rest _) nil))
                ((symbol-function 'emacsvox-aural-preview-stop) #'ignore)
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest arguments) (push (cons text arguments) submissions))))
        (emacsvox-reading-settings--preview))
      (should (= 1 (length submissions)))
      (let* ((submission (car submissions)) (text (car submission))
             (context (plist-get (cdr submission) :context))
             (prepared (emacsvox-aural-prepare-text text nil context)))
        (should (eq 'main (plist-get (cdr submission) :lane)))
        (should (string-match-p "complete source line" prepared))
        (should (= 3 (length (plist-get context :buffer-rules))))
        (should (= 3 (length (delete-dups (mapcar (lambda (r) (plist-get r :id)) (plist-get context :buffer-rules)))))))
    (should-not emacsvox-reading-lines-overrides)
    (should (= 0 (file-attribute-size (file-attributes custom-file)))))))

(ert-deftest emacsvox-reading-settings-bulk-controls-preserve-identities ()
  "Common volume and placement retain each sound, while individual choices vary."
  (emacsvox-test--with-reading-settings
    (emacsvox-reading-settings--stage :first-sound 'tone)
    (emacsvox-reading-settings--stage :middle-cue 'button)
    (let ((initial (emacsvox-reading-settings--values)))
      (cl-letf (((symbol-function 'emacsvox-aural-menu--read-number) (lambda (&rest _) 25)))
        (emacsvox-reading-settings--all-volume))
      (let ((values (emacsvox-reading-settings--values)))
        (dolist (type '(first middle last))
          (should (= 0.25 (plist-get values (emacsvox-reading-lines--key type 'volume))))
          (dolist (field '(sound cue tone placement))
            (let ((key (emacsvox-reading-lines--key type field)))
              (should (equal (plist-get initial key) (plist-get values key))))))))))

(ert-deftest emacsvox-speak-navigation-graphical-reading-menu ()
  "Real menu movement stages choices without applying them; Save is explicit."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-reading-settings
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-reading-settings)
      (let ((transient--prefix nil) (transient-show-menu t))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "<f8> m <down>"))
              (should-not (buffer-local-value 'visual-line-mode source))
              (execute-kbd-macro (kbd "2"))
              (should (eq 'emacsvox-reading-settings (oref transient--prefix command)))
              (should-not (buffer-local-value 'visual-line-mode source))
              (execute-kbd-macro (kbd "a"))
              (should (buffer-local-value 'visual-line-mode source))
              (execute-kbd-macro (kbd "2 s 2 p 3 q"))
              (should (eq 'tone (plist-get (emacsvox-reading-settings--values) :middle-sound)))
              (should (eq 'after (plist-get (emacsvox-reading-settings--values) :middle-placement)))
              (should-not (plist-member (buffer-local-value 'emacsvox-reading-lines-overrides source) :middle-sound))
              (should (string-match-p "structured timeline"
                                      (emacsvox-reading-lines--sound-unavailable (emacsvox-reading-settings--values) 'middle))))
          (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))

(ert-deftest emacsvox-speak-navigation-graphical-row-position-and-resize ()
  "Row inspection preserves point and recomputes after resize and hidden text."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert (mapconcat #'identity (make-list 70 "visible prose") " "))
      (visual-line-mode 1)
      (goto-char (point-min))
      (beginning-of-visual-line 2)
      (let ((position (point)) first second)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (setq first text))))
          (emacsvox-speak-row-position))
        (should (string-match-p "screen row 2 of" first))
        (should (= position (point)))
        (split-window-right)
        (redisplay t)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (setq second text))))
          (emacsvox-speak-row-position))
        (should-not (equal first second))
        (should (= position (point)))))))

(ert-deftest emacsvox-speak-navigation-graphical-reading-search-and-help ()
  "Settings search opens the real control; Help preserves the unapplied draft."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-settings)
  (require 'emacsvox-comint)
  (save-window-excursion
    (emacsvox-test--with-reading-settings
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient--stack nil) (transient-show-menu t))
        (unwind-protect
            (progn
              (execute-kbd-macro
               (vconcat (kbd "<f8> /") "Line reading, visual wrapping, continuation and screen rows" (kbd "RET")))
              (should (eq (oref transient--prefix command) 'emacsvox-reading-settings))
              (with-selected-window transient--window
                (should (equal "m" (oref (button-get (button-at (point)) 'button-data) key))))
              (execute-kbd-macro (kbd "m ? 2"))
              (should (derived-mode-p 'help-mode))
              (should (string-match-p "displayed row" (buffer-string)))
              (execute-kbd-macro (kbd "q 2 h"))
              (should (derived-mode-p 'help-mode))
              (should (string-match-p "Applied source preferences" (buffer-string)))
              (execute-kbd-macro (kbd "q"))
              (should (eq 'visual (plist-get (emacsvox-reading-settings--values) :mode)))
              (should-not (buffer-local-value 'visual-line-mode source)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))

(ert-deftest emacsvox-speak-navigation-graphical-reading-library-return ()
  "The recording library returns to the retained reading draft without applying it."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-sound-library)
  (save-window-excursion
    (emacsvox-test--with-reading-settings
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-reading-settings)
      (let ((transient--prefix nil) (transient--stack nil) (transient-show-menu t)
            (emacsvox-sound-library-directory (make-temp-file "reading-library-" t)))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "<f8> t 2 l"))
              (should (derived-mode-p 'emacsvox-sound-library-mode))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-reading-settings))
              (should (eq 'tone (plist-get (emacsvox-reading-settings--values) :middle-sound)))
              (should-not (buffer-local-value 'emacsvox-reading-lines-overrides source)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q")))
          (delete-directory emacsvox-sound-library-directory t))))))

(ert-deftest emacsvox-speak-navigation-graphical-row-font-and-hidden-overlay ()
  "Row counts follow displayed font size and invisible overlays without cached bounds."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert (mapconcat #'identity (make-list 60 "wrapped words") " "))
      (visual-line-mode 1)
      (goto-char (point-min))
      (let (normal enlarged folded overlay)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (setq normal text))))
          (emacsvox-speak-row-position))
        (put-text-property (point-min) (point-max) 'face '(:height 2.0))
        (redisplay t)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (setq enlarged text))))
          (emacsvox-speak-row-position))
        (should-not (equal normal enlarged))
        (setq overlay (make-overlay 14 (point-max)))
        (overlay-put overlay 'invisible t)
        (redisplay t)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (setq folded text))))
          (emacsvox-speak-row-position))
        (should (string-match-p "screen row 1 of 1" folded))
        (let ((start (point)))
          (end-of-visual-line)
          (should (eq 'complete (plist-get (emacsvox-speak--visual-row start (point)) :type))))))))

(provide 'emacsvox-reading-settings-tests)
;;; emacsvox-reading-settings-tests.el ends here
