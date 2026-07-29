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
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-scheme-manager)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-recent-feedback)
(require 'emacsvox-aural-feature-fragments)
(require 'emacsvox-aural-home)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-overrides)
(require 'emacsvox-aural-simple-editor)
(require 'emacsvox-aural-voice-palettes)

(defmacro emacsvox-test--with-aural-tools (&rest body)
  "Run BODY with isolated scheme, override, and training state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-module-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-example-registry
          (make-hash-table :test #'equal))
         (emacsvox-aural-enabled-feature-fragments nil)
         (emacsvox-aural-feature-fragment-order nil)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-configuration-generation 0)
         (emacsvox-aural-configuration-changed-hook nil)
         (emacsvox-aural--current-rules-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--provider-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--current-rules-cache-hits 0)
         (emacsvox-aural--current-rules-cache-misses 0)
         (emacsvox-aural-presentation-history nil)
         (emacsvox-aural-presentation-history-limit 20)
         (emacsvox-aural--presentation-sequence 0)
         (emacsvox-aural-history-record-interface-presentations nil)
         (emacsvox-aural-tools--last-source-buffer nil)
         (emacsvox-aural-tools--fragment-preview-last-examples
          (make-hash-table :test #'eq))
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-effective-resource-pack-changed-hook nil)
         (emacsvox-aural-feature-fragments-changed-hook nil)
         (emacsvox-aural-face-presentation-enabled t)
         (emacsvox-aural-face-presentation-changed-hook nil)
         (emacsvox-aural-plan-presented-hook nil)
         (post-command-hook nil)
         (this-command nil)
         (real-this-command nil)
         (emacsvox-aural-training-mode nil)
         (emacsvox-aural-training-voice 'annotate)
         (emacsvox-aural-tools--pending-training-explanations nil)
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

(ert-deftest emacsvox-aural-tools-voice-remap-derives-stable-dired-selector ()
  "Dired directory remaps use semantic identity, not transient movement."
  (let ((selector
         (emacsvox-aural-tools--voice-remap-selector
          '(:role filesystem-entry
            :entry-kind directory
            :events (focus-entered))
          '(:module dired
            :mode dired-mode
            :occasion navigation
            :legacy-faces (dired-directory)))))
    (should
     (equal
      selector
      '(:role filesystem-entry
        :entry-kind directory
        :module dired)))
    (should-not (plist-member selector :events))
    (should-not (plist-member selector :occasion))
    (should-not (plist-member selector :legacy-face))))

(ert-deftest emacsvox-aural-tools-voice-remap-prefills-named-voice-rule ()
  "The point wizard prepares a reviewable scoped rule without saving it."
  (emacsvox-test--with-aural-tools
    (let* ((source (generate-new-buffer " *aural-remap-source*"))
           (render
            (emacsvox-aural--make-render-plan
             :content
             (emacsvox-aural--make-content-style
              :voice 'voice-bolden)))
           answers
           prepared)
      (unwind-protect
          (cl-letf
              (((symbol-function
                 'emacsvox-aural-tools--remap-source-input)
                (lambda ()
                  (list
                   :source source
                   :facts
                   '(:role filesystem-entry
                     :entry-kind directory
                     :events (focus-entered))
                   :context
                   '(:module dired
                     :mode dired-mode
                     :occasion navigation
                     :legacy-faces (dired-directory))
                   :render render)))
               ((symbol-function 'completing-read)
                (lambda (prompt &rest _)
                  (push prompt answers)
                  (if (string-prefix-p "Voice for " prompt)
                      "animate"
                    "always (personal)")))
               ((symbol-function
                 'emacsvox-aural-editor--open-prefilled-rule)
                (lambda (scope rule source-buffer)
                  (setq prepared
                        (list scope rule source-buffer)))))
            (emacsvox-aural-remap-voice-at-point)
            (should
             (equal
              prepared
              (list
               'personal
               '(:id
                 personal-remap-dired-filesystem-entry-entry-kind-directory-voice
                 :match
                 (:role filesystem-entry
                  :entry-kind directory
                  :module dired)
                 :render (:content (:voice animate)))
               source)))
            (should
             (string-match-p
              "currently bolden"
              (car (last answers)))))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-earcon-remap-keeps-transition-context ()
  "Earcon remaps retain event and occasion unlike object-wide voice remaps."
  (let ((selector
         (emacsvox-aural-tools--earcon-remap-selector
          '(:role filesystem-entry
            :entry-kind directory
            :events (state-changed))
          '(:module dired
            :mode dired-mode
            :occasion state-change))))
    (should
     (equal
      selector
      '(:role filesystem-entry
        :entry-kind directory
        :module dired
        :events (state-changed)
        :occasion state-change)))))

(ert-deftest emacsvox-aural-overrides-manager-unifies-scopes-and-live-matches ()
  "The manager explains all override scopes against its remembered source."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-overrides-source*")))
      (unwind-protect
          (progn
            (setq
             emacsvox-aural-user-rules
             '((:id personal-directory-voice
                :match
                (:role filesystem-entry
                 :entry-kind directory
                 :module dired)
                :render (:content (:voice animate)))))
            (setq
             emacsvox-aural-session-rules
             '((:id session-directory-cue
                :enabled nil
                :match
                (:role filesystem-entry
                 :entry-kind directory
                 :module dired)
                :render
                (:before
                 ((:id directory-cue
                   :kind cue
                   :cue open-object))))))
            (with-current-buffer source
              (insert
               (emacsvox-aural-prepare-text
                "src"
                '(:role filesystem-entry
                  :entry-kind directory
                  :content "src")
                (emacsvox-aural-capture-context
                 'dired 'navigation)))
              (goto-char (point-min))
              (setq-local
               emacsvox-aural-buffer-rules
               '((:id buffer-message-voice
                  :match (:role message :module notmuch)
                  :render (:content (:voice smoothen))))))
            (should
             (equal
              (emacsvox-aural-overrides-status source)
              "1 personal, 1 session, 1 this buffer"))
            (save-window-excursion
              (emacsvox-aural-list-overrides source)
              (with-current-buffer "*Aural Presentation Overrides*"
                (should
                 (derived-mode-p 'emacsvox-aural-overrides-mode))
                (should
                 (equal
                  (mapcar #'car tabulated-list-entries)
                  '((personal personal-directory-voice)
                    (session session-directory-cue)
                    (buffer buffer-message-voice))))
                (let ((personal
                       (cadr
                        (assoc
                         '(personal personal-directory-voice)
                         tabulated-list-entries)))
                      (session
                       (cadr
                        (assoc
                         '(session session-directory-cue)
                         tabulated-list-entries)))
                      (buffer
                       (cadr
                        (assoc
                         '(buffer buffer-message-voice)
                         tabulated-list-entries))))
                  (should (equal (aref personal 0) "personal"))
                  (should
                   (string-match-p "voice animate" (aref personal 3)))
                  (should (equal (aref personal 4) "enabled"))
                  (should (equal (aref personal 5) "matches here"))
                  (should (equal (aref session 4) "disabled"))
                  (should (equal (aref session 5) "would match"))
                  (should (equal (aref buffer 5) "not here")))
                (dolist
                    (binding
                     '(("RET" . emacsvox-aural-overrides-edit)
                       ("P" . emacsvox-aural-overrides-preview)
                       ("t" . emacsvox-aural-overrides-toggle)
                       ("d" . emacsvox-aural-overrides-delete)
                       ("f" . emacsvox-aural-overrides-filter)
                       ("a" . emacsvox-aural-overrides-clear-filter)))
                  (should
                   (eq
                    (lookup-key
                     emacsvox-aural-overrides-mode-map
                     (kbd (car binding)))
                    (cdr binding)))))))
        (when (get-buffer "*Aural Presentation Overrides*")
          (kill-buffer "*Aural Presentation Overrides*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-overrides-toggle-applies-session-rule ()
  "Toggling in the manager immediately changes the existing session layer."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-override-toggle*")))
      (unwind-protect
          (progn
            (setq
             emacsvox-aural-session-rules
             '((:id temporary-heading
                :match (:role heading)
                :render (:content (:voice bolden)))))
            (save-window-excursion
              (emacsvox-aural-list-overrides source)
              (with-current-buffer "*Aural Presentation Overrides*"
                (emacsvox-aural-ui-goto-row
                 '(session temporary-heading))
                (cl-letf
                    (((symbol-function 'tts-speak) #'ignore))
                  (should-not (emacsvox-aural-overrides-toggle))
                  (should-not
                   (plist-get
                    (car emacsvox-aural-session-rules)
                    :enabled))
                  (should (emacsvox-aural-overrides-toggle))
                  (should
                   (plist-get
                    (car emacsvox-aural-session-rules)
                    :enabled))))))
        (when (get-buffer "*Aural Presentation Overrides*")
          (kill-buffer "*Aural Presentation Overrides*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-overrides-filter-and-clear-preserve-layers ()
  "Scope filtering narrows the unified view without changing rule data."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-override-filter*")))
      (unwind-protect
          (progn
            (setq
             emacsvox-aural-user-rules
             '((:id personal-org
                :match (:role heading :module org)
                :render (:content (:voice bolden)))))
            (setq
             emacsvox-aural-session-rules
             '((:id session-mail
                :match (:role message :module notmuch)
                :render (:content (:voice smoothen)))))
            (save-window-excursion
              (emacsvox-aural-list-overrides source)
              (with-current-buffer "*Aural Presentation Overrides*"
                (let ((answers '("session" "all" "all")))
                  (cl-letf
                      (((symbol-function 'completing-read)
                        (lambda (&rest _) (pop answers)))
                       ((symbol-function 'tts-speak) #'ignore))
                    (emacsvox-aural-overrides-filter)))
                (should
                 (equal
                  (mapcar #'car tabulated-list-entries)
                  '((session session-mail))))
                (cl-letf
                    (((symbol-function 'tts-speak) #'ignore))
                  (emacsvox-aural-overrides-clear-filter))
                (should
                 (equal
                  (mapcar #'car tabulated-list-entries)
                  '((personal personal-org)
                    (session session-mail))))
                (should (= (length emacsvox-aural-user-rules) 1))
                (should (= (length emacsvox-aural-session-rules) 1)))))
        (when (get-buffer "*Aural Presentation Overrides*")
          (kill-buffer "*Aural Presentation Overrides*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-overrides-preview-resolves-complete-cascade ()
  "Override preview includes matching base-scheme and override behavior."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-override-preview*"))
          played)
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             '(:schema-version 1
               :id preview-base
               :summary "Preview base"
               :parent default
               :rules
               ((:id base-heading-label
                 :match (:role heading)
                 :render
                 (:before
                  ((:id base-label
                    :kind speech
                    :text "Base heading"))))))
             :source "test")
            (emacsvox-aural-select-scheme 'preview-base)
            (setq
             emacsvox-aural-user-rules
             '((:id personal-heading-voice
                :match (:role heading)
                :render (:content (:voice bolden)))))
            (with-current-buffer source
              (insert
               (emacsvox-aural-prepare-text
                "Title"
                '(:role heading :content "Title")
                (emacsvox-aural-capture-context
                 'org 'navigation)))
              (goto-char (point-min)))
            (save-window-excursion
              (emacsvox-aural-list-overrides source)
              (with-current-buffer "*Aural Presentation Overrides*"
                (cl-letf
                    (((symbol-function 'emacsvox-aural-preview-play-plan)
                      (lambda (plan) (setq played plan))))
                  (let ((plan (emacsvox-aural-overrides-preview)))
                    (should (eq plan played))
                    (should
                     (equal
                      (emacsvox-aural-concrete-action-text
                       (car
                        (emacsvox-aural-concrete-plan-before plan)))
                      "Base heading"))
                    (should
                     (eq
                      (emacsvox-aural-concrete-content-voice-request
                       (emacsvox-aural-concrete-plan-content plan))
                      'bolden)))))))
        (when (get-buffer "*Aural Presentation Overrides*")
          (kill-buffer "*Aural Presentation Overrides*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-overrides-personal-delete-is-atomic ()
  "Personal removal persists, and a persistence failure restores the rule."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-override-delete*"))
          saved)
      (unwind-protect
          (progn
            (setq
             emacsvox-aural-user-rules
             '((:id persistent-heading
                :match (:role heading)
                :render (:content (:voice bolden)))))
            (save-window-excursion
              (emacsvox-aural-list-overrides source)
              (with-current-buffer "*Aural Presentation Overrides*"
                (emacsvox-aural-ui-goto-row
                 '(personal persistent-heading))
                (cl-letf
                    (((symbol-function 'yes-or-no-p)
                      (lambda (&rest _) t))
                     ((symbol-function 'emacsvox-aural-save-user-data)
                      (lambda (&rest _)
                        (error "simulated save failure"))))
                  (should-error
                   (emacsvox-aural-overrides-delete)
                   :type 'error))
                (should
                 (eq
                  (plist-get (car emacsvox-aural-user-rules) :id)
                  'persistent-heading))
                (cl-letf
                    (((symbol-function 'yes-or-no-p)
                      (lambda (&rest _) t))
                     ((symbol-function 'emacsvox-aural-save-user-data)
                      (lambda (&rest _) (setq saved t)))
                     ((symbol-function 'tts-speak) #'ignore))
                  (emacsvox-aural-overrides-delete))
                (should saved)
                (should-not emacsvox-aural-user-rules))))
        (when (get-buffer "*Aural Presentation Overrides*")
          (kill-buffer "*Aural Presentation Overrides*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-editor-opens-the-selected-override-rule ()
  "The manager-facing editor entry point preserves the selected rule."
  (emacsvox-test--with-aural-tools
    (let ((source (generate-new-buffer " *aural-override-editor*")))
      (unwind-protect
          (progn
            (setq
             emacsvox-aural-session-rules
             '((:id first
                :match (:role heading)
                :render (:content (:voice bolden)))
               (:id second
                :match (:role paragraph)
                :render (:content (:voice smoothen)))))
            (save-window-excursion
              (let ((buffer
                     (emacsvox-aural-editor-open-rule
                      'session 'second source)))
                (with-current-buffer buffer
                  (should
                   (= 1
                      (get-text-property
                       (point)
                       emacsvox-aural-editor--rule-index-property)))))))
        (when (get-buffer "*Aural Editor: session*")
          (kill-buffer "*Aural Editor: session*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-earcon-remap-selects-one-exact-phase ()
  "Multiple earcons are distinguished by phase, action, and source."
  (let* ((before
          (emacsvox-aural--make-concrete-action
           :id 'open-cue :kind 'cue :cue 'open-object
           :source 'open-rule))
         (after
          (emacsvox-aural--make-concrete-action
           :id 'mark-cue :kind 'cue :cue 'mark-object
           :source 'mark-rule))
         (concrete
          (emacsvox-aural--make-concrete-plan
           :before (list before)
           :after (list after)))
         choice)
    (cl-letf
        (((symbol-function 'completing-read)
          (lambda (_prompt collection &rest _)
            (cl-find-if
             (lambda (candidate)
               (string-prefix-p "After position" candidate))
             collection))))
      (setq choice
            (emacsvox-aural-tools--earcon-remap-choice concrete)))
    (should (eq (plist-get choice :phase) 'after))
    (should (eq (plist-get choice :action) after))))

(ert-deftest emacsvox-aural-tools-earcon-remap-rejects-duplicate-action-id ()
  "An ambiguous remove-by-ID operation is never described as exact."
  (let* ((first
          (emacsvox-aural--make-concrete-action
           :id 'shared-cue :kind 'cue :cue 'item :anchor 'object))
         (second
          (emacsvox-aural--make-concrete-action
           :id 'shared-cue :kind 'cue :cue 'button :anchor 'object))
         (concrete
          (emacsvox-aural--make-concrete-plan
           :before (list first second))))
    (should-error
     (emacsvox-aural-tools--validate-earcon-remap-choice
      (list :phase 'before :action first)
      concrete)
     :type 'user-error)))

(ert-deftest emacsvox-aural-tools-earcon-replacement-preview-is-cue-only ()
  "A replacement resolves through the active pack and bypasses speech."
  (emacsvox-test--with-aural-tools
    (let (played)
      (cl-letf
          (((symbol-function 'emacsvox-aural-preview-play-cues)
            (lambda (cues) (setq played cues))))
        (let ((result
               (emacsvox-aural-tools--preview-replacement-earcon
                '(:id replacement :kind cue :cue button :anchor object)
                '(:role filesystem-entry)
                '(:module dired :occasion navigation))))
          (should (eq result (car played)))
          (should
           (eq
            (emacsvox-aural-concrete-action-cue result)
            'button))
          (should
           (string-suffix-p
            "/button.ogg"
            (emacsvox-aural-concrete-action-resource result))))))))

(ert-deftest emacsvox-aural-tools-earcon-remap-prefills-exact-action-rule ()
  "The earcon wizard replaces one anchored action without freezing its phase."
  (emacsvox-test--with-aural-tools
    (let* ((source (generate-new-buffer " *aural-earcon-remap-source*"))
           (action
            (emacsvox-aural--make-concrete-action
             :id 'directory-cue
             :kind 'cue
             :cue 'item
             :resource "/tmp/item.ogg"
             :sample-id 'item
             :source 'dired-directory-rule
             :anchor 'object
             :requested-volume 0.6
             :requested-space '(:balance -0.2)))
           (concrete
            (emacsvox-aural--make-concrete-plan
             :before (list action)))
           prepared
           previewed
           auditions)
      (unwind-protect
          (cl-letf
              (((symbol-function
                 'emacsvox-aural-tools--remap-source-input)
                (lambda ()
                  (list
                   :source source
                   :facts
                   '(:role filesystem-entry
                     :entry-kind directory
                     :events (state-changed))
                   :context
                   '(:module dired
                     :mode dired-mode
                     :occasion state-change)
                   :concrete concrete)))
               ((symbol-function 'completing-read)
                (lambda (prompt &rest _)
                  (cond
                   ((string-prefix-p "Change " prompt) "replace it")
                   ((string-prefix-p "Keep this " prompt)
                    "always (personal)")
                   ((string-prefix-p "Replacement " prompt) "button")
                   (t (ert-fail (format "Unexpected prompt: %s" prompt))))))
               ((symbol-function 'emacsvox-aural-preview-play-cues)
                (lambda (cues)
                  (push cues auditions)))
               ((symbol-function
                 'emacsvox-aural-tools--preview-replacement-earcon)
                (lambda (data facts context)
                  (setq previewed (list data facts context))))
               ((symbol-function
                 'emacsvox-aural-editor--open-prefilled-rule)
                (lambda (scope rule source-buffer)
                  (setq prepared (list scope rule source-buffer)))))
            (emacsvox-aural-remap-earcon-at-point)
            (should
             (equal
              prepared
              (list
               'personal
               '(:id
                 personal-remap-dired-filesystem-entry-event-state-changed-occasion-state-change-entry-kind-directory-earcon-before-directory-cue
                 :match
                 (:role filesystem-entry
                  :entry-kind directory
                  :module dired
                  :events (state-changed)
                  :occasion state-change)
                 :render
                 (:before
                  (:anchor object
                   :remove (directory-cue)
                   :prepend
                   ((:id directory-cue
                     :kind cue
                     :cue button
                     :anchor object
                     :volume 0.6
                     :space (:balance -0.2))))))
               source)))
            (should (equal auditions (list (list action))))
            (should
             (equal
              previewed
              (list
               '(:id directory-cue
                 :kind cue
                 :cue button
                 :anchor object
                 :volume 0.6
                 :space (:balance -0.2))
               '(:role filesystem-entry
                 :entry-kind directory
                 :events (state-changed))
               '(:module dired
                 :mode dired-mode
                 :occasion state-change))))
            (should
             (emacsvox-aural-compile-rule (cadr prepared) 'user))
            (let* ((base
                    (emacsvox-aural-compile-rule
                     '(:id base-directory-cue
                       :match
                       (:role filesystem-entry
                        :entry-kind directory
                        :module dired
                        :events (state-changed)
                        :occasion state-change)
                       :render
                       (:before
                        ((:id directory-cue
                          :kind cue
                          :cue item
                          :anchor object))))
                     'core))
                   (override
                    (emacsvox-aural-compile-rule
                     (cadr prepared) 'user))
                   (resolved
                    (emacsvox-aural-resolve
                     '(:role filesystem-entry
                       :entry-kind directory
                       :events (state-changed))
                     '(:module dired :occasion state-change)
                     (list base override)
                     'object))
                   (actions
                    (emacsvox-aural-render-plan-before resolved)))
              (should (= (length actions) 1))
              (should
               (eq (emacsvox-aural-action-cue (car actions)) 'button))))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-earcon-remap-can-suppress-one-action ()
  "Suppressing an earcon removes only its exact ID at its frozen anchor."
  (emacsvox-test--with-aural-tools
    (let* ((source (generate-new-buffer " *aural-earcon-suppress-source*"))
           (action
            (emacsvox-aural--make-concrete-action
             :id 'marked-cue
             :kind 'cue
             :cue 'mark-object
             :resource "/tmp/mark.ogg"
             :sample-id 'mark
             :source 'dired-mark-rule
             :anchor 'transition))
           (concrete
            (emacsvox-aural--make-concrete-plan
             :after (list action)))
           prepared)
      (unwind-protect
          (cl-letf
              (((symbol-function
                 'emacsvox-aural-tools--remap-source-input)
                (lambda ()
                  (list
                   :source source
                   :facts
                   '(:role filesystem-entry
                     :states (marked)
                     :events (state-changed))
                   :context
                   '(:module dired :occasion state-change)
                   :concrete concrete)))
               ((symbol-function 'completing-read)
                (lambda (prompt &rest _)
                  (if (string-prefix-p "Change " prompt)
                      "suppress it"
                    "this Emacs session")))
               ((symbol-function 'emacsvox-aural-preview-play-cues)
                #'ignore)
               ((symbol-function
                 'emacsvox-aural-editor--open-prefilled-rule)
                (lambda (scope rule source-buffer)
                  (setq prepared (list scope rule source-buffer)))))
            (emacsvox-aural-remap-earcon-at-point)
            (should
             (equal
              prepared
              (list
               'session
               '(:id
                 session-remap-dired-filesystem-entry-marked-event-state-changed-occasion-state-change-earcon-after-marked-cue
                 :match
                 (:role filesystem-entry
                  :states (marked)
                  :module dired
                  :events (state-changed)
                  :occasion state-change)
                 :render
                 (:after
                  (:anchor transition :remove (marked-cue))))
               source)))
            (should
             (emacsvox-aural-compile-rule (cadr prepared) 'user)))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-earcon-remap-can-restore-generated-rule ()
  "Restoration targets the same stable scope-specific generated rule."
  (emacsvox-test--with-aural-tools
    (let* ((action
            (emacsvox-aural--make-concrete-action
             :id 'directory-cue
             :kind 'cue
             :cue 'button
             :resource "/tmp/button.ogg"
             :sample-id 'button
             :anchor 'object))
           (concrete
            (emacsvox-aural--make-concrete-plan
             :before (list action)))
           removed)
      (cl-letf
          (((symbol-function
             'emacsvox-aural-tools--remap-source-input)
            (lambda ()
              (list
               :facts
               '(:role filesystem-entry :entry-kind directory)
               :context
               '(:module dired :occasion navigation)
               :concrete concrete)))
           ((symbol-function 'completing-read)
            (lambda (prompt &rest _)
              (if (string-prefix-p "Change " prompt)
                  "restore inherited behavior"
                "this Emacs session")))
           ((symbol-function 'emacsvox-aural-preview-play-cues)
            #'ignore)
           ((symbol-function
             'emacsvox-aural-editor--open-without-rule)
            (lambda (scope rule-id source)
              (setq removed (list scope rule-id source)))))
        (emacsvox-aural-remap-earcon-at-point))
      (should
       (equal
        removed
        '(session
          session-remap-dired-filesystem-entry-occasion-navigation-entry-kind-directory-earcon-before-directory-cue
          nil))))))

(ert-deftest emacsvox-aural-editor-prefilled-rule-is-dirty-and-selected ()
  "A point remap replaces its stable draft and selects it for review."
  (emacsvox-test--with-aural-tools
    (let* ((name "*Aural Editor: session*")
           (buffer (get-buffer-create name))
           (source (generate-new-buffer " *aural-remap-editor-source*"))
           (old
            '(:id session-remap-dired-directory-voice
              :match (:module dired)
              :render (:content (:voice bolden))))
           (new
            '(:id session-remap-dired-directory-voice
              :match (:module dired :role filesystem-entry)
              :render (:content (:voice animate)))))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (emacsvox-aural-scheme-editor-mode)
              (setq
               emacsvox-aural-editor-scope 'session
               emacsvox-aural-editor-rules (list old)
               emacsvox-aural-editor-dirty nil))
            (cl-letf
                (((symbol-function 'emacsvox-edit-aural-rules)
                  (lambda (&rest _) buffer)))
              (should
               (eq
                (emacsvox-aural-editor--open-prefilled-rule
                 'session new source)
                buffer)))
            (with-current-buffer buffer
              (should emacsvox-aural-editor-dirty)
              (should (equal emacsvox-aural-editor-rules (list new)))
              (should
               (= (emacsvox-aural-editor--index-at-point) 0))))
        (kill-buffer buffer)
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-editor-remap-removal-restores-inheritance-unsaved ()
  "Removing a generated remap opens as a reviewable unsaved deletion."
  (emacsvox-test--with-aural-tools
    (let* ((name "*Aural Editor: session*")
           (buffer (get-buffer-create name))
           (source
            (generate-new-buffer " *aural-remap-removal-source*"))
           (keep
            '(:id keep-rule
              :match (:module dired)
              :render (:content (:voice bolden))))
           (remove
            '(:id session-remap-dired-item-earcon-before-item-cue
              :match (:module dired :role filesystem-entry)
              :render (:before (:remove (item-cue))))))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (emacsvox-aural-scheme-editor-mode)
              (setq
               emacsvox-aural-editor-scope 'session
               emacsvox-aural-editor-rules (list keep remove)
               emacsvox-aural-editor-dirty nil))
            (cl-letf
                (((symbol-function 'emacsvox-edit-aural-rules)
                  (lambda (&rest _) buffer)))
              (should
               (eq
                (emacsvox-aural-editor--open-without-rule
                 'session
                 'session-remap-dired-item-earcon-before-item-cue
                 source)
                buffer)))
            (with-current-buffer buffer
              (should emacsvox-aural-editor-dirty)
              (should (equal emacsvox-aural-editor-rules (list keep)))))
        (kill-buffer buffer)
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-recent-feedback-browses-frozen-output ()
  "Recent feedback exposes exact records for explanation and audition."
  (emacsvox-test--with-aural-tools
    (let* ((source (generate-new-buffer " *aural-feedback-source*"))
           (source-name (buffer-name source))
           (render
            (emacsvox-aural--make-render-plan
             :content
             (emacsvox-aural--make-content-style :voice 'bolden)))
           (cue
            (emacsvox-aural--make-concrete-action
             :id 'directory-cue
             :kind 'cue
             :cue 'item
             :resource "/tmp/item.ogg"
             :sample-id 'item-sample))
           (old-plan
            (emacsvox-aural--make-concrete-plan
             :content
             (emacsvox-aural--make-concrete-content
              :text "Documents"
              :speak t
              :voice-request 'lighten)
             :facts
             '(:role filesystem-entry :entry-kind directory)
             :context
             '(:module dired :mode dired-mode
               :mode-lineage (dired-mode) :occasion navigation)
             :source-plan render
             :degradations nil
             :rule-provenance nil))
           (new-plan
            (emacsvox-aural--make-concrete-plan
             :before (list cue)
             :content
             (emacsvox-aural--make-concrete-content
              :text "Network"
              :speak t
              :voice-request 'bolden)
             :facts
             '(:role filesystem-entry :entry-kind directory)
             :context
             '(:module dired :mode dired-mode
               :mode-lineage (dired-mode) :occasion navigation)
             :source-plan render
             :degradations '((:reason unsupported-space))
             :rule-provenance
             '((:id directory-rule
                :semantic-matches
                ((:kind role :selected object :actual filesystem-entry
                  :distance 1))))))
           (old-record
            (emacsvox-aural--make-presentation-record
             :id 1
             :queued-at (seconds-to-time 100)
             :plan old-plan
             :source-buffer-name source-name
             :source-position 1))
           (new-record
            (emacsvox-aural--make-presentation-record
             :id 2
             :queued-at (seconds-to-time 200)
             :plan new-plan
             :source-buffer-name source-name
             :source-position 2))
           spoken explained replayed auditioned remapped remapped-earcon)
      (setq
       emacsvox-aural-presentation-history
       (list new-record old-record))
      (unwind-protect
          (save-window-excursion
            (with-current-buffer source
              (emacsvox-aural-list-recent-feedback))
            (with-current-buffer "*Recent Aural Feedback*"
              (should
               (derived-mode-p 'emacsvox-aural-recent-feedback-mode))
              (should (eq emacsvox-aural-ui-source-buffer source))
              (should
               (equal
                (mapcar #'car tabulated-list-entries)
                '(2 1)))
              (should (= (tabulated-list-get-id) 2))
              (should
               (eq
                (key-binding (kbd "RET"))
                #'emacsvox-aural-recent-feedback-explain))
              (should
               (eq
                (key-binding (kbd "P"))
                #'emacsvox-aural-recent-feedback-replay))
              (should
               (eq
                (key-binding (kbd "p"))
                #'emacsvox-aural-ui-previous-row))
              (should
               (eq
                (key-binding (kbd "c"))
                #'emacsvox-aural-recent-feedback-audition-cues))
              (should
               (eq
                (key-binding (kbd "R"))
                #'emacsvox-aural-recent-feedback-remap-earcon))
              (should
               (eq
                (key-binding (kbd "i"))
                #'emacsvox-aural-toggle-interface-history-recording))
              (should
               (eq
                (key-binding (kbd "L"))
                #'emacsvox-aural-set-history-limit))
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text))))
                (emacsvox-aural-recent-feedback-speak-current))
              (dolist
                  (detail
                   '("Network"
                     "filesystem entry"
                     "Voice bolden"
                     "Earcons item"
                     "1 degradation"
                     "1 semantic fallback"))
                (should (string-match-p detail spoken)))
              (cl-letf
                  (((symbol-function
                     'emacsvox-aural-tools--display-explanation)
                    (lambda (explanation &rest _)
                      (setq explained explanation)))
                   ((symbol-function 'emacsvox-aural-preview-play-plan)
                    (lambda (plan) (setq replayed plan)))
                   ((symbol-function 'emacsvox-aural-preview-play-cues)
                    (lambda (cues) (setq auditioned cues)))
                   ((symbol-function
                     'emacsvox-aural-remap-voice-at-point)
                    (lambda (&optional record)
                      (setq remapped record)))
                   ((symbol-function
                     'emacsvox-aural-remap-earcon-at-point)
                    (lambda (&optional record)
                      (setq remapped-earcon record))))
                (emacsvox-aural-recent-feedback-explain)
                (should
                 (eq
                  (emacsvox-aural-explanation-basis explained)
                  'exact-queued))
                (should
                 (= (emacsvox-aural-explanation-presentation-id explained)
                    2))
                (emacsvox-aural-recent-feedback-replay)
                (should (eq replayed new-plan))
                (emacsvox-aural-recent-feedback-audition-cues)
                (should (equal auditioned (list cue)))
                (emacsvox-aural-recent-feedback-remap-voice)
                (should (eq remapped new-record))
                (emacsvox-aural-recent-feedback-remap-earcon)
                (should (eq remapped-earcon new-record)))
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text))))
                (should
                 (emacsvox-aural-toggle-interface-history-recording))
                (should
                 (equal spoken
                        "Aural interface history recording on"))
                (should-not
                 (emacsvox-aural-toggle-interface-history-recording))
                (should
                 (equal spoken
                        "Aural interface history recording off"))
                (should (= (emacsvox-aural-set-history-limit 1) 1))
                (should (= (length emacsvox-aural-presentation-history) 1))
                (should (= (emacsvox-aural-set-history-limit 250) 250))
                (should
                 (= emacsvox-aural-presentation-history-limit 250)))))
        (when (get-buffer "*Recent Aural Feedback*")
          (kill-buffer "*Recent Aural Feedback*"))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-record-remap-requires-matching-source ()
  "Historical remapping never guesses a live buffer from a retained name."
  (emacsvox-test--with-aural-tools
    (let* ((source (generate-new-buffer " *aural-record-source*"))
           (plan
            (emacsvox-aural--make-concrete-plan
             :content
             (emacsvox-aural--make-concrete-content
              :text "Network" :speak t :voice-request 'bolden)
             :facts
             '(:role filesystem-entry :entry-kind directory)
             :context '(:module dired :mode dired-mode)
             :source-plan
             (emacsvox-aural--make-render-plan
              :content
              (emacsvox-aural--make-content-style :voice 'bolden))))
           (record
            (emacsvox-aural--make-presentation-record
             :id 1
             :queued-at (current-time)
             :plan plan
             :source-buffer-name (buffer-name source))))
      (unwind-protect
          (progn
            (with-current-buffer source
              (should
               (eq
                (plist-get
                 (emacsvox-aural-tools--remap-source-input record)
                 :source)
                source)))
            (with-temp-buffer
              (should-not
               (plist-get
                (emacsvox-aural-tools--remap-source-input record)
                :source)))
            (let (choices)
              (cl-letf
                  (((symbol-function 'completing-read)
                    (lambda (_prompt collection &rest _)
                      (setq choices collection)
                      "always (personal)")))
                (should
                 (eq
                  (emacsvox-aural-tools--voice-remap-scope nil)
                  'personal)))
              (should-not (member "this buffer" choices))))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-tools-recent-feedback-reports-empty-history ()
  "Opening recent feedback explains when no record is retained."
  (emacsvox-test--with-aural-tools
    (should-error
     (emacsvox-aural-list-recent-feedback)
     :type 'user-error)))

(ert-deftest emacsvox-aural-tools-explain-and-preview-visual-faces ()
  "Point diagnosis and preview preserve ordered face compatibility context."
  (emacsvox-test--with-aural-tools
    (with-temp-buffer
      (insert
       (propertize
        "warning" 'face '(font-lock-warning-face bold)))
      (goto-char (point-min))
      (let ((context (emacsvox-aural-context-at-point)))
        (should
         (equal
          (plist-get context :legacy-faces)
          '(font-lock-warning-face bold)))
        (should
         (eq (plist-get context :legacy-face-source) 'face))
        (should
         (equal
          (mapcar
           (lambda (entry)
             (list
              (plist-get entry :face)
              (plist-get entry :source)
              (plist-get entry :property)))
           (plist-get context :legacy-face-provenance))
          '((font-lock-warning-face text-property face)
            (bold text-property face))))))
    (let* ((rule
            (emacsvox-aural-compile-rule
             '(:id warning-face
               :match (:legacy-face font-lock-warning-face)
               :render (:content (:voice bolden)))
             'user))
           (selector (emacsvox-aural-rule-selector rule))
           (input (emacsvox-aural-tools--representative-input rule)))
      (should
       (equal
        (emacsvox-aural-describe-selector selector)
        "visual face font lock warning face"))
      (should
       (equal
        (plist-get (cadr input) :legacy-faces)
        '(font-lock-warning-face)))
      (should
       (string-match-p
        "visual face font lock warning face"
        (emacsvox-aural-concise-explanation nil (cadr input)))))))

(ert-deftest emacsvox-aural-tools-point-and-speech-face-capture-agree ()
  "Point diagnosis uses the authoritative source snapshot used by speech."
  (emacsvox-test--with-aural-tools
    (with-temp-buffer
      (insert
       (propertize
        "styled" 'font-lock-face "font-lock-keyword-face"))
      (let ((overlay (make-overlay (point-min) (point-max))))
        (overlay-put overlay 'priority 4)
        (overlay-put overlay 'face 'font-lock-warning-face)
        (goto-char (point-min))
        (let* ((snapshot (emacsvox-aural-capture-source-faces))
               (context (emacsvox-aural-context-at-point))
               (source
                (emacsvox-aural-source-substring
                 (point-min) (point-max))))
          (should
           (equal
            (plist-get context :legacy-face-provenance)
            snapshot))
          (should
           (equal
            (get-text-property
             0 emacsvox-aural-source-faces-property source)
            snapshot))
          (should
           (equal
            (plist-get context :legacy-faces)
            '(font-lock-warning-face font-lock-keyword-face))))))))

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

(ert-deftest emacsvox-aural-tools-validation-reports-semantic-diagnostics ()
  "Validation exposes deprecated aliases and fallback-shadow relationships."
  (let ((emacsvox-aural-semantic-registry
         (copy-hash-table emacsvox-aural-semantic-registry))
        (emacsvox-aural-semantic-alias-registry
         (copy-hash-table emacsvox-aural-semantic-alias-registry)))
    (emacsvox-aural-register-semantic
     'tools-general-event
     :kind 'event
     :summary "General event")
    (emacsvox-aural-register-semantic
     'tools-specific-event
     :kind 'event
     :summary "Specific event"
     :fallback 'tools-general-event)
    (emacsvox-aural-validate-registry)
    (emacsvox-test--with-aural-tools
      (emacsvox-test--register-tools-scheme
       'semantic-diagnostics
       '((:id general-event
          :match (:event tools-general-event)
          :render (:content (:voice bolden)))
         (:id specific-event
          :match (:event tools-specific-event)
          :render (:content (:voice lighten)))
         (:id deprecated-state
          :match (:role heading :state collapsed)
          :render (:content (:voice smoothen)))))
      (let* ((report
              (emacsvox-aural-validate-scheme
               'semantic-diagnostics))
             (diagnostics
              (emacsvox-aural-validation-report-semantic-diagnostics
               report)))
        (should (emacsvox-aural-validation-report-valid report))
        (should
         (cl-find
          'deprecated-alias diagnostics
          :key (lambda (entry) (plist-get entry :kind))))
        (should
         (cl-find
          'fallback-shadow diagnostics
          :key (lambda (entry) (plist-get entry :kind))))
        (should
         (cl-some
          (lambda (warning)
            (string-match-p "deprecated" warning))
          (emacsvox-aural-validation-report-warnings report)))))))

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

(ert-deftest emacsvox-aural-tools-explains-exact-queued-presentation ()
  "Heard output remains explainable after active configuration changes."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme
     'heard-scheme
     '((:id heard-rule
        :match (:role heading)
        :render
        (:before
         ((:id heard-label :kind speech :text "Heard heading"))))))
    (with-temp-buffer
      (rename-buffer "aural-explanation-source" t)
      (let* ((facts '(:role heading :content "Title"))
             (context (emacsvox-aural-capture-context nil 'navigation))
             (render (emacsvox-aural-resolve-active facts context))
             (concrete (emacsvox-aural-compile-plan render facts context)))
        (cl-letf
            (((symbol-function 'tts-voice-reset-code)
              (lambda () "RESET"))
             ((symbol-function 'tts--protocol-queue-code) #'ignore)
             ((symbol-function 'tts--protocol-queue-text) #'ignore))
          (emacsvox-aural-queue-concrete-plan concrete "Title"))
        (let ((record (emacsvox-aural-last-presentation (current-buffer))))
          (should
           (equal
            (emacsvox-aural-tools--interactive-explanation-input nil)
            (list nil nil record)))
          (emacsvox-aural-register-scheme
           '(:schema-version 1
             :id current-scheme
             :summary "Changed after queueing"
             :parent default
             :rules
             ((:id current-rule
               :match (:role heading)
               :render
               (:before
                ((:id current-label :kind speech
                  :text "Current heading")))))))
          (emacsvox-aural-select-scheme 'current-scheme)
          (let* ((exact (emacsvox-aural-explain-record record))
                 (simulation (emacsvox-aural-explain facts context))
                 (spoken
                  (emacsvox-aural-tools--spoken-explanation exact)))
            (should
             (eq
              (emacsvox-aural-explanation-basis exact)
              'exact-queued))
            (should
             (eq
              (emacsvox-aural-explanation-scheme exact)
              'heard-scheme))
            (should
             (equal
              (mapcar
               (lambda (entry) (plist-get entry :id))
               (emacsvox-aural-explanation-matching-rules exact))
              '(heard-rule)))
            (should
             (equal
              (emacsvox-aural-concrete-action-text
               (car
                (emacsvox-aural-concrete-plan-before
                 (emacsvox-aural-explanation-concrete-plan exact))))
              "Heard heading"))
            (should
             (eq
              (emacsvox-aural-explanation-basis simulation)
              'simulation))
            (should
             (equal
              (mapcar
               (lambda (entry) (plist-get entry :id))
               (emacsvox-aural-explanation-matching-rules simulation))
              '(current-rule)))
            (should
             (string-match-p "Exact queued presentation" spoken))
            (unwind-protect
                (save-window-excursion
                  (emacsvox-aural-tools--display-explanation exact)
                  (with-current-buffer "*Help*"
                    (should
                     (string-match-p
                      "Basis: exact queued presentation"
                      (buffer-string)))))
              (when (get-buffer "*Help*")
                (kill-buffer "*Help*")))))))))

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
              :occasion continuous
              :face-presentation-enabled nil
              :voice-lock-enabled nil))
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
        "available for navigation, 1 rule" summary))
      (should
       (string-match-p
        "Visual face scheme presentation is disabled" summary))
      (should
       (string-match-p
        "Voice Lock is disabled" summary)))))

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
           ((symbol-function 'emacsvox-aural-preview-stop) #'ignore)
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
          (((symbol-function 'emacsvox-aural-compile-voice)
            (lambda (voice)
              (should (eq voice 'annotate))
              "TRAINING"))
           ((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code)
            (lambda (code) (push (list 'code code) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push (list 'text text) events))))
        (unwind-protect
            (progn
              (emacsvox-aural-training-mode 1)
              (emacsvox-aural-queue-concrete-plan plan))
          (emacsvox-aural-training-mode -1)))
      (let ((ordered (nreverse events)))
        (should
         (equal
          (last ordered 4)
          '((code "RESET")
            (code "TRAINING")
            (text "heading, level 1, inspection occasion.")
            (code "RESET"))))))))

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
           ((symbol-function 'emacsvox-aural-compile-voice)
            (lambda (voice)
              (should (eq voice 'annotate))
              "TRAINING"))
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
          (code "TRAINING")
          (text
           "product identity, earcon emacsvox, notification occasion.")
          (code "RESET")
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
                '(explain remap remap-earcon overrides recent-feedback profiles
                  schemes voices features face-presentation buffer-rules
                  semantics sounds spatial spatial-settings training
                  diagnostics)))
              (dolist
                  (binding
                   '(("RET" . emacsvox-aural-home-activate)
                     ("x" . emacsvox-aural-home-explain)
                     ("r" . emacsvox-aural-home-remap-voice)
                     ("R" . emacsvox-aural-home-remap-earcon)
                     ("O" . emacsvox-aural-home-overrides)
                     ("H" . emacsvox-aural-home-recent-feedback)
                     ("V" . emacsvox-aural-home-voice-palettes)
                     ("v" . emacsvox-aural-home-toggle-face-presentation)
                     ("?" . emacsvox-aural-home-help)))
                (should
                 (eq
                  (lookup-key
                   emacsvox-aural-home-mode-map
                   (kbd (car binding)))
                  (cdr binding))))
              (dolist
                  (binding
                   '(("SPC" . emacsvox-aural-ui-speak-current-row)
                     ("." . emacsvox-aural-ui-speak-current-cell)
                     ("n" . emacsvox-aural-ui-next-row)
                     ("C-n" . emacsvox-aural-ui-next-row)
                     ("<down>" . emacsvox-aural-ui-next-row)
                     ("p" . emacsvox-aural-ui-previous-row)
                     ("C-p" . emacsvox-aural-ui-previous-row)
                     ("<up>" . emacsvox-aural-ui-previous-row)
                     ("<right>" . emacsvox-aural-ui-next-column)
                     ("<left>" . emacsvox-aural-ui-previous-column)
                     ("g" . emacsvox-aural-ui-refresh)
                     ("q" . emacsvox-aural-quit)))
                (should
                 (eq
                  (key-binding (kbd (car binding)))
                  (cdr binding))))
              (let (spoken)
                (with-current-buffer "*Emacsvox Aural*"
                  (cl-letf (((symbol-function 'tts-speak)
                             (lambda (text) (setq spoken text))))
                    (emacsvox-aural-home--goto 'face-presentation)
                    (emacsvox-aural-home-toggle-face-presentation)
                    (should-not
                     emacsvox-aural-face-presentation-enabled)
                    (should
                     (string-match-p
                      "Visual face presentation.*off"
                      spoken))))))
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
                (should (equal spoken "Remap voice at point, Area"))
                (emacsvox-aural-home-next)
                (should (equal spoken "Remap earcon at point, Area"))
                (emacsvox-aural-home-next)
                (should (equal spoken "Presentation overrides, Area"))
                (emacsvox-aural-home-next)
                (should (equal spoken "Recent aural feedback, Area"))
                (emacsvox-aural-home-next)
                (should (equal spoken "Presentation profiles, Area"))
                (emacsvox-aural-home-next-column)
                (should
                 (string-prefix-p "Current status, " spoken))
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
        emacsvox-aural-overrides-mode-map
        emacsvox-aural-recent-feedback-mode-map
        emacsvox-aural-voice-palettes-mode-map
        emacsvox-aural-voice-palette-previews-mode-map
        emacsvox-aural-voice-tuner-mode-map
        emacsvox-aural-scheme-editor-mode-map
        emacsvox-aural-simple-editor-mode-map))
    (should
     (eq (lookup-key map (kbd "h")) #'emacsvox-aural))))

(ert-deftest emacsvox-aural-interfaces-provide-dismissal ()
  "Aural managers use shared exit feedback and editors retain confirmation."
  (dolist
      (mode
       '(emacsvox-aural-home-mode
         emacsvox-aural-semantics-mode
         emacsvox-aural-schemes-mode
         emacsvox-aural-feature-fragments-mode
         emacsvox-aural-overrides-mode
         emacsvox-aural-recent-feedback-mode
         emacsvox-aural-voice-palettes-mode
         emacsvox-aural-voice-palette-previews-mode))
    (with-temp-buffer
      (funcall mode)
      (should
       (eq (key-binding (kbd "q")) #'emacsvox-aural-quit))))
  (dolist
      (map
       (list
        emacsvox-aural-scheme-editor-mode-map
        emacsvox-aural-simple-editor-mode-map))
    (should
     (eq
      (lookup-key map (kbd "q"))
      #'emacsvox-aural-editor-quit)))
  (should
   (eq
    (lookup-key emacsvox-aural-voice-tuner-mode-map (kbd "q"))
    #'emacsvox-aural-voice-tuner-quit)))

(ert-deftest emacsvox-aural-quit-presents-mode-scoped-close-feedback ()
  "Dismissing an aural interface cues its close and speaks the destination."
  (let (events)
    (with-temp-buffer
      (emacsvox-aural-feature-fragments-mode)
      (cl-letf
          (((symbol-function 'quit-window)
            (lambda (&optional kill)
              (push (list 'quit kill) events)
              'dismissed))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (push
               (list
                'icon icon emacsvox-aural-submission-facts
                (plist-get emacsvox-aural-submission-context :module)
                emacsvox-aural-submission-occasion)
               events)))
           ((symbol-function 'emacsvox-speak-mode-line)
            (lambda () (push 'mode-line events))))
        (should (eq (emacsvox-aural-quit) 'dismissed))))
    (should
     (equal
      (nreverse events)
      '((quit nil)
        (icon close-object
         (:role aural-interface :events (aural-interface-closed))
         aural-tools state-change)
        mode-line)))))

(ert-deftest emacsvox-aural-editor-quit-confirms-before-shared-dismissal ()
  "Dirty editors still confirm before using shared aural exit feedback."
  (let ((emacsvox-aural-editor-dirty t)
        calls)
    (cl-letf
        (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
         ((symbol-function 'emacsvox-aural-quit)
          (lambda (&optional kill) (push kill calls))))
      (emacsvox-aural-editor-quit)
      (should-not calls)
      (setq emacsvox-aural-editor-dirty nil)
      (emacsvox-aural-editor-quit)
      (should (equal calls '(t))))))

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
          (should (equal (aref row 5) "1 direct, 1 total"))
          (should (equal (aref row 7) "you (personal)")))
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
               ("P" . emacsvox-preview-aural-scheme)
               ("v" . emacsvox-validate-aural-scheme)
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
     :built-in t :source "test" :collection 'org)
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
              (should (equal (aref built-in 2) "built-in"))
              (should
               (assoc
                (cons 'collection 'org)
                tabulated-list-entries))
              (should
               (assoc
                (cons 'collection 'personal)
                tabulated-list-entries)))
            (dolist
                (binding
                 '(("RET" . emacsvox-aural-feature-fragments-activate)
                   ("TAB"
                    . emacsvox-aural-feature-fragments-toggle-collection)
                   ("a" . emacsvox-aural-feature-fragments-toggle-view)
                   ("P" . emacsvox-aural-feature-fragments-preview)
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
                (cdr binding)))))
            (dolist (key '("n" "C-n" "<down>"))
              (should
               (eq
                (key-binding (kbd key))
                #'emacsvox-aural-ui-next-row)))
            (dolist (key '("p" "C-p" "<up>"))
              (should
               (eq
                (key-binding (kbd key))
                #'emacsvox-aural-ui-previous-row))))
      (when (get-buffer "*Aural Feature Fragments*")
        (kill-buffer "*Aural Feature Fragments*")))))

(ert-deftest emacsvox-aural-fragment-manager-navigation-speaks-edges ()
  "Fragment movement speaks value-first cells and boundaries without repeats."
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
                 (equal spoken "General, Option"))
                (emacsvox-aural-feature-fragments-previous)
                (should
                 (equal spoken "Top of presentation option list."))
                (emacsvox-aural-feature-fragments-next)
                (should
                 (equal spoken "first fragment, Option"))
                (emacsvox-aural-feature-fragments-next)
                (should
                 (equal spoken "second fragment, Option"))
                (emacsvox-aural-feature-fragments-next)
                (should
                 (equal spoken "Bottom of presentation option list."))
                (emacsvox-aural-feature-fragments-next-column)
                (should (equal spoken "Status, enabled 2"))))))
      (when (get-buffer "*Aural Feature Fragments*")
        (kill-buffer "*Aural Feature Fragments*")))))

(ert-deftest emacsvox-aural-fragment-toggle-preserves-stable-order ()
  "Disabling and re-enabling an option must not alter its precedence."
  (emacsvox-test--with-aural-tools
    (dolist (id '(notmuch-status notmuch-attachments))
      (emacsvox-aural-register-feature-fragment
       (list
        :schema-version 1
        :id id
        :summary (symbol-name id)
        :rules nil)
       :built-in t :source "test" :collection 'notmuch))
    (emacsvox-aural-set-enabled-feature-fragments
     '(notmuch-status notmuch-attachments))
    (cl-letf
        (((symbol-function 'emacsvox-aural-save-user-data) #'ignore))
      (emacsvox-aural-feature-fragments-toggle 'notmuch-status)
      (should
       (equal
        emacsvox-aural-enabled-feature-fragments
        '(notmuch-attachments)))
      (emacsvox-aural-feature-fragments-toggle 'notmuch-status))
    (should
     (equal
      emacsvox-aural-enabled-feature-fragments
      '(notmuch-status notmuch-attachments)))
    (should
     (equal
      emacsvox-aural-feature-fragment-order
      '(notmuch-status notmuch-attachments)))))

(ert-deftest emacsvox-aural-fragment-manager-groups-and-collapses-options ()
  "Collections are spoken, collapsible, and separate from active precedence."
  (emacsvox-test--with-aural-tools
    (dolist
        (definition
         '((org-levels org)
           (org-cues org)
           (personal-headings personal)))
      (emacsvox-aural-register-feature-fragment
       (list
        :schema-version 1
        :id (car definition)
        :summary (symbol-name (car definition))
        :rules nil)
       :built-in (not (eq (cadr definition) 'personal))
       :source "test"
       :collection (cadr definition)))
    (emacsvox-aural-set-enabled-feature-fragments
     '(org-levels personal-headings))
    (unwind-protect
        (save-window-excursion
          (emacsvox-aural-list-feature-fragments)
          (with-current-buffer "*Aural Feature Fragments*"
            (should
             (emacsvox-aural-feature-fragments--goto
              (cons 'collection 'org)))
            (let (spoken)
              (cl-letf
                  (((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text))))
                (emacsvox-aural-feature-fragments-toggle-collection))
              (should
               (equal
                spoken
                "org collection. 1 of 2 options enabled. Collapsed.")))
            (should-not (assq 'org-levels tabulated-list-entries))
            (cl-letf (((symbol-function 'tts-speak) #'ignore))
              (emacsvox-aural-feature-fragments-toggle-collection))
            (should (assq 'org-levels tabulated-list-entries))
            (emacsvox-aural-feature-fragments--goto 'org-levels)
            (cl-letf (((symbol-function 'tts-speak) #'ignore))
              (emacsvox-aural-feature-fragments-toggle-view))
            (should (eq emacsvox-aural-feature-fragments-view 'active))
            (should
             (equal
              (mapcar #'car tabulated-list-entries)
              '(org-levels personal-headings)))))
      (when (get-buffer "*Aural Feature Fragments*")
        (kill-buffer "*Aural Feature Fragments*")))))

(ert-deftest emacsvox-aural-fragment-preview-completes-curated-examples ()
  "Curated examples take precedence and uncovered rules derive simulations."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-feature-fragment
     '(:schema-version 1
       :id heading-levels
       :summary "Heading levels"
       :rules
       ((:id level-one-rule
         :match (:role heading :level 1 :occasion navigation)
         :render
         (:before
          ((:id level-one-label :kind speech :text "Level one"))))
        (:id level-two-rule
         :match (:role heading :level 2 :occasion navigation)
         :render
         (:before
          ((:id level-two-label :kind speech :text "Level two"))))))
     :built-in t :collection 'org)
    (emacsvox-aural-register-feature-fragment-example
     'heading-levels 'org-level-one
     :rule 'level-one-rule
     :summary "Level one Org heading"
     :facts '(:role heading :level 1 :content "Project roadmap")
     :context
     '(:module org :mode org-mode :occasion navigation)
     :source "test")
    (let ((examples
           (emacsvox-aural-tools--fragment-preview-examples 'heading-levels)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-feature-fragment-example-id examples)
        '(org-level-one automatic-level-two-rule)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-feature-fragment-example-source examples)
        '("test" automatic))))
    (let ((tts-speaker-process 'speaker)
          queued
          result)
      (cl-letf
          (((symbol-function 'process-live-p) (lambda (_) t))
           ((symbol-function 'emacsvox-aural-preview-stop) #'ignore)
           ((symbol-function 'emacsvox-aural-queue-concrete-plan)
            (lambda (plan &rest _) (setq queued plan)))
           ((symbol-function 'tts--protocol-dispatch) #'ignore))
        (setq
         result
         (emacsvox-aural-feature-fragments-preview
          nil 'heading-levels 'org-level-one)))
      (should (eq (plist-get result :kind) 'simulated))
      (should (eq (plist-get result :example) 'org-level-one))
      (should (eq (plist-get result :concrete) queued))
      (should
       (equal
        (emacsvox-aural-concrete-action-text
         (car (emacsvox-aural-concrete-plan-before queued)))
        "Level one"))
      (should-not emacsvox-aural-enabled-feature-fragments))))

(defun emacsvox-test--register-multiple-fragment-previews ()
  "Register a two-example presentation option for preview tests."
  (emacsvox-aural-register-feature-fragment
   '(:schema-version 1
     :id heading-earcons
     :summary "Heading earcons"
     :rules
     ((:id level-one-earcon
       :match (:role heading :level 1 :occasion navigation)
       :render
       (:before
        ((:id level-one-item :kind cue :cue item))))
      (:id level-two-earcon
       :match (:role heading :level 2 :occasion navigation)
       :render
       (:before
        ((:id level-two-section :kind cue :cue section))))))
   :built-in t :collection 'org)
  (emacsvox-aural-register-feature-fragment-example
   'heading-earcons 'level-one
   :rule 'level-one-earcon
   :summary "Level one heading"
   :facts '(:role heading :level 1 :content "Roadmap")
   :context '(:module org :mode org-mode :occasion navigation)
   :source "test")
  (emacsvox-aural-register-feature-fragment-example
   'heading-earcons 'level-two
   :rule 'level-two-earcon
   :summary "Level two heading"
   :facts '(:role heading :level 2 :content "Milestones")
   :context '(:module org :mode org-mode :occasion navigation)
   :source "test"))

(ert-deftest emacsvox-aural-fragment-preview-opens-multiple-example-browser ()
  "Interactive preview uses a persistent browser for multiple examples."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-multiple-fragment-previews)
    (let ((tts-speaker-process 'speaker)
          queued
          spoken
          (stops 0))
      (unwind-protect
          (save-window-excursion
            (emacsvox-aural-list-feature-fragments)
            (with-current-buffer "*Aural Feature Fragments*"
              (should
               (emacsvox-aural-feature-fragments--goto
                'heading-earcons))
              (cl-letf
                  (((symbol-function 'completing-read)
                    (lambda (&rest _)
                      (ert-fail
                       "Multiple examples must not reopen completion")))
                   ((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text)))
                   ((symbol-function 'called-interactively-p)
                    (lambda (&rest _) t))
                   ((symbol-function 'emacsvox-icon) #'ignore))
                (call-interactively
                 #'emacsvox-aural-feature-fragments-preview)))
            (with-current-buffer "*Aural Option Preview*"
              (should
               (derived-mode-p
                'emacsvox-aural-feature-fragment-previews-mode))
              (should
               (eq
                emacsvox-aural-feature-fragment-previews-fragment
                'heading-earcons))
              (should (= (length tabulated-list-entries) 2))
              (should (eq (tabulated-list-get-id) 'level-one))
              (should
               (eq
                (key-binding (kbd "<down>"))
                #'emacsvox-aural-ui-next-row))
              (should (string-match-p "Level one heading" spoken))
              (cl-letf
                  (((symbol-function 'tts-speak) #'ignore)
                   ((symbol-function 'emacsvox-icon) #'ignore))
                (emacsvox-aural-feature-fragment-previews-next))
              (should (eq (tabulated-list-get-id) 'level-two))
              (should
               (eq
                (gethash
                 'heading-earcons
                 emacsvox-aural-tools--fragment-preview-last-examples)
                'level-two))
              (setq spoken nil)
              (cl-letf
                  (((symbol-function 'process-live-p) (lambda (_) t))
                   ((symbol-function 'tts-stop)
                    (lambda () (cl-incf stops)))
                   ((symbol-function 'tts-speak)
                    (lambda (text) (setq spoken text)))
                   ((symbol-function 'emacsvox-aural-queue-concrete-plan)
                    (lambda (plan &rest _) (setq queued plan)))
                   ((symbol-function 'tts--protocol-dispatch) #'ignore))
                (emacsvox-aural-feature-fragment-previews-play))
              (should (= stops 1))
              (should queued)
              (should-not spoken)))
        (dolist
            (buffer
             '("*Aural Option Preview*" "*Aural Feature Fragments*"))
          (when (get-buffer buffer)
            (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-fragment-preview-cue-audition-is-speech-free ()
  "Cue-only audition bypasses content, training, and presentation history."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-multiple-fragment-previews)
    (let* ((example
            (emacsvox-aural-feature-fragment-example
             'heading-earcons 'level-one))
           (tts-speaker-process 'speaker)
           (emacsvox-aural-plan-presented-hook
            (list
             (lambda (_plan)
               (ert-fail "Cue audition must not run training hooks"))))
           played
           (stops 0))
      (cl-letf
          (((symbol-function 'process-live-p) (lambda (_) t))
           ((symbol-function 'tts-stop)
            (lambda () (cl-incf stops)))
           ((symbol-function 'tts-speak)
            (lambda (&rest _)
              (ert-fail "Cue audition must not speak")))
           ((symbol-function 'emacsvox-aural-queue-concrete-plan)
            (lambda (&rest _)
              (ert-fail "Cue audition must not queue a presentation")))
           ((symbol-function 'emacsvox-sounds-play-concrete-cue)
            (lambda (resource sample-id &optional balance)
              (push (list resource sample-id balance) played))))
        (let ((result
               (emacsvox-aural-tools--audition-fragment-preview-cues
                'heading-earcons example nil)))
          (should (= stops 1))
          (should (= (length played) 1))
          (should
           (string-suffix-p "/item.ogg" (caar played)))
          (should
           (eq
            (emacsvox-aural-concrete-action-cue
             (car (plist-get result :cues)))
            'item))
          (should-not emacsvox-aural-presentation-history))))))

(ert-deftest emacsvox-aural-fragment-preview-status-message-is-silent ()
  "Preview status remains visible without entering message speech."
  (let ((emacsvox-speak-messages t)
        observed)
    (cl-letf
        (((symbol-function 'message)
          (lambda (&rest _)
            (setq observed emacsvox-speak-messages))))
      (emacsvox-aural-tools--preview-message "Preview status"))
    (should-not observed)))

(ert-deftest emacsvox-aural-fragment-preview-prefers-live-source-context ()
  "Matching source facts and mode take precedence over simulated examples."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-feature-fragment
     '(:schema-version 1
       :id org-level
       :summary "Org level"
       :rules
       ((:id org-level-rule
         :match
         (:role heading :module org :occasion navigation :requires (level))
         :render
         (:before
          ((:id org-level-label :kind speech
            :text-template "Heading {level}"))))))
     :built-in t :collection 'org)
    (let ((source (generate-new-buffer " *aural-preview-source*"))
          (tts-speaker-process 'speaker)
          queued)
      (unwind-protect
          (progn
            (with-current-buffer source
              (insert "Roadmap")
              (add-text-properties
               (point-min) (point-max)
               (list
                emacsvox-aural-facts-property
                '(:role heading :level 2)))
              (setq major-mode 'org-mode)
              (setq-local emacsvox-aural-module 'org)
              (goto-char (point-min)))
            (setq emacsvox-aural-tools--last-source-buffer source)
            (cl-letf
                (((symbol-function 'process-live-p) (lambda (_) t))
                 ((symbol-function 'emacsvox-aural-preview-stop) #'ignore)
                 ((symbol-function 'emacsvox-aural-queue-concrete-plan)
                  (lambda (plan &rest _) (setq queued plan)))
                 ((symbol-function 'tts--protocol-dispatch) #'ignore))
              (let ((result
                     (emacsvox-aural-feature-fragments-preview
                      nil 'org-level)))
                (should (eq (plist-get result :kind) 'live))
                (should-not (plist-get result :example))
                (should
                 (equal
                  (plist-get
                   (emacsvox-aural-concrete-plan-facts queued)
                   :content)
                  "Roadmap"))
                (should
                 (eq
                  (plist-get
                   (emacsvox-aural-concrete-plan-context queued)
                   :occasion)
                  'navigation)))))
        (kill-buffer source)))))

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
                (setq emacsvox-aural-feature-fragments-view 'active)
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
           (emacsvox-aural-scheme-manager--spoken-summary
            'spoken-personal)))
      (should (string-match-p "spoken personal" summary))
      (should (string-match-p "Active personal scheme" summary))
      (should (string-match-p "Provided by you (personal)" summary))
      (should (string-match-p "Based on default" summary))
      (should (string-match-p "Sound pack chimes" summary))
      (should (string-match-p "1 effective presentation" summary))
      (should (string-match-p "Valid" summary)))))

(ert-deftest emacsvox-aural-scheme-manager-identifies-integration-provider ()
  "Built-in schemes identify the integration that registered them."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id org-example
       :summary "Org example"
       :parent default
       :rules ())
     :built-in t
     :source "emacsvox-aural-provider-org")
    (let* ((entry (emacsvox-aural-scheme-entry 'org-example))
           (row
            (cadr
             (emacsvox-aural-scheme-manager--scheme-row
              "org-example"))))
      (should
       (equal
        (emacsvox-aural-scheme-manager--scheme-provider entry)
        "Org integration"))
      (should (equal (aref row 7) "Org integration")))))

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
                (should (equal spoken "second, Scheme"))
                (emacsvox-aural-schemes-next)
                (should (eq (tabulated-list-get-id) 'second))
                (should (equal spoken "Bottom of scheme list."))
                (emacsvox-aural-schemes-previous)
                (should (eq (tabulated-list-get-id) 'default))
                (should (equal spoken "default, Scheme"))))))
      (when (get-buffer "*Aural Schemes*")
        (kill-buffer "*Aural Schemes*")))))

(ert-deftest emacsvox-aural-semantic-list-navigation-speaks-titles-and-edges ()
  "Semantic movement uses direction-aware order and announces boundaries."
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
                  (format "%s, Identifier" second)))
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
           'emacsvox-aural-scheme-manager--scheme-at-point-or-read)
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
  "Failed manager persistence publishes no registry or cache generation."
  (emacsvox-test--with-aural-tools
    (emacsvox-aural-register-scheme
     '(:schema-version 1 :id personal :summary "Personal"
       :parent default :rules ())
     :source "test")
    (let ((registry emacsvox-aural-scheme-registry)
          (generation emacsvox-aural-configuration-generation)
          notifications
          staged-registries)
      (add-hook
       'emacsvox-aural-configuration-changed-hook
       (lambda (&rest event) (push event notifications)))
      (cl-letf
          (((symbol-function 'emacsvox-aural-save-user-data)
            (lambda (&rest _)
              (push emacsvox-aural-scheme-registry staged-registries)
              (error "save failed"))))
        (should-error
         (emacsvox-copy-aural-scheme 'personal 'copied)
         :type 'error)
        (should-error
         (emacsvox-delete-aural-scheme 'personal)
         :type 'error)
        (should-error
         (emacsvox-rename-aural-scheme 'personal 'renamed)
         :type 'error))
      (should (= (length staged-registries) 3))
      (should
       (cl-every
        (lambda (staged) (not (eq staged registry)))
        staged-registries))
      (should (eq emacsvox-aural-scheme-registry registry))
      (should (= emacsvox-aural-configuration-generation generation))
      (should-not notifications)
      (should (emacsvox-aural-scheme-entry 'personal))
      (should-not (emacsvox-aural-scheme-entry 'copied))
      (should-not (emacsvox-aural-scheme-entry 'renamed)))))

(ert-deftest emacsvox-aural-editor-scheme-save-failure-is-transactional ()
  "Failed editor persistence leaves the live scheme and caches unchanged."
  (emacsvox-test--with-aural-tools
    (let ((data
           '(:schema-version 1
             :id personal
             :summary "Personal scheme"
             :parent default
             :rules
             ((:id original
               :match (:role heading)
               :render (:content (:voice bolden)))))))
      (emacsvox-aural-register-scheme data :source "test")
      (let ((registry emacsvox-aural-scheme-registry)
            (entry (emacsvox-aural-scheme-entry 'personal))
            (generation emacsvox-aural-configuration-generation)
            notifications
            staged-registry)
        (add-hook
         'emacsvox-aural-configuration-changed-hook
         (lambda (&rest event) (push event notifications)))
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
           (plist-get (car emacsvox-aural-editor-rules) :enabled)
           nil)
          (cl-letf
              (((symbol-function 'emacsvox-aural-save-user-data)
                (lambda (&rest _)
                  (setq
                   staged-registry emacsvox-aural-scheme-registry)
                  (error "save failed"))))
            (should-error
             (emacsvox-aural-editor-save)
             :type 'error)))
        (should-not (eq staged-registry registry))
        (should (eq emacsvox-aural-scheme-registry registry))
        (should (eq (emacsvox-aural-scheme-entry 'personal) entry))
        (should (= emacsvox-aural-configuration-generation generation))
        (should-not notifications)
        (should
         (equal
          (emacsvox-aural-scheme-entry-data entry)
          data))))))

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
           ((symbol-function 'emacsvox-aural-preview-stop) #'ignore)
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
           ((string-match-p "Action lifetime" prompt) "inferred")
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

(ert-deftest emacsvox-aural-simple-editor-describes-and-edits-visual-face ()
  "The spoken editor exposes face compatibility as an ordinary condition."
  (should
   (equal
    (emacsvox-aural-simple-editor--match-description
     '(:legacy-face font-lock-warning-face :occasion navigation))
    "visual face font lock warning face; during navigation"))
  (cl-letf
      (((symbol-function 'completing-read)
        (lambda (prompt &rest _)
          (cond
           ((string-match-p "Change which condition" prompt)
            "visual-face")
           ((string-match-p "Visual face" prompt)
            "font-lock-warning-face")
           (t (ert-fail (format "Unexpected prompt %s" prompt)))))))
    (should
     (equal
      (emacsvox-aural-simple-editor--edit-match
       '(:occasion navigation))
      '(:occasion navigation :legacy-face font-lock-warning-face)))))

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

(ert-deftest emacsvox-aural-simple-editor-creates-layered-face-presentation ()
  "The new-presentation wizard can append a cue and select a face voice."
  (emacsvox-test--with-aural-tools
    (emacsvox-test--register-tools-scheme 'face-test nil)
    (with-temp-buffer
      (emacsvox-test--setup-simple-editor 'face-test)
      (cl-letf
          (((symbol-function 'emacsvox-speak-line) #'ignore)
           ((symbol-function 'read-string)
            (lambda (prompt &rest _)
              (if (string-match-p "Presentation name" prompt)
                  "Warning face"
                (ert-fail (format "Unexpected prompt %s" prompt)))))
           ((symbol-function 'completing-read)
            (lambda (prompt &rest _)
              (cond
               ((string-match-p "Presentation target" prompt) "visual face")
               ((string-match-p "Visual face" prompt)
                "font-lock-warning-face")
               ((string-match-p "Module" prompt) "(none)")
               ((string-match-p "Occasion" prompt) "navigation")
               ((string-match-p "Before content feedback" prompt) "play a cue")
               ((string-match-p "Sound cue" prompt) "warn-user")
               ((string-match-p "Feedback position" prompt) "inherit")
               ((string-match-p "Speak the content" prompt) "keep current")
               ((string-match-p "Content voice" prompt) "bolden")
               ((string-match-p "Content position" prompt) "inherit")
               ((string-match-p "After content feedback" prompt)
                "inherit existing feedback")
               (t (ert-fail (format "Unexpected prompt %s" prompt)))))))
        (emacsvox-aural-simple-editor-add-rule))
      (let ((rule (car emacsvox-aural-editor-rules)))
        (should
         (equal
          (plist-get rule :match)
          '(:legacy-face font-lock-warning-face
            :occasion navigation)))
        (should
         (eq
          (plist-get (plist-get (plist-get rule :render) :content) :voice)
          'bolden))
        (should
         (equal
          (plist-get (plist-get (plist-get rule :render) :before) :append)
          '((:id face-test-warning-face-before-cue
             :kind cue :cue warn-user))))))))

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
