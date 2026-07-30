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
    (transient-save-and-exit :after
                             emacsvox--advice-transient-save-and-exit-after)
    (transient-set :after emacsvox--advice-transient-set-after)
    (transient-set-and-exit :after
                            emacsvox--advice-transient-set-and-exit-after)
    (transient-reset :after emacsvox--advice-transient-reset-after)
    (transient-history-next :after
                            emacsvox--advice-transient-history-next-after)
    (transient-history-prev :after
                            emacsvox--advice-transient-history-prev-after)
    (transient-toggle-docstrings :after
                                 emacsvox--advice-transient-toggle-docstrings-after)
    (transient-toggle-level-limit :after
                                  emacsvox--advice-transient-toggle-level-limit-after)
    (transient-toggle-debug :after
                            emacsvox--advice-transient-toggle-debug-after)
    (transient-set-level :after
                         emacsvox--advice-transient-set-level-after)
    (transient-copy-menu-text :after
                              emacsvox--advice-transient-copy-menu-text-after)
    (transient-scroll-up :after
                         emacsvox--advice-transient-scroll-up-after)
    (transient-scroll-down :after
                           emacsvox--advice-transient-scroll-down-after)
    (transient-infix-set :after
                         emacsvox--advice-transient-infix-set-after)
    (transient-prefix-set :after
                          emacsvox--advice-transient-prefix-set-after)
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
        submissions
        stops)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions)))
              ((symbol-function 'tts-stop)
               (lambda (scope) (push scope stops))))
      (emacsvox--advice-transient-save-after)
      (emacsvox--advice-transient-set-after))
    (should (equal stops '(all)))
    (should (= (length submissions) 1))
    (should
     (equal
      (plist-get (car submissions) :facts)
      '(:role command-menu :command-menu-action transient-set
        :events (command-menu-value-changed))))))

