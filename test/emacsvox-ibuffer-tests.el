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

(provide 'emacsvox-ibuffer-tests)
;;; emacsvox-ibuffer-tests.el ends here
