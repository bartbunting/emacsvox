;;; emacsvox-aural-voice-workbench-tests.el --- Workbench UI tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify spoken cross-synth inventory and routing views.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-voice-workbench)
(require 'emacsvox-aural-voice-editor)
(require 'emacsvox-omnivox-components)
(require 'omnivox-voices)

(defconst emacsvox-test--workbench-inventory
  '(:adapter "omnivox" :source "live" :status "available"
    :generation 12 :received-at nil :stale nil
    :preferred-engine-id "eloquence" :process-agreement "agree"
    :preferred-engine-order ("eloquence" "winrt")
    :fallback-engine-order ("winrt") :disabled-engine-ids nil
    :preview-support "logical-route" :routing-policy-support "runtime"
    :engines
    ((:engine-id "eloquence" :display-name "Eloquence"
      :availability "available" :health "healthy"
      :circuit "closed" :last-failure nil :cooldown-remaining-ms nil
      :audio-output "buffered_pcm" :marker-support (word native-index)
      :anchor-support "exact/native-index"
      :default-voice-id "eci:Reed" :inventory-kind "live"
      :acss-dimensions (rate average-pitch pitch-range stress richness volume)
      :post-synthesis-dimensions (reverb echo chorus)
      :preview-support "logical-route" :routing-policy-support "logical-voice"
      :capabilities (:markers (:word t :native_index t))
      :voices
      ((:engine-id "eloquence" :voice-id "eci:Reed"
        :display-name "Reed" :language "en-AU" :gender "male"
        :quality "standard" :availability "available")))
     (:engine-id "winrt" :display-name "Windows Speech"
      :availability "available" :health "degraded"
      :circuit "cooldown" :last-failure "helper exited"
      :cooldown-remaining-ms 750 :audio-output "buffered_pcm"
      :marker-support (word sentence) :anchor-support "word-boundary"
      :default-voice-id "David" :inventory-kind "live"
      :acss-dimensions (rate average-pitch volume)
      :post-synthesis-dimensions nil
      :preview-support "logical-route" :routing-policy-support "logical-voice"
      :capabilities (:markers (:word t :sentence t))
      :voices
      ((:engine-id "winrt" :voice-id "David" :display-name "David"
        :language "en-US" :gender "male" :quality "standard"
        :availability "available")))))
  "Representative normalized Workbench inventory.")

(defconst emacsvox-test--workbench-routing-profile
  '(:schema-version 2 :id workstation :summary "Workbench profile" :engine-order ("eloquence" "winrt") :disabled-engines nil :fallback (:allow-same-language t :global-default nil :engines ("winrt")))
  "Representative staged Workbench route.")

(defmacro emacsvox-test--with-voice-workbench (&rest body)
  "Run BODY in an isolated Voice Workbench buffer."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-voice-palette-registry (copy-hash-table emacsvox-aural-voice-palette-registry))
         (emacsvox-aural-voice-palette-override 'workbench-test)
         (emacsvox-aural-routing--choice-sets
          '((:schema-version 3 :id "workbench-bolden" :palette workbench-test :voice bolden
             :choices ((:id "reed" :selector (:kind exact :scope local :engine-id "eloquence"
                                                       :voice-id "eci:Reed") :adjustments nil)))))
         (emacsvox-aural-routing-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-active-routing-profile 'workstation)
         (emacsvox-aural-session-engine-order nil)
         (emacsvox-aural-routing-profile-changed-hook nil)
         (emacsvox-aural-routing-apply-status nil)
         (emacsvox-aural-routing-apply-status-hook nil)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-engine-priority-ids nil)
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-disabled-engine-ids nil)
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t)
         (tts-voice-inventory-function
          (lambda () (copy-tree emacsvox-test--workbench-inventory)))
         (tts-voice-capabilities-function
          (lambda ()
            '(:adapter omnivox :source discovered
              :family-selection routed
              :dimensions (average-pitch pitch-range stress richness volume))))
         (tts-voice-configuration-apply-function
          #'tts-default-apply-voice-configuration)
         (tts-last-realized-voice-function
          #'tts-default-last-realized-voice)
         (emacsvox-aural-ui-source-buffer nil))
     (emacsvox-aural-register-voice-palette-data
      '(:schema-version 3 :id workbench-test :summary "Workbench voices" :parent acss-default
        :routing owned :entries ((bolden :personality voice-bolden :choices nil
                                         :language "en-AU" :local-choices "workbench-bolden"))))
     (emacsvox-aural-register-routing-profile-data
      emacsvox-test--workbench-routing-profile "test")
     (with-temp-buffer
       (cl-letf (((symbol-function 'tts-speak) #'ignore))
         (emacsvox-aural-voice-workbench-mode)
         (emacsvox-aural-voice-workbench-refresh)
         ,@body))))

(defun emacsvox-test--expand-voice-languages ()
  "Open collapsed headings using the browser's actual Return action."
  (dolist (row (copy-sequence tabulated-list-entries))
    (when (and (emacsvox-aural-voice-workbench--language-row-p (car row))
               (string-suffix-p "collapsed" (aref (cadr row) 1)))
      (emacsvox-aural-ui-goto-row (car row))
      (call-interactively (key-binding (kbd "RET"))))))