(ert-deftest emacsvox-transient-value-commands-have-distinct-semantics ()
  "Set, save, and reset values expose their exact operation and cue."
  (dolist
      (entry
       '((transient-set
          emacsvox--advice-transient-set-after save-object)
         (transient-set-and-exit
          emacsvox--advice-transient-set-and-exit-after save-object)
         (transient-save
          emacsvox--advice-transient-save-after save-object)
         (transient-save-and-exit
          emacsvox--advice-transient-save-and-exit-after save-object)
         (transient-reset
          emacsvox--advice-transient-reset-after delete-object)))
    (pcase-let ((`(,target ,function ,icon) entry))
      (let ((ems--interactive-fn-name target)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
                   (lambda (&rest arguments)
                     (push arguments submissions)))
                  ((symbol-function 'tts-stop) #'ignore))
          (funcall function))
        (should (= (length submissions) 1))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value
           (car
            (plist-get
             (car submissions) :compatibility-actions)))
          icon))))))

(ert-deftest emacsvox-transient-history-uses-prefix-value-not-minibuffer ()
  "History movement presents the active prefix value outside a minibuffer."
  (let ((ems--interactive-fn-name 'transient-history-next)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-transient--value-text)
               (lambda () "--verbose, main"))
              ((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (push (cons content arguments) submissions)))
              ((symbol-function 'minibuffer-contents)
               (lambda () (ert-fail "History consulted the minibuffer"))))
      (emacsvox--advice-transient-history-next-after))
    (should (= (length submissions) 1))
    (should (equal (caar submissions) "--verbose, main"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role command-menu-item
        :command-menu-item-kind history
        :command-menu-action transient-history-next
        :events (command-menu-value-changed)
        :states (selected))))))

(ert-deftest emacsvox-transient-package-infix-change-is-presented ()
  "The shared infix adapter presents a matching package-defined infix once."
  (let ((object
         (make-instance
          'transient-switch
          :command 'sample-toggle
          :description "Verbose"
          :argument "--verbose"))
        (ems--interactive-fn-name 'sample-toggle)
        submissions)
    (oset object value "--verbose")
    (cl-letf (((symbol-function 'transient-get-summary)
               (lambda (_) "Verbose"))
              ((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (push (cons content arguments) submissions))))
      (emacsvox--advice-transient-infix-set-after
       object "--verbose"))
    (should (= (length submissions) 1))
    (should (equal (caar submissions) "Verbose, --verbose"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role command-menu-item
        :command-menu-item-kind value
        :command-menu-action sample-toggle
        :events (command-menu-value-changed)
        :states (selected))))))

(ert-deftest emacsvox-transient-infix-adapter-ignores-setup-and-cleanup ()
  "Infix initialization and incompatible-option cleanup remain silent."
  (let ((object
         (make-instance
          'transient-switch
          :command 'other-toggle
          :description "Other"
          :argument "--other"))
        (ems--interactive-fn-name 'sample-toggle)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (emacsvox--advice-transient-infix-set-after object nil))
    (should-not submissions)
    (should (eq ems--interactive-fn-name 'sample-toggle))))

(ert-deftest emacsvox-transient-prefix-preset-is-presented ()
  "Package-defined prefix presets expose their resulting value."
  (let ((ems--interactive-fn-name 'sample-preset)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (push (cons content arguments) submissions))))
      (emacsvox--advice-transient-prefix-set-after
       '("--verbose" "main")))
    (should (equal (caar submissions) "--verbose, main"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role command-menu-item
        :command-menu-item-kind value
        :command-menu-action sample-preset
        :events (command-menu-value-changed)
        :states (selected))))))

(ert-deftest emacsvox-transient-toggle-feedback-reports-resulting-state ()
  "Transient presentation toggles expose their resulting on/off state."
  (dolist
      (entry
       '((transient-toggle-common
          emacsvox--advice-transient-toggle-common-after
          transient-show-common-commands)
         (transient-toggle-docstrings
          emacsvox--advice-transient-toggle-docstrings-after
          transient--docsp)
         (transient-toggle-level-limit
          emacsvox--advice-transient-toggle-level-limit-after
          transient--all-levels-p)
         (transient-toggle-debug
          emacsvox--advice-transient-toggle-debug-after
          transient--debug)))
    (pcase-let ((`(,target ,function ,variable) entry))
      (dolist (enabled '(nil t))
        (let ((ems--interactive-fn-name target)
              submissions)
          (cl-progv (list variable) (list enabled)
            (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
                       (lambda (&rest arguments)
                         (push arguments submissions)))
                      ((symbol-function 'tts-stop) #'ignore))
              (funcall function)))
          (should (= (length submissions) 1))
          (should
           (eq
            (emacsvox-aural-compatibility-action-value
             (car
              (plist-get
               (car submissions) :compatibility-actions)))
            (if enabled 'on 'off))))))))

