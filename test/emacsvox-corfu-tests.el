;;; emacsvox-corfu-tests.el --- Corfu advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'corfu)
(require 'shell)
(require 'emacsvox-advice)
(load (expand-file-name "../lisp/emacsvox-corfu.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-corfu-advice-is-current-and-direct ()
  "Current Corfu targets use native advice directly."
  (dolist (entry emacsvox-corfu--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-corfu-face-map-covers-current-interface ()
  "Every mapped Corfu face exists in the installed package."
  (dolist (entry emacsvox-corfu--face-map)
    (should (facep (car entry)))))

(ert-deftest emacsvox-corfu-navigation-is-target-aware ()
  "Only the matching interactive Corfu navigation command speaks."
  (let ((ems--interactive-fn-name 'corfu-next)
        (calls 0))
    (cl-letf (((symbol-function 'emacsvox-corfu--speak-candidate)
               (lambda (&rest _) (cl-incf calls))))
      (emacsvox--advice-corfu-previous-after)
      (emacsvox--advice-corfu-next-after))
    (should (= calls 1))))

(ert-deftest emacsvox-corfu-opening-announces-first-candidate-and-count ()
  "Opening Corfu announces the first choice and total without selecting it."
  (with-temp-buffer
    (let ((corfu-mode t)
          (corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index -1)
          (corfu--total 2)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (emacsvox--advice-corfu--update-after))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "emacs/, 2 completions"))
        (should
         (eq (get-text-property 0 'personality content) voice-bolden))
        (should
         (eq
          (get-text-property
           (string-match "2 completions" content)
           'personality content)
          voice-annotate))
        (should (eq (plist-get facts :role) 'candidate))
        (should (equal (plist-get facts :events) '(focus-entered)))
        (should-not (plist-member facts :states))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(open-object)))))))

(ert-deftest emacsvox-corfu-update-formats-changed-candidate-once ()
  "Candidate change detection and speech share one formatted snapshot."
  (with-temp-buffer
    (setq-local emacsvox-corfu--prev-candidate "previous")
    (setq-local emacsvox-corfu--prev-index 0)
    (setq-local emacsvox-corfu--prev-total 2)
    (setq-local emacsvox-corfu--session-active-p t)
    (let ((corfu-mode t)
          (corfu--candidates '("first" "second"))
          (corfu--index 1)
          (corfu--total 2)
          (format-calls 0)
          spoken)
      (cl-letf
          (((symbol-function 'emacsvox-corfu--candidate-with-annotation)
            (lambda (&rest _arguments)
              (format "snapshot %d" (cl-incf format-calls))))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _arguments)
              (setq spoken content))))
        (emacsvox--advice-corfu--update-after))
      (should (= format-calls 1))
      (should (equal spoken "snapshot 1"))
      (should (equal emacsvox-corfu--prev-candidate spoken)))))

(ert-deftest emacsvox-corfu-navigation-speaks-position-and-voices ()
  "Candidate navigation distinguishes selection, annotation, and position."
  (with-temp-buffer
    (let ((corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index 0)
          (corfu--total 2)
          (corfu--metadata nil)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (emacsvox-corfu--speak-candidate nil t))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions))
                   (position (string-match "1 of 2" content)))
        (should (equal content "emacs/, 1 of 2"))
        (should
         (eq (get-text-property 0 'personality content) voice-bolden))
        (should
         (eq (get-text-property position 'personality content)
             voice-annotate))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 0))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(large-movement)))))))

(ert-deftest emacsvox-corfu-complete-announces-common-expansion ()
  "TAB on the prompt distinguishes common expansion from acceptance."
  (with-temp-buffer
    (insert "~/src/em")
    (let ((completion-in-region--data
           (list (point-min) (point-max) nil nil))
          (completion-in-region-mode t)
          (corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index -1)
          (corfu--total 2)
          (corfu--metadata nil)
          (ems--interactive-fn-name 'corfu-complete)
          (calls 0)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (should
         (eq
          'expanded
          (emacsvox--advice-corfu-complete-around
           (lambda ()
             (cl-incf calls)
             (delete-region (point-min) (point-max))
             (insert "~/src/emacs")
             'expanded)))))
      (should (= calls 1))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content
                       "~/src/emacs, 2 completions"))
        (should
         (equal
          (plist-get facts :events)
          '(completion-input-updated)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(item)))))))

(ert-deftest emacsvox-corfu-insert-submits-accepted-candidate ()
  "RET acceptance uses candidate semantics and a completion cue."
  (with-temp-buffer
    (let ((corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index 1)
          (corfu--total 2)
          (corfu--metadata nil)
          (ems--interactive-fn-name 'corfu-insert)
          (calls 0)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (should
         (eq
          'inserted
          (emacsvox--advice-corfu-insert-around
           (lambda ()
             (cl-incf calls)
             'inserted)))))
      (should (= calls 1))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "emacsvox/, 2 of 2"))
        (should (equal (plist-get facts :events) '(accepted)))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 1))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(complete)))))))

(ert-deftest emacsvox-corfu-complete-selected-candidate-can-continue ()
  "TAB insertion is not called accepted while completion remains active."
  (with-temp-buffer
    (insert "em")
    (let ((completion-in-region--data
           (list (point-min) (point-max) nil nil))
          (completion-in-region-mode t)
          (corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index 1)
          (corfu--total 2)
          (corfu--metadata nil)
          (ems--interactive-fn-name 'corfu-complete)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (emacsvox--advice-corfu-complete-around
         (lambda ()
           (delete-region (point-min) (point-max))
           (insert "emacsvox/")
           (setq corfu--index -1)
           'continued)))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts)))
        (should (equal content "emacsvox/, 2 of 2"))
        (should
         (equal
          (plist-get facts :events)
          '(completion-input-updated)))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 1))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           (plist-get arguments :compatibility-actions))
          '(item)))))))

(ert-deftest emacsvox-corfu-complete-selected-candidate-can-finish ()
  "TAB reports acceptance only when it actually closes completion."
  (with-temp-buffer
    (insert "em")
    (let ((completion-in-region--data
           (list (point-min) (point-max) nil nil))
          (completion-in-region-mode t)
          (corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index 1)
          (corfu--total 2)
          (corfu--metadata nil)
          (ems--interactive-fn-name 'corfu-complete)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (emacsvox--advice-corfu-complete-around
         (lambda ()
           (setq corfu--index -1)
           (setq completion-in-region-mode nil)
           'finished)))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts)))
        (should (equal content "emacsvox/, 2 of 2"))
        (should (equal (plist-get facts :events) '(accepted)))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 1))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           (plist-get arguments :compatibility-actions))
          '(complete)))))))

(ert-deftest emacsvox-corfu-expand-is-target-aware ()
  "Direct `corfu-expand' owns feedback from its nested completion path."
  (with-temp-buffer
    (insert "em")
    (let ((completion-in-region--data
           (list (point-min) (point-max) nil nil))
          (completion-in-region-mode t)
          (corfu--candidates '("emacs/" "emacsvox/"))
          (corfu--index -1)
          (corfu--total 2)
          (corfu--metadata nil)
          (ems--interactive-fn-name 'corfu-expand)
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox--advice-corfu-complete-around #'ignore)
        (should (eq ems--interactive-fn-name 'corfu-expand))
        (emacsvox--advice-corfu-expand-around
         (lambda ()
           (delete-region (point-min) (point-max))
           (insert "emacs/"))))
      (should (= (length submissions) 1))
      (should-not ems--interactive-fn-name))))

(ert-deftest emacsvox-corfu-empty-insert-closes-natively ()
  "RET without a selected candidate submits one native close action."
  (with-temp-buffer
    (let ((corfu--candidates '("emacs/"))
          (corfu--index -1)
          (corfu--total 1)
          (corfu--metadata nil)
          (ems--interactive-fn-name 'corfu-insert)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Empty insertion submitted spoken content")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments) (setq captured arguments))))
        (emacsvox--advice-corfu-insert-around #'ignore))
      (should
       (equal
        (plist-get (plist-get captured :facts) :events)
        '(completion-session-closed)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get captured :compatibility-actions))
        '(close-object))))))

(ert-deftest emacsvox-corfu-quit-closes-natively-and-resets-state ()
  "Direct quit uses one native action and clears session bookkeeping."
  (with-temp-buffer
    (setq-local
     emacsvox-corfu--prev-candidate "candidate"
     emacsvox-corfu--prev-index 2
     emacsvox-corfu--prev-total 3
     emacsvox-corfu--session-active-p t)
    (let ((ems--interactive-fn-name 'corfu-quit)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments) (setq captured arguments))))
        (emacsvox--advice-corfu-quit-after))
      (should
       (equal
        (plist-get (plist-get captured :facts) :events)
        '(completion-session-closed)))
      (should-not emacsvox-corfu--prev-candidate)
      (should (= emacsvox-corfu--prev-index -1))
      (should (= emacsvox-corfu--prev-total 0))
      (should-not emacsvox-corfu--session-active-p))))

(ert-deftest emacsvox-corfu-nested-quit-is-quiet ()
  "A quit nested under another Corfu command only resets state."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'corfu-insert)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _) (push 'submission events))))
        (emacsvox--advice-corfu-quit-after))
      (should-not events)
      (should (eq ems--interactive-fn-name 'corfu-insert)))))

(ert-deftest emacsvox-corfu-reset-distinguishes-prompt-from-close ()
  "Reset speaks the prompt while active and cues closure only when finished."
  (dolist (active-p '(t nil))
    (with-temp-buffer
      (let ((completion-in-region-mode t)
            (corfu--index 1)
            (corfu--preselect -1)
            (ems--interactive-fn-name 'corfu-reset)
            events)
        (cl-letf
            (((symbol-function 'emacsvox-corfu--speak-candidate)
              (lambda (&rest arguments)
                (push (cons 'candidate arguments) events)))
             ((symbol-function 'emacsvox-aural-submit-actions)
              (lambda (&rest arguments)
                (push (cons 'actions arguments) events))))
          (emacsvox--advice-corfu-reset-around
           (lambda ()
             (setq completion-in-region-mode active-p)
             'reset)))
        (if active-p
            (should
             (equal events '((candidate large-movement t))))
          (pcase-let ((`((actions . ,arguments)) events))
            (should
             (equal
              (plist-get (plist-get arguments :facts) :events)
              '(completion-session-closed)))
            (should
             (equal
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions))
              '(close-object)))))))))

(ert-deftest emacsvox-corfu-reset-defers-stale-input-feedback ()
  "Input restoration waits for Corfu to recompute candidate state."
  (with-temp-buffer
    (setq-local
     emacsvox-corfu--prev-candidate "stale"
     emacsvox-corfu--prev-index 0
     emacsvox-corfu--prev-total 2)
    (let ((completion-in-region-mode t)
          (corfu--index -1)
          (corfu--preselect -1)
          (ems--interactive-fn-name 'corfu-reset)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-corfu--speak-candidate)
            (lambda (&rest _) (push 'candidate events)))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _) (push 'actions events))))
        (emacsvox--advice-corfu-reset-around #'ignore))
      (should-not events)
      (should-not emacsvox-corfu--prev-candidate)
      (should (= emacsvox-corfu--prev-index -1))
      (should (= emacsvox-corfu--prev-total 0)))))

(ert-deftest emacsvox-corfu-shell-directory-completion-preserves-input ()
  "Corfu completes a sole Shell directory without selecting a candidate."
  (let ((root (file-name-as-directory
               (make-temp-file "emacsvox-corfu-shell-" t))))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "src" root))
          (with-temp-buffer
            (setq default-directory root)
            (shell-mode)
            (insert "cd sr")
            (let ((corfu-preselect 'prompt)
                  (corfu-preview-current nil))
              (corfu-mode 1)
              (cl-letf
                  (((symbol-function 'corfu--popup-show)
                    (lambda (&rest _)))
                   ((symbol-function 'corfu--popup-hide)
                    (lambda (&rest _)))
                   ((symbol-function 'emacsvox-aural-submit)
                    (lambda (&rest _))))
                (completion-at-point)
                (should (equal (buffer-string) "cd src/"))
                (should completion-in-region-mode)
                (should (= corfu--index -1))
                (should (equal default-directory root))
                (corfu-insert)
                (should-not completion-in-region-mode)
                (should (equal (buffer-string) "cd src/"))))))
      (delete-directory root t))))

(ert-deftest emacsvox-corfu-shell-initial-expansion-speaks-before-choices ()
  "Initial TAB and the following popup update announce the expanded path once."
  (let ((root (file-name-as-directory
               (make-temp-file "emacsvox-corfu-shell-" t))))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "src/JAWS" root) t)
          (make-directory (expand-file-name "src/project" root))
          (save-window-excursion
            (with-temp-buffer
              (setq default-directory root)
              (shell-mode)
              (set-window-buffer (selected-window) (current-buffer))
              (insert "cd sr")
              (let ((corfu-preselect 'prompt)
                    (corfu-preview-current nil)
                    (corfu-on-exact-match nil)
                    (this-command 'completion-at-point)
                    speech)
                (corfu-mode 1)
                (cl-letf
                    (((symbol-function 'corfu--candidates-popup) #'ignore)
                     ((symbol-function 'corfu--popup-hide) #'ignore)
                     ((symbol-function 'emacsvox-icon) #'ignore)
                     ((symbol-function 'tts-speak)
                      (lambda (text) (push text speech)))
                     ((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest _) (push text speech))))
                  (unwind-protect
                      (progn
                        (call-interactively #'completion-at-point)
                        (should (equal (buffer-string) "cd src/"))
                        (should completion-in-region-mode)
                        ;; Corfu computes the directory's children only after
                        ;; the initial completion command has returned.
                        (corfu--post-command)
                        (should (= corfu--total 2))
                        (should (= corfu--index -1))
                        (should
                         (equal speech '("src/, 2 completions")))
                        (corfu--post-command)
                        (should (= (length speech) 1))
                        (call-interactively #'corfu-next)
                        (should (equal (car speech) "JAWS/, 1 of 2")))
                    (corfu-quit)))))))
      (delete-directory root t))))

(ert-deftest emacsvox-corfu-initial-completion-handles-unchanged-and-finished ()
  "Initial completion announces unchanged choices or a finished word once."
  (dolist (initial '("f" "fo"))
    (with-temp-buffer
      (insert initial)
      (let ((completion-at-point-functions
             (list (lambda ()
                     (list (point-min) (point-max) '("foo" "far")))))
            (corfu-preselect 'prompt)
            (corfu-preview-current nil)
            (corfu-on-exact-match nil)
            speech)
        (corfu-mode 1)
        (cl-letf
            (((symbol-function 'corfu--popup-hide) #'ignore)
             ((symbol-function 'emacsvox-icon) #'ignore)
             ((symbol-function 'tts-speak)
              (lambda (text) (push text speech)))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (text &rest _) (push text speech))))
          (unwind-protect
              (progn
                (call-interactively #'completion-at-point)
                (if (equal initial "f")
                    (progn
                      (should completion-in-region-mode)
                      (corfu--update)
                      (should (equal speech '("far, 2 completions"))))
                  (should-not completion-in-region-mode)
                  (should (equal (buffer-string) "foo"))
                  (should (equal speech '("foo")))))
            (corfu-quit)))))))

(ert-deftest emacsvox-corfu-separator-policy-uses-named-tone ()
  "Separator insertion resolves its short confirmation tone by intent."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:events (completion-separator-inserted))
             '(:module corfu :mode text-mode :occasion edit)))
           (action (car (emacsvox-aural-render-plan-before plan))))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(corfu-separator-inserted-tone)))
      (should (eq (emacsvox-aural-action-kind action) 'tone))
      (should
       (eq
        (emacsvox-aural-action-tone action)
        'completion-separator)))))

(ert-deftest emacsvox-corfu-separator-preserves-cue-then-tone-order ()
  "Interactive separator insertion submits cue and tone together."
  (let ((ems--interactive-fn-name 'corfu-insert-separator)
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (setq captured arguments))))
      (emacsvox--advice-corfu-insert-separator-after))
    (should
     (equal
      (plist-get captured :facts)
      '(:events (completion-separator-inserted))))
    (should (eq (plist-get captured :module) 'corfu))
    (should (eq (plist-get captured :occasion) 'edit))
    (should
     (equal
      (mapcar
       #'emacsvox-aural-compatibility-action-value
      (plist-get captured :compatibility-actions))
      '(select-object)))))

(ert-deftest emacsvox-corfu-separator-presents-one-native-transaction ()
  "Separator cue and first-class tone share one ordered presentation."
  (dolist (icons-enabled '(t nil))
    (let ((ems--interactive-fn-name 'corfu-insert-separator)
          (emacsvox-aural-active-scheme 'default)
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
          events
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural--ensure-speaker)
            (lambda () (push 'ensure events)))
           ((symbol-function 'emacsvox-queue-resource)
            (lambda (_) (push 'cue events)))
           ((symbol-function 'emacsvox-aural--protocol-presentation-tone)
            (lambda (pitch duration mode)
              (push (list 'tone pitch duration mode) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text)
              (ert-fail
               (format "Separator queued spoken content: %S" text))))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (setq
         submission
         (emacsvox--advice-corfu-insert-separator-after)))
      (should (emacsvox-aural-submission-p submission))
      (should
       (equal
        (nreverse events)
        (append
         '(ensure)
         (when icons-enabled '(cue))
         '((tone 500 50 overlay) dispatch))))
      (should (= (length emacsvox-aural-presentation-history) 1))
      (let ((plan (car (emacsvox-aural-submission-plans submission))))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-kind
           (emacsvox-aural-concrete-plan-before plan))
          (append (when icons-enabled '(cue)) '(tone))))))))

(ert-deftest emacsvox-corfu-separator-is-quiet-programmatically ()
  "Programmatic separator insertion produces no feedback."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest _) (push 'submit-actions events))))
      (emacsvox--advice-corfu-insert-separator-after))
    (should-not events)))

(provide 'emacsvox-corfu-tests)
;;; emacsvox-corfu-tests.el ends here
