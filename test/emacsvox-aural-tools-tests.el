;;; emacsvox-aural-tools-tests.el --- Aural tools and editor tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test disabled-rule semantics, validation, explanation, preview, training,
;; selection/copy/reset commands, and the accessible editor working model.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-sounds)
(require 'tts-speak)
(require 'voice-setup)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-simple-editor)

(defmacro emacsvox-test--with-aural-tools (&rest body)
  "Run BODY with isolated scheme, override, and training state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-module-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-enabled-feature-fragments nil)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-tools--last-source-buffer nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-feature-fragments-changed-hook nil)
         (emacsvox-aural-plan-presented-hook nil)
         (emacsvox-aural-training-mode nil)
         (emacsvox-sounds-current-pack 'chimes)
         (emacsvox-aural-spatial-enabled t)
         (emacsvox-aural-spatial-speech-enabled t)
         (emacsvox-aural-spatial-cue-enabled t)
         (emacsvox-aural-spatial-output 'auto)
         (emacsvox-aural-spatial-maximum-separation 1.0)
         (emacsvox-aural-spatial-remapping 'normal)
         (emacsvox-aural-speech-balance-function nil)
         (emacsvox-aural-queued-cue-balance-function nil))
     (emacsvox-aural--register-default-scheme)
     ,@body))

(defun emacsvox-test--register-tools-scheme (id rules)
  "Register and select a test scheme ID containing RULES."
  (emacsvox-aural-register-scheme
   (list
    :schema-version 1
    :id id
    :summary "Aural tools test scheme"
    :parent 'default
    :rules rules))
  (emacsvox-aural-select-scheme id))

(defun emacsvox-test--tools-context (&optional mode)
  "Return a minimal inspection context for MODE."
  (list
   :mode (or mode 'text-mode)
   :mode-lineage (list (or mode 'text-mode))
   :occasion 'inspection))

(ert-deftest emacsvox-aural-tools-disabled-rules-stay-valid-but-inactive ()
  "Schema-v1 disabled rules remain inspectable without entering resolution."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'disabled-test
     '((:id disabled-cue
        :enabled nil
        :match (:role heading)
        :render
        (:before
         ((:id disabled-item :kind cue :cue item))))))
    (let* ((entry (emacsvox-aural-scheme-entry 'disabled-test))
           (compiled
            (emacsvox-aural-scheme-entry-compiled entry))
           (report (emacsvox-aural-validate-scheme 'disabled-test)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-rule-id
         (emacsvox-aural-scheme-rules compiled))
        '(disabled-cue)))
      (should-not (emacsvox-aural-effective-scheme-rules 'disabled-test))
      (should-not (emacsvox-aural-scheme-required-cues compiled))
      (should
       (equal
        (emacsvox-aural-validation-report-disabled-rules report)
        '(disabled-cue)))
      (should
       (emacsvox-aural-validation-report-valid report))
      (should-not
       (emacsvox-aural-render-plan-before
        (emacsvox-aural-resolve-active
         '(:role heading)
         (emacsvox-test--tools-context)))))))

(ert-deftest emacsvox-aural-tools-disabled-ids-remain-cross-layer-unique ()
  "A disabled override cannot park a duplicate identifier ambiguously."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'id-test
     '((:id shared
        :match (:role heading)
        :render (:content (:voice bolden)))))
    (let ((emacsvox-aural-user-rules
           '((:id shared
              :enabled nil
              :match (:role heading)
              :render (:content (:voice lighten))))))
      (should-error
       (emacsvox-aural-current-rules
        (emacsvox-test--tools-context))
       :type 'emacsvox-aural-scheme-error))))

(ert-deftest emacsvox-aural-tools-enabled-field-must-be-boolean ()
  "The schema-v1 enabled extension rejects ambiguous values."
  (should-error
   (emacsvox-aural-compile-rule
    '(:id invalid-enabled
      :enabled yes
      :match (:role heading)
      :render (:content (:voice bolden)))
    'user)
   :type 'emacsvox-aural-rule-error))

(ert-deftest emacsvox-aural-tools-capture-facts-and-context-at-point ()
  "Point inspection uses semantic facts and frozen concrete context."
  (emacsvox-test--with-aural-tools
    (with-temp-buffer
      (setq major-mode 'emacs-lisp-mode)
      (let* ((facts '(:role heading :level 2 :content "Title"))
             (context (emacsvox-aural-capture-context 'org 'navigation))
             (prepared (emacsvox-aural-prepare-text "Title" facts context)))
        (insert prepared)
        (goto-char (point-min))
        (should (equal (emacsvox-aural-facts-at-point) facts))
        (should
         (eq
          (plist-get (emacsvox-aural-context-at-point) :module)
          'org))
        (should
         (eq
          (plist-get (emacsvox-aural-context-at-point) :mode)
          'emacs-lisp-mode))))))

(ert-deftest emacsvox-aural-tools-validation-reports-rule-diagnostics ()
  "Validation reports ineffective rules, stable-ID ties, and disabled rules."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'diagnostics
     '((:id no-effect
        :match (:role heading)
        :render ())
       (:id tie-a
        :order 5
        :match (:role heading)
        :render (:content (:voice bolden)))
       (:id tie-b
        :order 5
        :match (:role heading)
        :render (:content (:voice lighten)))
       (:id parked
        :enabled nil
        :match (:role heading)
        :render (:content (:voice smoothen)))))
    (let ((report (emacsvox-aural-validate-scheme 'diagnostics)))
      (should (emacsvox-aural-validation-report-valid report))
      (should
       (equal
        (emacsvox-aural-validation-report-unreachable-rules report)
        '(no-effect)))
      (should
       (equal
        (emacsvox-aural-validation-report-ambiguous-ties report)
        '((tie-a . tie-b))))
      (should
       (equal
        (emacsvox-aural-validation-report-disabled-rules report)
        '(parked))))))

(ert-deftest emacsvox-aural-tools-explain-suppression-and-degradation ()
  "Explanation reproduces matches, removed actions, and backend fallback."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'explain-test
     '((:id add-cue
        :match (:role heading)
        :render
        (:before ((:id heading-cue :kind cue :cue item))
         :content (:volume 0.5)))
       (:id remove-cue
        :match (:role heading :state folded)
        :render (:before (:remove (heading-cue))))))
    (let* ((explanation
            (emacsvox-aural-explain
             '(:role heading :state folded :content "Title")
             (emacsvox-test--tools-context)))
           (matches
            (mapcar
             (lambda (entry) (plist-get entry :id))
             (emacsvox-aural-explanation-matching-rules explanation))))
      (should (equal matches '(add-cue remove-cue)))
      (should
       (equal
        (emacsvox-aural-explanation-suppressed-actions explanation)
        '(heading-cue)))
      (should
       (emacsvox-aural-concrete-plan-degradations
        (emacsvox-aural-explanation-concrete-plan explanation))))))

(ert-deftest emacsvox-aural-tools-explain-infers-matching-occasion ()
  "Point help prefers an occasion that exercises the active scheme."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'occasion-test
     '((:id navigation-heading
        :match (:role heading :module org :occasion navigation)
        :render
        (:before
         ((:id heading-label :kind speech :text "Heading"))))))
    (let ((facts '(:role heading :level 1))
          (context
           '(:module org :mode org-mode :mode-lineage (org-mode)
             :occasion continuous)))
      (should
       (eq
        (emacsvox-aural-tools--best-explanation-occasion
         facts context)
        'navigation))
      (should
       (equal
        (emacsvox-aural-tools--occasion-match-counts facts context)
        '((continuous . 0)
          (edit . 0)
          (inspection . 0)
          (navigation . 1)
          (notification . 0)
          (state-change . 0)))))))

(ert-deftest emacsvox-aural-tools-explain-prefix-chooses-occasion ()
  "A prefix prompt can override the automatically inferred occasion."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'occasion-test
     '((:id navigation-heading
        :match (:role heading :module org :occasion navigation)
        :render (:content (:voice bolden)))))
    (with-temp-buffer
      (setq-local emacsvox-aural-module 'org)
      (setq major-mode 'org-mode)
      (insert
       (propertize
        "Heading"
        emacsvox-aural-facts-property
        '(:role heading :level 1)))
      (goto-char (point-min))
      (let (default)
        (cl-letf
            (((symbol-function 'completing-read)
              (lambda (_prompt _collection &rest arguments)
                (setq default (nth 4 arguments))
                "continuous")))
          (pcase-let
              ((`(,facts ,context)
                (emacsvox-aural-tools--read-explanation-input t)))
            (should (equal facts '(:role heading :level 1)))
            (should (eq (plist-get context :occasion) 'continuous))
            (should (equal default "navigation"))))))))

(ert-deftest emacsvox-aural-tools-explain-preserves-frozen-occasion ()
  "Help on prepared output reports its actual occasion without inference."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'occasion-test
     '((:id navigation-heading
        :match (:role heading :occasion navigation)
        :render (:content (:voice bolden)))))
    (with-temp-buffer
      (insert
       (emacsvox-aural-prepare-text
        "Heading"
        '(:role heading :level 1)
        '(:mode text-mode :mode-lineage (text-mode)
          :occasion continuous)))
      (goto-char (point-min))
      (pcase-let
          ((`(,facts ,context)
            (emacsvox-aural-tools--read-explanation-input nil)))
        (should (equal facts '(:role heading :level 1)))
        (should (eq (plist-get context :occasion) 'continuous))))))

(ert-deftest emacsvox-aural-tools-explanation-speaks-concise-order ()
  "Interactive help speaks natural output order and keeps technical detail."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'occasion-test
     '((:id navigation-heading
        :match (:role heading :module org :occasion navigation)
        :render
        (:before
         ((:id heading-label :kind speech :text "Heading"))
         :content (:voice bolden)))))
    (let* ((facts '(:role heading :level 1 :state folded))
           (context
            '(:module org :mode org-mode :mode-lineage (org-mode)
              :occasion navigation))
           (explanation (emacsvox-aural-explain facts context))
           (counts
            (emacsvox-aural-tools--occasion-match-counts facts context))
           icon spoken)
      (unwind-protect
          (progn
            (cl-letf
                (((symbol-function 'emacsvox-icon)
                  (lambda (value) (setq icon value)))
                 ((symbol-function 'tts-speak)
                  (lambda (text) (setq spoken text))))
              (save-window-excursion
                (emacsvox-aural-tools--display-explanation
                 explanation t counts)))
            (should (eq icon 'help))
            (should
             (string-match-p
              "Scheme occasion test" spoken))
            (should
             (string-match-p
              "Occasion navigation" spoken))
            (should
             (string-match-p
              "Before the content, say Heading" spoken))
            (should
             (string-match-p
              "content is spoken using the bolden voice" spoken))
            (with-current-buffer "*Help*"
              (should
               (string-match-p
                "Scheme: occasion-test" (buffer-string)))
              (should
               (string-match-p
                "Resolved presentation order" (buffer-string)))
              (should
               (string-match-p
                "Technical details" (buffer-string)))))
        (when (get-buffer "*Help*")
          (kill-buffer "*Help*"))))))

(ert-deftest emacsvox-aural-tools-explanation-names-matching-occasions ()
  "No-match spoken help identifies a useful alternative occasion."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'occasion-test
     '((:id navigation-heading
        :match (:role heading :occasion navigation)
        :render (:content (:voice bolden)))))
    (let* ((facts '(:role heading))
           (context
            '(:mode text-mode :mode-lineage (text-mode)
              :occasion continuous))
           (explanation (emacsvox-aural-explain facts context))
           (summary
            (emacsvox-aural-tools--spoken-explanation
             explanation
             (emacsvox-aural-tools--occasion-match-counts
              facts context))))
      (should
       (string-match-p
        "No rule matched" summary))
      (should
       (string-match-p
        "available for navigation, 1 rule" summary)))))

(ert-deftest emacsvox-aural-tools-preview-uses-representative-context ()
  "Rule preview constructs selector-matching facts and mode context."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'preview-test
     '((:id elisp-preview
        :match (:role heading :mode emacs-lisp-mode)
        :render
        (:before
         ((:id label :kind speech :text "Heading"))))))
    (let ((tts-speaker-process 'speaker)
          queued)
      (cl-letf
          (((symbol-function 'process-live-p) (lambda (_) t))
           ((symbol-function 'emacsvox-aural-queue-concrete-plan)
            (lambda (plan &rest _) (setq queued plan)))
           ((symbol-function 'tts--protocol-dispatch) #'ignore))
        (emacsvox-preview-aural-rule 'elisp-preview))
      (should
       (eq
        (plist-get
         (emacsvox-aural-concrete-plan-context queued)
         :mode)
        'emacs-lisp-mode))
      (should
       (equal
        (emacsvox-aural-concrete-action-text
         (car (emacsvox-aural-concrete-plan-before queued)))
        "Heading")))))

(ert-deftest emacsvox-aural-tools-copy-scheme-inherited-or-flattened ()
  "Copy supports editable inheritance and a fully flattened alternative."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-tools-copy-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-test--register-tools-scheme
             'copy-source
             '((:id source-rule
                :match (:role heading)
                :render (:content (:voice bolden)))))
            (emacsvox-copy-aural-scheme
             'copy-source 'inherited-copy)
            (emacsvox-copy-aural-scheme
             'copy-source 'flat-copy t)
            (should
             (eq
              (emacsvox-aural-scheme-parent
               (emacsvox-aural-scheme-entry-compiled
                (emacsvox-aural-scheme-entry 'inherited-copy)))
              'copy-source))
            (should-not
             (emacsvox-aural-scheme-parent
              (emacsvox-aural-scheme-entry-compiled
               (emacsvox-aural-scheme-entry 'flat-copy))))
            (should
             (equal
              (mapcar
               #'emacsvox-aural-rule-id
               (emacsvox-aural-effective-scheme-rules 'flat-copy))
              '(source-rule)))
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-tools-reset-each-override-scope ()
  "Reset clears only the requested personal, session, or buffer layer."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-tools-reset-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory))
           (rule
            '(:id one :match (:role heading)
              :render (:content (:voice bolden)))))
      (unwind-protect
          (with-temp-buffer
            (setq
             emacsvox-aural-user-rules (list rule)
             emacsvox-aural-session-rules (list rule)
             emacsvox-aural-buffer-rules (list rule))
            (emacsvox-reset-aural-overrides 'buffer)
            (should-not emacsvox-aural-buffer-rules)
            (should emacsvox-aural-session-rules)
            (emacsvox-reset-aural-overrides 'session)
            (should-not emacsvox-aural-session-rules)
            (emacsvox-reset-aural-overrides 'personal)
            (should-not emacsvox-aural-user-rules)
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-tools-training-follows-normal-plan ()
  "Training queues concise semantic identification after normal content."
  (emacsvox-test--with-aural-tools
    (let* ((facts '(:role heading :level 1 :content "Title"))
           (context (emacsvox-test--tools-context))
           (render (emacsvox-aural-resolve-active facts context))
           (plan (emacsvox-aural-compile-plan render facts context))
           events)
      (cl-letf
          (((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code)
            (lambda (code) (push (list 'code code) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push (list 'text text) events))))
        (unwind-protect
            (progn
              (emacsvox-aural-training-mode 1)
              (emacsvox-aural-queue-concrete-plan plan))
          (emacsvox-aural-training-mode -1)))
      (should
       (equal
        (car (last (nreverse events)))
        '(text "heading, level 1, inspection occasion."))))))

(ert-deftest emacsvox-aural-tools-training-identifies-standalone-legacy-cue ()
  "A local compatibility cue is followed by its frozen semantic explanation."
  (emacsvox-test--with-aural-tools
    (let ((tts-speaker-process 'speaker)
          (emacsvox-use-icons t)
          events)
      (cl-letf
          (((symbol-function 'process-live-p) (lambda (_) t))
           ((symbol-function 'emacsvox-sounds-play-concrete-cue)
            (lambda (&rest _) (push 'local-cue events)))
           ((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code)
            (lambda (code) (push (list 'code code) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push (list 'text text) events)))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (unwind-protect
            (progn
              (emacsvox-aural-training-mode 1)
              (emacsvox-icon 'emacsvox))
          (emacsvox-aural-training-mode -1)))
      (should
       (equal
        (nreverse events)
        '(local-cue
          (code "RESET")
          (text
           "product identity, legacy cue emacsvox, notification occasion.")
          dispatch))))))

(ert-deftest emacsvox-aural-tools-list-buffers-use-accessible-modes ()
  "Aural home and list commands populate predictable tabulated buffers."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-home-source*")))
      (unwind-protect
          (save-window-excursion
            (with-current-buffer source
              (emacsvox-aural))
            (with-current-buffer "*Emacsvox Aural*"
              (should (derived-mode-p 'emacsvox-aural-home-mode))
              (should (eq emacsvox-aural-home-source-buffer source))
              (should
               (equal
                (mapcar #'car tabulated-list-entries)
                '(explain schemes features buffer-rules semantics sounds
                  spatial spatial-settings training diagnostics)))
              (dolist
                  (binding
                   '(("RET" . emacsvox-aural-home-activate)
                     ("SPC" . emacsvox-aural-home-speak-current)
                     ("." . emacsvox-aural-home-speak-current-cell)
                     ("n" . emacsvox-aural-home-next)
                     ("p" . emacsvox-aural-home-previous)
                     ("<down>" . emacsvox-aural-home-next)
                     ("<up>" . emacsvox-aural-home-previous)
                     ("<right>" . emacsvox-aural-home-next-column)
                     ("<left>" . emacsvox-aural-home-previous-column)
                     ("x" . emacsvox-aural-home-explain)
                     ("g" . emacsvox-aural-home-refresh)
                     ("?" . emacsvox-aural-home-help)))
                (should
                 (eq
                  (lookup-key
                   emacsvox-aural-home-mode-map
                   (kbd (car binding)))
                  (cdr binding)))))
            (emacsvox-list-aural-semantics)
            (with-current-buffer "*Aural Semantics*"
              (should (derived-mode-p 'emacsvox-aural-semantics-mode))
              (should tabulated-list-entries))
            (emacsvox-list-aural-schemes)
            (with-current-buffer "*Aural Schemes*"
              (should (derived-mode-p 'emacsvox-aural-schemes-mode))
              (should
               (equal
                (mapcar #'car tabulated-list-entries)
                '(default)))))
        (dolist
            (buffer
             '("*Emacsvox Aural*" "*Aural Semantics*" "*Aural Schemes*"))
          (when (get-buffer buffer)
            (kill-buffer buffer)))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-home-speaks-navigation-and-source-explanation ()
  "The home buffer speaks cells and diagnoses its remembered source."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-explanation-source*"))
          spoken
          explained-in)
      (unwind-protect
          (save-window-excursion
            (emacsvox-aural source)
            (cl-letf
                (((symbol-function 'tts-speak)
                  (lambda (text) (setq spoken text)))
                 ((symbol-function 'emacsvox-icon) #'ignore)
                 ((symbol-function 'emacsvox-aural-explain-presentation)
                  (lambda ()
                    (interactive)
                    (setq explained-in (current-buffer)))))
              (with-current-buffer "*Emacsvox Aural*"
                (emacsvox-aural-home-previous)
                (should (equal spoken "Top of aural home."))
                (emacsvox-aural-home-next)
                (should (equal spoken "Area, Schemes"))
                (emacsvox-aural-home-next-column)
                (should (equal spoken "Current status, default"))
                (emacsvox-aural-home-explain))
              (should (eq explained-in source))))
        (when (get-buffer "*Emacsvox Aural*")
          (kill-buffer "*Emacsvox Aural*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-interfaces-provide-home-navigation ()
  "Every aural child manager and editor uses h for the aural home."
  (dolist
      (map
       (list
        emacsvox-aural-semantics-mode-map
        emacsvox-aural-schemes-mode-map
        emacsvox-aural-feature-fragments-mode-map
        emacsvox-aural-scheme-editor-mode-map
        emacsvox-aural-simple-editor-mode-map))
    (should
     (eq (lookup-key map (kbd "h")) #'emacsvox-aural))))

(ert-deftest emacsvox-aural-tools-expose-discoverable-command-namespace ()
  "Preferred aural command names coexist with established compatibility names."
  (dolist
      (entry
       '((emacsvox-aural-list-semantics
          . emacsvox-list-aural-semantics)
         (emacsvox-aural-describe-semantic
          . emacsvox-describe-aural-semantic)
         (emacsvox-aural-list-schemes
          . emacsvox-list-aural-schemes)
         (emacsvox-aural-describe-scheme
          . emacsvox-describe-aural-scheme)
         (emacsvox-aural-show-scheme-validation
          . emacsvox-validate-aural-scheme)
         (emacsvox-aural-explain-presentation
          . emacsvox-explain-aural-presentation)
         (emacsvox-aural-preview-scheme
          . emacsvox-preview-aural-scheme)
         (emacsvox-aural-set-scheme
          . emacsvox-set-aural-scheme)
         (emacsvox-aural-copy-scheme
          . emacsvox-copy-aural-scheme)
         (emacsvox-aural-delete-scheme
          . emacsvox-delete-aural-scheme)
         (emacsvox-aural-rename-scheme
          . emacsvox-rename-aural-scheme)
         (emacsvox-aural-edit-scheme
          . emacsvox-edit-aural-scheme)
         (emacsvox-aural-edit-scheme-advanced
          . emacsvox-edit-aural-scheme-advanced)
         (emacsvox-aural-edit-rules
          . emacsvox-edit-aural-rules)
         (emacsvox-aural-edit-feature-fragment
          . emacsvox-edit-aural-feature-fragment)))
    (should (commandp (car entry)))
    (should
     (eq
      (indirect-function (car entry))
      (indirect-function (cdr entry))))))

(ert-deftest emacsvox-aural-scheme-manager-rows-and-commands-are-complete ()
  "The manager exposes useful row state and every documented operation."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id personal
       :summary "Personal manager test"
       :parent default
       :rules
       ((:id heading
         :match (:role heading)
         :render (:content (:voice bolden)))))
     :source "test")
    (emacsvox-aural-select-scheme 'personal)
    (save-window-excursion
      (emacsvox-list-aural-schemes)
      (with-current-buffer "*Aural Schemes*"
        (let ((row (cadr (assq 'personal tabulated-list-entries))))
          (should (equal (aref row 1) "active"))
          (should (equal (aref row 2) "personal"))
          (should (equal (aref row 3) "default"))
          (should (equal (aref row 5) "1 direct, 1 total")))
        (should
         (eq
          (lookup-key emacsvox-aural-schemes-mode-map (kbd "RET"))
          #'emacsvox-describe-aural-scheme))
        (dolist
            (binding
             '(("e" . emacsvox-aural-schemes-edit)
               ("A" . emacsvox-aural-schemes-edit-advanced)
               ("c" . emacsvox-aural-schemes-copy)
               ("d" . emacsvox-delete-aural-scheme)
               ("r" . emacsvox-rename-aural-scheme)
               ("a" . emacsvox-aural-schemes-activate)
               ("n" . emacsvox-aural-schemes-next)
               ("p" . emacsvox-aural-schemes-previous)
               ("P" . emacsvox-preview-aural-scheme)
               ("<down>" . emacsvox-aural-schemes-next)
               ("<up>" . emacsvox-aural-schemes-previous)
               ("<right>" . emacsvox-aural-schemes-next-column)
               ("<left>" . emacsvox-aural-schemes-previous-column)
               ("v" . emacsvox-validate-aural-scheme)
               ("SPC" . emacsvox-aural-schemes-speak-current)
               ("." . emacsvox-aural-schemes-speak-current-cell)
               ("f" . emacsvox-aural-list-feature-fragments)
               ("h" . emacsvox-aural)
               ("?" . emacsvox-aural-schemes-help)))
          (should
           (eq
            (lookup-key
             emacsvox-aural-schemes-mode-map
             (kbd (car binding)))
            (cdr binding))))))
    (kill-buffer "*Aural Schemes*")))

(ert-deftest emacsvox-aural-fragment-manager-rows-and-commands-are-complete ()
  "The fragment manager exposes state, accessible navigation, and operations."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-feature-fragment
     '(:schema-version 1
       :id built-in-fragment
       :summary "Built-in fragment"
       :rules
       ((:id built-in-heading
         :match (:role heading)
         :render (:content (:speak t)))))
     :built-in t :source "test")
    (emacsvox-aural-register-feature-fragment
     '(:schema-version 1
       :id personal-fragment
       :summary "Personal fragment"
       :rules ())
     :source "test")
    (emacsvox-aural-set-enabled-feature-fragments
     '(personal-fragment built-in-fragment))
    (unwind-protect
        (save-window-excursion
          (emacsvox-aural-list-feature-fragments)
          (with-current-buffer "*Aural Feature Fragments*"
            (let ((personal
                   (cadr
                    (assq
                     'personal-fragment
                     tabulated-list-entries)))
                  (built-in
                   (cadr
                    (assq
                     'built-in-fragment
                     tabulated-list-entries))))
              (should (equal (aref personal 1) "enabled 1"))
              (should (equal (aref personal 2) "personal"))
              (should (equal (aref built-in 1) "enabled 2"))
              (should (equal (aref built-in 2) "built-in")))
            (dolist
                (binding
                 '(("RET" . emacsvox-aural-describe-feature-fragment)
                   ("SPC" . emacsvox-aural-feature-fragments-speak-current)
                   ("." . emacsvox-aural-feature-fragments-speak-current-cell)
                   ("n" . emacsvox-aural-feature-fragments-next)
                   ("p" . emacsvox-aural-feature-fragments-previous)
                   ("<down>" . emacsvox-aural-feature-fragments-next)
                   ("<up>" . emacsvox-aural-feature-fragments-previous)
                   ("<right>"
                    . emacsvox-aural-feature-fragments-next-column)
                   ("<left>"
                    . emacsvox-aural-feature-fragments-previous-column)
                   ("t" . emacsvox-aural-feature-fragments-toggle)
                   ("<M-up>" . emacsvox-aural-feature-fragments-move-up)
                   ("<M-down>" . emacsvox-aural-feature-fragments-move-down)
                   ("N" . emacsvox-aural-create-feature-fragment)
                   ("c" . emacsvox-aural-copy-feature-fragment)
                   ("e" . emacsvox-aural-feature-fragments-edit)
                   ("d" . emacsvox-aural-delete-feature-fragment)
                   ("v"
                    . emacsvox-aural-show-feature-fragment-validation)
                   ("s" . emacsvox-aural-list-schemes)
                   ("h" . emacsvox-aural)
                   ("?" . emacsvox-aural-feature-fragments-help)))
              (should
               (eq
                (lookup-key
                 emacsvox-aural-feature-fragments-mode-map
                 (kbd (car binding)))
                (cdr binding))))))
      (when (get-buffer "*Aural Feature Fragments*")
        (kill-buffer "*Aural Feature Fragments*")))))

(ert-deftest emacsvox-aural-fragment-manager-navigation-speaks-edges ()
  "Fragment movement speaks titled cells and boundaries without repetition."
  (emacsvox-test--with-aural-tools
    (dolist (id '(first-fragment second-fragment))
      (emacsvox-aural-register-feature-fragment
       (list
        :schema-version 1
        :id id
        :summary (symbol-name id)
        :rules nil)
       :built-in t :source "test"))
    (emacsvox-aural-set-enabled-feature-fragments
     '(first-fragment second-fragment))
    (unwind-protect
        (save-window-excursion
          (emacsvox-aural-list-feature-fragments)
          (with-current-buffer "*Aural Feature Fragments*"
            (let (spoken)
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text)))
                   ((symbol-function 'emacsvox-icon) #'ignore))
                (emacsvox-aural-feature-fragments-previous)
                (should
                 (equal spoken "Top of feature fragment list."))
                (emacsvox-aural-feature-fragments-next)
                (should
                 (equal spoken "Fragment, second-fragment"))
                (emacsvox-aural-feature-fragments-next)
                (should
                 (equal spoken "Bottom of feature fragment list."))
                (emacsvox-aural-feature-fragments-next-column)
                (should (equal spoken "Status, enabled 2"))))))
      (when (get-buffer "*Aural Feature Fragments*")
        (kill-buffer "*Aural Feature Fragments*")))))

(ert-deftest emacsvox-aural-fragment-manager-mutates-persistent-state ()
  "Toggle, reorder, copy, create, and delete persist one coherent state."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-fragments-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-feature-fragment
             '(:schema-version 1 :id built-in-fragment
               :summary "Built in" :rules ())
             :built-in t :source "test")
            (emacsvox-aural-register-feature-fragment
             '(:schema-version 1 :id disposable
               :summary "Disposable" :rules ())
             :source emacsvox-aural-schemes-file)
            (emacsvox-aural-feature-fragments-toggle
             'built-in-fragment)
            (emacsvox-aural-feature-fragments-toggle 'disposable)
            (should
             (equal
              emacsvox-aural-enabled-feature-fragments
              '(built-in-fragment disposable)))
            (cl-letf
                (((symbol-function
                   'emacsvox-aural-feature-fragments-speak-current)
                  #'ignore))
              (with-temp-buffer
                (emacsvox-aural-feature-fragments-mode)
                (setq
                 tabulated-list-entries
                 (list
                  (emacsvox-aural-tools--fragment-row 'disposable)))
                (tabulated-list-print)
                (emacsvox-aural-feature-fragments-move-up)))
            (should
             (equal
              emacsvox-aural-enabled-feature-fragments
              '(disposable built-in-fragment)))
            (emacsvox-aural-copy-feature-fragment
             'built-in-fragment 'copied-fragment)
            (emacsvox-aural-create-feature-fragment
             'new-fragment "New fragment")
            (should
             (emacsvox-aural-feature-fragment-entry 'copied-fragment))
            (should
             (emacsvox-aural-feature-fragment-entry 'new-fragment))
            (should-not
             (emacsvox-aural-feature-fragment-enabled-p
              'copied-fragment))
            (emacsvox-aural-delete-feature-fragment 'disposable)
            (should-not
             (emacsvox-aural-feature-fragment-entry 'disposable))
            (should
             (equal
              emacsvox-aural-enabled-feature-fragments
              '(built-in-fragment)))
            (let ((data
                   (emacsvox-aural-read-user-data
                    emacsvox-aural-schemes-file)))
              (should
               (equal
                (plist-get data :enabled-feature-fragments)
                '(built-in-fragment)))
              (should
               (equal
                (mapcar
                 (lambda (fragment) (plist-get fragment :id))
                 (plist-get data :feature-fragments))
                '(copied-fragment new-fragment)))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-fragment-manager-rolls-back-save-errors ()
  "A persistence failure restores the prior registry and enabled order."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-feature-fragment
     '(:schema-version 1 :id stable-fragment
       :summary "Stable" :rules ())
     :source "test")
    (let ((registry emacsvox-aural-feature-fragment-registry)
          (enabled emacsvox-aural-enabled-feature-fragments))
      (cl-letf
          (((symbol-function 'emacsvox-aural-save-user-data)
            (lambda (&rest _) (error "simulated save failure"))))
        (should-error
         (emacsvox-aural-feature-fragments-toggle 'stable-fragment)
         :type 'error))
      (should (eq emacsvox-aural-feature-fragment-registry registry))
      (should (eq emacsvox-aural-enabled-feature-fragments enabled))
      (should-not
       (emacsvox-aural-feature-fragment-enabled-p 'stable-fragment)))))

(ert-deftest emacsvox-aural-scheme-manager-speaks-natural-row-summary ()
  "A manager row has concise status, inheritance, resource, and count speech."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id spoken-personal
       :summary "Spoken manager test"
       :parent default
       :rules
       ((:id heading
         :match (:role heading)
         :render (:content (:voice bolden)))))
     :source "test")
    (emacsvox-aural-select-scheme 'spoken-personal)
    (let ((summary
           (emacsvox-aural-tools--scheme-spoken-summary
            'spoken-personal)))
      (should (string-match-p "spoken personal" summary))
      (should (string-match-p "Active personal scheme" summary))
      (should (string-match-p "Based on default" summary))
      (should (string-match-p "Sound pack chimes" summary))
      (should (string-match-p "1 effective presentation" summary))
      (should (string-match-p "Valid" summary)))))

(ert-deftest emacsvox-aural-scheme-manager-column-navigation-speaks-title ()
  "Horizontal movement speaks titles, blank values, and column boundaries."
  (emacsvox-test--with-aural-tools
    (unwind-protect
        (save-window-excursion
          (emacsvox-list-aural-schemes)
          (with-current-buffer "*Aural Schemes*"
            (let (spoken)
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text)))
                   ((symbol-function 'emacsvox-icon) #'ignore))
                (emacsvox-aural-schemes-previous-column)
                (should (equal spoken "First column."))
                (emacsvox-aural-schemes-next-column)
                (should (equal spoken "Status, active"))
                (emacsvox-aural-tools--goto-tabulated-column 3)
                (emacsvox-aural-schemes-speak-current-cell)
                (should (equal spoken "Based on, blank"))
                (emacsvox-aural-tools--goto-tabulated-column
                 (1- (length tabulated-list-format)))
                (emacsvox-aural-schemes-next-column)
                (should (equal spoken "Last column."))))))
      (when (get-buffer "*Aural Schemes*")
        (kill-buffer "*Aural Schemes*")))))

(ert-deftest emacsvox-aural-scheme-manager-row-navigation-speaks-boundaries ()
  "Row navigation preserves the column and announces top and bottom."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id second
       :summary "Second scheme"
       :parent default
       :rules ())
     :source "test")
    (unwind-protect
        (save-window-excursion
          (emacsvox-list-aural-schemes)
          (with-current-buffer "*Aural Schemes*"
            (let (spoken)
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text)))
                   ((symbol-function 'emacsvox-icon) #'ignore))
                (should (eq (tabulated-list-get-id) 'default))
                (emacsvox-aural-schemes-previous)
                (should (eq (tabulated-list-get-id) 'default))
                (should (equal spoken "Top of scheme list."))
                (emacsvox-aural-schemes-next)
                (should (eq (tabulated-list-get-id) 'second))
                (should (equal spoken "Scheme, second"))
                (emacsvox-aural-schemes-next)
                (should (eq (tabulated-list-get-id) 'second))
                (should (equal spoken "Bottom of scheme list."))
                (emacsvox-aural-schemes-previous)
                (should (eq (tabulated-list-get-id) 'default))
                (should (equal spoken "Scheme, default"))))))
      (when (get-buffer "*Aural Schemes*")
        (kill-buffer "*Aural Schemes*")))))

(ert-deftest emacsvox-aural-semantic-list-navigation-speaks-titles-and-edges ()
  "Semantic row and column movement announces titles and list boundaries."
  (emacsvox-test--with-aural-tools
    (unwind-protect
        (save-window-excursion
          (emacsvox-list-aural-semantics)
          (with-current-buffer "*Aural Semantics*"
            (let* ((ids
                    (mapcar
                     #'emacsvox-aural-semantic-id
                     (emacsvox-aural-semantics)))
                   (first (car ids))
                   (second (cadr ids))
                   (last (car (last ids)))
                   spoken)
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text)))
                   ((symbol-function 'emacsvox-icon) #'ignore))
                (should (eq (tabulated-list-get-id) first))
                (emacsvox-aural-semantics-previous)
                (should (equal spoken "Top of semantic list."))
                (emacsvox-aural-semantics-next)
                (should (eq (tabulated-list-get-id) second))
                (should
                 (equal
                  spoken
                  (format "Identifier, %s" second)))
                (emacsvox-aural-semantics-next-column)
                (should (string-prefix-p "Kind, " spoken))
                (emacsvox-aural-semantics--goto last)
                (emacsvox-aural-semantics-next)
                (should (eq (tabulated-list-get-id) last))
                (should (equal spoken "Bottom of semantic list."))))))
      (when (get-buffer "*Aural Semantics*")
        (kill-buffer "*Aural Semantics*")))))

(ert-deftest emacsvox-aural-scheme-manager-view-separates-direct-and-inherited ()
  "Scheme details distinguish direct, inherited, and effective presentations."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id manager-parent
       :summary "Manager parent"
       :parent default
       :rules
       ((:id parent-heading
         :match (:role heading)
         :render (:content (:voice bolden)))))
     :source "test")
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id manager-child
       :summary "Manager child"
       :parent manager-parent
       :rules
       ((:id child-item
         :match (:role heading :level 2)
         :render (:content (:voice smoothen)))))
     :source "test")
    (unwind-protect
        (save-window-excursion
          (emacsvox-describe-aural-scheme 'manager-child)
          (with-current-buffer "*Help*"
            (let ((text (buffer-string)))
              (should
               (string-match-p
                "Inheritance chain: default -> manager-parent -> manager-child"
                text))
              (should (string-match-p "Direct presentations" text))
              (should (string-match-p "child-item" text))
              (should (string-match-p "Inherited presentations" text))
              (should (string-match-p "parent-heading" text))
              (should
               (string-match-p
                "Effective presentation order (2 total)"
                text)))))
      (when (get-buffer "*Help*")
        (kill-buffer "*Help*")))))

(ert-deftest emacsvox-aural-scheme-manager-protects-built-ins ()
  "Built-in schemes cannot be edited, deleted, or renamed."
  (emacsvox-test--with-aural-tools
    (should-error
     (emacsvox-delete-aural-scheme 'default)
     :type 'user-error)
    (should-error
     (emacsvox-rename-aural-scheme 'default 'renamed-default)
     :type 'user-error)
    (cl-letf
        (((symbol-function
           'emacsvox-aural-tools--scheme-at-point-or-read)
          (lambda (&rest _) 'default)))
      (should-error
       (emacsvox-aural-schemes-edit)
       :type 'user-error)
      (should-error
       (emacsvox-aural-schemes-edit-advanced)
       :type 'user-error))))

(ert-deftest emacsvox-aural-scheme-manager-refuses-delete-with-children ()
  "Deletion names child schemes instead of breaking inheritance."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1 :id parent :summary "Parent"
       :parent default :rules ())
     :source "test")
    (emacsvox-aural-register-scheme
     '(:schema-version 1 :id child :summary "Child"
       :parent parent :rules ())
     :source "test")
    (let ((error
           (should-error
            (emacsvox-delete-aural-scheme 'parent)
            :type 'user-error)))
      (should (string-match-p "inherited by child" (cadr error))))
    (should (emacsvox-aural-scheme-entry 'parent))
    (should (emacsvox-aural-scheme-entry 'child))))

(ert-deftest emacsvox-aural-scheme-manager-delete-active-selects-parent ()
  "Deleting an active personal scheme persists removal and selects its parent."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-manager-delete-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             '(:schema-version 1 :id disposable :summary "Disposable"
               :parent default :rules ())
             :source emacsvox-aural-schemes-file)
            (emacsvox-aural-select-scheme 'disposable)
            (emacsvox-delete-aural-scheme 'disposable)
            (should-not (emacsvox-aural-scheme-entry 'disposable))
            (should (eq emacsvox-aural-active-scheme 'default))
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-scheme-manager-rename-updates-active-and-children ()
  "Renaming is atomic across the target, active selection, and child parents."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-manager-rename-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             '(:schema-version 1 :id old-parent :summary "Old parent"
               :parent default :rules ())
             :source emacsvox-aural-schemes-file)
            (emacsvox-aural-register-scheme
             '(:schema-version 1 :id child :summary "Child"
               :parent old-parent :rules ())
             :source emacsvox-aural-schemes-file)
            (emacsvox-aural-select-scheme 'old-parent)
            (emacsvox-rename-aural-scheme 'old-parent 'new-parent)
            (should-not (emacsvox-aural-scheme-entry 'old-parent))
            (should (emacsvox-aural-scheme-entry 'new-parent))
            (should (eq emacsvox-aural-active-scheme 'new-parent))
            (should
             (eq
              (emacsvox-aural-scheme-parent
               (emacsvox-aural-scheme-entry-compiled
                (emacsvox-aural-scheme-entry 'child)))
              'new-parent))
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-scheme-manager-mutations-roll-back-on-save-error ()
  "Delete and rename leave the live registry untouched when persistence fails."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1 :id personal :summary "Personal"
       :parent default :rules ())
     :source "test")
    (cl-letf
        (((symbol-function 'emacsvox-aural-save-user-data)
          (lambda (&rest _) (error "save failed"))))
      (should-error
       (emacsvox-delete-aural-scheme 'personal)
       :type 'error)
      (should (emacsvox-aural-scheme-entry 'personal))
      (should-error
       (emacsvox-rename-aural-scheme 'personal 'renamed)
       :type 'error)
      (should (emacsvox-aural-scheme-entry 'personal))
      (should-not (emacsvox-aural-scheme-entry 'renamed)))))

(ert-deftest emacsvox-aural-scheme-manager-previews-inactive-scheme ()
  "Preview uses the selected scheme without changing the active scheme."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id inactive-preview
       :summary "Inactive preview"
       :parent default
       :rules
       ((:id preview-heading
         :match (:role heading :mode emacs-lisp-mode)
         :render
         (:before
          ((:id preview-label :kind speech :text "Preview heading"))))))
     :source "test")
    (let ((tts-speaker-process 'speaker)
          queued)
      (cl-letf
          (((symbol-function 'process-live-p) (lambda (_) t))
           ((symbol-function 'emacsvox-aural-queue-concrete-plan)
            (lambda (plan &rest _) (setq queued plan)))
           ((symbol-function 'tts--protocol-dispatch) #'ignore))
        (emacsvox-preview-aural-scheme
         'inactive-preview 'preview-heading))
      (should (eq emacsvox-aural-active-scheme 'default))
      (should
       (equal
        (emacsvox-aural-concrete-action-text
         (car (emacsvox-aural-concrete-plan-before queued)))
        "Preview heading")))))

(ert-deftest emacsvox-aural-editor-reads-portable-spatial-values ()
  "The guided editor produces validated balance and azimuth scheme data."
  (cl-letf
      (((symbol-function 'completing-read)
        (lambda (&rest _) "balance"))
       ((symbol-function 'read-number)
        (lambda (&rest _) -0.35)))
    (should
     (equal
      (emacsvox-aural-editor--read-space nil "Speech")
      '(:balance -0.35))))
  (cl-letf
      (((symbol-function 'completing-read)
        (lambda (&rest _) "azimuth"))
       ((symbol-function 'read-number)
        (lambda (&rest _) 135)))
    (should
     (equal
      (emacsvox-aural-editor--read-space nil "Cue")
      '(:azimuth 135.0)))))

(ert-deftest emacsvox-aural-editor-builds-safe-semantic-speech-template ()
  "The advanced editor builds data-only speech templates."
  (cl-letf
      (((symbol-function 'completing-read)
        (lambda (prompt &rest _)
          (cond
           ((string-match-p "Action kind" prompt) "speech")
           ((string-match-p "Speech wording" prompt) "semantic template")
           ((string-match-p "Annotation voice" prompt) "default")
           ((string-match-p "spatial placement" prompt) "unchanged")
           (t (ert-fail (format "Unexpected prompt %s" prompt))))))
       ((symbol-function 'read-string)
        (lambda (prompt &rest _)
          (if (string-match-p "identifier" prompt)
              "heading-level-label"
            "Heading {level}"))))
    (let ((action
           (emacsvox-aural-editor--read-action
            'heading-rule 'before 0)))
      (should
       (equal
        action
        '(:id heading-level-label :kind speech
          :text-template "Heading {level}")))
      (should
       (emacsvox-aural-compile-rule
        (list
         :id 'heading-rule
         :match '(:role heading :requires (level))
         :render (list :before (list action)))
        'user)))))

(ert-deftest emacsvox-aural-simple-editor-describes-and-edits-required-details ()
  "The simple editor speaks presence selectors and template wording clearly."
  (should
   (equal
    (emacsvox-aural-simple-editor--attribute-description
     '(:requires (level)))
    "level present"))
  (should
   (equal
    (emacsvox-aural-simple-editor--action-description
     '(:id label :kind speech :text-template "Heading {level}"))
    "say template \"Heading {level}\""))
  (cl-letf
      (((symbol-function 'completing-read)
        (lambda (prompt &rest _)
          (cond
           ((string-match-p "Detail to edit" prompt) "level")
           ((string-match-p "level detail" prompt) "require presence")
           (t (ert-fail (format "Unexpected prompt %s" prompt)))))))
    (should
     (equal
      (emacsvox-aural-simple-editor--edit-attribute
       '(:role heading :level 2))
      '(:role heading :requires (level))))))

(defun emacsvox-test--setup-simple-editor (scheme)
  "Set up the current buffer as the simple editor for SCHEME."
  (let ((entry (emacsvox-aural-scheme-entry scheme)))
    (emacsvox-aural-simple-editor-mode)
    (setq
     emacsvox-aural-editor-scope 'scheme
     emacsvox-aural-editor-target scheme
     emacsvox-aural-editor-scheme-data
     (copy-tree (emacsvox-aural-scheme-entry-data entry))
     emacsvox-aural-editor-rules
     (copy-tree
      (plist-get (emacsvox-aural-scheme-entry-data entry) :rules))
     emacsvox-aural-editor-dirty nil)
    (emacsvox-aural-simple-editor-refresh)))

(ert-deftest emacsvox-aural-simple-editor-renders-natural-spoken-fields ()
  "The default scheme editor presents a navigable natural-language form."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'simple-test
     '((:id org-heading
        :match (:role heading :module org :occasion navigation :level 1)
        :render
        (:before
         ((:id label :kind speech :text "Heading")
          (:id cue :kind cue :cue item))
         :content (:voice bolden)
         :after (:remove (inherited-cue))))))
    (with-temp-buffer
      (emacsvox-test--setup-simple-editor 'simple-test)
      (let ((text (buffer-string))
            spoken)
        (should
         (string-match-p
          "Applies to:.*object heading; level 1; module org; during navigation"
          text))
        (should
         (string-match-p
          "Before content:.*say \"Heading\", then play the item cue"
          text))
        (should
         (string-match-p
          "Content:.*use the bolden voice"
          text))
        (should
         (string-match-p
          "Advanced details:.*advanced after-content operations"
          text))
        (should-not (string-match-p "(:role" text))
        (should
         (emacsvox-aural-simple-editor--goto-field
          '(:kind match :rule 0)))
        (should (= (emacsvox-aural-editor--index-at-point) 0))
        (goto-char
         (car
          (emacsvox-aural-simple-editor--field-positions)))
        (cl-letf
            (((symbol-function 'emacsvox-speak-line)
              (lambda ()
                (setq
                 spoken
                 (buffer-substring
                  (line-beginning-position) (line-end-position))))))
          (emacsvox-aural-simple-editor-next-field))
        (should (string-match-p "Based on:" spoken))))))

(ert-deftest emacsvox-aural-simple-editor-edits-one-field-only ()
  "RET on a field changes that field without restarting a rule wizard."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'simple-test
     '((:id heading
        :match (:role heading)
        :render (:content (:voice bolden)))))
    (with-temp-buffer
      (emacsvox-test--setup-simple-editor 'simple-test)
      (let ((rules-before (copy-tree emacsvox-aural-editor-rules)))
        (goto-char
         (car
          (emacsvox-aural-simple-editor--field-positions)))
        (cl-letf
            (((symbol-function 'read-string)
              (lambda (&rest _) "My clear scheme"))
             ((symbol-function 'emacsvox-speak-line) #'ignore))
          (emacsvox-aural-simple-editor-edit-field))
        (should
         (equal
          (plist-get emacsvox-aural-editor-scheme-data :summary)
          "My clear scheme"))
        (should (equal emacsvox-aural-editor-rules rules-before))
        (should emacsvox-aural-editor-dirty)))))

(ert-deftest emacsvox-aural-simple-editor-builds-ordered-feedback ()
  "Simple feedback choices produce validated ordered actions and placement."
  (emacsvox-test--with-aural-tools
    (let (prompts)
      (cl-letf
          (((symbol-function 'completing-read)
            (lambda (prompt &rest _)
              (push prompt prompts)
              (cond
               ((string-match-p "feedback:" prompt)
                "say a label then play a cue")
               ((string-match-p "Sound cue:" prompt) "item")
               ((string-match-p "position:" prompt) "left")
               (t (ert-fail (format "Unexpected prompt %s" prompt))))))
           ((symbol-function 'read-string)
            (lambda (&rest _) "Heading")))
        (let* ((phase
                (emacsvox-aural-simple-editor--edit-phase
                 'heading-rule 'before nil))
               (actions (plist-get phase :replace)))
          (should
           (equal (mapcar (lambda (action) (plist-get action :kind)) actions)
                  '(speech cue)))
          (should
           (equal (mapcar (lambda (action) (plist-get action :space)) actions)
                  '((:balance -0.65) (:balance -0.65))))
          (should
           (emacsvox-aural-compile-rule
            (list
             :id 'heading-rule
             :match '(:role heading)
             :render (list :before phase))
            'user)))))))

(ert-deftest emacsvox-aural-simple-editor-switch-preserves-working-data ()
  "Switching between simple and advanced views does not discard changes."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'simple-test
     '((:id heading
        :match (:role heading)
        :render (:content (:voice bolden)))))
    (with-temp-buffer
      (emacsvox-test--setup-simple-editor 'simple-test)
      (setq emacsvox-aural-editor-dirty t)
      (let ((data emacsvox-aural-editor-scheme-data)
            (rules emacsvox-aural-editor-rules))
        (emacsvox-aural-simple-editor-use-advanced)
        (should (derived-mode-p 'emacsvox-aural-scheme-editor-mode))
        (should (eq emacsvox-aural-editor-scheme-data data))
        (should (eq emacsvox-aural-editor-rules rules))
        (should emacsvox-aural-editor-dirty)
        (emacsvox-aural-editor-use-simple-editor)
        (should (derived-mode-p 'emacsvox-aural-simple-editor-mode))
        (should (eq emacsvox-aural-editor-scheme-data data))
        (should (eq emacsvox-aural-editor-rules rules))
        (should emacsvox-aural-editor-dirty)))))

(ert-deftest emacsvox-aural-simple-editor-validates-and-saves ()
  "The simple form commits through the existing atomic scheme save path."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-simple-save-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-test--register-tools-scheme
             'simple-test
             '((:id heading
                :match (:role heading)
                :render (:content (:voice bolden)))))
            (with-temp-buffer
              (emacsvox-test--setup-simple-editor 'simple-test)
              (setq
               emacsvox-aural-editor-scheme-data
               (plist-put
                (copy-tree emacsvox-aural-editor-scheme-data)
                :summary "Saved from the simple form")
               emacsvox-aural-editor-dirty t)
              (emacsvox-aural-simple-editor-save)
              (should-not emacsvox-aural-editor-dirty)
              (should
               (derived-mode-p 'emacsvox-aural-simple-editor-mode)))
            (should
             (equal
              (plist-get
               (emacsvox-aural-scheme-entry-data
                (emacsvox-aural-scheme-entry 'simple-test))
               :summary)
              "Saved from the simple form"))
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-simple-editor-copies-built-in-for-editing ()
  "The no-personal-scheme workflow offers a flattened editable copy."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-simple-copy-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             '(:schema-version 1
               :id built-in-example
               :summary "Built-in example"
               :parent default
               :rules
               ((:id built-in-rule
                 :match (:role heading)
                 :render (:content (:voice bolden)))))
             :built-in t :source "test")
            (cl-letf
                (((symbol-function 'completing-read)
                  (lambda (prompt &rest _)
                    (cond
                     ((string-match-p "Edit personal" prompt)
                      "[Copy a built-in scheme]")
                     ((string-match-p "Copy built-in" prompt)
                      "built-in-example")
                     (t (ert-fail (format "Unexpected prompt %s" prompt))))))
                 ((symbol-function 'read-string)
                  (lambda (&rest _) "my-example")))
              (should
               (eq
                (emacsvox-aural-simple-editor--read-scheme)
                'my-example)))
            (let ((entry (emacsvox-aural-scheme-entry 'my-example)))
              (should entry)
              (should-not (emacsvox-aural-scheme-entry-built-in entry))
              (should
               (equal
                (mapcar
                 (lambda (rule) (plist-get rule :id))
                 (plist-get
                  (emacsvox-aural-scheme-entry-data entry) :rules))
                '(built-in-rule)))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-edit-aural-scheme-opens-simple-editor ()
  "The public editing command now opens the simple spoken form."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'simple-test
     '((:id heading
        :match (:role heading)
        :render (:content (:voice bolden)))))
    (let (buffer)
      (unwind-protect
          (cl-letf
              (((symbol-function 'emacsvox-speak-line) #'ignore))
            (save-window-excursion
              (setq buffer
                    (emacsvox-edit-aural-scheme 'simple-test)))
            (with-current-buffer buffer
              (should
               (derived-mode-p 'emacsvox-aural-simple-editor-mode))))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-aural-editor-toggle-reorder-and-save-session ()
  "The accessible working model toggles, reorders, validates, and commits."
  (emacsvox-test--with-aural-tools
    (let ((first
           '(:id first :match (:role heading)
             :render (:content (:voice bolden))))
          (second
           '(:id second :match (:role heading)
             :render (:content (:voice lighten)))))
      (with-temp-buffer
        (emacsvox-aural-scheme-editor-mode)
        (setq
         emacsvox-aural-editor-scope 'session
         emacsvox-aural-editor-target (current-buffer)
         emacsvox-aural-editor-rules (list first second))
        (emacsvox-aural-editor-refresh)
        (goto-char
         (text-property-any
          (point-min) (point-max)
          emacsvox-aural-editor--rule-index-property 0))
        (emacsvox-aural-editor-toggle-rule)
        (goto-char
         (text-property-any
          (point-min) (point-max)
          emacsvox-aural-editor--rule-index-property 1))
        (emacsvox-aural-editor-move-rule-up)
        (emacsvox-aural-editor-save)
        (should
         (equal
          (mapcar
           (lambda (rule) (plist-get rule :id))
           emacsvox-aural-session-rules)
          '(second first)))
        (should-not (plist-get (cadr emacsvox-aural-session-rules) :enabled))
        (should-not emacsvox-aural-editor-dirty)))))

(ert-deftest emacsvox-aural-editor-saves-personal-scheme-atomically ()
  "Scheme scope replaces the personal entry and persists validated data."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-editor-scheme-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory))
           (data
            '(:schema-version 1
              :id personal
              :summary "Personal scheme"
              :parent default
              :rules
              ((:id original
                :match (:role heading)
                :render (:content (:voice bolden)))))))
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             data :source emacsvox-aural-schemes-file)
            (with-temp-buffer
              (emacsvox-aural-scheme-editor-mode)
              (setq
               emacsvox-aural-editor-scope 'scheme
               emacsvox-aural-editor-target 'personal
               emacsvox-aural-editor-scheme-data (copy-tree data)
               emacsvox-aural-editor-rules
               (copy-tree (plist-get data :rules))
               emacsvox-aural-editor-dirty t)
              (setf
               (plist-get
                (car emacsvox-aural-editor-rules)
                :enabled)
               nil)
              (emacsvox-aural-editor-save))
            (let* ((entry (emacsvox-aural-scheme-entry 'personal))
                   (saved
                    (car
                     (plist-get
                      (emacsvox-aural-scheme-entry-data entry)
                      :rules))))
              (should-not (plist-get saved :enabled))
              (should-not
               (emacsvox-aural-effective-scheme-rules 'personal)))
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-editor-saves-personal-feature-fragment ()
  "Fragment scope validates and atomically persists edited rules."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-editor-fragment-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory))
           (data
            '(:schema-version 1
              :id personal-fragment
              :summary "Personal fragment"
              :rules
              ((:id original-fragment-rule
                :match (:role heading)
                :render (:content (:speak t)))))))
      (unwind-protect
          (progn
            (emacsvox-aural-register-feature-fragment
             data :source emacsvox-aural-schemes-file)
            (emacsvox-aural-set-enabled-feature-fragments
             '(personal-fragment))
            (with-temp-buffer
              (emacsvox-aural-scheme-editor-mode)
              (setq
               emacsvox-aural-editor-scope 'fragment
               emacsvox-aural-editor-target 'personal-fragment
               emacsvox-aural-editor-scheme-data (copy-tree data)
               emacsvox-aural-editor-rules
               (copy-tree (plist-get data :rules))
               emacsvox-aural-editor-dirty t)
              (setf
               (plist-get
                (car emacsvox-aural-editor-rules)
                :enabled)
               nil)
              (emacsvox-aural-editor-save))
            (let* ((entry
                    (emacsvox-aural-feature-fragment-entry
                     'personal-fragment))
                   (saved
                    (car
                     (plist-get
                      (emacsvox-aural-feature-fragment-entry-data entry)
                      :rules))))
              (should-not (plist-get saved :enabled))
              (should
               (equal
                emacsvox-aural-enabled-feature-fragments
                '(personal-fragment))))
            (should (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-editor-refuses-invalid-scheme-resources ()
  "Saving cannot install working scheme data with missing resources."
  (emacsvox-test--with-aural-tools
    (let* ((directory (make-temp-file "emacsvox-editor-invalid-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "schemes.el" directory))
           (data
            '(:schema-version 1
              :id personal
              :summary "Personal scheme"
              :parent default
              :rules nil)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-resource-pack
             'empty
             :summary "Empty test pack"
             :kind 'sound
             :directory directory)
            (emacsvox-aural-register-scheme
             data :source emacsvox-aural-schemes-file)
            (with-temp-buffer
              (emacsvox-aural-scheme-editor-mode)
              (setq
               emacsvox-aural-editor-scope 'scheme
               emacsvox-aural-editor-target 'personal
               emacsvox-aural-editor-scheme-data
               (plist-put (copy-tree data) :resource-pack 'empty)
               emacsvox-aural-editor-rules
               '((:id missing
                  :match (:role heading)
                  :render
                  (:before
                   ((:id missing-cue :kind cue :cue item))))))
              (should-error
               (emacsvox-aural-editor-save)
               :type 'user-error))
            (should-not
             (plist-get
              (emacsvox-aural-scheme-entry-data
               (emacsvox-aural-scheme-entry 'personal))
              :resource-pack))
            (should-not (file-exists-p emacsvox-aural-schemes-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-editor-saves-to-original-buffer-scope ()
  "Buffer scope applies working rules to the source, not the editor buffer."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-editor-source*"))
          (rule
           '(:id local
             :match (:role heading)
             :render (:content (:voice bolden)))))
      (unwind-protect
          (with-temp-buffer
            (emacsvox-aural-scheme-editor-mode)
            (setq
             emacsvox-aural-editor-scope 'buffer
             emacsvox-aural-editor-target source
             emacsvox-aural-editor-rules (list rule))
            (emacsvox-aural-editor-save)
            (should-not emacsvox-aural-buffer-rules)
            (with-current-buffer source
              (should
               (equal
                (plist-get (car emacsvox-aural-buffer-rules) :id)
                'local))))
        (kill-buffer source)))))

(provide 'emacsvox-aural-tools-tests)
;;; emacsvox-aural-tools-tests.el ends here