(ert-deftest emacsvox-transient-level-editing-distinguishes-entry-and-save ()
  "Level editing reports entering the editor separately from saving a level."
  (let ((ems--interactive-fn-name 'transient-set-level)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (emacsvox--advice-transient-set-level-after nil nil))
    (should
     (equal
      (plist-get (car submissions) :facts)
      '(:role command-menu :command-menu-action edit-levels))))
  (let ((ems--interactive-fn-name 'transient-set-level)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest arguments)
                 (push arguments submissions))))
      (emacsvox--advice-transient-set-level-after 'sample-command 5))
    (should
     (equal
      (plist-get (car submissions) :facts)
      '(:role command-menu :command-menu-action set-level
        :events (command-menu-value-changed))))))

(ert-deftest emacsvox-transient-copy-menu-text-is-presented ()
  "Copying menu text reports completion through one native transaction."
  (let ((ems--interactive-fn-name 'transient-copy-menu-text)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (push (cons content arguments) submissions))))
      (emacsvox--advice-transient-copy-menu-text-after))
    (should (equal (caar submissions) "Transient menu copied"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role command-menu :command-menu-action copy-menu-text
        :events (operation-completed))))))

(ert-deftest emacsvox-transient-scroll-presents-visible-line ()
  "Menu scrolling presents its destination through the shared menu helper."
  (let ((ems--interactive-fn-name 'transient-scroll-up)
        calls)
    (cl-letf (((symbol-function 'emacsvox-transient--present-visible-menu)
               (lambda (&rest arguments)
                 (push arguments calls))))
      (emacsvox--advice-transient-scroll-down-after)
      (emacsvox--advice-transient-scroll-up-after))
    (should
     (equal
      calls
      '((transient-scroll-up nil navigation scroll))))))

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
      (should (eq emacsvox-aural-module 'transient))
      (should-not (eq (current-local-map) transient-sticky-map))
      (should
       (eq
        (lookup-key (current-local-map) (kbd "M-n"))
        'emacsvox-transient-next-section)))
    (should
     (equal
      (lookup-key transient-sticky-map (kbd "M-n"))
      sticky-next))))

(ert-deftest emacsvox-transient-native-submission-honors-presentation-controls ()
  "Menu content independently honors cue, face-policy, and Voice Lock controls."
  (dolist (icons-enabled '(t nil))
    (dolist (face-presentation '(t nil))
      (dolist (voice-lock-enabled '(t nil))
        (with-temp-buffer
          (let ((emacsvox-aural-active-scheme 'default)
                (emacsvox-aural-enabled-feature-fragments nil)
                (emacsvox-aural-user-rules nil)
                (emacsvox-aural-session-rules nil)
                (emacsvox-aural-buffer-rules nil)
                (emacsvox-aural-presentation-history nil)
                (emacsvox-aural-presentation-history-limit 20)
                (emacsvox-aural--presentation-sequence 0)
                (emacsvox-aural--submission-sequence 0)
                (emacsvox-aural-plan-presented-hook nil)
                (emacsvox-use-icons icons-enabled)
                (emacsvox-aural-face-presentation-enabled
                 face-presentation)
                (voice-lock-mode voice-lock-enabled)
                events
                submission)
            (cl-letf
                (((symbol-function 'tts-speak)
                  (lambda (prepared)
                    (with-temp-buffer
                      (insert prepared)
                      (tts-audio-format (point-min) (point-max)))))
                 ((symbol-function 'emacsvox-queue-resource)
                  (lambda (_resource) (push 'cue events)))
                 ((symbol-function 'tts-voice-reset-code)
                  (lambda () "RESET"))
                 ((symbol-function 'tts--protocol-queue-code) #'ignore)
                 ((symbol-function 'tts--protocol-queue-text)
                  (lambda (text) (push (list 'text text) events)))
                 ((symbol-function 'tts--protocol-silence) #'ignore))
              (setq
               submission
               (emacsvox-transient--submit-text
                (propertize "Options" 'face 'transient-heading)
                (emacsvox-transient--menu-facts
                 'show 'command-menu-opened)
                'navigation
                'open-object)))
            (should (emacsvox-aural-submission-p submission))
            (should
             (equal
              (nreverse events)
              (if icons-enabled
                  '(cue (text "Options"))
                '((text "Options")))))
            (should (= (length emacsvox-aural-presentation-history) 1))
            (let* ((plan
                    (car
                     (emacsvox-aural-submission-plans submission)))
                   (context
                    (emacsvox-aural-concrete-plan-context plan))
                   (content
                    (emacsvox-aural-concrete-plan-content plan)))
              (should (eq (plist-get context :module) 'transient))
              (should
               (eq
                (plist-get context :icons-enabled)
                icons-enabled))
              (should
               (eq
                (plist-get context :face-presentation-enabled)
                face-presentation))
              (should
               (eq
                (plist-get context :voice-lock-enabled)
                voice-lock-enabled))
              (should
               (equal
                (mapcar
                 #'emacsvox-aural-concrete-action-cue
                 (emacsvox-aural-concrete-plan-before plan))
                (and icons-enabled '(open-object))))
              (should
               (eq
                (emacsvox-aural-concrete-content-voice-request content)
                (and voice-lock-enabled 'voice-lighten))))))))))

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
