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
      :post-synthesis-dimensions (reverb echo)
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
  '(:schema-version 2 :id workstation :summary "Workbench profile"
    :engine-order ("eloquence" "winrt")
    :disabled-engines nil
    :fallback
    (:allow-same-language t :global-default nil :engines ("winrt"))
    :bindings
    ((:logical-voice voice-bolden :language "en-AU"
      :selectors
      ((:kind exact :scope local :engine-id "eloquence"
        :voice-id "eci:Reed")))))
  "Representative staged Workbench route.")

(defmacro emacsvox-test--with-voice-workbench (&rest body)
  "Run BODY in an isolated Voice Workbench buffer."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-routing-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-active-routing-profile 'workstation)
         (emacsvox-aural-session-routing-bindings nil)
         (emacsvox-aural-routing-profile-changed-hook nil)
         (emacsvox-aural-routing-apply-status nil)
         (emacsvox-aural-routing-apply-status-hook nil)
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
     (emacsvox-aural-register-routing-profile-data
      emacsvox-test--workbench-routing-profile "test")
     (with-temp-buffer
       (cl-letf (((symbol-function 'tts-speak) #'ignore))
         (emacsvox-aural-voice-workbench-mode)
         (emacsvox-aural-voice-workbench-refresh)
         ,@body))))

(ert-deftest emacsvox-aural-voice-workbench-provides-four-spoken-views ()
  "One shared UI exposes logical, physical, engine, and style/effect rows."
  (emacsvox-test--with-voice-workbench
    (should (eq emacsvox-aural-voice-workbench-view 'logical))
    (should (emacsvox-aural-ui-goto-row "voice-bolden"))
    (should
     (string-match-p "eci:Reed"
                     (emacsvox-aural-voice-workbench-speak-current)))
    (emacsvox-aural-voice-workbench-physical-view)
    (should (= (length tabulated-list-entries) 2))
    (emacsvox-aural-voice-workbench-engine-view)
    (should (= (length tabulated-list-entries) 2))
    (emacsvox-aural-voice-workbench-style-view)
    (should tabulated-list-entries)))

(ert-deftest emacsvox-aural-voice-workbench-stages-distinct-engine-orders ()
  "Preferred, fallback, and disabled policy lists remain independent."
  (emacsvox-test--with-voice-workbench
    (setq emacsvox-aural-voice-workbench-view 'engines)
    (emacsvox-aural-voice-workbench-refresh "eloquence")
    (emacsvox-aural-voice-workbench-move-selector-down)
    (should
     (equal
      (plist-get emacsvox-aural-voice-workbench-staged-profile :engine-order)
      '("winrt" "eloquence")))
    (emacsvox-aural-voice-workbench-toggle-fallback-engine)
    (emacsvox-aural-voice-workbench-move-fallback-engine-up)
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
      (should (string-match-p "\\bvoice-bolden\\b" (aref entry 7))))))

(ert-deftest emacsvox-aural-voice-workbench-shows-portable-and-realized-identity ()
  "Logical rows put palette aliases, requested style, route, and result together."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "voice-bolden"))
    (let ((entry (tabulated-list-get-entry)))
      (should (equal (aref entry 0) "acss-default"))
      (should (string-match-p "bolden" (aref entry 1)))
      (should (equal (aref entry 2) "voice-bolden"))
      (should (string-match-p "eci:Reed" (aref entry 4)))
      (should (equal (aref entry 5) "eloquence/eci:Reed")))))

(ert-deftest emacsvox-aural-voice-workbench-shows-last-played-route ()
  "Logical rows distinguish predicted routing from playback observation."
  (emacsvox-test--with-voice-workbench
    (let ((tts-last-realized-voice-function
           (lambda (_logical)
             '(:engine-id "dectalk" :voice-id "paul"
               :degraded-acss ("richness") :degraded-effects nil))))
      (emacsvox-aural-voice-workbench-refresh "voice-bolden")
      (let ((entry (tabulated-list-get-entry)))
        (should (equal (aref entry 5) "eloquence/eci:Reed"))
        (should
         (equal (aref entry 6) "dectalk/paul omitted richness"))))))

