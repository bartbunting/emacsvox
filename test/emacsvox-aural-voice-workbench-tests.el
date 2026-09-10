;;; emacsvox-aural-voice-workbench-tests.el --- Workbench UI tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify spoken cross-synth inventory and routing views.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-voice-workbench)

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
    (should (= (length tabulated-list-entries) 2))
    (emacsvox-aural-voice-workbench-engine-view)
    (should (= (length tabulated-list-entries) 2))
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
  "Engine rows expose audio, markers, failure, cooldown, and circuit state."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'engines)
    (emacsvox-aural-voice-workbench-refresh "winrt")
    (let ((spoken (emacsvox-aural-voice-workbench-speak-current)))
      (should (string-match-p "buffered_pcm" spoken))
      (should (string-match-p "helper exited" spoken))
      (should (string-match-p "750 ms" spoken))
      (should (string-match-p "word-boundary" spoken)))))

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
     (equal (car (car tabulated-list-entries)) '("winrt" "David")))
    (setq emacsvox-aural-voice-workbench-filter '(:gender "female"))
    (emacsvox-aural-voice-workbench-refresh)
    (should-not tabulated-list-entries)))

(ert-deftest emacsvox-aural-voice-workbench-shows-physical-voice-users ()
  "Physical inventory identifies matching staged logical routes."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'physical)
    (emacsvox-aural-voice-workbench-refresh '("eloquence" "eci:Reed"))
    (let ((entry (tabulated-list-get-entry)))
      (should (string-match-p "\\bbolden\\b" (aref entry 7))))))

(ert-deftest emacsvox-aural-voice-workbench-shows-portable-and-realized-identity ()
  "Logical rows put palette aliases, requested style, route, and result together."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "bolden"))
    (let ((entry (tabulated-list-get-entry)))
      (should (equal (aref entry 0) "workbench-test"))
      (should (string-match-p "bolden" (aref entry 1)))
      (should (equal (aref entry 2) "bolden"))
      (should (string-match-p "eci:Reed" (aref entry 4)))
      (should (equal (aref entry 5) "eloquence/eci:Reed")))))

(ert-deftest emacsvox-aural-voice-workbench-shows-last-played-route ()
  "Logical rows distinguish predicted routing from playback observation."
  (emacsvox-test--with-voice-workbench
    (let ((tts-last-realized-voice-function
           (lambda (_logical)
             '(:engine-id "dectalk" :voice-id "paul"
               :degraded-acss ("richness") :degraded-effects nil))))
      (emacsvox-aural-voice-workbench-refresh "bolden")
      (let ((entry (tabulated-list-get-entry)))
        (should (equal (aref entry 5) "eloquence/eci:Reed"))
        (should
         (equal (aref entry 6) "dectalk/paul omitted richness"))))))

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
  "Engine RET filters physical voices and preserves the engine's selected column."
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-voice-workbench--switch 'engines)
    (emacsvox-aural-ui-goto-row "eloquence")
    (emacsvox-aural-ui-goto-tabulated-column 2)
    (setq emacsvox-aural-voice-workbench-filter '(:language "en-AU"))
    (emacsvox-aural-voice-workbench-open-row)
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
    (call-interactively (key-binding (kbd "RET")))
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
        (call-interactively (key-binding (kbd "RET")))
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
    (emacsvox-aural-voice-workbench-open-row)
    (should (equal (tabulated-list-get-id) '("winrt" "David")))
    (call-interactively (key-binding (kbd "v")))
    (should (equal (tabulated-list-get-id) '("eloquence" "eci:Reed")))
    (should (equal emacsvox-aural-voice-workbench-filter
                   '(:engine "eloquence" :gender "male")))
    (emacsvox-aural-voice-workbench-engine-view)
    (emacsvox-aural-voice-workbench-open-row)
    (call-interactively (key-binding (kbd "C")))
    (should (= (length tabulated-list-entries) 2))
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
        (call-interactively (key-binding (kbd "RET")))
        (call-interactively (key-binding (kbd "q")))
        (should-not quit)
        (should (emacsvox-aural-voice-workbench--dirty-p))
        (call-interactively (key-binding (kbd "q"))))
      (should quit)
      (should
       (string-match-p "Engine policy changes remain staged" spoken))
      (should (string-match-p "press w to save and apply" spoken)))))

(provide 'emacsvox-aural-voice-workbench-tests)
;;; emacsvox-aural-voice-workbench-tests.el ends here
