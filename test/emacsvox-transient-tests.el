;;; emacsvox-transient-tests.el --- Transient advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Transient advice.

;;; Code:

(require 'ert)
(require 'transient)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-transient.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--transient-advice
  '((transient-toggle-common :after
                             emacsvox--advice-transient-toggle-common-after)
    (transient-resume :around
                      emacsvox--advice-transient-resume-around)
    (transient-quit-all :after
                        emacsvox--advice-transient-quit-all-after)
    (transient-quit-one :after
                        emacsvox--advice-transient-quit-one-after)
    (transient-quit-seq :after
                        emacsvox--advice-transient-quit-seq-after)
    (transient-save :after emacsvox--advice-transient-save-after)
    (transient-set :after emacsvox--advice-transient-set-after)
    (transient-history-next :after
                            emacsvox--advice-transient-history-next-after)
    (transient-history-prev :after
                            emacsvox--advice-transient-history-prev-after)
    (transient--show :after emacsvox--advice-transient--show-after)
    (transient-suspend :around
                       emacsvox--advice-transient-suspend-around)
    (transient-backward-button
     :around emacsvox--advice-transient-backward-button-around)
    (transient-forward-button
     :around emacsvox--advice-transient-forward-button-around))
  "Current Emacs 31 Transient targets and their direct native advice.")