(ert-deftest emacsvox-aural-voice-workbench-stages-exact-assignment-and-undo ()
  "Filtered browsing adds a local exact selector and undo restores its snapshot."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "voice-annotate"))
    (emacsvox-aural-voice-workbench-begin-assignment)
    (should (eq emacsvox-aural-voice-workbench-view 'physical))
    (should (equal emacsvox-aural-voice-workbench-assignment-target
                   "voice-annotate"))
    (emacsvox-aural-voice-workbench-refresh '("winrt" "David"))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "exact installed voice, local to this machine"))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (emacsvox-aural-voice-workbench-complete-assignment))
    (should (eq emacsvox-aural-voice-workbench-view 'logical))
    (let* ((binding
            (emacsvox-aural-voice-workbench--profile-binding "voice-annotate"))
           (selector (car (plist-get binding :selectors))))
      (should (equal (plist-get binding :language) "en-US"))
      (should (eq (plist-get selector :kind) 'exact))
      (should (eq (plist-get selector :scope) 'local))
      (should (equal (plist-get selector :engine-id) "winrt"))
      (should (equal (plist-get selector :voice-id) "David")))
    (emacsvox-aural-voice-workbench-undo)
    (should-not
     (emacsvox-aural-voice-workbench--profile-binding "voice-annotate"))
    (should-not (emacsvox-aural-voice-workbench--dirty-p))))

(ert-deftest emacsvox-aural-voice-workbench-builds-portable-assignment-selectors ()
  "Physical candidates can become engine defaults or portable properties."
  (emacsvox-test--with-voice-workbench
    (let ((pair
           (emacsvox-aural-voice-workbench--physical-pair
            '("eloquence" "eci:Reed"))))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "portable engine default")))
        (should
         (equal
          (emacsvox-aural-voice-workbench--assignment-selector pair)
          '(:kind engine-default :scope portable :engine-id "eloquence"))))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "portable language and gender")))
        (should
         (equal
          (emacsvox-aural-voice-workbench--assignment-selector pair)
          '(:kind properties :scope portable :language "en-AU"
            :gender "male")))))))

(ert-deftest emacsvox-aural-voice-workbench-reorders-copies-and-deletes-routes ()
  "Fallback editing changes only the staged profile and remains undoable."
  (emacsvox-test--with-voice-workbench
    (emacsvox-aural-voice-workbench--replace-binding
     "voice-bolden"
     '((:kind exact :scope local :engine-id "eloquence"
        :voice-id "eci:Reed")
       (:kind engine-default :scope portable :engine-id "winrt")))
    (emacsvox-aural-voice-workbench-refresh "voice-bolden")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _)
                 "1. eloquence/eci:Reed [local]")))
      (emacsvox-aural-voice-workbench-move-selector-down))
    (should
     (equal
      (plist-get
       (car (emacsvox-aural-voice-workbench--explicit-selectors "voice-bolden"))
       :engine-id)
      "winrt"))
    (should (emacsvox-aural-ui-goto-row "voice-annotate"))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "voice-bolden"))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (emacsvox-aural-voice-workbench-copy-route))
    (should
     (equal
      (emacsvox-aural-voice-workbench--explicit-selectors "voice-annotate")
      (emacsvox-aural-voice-workbench--explicit-selectors "voice-bolden")))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "1. winrt default [portable]"))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (emacsvox-aural-voice-workbench-delete-selector))
    (should
     (= (length
         (emacsvox-aural-voice-workbench--explicit-selectors "voice-annotate"))
        1))))