(ert-deftest emacsvox-aural-voice-workbench-timeout-reports-unconfirmed-outcome ()
  "Timeout feedback preserves partial success and offers a retry without claiming rollback."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-routing-apply-status
          '(:profile-id workstation :status partial
            :processes ((:role speaker :status applied)
                        (:role notification :status failed :phase timeout))))
    (let (spoken)
      (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--announce)
                 (lambda (format-string &rest arguments)
                   (setq spoken (apply #'format format-string arguments)))))
        (emacsvox-aural-voice-workbench--apply-complete
         (current-buffer) emacsvox-aural-routing-apply-status))
      (should (string-match-p "partial 1/2; timed out; server outcome unconfirmed"
                              (emacsvox-aural-voice-workbench--apply-status-description)))
      (should (string-match-p "notification timed out; server outcome unconfirmed"
                              (emacsvox-aural-voice-workbench--registration-description
                               'voice-bolden)))
      (should (string-match-p "partial; timed out; server outcome unconfirmed" spoken))
      (should (string-match-p "Press r to reapply" spoken)))))

(ert-deftest emacsvox-aural-voice-workbench-lists-only-usable-engines ()
  "Quick preference excludes disabled, unavailable, and failed engines."
  (emacsvox-test--with-voice-workbench
    (let ((inventory (copy-tree emacsvox-test--workbench-inventory))
          (profile (copy-tree emacsvox-test--workbench-routing-profile)))
      (setf (plist-get profile :disabled-engines) '("winrt"))
      (setf
       (plist-get inventory :engines)
       (append
        (plist-get inventory :engines)
        '((:engine-id "failed" :display-name "Failed"
           :availability "available" :health "failed" :voices nil)
          (:engine-id "missing" :display-name "Missing"
           :availability "unavailable" :health "unavailable"
           :voices nil))))
      (should
       (equal
        (mapcar
         #'cdr
         (emacsvox-aural-voice-workbench--engine-candidates
          inventory profile))
        '("eloquence"))))))

(ert-deftest emacsvox-aural-voice-workbench-current-actions-separate-voices-and-policy ()
  "Named editing uses the common editor; engine controls remain reachable."
  (emacsvox-test--with-voice-workbench
    (dolist (command '(emacsvox-aural-voice-workbench-assign
                       emacsvox-aural-voice-workbench-copy-route
                       emacsvox-aural-voice-workbench-delete-selector
                       emacsvox-aural-voice-workbench-migrate
                       emacsvox-aural-voice-workbench-apply-preset))
      (should-not (fboundp command)))
    (should (emacsvox-aural-ui-goto-row "bolden"))
    (cl-letf (((symbol-function 'emacsvox-aural-voice-editor-open)
               (lambda (palette voice &rest _)
                 (should (eq palette 'workbench-test)) (should (equal voice "bolden")))))
      (call-interactively (key-binding (kbd "t"))))
    (should-not (emacsvox-aural-voice-workbench--action-applicable-p
                 'emacsvox-aural-voice-workbench-move-preferred-engine-up))
    (emacsvox-aural-voice-workbench-engine-view)
    (dolist (key '("O" "[" "]" "f" "{" "}" "D" "K" "w"))
      (let ((command (key-binding (kbd key))))
        (should (commandp command))
        (should (emacsvox-aural-voice-workbench--action-applicable-p command))))))

(ert-deftest emacsvox-aural-voice-workbench-prefers-engine-for-session ()
  "Quick preference applies live but preserves saved routes and fallback."
  (emacsvox-test--with-voice-workbench
    (let ((saved
           (copy-tree
            (emacsvox-aural-routing-profile-entry-data
             (emacsvox-aural-routing-profile 'workstation))))
          spoken)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox-aural-prefer-engine "winrt"))
      (should
       (equal emacsvox-aural-session-engine-order
              '("winrt" "eloquence")))
      (should
       (equal omnivox-engine-priority-ids
              emacsvox-aural-session-engine-order))
      (should (equal omnivox-fallback-engine-ids '("winrt")))
      (should
       (equal
        (emacsvox-aural-routing-profile-entry-data
         (emacsvox-aural-routing-profile 'workstation))
        saved))
      (let ((first
             (car (emacsvox-aural-voice-workbench--selectors 'bolden))))
        (should (eq (plist-get first :kind) 'exact))
        (should (equal (plist-get first :engine-id) "eloquence")))
      (should
       (equal spoken
              "Windows Speech is now preferred for this session"))
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox-aural-restore-saved-engine-order))
      (should-not emacsvox-aural-session-engine-order)
      (should (equal omnivox-engine-priority-ids '("eloquence" "winrt")))
      (should
       (equal spoken
              "Saved engine order restored; Eloquence is preferred")))))

(ert-deftest emacsvox-aural-voice-workbench-prefers-engine-on-first-run ()
  "Quick preference uses a transient runtime profile on first run."
  (emacsvox-test--with-voice-workbench
    (clrhash emacsvox-aural-routing-profile-registry)
    (setq emacsvox-aural-active-routing-profile nil
          omnivox-engine-priority-ids nil
          omnivox-fallback-engine-ids '("espeak"))
    (let* ((directory (make-temp-file "emacsvox-first-engine-" t))
           (emacsvox-aural-routing-profiles-file
            (expand-file-name "routing.el" directory))
           spoken)
      (unwind-protect
          (cl-letf (((symbol-function 'tts-speak)
                     (lambda (text) (setq spoken text))))
            (should
             (equal
              (mapcar
               #'cdr
               (emacsvox-aural-voice-workbench--engine-candidates))
              '("eloquence" "winrt")))
            (emacsvox-aural-prefer-engine "winrt")
            (should
             (equal emacsvox-aural-session-engine-order
                    '("winrt" "eloquence")))
            (should (equal omnivox-fallback-engine-ids '("winrt")))
            (let ((entry
                   (emacsvox-aural-routing-profile
                    emacsvox-aural-active-routing-profile)))
              (should entry)
              (should
               (eq (emacsvox-aural-routing-profile-entry-source entry)
                   emacsvox-aural-voice-workbench--session-profile-source)))
            (should-not (file-exists-p emacsvox-aural-routing-profiles-file))
            (should
             (equal spoken
                    "Windows Speech is now preferred for this session"))
            (emacsvox-aural-restore-saved-engine-order)
            (should-not emacsvox-aural-session-engine-order)
            (should
             (equal spoken
                    "Initial engine order restored; Eloquence is preferred")))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-voice-workbench-saves-first-engine-preference ()
  "A prefixed first-run preference creates the requested saved profile."
  (emacsvox-test--with-voice-workbench
    (clrhash emacsvox-aural-routing-profile-registry)
    (setq emacsvox-aural-active-routing-profile nil
          omnivox-engine-priority-ids nil
          omnivox-fallback-engine-ids '("espeak"))
    (let* ((directory (make-temp-file "emacsvox-first-saved-engine-" t))
           (emacsvox-aural-routing-profiles-file
            (expand-file-name "routing.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-prefer-engine "winrt" t)
            (should (file-exists-p emacsvox-aural-routing-profiles-file))
            (let* ((saved
                    (emacsvox-aural-read-routing-profiles
                     emacsvox-aural-routing-profiles-file))
                   (profile (car (plist-get saved :profiles))))
              (should
               (eq (plist-get saved :active-profile)
                   emacsvox-aural-active-routing-profile))
              (should
               (equal (plist-get profile :engine-order)
                      '("winrt" "eloquence")))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-voice-workbench-saves-engine-preference ()
  "A prefix saves only promoted global order and clears the session overlay."
  (emacsvox-test--with-voice-workbench
    (let* ((directory (make-temp-file "emacsvox-engine-preference-" t))
           (emacsvox-aural-routing-profiles-file
            (expand-file-name "routing.el" directory))
           (fallback
            (copy-tree
             (plist-get emacsvox-test--workbench-routing-profile :fallback)))
           (bindings
            (copy-tree
             (plist-get emacsvox-test--workbench-routing-profile :bindings)))
           spoken)
      (unwind-protect
          (progn
            (emacsvox-aural-prefer-engine "winrt")
            (cl-letf (((symbol-function 'tts-speak)
                       (lambda (text) (setq spoken text))))
              (emacsvox-aural-prefer-engine "winrt" t))
            (let* ((profile
                    (emacsvox-aural-routing-profile-entry-data
                     (emacsvox-aural-routing-profile 'workstation)))
                   (saved-data
                    (emacsvox-aural-read-routing-profiles
                     emacsvox-aural-routing-profiles-file))
                   (saved-profile (car (plist-get saved-data :profiles))))
              (should-not emacsvox-aural-session-engine-order)
              (should
               (equal (plist-get profile :engine-order)
                      '("winrt" "eloquence")))
              (should
               (equal (plist-get saved-profile :engine-order)
                      '("winrt" "eloquence")))
              (should (equal (plist-get profile :fallback) fallback))
              (should (equal (plist-get profile :bindings) bindings))
              (should
               (equal spoken
                      "Windows Speech is now the saved preferred engine"))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-voice-workbench-protects-staged-edits ()
  "Quick engine preference cannot obscure unsaved Workbench routing edits."
  (emacsvox-test--with-voice-workbench
    (setf (plist-get emacsvox-aural-voice-workbench-staged-profile :summary)
          "unsaved")
    (should-error
     (emacsvox-aural-prefer-engine "winrt")
     :type 'user-error)
    (should-not emacsvox-aural-session-engine-order)))

(ert-deftest emacsvox-aural-voice-workbench-save-failure-restores-session ()
  "A failed persistent preference retains the prior temporary preference."
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-prefer-engine "winrt")
    (let ((before
           (copy-tree
            (emacsvox-aural-routing-profile-entry-data
             (emacsvox-aural-routing-profile 'workstation)))))
      (cl-letf (((symbol-function 'emacsvox-aural-save-routing-profiles)
                 (lambda (&rest _) (error "simulated save failure"))))
        (should-error
         (emacsvox-aural-prefer-engine "eloquence" t)
         :type 'error))
      (should
       (equal emacsvox-aural-session-engine-order
              '("winrt" "eloquence")))
      (should
       (equal
        (emacsvox-aural-routing-profile-entry-data
         (emacsvox-aural-routing-profile 'workstation))
        before)))))

(ert-deftest emacsvox-aural-voice-workbench-provides-four-spoken-views ()
  "One shared UI exposes logical, physical, engine, and style/effect rows."
  (emacsvox-test--with-voice-workbench
    (should (eq emacsvox-aural-voice-workbench-view 'logical))
    (should (emacsvox-aural-ui-goto-row "bolden"))
    (should
     (string-match-p "eci:Reed"
                     (emacsvox-aural-voice-workbench-speak-current)))
    (emacsvox-aural-voice-workbench-physical-view)
    (should (= (length tabulated-list-entries) 3))
    (emacsvox-aural-voice-workbench-engine-view)
    (should (= (length tabulated-list-entries) 7))
    (should (equal (aref (cadr (assoc "piper" tabulated-list-entries)) 1) "not reported"))
    (should (string-prefix-p "Prototype;"
                             (aref (cadr (assoc "mbrola" tabulated-list-entries)) 1)))
    (emacsvox-aural-voice-workbench-style-view)
    (should tabulated-list-entries)))

(ert-deftest emacsvox-aural-voice-workbench-separates-availability-and-policy ()
  "Missing engines remain diagnosable without being announced as enabled."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (copy-tree emacsvox-test--workbench-inventory))
           (missing '(:engine-id "rhvoice" :display-name "RHVoice"
                      :availability "unavailable"
                      :availability-reason "Runtime library was not found"
                      :health "unavailable" :voices nil))
           (tts-voice-inventory-function (lambda () inventory)))
      (push missing (plist-get inventory :engines))
      (emacsvox-aural-voice-workbench-engine-view)
      (emacsvox-aural-ui-goto-row "rhvoice")
      (let ((spoken (emacsvox-aural-voice-workbench-speak-current)))
        (should (string-search "Engine, RHVoice. Availability, unavailable" spoken))
        (should (string-search "Routing policy, allowed" spoken))
        (should (string-search "Runtime library was not found" spoken))
        (should-not (string-search "enabled" spoken)))
      (emacsvox-aural-ui-goto-row "eloquence")
      (should (string-search "Availability, available"
                             (emacsvox-aural-voice-workbench-speak-current)))
      (emacsvox-aural-voice-workbench-toggle-disabled-engine)
      (should (string-search "Routing policy, disabled staged"
                             (emacsvox-aural-voice-workbench-speak-current))))))

(ert-deftest emacsvox-aural-voice-workbench-stages-distinct-engine-orders ()
  "Preferred, fallback, and disabled policy lists remain independent."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'engines)
    (emacsvox-aural-voice-workbench-refresh "eloquence")
    (let (spoken)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox-aural-voice-workbench-move-preferred-engine-down))
      (should
       (string-match-p
        "eloquence to position 2 of 2 in global preferred order"
        spoken)))
    (should
     (equal
      (plist-get emacsvox-aural-voice-workbench-staged-profile :engine-order)
      '("winrt" "eloquence")))
    (emacsvox-aural-voice-workbench-toggle-fallback-engine)
    (let (spoken)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox-aural-voice-workbench-move-fallback-engine-up))
      (should
       (string-match-p
        "eloquence to position 1 of 2 in global fallback order"
        spoken)))
    (should
     (equal
      (plist-get
       (plist-get emacsvox-aural-voice-workbench-staged-profile :fallback)
       :engines)
      '("eloquence" "winrt")))
    (emacsvox-aural-voice-workbench-toggle-disabled-engine)
    (should
     (equal
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :disabled-engines)
      '("eloquence")))))

(ert-deftest emacsvox-aural-voice-workbench-shows-engine-runtime-detail ()
  "Engine rows show failures; Details exposes audio and marker capabilities."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'engines)
    (emacsvox-aural-voice-workbench-refresh "winrt")
    (let ((spoken (emacsvox-aural-voice-workbench-speak-current)))
      (should (string-match-p "helper exited" spoken))
      (should (string-match-p "750 ms" spoken))
      (save-window-excursion
        (emacsvox-aural-voice-workbench-describe)
        (with-current-buffer (help-buffer)
          (should (string-match-p "Audio: buffered_pcm" (buffer-string)))
          (should (string-match-p "Anchors: word-boundary" (buffer-string))))))))

(ert-deftest emacsvox-aural-voice-workbench-reports-status-without-speaking ()
  "Quiet refresh updates inventory, process, and staged-state header status."
  (emacsvox-test--with-voice-workbench
    (let (spoken)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox-aural-voice-workbench-refresh)
        (should-not spoken)))
    (let ((header (emacsvox-aural-voice-workbench--header)))
      (should (string-match-p "generation 12" header))
      (should (string-match-p "processes agree" header))
      (should (string-match-p "routing workstation, committed" header)))
    (setf (plist-get emacsvox-aural-voice-workbench-staged-profile :summary)
          "changed")
    (should
     (string-match-p "routing workstation, staged"
                     (emacsvox-aural-voice-workbench--header)))))

(ert-deftest emacsvox-aural-voice-workbench-reuses-first-run-inventory ()
  "First-run profile setup should reuse the mode's inventory snapshot."
  (let* ((emacsvox-aural-routing-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-active-routing-profile nil)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-engine-priority-ids nil)
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-disabled-engine-ids nil)
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t)
         (calls 0)
         (tts-voice-inventory-function
          (lambda ()
            (cl-incf calls)
            (copy-tree emacsvox-test--workbench-inventory))))
    (with-temp-buffer
      (cl-letf (((symbol-function 'tts-speak) #'ignore))
        (emacsvox-aural-voice-workbench-mode))
      (should (= calls 1))
      (should
       (equal emacsvox-aural-voice-workbench-inventory
              emacsvox-test--workbench-inventory)))))

(ert-deftest emacsvox-aural-voice-workbench-filters-physical-inventory ()
  "Physical rows filter by voice traits and engine health."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'physical
          emacsvox-aural-voice-workbench-filter
          '(:language "en-US" :health "degraded"))
    (emacsvox-aural-voice-workbench-refresh)
    (should (= (length tabulated-list-entries) 1))
    (should
     (equal (tabulated-list-get-id) '("winrt" "David")))
    (setq emacsvox-aural-voice-workbench-filter '(:gender "female"))
    (emacsvox-aural-voice-workbench-refresh)
    (should-not tabulated-list-entries)))

(ert-deftest emacsvox-aural-voice-workbench-shows-physical-voice-users ()
  "Physical inventory identifies matching staged logical routes."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'physical)
    (emacsvox-aural-voice-workbench-refresh '("eloquence" "eci:Reed"))
    (let ((entry (cadr (assoc '("eloquence" "eci:Reed") (emacsvox-aural-voice-workbench--detail-entries)))))
      (should (string-match-p "\\bbolden\\b" (aref entry 7))))))

(ert-deftest emacsvox-aural-workbench-large-inventory-resolves-each-choice-once ()
  "A large voice list shares resolution within a redraw, then sees later edits."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'physical
          emacsvox-aural-voice-workbench-inventory
          (copy-tree emacsvox-test--workbench-inventory)
          emacsvox-aural-routing--choice-sets
          (copy-tree emacsvox-aural-routing--choice-sets))
    (let* ((engine (car (plist-get emacsvox-aural-voice-workbench-inventory :engines)))
           (logical-count (length (emacsvox-aural-voice-workbench--logical-voices)))
           (resolve (symbol-function 'emacsvox-aural-voice-workbench--resolved-voice))
           (calls 0))
      (setf (plist-get engine :voices)
            (append (plist-get engine :voices)
                    (cl-loop for i below 100 collect
                             (list :voice-id (format "extra-%d" i)
                                   :display-name (format "Extra %d" i)
                                   :availability "available"))))
      (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--resolved-voice)
                 (lambda (voice) (cl-incf calls) (funcall resolve voice))))
        (let ((rows (emacsvox-aural-voice-workbench--detail-entries)))
          (should (= 102 (length rows)))
          (should (= logical-count calls))
          (should (string-match-p "\\bbolden\\b"
                                  (aref (cadr (assoc '("eloquence" "eci:Reed") rows)) 7))))
        (setf (plist-get (plist-get (car (plist-get (car emacsvox-aural-routing--choice-sets)
                                                   :choices)) :selector) :voice-id)
              "extra-99")
        (setq calls 0)
        (let ((rows (emacsvox-aural-voice-workbench--detail-entries)))
          (should (= logical-count calls))
          (should-not (string-match-p "\\bbolden\\b"
                                      (aref (cadr (assoc '("eloquence" "eci:Reed") rows)) 7)))
          (should (string-match-p "\\bbolden\\b"
                                  (aref (cadr (assoc '("eloquence" "extra-99") rows)) 7))))))))

(ert-deftest emacsvox-aural-workbench-playback-refreshes-only-last-played-views ()
  "Playback leaves physical rows alone; real inventory changes still update them."
  (emacsvox-test--with-voice-workbench
    (let ((buffer (current-buffer)) refreshed)
      (cl-letf (((symbol-function 'buffer-list) (lambda (&rest _) (list buffer)))
                ((symbol-function 'emacsvox-aural-voice-workbench-refresh)
                 (lambda (&rest _) (push emacsvox-aural-voice-workbench-view refreshed)))
                ((symbol-function 'emacsvox-aural-voice-workbench--library-check-lanes) #'ignore))
        (dolist (view '(physical engines logical styles))
          (setq emacsvox-aural-voice-workbench-view view)
          (run-hook-with-args 'tts-realized-voice-changed-hook '(:logical-voice "bolden")))
        (should (equal refreshed '(styles logical)))
        (setq refreshed nil emacsvox-aural-voice-workbench-view 'physical)
        (run-hooks 'tts-voice-inventory-changed-hook)
        (should (equal refreshed '(physical)))))))

(ert-deftest emacsvox-aural-voice-workbench-shows-portable-and-realized-identity ()
  "Named voice rows lead with the name and distinguish predicted and played voices."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "bolden"))
    (let ((entry (tabulated-list-get-entry)))
      (should (equal (aref entry 0) "bolden"))
      (should (string-match-p "eci:Reed" (aref entry 2)))
      (should (equal (aref entry 3) "eloquence/eci:Reed")))))

(ert-deftest emacsvox-aural-voice-workbench-shows-last-played-route ()
  "Logical rows distinguish predicted routing from playback observation."
  (emacsvox-test--with-voice-workbench
    (let ((tts-last-realized-voice-function
           (lambda (_logical)
             '(:engine-id "dectalk" :voice-id "paul"
               :degraded-acss ("richness") :degraded-effects nil))))
      (emacsvox-aural-voice-workbench-refresh "bolden")
      (let ((entry (tabulated-list-get-entry)))
        (should (equal (aref entry 3) "eloquence/eci:Reed"))
        (should
         (equal (aref entry 4) "dectalk/paul omitted richness"))))))

(ert-deftest emacsvox-aural-voice-workbench-diagnoses-disappearing-inventory ()
  "A stale or vanished exact voice is reported without rewriting its route."
  (emacsvox-test--with-voice-workbench
    (let ((before
           (copy-tree emacsvox-aural-voice-workbench-staged-profile)))
      (setq emacsvox-aural-voice-workbench-inventory
            (copy-tree emacsvox-test--workbench-inventory))
      (setf (plist-get emacsvox-aural-voice-workbench-inventory :stale) t)
      (setf
       (plist-get
        (car
         (plist-get emacsvox-aural-voice-workbench-inventory :engines))
        :voices)
       nil)
      (let* ((diagnostics
              (emacsvox-aural-voice-workbench--profile-diagnostics
               emacsvox-aural-voice-workbench-staged-profile))
             (kinds (mapcar (lambda (entry) (plist-get entry :kind))
                            diagnostics)))
        (should (memq 'stale-inventory kinds))
        (should (memq 'voice-missing kinds)))
      (should
       (equal
        (emacsvox-aural-voice-workbench--realization-description
         "bolden")
        "unavailable"))
      (should (equal (plist-get (plist-get before :fallback) :engines) '("winrt")))
      (should
       (equal before emacsvox-aural-voice-workbench-staged-profile)))))

(ert-deftest emacsvox-aural-voice-workbench-cancel-restores-opening-copy ()
  "Cancelling staged work restores the exact committed profile and clears undo."
  (emacsvox-test--with-voice-workbench
    (let ((opening
           (copy-tree emacsvox-aural-voice-workbench-committed-profile)))
      (emacsvox-aural-voice-workbench--stage
       "Test edit"
       (lambda ()
         (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                          :summary)
               "changed")))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (emacsvox-aural-voice-workbench-cancel-staged))
      (should
       (equal emacsvox-aural-voice-workbench-staged-profile opening))
      (should-not emacsvox-aural-voice-workbench-undo-stack))))

(ert-deftest emacsvox-aural-voice-workbench-saves-and-applies-atomically ()
  "Save commits one staged profile and retains its prior revision for undo."
  (emacsvox-test--with-voice-workbench
    (let* ((directory (make-temp-file "emacsvox-workbench-save-" t))
           (emacsvox-aural-routing-profiles-file
            (expand-file-name "routing.el" directory))
           (opening
            (copy-tree emacsvox-aural-voice-workbench-committed-profile)))
      (unwind-protect
          (progn
            (emacsvox-aural-voice-workbench--stage
             "Test saved edit"
             (lambda ()
               (setf
                (plist-get emacsvox-aural-voice-workbench-staged-profile
                           :summary)
                "saved")))
            (emacsvox-aural-voice-workbench-save-and-apply)
            (should
             (equal
              (plist-get emacsvox-aural-voice-workbench-committed-profile
                         :summary)
              "saved"))
            (should-not (emacsvox-aural-voice-workbench--dirty-p))
            (should
             (equal emacsvox-aural-voice-workbench-applied-undo opening))
            (should (file-exists-p emacsvox-aural-routing-profiles-file))
            (should
             (eq (plist-get emacsvox-aural-routing-apply-status :status)
                 'applied)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-voice-workbench-previews-exact-row-transactionally ()
  "Physical preview uses an exact session selector without staging edits."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'physical)
    (emacsvox-aural-voice-workbench-refresh '("eloquence" "eci:Reed"))
    (let ((before (copy-tree emacsvox-aural-voice-workbench-staged-profile))
          entries)
      (let ((tts-voice-preview-function
             (lambda (value callback)
               (setq entries value)
               (funcall
                callback
                '(:status completed :completion-guarantee playback
                  :results
                  ((:status completed
                    :realized
                    (:engine-id "eloquence" :voice-id "eci:Reed"))))))))
        (emacsvox-aural-voice-workbench-preview))
      (let ((selector (plist-get (car entries) :selector)))
        (should (eq (plist-get selector :kind) 'exact))
        (should (eq (plist-get selector :scope) 'session))
        (should (equal (plist-get selector :engine-id) "eloquence"))
        (should (equal (plist-get selector :voice-id) "eci:Reed")))
      (should
       (equal (mapcar (lambda (entry) (plist-get entry :text)) entries)
              (list "1, Eloquence, Reed." emacsvox-aural-voice-workbench-preview-text)))
      (should (equal emacsvox-aural-voice-workbench-staged-profile before))
      (should
       (eq (plist-get emacsvox-aural-voice-workbench-last-preview :status)
           'completed)))))

(ert-deftest emacsvox-aural-voice-workbench-preview-all-reuses-sample-text ()
  "Preview-all submits every visible voice with identical comparison text."
  (emacsvox-test--with-voice-workbench
    (let (entries)
      (let ((tts-voice-preview-function
             (lambda (value callback)
               (setq entries value)
               (funcall callback '(:status queued :results nil)))))
        (emacsvox-aural-voice-workbench-preview-all))
      (should (= (length entries) 2))
      (should
       (equal (mapcar (lambda (entry) (plist-get entry :text)) entries)
              (list "1, Eloquence, Reed." emacsvox-aural-voice-workbench-preview-text)))
      (should
       (equal
        (mapcar
         (lambda (entry)
           (plist-get (plist-get entry :selector) :kind))
         entries)
        '(exact exact))))))

(ert-deftest emacsvox-aural-workbench-engine-entry-preserves-view-orientation ()
  "Engine v filters physical voices and preserves the engine's selected column."
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-voice-workbench--switch 'engines)
    (emacsvox-aural-ui-goto-row "eloquence")
    (emacsvox-aural-ui-goto-tabulated-column 2)
    (setq emacsvox-aural-voice-workbench-filter '(:language "en-AU"))
    (emacsvox-aural-voice-workbench-physical-view)
    (should (eq emacsvox-aural-voice-workbench-view 'physical))
    (should (equal emacsvox-aural-voice-workbench-filter
                   '(:language "en-AU")))
    (should (equal (emacsvox-aural-voice-workbench--physical-filter)
                   '(:language "en-AU" :engine "eloquence")))
    (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed")))
    (emacsvox-aural-ui-goto-tabulated-column 3)
    (call-interactively (key-binding (kbd "q")))
    (should (equal (tabulated-list-get-id) "eloquence"))
    (should (= (emacsvox-aural-ui-tabulated-column-index) 2))
    (emacsvox-aural-voice-workbench--switch 'physical)
    (should (= (emacsvox-aural-ui-tabulated-column-index) 3))))

(ert-deftest emacsvox-aural-workbench-back-survives-empty-voice-list-refresh ()
  "An empty refreshed list still returns to its engine before dismissing."
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-voice-workbench-engine-view)
    (emacsvox-aural-ui-goto-row "winrt")
    (emacsvox-aural-ui-goto-tabulated-column 3)
    (setq emacsvox-aural-voice-workbench-filter '(:language "missing"))
    (call-interactively (key-binding (kbd "v")))
    (emacsvox-aural-voice-workbench-refresh)
    (should-not tabulated-list-entries)
    (should (emacsvox-aural-voice-workbench--action-applicable-p
             (key-binding (kbd "q"))))
    (let ((dismissed 0))
      (cl-letf (((symbol-function 'emacsvox-aural-quit)
                 (lambda () (cl-incf dismissed))))
        (call-interactively (key-binding (kbd "q")))
        (should (eq emacsvox-aural-voice-workbench-view 'engines))
        (should (equal (tabulated-list-get-id) "winrt"))
        (should (= (emacsvox-aural-ui-tabulated-column-index) 3))
        (should (zerop dismissed))
        (call-interactively (key-binding (kbd "q")))
        (should (= dismissed 1))))))

(ert-deftest emacsvox-aural-workbench-direct-views-do-not-inherit-back-target ()
  "Direct physical browsing dismisses normally, including after view changes."
  (emacsvox-test--with-voice-workbench
    (let ((dismissed 0))
      (cl-letf (((symbol-function 'emacsvox-aural-quit)
                 (lambda () (cl-incf dismissed))))
        (emacsvox-aural-voice-workbench-physical-view)
        (call-interactively (key-binding (kbd "q")))
        (should (= dismissed 1))
        (emacsvox-aural-voice-workbench-engine-view)
        (call-interactively (key-binding (kbd "v")))
        (emacsvox-aural-voice-workbench-logical-view)
        (emacsvox-aural-voice-workbench-physical-view)
        (call-interactively (key-binding (kbd "q")))
        (should (= dismissed 2))))))

(ert-deftest emacsvox-aural-workbench-engine-scope-preserves-explicit-filters ()
  "Temporary browsing restores explicit filters; v and C can leave its scope."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-filter '(:engine "eloquence" :gender "male"))
    (emacsvox-aural-voice-workbench-engine-view)
    (emacsvox-aural-ui-goto-row "winrt")
    (emacsvox-aural-voice-workbench-physical-view)
    (should (equal (tabulated-list-get-id) '("winrt" "David")))
    (call-interactively (key-binding (kbd "v")))
    (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed")))
    (should (equal emacsvox-aural-voice-workbench-filter
                   '(:engine "eloquence" :gender "male")))
    (emacsvox-aural-voice-workbench-engine-view)
    (emacsvox-aural-voice-workbench-physical-view)
    (call-interactively (key-binding (kbd "C")))
    (emacsvox-test--expand-voice-languages)
    (should (= (length tabulated-list-entries) 3))
    (should-not emacsvox-aural-voice-workbench--voice-list-parent)
    (should-not emacsvox-aural-voice-workbench-filter)))

(ert-deftest emacsvox-aural-workbench-bulk-preview-follows-rendered-order ()
  "Sorted rows determine audible order; unavailable engines are skipped."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (copy-tree emacsvox-test--workbench-inventory))
           (engine (car (plist-get inventory :engines)))
           (extra (copy-tree (car (plist-get engine :voices))))
           (tts-voice-inventory-function (lambda () inventory))
           entries)
      (setf (plist-get extra :voice-id) "eci:Zoe"
            (plist-get extra :display-name) "Zoe"
            (plist-get engine :voices) (append (plist-get engine :voices) (list extra)))
      (emacsvox-aural-voice-workbench--switch 'physical)
      (emacsvox-test--expand-voice-languages)
      (setq tabulated-list-sort-key '("Physical voice" . t))
      (emacsvox-aural-voice-workbench-refresh)
      (cl-letf (((symbol-function 'tts-preview-voices)
                 (lambda (value _callback) (setq entries value))))
        (emacsvox-aural-voice-workbench-preview-all))
      (should (equal (mapcar (lambda (entry) (plist-get (plist-get entry :selector) :voice-id))
                            entries) '("eci:Zoe" "eci:Zoe" "eci:Reed" "eci:Reed")))
      (should (equal (plist-get (nth 1 entries) :text) (plist-get (nth 3 entries) :text)))
      (should (string-match-p "Zoe" (plist-get (nth 0 entries) :text)))
      (emacsvox-aural-ui-goto-row '("winrt" "David"))
      (should-error (emacsvox-aural-voice-workbench-preview) :type 'user-error))))

(ert-deftest emacsvox-aural-workbench-comparison-starts-at-selected-row ()
  "Comparison keeps A fixed and searches all engines only when explicitly chosen."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (copy-tree emacsvox-test--workbench-inventory))
           (second (cadr (plist-get inventory :engines)))
           (tts-voice-inventory-function (lambda () inventory))
           entries prompts)
      (setf (plist-get second :circuit) "closed")
      (setq emacsvox-aural-voice-workbench-filter '(:engine "eloquence"))
      (emacsvox-aural-voice-workbench--switch 'physical)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt choices &rest _)
                   (push prompt prompts)
                   (if (= (length prompts) 1)
                       (progn (should (equal choices '(("Search all engines"))))
                              "Search all engines")
                     (should (string-match-p "David" (caar choices)))
                     (caar choices))))
                ((symbol-function 'tts-preview-voices)
                 (lambda (value _callback) (setq entries value))))
        (emacsvox-aural-voice-workbench-compare))
      (should (= (length prompts) 2))
      (should (equal (plist-get (nth 0 entries) :text) "A, Eloquence, Reed."))
      (should (equal (plist-get (nth 2 entries) :text) "B, Windows Speech, David."))
      (should (equal (plist-get (nth 1 entries) :text) (plist-get (nth 3 entries) :text)))
      (should (equal emacsvox-aural-voice-workbench-filter '(:engine "eloquence"))))))

(ert-deftest emacsvox-aural-workbench-ignores-obsolete-preview-status ()
  "An old cancellation callback cannot replace the newer preview's status."
  (emacsvox-test--with-voice-workbench
    (let (callbacks)
      (cl-letf (((symbol-function 'tts-preview-voices)
                 (lambda (_entries callback) (push callback callbacks))))
        (emacsvox-aural-voice-workbench--preview-entries '((:text "first")))
        (emacsvox-aural-voice-workbench--preview-entries '((:text "second")))
        (funcall (cadr callbacks) '(:status cancelled))
        (should (equal (plist-get emacsvox-aural-voice-workbench-last-preview :status)
                       "running 1"))
        (funcall (car callbacks) '(:status completed))
        (should (eq (plist-get emacsvox-aural-voice-workbench-last-preview :status)
                    'completed))))))

(ert-deftest emacsvox-aural-voice-workbench-logical-preview-carries-effects ()
  "Logical preview uses the effective route and complete portable style."
  (emacsvox-test--with-voice-workbench
    (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                     :engine-order)
          nil)
    (cl-letf
        (((symbol-function 'emacsvox-aural-voice-workbench--palette-entry)
          (lambda (_logical)
            '(annotate
              :rate-offset -6 :average-pitch 4 :pitch-range nil :stress 2
              :richness 7 :gain 5 :low-pass 8 :high-pass 1 :pan 5
              :reverb 7 :echo 3 :chorus 6))))
      (let* ((entry
              (emacsvox-aural-voice-workbench--logical-preview-entry
               "voice-annotate"))
             (acss (plist-get entry :acss))
             (effects (plist-get entry :effects)))
        (should (plist-member entry :selectors))
        (should-not (plist-get entry :selectors))
        (should-not (plist-member entry :selector))
        (should-not (plist-member acss :rate))
        (should (= (plist-get entry :rate-offset) -6))
        (should (= (plist-get acss :average-pitch) (/ 4.0 9.0)))
        (should-not (plist-member acss :pitch-range))
        (should (= (plist-get effects :gain) 0.5))
        (should (= (plist-get effects :pan) 0.5))
        (should (= (plist-get effects :low-pass) (/ 8.0 9.0)))
        (should (= (plist-get effects :high-pass) (/ 1.0 9.0)))
        (should (= (plist-get effects :reverb) (/ 7.0 9.0)))
        (should (= (plist-get effects :echo) (/ 3.0 9.0)))
        (should (= (plist-get effects :chorus) (/ 6.0 9.0)))))))

(ert-deftest emacsvox-aural-voice-workbench-preview-preserves-effect-scale ()
  "Public logical previews use exact gain/pan neutral points and keep omissions."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'logical)
    (should (emacsvox-aural-ui-goto-row "bolden"))
    ;; Values on both sides of five distinguish the piecewise effect scale
    ;; from the ordinary ACSS division by nine.  State expectations explicitly.
    (dolist (fixture '((nil nil) (0 0.0) (4 0.4) (5 0.5) (6 0.625) (9 1.0)))
      (let ((level (car fixture)) (expected (cadr fixture)) entries)
        (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--palette-entry)
                   (lambda (_voice) (list 'bolden :gain level :pan level)))
                  ((symbol-function 'tts-preview-voices)
                   (lambda (value _callback) (setq entries value))))
          (emacsvox-aural-voice-workbench-preview))
        (let ((effects (plist-get (car entries) :effects)))
          (dolist (key '(:gain :pan))
            (if expected
                (should (= (plist-get effects key) expected))
              (should-not (plist-member effects key)))))))))

(ert-deftest emacsvox-aural-voice-workbench-quit-warns-about-staged-route ()
  "Hiding a dirty Workbench says that the physical route is not saved."
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-voice-workbench--stage
     "Change a route"
     (lambda ()
       (setf
        (plist-get emacsvox-aural-voice-workbench-staged-profile :summary)
        "changed")))
    (let (spoken quit)
      (cl-letf
          (((symbol-function 'quit-window)
            (lambda (&optional _) (setq quit t)))
           ((symbol-function 'tts-speak)
            (lambda (text) (setq spoken text)))
           ((symbol-function 'emacsvox-icon) #'ignore)
           ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
        (emacsvox-aural-voice-workbench-engine-view)
        (call-interactively (key-binding (kbd "v")))
        (call-interactively (key-binding (kbd "q")))
        (should-not quit)
        (should (emacsvox-aural-voice-workbench--dirty-p))
        (call-interactively (key-binding (kbd "q"))))
      (should quit)
      (should
       (string-match-p "Engine policy changes remain staged" spoken))
      (should (string-match-p "press w to save and apply" spoken)))))


(ert-deftest emacsvox-aural-voice-workbench-compact-columns-retain-details ()
  "Each view keeps its row identities, and Details retains hidden fields."
  (emacsvox-test--with-voice-workbench
    (dolist (view '(logical physical engines styles))
      (setq emacsvox-aural-voice-workbench-view view)
      (emacsvox-aural-voice-workbench-refresh)
      (when (eq view 'physical) (emacsvox-test--expand-voice-languages))
      (dolist (row tabulated-list-entries)
        (should (= (length (cadr row)) (length tabulated-list-format))))
      (should-not (cl-set-exclusive-or (mapcar #'car (cl-remove-if
                                   (lambda (row) (emacsvox-aural-voice-workbench--language-row-p (car row)))
                                   tabulated-list-entries))
                     (mapcar #'car (emacsvox-aural-voice-workbench--detail-entries)) :test #'equal)))
    (setq emacsvox-aural-voice-workbench-view 'physical)
    (emacsvox-aural-voice-workbench-refresh '("eloquence" "eci:Reed"))
    (save-window-excursion
      (emacsvox-aural-voice-workbench-describe)
      (with-current-buffer (help-buffer)
        (should (string-match-p "Native ID: eci:Reed" (buffer-string)))
        (should (string-match-p "generation 12" (buffer-string)))))
    (setq emacsvox-aural-voice-workbench-view 'engines)
    (emacsvox-aural-voice-workbench-refresh "eloquence")
    (should (equal (aref (tabulated-list-get-entry) 0) "Eloquence"))))

(ert-deftest emacsvox-aural-voice-workbench-engine-details-browse-and-return ()
  "Engine details open scoped voices without disturbing another workbench."
  (emacsvox-test--with-voice-workbench
    (let ((general (current-buffer))
          (manager (generate-new-buffer " *engine manager fixture*"))
          details browser
          (staged (copy-tree emacsvox-aural-voice-workbench-staged-profile)))
      (unwind-protect
          (save-window-excursion
            (setq emacsvox-aural-voice-workbench-filter '(:language "en-US"))
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                      ((symbol-function 'emacsvox-aural-ui-speak) #'ignore)
                      ((symbol-function 'tts-preview-voices)
                       (lambda (&rest _) (ert-fail "Browsing played a sample"))))
              (switch-to-buffer manager)
              (emacsvox-omnivox-components-mode)
              (setq emacsvox-omnivox-components--records
                    '((:id "eloquence" :name "Eloquence" :state "runtime-required" :size 0)))
              (emacsvox-omnivox-components--render "eloquence")
              (emacsvox-omnivox-components-activate)
              (setq details (current-buffer))
              (should (emacsvox-aural-ui-goto-row 'voices))
              (emacsvox-omnivox-components--details-activate)
              (setq browser (current-buffer))
              (should (derived-mode-p 'emacsvox-aural-voice-workbench-mode))
              (should (equal (mapcar #'car tabulated-list-entries)
                             '(("eloquence" "eci:Reed"))))
              (should (string-search "a Apply" (emacsvox-aural-voice-workbench--header)))
              (should (equal (plist-get (emacsvox-aural-voice-workbench--current-preview-entry) :selector)
                             '(:kind exact :engine-id "eloquence" :voice-id "eci:Reed" :scope session)))
              (with-current-buffer general
                (should (eq emacsvox-aural-voice-workbench-view 'logical))
                (should (equal emacsvox-aural-voice-workbench-filter '(:language "en-US")))
                (should (equal staged emacsvox-aural-voice-workbench-staged-profile)))
              (emacsvox-aural-voice-workbench-quit)
              (should (eq (current-buffer) details))
              (should (eq (tabulated-list-get-id) 'voices))
              (emacsvox-omnivox-components--details-back)
              (should (eq (current-buffer) manager))
              (should (equal (tabulated-list-get-id) "eloquence"))))
        (dolist (buffer (list browser details manager))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-workbench-engine-browser-refresh-and-editor ()
  "Dedicated browsers refresh quietly, retain drafts and hand off exact voices."
  (emacsvox-test--with-voice-workbench
    (let* ((parent (current-buffer)) browser editor-call
           (inventory (copy-tree emacsvox-test--workbench-inventory))
           (tts-voice-inventory-function (lambda () inventory)))
      (unwind-protect
          (save-window-excursion
            (setq browser (emacsvox-aural-voice-workbench--open-engine "eloquence" parent))
            (setf (plist-get emacsvox-aural-voice-workbench-staged-profile :engine-order)
                  '("winrt" "eloquence"))
            (setf (plist-get (car (plist-get inventory :engines)) :health) "degraded")
            (with-current-buffer parent (emacsvox-aural-voice-workbench-refresh-if-live))
            (should (eq (current-buffer) browser))
            (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed")))
            (should (equal (aref (cadr (assoc '("eloquence" "eci:Reed") (emacsvox-aural-voice-workbench--detail-entries))) 6) "degraded"))
            (should (equal (plist-get emacsvox-aural-voice-workbench-staged-profile :engine-order)
                           '("winrt" "eloquence")))
            (cl-letf (((symbol-function 'emacsvox-aural-voice-editor-experiment)
                       (lambda (pair source text) (setq editor-call (list pair source text)))))
              (emacsvox-aural-voice-workbench-tune))
            (should (equal (plist-get (cadar editor-call) :voice-id) "eci:Reed"))
            (should (eq (cadr editor-call) browser))
            (should (equal (caddr editor-call) emacsvox-aural-voice-workbench-preview-text))
            (cl-letf (((symbol-function 'tts-preview-voices)
                       (lambda (_entries callback)
                         (funcall callback '(:status failed :results ((:message "Exact voice unavailable"))))))
                      ((symbol-function 'emacsvox-aural-preview-message) #'ignore)
                      ((symbol-function 'emacsvox-aural-ui-announce-result) #'ignore))
              (emacsvox-aural-voice-workbench-preview))
            (should (eq (plist-get emacsvox-aural-voice-workbench-last-preview :status) 'failed)))
        (when (buffer-live-p browser) (kill-buffer browser))))))

(ert-deftest emacsvox-aural-voice-workbench-graphical-engine-browser-return ()
  "Real redisplay preserves the browser through refresh, editing and return."
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-voice-workbench
    (let ((parent (current-buffer)) browser editor
          (emacsvox-aural-voice-drafts--registry (make-hash-table :test #'equal))
          (emacsvox-aural-voice-editor--contexts (make-hash-table :test #'equal))
          (emacsvox-aural-voice-editor--preview-owner nil))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer parent)
            (setq browser (emacsvox-aural-voice-workbench--open-engine "eloquence" parent))
            (redisplay t)
            (let ((window (selected-window)) (row (tabulated-list-get-id)))
              (with-current-buffer parent (emacsvox-aural-voice-workbench-refresh-if-live))
              (redisplay t)
              (should (eq (selected-window) window))
              (should (eq (window-buffer window) browser))
              (should (equal (tabulated-list-get-id) row))
              (should (pos-visible-in-window-p (point) window)))
            (cl-letf (((symbol-function 'tts-stop) #'ignore)
                      ((symbol-function 'emacsvox-icon) #'ignore)
                      ((symbol-function 'tts-preview-voices)
                       (lambda (&rest _) (ert-fail "Opening the editor played a sample"))))
              (emacsvox-aural-voice-workbench-tune)
              (setq editor (current-buffer))
              (redisplay t)
              (should (derived-mode-p 'emacsvox-aural-voice-editor-mode))
              (should (emacsvox-aural-voice-editor--get :experiment))
              (should (eq (marker-buffer (emacsvox-aural-voice-editor--get :origin)) browser))
              (emacsvox-aural-voice-editor-leave)
              (redisplay t)
              (should (eq (current-buffer) browser))
              (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed"))))
            (emacsvox-aural-voice-workbench-quit)
            (redisplay t)
            (should (eq (window-buffer (selected-window)) parent)))
        (dolist (buffer (list editor browser))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (let ((kill-buffer-query-functions nil)) (kill-buffer)))))))))

(ert-deftest emacsvox-aural-workbench-home-opening-announces-before-discovery ()
  "Both Home routes speak the selected engine without waiting for a check."
  (require 'emacsvox-aural-home)
  (emacsvox-test--with-voice-workbench
    (let ((browser (current-buffer)) spoken)
      (emacsvox-aural-voice-workbench-engine-view)
      (emacsvox-aural-ui-goto-row "eloquence")
      (cl-letf (((symbol-function 'get-buffer-create) (lambda (_ &optional _inhibit-hooks) browser))
                ((symbol-function 'tts-speak) (lambda (text) (push text spoken)))
                ((symbol-function 'emacsvox-aural-ui--pop-to-buffer)
                 (lambda (buffer speaker) (with-current-buffer buffer (funcall speaker))))
                ((symbol-function 'tts-refresh-voice-inventory)
                 (lambda () (ert-fail "Opening Browse Voices requested discovery")))
                ((symbol-function 'emacsvox-omnivox-components--request-records)
                 (lambda () (ert-fail "Opening Browse Voices checked installation"))))
        (emacsvox-aural-home-browse-voices)
        (emacsvox-aural-home-engine-modules)
        (emacsvox-omnivox-manage-components))
      (should (= 3 (length spoken)))
      (dolist (text spoken)
        (should (string-prefix-p "Browse voices. Eloquence. available. 1 voice." text))))))

(ert-deftest emacsvox-aural-workbench-graphical-engine-management-round-trip ()
  "Browse Voices owns details and preserves a staged edit through nested views."
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-voice-workbench
    (let ((browser (current-buffer))
          (manager (generate-new-buffer " *browse management state*"))
          details mbrola-details voices events)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer browser)
            (emacsvox-aural-voice-workbench-engine-view)
            (emacsvox-aural-ui-goto-row "eloquence")
            (emacsvox-aural-ui-goto-tabulated-column 2)
            (setq emacsvox-aural-voice-workbench-filter '(:language "en-US"))
            (setf (plist-get emacsvox-aural-voice-workbench-staged-profile :summary) "Unfinished edit")
            (with-current-buffer manager
              (emacsvox-omnivox-components-mode))
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--manager-buffer) (lambda (&rest _) manager))
                      ((symbol-function 'emacsvox-omnivox-components--speak)
                       (lambda (text) (push (cons 'speech text) events)))
                      ((symbol-function 'emacsvox-omnivox-components--request-records)
                       (lambda () (push 'background-check events))))
              (call-interactively (key-binding (kbd "RET")))
              (setq details (current-buffer))
              (redisplay t)
              (should (derived-mode-p 'emacsvox-omnivox-engine-details-mode))
              (should (eq browser emacsvox-omnivox-components--details-parent))
              (should (equal (mapcar (lambda (event) (if (consp event) (car event) event))
                                    (reverse events)) '(speech)))
              (should (string-prefix-p "eloquence." (cdr (car events))))
              (emacsvox-aural-ui-goto-row 'voices)
              (call-interactively (key-binding (kbd "RET")))
              (setq voices (current-buffer))
              (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed")))
              (call-interactively (key-binding (kbd "q")))
              (should (eq details (current-buffer)))
              (let ((window (selected-window)))
                (with-current-buffer manager (emacsvox-omnivox-components--refresh-details))
                (redisplay t)
                (should (eq window (selected-window)))
                (should (eq 'voices (tabulated-list-get-id))))
              (call-interactively (key-binding (kbd "q")))
              (redisplay t)
              (should (eq browser (current-buffer)))
              (should (equal "eloquence" (tabulated-list-get-id)))
              (should (= 2 (emacsvox-aural-ui-tabulated-column-index)))
              (should (equal '(:language "en-US") emacsvox-aural-voice-workbench-filter))
              (should (emacsvox-aural-voice-workbench--dirty-p))
              (emacsvox-aural-ui-goto-row "mbrola")
              (call-interactively (key-binding (kbd "RET")))
              (setq mbrola-details (current-buffer))
              (redisplay t)
              (should (equal emacsvox-omnivox-components--engine-id "mbrola"))
              (should (assq 'prototype-setup tabulated-list-entries))
              (should-not (assq 'install tabulated-list-entries))
              (call-interactively (key-binding (kbd "q")))
              (should (eq browser (current-buffer)))
              (should (equal "mbrola" (tabulated-list-get-id)))))
        (dolist (buffer (list voices details mbrola-details manager))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-workbench-other-adapters-browse-voices-directly ()
  "Other adapters retain RET voice browsing without Omnivox management rows."
  (emacsvox-test--with-voice-workbench
    (let ((inventory (copy-tree emacsvox-test--workbench-inventory)))
      (setf (plist-get inventory :adapter) "fixture")
      (let ((tts-voice-inventory-function (lambda () inventory)))
        (emacsvox-aural-voice-workbench-engine-view)
        (should (= 2 (length tabulated-list-entries)))
        (emacsvox-aural-ui-goto-row "eloquence")
        (cl-letf (((symbol-function 'emacsvox-omnivox-components--open-engine)
                   (lambda (&rest _) (ert-fail "Another adapter opened Omnivox management"))))
          (emacsvox-aural-voice-workbench-open-row))
        (should (eq 'physical emacsvox-aural-voice-workbench-view))
        (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed")))))))

(ert-deftest emacsvox-aural-workbench-unreported-engine-retains-download-access ()
  "An optional engine without live voices still opens its downloads and status."
  (emacsvox-test--with-voice-workbench
    (let ((browser (current-buffer))
          (manager (generate-new-buffer " *unreported management state*"))
          details spoken)
      (unwind-protect
          (progn
            (emacsvox-aural-voice-workbench-engine-view)
            (emacsvox-aural-ui-goto-row "piper")
            (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
              (emacsvox-aural-voice-workbench--speak-opening))
            (should (string-prefix-p "Browse voices. Piper. not reported." spoken))
            (with-current-buffer manager (emacsvox-omnivox-components-mode))
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--manager-buffer) (lambda (&rest _) manager))
                      ((symbol-function 'emacsvox-omnivox-components--request-records) #'ignore)
                      ((symbol-function 'emacsvox-aural-ui--pop-to-buffer)
                       (lambda (buffer speaker)
                         (setq details buffer)
                         (with-current-buffer buffer (funcall speaker)))))
              (emacsvox-aural-voice-workbench-open-row))
            (with-current-buffer details
              (should (equal "piper" emacsvox-omnivox-components--engine-id))
              (should (eq browser emacsvox-omnivox-components--details-parent))
              (should (assoc 'download-voices tabulated-list-entries))
              (should (equal (aref (cadr (assoc 'summary tabulated-list-entries)) 1)
                             "Not checked"))
              (should-not (assoc 'main-target tabulated-list-entries))))
        (dolist (buffer (list details manager))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-workbench-library-merges-without-changing-routing ()
  (emacsvox-test--with-voice-workbench
    (cl-letf (((symbol-function 'omnivox-library--source-key) (lambda () '(fixture))))
      (setq emacsvox-aural-voice-workbench-view 'physical
            emacsvox-aural-voice-workbench--library-source '(fixture)
            emacsvox-aural-voice-workbench--library-reply
            '(:index (:voices [(:engine_id "eloquence" :physical_id "eci:Reed" :display_name "Installed Reed" :enabled :false)
                              (:engine_id "piper" :physical_id "download" :display_name "Downloaded voice" :enabled t)])))
      (emacsvox-aural-voice-workbench-refresh)
      (emacsvox-test--expand-voice-languages)
      (should (= 4 (length tabulated-list-entries)))
      (should (= 2 (length (emacsvox-aural-voice-workbench--all-engine-voices))))
      (let ((row (cadr (assoc '("eloquence" "eci:Reed") tabulated-list-entries))))
        (should (equal "Reed" (string-trim-left (aref row 0))))
        (should (equal "Library" (aref row 3)))
        (should (equal "No" (aref row 4))))
      (should (emacsvox-aural-voice-workbench--unavailable-reason
               (emacsvox-aural-voice-workbench--physical-pair '("piper" "download"))))
      (let ((emacsvox-aural-voice-workbench--library-source '(different)))
        (should (= 2 (length (emacsvox-aural-voice-workbench--browse-pairs))))))))

(ert-deftest emacsvox-aural-voice-workbench-library-active-is-worker-eligibility ()
  (emacsvox-test--with-voice-workbench
    (let ((main (make-pipe-process :name "active main fixture" :noquery t))
          (notify (make-pipe-process :name "active notify fixture" :noquery t)))
      (unwind-protect
          (let ((tts-speaker-process main) (tts-notify-process notify))
            (cl-letf (((symbol-function 'omnivox-library--source-key) (lambda () '(fixture)))
                      ((symbol-function 'omnivox-voice-inventory) (lambda () emacsvox-test--workbench-inventory)))
              (setq emacsvox-aural-voice-workbench-view 'physical
                    emacsvox-aural-voice-workbench--library-source '(fixture)
                    emacsvox-aural-voice-workbench--library-reply
                    '(:index (:target_id "target" :profile_id "profile"
                              :voices [(:engine_id "eloquence" :physical_id "eci:Reed" :enabled :false)])))
              (dolist (worker (list main notify))
                (process-put worker omnivox--control-inventory-property '(:inventory_generation 12)))
              (let ((status '(:type "voice_library_status_v1" :inventory_generation 12
                             :configuration (:target_id "target" :profile_id "profile")
                             :eligible_voices [(:engine_id "eloquence" :voice_id "eci:Reed")])))
                (setq emacsvox-aural-voice-workbench--library-lanes
                      (list (cons 'main (list :process main :generation 12 :status (copy-tree status t)))
                            (cons 'notification (list :process notify :generation 12 :status (copy-tree status t))))))
              (should (equal '("Library" "No" "Both")
                             (emacsvox-aural-voice-workbench--library-states '("eloquence" "eci:Reed"))))
              ;; Desired changes do not manufacture an applied result.
              (setf (plist-get (aref (plist-get (emacsvox-aural-voice-workbench--library-index) :voices) 0) :enabled) t)
              (should (equal "Both" (nth 2 (emacsvox-aural-voice-workbench--library-states '("eloquence" "eci:Reed")))))
              (setf (plist-get (plist-get (alist-get 'notification emacsvox-aural-voice-workbench--library-lanes) :status) :eligible_voices) [])
              (should (equal "Main only" (nth 2 (emacsvox-aural-voice-workbench--library-states '("eloquence" "eci:Reed")))))
              (process-put main omnivox--control-inventory-property '(:inventory_generation 13))
              (should (eq 'unknown (emacsvox-aural-voice-workbench--library-active '("eloquence" "eci:Reed") 'main)))
              (process-put main omnivox--control-inventory-property '(:inventory_generation 12))
              (let ((tts-speaker-process notify))
                (should (eq 'unknown (emacsvox-aural-voice-workbench--library-active '("eloquence" "eci:Reed") 'main))))
              (delete-process main)
              (should (eq 'unknown (emacsvox-aural-voice-workbench--library-active '("eloquence" "eci:Reed") 'main)))))
        (dolist (worker (list main notify)) (when (process-live-p worker) (delete-process worker)))))))

(ert-deftest emacsvox-aural-voice-workbench-library-late-inspection-is-discarded ()
  (emacsvox-test--with-voice-workbench
    (let ((source '(first)) callbacks)
      (cl-letf (((symbol-function 'omnivox-library--source-key) (lambda () source))
                ((symbol-function 'omnivox-library--inspect-async)
                 (lambda (callback) (push callback callbacks) #'ignore))
                ((symbol-function 'emacsvox-aural-voice-workbench--library-check-lanes) #'ignore))
        (setq emacsvox-aural-voice-workbench-view 'physical)
        (emacsvox-aural-voice-workbench--library-start)
        (setq source '(second))
        (emacsvox-aural-voice-workbench--library-start)
        (funcall (cadr callbacks) '(:index (:voices [(:engine_id "piper" :physical_id "old")])) nil)
        (should-not (emacsvox-aural-voice-workbench--library-index))
        (funcall (car callbacks) '(:index (:voices [])) nil)
        (should (equal [] (plist-get (emacsvox-aural-voice-workbench--library-index) :voices)))))))

(ert-deftest emacsvox-aural-voice-workbench-library-status-replies-stay-correlated ()
  (emacsvox-test--with-voice-workbench
    (let ((worker (make-pipe-process :name "status correlation fixture" :noquery t))
          receive timeout (count 0))
      (unwind-protect
          (let ((tts-speaker-process worker) (tts-notify-process nil))
            (process-put worker omnivox--control-inventory-property '(:inventory_generation 12))
            (setq emacsvox-aural-voice-workbench-view 'physical)
            (cl-letf (((symbol-function 'omnivox--process-supports-p) (lambda (&rest _) t))
                      ((symbol-function 'run-at-time) (lambda (_time _repeat callback) (setq timeout callback) nil))
                      ((symbol-function 'omnivox--send-control-request)
                       (lambda (_process request callback)
                         (should (equal request '(:type "voice_library_status_v1")))
                         (cl-incf count) (setq receive callback) count)))
              (emacsvox-aural-voice-workbench--library-check-lanes)
              (emacsvox-aural-voice-workbench--library-check-lanes)
              (should (= count 1))
              (funcall receive worker '(:type "voice_library_status_v1" :inventory_generation 11))
              (should-not (plist-get (alist-get 'main emacsvox-aural-voice-workbench--library-lanes) :status))
              (process-put worker omnivox--control-inventory-property '(:inventory_generation 13))
              (emacsvox-aural-voice-workbench--library-check-lanes)
              (should (= count 2))
              (funcall timeout)
              ;; A response after the deadline cannot promote Unknown to Active.
              (funcall receive worker '(:type "voice_library_status_v1" :inventory_generation 13))
              (should-not (plist-get (alist-get 'main emacsvox-aural-voice-workbench--library-lanes) :status))
              (process-put worker omnivox--control-inventory-property '(:inventory_generation 14))
              (emacsvox-aural-voice-workbench--library-check-lanes)
              (funcall receive worker '(:type "voice_library_status_v1" :inventory_generation 14
                                        :configuration :null :eligible_voices []))
              (should (equal 14 (plist-get (plist-get (alist-get 'main emacsvox-aural-voice-workbench--library-lanes) :status) :inventory_generation)))
              (emacsvox-aural-voice-workbench--library-stop)))
        (when (process-live-p worker) (delete-process worker))))))

(ert-deftest emacsvox-aural-voice-workbench-library-uses-each-lanes-health ()
  "Real normalization must use notification inventory even from compiled code."
  (emacsvox-test--with-voice-workbench
    (let* ((main (make-pipe-process :name "health main fixture" :noquery t))
           (notify (make-pipe-process :name "health notify fixture" :noquery t))
           (tts-speaker-process main) (tts-notify-process notify)
           (raw '(:inventory_generation 12
                  :engines [(:id "eloquence" :display_name "Eloquence"
                                 :availability (:status "available") :health (:status "healthy")
                                 :voices [(:id (:engine_id "eloquence" :voice_id "eci:Reed")
                                               :display_name "Reed" :availability (:status "available"))])]))
           (other (copy-tree raw t))
           (omnivox-engine-inventory raw)
           (status '(:type "voice_library_status_v1" :configuration :null
                     :inventory_generation 12
                     :eligible_voices [(:engine_id "eloquence" :voice_id "eci:Reed")])))
      (unwind-protect
          (progn
            (setf (plist-get (aref (plist-get other :engines) 0) :health) '(:status "failed"))
            (process-put main omnivox--control-inventory-property raw)
            (process-put notify omnivox--control-inventory-property other)
            (setq emacsvox-aural-voice-workbench-view 'physical
                  emacsvox-aural-voice-workbench--library-lanes
                  (list (cons 'main (list :process main :generation 12 :status status))
                        (cons 'notification (list :process notify :generation 12 :status status))))
            (should (eq 'yes (emacsvox-aural-voice-workbench--library-active '("eloquence" "eci:Reed") 'main)))
            (should (eq 'no (emacsvox-aural-voice-workbench--library-active '("eloquence" "eci:Reed") 'notification)))
            (let ((normalize (symbol-function 'omnivox-voice-inventory)) (count 0))
              (cl-letf (((symbol-function 'omnivox-voice-inventory)
                         (lambda () (cl-incf count) (funcall normalize))))
                (dotimes (_ 10)
                  (emacsvox-aural-voice-workbench--library-active '("eloquence" "eci:Reed") 'notification))
                (should (<= count 1)))))
        (delete-process main) (delete-process notify)))))

(defun emacsvox-test--language-inventory ()
  "Return voices whose names, tags and unknown languages exercise grouping."
  (let* ((inventory (copy-tree emacsvox-test--workbench-inventory))
         (engine (car (plist-get inventory :engines))))
    (setf (plist-get inventory :engines) (list engine)
          (plist-get engine :voices)
          (mapcar (lambda (entry)
                    (list :engine-id "eloquence" :voice-id (nth 0 entry)
                          :display-name (nth 1 entry) :language (nth 2 entry)
                          :availability "available"))
                  '(("z" "Zoe" "en_US") ("a" "alice" "EN-us")
                    ("fr" "Brigitte" "fr-FR") ("unknown" "No language" nil)
                    ("rare" "Rare language" "zz-ZZ"))))
    inventory))

(defun emacsvox-test--espeak-language-inventory ()
  "Return native-style eSpeak names and language tags."
  (let* ((inventory (copy-tree emacsvox-test--workbench-inventory))
         (engine (car (plist-get inventory :engines))))
    (setf (plist-get inventory :engines) (list engine)
          (plist-get engine :engine-id) "espeak"
          (plist-get engine :display-name) "eSpeak NG"
          (plist-get engine :voices)
          (mapcar (lambda (entry)
                    (list :engine-id "espeak" :voice-id (nth 0 entry)
                          :display-name (nth 1 entry) :language (nth 2 entry)
                          :availability "available"))
                  '(("de" "German" "de") ("gb" "English (Great Britain)" "en-gb")
                    ("midlands" "English (West Midlands)" "en-gb-x-gbcwmd")
                    ("lancaster" "English (Lancaster)" "en-gb-x-gbclan")
                    ("us" "English (America)" "en-us")
                    ("nyc" "English (America, New York City)" "en-us-nyc"))))
    inventory))

(ert-deftest emacsvox-aural-workbench-espeak-tree-and-singletons ()
  "Single voices are direct rows; English retains independently folded regions."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--espeak-language-inventory))
           (tts-voice-inventory-function (lambda () inventory)))
      (emacsvox-aural-voice-workbench--switch 'physical)
      (should (equal (mapcar #'car tabulated-list-entries)
                     '((:language "en") ("espeak" "de"))))
      (emacsvox-aural-ui-goto-row '(:language "en"))
      (emacsvox-aural-voice-workbench-open-row)
      (should (equal (mapcar #'car tabulated-list-entries)
                     '((:language "en") (:language "en-gb") (:language "en-us") ("espeak" "de"))))
      (emacsvox-aural-ui-goto-row '(:language "en-gb"))
      (emacsvox-aural-voice-workbench-open-row)
      (should (assoc '("espeak" "midlands") tabulated-list-entries))
      (should-not (assoc '("espeak" "nyc") tabulated-list-entries))
      (should-not (string-search "GBCWMD" (buffer-string)))
      (dolist (descending '(nil t))
        (setq tabulated-list-sort-key (cons "Physical voice" descending))
        (emacsvox-aural-voice-workbench-refresh)
        (should (equal (seq-take (mapcar #'car tabulated-list-entries) 2)
                       '((:language "en") (:language "en-gb"))))
        (should (equal (nth 5 (mapcar #'car tabulated-list-entries)) '(:language "en-us"))))
      (emacsvox-aural-ui-goto-row '(:language "en"))
      (emacsvox-aural-voice-workbench-open-row)
      (should-not (assoc '("espeak" "midlands") tabulated-list-entries))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_ choices &rest _)
                   (car (seq-find (lambda (entry) (equal (cdr entry) '("espeak" "midlands"))) choices)))))
        (emacsvox-aural-voice-workbench-find-voice))
      (should (equal (tabulated-list-get-id) '("espeak" "midlands")))
      (should (assoc '(:language "en-gb") tabulated-list-entries))
      (should-not (assoc '("espeak" "nyc") tabulated-list-entries)))))

(ert-deftest emacsvox-aural-workbench-graphical-quit-unwinds-voice-browser ()
  "Repeated q reaches the original buffer rather than restoring voice windows."
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-voice-workbench
    (let ((browser (current-buffer))
          (origin (generate-new-buffer " *voice quit origin*"))
          (manager (generate-new-buffer " *voice quit manager*")) details voices)
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (switch-to-buffer origin)
            (insert "Retained draft")
            (goto-char 5)
            (emacsvox-aural-ui--pop-to-buffer browser #'ignore)
            (emacsvox-aural-voice-workbench-engine-view)
            (emacsvox-aural-ui-goto-row "eloquence")
            (with-current-buffer manager (emacsvox-omnivox-components-mode))
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--manager-buffer) (lambda (&rest _) manager))
                      ((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                      ((symbol-function 'emacsvox-omnivox-components--request-records) #'ignore))
              (emacsvox-aural-voice-workbench-open-row)
              (setq details (current-buffer))
              (emacsvox-aural-ui-goto-row 'voices)
              (execute-kbd-macro (kbd "RET"))
              (setq voices (current-buffer))
              (execute-kbd-macro (kbd "q"))
              (should (eq (current-buffer) details))
              (should-not (get-buffer-window voices))
              (execute-kbd-macro (kbd "q"))
              (should (eq (current-buffer) browser))
              (execute-kbd-macro (kbd "q"))
              (redisplay t)
              (should (eq (current-buffer) origin))
              (should (= (point) 5))
              (should (equal (buffer-string) "Retained draft"))))
        (dolist (buffer (list voices details manager origin))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-workbench-graphical-espeak-tree-navigation ()
  "Nested expansion, exact preview and background refresh work in a real frame."
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--espeak-language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (browser (current-buffer))
           (draft (generate-new-buffer " *espeak tree draft*")) previews)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer browser)
            (emacsvox-aural-voice-workbench--switch 'physical)
            (cl-letf (((symbol-function 'tts-preview-voices)
                       (lambda (entries _callback) (push entries previews))))
              (execute-kbd-macro (kbd "RET <down> RET"))
              (should (equal (tabulated-list-get-id) '(:language "en-gb")))
              (should-not previews)
              (should (emacsvox-aural-ui-goto-row '("espeak" "midlands")))
              (redisplay t)
              (should (pos-visible-in-window-p (point)))
              (should (string-prefix-p "    English (West Midlands)" (aref (tabulated-list-get-entry) 0)))
              (execute-kbd-macro (kbd "RET"))
              (should (equal "midlands" (plist-get (plist-get (car (last (car previews))) :selector) :voice-id)))
              (switch-to-buffer draft)
              (insert "Unsubmitted draft")
              (with-current-buffer browser (emacsvox-aural-voice-workbench-refresh))
              (redisplay t)
              (should (eq (window-buffer (selected-window)) draft))
              (should (equal (buffer-string) "Unsubmitted draft"))
              (switch-to-buffer browser)
              (should (equal (tabulated-list-get-id) '("espeak" "midlands")))
              (emacsvox-aural-ui-goto-row '(:language "en-gb"))
              (execute-kbd-macro (kbd "RET"))
              (should-not (assoc '("espeak" "midlands") tabulated-list-entries))
              (should (equal (tabulated-list-get-id) '(:language "en-gb")))))
        (kill-buffer draft)))))

(ert-deftest emacsvox-aural-workbench-languages-toggle-and-preview-exact-voice ()
  "Return expands groups or previews the selected voice without changing data."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (saved (copy-tree emacsvox-aural-voice-workbench-staged-profile))
           previews tuned)
      (emacsvox-aural-voice-workbench--switch 'physical)
      (should (equal (mapcar #'car tabulated-list-entries)
                     '((:language "en-us") ("eloquence" "fr") ("eloquence" "unknown") ("eloquence" "rare"))))
      (should (string-search "English, United States" (aref (tabulated-list-get-entry) 0)))
      (should (equal (aref (tabulated-list-get-entry) 1) "2 voices; collapsed"))
      (cl-letf (((symbol-function 'tts-preview-voices) (lambda (entries _callback) (push entries previews)))
                ((symbol-function 'tts-restart) (lambda () (ert-fail "Grouping restarted speech")))
                ((symbol-function 'customize-save-variable) (lambda (&rest _) (ert-fail "Grouping saved configuration")))
                ((symbol-function 'emacsvox-aural-voice-editor-experiment)
                 (lambda (pair &rest _) (setq tuned pair))))
        (should-error (call-interactively (key-binding (kbd "P"))) :type 'user-error)
        (should-error (call-interactively (key-binding (kbd "+"))) :type 'user-error)
        (should-error (call-interactively (key-binding (kbd "t"))) :type 'user-error)
        (call-interactively (key-binding (kbd "A")))
        (should (equal (mapcar (lambda (entry) (plist-get (plist-get entry :selector) :voice-id)) (car previews))
                       '("fr" "fr" "unknown" "unknown" "rare" "rare")))
        (setq previews nil)
        (call-interactively (key-binding (kbd "RET")))
        (should-not previews)
        (should (equal (tabulated-list-get-id) '(:language "en-us")))
        (should (equal (seq-take (mapcar #'car tabulated-list-entries) 3)
                       '((:language "en-us") ("eloquence" "a") ("eloquence" "z"))))
        (emacsvox-aural-ui-goto-row '("eloquence" "z"))
        (call-interactively (key-binding (kbd "RET")))
        (should (equal (plist-get (plist-get (car (last (car previews))) :selector) :voice-id) "z"))
        (should (equal (tabulated-list-get-id) '("eloquence" "z")))
        (call-interactively (key-binding (kbd "t")))
        (should (equal (plist-get (cadr tuned) :voice-id) "z"))
        (emacsvox-aural-ui-goto-row '(:language "en-us"))
        (call-interactively (key-binding (kbd "RET")))
        (emacsvox-aural-voice-workbench-refresh)
        (should (= 4 (length tabulated-list-entries)))
        (should (equal (aref (tabulated-list-get-entry) 1) "2 voices; collapsed"))
        (should (equal saved emacsvox-aural-voice-workbench-staged-profile))))))

(ert-deftest emacsvox-aural-workbench-language-sorting-and-bulk-preview ()
  "Both column directions keep groups together and preview only visible voices."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory)) previews)
      (emacsvox-aural-voice-workbench--switch 'physical)
      (emacsvox-aural-ui-goto-row '(:language "en-us"))
      (call-interactively (key-binding (kbd "RET")))
      (dolist (descending '(nil t))
        (setq tabulated-list-sort-key (cons "Physical voice" descending))
        (emacsvox-aural-voice-workbench-refresh)
        (should (equal (seq-take (mapcar #'car tabulated-list-entries) 4)
                       (append '((:language "en-us"))
                               (if descending '(("eloquence" "z") ("eloquence" "a"))
                                 '(("eloquence" "a") ("eloquence" "z")))
                               '(("eloquence" "fr")))))
        (cl-letf (((symbol-function 'tts-preview-voices) (lambda (entries _callback) (setq previews entries))))
          (call-interactively (key-binding (kbd "A"))))
        (should (equal (mapcar (lambda (entry) (plist-get (plist-get entry :selector) :voice-id)) previews)
                       (append (if descending '("z" "z" "a" "a") '("a" "a" "z" "z"))
                               '("fr" "fr" "unknown" "unknown" "rare" "rare")))))
      (setq tabulated-list-sort-key '("Engine" . t))
      (emacsvox-aural-voice-workbench-refresh)
      (should (equal (car (car tabulated-list-entries)) '(:language "en-us"))))))

(ert-deftest emacsvox-aural-workbench-language-selection-follows-metadata-and-filter ()
  "Selection survives a language correction; hidden voices remain browsable."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (voice (cadr (plist-get (car (plist-get inventory :engines)) :voices))))
      (setq emacsvox-aural-voice-workbench-view 'physical)
      (emacsvox-aural-voice-workbench-refresh '("eloquence" "a"))
      (emacsvox-aural-ui-goto-tabulated-column 2)
      (setf (plist-get voice :language) "fr-FR")
      (emacsvox-aural-voice-workbench-refresh)
      (should (equal (tabulated-list-get-id) '("eloquence" "a")))
      (should (= 2 (emacsvox-aural-ui-tabulated-column-index)))
      (should (string-suffix-p "expanded" (aref (cadr (assoc '(:language "fr-fr") tabulated-list-entries)) 1)))
      (setq emacsvox-aural-voice-workbench-filter '(:language "zz-ZZ"))
      (emacsvox-aural-voice-workbench-refresh)
      (should (equal (mapcar #'car tabulated-list-entries) '(("eloquence" "rare"))))
      (should (emacsvox-aural-ui-goto-row '("eloquence" "rare"))))))

(ert-deftest emacsvox-aural-workbench-language-download-retains-engine-scope ()
  "A language heading does not become an engine ID for voice downloads."
  (require 'omnivox-catalogue)
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-voice-workbench-engine-view)
    (emacsvox-aural-ui-goto-row "eloquence")
    (emacsvox-aural-voice-workbench-physical-view)
    (emacsvox-aural-ui-goto-row '(:language "en-au"))
    (let (engine)
      (cl-letf (((symbol-function 'omnivox-catalogue) (lambda (id) (setq engine id))))
        (call-interactively (key-binding (kbd "d"))))
      (should (equal engine "eloquence")))))

(ert-deftest emacsvox-aural-workbench-graphical-language-navigation-and-refresh ()
  "Spoken group navigation and silent refresh preserve the actual GUI focus."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-tabulated-list)
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (browser (current-buffer))
           (draft (generate-new-buffer " *language draft*")) spoken previews)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer browser)
            (emacsvox-aural-voice-workbench--switch 'physical)
            (cl-letf (((symbol-function 'tts-preview-voices) (lambda (entries _callback) (push entries previews)))
                      ((symbol-function 'tts-speak) (lambda (text) (push (substring-no-properties text) spoken)))
                      ((symbol-function 'emacsvox-aural-submit)
                       (lambda (text &rest _) (push (substring-no-properties text) spoken))))
              (execute-kbd-macro (kbd "RET"))
              (should-not previews)
              (dolist (step '(("<down>" ("eloquence" "a") "alice")
                              ("<up>" (:language "en-us") "2 voices; expanded")))
                (setq spoken nil)
                (execute-kbd-macro (kbd (car step)))
                (should (equal (tabulated-list-get-id) (nth 1 step)))
                (should (= 1 (length spoken)))
                (should (string-search (nth 2 step) (car spoken))))
              (execute-kbd-macro (kbd "<down> RET"))
              (should (= 1 (length previews)))
              (execute-kbd-macro (kbd "<right>"))
              (switch-to-buffer draft)
              (insert "Unsubmitted draft")
              (setq spoken nil)
              (with-current-buffer browser (emacsvox-aural-voice-workbench-refresh))
              (redisplay t)
              (should (eq (window-buffer (selected-window)) draft))
              (should (equal (buffer-string) "Unsubmitted draft"))
              (should-not spoken)
              (switch-to-buffer browser)
              (should (equal (tabulated-list-get-id) '("eloquence" "a")))
              (should (= 1 (emacsvox-aural-ui-tabulated-column-index)))
              (should (= (point) (window-point)))
              (should (pos-visible-in-window-p (point)))
              (execute-kbd-macro (kbd "<left> <up> RET"))
              (should (equal (tabulated-list-get-id) '(:language "en-us")))
              (should (= 4 (length tabulated-list-entries)))
              (should (= 1 (length previews)))))
        (kill-buffer draft)))))

(defun emacsvox-test--browser-library ()
  "Return downloaded, imported and bundled voices for browser checks."
  '(:target_id "target" :profile_id "profile" :disabled_physical_ids []
    :packages [(:package_id "download" :revision_id "r" :ownership "managed"
                            :catalogue (:entry_id "fixture" :revision "1"))
               (:package_id "import" :revision_id "r" :ownership "imported" :catalogue :null)]
    :voices [(:engine_id "eloquence" :physical_id "a" :display_name "alice" :language "en-US"
                        :enabled t :package_id "download" :revision_id "r")
             (:engine_id "eloquence" :physical_id "fr" :display_name "Brigitte" :language "fr-FR"
                         :enabled :false :package_id "download" :revision_id "r")
             (:engine_id "eloquence" :physical_id "unknown" :display_name "No language" :language :null
                         :enabled t :package_id "import" :revision_id "r")
             (:engine_id "eloquence" :physical_id "z" :display_name "Zoe" :language "en-US"
                         :enabled t :package_id :null :revision_id :null)]))

(ert-deftest emacsvox-aural-workbench-quick-filter-counts-and-search ()
  "Filters count hidden voices, retain selection, and find excluded downloads."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (index (emacsvox-test--browser-library)) spoken)
      (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--library-index) (lambda () index))
                ((symbol-function 'emacsvox-aural-ui-speak) (lambda (text) (push text spoken))))
        (setq emacsvox-aural-voice-workbench-view 'physical)
        (emacsvox-aural-voice-workbench-refresh)
        (should (= 4 (length tabulated-list-entries))) ; all groups collapsed
        (should (= 5 (alist-get 'all emacsvox-aural-voice-workbench--filter-counts)))
        (should (= 2 (alist-get 'downloaded emacsvox-aural-voice-workbench--filter-counts)))
        (should (= 3 (alist-get 'enabled emacsvox-aural-voice-workbench--filter-counts)))
        (should (equal "Needs Apply: 0; 4 unchecked" (emacsvox-aural-voice-workbench--quick-description 'needs-apply)))
        (emacsvox-aural-voice-workbench-refresh '("eloquence" "z"))
        (emacsvox-aural-ui-goto-tabulated-column 2)
        (let ((last-command-event ?2))
          (call-interactively (key-binding (kbd "2"))))
        (should (equal 'downloaded emacsvox-aural-voice-workbench--quick-filter))
        (should (= 2 (length (emacsvox-aural-voice-workbench--detail-entries))))
        (emacsvox-aural-voice-workbench-refresh '("eloquence" "fr"))
        (emacsvox-aural-ui-goto-tabulated-column 1)
        (emacsvox-aural-voice-workbench-quick-filter 'all)
        (should (equal '("eloquence" "z") (tabulated-list-get-id)))
        (should (= 2 (emacsvox-aural-ui-tabulated-column-index)))
        (emacsvox-aural-voice-workbench-quick-filter 'downloaded)
        (should (equal '("eloquence" "fr") (tabulated-list-get-id)))
        (should (= 1 (emacsvox-aural-ui-tabulated-column-index)))
        (emacsvox-aural-voice-workbench-quick-filter 'enabled)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt choices &rest _)
                     (should (= 5 (length choices)))
                     (car (seq-find (lambda (entry) (equal (cdr entry) '("eloquence" "fr"))) choices)))))
          (call-interactively (key-binding (kbd "/"))))
        (should (eq 'all emacsvox-aural-voice-workbench--quick-filter))
        (should (equal '("eloquence" "fr") (tabulated-list-get-id)))
        (should (equal "No" (aref (tabulated-list-get-entry) 4)))
        (should-not (assoc '(:language "fr-fr") tabulated-list-entries))
        (setq emacsvox-aural-voice-workbench-filter '(:language "fr-FR"))
        (emacsvox-aural-voice-workbench-refresh)
        (should (= 1 (alist-get 'all emacsvox-aural-voice-workbench--filter-counts)))
        (let ((last-command-event ?Q))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt choices &rest _)
                       (should (equal (mapcar #'car choices)
                                      '("All voices: 1" "Downloaded: 1" "Enabled: 0" "Needs Apply: 0; 1 unchecked")))
                       (caar choices))))
            (call-interactively (key-binding (kbd "Q")))))
        (emacsvox-aural-voice-workbench-quick-filter 'enabled)
        (should-not tabulated-list-entries)
        (should (string-search "No matching voices" (car spoken)))
        (emacsvox-aural-voice-workbench-clear-filters)
        (should (= 5 (alist-get 'all emacsvox-aural-voice-workbench--filter-counts)))))))

(ert-deftest emacsvox-aural-workbench-filters-check-target-once-per-redraw ()
  "Counts and row status must not multiply filesystem checks per voice."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (checks 0))
      (setq emacsvox-aural-voice-workbench-view 'physical
            emacsvox-aural-voice-workbench--library-source '(fixture)
            emacsvox-aural-voice-workbench--library-reply
            (list :index (emacsvox-test--browser-library)))
      (cl-letf (((symbol-function 'omnivox-library--source-key)
                 (lambda () (cl-incf checks) '(fixture))))
        (emacsvox-aural-voice-workbench-refresh)
        (should (= 1 checks))
        (should (= 5 (alist-get 'all emacsvox-aural-voice-workbench--filter-counts)))))))

(ert-deftest emacsvox-aural-workbench-needs-apply-uses-current-administrative-state ()
  "Check desired changes, worker replacement, policy, health and target identity."
  (emacsvox-test--with-voice-workbench
    (let* ((index (copy-tree (emacsvox-test--browser-library) t))
           (row (aref (plist-get index :voices) 0))
           (main (make-pipe-process :name "quick filter main" :noquery t))
           (notify (make-pipe-process :name "quick filter notify" :noquery t))
           (tts-speaker-process main) (tts-notify-process notify)
           (raw '(:inventory_generation 12 :routing_policy (:policy (:disabled_engine_ids []))))
           (status '(:configuration (:target_id "target" :profile_id "profile")
                     :overridden_engines [] :eligible_voices [(:engine_id "eloquence" :voice_id "a")])))
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--library-index) (lambda () index)))
            (dolist (entry (list (cons 'main main) (cons 'notification notify)))
              (process-put (cdr entry) omnivox--control-inventory-property (copy-tree raw t))
              (setf (alist-get (car entry) emacsvox-aural-voice-workbench--library-lanes)
                    (list :process (cdr entry) :generation 12 :status (copy-tree status t))))
            (should (eq 'no (emacsvox-aural-voice-workbench--needs-apply row)))
            ;; Health failures must not manufacture a pending selection change.
            (process-put main omnivox--control-inventory-property
                         (append '(:engines [(:id "eloquence" :health (:status "failed"))]) raw))
            (should (eq 'no (emacsvox-aural-voice-workbench--needs-apply row)))
            (let ((other (plist-get (alist-get 'notification emacsvox-aural-voice-workbench--library-lanes) :status)))
              (setf (plist-get other :eligible_voices) [])
              (should (eq 'yes (emacsvox-aural-voice-workbench--needs-apply row)))
              ;; A disabled engine's missing eligibility is not a pending enable.
              (process-put notify omnivox--control-inventory-property
                           '(:inventory_generation 12 :routing_policy (:policy (:disabled_engine_ids ["eloquence"]))))
              (should (eq 'no (emacsvox-aural-voice-workbench--needs-apply row)))
              (process-put notify omnivox--control-inventory-property raw)
              (setf (plist-get other :overridden_engines) ["eloquence"])
              (should (eq 'unknown (emacsvox-aural-voice-workbench--needs-apply row)))
              (setf (plist-get other :overridden_engines) []
                    (plist-get other :configuration) '(:target_id "different" :profile_id "profile"))
              (should (eq 'unknown (emacsvox-aural-voice-workbench--needs-apply row)))
              (setf (plist-get other :configuration) :null)
              (should (eq 'yes (emacsvox-aural-voice-workbench--needs-apply row))))
            ;; Disabling a currently eligible voice also needs Apply.
            (setf (plist-get row :enabled) :false)
            (should (eq 'yes (emacsvox-aural-voice-workbench--needs-apply row)))
            (process-put main omnivox--control-inventory-property '(:inventory_generation 13))
            (should (eq 'unknown (emacsvox-aural-voice-workbench--needs-apply row)))
            (let ((tts-speaker-process notify))
              (should (eq 'unknown (emacsvox-aural-voice-workbench--needs-apply row))))
            (setq emacsvox-aural-voice-workbench--library-ticket '(pending))
            (should (eq 'unknown (emacsvox-aural-voice-workbench--needs-apply row))))
        (delete-process main) (delete-process notify)))))

(ert-deftest emacsvox-aural-workbench-graphical-filter-search-and-editor-return ()
  "Searching a folded language and returning from the editor retains GUI focus."
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-voice-workbench
    (let* ((inventory (emacsvox-test--language-inventory))
           (tts-voice-inventory-function (lambda () inventory))
           (browser (current-buffer))
           (emacsvox-aural-voice-editor--contexts (make-hash-table :test #'equal))
           (emacsvox-aural-voice-drafts--registry (make-hash-table :test #'equal))
           editor)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer browser)
            (emacsvox-aural-voice-workbench--switch 'physical)
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt choices &rest _)
                         (car (seq-find (lambda (entry) (equal (cdr entry) '("eloquence" "fr"))) choices))))
                      ((symbol-function 'tts-preview-voices) (lambda (&rest _))))
              (execute-kbd-macro (kbd "/"))
              (should (equal '("eloquence" "fr") (tabulated-list-get-id)))
              (should (pos-visible-in-window-p (point)))
              (execute-kbd-macro (kbd "<right> t"))
              (setq editor (current-buffer))
              (should (derived-mode-p 'emacsvox-aural-voice-editor-mode))
              (with-current-buffer browser (emacsvox-aural-voice-workbench-refresh))
              (should (eq (window-buffer (selected-window)) editor))
              (execute-kbd-macro (kbd "q"))
              (redisplay t)
              (should (eq (current-buffer) browser))
              (should (eq (window-buffer (selected-window)) browser))
              (should (equal '("eloquence" "fr") (tabulated-list-get-id)))
              (should (= 1 (emacsvox-aural-ui-tabulated-column-index)))
              (should (= (point) (window-point)))
              (should (pos-visible-in-window-p (point)))))
        (when (buffer-live-p editor) (kill-buffer editor))))))

(provide 'emacsvox-aural-voice-workbench-tests)
;;; emacsvox-aural-voice-workbench-tests.el ends here