(ert-deftest emacsvox-transient-advice-is-directly-registered ()
  "Transient advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--transient-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-transient-feedback-is-target-aware ()
  "Only feedback for the matching Transient command is emitted."
  (let ((ems--interactive-fn-name 'transient-set)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-stop)
               (lambda (scope) (push (list 'stop scope) events))))
      (emacsvox--advice-transient-save-after)
      (emacsvox--advice-transient-set-after))
    (should
     (equal
      (nreverse events)
      '((icon save-object) (stop all))))))

(ert-deftest emacsvox-transient-show-caches-and-speaks-menu ()
  "Showing a new Transient menu caches and semantically presents its line."
  (save-window-excursion
    (with-temp-buffer
      (insert "Transient choices")
      (set-window-buffer (selected-window) (current-buffer))
      (let ((transient--window (selected-window))
            (emacsvox-transient--announced-prefix 'stale)
            (emacsvox-transient--announced-stack nil)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (content &rest arguments)
                     (push (cons content arguments) submissions))))
          (emacsvox--advice-transient--show-after))
        (should (equal emacsvox-transient-cache "Transient choices"))
        (should (eq emacsvox-aural-module 'transient))
        (should (= (length submissions) 1))
        (should
         (equal
          (plist-get (cdar submissions) :facts)
          '(:role command-menu :command-menu-action show
            :events (command-menu-opened))))
        (should (eq (plist-get (cdar submissions) :module) 'transient))
        (should (eq (plist-get (cdar submissions) :occasion) 'navigation))
        (let ((action
               (car
                (plist-get
                 (cdar submissions) :compatibility-actions))))
          (should
           (eq
            (emacsvox-aural-compatibility-action-value action)
            'open-object)))))))

(ert-deftest emacsvox-transient-show-deduplicates-menu-redisplay ()
  "Redrawing one live menu refreshes the cache without repeating feedback."
  (save-window-excursion
    (with-temp-buffer
      (insert "First menu")
      (set-window-buffer (selected-window) (current-buffer))
      (let ((transient--window (selected-window))
            (emacsvox-transient--announced-prefix 'stale)
            (emacsvox-transient--announced-stack nil)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (&rest arguments)
                     (push arguments submissions))))
          (emacsvox--advice-transient--show-after)
          (erase-buffer)
          (insert "Updated menu")
          (emacsvox--advice-transient--show-after))
        (should (equal emacsvox-transient-cache "Updated menu"))
        (should (= (length submissions) 1))))))

(ert-deftest emacsvox-transient-explicit-show-repeats-menu-presentation ()
  "An explicit request to show the menu speaks even when already announced."
  (save-window-excursion
    (with-temp-buffer
      (insert "Transient choices")
      (set-window-buffer (selected-window) (current-buffer))
      (let ((transient--window (selected-window))
            (emacsvox-transient--announced-prefix transient--prefix)
            (emacsvox-transient--announced-stack
             (emacsvox-transient--stack-commands))
            (ems--interactive-fn-name 'transient-show)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (&rest arguments)
                     (push arguments submissions))))
          (emacsvox--advice-transient--show-after))
        (should (= (length submissions) 1))))))

(ert-deftest emacsvox-transient-suspend-calls-original-once ()
  "Interactive suspension builds the browse buffer after one original call."
  (let ((buffer-name "*Transient-Emacsvox*")
        (emacsvox-transient-cache "Transient choices")
        (ems--interactive-fn-name 'transient-suspend)
        (calls 0)
        submissions)
    (when (get-buffer buffer-name)
      (kill-buffer buffer-name))
    (unwind-protect
        (save-window-excursion
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (cons content arguments) submissions))))
            (should
             (eq
              'result
              (emacsvox--advice-transient-suspend-around
               (lambda ()
                 (setq calls (1+ calls))
                 'result)))))
          (should (= calls 1))
          (with-current-buffer buffer-name
            (should (eq major-mode 'emacsvox-transient-mode))
            (should
             (equal
              (buffer-string)
              "r to resume, q to close this browser.\n\nTransient choices")))
          (should (= (length submissions) 1))
          (should
           (equal
            (plist-get (cdar submissions) :facts)
            '(:role command-menu :command-menu-action suspend
              :events (command-menu-suspended)))))
      (when (get-buffer buffer-name)
        (kill-buffer buffer-name)))))

(ert-deftest emacsvox-transient-programmatic-suspend-runs-once ()
  "Programmatic suspension is quiet and invokes the original once."
  (let ((calls 0)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (should
       (eq
        'result
        (emacsvox--advice-transient-suspend-around
         (lambda ()
           (setq calls (1+ calls))
           'result)))))
    (should (= calls 1))
    (should-not submissions)))

(ert-deftest emacsvox-transient-resume-reports-only-a-real-resumption ()
  "Resume feedback distinguishes a suspended menu from the no-stack case."
  (let ((ems--interactive-fn-name 'transient-resume)
        (transient--stack '((sample-prefix nil nil)))
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions)))
              ((symbol-function 'tts-stop) #'ignore))
      (should
       (eq
        'result
        (emacsvox--advice-transient-resume-around
         (lambda () 'result)))))
    (should (= (length submissions) 1))
    (should
     (equal
      (plist-get (car submissions) :facts)
      '(:role command-menu :command-menu-action resume
        :events (command-menu-resumed)))))
  (let ((ems--interactive-fn-name 'transient-resume)
        (transient--stack nil)
        (transient-resume-mode nil)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (emacsvox--advice-transient-resume-around
       (lambda () 'result)))
    (should-not submissions)))

(ert-deftest emacsvox-transient-quit-all-presents-menu-closure ()
  "Quitting the active menu presents closure without claiming task success."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'transient-quit-all)
          (transient--prefix nil)
          submissions
          stops)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (cons content arguments) submissions)))
                ((symbol-function 'tts-stop)
                 (lambda (scope) (push scope stops))))
        (emacsvox--advice-transient-quit-all-after))
      (should (equal stops '(all)))
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role command-menu :command-menu-action transient-quit-all
          :events (command-menu-closed)))))))

(ert-deftest emacsvox-transient-quit-sequence-does-not-close-menu ()
  "Aborting an incomplete key sequence must not report the menu as closed."
  (let ((ems--interactive-fn-name 'transient-quit-seq)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (emacsvox--advice-transient-quit-seq-after))
    (should (= (length submissions) 1))
    (should
     (equal
      (plist-get (car submissions) :facts)
      '(:role command-menu
        :command-menu-action abort-key-sequence)))))

(ert-deftest emacsvox-transient-exit-hook-only-resets-display-state ()
  "Generic suffix exit must not claim success or duplicate package feedback."
  (let ((emacsvox-transient--announced-prefix 'prefix)
        (emacsvox-transient--announced-stack '(parent))
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (&rest arguments)
                 (push arguments submissions)))
              ((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (emacsvox-transient-post-hook))
    (should-not emacsvox-transient--announced-prefix)
    (should-not emacsvox-transient--announced-stack)
    (should-not submissions)))

(ert-deftest emacsvox-transient-button-navigation-runs-once ()
  "Transient button movement presents one item after one original call."
  (save-window-excursion
    (with-temp-buffer
      (insert-text-button "Choice" 'action #'ignore)
      (goto-char (point-min))
      (set-window-buffer (selected-window) (current-buffer))
      (set-window-point (selected-window) (point))
      (let ((transient--window (selected-window))
            (ems--interactive-fn-name 'transient-forward-button)
            (calls 0)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (content &rest arguments)
                     (push (cons content arguments) submissions))))
          (should
           (eq
            'result
            (emacsvox--advice-transient-forward-button-around
             (lambda (n)
               (setq calls (1+ calls))
               'result)
             2))))
        (should (= calls 1))
        (should (= (length submissions) 1))
        (should
         (equal
          (caar submissions)
          "Choice"))
        (should
         (equal
          (plist-get (cdar submissions) :facts)
          '(:role command-menu-item
            :command-menu-item-kind command
            :command-menu-action focus-button
            :events (focus-entered)
            :states (selected))))))))

(ert-deftest emacsvox-transient-section-navigation-is-native ()
  "Section navigation presents the reached heading and its semantic identity."
  (save-window-excursion
    (with-temp-buffer
      (insert
       "Menu\n"
       (propertize "Options" 'face 'transient-heading)
       "\nChoice")
      (goto-char (point-min))
      (set-window-buffer (selected-window) (current-buffer))
      (let ((transient--window (selected-window))
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (content &rest arguments)
                     (push (cons content arguments) submissions))))
          (emacsvox-transient-next-section))
        (should (= (length submissions) 1))
        (should (equal (caar submissions) "Options"))
        (should
         (equal
          (plist-get (cdar submissions) :facts)
          '(:role command-menu-item
            :command-menu-item-kind section
            :command-menu-action next-section
            :events (focus-entered)
            :states (selected))))))))

(ert-deftest emacsvox-transient-section-boundary-is-presented ()
  "Section navigation provides semantic failure feedback at a boundary."
  (save-window-excursion
    (with-temp-buffer
      (insert "No headings")
      (goto-char (point-max))
      (set-window-buffer (selected-window) (current-buffer))
      (let ((transient--window (selected-window))
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
                   (lambda (&rest arguments)
                     (push arguments submissions))))
          (emacsvox-transient-next-section))
        (should (= (length submissions) 1))
        (should
         (equal
          (plist-get (car submissions) :facts)
          '(:role command-menu-item
            :command-menu-item-kind section
            :command-menu-action next-section
            :events (operation-failed))))))))

(ert-deftest emacsvox-transient-browse-mode-has-an-isolated-keymap ()
  "The browse mode must not mutate Transient's shared sticky keymap."
  (let ((sticky-next
         (lookup-key transient-sticky-map (kbd "M-n"))))
    (with-temp-buffer
      (emacsvox-transient-mode)
      (should-not (eq (current-local-map) transient-sticky-map))
      (should
       (eq
        (lookup-key (current-local-map) (kbd "M-n"))
        'emacsvox-transient-next-section)))
    (should
     (equal
      (lookup-key transient-sticky-map (kbd "M-n"))
      sticky-next))))

(ert-deftest emacsvox-transient-browse-section-navigation-stays-in-browser ()
  "Browse-buffer section movement must not jump into a live menu window."
  (save-window-excursion
    (let ((menu-buffer (generate-new-buffer " *Transient menu test*")))
      (unwind-protect
          (with-temp-buffer
            (insert
             "Menu\n"
             (propertize "Browse section" 'face 'transient-heading))
            (goto-char (point-min))
            (emacsvox-transient-mode)
            (set-window-buffer (selected-window) (current-buffer))
            (let ((transient--window
                   (display-buffer
                    menu-buffer
                    '((display-buffer-pop-up-window))))
                  submissions)
              (cl-letf (((symbol-function 'emacsvox-aural-submit)
                         (lambda (content &rest _)
                           (push content submissions))))
                (emacsvox-transient-next-section))
              (should (equal submissions '("Browse section")))
              (should (eq (window-buffer (selected-window))
                          (current-buffer)))))
        (kill-buffer menu-buffer)))))

(ert-deftest emacsvox-transient-setup-uses-emacs-31-settings ()
  "Transient setup uses the current Emacs 31 menu setting names."
  (should transient-enable-menu-navigation)
  (should (= transient-show-menu 1)))

(ert-deftest emacsvox-transient-face-inventory-is-current ()
  "Every current Transient face should have an explicit voice."
  (let ((configured
         (sort
          (mapcar #'car emacsvox-transient--face-voice-map)
          (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
        (current
         (sort
          (seq-filter
           (lambda (face)
             (string-prefix-p "transient-" (symbol-name face)))
           (face-list))
          (lambda (a b) (string< (symbol-name a) (symbol-name b))))))
    (should (equal configured current))
    (should (= (length configured) 23))
    (should
     (= (length configured)
        (length (delete-dups (copy-sequence configured)))))))

(ert-deftest emacsvox-transient-face-voices-are-explicit ()
  "Current Transient faces should resolve to their declared personalities."
  (dolist (entry emacsvox-transient--face-voice-map)
    (should
     (eq
      (voice-setup-get-voice-for-face (car entry))
      (cadr entry)))))

(provide 'emacsvox-transient-tests)
;;; emacsvox-transient-tests.el ends here
