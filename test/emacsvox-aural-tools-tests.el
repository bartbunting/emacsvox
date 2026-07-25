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

(defmacro emacsvox-test--with-aural-tools (&rest body)
  "Run BODY with isolated scheme, override, and training state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-module-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-active-scheme-changed-hook nil)
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
  "Semantic and scheme list commands populate predictable tabulated buffers."
  (emacsvox-test--with-aural-tools
    (save-window-excursion
      (emacsvox-list-aural-semantics)
      (with-current-buffer "*Aural Semantics*"
        (should (derived-mode-p 'emacsvox-aural-semantics-mode))
        (should tabulated-list-entries))
      (emacsvox-list-aural-schemes)
      (with-current-buffer "*Aural Schemes*"
        (should (derived-mode-p 'emacsvox-aural-schemes-mode))
        (should
         (equal (mapcar #'car tabulated-list-entries) '(default)))))
    (kill-buffer "*Aural Semantics*")
    (kill-buffer "*Aural Schemes*")))

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