(ert-deftest emacsvox-aural-voice-workbench-bulk-routing-is-explicit ()
  "Bulk mapping and engine replacement use one confirmed staged transaction."
  (emacsvox-test--with-voice-workbench
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "winrt"))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (emacsvox-aural-voice-workbench-bind-unmapped))
    (should
     (equal
      (plist-get
       (car (emacsvox-aural-voice-workbench--explicit-selectors
             "voice-annotate"))
       :engine-id)
      "winrt"))
    (let ((answers
           '("eloquence" "winrt"
             "convert exact voices to destination engine default")))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (pop answers)))
                ((symbol-function 'completing-read-multiple)
                 (lambda (&rest _) '("voice-bolden")))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (emacsvox-aural-voice-workbench-replace-engine)))
    (should
     (equal
      (car (emacsvox-aural-voice-workbench--explicit-selectors "voice-bolden"))
      '(:kind engine-default :scope portable :engine-id "winrt")))))

(ert-deftest emacsvox-aural-voice-workbench-suggestions-are-reviewed-and-undoable ()
  "An exact family alias remains staged with provenance until explicit save."
  (emacsvox-test--with-voice-workbench
    (let* ((inventory
            '(:adapter "omnivox" :source "live" :engines
              ((:engine-id "eloquence" :availability "available"
                :health "healthy" :default-voice-id "v1"
                :voices
                ((:engine-id "eloquence" :voice-id "v1"
                  :display-name "Adult male 1" :language "en-US"
                  :gender "male" :availability "available"))))))
           (tts-voice-inventory-function
            (lambda () (copy-tree inventory))))
      (cl-progv '(voice-annotate-settings) '((paul nil 4 0 4))
        (emacsvox-aural-voice-workbench-refresh "voice-annotate")
        (let ((suggestions
               (emacsvox-aural-voice-workbench--suggestions
                "voice-annotate")))
          (should (eq (plist-get (car suggestions) :reason) 'exact-alias))
          (should
           (equal
            (plist-get (plist-get (car suggestions) :selector) :voice-id)
            "v1")))
        (cl-letf
            (((symbol-function 'completing-read)
              (lambda (_prompt collection &rest _) (caar collection)))
             ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
          (emacsvox-aural-voice-workbench-suggest-route))))
    (let ((selector
           (car
            (emacsvox-aural-voice-workbench--explicit-selectors
             "voice-annotate"))))
      (should (eq (plist-get selector :kind) 'exact))
      (should (equal (plist-get selector :voice-id) "v1")))
    (should
     (eq (plist-get (car emacsvox-aural-voice-workbench-provenance) :kind)
         'suggested))
    (let ((entry (tabulated-list-get-entry)))
      (should (string-match-p "suggested" (aref entry 11))))
    (emacsvox-aural-voice-workbench-undo)
    (should-not
     (emacsvox-aural-voice-workbench--profile-binding "voice-annotate"))
    (should-not emacsvox-aural-voice-workbench-provenance)))

(ert-deftest emacsvox-aural-voice-workbench-migrates-palette-without-saving ()
  "Palette migration fills unmapped voices in one staged transaction only."
  (emacsvox-test--with-voice-workbench
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (emacsvox-aural-voice-workbench--migrate-active-palette))
    (should
     (emacsvox-aural-voice-workbench--profile-binding "voice-annotate"))
    (should (emacsvox-aural-voice-workbench--dirty-p))
    (should
     (eq (plist-get (car emacsvox-aural-voice-workbench-provenance) :kind)
         'imported))
    (should
     (equal
      (plist-get
       (car
        (emacsvox-aural-voice-workbench--explicit-selectors
         "voice-annotate"))
       :engine-id)
      "eloquence"))))

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
         "voice-bolden")
        "winrt/David"))
      (should
       (equal before emacsvox-aural-voice-workbench-staged-profile)))))

(ert-deftest emacsvox-aural-voice-workbench-keeps-reduced-adapters-navigable ()
  "Free-form and unsupported adapters retain logical editing without fake voices."
  (emacsvox-test--with-voice-workbench
    (dolist
        (inventory
         '((:adapter "mac" :source "free-form" :status "available"
            :generation 0 :stale nil :process-agreement "single-adapter"
            :engines
            ((:engine-id "mac" :display-name "Mac"
              :availability "available" :health "healthy" :voices nil)))
           (:adapter "plain" :source "unavailable" :status "unavailable"
            :generation 0 :stale nil :process-agreement "single-adapter"
            :engines
            ((:engine-id "plain" :display-name "Plain"
              :availability "unavailable" :health "unavailable"
              :voices nil)))))
      (let ((tts-voice-inventory-function
             (lambda () (copy-tree inventory))))
        (setq emacsvox-aural-voice-workbench-view 'logical)
        (emacsvox-aural-voice-workbench-refresh "voice-bolden")
        (should tabulated-list-entries)
        (should-not
         (emacsvox-aural-voice-workbench--suggestions "voice-annotate"))
        (setq emacsvox-aural-voice-workbench-view 'physical)
        (emacsvox-aural-voice-workbench-refresh)
        (should-not tabulated-list-entries)))))

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
       (equal (plist-get (car entries) :text)
              emacsvox-aural-voice-workbench-preview-text))
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
       (equal (delete-dups (mapcar (lambda (entry) (plist-get entry :text))
                                   entries))
              (list emacsvox-aural-voice-workbench-preview-text)))
      (should
       (equal
        (mapcar
         (lambda (entry)
           (plist-get (plist-get entry :selector) :kind))
         entries)
        '(exact exact))))))

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
              :rate 6 :average-pitch 4 :pitch-range nil :stress 2
              :richness 7 :gain 5 :low-pass 8 :high-pass 1 :pan 5
              :reverb 7 :echo 3))))
      (let* ((entry
              (emacsvox-aural-voice-workbench--logical-preview-entry
               "voice-annotate"))
             (selector (plist-get entry :selector))
             (acss (plist-get entry :acss))
             (effects (plist-get entry :effects)))
        (should (eq (plist-get selector :kind) 'engine-default))
        (should (eq (plist-get selector :scope) 'session))
        (should (equal (plist-get selector :engine-id) "eloquence"))
        (should (= (plist-get acss :rate) (/ 6.0 9.0)))
        (should (= (plist-get acss :average-pitch) (/ 4.0 9.0)))
        (should-not (plist-member acss :pitch-range))
        (should (= (plist-get effects :low-pass) (/ 8.0 9.0)))
        (should (= (plist-get effects :high-pass) (/ 1.0 9.0)))
        (should (= (plist-get effects :reverb) (/ 7.0 9.0)))
        (should (= (plist-get effects :echo) (/ 3.0 9.0)))))))

(ert-deftest emacsvox-aural-voice-workbench-opens-route-aware-tuner ()
  "Logical tuning passes the staged selector and realized engine unchanged."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "voice-bolden"))
    (let (arguments)
      (cl-letf
          (((symbol-function
             'emacsvox-aural-voice-workbench--editable-palette)
            (lambda (palette _logical) palette))
           ((symbol-function 'emacsvox-aural-voice-tuner-open)
            (lambda (&rest values) (setq arguments values))))
        (emacsvox-aural-voice-workbench-tune))
      (should (eq (nth 0 arguments) 'acss-default))
      (should (eq (nth 1 arguments) 'bolden))
      (let ((selector (plist-get (nthcdr 4 arguments) :selector))
            (engine (plist-get (nthcdr 4 arguments) :engine))
            (realized (plist-get (nthcdr 4 arguments) :realized)))
        (should (eq (plist-get selector :kind) 'exact))
        (should (equal (plist-get selector :voice-id) "eci:Reed"))
        (should (equal (plist-get engine :engine-id) "eloquence"))
        (should
         (equal realized
                '(:engine-id "eloquence" :voice-id "eci:Reed")))))))

(ert-deftest emacsvox-aural-voice-workbench-tunes-unrouted-voice-on-default ()
  "An unrouted logical voice auditions without persisting a route."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "voice-annotate"))
    (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                     :engine-order)
          nil)
    (let ((before
           (copy-tree emacsvox-aural-voice-workbench-staged-profile))
          arguments)
      (cl-letf
          (((symbol-function
             'emacsvox-aural-voice-workbench--editable-palette)
            (lambda (palette _logical) palette))
           ((symbol-function 'emacsvox-aural-voice-tuner-open)
            (lambda (&rest values) (setq arguments values))))
        (emacsvox-aural-voice-workbench-tune))
      (let ((selector (plist-get (nthcdr 4 arguments) :selector))
            (engine (plist-get (nthcdr 4 arguments) :engine)))
        (should (eq (plist-get selector :kind) 'engine-default))
        (should (eq (plist-get selector :scope) 'session))
        (should (equal (plist-get selector :engine-id) "eloquence"))
        (should (equal (plist-get engine :engine-id) "eloquence")))
      (should
       (equal emacsvox-aural-voice-workbench-staged-profile before)))))

(ert-deftest emacsvox-aural-voice-workbench-copies-built-in-before-tuning ()
  "Logical tuning can create and activate an editable palette in place."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "voice-bolden"))
    (let (copied selected refreshed arguments)
      (cl-letf
          (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
           ((symbol-function 'emacsvox-aural-voice-palettes--copy)
            (lambda (source)
              (setq copied source)
              'acss-personal))
           ((symbol-function 'emacsvox-aural-select-voice-palette)
            (lambda (palette)
              (setq selected palette)
              palette))
           ((symbol-function 'emacsvox-aural-voice-workbench-refresh)
            (lambda (&optional id) (setq refreshed id)))
           ((symbol-function 'emacsvox-aural-voice-tuner-open)
            (lambda (&rest values) (setq arguments values))))
        (emacsvox-aural-voice-workbench-tune))
      (should (eq copied 'acss-default))
      (should (eq selected 'acss-personal))
      (should (equal refreshed "voice-bolden"))
      (should (eq (nth 0 arguments) 'acss-personal))
      (should (eq (nth 1 arguments) 'bolden)))))

(ert-deftest emacsvox-aural-voice-workbench-can-decline-palette-copy ()
  "Declining the editable-copy offer leaves palette and tuner unchanged."
  (emacsvox-test--with-voice-workbench
    (should (emacsvox-aural-ui-goto-row "voice-bolden"))
    (let (copied opened)
      (cl-letf
          (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
           ((symbol-function 'emacsvox-aural-voice-palettes--copy)
            (lambda (&rest _) (setq copied t)))
           ((symbol-function 'emacsvox-aural-voice-tuner-open)
            (lambda (&rest _) (setq opened t))))
        (should-error
         (emacsvox-aural-voice-workbench-tune)
         :type 'user-error))
      (should-not copied)
      (should-not opened))))

(ert-deftest emacsvox-aural-voice-workbench-bindings-are-complete ()
  "Workbench view, filter, detail, refresh, home, and help keys are present."
  (dolist
      (binding
       '(("RET" . emacsvox-aural-voice-workbench-describe)
         ("l" . emacsvox-aural-voice-workbench-logical-view)
         ("v" . emacsvox-aural-voice-workbench-physical-view)
         ("e" . emacsvox-aural-voice-workbench-engine-view)
         ("s" . emacsvox-aural-voice-workbench-style-view)
         ("F" . emacsvox-aural-voice-workbench-set-filter)
         ("C" . emacsvox-aural-voice-workbench-clear-filters)
         ("R" . emacsvox-aural-voice-workbench-refresh-inventory)
         ("P" . emacsvox-aural-voice-workbench-preview)
         ("A" . emacsvox-aural-voice-workbench-preview-all)
         ("B" . emacsvox-aural-voice-workbench-compare)
         ("T" . emacsvox-aural-voice-workbench-edit-preview-text)
         ("S" . emacsvox-aural-voice-workbench-stop-preview)
         ("t" . emacsvox-aural-voice-workbench-tune)
         ("a" . emacsvox-aural-voice-workbench-assign)
         ("j" . emacsvox-aural-voice-workbench-suggest-route)
         ("c" . emacsvox-aural-voice-workbench-cancel-assignment)
         ("[" . emacsvox-aural-voice-workbench-move-selector-up)
         ("]" . emacsvox-aural-voice-workbench-move-selector-down)
         ("O" . emacsvox-aural-voice-workbench-toggle-preferred-engine)
         ("f" . emacsvox-aural-voice-workbench-toggle-fallback-engine)
         ("{" . emacsvox-aural-voice-workbench-move-fallback-engine-up)
         ("}" . emacsvox-aural-voice-workbench-move-fallback-engine-down)
         ("D" . emacsvox-aural-voice-workbench-toggle-disabled-engine)
         ("K" . emacsvox-aural-voice-workbench-request-recovery-probe)
         ("d" . emacsvox-aural-voice-workbench-delete-selector)
         ("y" . emacsvox-aural-voice-workbench-copy-route)
         ("M" . emacsvox-aural-voice-workbench-bind-unmapped)
         ("X" . emacsvox-aural-voice-workbench-replace-engine)
         ("m" . emacsvox-aural-voice-workbench-migrate)
         ("N" . emacsvox-aural-voice-workbench-apply-preset)
         ("E" . emacsvox-aural-voice-workbench-export-profile)
         ("I" . emacsvox-aural-voice-workbench-import-profile)
         ("u" . emacsvox-aural-voice-workbench-undo)
         ("x" . emacsvox-aural-voice-workbench-describe)
         ("w" . emacsvox-aural-voice-workbench-save-and-apply)
         ("C-c C-c" . emacsvox-aural-voice-workbench-save-and-apply)
         ("C-c C-k" . emacsvox-aural-voice-workbench-cancel-staged)
         ("r" . emacsvox-aural-voice-workbench-retry-apply)
         ("U" . emacsvox-aural-voice-workbench-undo-applied)
         ("q" . emacsvox-aural-quit)
         ("h" . emacsvox-aural)
         ("?" . emacsvox-aural-voice-workbench-help)))
    (should
     (eq (lookup-key emacsvox-aural-voice-workbench-mode-map
                     (kbd (car binding)))
         (cdr binding)))))

(provide 'emacsvox-aural-voice-workbench-tests)
;;; emacsvox-aural-voice-workbench-tests.el ends here
