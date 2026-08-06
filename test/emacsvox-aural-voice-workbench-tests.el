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
    :preview-support "logical-route" :routing-policy-support "logical-voice"
    :engines
    ((:engine-id "eloquence" :display-name "Eloquence"
      :availability "available" :health "healthy"
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
  '(:schema-version 1 :id workstation :summary "Workbench profile"
    :engine-order ("eloquence" "winrt")
    :fallback
    (:allow-same-language t :global-default nil :engines nil)
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
         (tts-voice-inventory-function
          (lambda () (copy-tree emacsvox-test--workbench-inventory)))
         (tts-voice-capabilities-function
          (lambda ()
            '(:adapter omnivox :source discovered
              :family-selection routed
              :dimensions (average-pitch pitch-range stress richness volume))))
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
         ("a" . emacsvox-aural-voice-workbench-assign)
         ("c" . emacsvox-aural-voice-workbench-cancel-assignment)
         ("[" . emacsvox-aural-voice-workbench-move-selector-up)
         ("]" . emacsvox-aural-voice-workbench-move-selector-down)
         ("d" . emacsvox-aural-voice-workbench-delete-selector)
         ("y" . emacsvox-aural-voice-workbench-copy-route)
         ("M" . emacsvox-aural-voice-workbench-bind-unmapped)
         ("X" . emacsvox-aural-voice-workbench-replace-engine)
         ("u" . emacsvox-aural-voice-workbench-undo)
         ("x" . emacsvox-aural-voice-workbench-cancel-staged)
         ("q" . emacsvox-aural-quit)
         ("h" . emacsvox-aural)
         ("?" . emacsvox-aural-voice-workbench-help)))
    (should
     (eq (lookup-key emacsvox-aural-voice-workbench-mode-map
                     (kbd (car binding)))
         (cdr binding)))))

(provide 'emacsvox-aural-voice-workbench-tests)
;;; emacsvox-aural-voice-workbench-tests.el ends here
