;;; emacsvox-ibuffer-tests.el --- Ibuffer advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Ibuffer advice.

;;; Code:

(require 'ert)
(require 'ibuffer)
(require 'ibuf-ext)
(require 'replace)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ibuffer.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ibuffer-removed-targets
  '(ibuffer-limit-disable
    ibuffer-occur-display-occurence
    ibuffer-occur-goto-occurence
    ibuffer-quit)
  "Ibuffer commands absent from Emacs 31.")

(ert-deftest emacsvox-ibuffer-obsolete-targets-remain-absent ()
  "The integration must not recreate commands removed before Emacs 31."
  (dolist (target emacsvox-test--ibuffer-removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-ibuffer-emacs31-replacement-targets-exist ()
  "Current filtering, Occur, and quit commands are available."
  (dolist (target
           '(ibuffer-filter-disable
             occur-mode-display-occurrence
             occur-mode-goto-occurrence
             quit-window))
    (should (fboundp target)))
  (with-temp-buffer
    (ibuffer-mode)
    (should (eq (key-binding (kbd "q")) 'quit-window))))

(defconst emacsvox-test--ibuffer-entry-navigation-after-targets
  '(ibuffer ibuffer-other-window ibuffer-list-buffers ibuffer-customize
    ibuffer-update
    ibuffer-backward-line ibuffer-forward-line
    ibuffer-backward-filter-group ibuffer-forward-filter-group
    ibuffer-backwards-next-marked ibuffer-forward-next-marked
    ibuffer-visit-buffer ibuffer-visit-buffer-1-window
    ibuffer-visit-buffer-other-window
    ibuffer-visit-buffer-other-window-noselect
    ibuffer-visit-buffer-other-frame
    ibuffer-diff-with-file
    ibuffer-do-view ibuffer-do-view-horizontally
    ibuffer-do-view-other-frame ibuffer-do-save)
  "Ibuffer entry and navigation commands with direct after advice.")

(ert-deftest emacsvox-ibuffer-entry-navigation-advice-is-directly-registered ()
  "Ibuffer entry and navigation advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--ibuffer-entry-navigation-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (dolist
      (entry
       '((ibuffer-bury-buffer
          emacsvox--advice-ibuffer-bury-buffer-around)
         (quit-window
          emacsvox--advice-ibuffer-quit-window-around)))
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :around function) ems--modern-advice-wrappers))))
  (when (fboundp 'emacsvox--advice-quit-window-after)
    (should
     (advice-member-p
      #'emacsvox--advice-quit-window-after 'quit-window))))

(ert-deftest emacsvox-ibuffer-navigation-feedback-is-target-aware ()
  "Only matching interactive Ibuffer navigation speaks and cues."
  (let ((ems--interactive-fn-name 'ibuffer-forward-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-ibuffer-summarize-line)
               (lambda () (push 'summarize events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-ibuffer-backward-line-after)
      (emacsvox--advice-ibuffer-forward-line-after))
    (should
     (equal
      (nreverse events)
      '(summarize (icon select-object))))))

(ert-deftest emacsvox-ibuffer-bury-calls-original-once ()
  "Burying an Ibuffer entry preserves one original call and its result."
  (let ((ems--interactive-fn-name 'ibuffer-bury-buffer)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'ibuffer-current-buffer)
               (lambda (&rest _) 'target-buffer))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (should
       (eq
        (emacsvox--advice-ibuffer-bury-buffer-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'buried)
         2)
        'buried)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original (2))
        (icon select-object)
        (message "Buried buffer target-buffer"))))))

(ert-deftest emacsvox-ibuffer-bury-programmatic-call-still-runs ()
  "Programmatic Ibuffer burying runs once without spoken feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'ibuffer-current-buffer)
               (lambda (&rest _) 'target-buffer))
              ((symbol-function 'emacsvox-icon)
               (lambda (&rest arguments) (push arguments events)))
              ((symbol-function 'message)
               (lambda (&rest arguments) (push arguments events))))
      (should
       (eq
        (emacsvox--advice-ibuffer-bury-buffer-around
         (lambda (&rest _)
           (cl-incf calls)
           'buried))
        'buried)))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-ibuffer-quit-feedback-is-mode-scoped ()
  "Interactive `quit-window' feedback is limited to Ibuffer origins."
  (let ((ems--interactive-fn-name 'quit-window)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (with-temp-buffer
        (ibuffer-mode)
        (should
         (eq
          (emacsvox--advice-ibuffer-quit-window-around
           (lambda (&rest _)
             (cl-incf calls)
             'quit))
          'quit)))
      (with-temp-buffer
        (should
         (eq
          (emacsvox--advice-ibuffer-quit-window-around
           (lambda (&rest _)
             (cl-incf calls)
             'quit))
          'quit))))
    (should (= calls 2))
    (should
     (equal
      (nreverse events)
      '((icon close-object) speak-mode-line)))))

(defconst emacsvox-test--ibuffer-mark-operation-after-targets
  '(ibuffer-mark-forward
    ibuffer-mark-for-delete ibuffer-mark-for-delete-backwards
    ibuffer-unmark-forward ibuffer-unmark-backward ibuffer-unmark-all
    ibuffer-toggle-marks
    ibuffer-do-shell-command-pipe-replace
    ibuffer-do-shell-command-pipe ibuffer-do-shell-command-file
    ibuffer-do-rename-uniquely ibuffer-do-replace-regexp
    ibuffer-do-kill-lines ibuffer-copy-filename-as-kill
    ibuffer-mark-by-name-regexp ibuffer-mark-by-mode-regexp
    ibuffer-mark-by-file-name-regexp ibuffer-mark-by-mode
    ibuffer-mark-modified-buffers ibuffer-mark-unsaved-buffers
    ibuffer-mark-dissociated-buffers ibuffer-mark-help-buffers
    ibuffer-mark-compressed-file-buffers ibuffer-mark-old-buffers
    ibuffer-mark-special-buffers ibuffer-mark-read-only-buffers
    ibuffer-mark-dired-buffers)
  "Ibuffer marking and buffer operations with direct after advice.")

(ert-deftest emacsvox-ibuffer-mark-operation-advice-is-directly-registered ()
  "Ibuffer marking and operation advice bypasses the bridge."
  (dolist (target emacsvox-test--ibuffer-mark-operation-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ibuffer-mark-feedback-is-target-aware ()
  "Only the matching interactive mark command cues and speaks."
  (let ((ems--interactive-fn-name 'ibuffer-unmark-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-ibuffer-speak-buffer-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-ibuffer-mark-forward-after)
      (emacsvox--advice-ibuffer-unmark-forward-after))
    (should
     (equal
      (nreverse events)
      '((icon deselect-object) speak-line)))))

(ert-deftest emacsvox-ibuffer-operation-feedback-is-target-aware ()
  "Only the matching interactive buffer operation emits its cue."
  (let ((ems--interactive-fn-name 'ibuffer-do-rename-uniquely)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-ibuffer-do-replace-regexp-after)
      (emacsvox--advice-ibuffer-do-rename-uniquely-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-ibuffer-copy-filename-feedback-is-not-duplicated ()
  "Copying filenames emits the effective legacy feedback exactly once."
  (let ((ems--interactive-fn-name 'ibuffer-copy-filename-as-kill)
        (registrations 0)
        events)
    (advice-mapc
     (lambda (function _properties)
       (when
           (eq
            function
            #'emacsvox--advice-ibuffer-copy-filename-as-kill-after)
         (cl-incf registrations)))
     'ibuffer-copy-filename-as-kill)
    (cl-letf (((symbol-function 'ibuffer-count-marked-lines)
               (lambda (&rest _) 3))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-ibuffer-copy-filename-as-kill-after))
    (should (= registrations 1))
    (should
     (equal
      (nreverse events)
      '((icon delete-object)
        (speak "copied 3 filenames."))))))

(defconst emacsvox-test--ibuffer-filter-sort-after-targets
  '(ibuffer-interactive-filter-by-mode
    ibuffer-recompile-formats ibuffer-switch-format
    ibuffer-toggle-filter-group
    ibuffer-filters-to-filter-group ibuffer-set-filter-groups-by-mode
    ibuffer-clear-filter-groups ibuffer-jump-to-filter-group
    ibuffer-kill-filter-group ibuffer-filter-disable
    ibuffer-filter-by-mode ibuffer-filter-by-used-mode
    ibuffer-filter-by-name ibuffer-filter-by-filename
    ibuffer-filter-by-size-gt ibuffer-filter-by-size-lt
    ibuffer-filter-by-content ibuffer-filter-by-predicate
    ibuffer-toggle-sorting-mode ibuffer-invert-sorting
    ibuffer-do-sort-by-major-mode ibuffer-do-sort-by-alphabetic
    ibuffer-do-sort-by-size ibuffer-pop-filter)
  "Ibuffer filtering and sorting commands with direct after advice.")

(ert-deftest emacsvox-ibuffer-filter-sort-advice-is-directly-registered ()
  "Ibuffer filter and sorting advice bypasses the bridge."
  (dolist (target emacsvox-test--ibuffer-filter-sort-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (dolist
      (entry
       '((ibuffer-pop-filter-group
          emacsvox--advice-ibuffer-pop-filter-group-around)
         (ibuffer-yank-filter-group
          emacsvox--advice-ibuffer-yank-filter-group-around)))
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :around function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ibuffer-filter-feedback-is-target-aware ()
  "Only the matching interactive filter command emits its cue."
  (let ((ems--interactive-fn-name 'ibuffer-filter-by-name)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-ibuffer-filter-by-mode-after)
      (emacsvox--advice-ibuffer-filter-by-name-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-ibuffer-duplicate-filter-sort-advice-is-collapsed ()
  "Duplicate legacy filter and sort definitions register only once."
  (dolist
      (entry
       '((ibuffer-filter-by-predicate
          emacsvox--advice-ibuffer-filter-by-predicate-after)
         (ibuffer-toggle-sorting-mode
          emacsvox--advice-ibuffer-toggle-sorting-mode-after)))
    (pcase-let ((`(,target ,expected) entry)
                (registrations 0))
      (advice-mapc
       (lambda (function _properties)
         (when (eq function expected)
           (cl-incf registrations)))
       target)
      (should (= registrations 1)))))

(ert-deftest emacsvox-ibuffer-pop-filter-group-calls-original-once ()
  "Interactive filter-group popping preserves one call and its result."
  (let ((ems--interactive-fn-name 'ibuffer-pop-filter-group)
        (ibuffer-filter-groups '(("Work" . ((mode . text-mode)))))
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (should
       (eq
        (emacsvox--advice-ibuffer-pop-filter-group-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'popped))
        'popped)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original nil)
        (icon task-done)
        (speak "Popped group Work"))))))

(ert-deftest emacsvox-ibuffer-yank-filter-group-preserves-order ()
  "Interactive filter-group yanking cues around one original call."
  (let ((ems--interactive-fn-name 'ibuffer-yank-filter-group)
        (ibuffer-filter-group-kill-ring
         '(("Archived" . ((name . "old")))))
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (should
       (eq
        (emacsvox--advice-ibuffer-yank-filter-group-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'yanked)
         "Before")
        'yanked)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon yank-object)
        (original ("Before"))
        (speak "Yanked Archived group."))))))

(ert-deftest emacsvox-ibuffer-filter-group-programmatic-calls-still-run ()
  "Programmatic pop and yank operations run once without feedback."
  (let ((ems--interactive-fn-name nil)
        (ibuffer-filter-groups '(("Work" . nil)))
        (ibuffer-filter-group-kill-ring '(("Archived" . nil)))
        (pop-calls 0)
        (yank-calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest arguments) (push arguments events)))
              ((symbol-function 'dtk-speak)
               (lambda (&rest arguments) (push arguments events))))
      (should
       (eq
        (emacsvox--advice-ibuffer-pop-filter-group-around
         (lambda (&rest _)
           (cl-incf pop-calls)
           'popped))
        'popped))
      (should
       (eq
        (emacsvox--advice-ibuffer-yank-filter-group-around
         (lambda (&rest _)
           (cl-incf yank-calls)
           'yanked)
         "Before")
        'yanked)))
    (should (= pop-calls 1))
    (should (= yank-calls 1))
    (should-not events)))

(ert-deftest emacsvox-ibuffer-kill-filter-group-uses-native-name ()
  "Filter-group kill feedback uses the explicit native NAME argument."
  (let ((ems--interactive-fn-name 'ibuffer-kill-filter-group)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-ibuffer-kill-filter-group-after "Work"))
    (should
     (equal
      (nreverse events)
      '((icon delete-object)
        (speak "Killed Work group."))))))

(provide 'emacsvox-ibuffer-tests)
;;; emacsvox-ibuffer-tests.el ends here
