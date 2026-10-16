;;; emacsvox-capitalization-tests.el --- Capitalization menu tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Exercise scope, real menu focus, private cue drafts, and Customize persistence and legacy rule migration.
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
              (symbols '(tts-caps tts-split-caps emacsvox-capitalization-presentation
                         emacsvox-capitalization-capital-tone emacsvox-capitalization-all-caps-tone))
              (defaults (mapcar (lambda (s) (cons s (default-value s))) symbols))
              (properties (mapcar (lambda (s) (cons s (copy-tree (symbol-plist s)))) symbols)))
         (unwind-protect
             (progn
               (set-default 'tts-caps nil)
               (set-default 'tts-split-caps t)
               (set-default 'emacsvox-capitalization-presentation 'tone)
               (dolist (symbol '(emacsvox-capitalization-capital-tone emacsvox-capitalization-all-caps-tone))
                 (set-default symbol (eval (car (get symbol 'standard-value)) t)))
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
                                     "--eval" (format "(progn (setq load-prefer-newer t) (load %S nil t))" custom-file)
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

(ert-deftest emacsvox-capitalization-menu-graphical-save-customize-and-reset ()
  "Save writes Customize without touching personal rules; reset restores defaults."
  (emacsvox-test--with-capitalization-gui
    (setq emacsvox-aural-user-rules
          '((:id unrelated-cap-test :match (:mode text-mode) :render (:content (:voice bolden)))))
    (let ((unrelated (copy-tree emacsvox-aural-user-rules)))
      (execute-kbd-macro (kbd "l p 6 0 0 RET d 3 0 RET S"))
      (should (equal emacsvox-aural-user-rules unrelated))
      (should-not (file-exists-p emacsvox-aural-schemes-file))
      (should (file-exists-p custom-file))
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
      (should (= (plist-get emacsvox-capitalization-capital-tone :pitch) 440))
      (should (equal emacsvox-aural-user-rules unrelated)))))

(defmacro emacsvox-test--with-capitalization-cue (kind &rest body)
  "Run BODY with a captured cue of KIND."
  (declare (indent 1) (debug t))
  `(let* ((cue (emacsvox-capitalization--draft ,kind))
          (transient--prefix
           (transient-prefix :command 'emacsvox-capitalization-cue
                             :scope (plist-put (copy-sequence context) :cue-draft cue))))
     ,@body))

(ert-deftest emacsvox-capitalization-shared-editor-apply-save-and-fresh-reload ()
  "Apply changes live defaults; Save persists full tones for a fresh Emacs."
  (emacsvox-test--with-capitalization
    (dolist (kind '(capital all-caps))
      (emacsvox-test--with-capitalization-cue kind
        (cl-letf (((symbol-function 'transient-setup)
                   (lambda (command &rest args)
                     (setq transient--prefix
                           (transient-prefix :command command :scope (plist-get (nthcdr 2 args) :scope))))))
          (emacsvox-capitalization--edit-tone))
        (emacsvox-tone-editor--put :waveform 'triangle)
        (emacsvox-tone-editor--put :volume 40)
        (emacsvox-tone-editor--put :sweep t)
        (emacsvox-tone-editor--put :end-pitch 700)
        (should (= (plist-get (default-value (emacsvox-capitalization--option kind)) :volume) 1.0))
        (emacsvox-tone-editor--apply)
        (should-not emacsvox-aural-user-rules)
        (should-not (file-exists-p emacsvox-aural-schemes-file))
        (let ((current (funcall (plist-get (plist-get (emacsvox-tone-editor--state) :provider) :current))))
          (should (= (plist-get current :volume) 40)))
        (dolist (presentation '(tone spoken-tone))
          (let* ((actions (emacsvox-aural-concrete-plan-before
                           (emacsvox-test--capitalization-plan kind presentation)))
                 (tone (cl-find 'tone actions :key #'emacsvox-aural-concrete-action-kind)))
            (should (= (emacsvox-aural-concrete-action-requested-volume tone) 0.4))
            (should (equal (emacsvox-aural-concrete-action-shape tone)
                           '(:waveform triangle :end-frequency-hz 700)))
            (should (= (length actions) (if (eq presentation 'tone) 1 2)))))
        (emacsvox-tone-editor--save)))
    (with-temp-buffer
      (should
       (zerop
        (call-process
         (expand-file-name invocation-name invocation-directory) nil t nil "-Q" "--batch"
         "--eval" (format "(progn (setq load-prefer-newer t) (load %S nil t))" custom-file)
         "-L" emacsvox-lisp-directory "-l" "emacsvox-preamble"
         "--eval" "(prin1 (mapcar (lambda (tone) (list (plist-get tone :volume) (plist-get tone :shape))) (list emacsvox-capitalization-capital-tone emacsvox-capitalization-all-caps-tone)))")))
      (should (string-match-p
               (regexp-quote "((0.4 (:waveform triangle :end-frequency-hz 700)) (0.4 (:waveform triangle :end-frequency-hz 700)))")
               (buffer-string))))))

(ert-deftest emacsvox-capitalization-save-migrates-only-unchanged-menu-rules ()
  "Save imports legacy pairs and full tones, leaving other cues and rules intact."
  (emacsvox-test--with-capitalization
    (dolist (values '((600 . 30) (21.5 . 2.5)
                     (:pitch 750 :duration 45 :volume 0.4 :shape (:waveform triangle))))
      (setq emacsvox-capitalization--drafts (make-hash-table :test #'eq)
            emacsvox-aural-user-rules
            (append (emacsvox-capitalization--rules 'capital values)
                    (emacsvox-capitalization--rules 'all-caps '(1500 . 25))
                    '((:id contextual :match (:mode text-mode) :render (:content (:voice bolden))))))
      (emacsvox-aural-save-user-data)
      (let ((others (copy-tree (nthcdr 2 emacsvox-aural-user-rules))))
        (emacsvox-test--with-capitalization-cue 'capital
          (should-error (emacsvox-capitalization--cue-apply) :type 'user-error)
          (emacsvox-capitalization--cue-save)
          (should (equal emacsvox-aural-user-rules others))
          (setq emacsvox-aural-user-rules nil)
          (emacsvox-aural-load-user-data)
          (should (equal emacsvox-aural-user-rules others))
          (dolist (presentation '(tone spoken-tone))
            (let ((tone (cl-find 'tone (emacsvox-aural-concrete-plan-before
                                       (emacsvox-test--capitalization-plan 'capital presentation))
                                 :key #'emacsvox-aural-concrete-action-kind)))
              (should (= (emacsvox-aural-concrete-action-pitch tone)
                         (if (numberp (car values)) (car values) (plist-get values :pitch)))))))))))

(ert-deftest emacsvox-capitalization-customize-preserves-contextual-overrides ()
  "A hand-edited old menu rule remains higher priority than the basic defaults."
  (emacsvox-test--with-capitalization
    (setq emacsvox-aural-user-rules (emacsvox-capitalization--rules 'capital '(900 . 35)))
    (dolist (rule emacsvox-aural-user-rules)
      (setf (plist-get rule :match) (append (plist-get rule :match) '(:mode text-mode))))
    (emacsvox-aural-save-user-data)
    (let ((before (copy-tree emacsvox-aural-user-rules)))
      (emacsvox-test--with-capitalization-cue 'capital
        (setf (plist-get (plist-get cue :values) :pitch) 500)
        (emacsvox-capitalization--cue-save)
        (should (equal emacsvox-aural-user-rules before))
        (should (equal (plist-get (emacsvox-aural-read-user-data) :user-rules) before))
        (text-mode)
        (should (= (emacsvox-aural-concrete-action-pitch
                    (car (emacsvox-aural-concrete-plan-before
                          (emacsvox-test--capitalization-plan 'capital 'tone)))) 900))
        (fundamental-mode)
        (should (= (emacsvox-aural-concrete-action-pitch
                    (car (emacsvox-aural-concrete-plan-before
                          (emacsvox-test--capitalization-plan 'capital 'tone)))) 500))))))

(ert-deftest emacsvox-capitalization-save-failure-conflict-and-migration-retry ()
  "Failed Customize and rule writes preserve recoverable settings; stale drafts fail."
  (emacsvox-test--with-capitalization
    (setq emacsvox-aural-user-rules (emacsvox-capitalization--rules 'capital '(700 . 20)))
    (emacsvox-aural-save-user-data)
    (emacsvox-test--with-capitalization-cue 'capital
      (let ((before (copy-tree emacsvox-aural-user-rules))
            (option-before (copy-tree emacsvox-capitalization-capital-tone)))
        (setf (plist-get (plist-get cue :values) :pitch) 800)
        (cl-letf (((symbol-function 'customize-save-variable)
                   (lambda (symbol value &rest _)
                     (set-default symbol value) (error "Injected Customize write failure"))))
          (should-error (emacsvox-capitalization--cue-save)))
        (should (equal emacsvox-capitalization-capital-tone option-before))
        (should (equal emacsvox-aural-user-rules before))
        (with-temp-buffer
          (setq-local emacsvox-aural-editor-scope 'personal emacsvox-aural-editor-dirty t)
          (should-error (emacsvox-capitalization--cue-save) :type 'user-error))
        (cl-letf (((symbol-function 'emacsvox-aural-save-user-data)
                   (lambda (&rest _) (error "Injected rule write failure"))))
          (should-error (emacsvox-capitalization--cue-save)))
        (should (= (plist-get emacsvox-capitalization-capital-tone :pitch) 800))
        (should (equal emacsvox-aural-user-rules before))
        (should (equal (plist-get (emacsvox-aural-read-user-data) :user-rules) before))
        (emacsvox-capitalization--cue-save)
        (should-not emacsvox-aural-user-rules)
        (set-default 'emacsvox-capitalization-capital-tone option-before)
        (should-error (emacsvox-capitalization--cue-save) :type 'user-error)))))

(ert-deftest emacsvox-capitalization-shared-editor-graphical-return-and-save ()
  "Real keys apply full tones globally, discard private changes and save Customize."
  (emacsvox-test--with-capitalization-gui
    (execute-kbd-macro (kbd "l E w t A q"))
    (should (eq (oref transient--prefix command) 'emacsvox-capitalization-cue))
    (should-not emacsvox-aural-user-rules)
    (should (eq (plist-get (plist-get emacsvox-capitalization-capital-tone :shape) :waveform) 'triangle))
    (execute-kbd-macro (kbd "E w r q E"))
    (should (eq (emacsvox-tone-editor--get :waveform) 'triangle))
    (execute-kbd-macro (kbd "W q"))
    (should (file-exists-p custom-file))
    (should-not (file-exists-p emacsvox-aural-schemes-file))
    (execute-kbd-macro (kbd "r S"))
    (should (eq (plist-get (plist-get emacsvox-capitalization-capital-tone :shape) :waveform) 'sine))))

(provide 'emacsvox-capitalization-tests)
;;; emacsvox-capitalization-tests.el ends here
