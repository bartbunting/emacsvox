;;; emacsvox-aural-transport-tests.el --- Concrete transport tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test source-boundary capture, concrete cue and voice compilation, strict
;; queue ordering, legacy adapters, and owned Pulse/PipeWire sample lifecycles.

;;; Code:

(require 'cl-lib)
(require 'benchmark)
(require 'ert)
(require 'seq)
(require 'emacsvox-sounds)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-submission)
(require 'tts-speak)
(require 'voice-setup)

(defvar emacsvox-pronounce-personality)
(defvar emacsvox-pronounce-table)

(defmacro emacsvox-test--with-transport-scheme (&rest body)
  "Run BODY with isolated scheme and contextual override state."
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
         (emacsvox-aural--file-digest-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural-unsupported-volume-policy 'degrade)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-feature-fragment-order nil)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-effective-resource-pack-changed-hook nil)
         (emacsvox-aural-face-presentation-enabled t)
         (emacsvox-aural-face-presentation-changed-hook nil)
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

(defun emacsvox-test--transport-scheme (rules)
  "Register and select a transport test scheme containing RULES."
  (emacsvox-aural-register-scheme
   (list
    :schema-version 1
    :id 'transport-test
    :summary "Concrete transport test scheme"
    :parent 'default
    :rules rules))
  (emacsvox-aural-select-scheme 'transport-test))

(defun emacsvox-test--transport-context (&optional mode)
  "Return a minimal presentation context for MODE."
  (list
   :mode (or mode 'text-mode)
   :mode-lineage (list (or mode 'text-mode))
   :occasion 'navigation))

(defun emacsvox-test--transport-adapter-command (personality)
  "Return the mock adapter command for PERSONALITY.

Loaded `defvoice' personalities resolve through their ACSS-backed value."
  (format
   "<%s>"
   (if (boundp personality)
       (symbol-value personality)
     personality)))

(defun emacsvox-test--concrete-plans-in (text)
  "Return consecutive concrete aural plans carried by TEXT."
  (let ((position 0)
        plans)
    (while (< position (length text))
      (push (emacsvox-aural-concrete-plan-at position text) plans)
      (setq
       position
       (next-single-property-change
        position emacsvox-aural-concrete-plan-property
        text (length text))))
    (nreverse plans)))

(ert-deftest emacsvox-aural-source-text-property-ignores-aliases ()
  "Source capture distinguishes actual properties from character aliases."
  (let ((text (propertize "face" 'face 'font-lock-comment-face)))
    (with-temp-buffer
      (setq-local char-property-alias-alist '((personality face)))
      (should
       (eq
        (get-text-property 0 'personality text)
        'font-lock-comment-face))
      (should-not
       (emacsvox-aural-source-text-property
        0 'personality text)))))

(ert-deftest emacsvox-aural-source-call-with-submission-freezes-boundary ()
  "The shared source boundary captures once and preserves nested intent."
  (let (captures observed)
    (cl-letf
        (((symbol-function 'emacsvox-aural-capture-context)
          (lambda (module occasion)
            (push (list module occasion) captures)
            (list :module module :occasion occasion :frozen t))))
      (should
       (eq
        (emacsvox-aural-call-with-submission
         (lambda (&rest arguments)
           (setq
            observed
            (list
             arguments
             emacsvox-aural-submission-facts
             emacsvox-aural-submission-context
             emacsvox-aural-submission-module
             emacsvox-aural-submission-occasion))
           'called)
         :facts '(:role message)
         :module 'notmuch
         :occasion 'navigation
         :arguments '(one two))
        'called)))
    (should (equal captures '((notmuch navigation))))
    (should
     (equal
      observed
      '((one two)
        (:role message)
        (:module notmuch :occasion navigation :frozen t)
        notmuch navigation)))
    (let ((emacsvox-aural-submission-facts '(:role heading))
          (emacsvox-aural-submission-context
           '(:module org :occasion state-change :frozen outer))
          (emacsvox-aural-submission-module 'org)
          (emacsvox-aural-submission-occasion 'state-change))
      (setq observed nil)
      (emacsvox-aural-call-with-submission
       (lambda ()
         (setq
          observed
          (list
           emacsvox-aural-submission-facts
           emacsvox-aural-submission-context
           emacsvox-aural-submission-module
           emacsvox-aural-submission-occasion)))
       :facts '(:role message)
       :context '(:module notmuch :occasion navigation)
       :module 'notmuch
       :occasion 'navigation)
      (should
       (equal
        observed
        '((:role heading)
          (:module org :occasion state-change :frozen outer)
          org state-change)))
      (should (equal captures '((notmuch navigation)))))))

(ert-deftest emacsvox-aural-submission-combines-one-object-and-legacy-actions ()
  "One native submission resolves object policy once around ordered adapters."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id heading-cue
        :match (:role heading)
        :render
        (:before
         ((:id semantic-heading :kind cue :cue new-mail
           :anchor object))))))
    (let* ((emacsvox-aural--submission-sequence 0)
           (context
            '(:module org
              :mode org-mode
              :mode-lineage (org-mode outline-mode text-mode)
              :occasion navigation
              :face-presentation-enabled t
              :voice-lock-enabled t
              :icons-enabled t))
           (content
            (concat
             (propertize
              "First"
              emacsvox-aural-facts-property
              '(:role heading :level 1))
             (propertize
              "Second"
              emacsvox-aural-facts-property
              '(:role heading :level 2))))
           spoken
           submission)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text) (setq spoken text))))
        (setq
         submission
         (emacsvox-aural-submit
          content
          :facts '(:role heading)
          :context context
          :compatibility-actions
          (list
           (emacsvox-aural-compatibility-icon 'item)
           (emacsvox-aural-compatibility-icon 'button)
           (emacsvox-aural-compatibility-icon 'repeat-stop 'after)))))
      (should (emacsvox-aural-submission-p submission))
      (should
       (eq spoken
           (emacsvox-aural-submission-prepared-content submission)))
      (let* ((plans (emacsvox-aural-submission-plans submission))
             (first (car plans))
             (last (car (last plans)))
             (all-before
              (apply
               #'append
               (mapcar #'emacsvox-aural-concrete-plan-before plans)))
             (all-after
              (apply
               #'append
               (mapcar #'emacsvox-aural-concrete-plan-after plans))))
        (should (= (length plans) 2))
        (should
         (equal
          (mapcar #'emacsvox-aural-concrete-plan-object-id plans)
          '((submission 1) (submission 1))))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-cue
           (emacsvox-aural-concrete-plan-before first))
          '(item button new-mail)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-cue
           (emacsvox-aural-concrete-plan-after last))
          '(repeat-stop)))
        (should
         (= (cl-count 'new-mail all-before
                      :key #'emacsvox-aural-concrete-action-cue)
            1))
        (should
         (= (cl-count 'item all-before
                      :key #'emacsvox-aural-concrete-action-cue)
            1))
        (should
         (= (cl-count 'button all-before
                      :key #'emacsvox-aural-concrete-action-cue)
            1))
        (should
         (= (cl-count 'repeat-stop all-after
                      :key #'emacsvox-aural-concrete-action-cue)
            1))
        (should
         (equal
          (plist-get
           (emacsvox-aural-submission-facts submission)
           :events)
          '(activity-ended)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-id
           (cl-remove
            'semantic-heading
            (emacsvox-aural-concrete-plan-before first)
            :key #'emacsvox-aural-concrete-action-id))
          '(compatibility-item-1-legacy-cue
            compatibility-button-2-legacy-cue)))))))

(ert-deftest emacsvox-aural-submission-records-one-exact-history-transaction ()
  "Clause and formatting runs remain exact inside one history transaction."
  (emacsvox-test--with-transport-scheme
    (let* ((emacsvox-aural--submission-sequence 0)
           (context
            '(:module org
              :mode org-mode
              :mode-lineage (org-mode outline-mode text-mode)
              :occasion navigation
              :face-presentation-enabled t
              :voice-lock-enabled t
              :icons-enabled t))
           (content
            (concat
             (propertize "First" 'personality 'voice-bolden)
             (propertize
              "Second" 'personality 'voice-animate 'pause 0.15)))
           queued)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (prepared)
              (with-temp-buffer
                (insert prepared)
                (let ((split
                       (next-single-property-change
                        (point-min)
                        emacsvox-aural-concrete-plan-property
                        (current-buffer)
                        (point-max))))
                  (tts-audio-format (point-min) split)
                  (tts-audio-format split (point-max))))))
           ((symbol-function 'tts-voice-reset-code)
            (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code) #'ignore)
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push text queued)))
           ((symbol-function 'tts--protocol-silence) #'ignore))
        (emacsvox-aural-submit
         content :facts '(:role heading) :context context))
      (should (equal (nreverse queued) '("First" "Second")))
      (should (= (length emacsvox-aural-presentation-history) 1))
      (let* ((record (emacsvox-aural-last-presentation))
             (plans
              (emacsvox-aural-presentation-record-effective-plans
               record))
             (runs (emacsvox-aural-presentation-record-runs record)))
        (should (= (emacsvox-aural-presentation-record-transaction-id record) 1))
        (should (= (length plans) 2))
        (should-not (emacsvox-aural-presentation-record-run-id record))
        (should
         (equal
          (mapcar
           (lambda (plan)
             (emacsvox-aural-concrete-content-text
              (emacsvox-aural-concrete-plan-content plan)))
           plans)
          '("First" "Second")))
        (should
         (equal
          (mapcar (lambda (run) (nth 2 run)) runs)
          '(nil 0.15)))
        (should
         (equal
          (mapcar
           (lambda (plan)
             (plist-get
              (emacsvox-aural-concrete-plan-context plan)
              :presentation-transaction-id))
           plans)
          '(1 1)))))))

(ert-deftest emacsvox-aural-action-submission-queues-one-native-transaction ()
  "Action-only rules queue in order and retain one exact transaction."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id folded-heading
        :match (:role heading :state folded)
        :render
        (:before
         ((:id empty :kind tone :tone line-empty))
         :after
         ((:id trailing-gap :kind pause :duration 40))))))
    (let* ((emacsvox-aural--submission-sequence 0)
           (facts '(:role heading :state folded))
           (context
            (append
             (emacsvox-test--transport-context)
             '(:icons-enabled nil)))
           events
           submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural--ensure-speaker)
            (lambda () (push 'ensure events)))
           ((symbol-function 'tts--protocol-tone)
            (lambda (pitch duration &optional force)
              (push (list 'tone pitch duration force) events)))
           ((symbol-function 'tts--protocol-silence)
            (lambda (duration &optional _force)
              (push (list 'pause duration) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text)
              (ert-fail
               (format "Action-only submission queued content: %S" text))))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (setq
         submission
         (emacsvox-aural-submit-actions
          :facts facts
          :context context)))
      (should
       (equal
        (nreverse events)
        '(ensure (tone 130.8 150 nil) (pause 40) dispatch)))
      (should (emacsvox-aural-submission-p submission))
      (should (= (emacsvox-aural-submission-id submission) 1))
      (should (equal (emacsvox-aural-submission-facts submission) facts))
      (should (equal (emacsvox-aural-submission-context submission) context))
      (should-not (emacsvox-aural-submission-content submission))
      (should-not
       (emacsvox-aural-submission-compatibility-actions submission))
      (should-not
       (emacsvox-aural-submission-prepared-content submission))
      (let* ((plans (emacsvox-aural-submission-plans submission))
             (plan (car plans))
             (record (emacsvox-aural-last-presentation)))
        (should (= (length plans) 1))
        (should
         (= (plist-get
             (emacsvox-aural-concrete-plan-context plan)
             :presentation-transaction-id)
            1))
        (should (= (length emacsvox-aural-presentation-history) 1))
        (should
         (= (emacsvox-aural-presentation-record-effective-transaction-id
             record)
            1))
        (should
         (equal
          (emacsvox-aural-presentation-record-effective-plans record)
          (list plan)))))))

(ert-deftest emacsvox-aural-action-submission-presents-enabled-cue ()
  "An enabled semantic cue uses the ordered transport and enters history."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id heading
        :match (:role heading)
        :render
        (:before ((:id item :kind cue :cue item))))))
    (let ((context
           (append
            (emacsvox-test--transport-context)
            '(:icons-enabled t)))
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural--ensure-speaker)
            (lambda () (push 'ensure events)))
           ((symbol-function 'emacsvox-queue-resource)
            (lambda (_resource) (push 'cue events)))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (emacsvox-aural-submit-actions
         :facts '(:role heading)
         :context context))
      (should (equal (nreverse events) '(ensure cue dispatch)))
      (should (= (length emacsvox-aural-presentation-history) 1)))))

(ert-deftest emacsvox-aural-action-submission-skips-disabled-cue ()
  "A cue-only result disabled at its source performs no lifecycle work."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id heading
        :match (:role heading)
        :render
        (:before ((:id item :kind cue :cue item))))))
    (let ((context
           (append
            (emacsvox-test--transport-context)
            '(:icons-enabled nil)))
          events
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural--ensure-speaker)
            (lambda () (push 'ensure events)))
           ((symbol-function 'emacsvox-queue-resource)
            (lambda (_resource) (push 'cue events)))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (setq
         submission
         (emacsvox-aural-submit-actions
          :facts '(:role heading)
          :context context)))
      (should-not events)
      (should (= (length (emacsvox-aural-submission-plans submission)) 1))
      (should-not emacsvox-aural-presentation-history))))

(ert-deftest emacsvox-aural-action-submission-skips-empty-plan ()
  "An unmatched action-only submission neither starts nor dispatches."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme nil)
    (let (events submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural--ensure-speaker)
            (lambda () (push 'ensure events)))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (setq
         submission
         (emacsvox-aural-submit-actions
          :facts '(:role heading)
          :context
          (append
           (emacsvox-test--transport-context)
           '(:icons-enabled t)))))
      (should-not events)
      (should (= (length (emacsvox-aural-submission-plans submission)) 1))
      (should-not emacsvox-aural-presentation-history))))

(ert-deftest emacsvox-aural-action-submission-rejects-content ()
  "Action-only facts cannot smuggle even empty object content."
  (dolist (content '(nil ""))
    (should-error
     (emacsvox-aural-submit-actions
      :facts (list :role 'heading :content content)
      :context
      (append
       (emacsvox-test--transport-context)
       '(:icons-enabled t)))
     :type 'emacsvox-aural-submission-error)))

(ert-deftest emacsvox-speak-line-detects-semantic-conditions-in-order ()
  "Line classification preserves blank and punctuation-policy precedence."
  (let ((tts-punctuation-mode 'some))
    (dolist
        (case
         '(("" empty)
           (" \t" whitespace-only)
           ("---" separator)
           ("!@#" decorative)
           ("☃" unspeakable)
           ("text" nil)))
      (should
       (eq
        (emacsvox-speak--line-condition (car case))
        (cadr case)))))
  (let ((tts-punctuation-mode 'all))
    (should (eq (emacsvox-speak--line-condition "") 'empty))
    (should
     (eq
      (emacsvox-speak--line-condition " ")
      'whitespace-only))
    (dolist (line '("---" "!@#" "☃"))
      (should-not (emacsvox-speak--line-condition line)))))

(ert-deftest emacsvox-speak-visual-line-detects-blank-conditions ()
  "Visual-line classification distinguishes blank segments from wrap edges."
  (dolist
      (case
       '(("" empty)
         (" \t" whitespace-only)
         ("content" nil)))
    (with-temp-buffer
      (insert (car case))
      (goto-char (point-min))
      (visual-line-mode 1)
      (should
       (eq
        (emacsvox-speak--visual-line-condition)
        (cadr case)))))
  (with-temp-buffer
    (insert "content")
    (cl-letf
        (((symbol-function 'beginning-of-visual-line)
          (lambda (&rest _) (goto-char (point-max))))
         ((symbol-function 'end-of-visual-line) #'ignore))
      (should-not (emacsvox-speak--visual-line-condition)))))

(ert-deftest emacsvox-speak-line-submits-first-class-condition-tones ()
  "Core line conditions compose with object facts and resolve to named tones."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme nil)
    (dolist
        (case
         '(("" empty line-empty 130.8)
           (" \t" whitespace-only line-whitespace 261.6)
           ("---" separator line-separator 523.3)
           ("!@#" decorative line-decoration 1047)
           ("☃" unspeakable line-unspeakable 2093)))
      (with-temp-buffer
        (insert (car case))
        (goto-char (point-min))
        (let ((emacsvox-show-point nil)
              (emacsvox-audio-indentation nil)
              (emacsvox-aural-presentation-history nil)
              (emacsvox-aural-submission-facts
               '(:role heading :content "stale object text"))
              (emacsvox-aural-submission-context nil)
              (emacsvox-aural-submission-module nil)
              (emacsvox-aural-submission-occasion nil)
              (tts-punctuation-mode 'some)
              (tts-quiet nil)
              (tts-speaker-process 'speaker)
              events)
          (cl-letf
              (((symbol-function 'process-live-p)
                (lambda (process) (eq process 'speaker)))
               ((symbol-function 'tts-stop) #'ignore)
               ((symbol-function 'tts-initialize)
                (lambda ()
                  (ert-fail "Live line-tone transport was reinitialized")))
               ((symbol-function 'tts-speak)
                (lambda (&rest _)
                  (ert-fail "A line condition entered text speech")))
               ((symbol-function 'tts--protocol-queue-text)
                (lambda (text)
                  (ert-fail
                   (format "A line condition queued content: %S" text))))
               ((symbol-function 'tts--protocol-tone)
                (lambda (pitch duration &optional force)
                  (push (list 'tone pitch duration force) events)))
               ((symbol-function 'tts--protocol-dispatch)
                (lambda () (push 'dispatch events))))
            (emacsvox-speak-line))
          (should
           (equal
            (nreverse events)
            (list (list 'tone (nth 3 case) 150 nil) 'dispatch)))
          (let* ((record (emacsvox-aural-last-presentation))
                 (plan
                  (car
                   (emacsvox-aural-presentation-record-effective-plans
                    record)))
                 (facts (emacsvox-aural-concrete-plan-facts plan))
                 (tone
                  (car (emacsvox-aural-concrete-plan-before plan))))
            (should (eq (plist-get facts :role) 'heading))
            (should-not (plist-member facts :content))
            (should
             (eq
              (plist-get facts :line-condition)
              (nth 1 case)))
            (should
             (eq
              (emacsvox-aural-concrete-action-tone tone)
              (nth 2 case)))))))))

(ert-deftest emacsvox-speak-edit-operations-submit-first-class-tones ()
  "Core edit operations resolve named tones under the edit occasion."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme nil)
    (dolist
        (case
         '((deletion edit-deletion 500 75)
           (line-created edit-line-created 225 75)
           (uppercase edit-uppercase 800 100)
           (lowercase edit-lowercase 600 100)
           (capitalize edit-uppercase 800 100)))
      (let ((emacsvox-aural-presentation-history nil)
            (emacsvox-aural-submission-facts
             '(:role field :content "changed text"))
            (emacsvox-aural-submission-context nil)
            (emacsvox-aural-submission-module nil)
            (emacsvox-aural-submission-occasion nil)
            (tts-quiet nil)
            (tts-speaker-process 'speaker)
            events)
        (cl-letf
            (((symbol-function 'process-live-p)
              (lambda (process) (eq process 'speaker)))
             ((symbol-function 'tts-initialize)
              (lambda ()
                (ert-fail "Live edit transport was reinitialized")))
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (text)
                (ert-fail
                 (format "Edit queued content: %S" text))))
             ((symbol-function 'tts--protocol-tone)
              (lambda (pitch duration &optional force)
                (push (list 'tone pitch duration force) events)))
             ((symbol-function 'tts--protocol-dispatch)
              (lambda () (push 'dispatch events))))
          (emacsvox-speak-edit-operation (car case)))
        (should
         (equal
          (nreverse events)
          (list
           (list 'tone (nth 2 case) (nth 3 case) nil)
           'dispatch)))
        (let* ((record (emacsvox-aural-last-presentation))
               (plan
                (car
                 (emacsvox-aural-presentation-record-effective-plans
                  record)))
               (facts (emacsvox-aural-concrete-plan-facts plan))
               (context (emacsvox-aural-concrete-plan-context plan))
               (tone (car (emacsvox-aural-concrete-plan-before plan))))
          (should-not (plist-member facts :role))
          (should-not (plist-member facts :content))
          (should (eq (plist-get facts :edit-operation) (car case)))
          (should (eq (plist-get context :occasion) 'edit))
          (should
           (eq
            (emacsvox-aural-concrete-action-tone tone)
            (nth 1 case))))))))

(ert-deftest emacsvox-speak-line-condition-preserves-legacy-silence ()
  "Quiet mode or an unavailable existing server still suppresses line tones."
  (dolist (state '((t t) (nil nil)))
    (let ((tts-quiet (car state))
          (tts-speaker-process 'speaker)
          submitted)
      (cl-letf
          (((symbol-function 'process-live-p)
            (lambda (_process) (cadr state)))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _arguments) (setq submitted t))))
        (emacsvox-speak--present-line-condition 'empty))
      (should-not submitted))))

(defun emacsvox-test--tts-source-policy-result
    (text faces voice-lock source-icons scratch-icons)
  "Speak TEXT and summarize source policy at the real TTS scratch boundary.

FACES and VOICE-LOCK are the source presentation controls.
SOURCE-ICONS is the source buffer's local icon setting, while SCRATCH-ICONS
is the default inherited by a newly created TTS scratch buffer."
  (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
    (kill-buffer scratch))
  (let ((original-icons (default-value 'emacsvox-use-icons))
        (queue-plan (symbol-function 'emacsvox-aural-queue-concrete-plan))
        (tts-speaker-process 'speaker)
        (tts-stop-immediately nil)
        (tts-quiet nil)
        (emacsvox-pronounce-table nil)
        (emacsvox-pronounce-personality nil)
        summary
        resources)
    (unwind-protect
        (progn
          (set-default 'emacsvox-use-icons scratch-icons)
          (with-temp-buffer
            (setq-local voice-lock-mode voice-lock)
            (setq-local emacsvox-use-icons source-icons)
            (let ((emacsvox-aural-face-presentation-enabled faces))
              (cl-letf
                  (((symbol-function 'process-live-p) (lambda (_) t))
                   ((symbol-function 'tts-get-voice-command)
                    (lambda (voice) (format "<%s>" voice)))
                   ((symbol-function 'tts-voice-reset-code)
                    (lambda () "RESET"))
                   ((symbol-function 'tts--protocol-sync) #'ignore)
                   ((symbol-function 'tts--protocol-dispatch) #'ignore)
                   ((symbol-function 'tts--protocol-queue-code) #'ignore)
                   ((symbol-function 'tts--protocol-queue-text) #'ignore)
                   ((symbol-function 'tts--protocol-silence) #'ignore)
                   ((symbol-function 'emacsvox-queue-resource)
                    (lambda (resource) (push resource resources)))
                   ((symbol-function 'emacsvox-aural-queue-concrete-plan)
                    (lambda (concrete &optional final-text)
                      (setq
                       summary
                       (list
                        :context
                        (copy-tree
                         (emacsvox-aural-concrete-plan-context concrete))
                        :cues
                        (mapcar
                         #'emacsvox-aural-concrete-action-cue
                         (emacsvox-aural-concrete-plan-before concrete))
                        :voice-command
                        (emacsvox-aural-concrete-content-voice-command
                         (emacsvox-aural-concrete-plan-content concrete))))
                      (funcall queue-plan concrete final-text)))
                   ((symbol-function 'tts-move-across-a-chunk)
                    (lambda (&rest _)
                      (goto-char (point-max))
                      t)))
                (tts-speak text)))))
      (set-default 'emacsvox-use-icons original-icons)
      (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
        (kill-buffer scratch)))
    (append summary (list :resources (nreverse resources)))))

(ert-deftest emacsvox-aural-transport-captures-source-context ()
  "Source buffer, name, mode, module, and occasion are frozen together."
  (with-temp-buffer
    (rename-buffer "transport-source" t)
    (setq
     major-mode 'emacs-lisp-mode
     emacsvox-aural-module 'elisp
     voice-lock-mode t)
    (let ((context (emacsvox-aural-capture-context nil 'navigation)))
      (should (eq (plist-get context :source-buffer) (current-buffer)))
      (should
       (equal
        (plist-get context :source-buffer-name)
        "transport-source"))
      (should (eq (plist-get context :mode) 'emacs-lisp-mode))
      (should (eq (plist-get context :module) 'elisp))
      (should (eq (plist-get context :occasion) 'navigation))
      (should (plist-get context :face-presentation-enabled))
      (should (plist-get context :voice-lock-enabled))
      (should (plist-get context :icons-enabled)))))

(ert-deftest emacsvox-aural-transport-marks-interface-history-at-source ()
  "Aural UI capture policy is frozen before speech enters its scratch buffer."
  (with-temp-buffer
    (setq-local emacsvox-aural-ui-interface-buffer t)
    (let ((emacsvox-aural-history-record-interface-presentations nil))
      (should
       (plist-get
        (emacsvox-aural-capture-context 'aural-tools 'navigation)
        :history-recording-inhibited)))
    (let ((emacsvox-aural-history-record-interface-presentations t))
      (should-not
       (plist-get
        (emacsvox-aural-capture-context 'aural-tools 'navigation)
        :history-recording-inhibited)))))

(ert-deftest emacsvox-aural-transport-renders-templates-before-queueing ()
  "Semantic templates become concrete text at the source boundary."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id dynamic-heading
        :match (:role heading :requires (level))
        :render
        (:before
         ((:id heading-label :kind speech
           :text-template "Heading {level} is ready"))))))
    (let* ((facts '(:role heading :level 3 :content "Title"))
           (context (emacsvox-test--transport-context 'org-mode))
           (render (emacsvox-aural-resolve-active facts context))
           (concrete
            (emacsvox-aural-compile-plan render facts context)))
      (setf (plist-get facts :level) 9)
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-text
         (emacsvox-aural-concrete-plan-before concrete))
        '("Heading 3 is ready")))
      (should
       (equal
        (emacsvox-aural-concrete-plan-facts concrete)
        '(:role heading :level 3 :content "Title"))))))

(ert-deftest emacsvox-aural-transport-content-addresses-samples ()
  "Equal content shares an identifier and changed content gets a generation."
  (let* ((directory (make-temp-file "emacsvox-sample-id-" t))
         (first (expand-file-name "first.ogg" directory))
         (second (expand-file-name "second.ogg" directory)))
    (unwind-protect
        (progn
          (write-region "same" nil first nil 'silent)
          (write-region "same" nil second nil 'silent)
          (let ((one (emacsvox-aural-sample-id 'my-pack 'item first))
                (two (emacsvox-aural-sample-id 'my-pack 'item second)))
            (should (equal one two))
            (should (string-prefix-p "emacsvox-my-pack-item-" one))
            (write-region "changed" nil second nil 'silent)
            (should-not
             (equal
              one
              (emacsvox-aural-sample-id
               'my-pack 'item second)))))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-transport-caches-digests-by-file-generation ()
  "Canonical aliases share a digest until metadata or resources change."
  (let* ((directory (make-temp-file "emacsvox-digest-cache-" t))
         (resource (expand-file-name "item.ogg" directory))
         (alias (expand-file-name "alias.ogg" directory))
         (original (symbol-function 'secure-hash))
         (hashes 0)
         (emacsvox-aural--file-digest-cache
          (make-hash-table :test #'equal)))
    (unwind-protect
        (progn
          (write-region "one" nil resource nil 'silent)
          (make-symbolic-link resource alias)
          (cl-letf
              (((symbol-function 'secure-hash)
                (lambda (&rest arguments)
                  (cl-incf hashes)
                  (apply original arguments))))
            (let ((first (emacsvox-aural--file-digest resource)))
              (should (equal first (emacsvox-aural--file-digest resource)))
              (should (equal first (emacsvox-aural--file-digest alias)))
              (should (= hashes 1))
              (write-region "changed-size" nil resource nil 'silent)
              (should-not
               (equal first (emacsvox-aural--file-digest alias)))
              (should (= hashes 2))
              (run-hook-with-args
               'emacsvox-aural-resource-packs-changed-hook 'test-pack)
              (emacsvox-aural--file-digest alias)
              (should (= hashes 3)))))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-transport-freezes-volume-capability-policy ()
  "Unsupported volume is explicit and can be degraded or rejected."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id volume
        :match (:role heading)
        :render
        (:before
         ((:id label :kind speech :text "Heading" :volume 0.4))
         :content (:volume 0.7)))))
    (let* ((facts '(:role heading :content "Title"))
           (context (emacsvox-test--transport-context))
           (render (emacsvox-aural-resolve-active facts context))
           (plan (emacsvox-aural-compile-plan render facts context))
           (action (car (emacsvox-aural-concrete-plan-before plan)))
           (content (emacsvox-aural-concrete-plan-content plan)))
      (should (= (emacsvox-aural-concrete-action-requested-volume action)
                 0.4))
      (should
       (eq
        (emacsvox-aural-concrete-action-volume-capability action)
        'unsupported))
      (should (= (emacsvox-aural-concrete-content-requested-volume content)
                 0.7))
      (should
       (eq
        (emacsvox-aural-concrete-content-volume-capability content)
        'unsupported))
      (should
       (= 2
          (cl-count
           'unsupported-volume
           (emacsvox-aural-concrete-plan-degradations plan)
           :key (lambda (entry) (plist-get entry :reason)))))
      (let ((emacsvox-aural-unsupported-volume-policy 'reject))
        (should-error
         (emacsvox-aural-compile-plan render facts context)
         :type 'emacsvox-aural-transport-error)))))

(ert-deftest emacsvox-aural-transport-compiles-cues-and-palette-voices ()
  "Semantic cue and voice names become paths, sample IDs, and TTS commands."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id heading
        :match (:role heading)
        :render
        (:before ((:id item-cue :kind cue :cue item))
         :content (:voice bolden)))))
    (cl-letf (((symbol-function 'tts-get-voice-command)
               (lambda (voice) (format "<%s>" voice))))
      (let* ((facts '(:role heading :content "Title"))
             (context (emacsvox-test--transport-context))
             (render
              (emacsvox-aural-resolve-active facts context))
             (plan
              (emacsvox-aural-compile-plan render facts context))
             (cue (car (emacsvox-aural-concrete-plan-before plan))))
        (should
         (string-suffix-p
          "/packs/chimes/item.ogg"
          (emacsvox-aural-concrete-action-resource cue)))
        (should
         (string-prefix-p
          "emacsvox-chimes-item-"
          (emacsvox-aural-concrete-action-sample-id cue)))
        (should
         (equal
          (emacsvox-aural-concrete-content-voice-command
           (emacsvox-aural-concrete-plan-content plan))
          (emacsvox-test--transport-adapter-command
           'voice-bolden)))))))

(ert-deftest emacsvox-aural-transport-compiles-and-queues-named-tones ()
  "Named tones freeze protocol parameters and do not follow icon policy."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id empty-line
        :match (:role heading :state folded)
        :render
        (:before
         ((:id empty-tone :kind tone :tone line-empty))))))
    (let* ((facts '(:role heading :state folded :content ""))
           (context
            (plist-put
             (emacsvox-test--transport-context)
             :icons-enabled nil))
           (render (emacsvox-aural-resolve-active facts context))
           (plan (emacsvox-aural-compile-plan render facts context))
           (action (car (emacsvox-aural-concrete-plan-before plan)))
           events)
      (should (eq (emacsvox-aural-concrete-action-kind action) 'tone))
      (should (eq (emacsvox-aural-concrete-action-tone action) 'line-empty))
      (should (= (emacsvox-aural-concrete-action-pitch action) 130.8))
      (should (= (emacsvox-aural-concrete-action-duration action) 150))
      (should (emacsvox-aural-concrete-action-force action))
      (cl-letf
          (((symbol-function 'tts--protocol-tone)
            (lambda (pitch duration &optional force)
              (push (list pitch duration force) events))))
        (emacsvox-aural-queue-concrete-action action context))
      (should (equal events '((130.8 150 nil))))
      (should
       (string-match-p
        "tone line-empty at 130.8 Hz for 150 ms"
        (emacsvox-aural-describe-concrete-action action))))))

(ert-deftest emacsvox-aural-transport-rejects-unregistered-tones ()
  "An unknown tone cannot cross the concrete source boundary."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id unknown-tone
        :match (:role heading)
        :render
        (:before
         ((:id unknown :kind tone :tone not-registered))))))
    (let* ((facts '(:role heading :content "line"))
           (context (emacsvox-test--transport-context))
           (render (emacsvox-aural-resolve-active facts context)))
      (should-error
       (emacsvox-aural-compile-plan render facts context)
       :type 'emacsvox-aural-transport-error))))

(ert-deftest emacsvox-aural-transport-compiles-raw-acss ()
  "A raw ACSS style is named before the selected adapter compiles it."
  (let ((style (make-acss :average-pitch 4 :richness 6))
        events)
    (cl-letf (((symbol-function 'voice-from-acss)
               (lambda (value)
                 (push (list 'acss value) events)
                 'generated-voice))
              ((symbol-function 'emacsvox-aural-active-voice-capabilities)
               (lambda ()
                 '(:adapter test
                   :dimensions
                   (family average-pitch pitch-range stress richness))))
              ((symbol-function 'tts-get-voice-command)
               (lambda (voice)
                 (push (list 'adapter voice) events)
                 "<generated>")))
      (should
       (equal
        (emacsvox-aural-compile-voice style)
        "<generated>")))
    (should
     (equal
      (nreverse events)
      `((acss ,style) (adapter generated-voice))))))

(ert-deftest emacsvox-aural-transport-compiles-named-base-and-partial-style ()
  "A named base and explicit overlay compile once with effective ACSS data."
  (let (generated adapter-calls)
    (cl-letf
        (((symbol-function 'emacsvox-aural-active-voice-capabilities)
          (lambda ()
            '(:adapter test
              :dimensions
              (family average-pitch pitch-range stress richness))))
         ((symbol-function 'voice-from-acss)
          (lambda (style)
            (setq generated style)
            'generated-overlay))
         ((symbol-function 'tts-get-voice-command)
          (lambda (voice)
            (push voice adapter-calls)
            (format "<%s>" voice))))
      (let* ((provenance
              '((preset . base-rule) (pitch-range . overlay-rule)))
             (compiled
              (emacsvox-aural-compile-voice-style
               '(:preset bolden :pitch-range 3)
               'acss-default
               provenance)))
        (should
         (equal
          (emacsvox-aural-compiled-voice-command compiled)
          (format
           "%s <generated-overlay>"
           (emacsvox-test--transport-adapter-command 'voice-bolden))))
        (should (equal (nreverse adapter-calls)
                       (list
                        (if (boundp 'voice-bolden)
                            (symbol-value 'voice-bolden)
                          'voice-bolden)
                        'generated-overlay)))
        (should (= (acss-pitch-range generated) 3))
        (should
         (= (plist-get
             (emacsvox-aural-compiled-voice-style compiled)
             :pitch-range)
            3))
        (should
         (equal
          (emacsvox-aural-compiled-voice-provenance compiled)
          provenance))
        (should-not
         (emacsvox-aural-compiled-voice-degradations compiled))))))

(ert-deftest emacsvox-aural-transport-records-unsupported-voice-dimension ()
  "Unsupported explicit ACSS data degrades to the adapter default visibly."
  (cl-letf
      (((symbol-function 'emacsvox-aural-active-voice-capabilities)
        (lambda ()
          '(:adapter limited :dimensions (average-pitch)))))
    (let* ((compiled
            (emacsvox-aural-compile-voice-style '(:richness 8)))
           (degradation
            (car
             (emacsvox-aural-compiled-voice-degradations compiled))))
      (should-not (emacsvox-aural-compiled-voice-command compiled))
      (should-not
       (plist-get
        (emacsvox-aural-compiled-voice-style compiled) :richness))
      (should
       (eq
        (plist-get degradation :reason)
        'unsupported-voice-dimension))
      (should (eq (plist-get degradation :dimension) 'richness))
      (should (eq (plist-get degradation :adapter) 'limited)))))

(ert-deftest emacsvox-aural-transport-uses-adapter-owned-voice-capabilities ()
  "The aural layer consumes the descriptor selected by the TTS adapter."
  (let ((tts-voice-capabilities-function
         (lambda ()
           '(:adapter selected
             :source static
             :family-selection unsupported
             :dimensions (average-pitch)))))
    (let ((capabilities (emacsvox-aural-active-voice-capabilities)))
      (should (eq (plist-get capabilities :adapter) 'selected))
      (should (equal (plist-get capabilities :dimensions)
                     '(average-pitch))))))

(ert-deftest emacsvox-aural-transport-portable-family-follows-synth ()
  "A generic family is realized by the active adapter on every compile."
  (let ((cases
         '(((:adapter outloud
             :family-selection enumerated
             :families
             ((outloud-v2 :label "Adult female 1" :generic (female)))
             :dimensions (family))
            . outloud-v2)
           ((:adapter dectalk
             :family-selection enumerated
             :families
             ((betty :label "Beautiful Betty" :generic (female)))
             :dimensions (family))
            . betty))))
    (dolist (case cases)
      (let (generated)
        (cl-letf
            (((symbol-function 'emacsvox-aural-active-voice-capabilities)
              (lambda () (copy-tree (car case))))
             ((symbol-function 'voice-from-acss)
              (lambda (style)
                (setq generated style)
                'generated-family))
             ((symbol-function 'tts-get-voice-command)
              (lambda (_) "<family>")))
          (let ((compiled
                 (emacsvox-aural-compile-voice-style
                  '(:family female))))
            (should
             (eq
              (plist-get
               (emacsvox-aural-compiled-voice-style compiled)
               :family)
              (cdr case)))
            (should (equal
                     (emacsvox-aural-compiled-voice-command compiled)
                     "<family>"))))
        (should (eq (acss-family generated) (cdr case)))))))

(ert-deftest emacsvox-aural-transport-degrades-unavailable-exact-family ()
  "An adapter-specific family falls back visibly after a synth change."
  (cl-letf
      (((symbol-function 'emacsvox-aural-active-voice-capabilities)
        (lambda ()
          '(:adapter dectalk
            :family-selection enumerated
            :families
            ((paul :generic (male)) (betty :generic (female)))
            :dimensions (family)))))
    (let* ((compiled
            (emacsvox-aural-compile-voice-style
             '(:family outloud-v7)))
           (degradation
            (car (emacsvox-aural-compiled-voice-degradations compiled))))
      (should-not (emacsvox-aural-compiled-voice-command compiled))
      (should-not
       (plist-get
        (emacsvox-aural-compiled-voice-style compiled)
        :family))
      (should
       (eq (plist-get degradation :reason)
           'unavailable-voice-family))
      (should (eq (plist-get degradation :adapter) 'dectalk))
      (should (eq (plist-get degradation :requested) 'outloud-v7))
      (should (equal (plist-get degradation :available) '(paul betty))))))

(ert-deftest emacsvox-aural-spatial-reduces-azimuth-to-stereo ()
  "Listener-relative azimuth uses the documented sine stereo fallback."
  (should
   (= (emacsvox-aural-spatial-requested-balance '(:azimuth 90)) 1.0))
  (should
   (= (emacsvox-aural-spatial-requested-balance '(:azimuth -90)) -1.0))
  (should
   (<
    (abs
     (emacsvox-aural-spatial-requested-balance '(:azimuth 180)))
    0.000001)))

(ert-deftest emacsvox-aural-transport-centers-unsupported-spatial-output ()
  "Unsupported speech and ordered cue transports degrade predictably."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id spatial-heading
        :match (:role heading)
        :render
        (:before
         ((:id cue :kind cue :cue item :space (:balance -0.5))
          (:id label :kind speech :text "Heading"
           :space (:balance 0.25)))
         :content (:space (:azimuth 90))))))
    (let* ((emacsvox-aural-speech-balance-function nil)
           (emacsvox-aural-queued-cue-balance-function nil)
           (facts '(:role heading :content "Title"))
           (context (emacsvox-test--transport-context))
           (plan
            (emacsvox-aural-compile-plan
             (emacsvox-aural-resolve-active facts context)
             facts context))
           (before (emacsvox-aural-concrete-plan-before plan))
           (content (emacsvox-aural-concrete-plan-content plan))
           (reasons
            (mapcar
             (lambda (entry) (plist-get entry :reason))
             (emacsvox-aural-concrete-plan-degradations plan))))
      (should
       (equal (mapcar #'emacsvox-aural-concrete-action-balance before)
              '(0.0 0.0)))
      (should (= (emacsvox-aural-concrete-content-balance content) 0.0))
      (should (= (cl-count 'backend-centered reasons) 3))
      (should (memq 'azimuth-reduced-to-stereo reasons)))))

(ert-deftest emacsvox-aural-transport-spatial-adapters-preserve-order ()
  "Speech balance brackets text and an ordered cue adapter stays in sequence."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id spatial-heading
        :match (:role heading)
        :render
        (:before
         ((:id label :kind speech :text "Heading"
           :space (:balance -0.5))
          (:id cue :kind cue :cue item :space (:balance 0.25)))
         :content (:space (:balance 1.0))))))
    (let ((emacsvox-aural-spatial-maximum-separation 0.75)
          (emacsvox-aural-spatial-remapping 'normal)
          events)
      (cl-letf
          (((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code)
            (lambda (code) (push (list 'code code) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push (list 'text text) events))))
        (let ((emacsvox-aural-speech-balance-function
               (lambda (balance)
                 (push (list 'speech-balance balance) events)))
              (emacsvox-aural-queued-cue-balance-function
               (lambda (resource balance)
                 (push
                  (list 'cue (file-name-base resource) balance)
                  events))))
          (let* ((facts '(:role heading :content "Title"))
                 (context (emacsvox-test--transport-context))
                 (plan
                  (emacsvox-aural-compile-plan
                   (emacsvox-aural-resolve-active facts context)
                   facts context)))
            (emacsvox-aural-queue-concrete-plan plan)
            (should
             (equal
              (nreverse events)
              '((speech-balance -0.5)
                (text "Heading")
                (speech-balance 0.0)
                (cue "item" 0.25)
                (code "RESET")
                (speech-balance 0.75)
                (text "Title")
                (speech-balance 0.0))))
            (should
             (memq
              'maximum-separation
              (mapcar
               (lambda (entry) (plist-get entry :reason))
               (emacsvox-aural-concrete-plan-degradations plan))))))))))

(ert-deftest emacsvox-aural-transport-honors-independent-spatial-controls ()
  "Speech and cue controls, remapping, and maximum separation compose."
  (let ((emacsvox-aural-spatial-enabled t)
        (emacsvox-aural-spatial-speech-enabled nil)
        (emacsvox-aural-spatial-cue-enabled t)
        (emacsvox-aural-spatial-remapping 'reverse)
        (emacsvox-aural-spatial-maximum-separation 0.4))
    (should
     (equal
      (emacsvox-aural-spatial-apply-user-policy 0.8 'speech)
      '(:balance 0.0 :reasons (speech-spatialization-disabled))))
    (should
     (equal
      (emacsvox-aural-spatial-apply-user-policy 0.8 'cue)
      '(:balance -0.4 :reasons (user-remapping maximum-separation))))))

(ert-deftest emacsvox-aural-transport-mono-output-centers-with-reason ()
  "A declared mono output overrides otherwise spatial-capable adapters."
  (let ((emacsvox-aural-spatial-output 'mono)
        (emacsvox-aural-speech-balance-function #'ignore))
    (let ((compiled
           (emacsvox-aural--compile-space
            '(:balance -0.6) 'speech 'speech nil '(:content t))))
      (should (= (plist-get compiled :balance) 0.0))
      (should (eq (plist-get compiled :capability) 'mono))
      (should
       (eq
        (plist-get (car (plist-get compiled :degradations)) :reason)
        'mono-output)))))

(ert-deftest emacsvox-aural-transport-does-not-double-spatialize-assets ()
  "A pre-spatialized resource is played unchanged despite a rule request."
  (emacsvox-test--with-transport-scheme
    (let ((emacsvox-sounds-current-pack '3d)
          (emacsvox-aural-queued-cue-balance-function #'ignore))
      (emacsvox-test--transport-scheme
       '((:id cue
          :match (:role heading)
          :render
          (:before
           ((:id item :kind cue :cue item :space (:balance 0.8)))))))
      (let* ((facts '(:role heading))
             (context (emacsvox-test--transport-context))
             (plan
              (emacsvox-aural-compile-plan
               (emacsvox-aural-resolve-active facts context)
               facts context))
             (cue (car (emacsvox-aural-concrete-plan-before plan))))
        (should (= (emacsvox-aural-concrete-action-balance cue) 0.0))
        (should
         (eq
          (plist-get
           (car (emacsvox-aural-concrete-plan-degradations plan))
           :reason)
          'pre-spatialized-resource))))))

(ert-deftest emacsvox-aural-transport-distinguishes-local-and-queued-cues ()
  "The same cue can spatialize in local SoX and center on the server."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id cue
        :match (:role heading)
        :render
        (:before
         ((:id item :kind cue :cue item :space (:balance -0.75)))))))
    (let* ((facts '(:role heading))
           (context (emacsvox-test--transport-context))
           (render (emacsvox-aural-resolve-active facts context))
           (sox-play "/usr/bin/play")
           (emacsvox-play-program sox-play)
           (emacsvox-aural-queued-cue-balance-function nil)
           (local (emacsvox-aural-compile-plan
                   render facts context 'local-cue))
           (queued (emacsvox-aural-compile-plan
                    render facts context 'queued-cue)))
      (should
       (= -0.75
          (emacsvox-aural-concrete-action-balance
           (car (emacsvox-aural-concrete-plan-before local)))))
      (should
       (= 0.0
          (emacsvox-aural-concrete-action-balance
           (car (emacsvox-aural-concrete-plan-before queued))))))))

(ert-deftest emacsvox-aural-transport-queues-one-strict-order ()
  "Before actions, styled content, and after actions share one ordered queue."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id complete-heading
        :match (:role heading)
        :render
        (:before
         ((:id label :kind speech :text "Heading" :voice annotate)
          (:id cue :kind cue :cue item)
          (:id gap :kind pause :duration 40))
         :content (:voice bolden)
         :after
         ((:id state :kind speech :text "folded"))))))
    (let* ((facts '(:role heading :content "Title"))
           (context (emacsvox-test--transport-context))
           events)
      (cl-letf (((symbol-function 'tts-get-voice-command)
                 (lambda (voice) (format "<%s>" voice)))
                ((symbol-function 'tts-voice-reset-code)
                 (lambda () "RESET"))
                ((symbol-function 'tts--protocol-queue-code)
                 (lambda (code) (push (list 'code code) events)))
                ((symbol-function 'tts--protocol-queue-text)
                 (lambda (text) (push (list 'text text) events)))
                ((symbol-function 'tts--protocol-silence)
                 (lambda (duration &optional _force)
                   (push (list 'pause duration) events)))
                ((symbol-function 'emacsvox-queue-resource)
                 (lambda (resource)
                   (push
                    (list 'cue (file-name-base resource))
                    events))))
        (emacsvox-aural-queue-concrete-plan
         (emacsvox-aural-compile-plan
          (emacsvox-aural-resolve-active facts context)
          facts context)))
      (should
       (equal
        (nreverse events)
        `((code
           ,(emacsvox-test--transport-adapter-command
             'voice-annotate))
          (text "Heading")
          (code "RESET")
          (cue "item")
          (pause 40)
          (code "RESET")
          (code
           ,(emacsvox-test--transport-adapter-command
             'voice-bolden))
          (text "Title")
          (code "RESET")
          (text "folded")))))))

(ert-deftest emacsvox-aural-transport-retains-bounded-data-only-history ()
  "Actually queued payloads retain provenance without retaining buffers."
  (emacsvox-test--with-transport-scheme
    (let ((emacsvox-aural-presentation-history-limit 2))
      (with-temp-buffer
        (rename-buffer "aural-history-source" t)
        (goto-char (point-min))
        (let* ((facts '(:role heading :content "source"))
               (context (emacsvox-aural-capture-context nil 'continuous))
               (render (emacsvox-aural-resolve-active facts context))
               (plan (emacsvox-aural-compile-plan render facts context)))
          (setf (emacsvox-aural-concrete-plan-object-id plan) 'paragraph-1)
          (setf (emacsvox-aural-concrete-plan-run-id plan) 2)
          (cl-letf
              (((symbol-function 'tts-voice-reset-code)
                (lambda () "RESET"))
               ((symbol-function 'tts--protocol-queue-code) #'ignore)
               ((symbol-function 'tts--protocol-queue-text) #'ignore))
            (emacsvox-aural-queue-concrete-plan plan "first")
            (emacsvox-aural-queue-concrete-plan plan "second")
            (emacsvox-aural-queue-concrete-plan plan "third"))))
      (should (= (length emacsvox-aural-presentation-history) 2))
      (let* ((record (emacsvox-aural-last-presentation))
             (plan (emacsvox-aural-presentation-record-plan record))
             (context (emacsvox-aural-concrete-plan-context plan)))
        (should (equal
                 (emacsvox-aural-presentation-record-source-buffer-name
                  record)
                 "aural-history-source"))
        (should (eq
                 (emacsvox-aural-presentation-record-object-id record)
                 'paragraph-1))
        (should (= (emacsvox-aural-presentation-record-run-id record) 2))
        (should
         (equal
          (emacsvox-aural-concrete-content-text
           (emacsvox-aural-concrete-plan-content plan))
          "third"))
        (should-not (plist-get context :source-buffer))
        (cl-labels
            ((retains-buffer-p
              (value)
              (cond
               ((bufferp value) t)
               ((stringp value) nil)
               ((consp value)
                (or
                 (retains-buffer-p (car value))
                 (retains-buffer-p (cdr value))))
               ((vectorp value)
                (seq-some #'retains-buffer-p value))
               (t nil))))
          (should-not (retains-buffer-p record)))))))

(ert-deftest emacsvox-aural-transport-excludes-inhibited-interface-history ()
  "Interface presentations leave existing source history and sequence intact."
  (emacsvox-test--with-transport-scheme
    (let* ((kept 'existing-source-record)
           (emacsvox-aural-presentation-history (list kept))
           (plan
            (emacsvox-aural--make-concrete-plan
             :content
             (emacsvox-aural--make-concrete-content
              :text "Aural row" :speak t)
             :facts '(:role aural-interface)
             :context
             '(:module aural-tools :mode emacsvox-aural-tabulated-mode
               :mode-lineage (emacsvox-aural-tabulated-mode)
               :occasion navigation :history-recording-inhibited t))))
      (should-not (emacsvox-aural-record-presentation plan))
      (should (equal emacsvox-aural-presentation-history (list kept)))
      (should (zerop emacsvox-aural--presentation-sequence)))))

(ert-deftest emacsvox-aural-transport-scales-long-multi-face-document ()
  "Long face-rich text reuses one rule snapshot within bounded resources."
  (emacsvox-test--with-transport-scheme
    (let* ((text (make-string 240 ?x))
           (context (emacsvox-test--transport-context))
           (facts '(:role heading))
           (original
            (symbol-function 'emacsvox-aural--compute-current-rules))
           (computations 0))
      (dotimes (index (length text))
        (put-text-property
         index (1+ index) 'face
         (if (zerop (% index 2)) 'bold 'italic)
         text))
      (clrhash emacsvox-aural--current-rules-cache)
      (setq
       emacsvox-aural--current-rules-cache-hits 0
       emacsvox-aural--current-rules-cache-misses 0)
      (let ((before (memory-use-counts))
            elapsed
            after)
        (cl-letf
            (((symbol-function 'emacsvox-aural--compute-current-rules)
              (lambda (current-context)
                (cl-incf computations)
                (funcall original current-context))))
          (setq
           elapsed
           (car
            (benchmark-run
             1
             (emacsvox-aural-prepare-text text facts context)))))
        (setq after (memory-use-counts))
        (should (= computations 1))
        (should (= emacsvox-aural--current-rules-cache-misses 1))
        (should (> emacsvox-aural--current-rules-cache-hits 100))
        (should (< elapsed 5.0))
        (should (< (- (nth 0 after) (nth 0 before)) 5000000))
        (should (< (- (nth 2 after) (nth 2 before)) 5000000))
        (should (< (- (nth 4 after) (nth 4 before)) 1000000))))))

(ert-deftest emacsvox-aural-transport-queue-never-reresolves ()
  "Queueing a compiled plan performs no semantic, resource, or voice lookup."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id cue
        :match (:role heading)
        :render
        (:before ((:id item :kind cue :cue item))))))
    (let* ((facts '(:role heading))
           (context (emacsvox-test--transport-context))
           (plan
            (emacsvox-aural-compile-plan
             (emacsvox-aural-resolve-active facts context)
             facts context))
           queued)
      (cl-letf (((symbol-function 'emacsvox-aural-resolve-active)
                 (lambda (&rest _) (error "late semantic resolution")))
                ((symbol-function 'emacsvox-aural-resolve-cue)
                 (lambda (&rest _) (error "late resource resolution")))
                ((symbol-function 'tts-get-voice-command)
                 (lambda (&rest _) (error "late voice resolution")))
                ((symbol-function 'emacsvox-queue-resource)
                 (lambda (resource) (setq queued resource))))
        (emacsvox-aural-queue-concrete-plan plan))
      (should (string-suffix-p "/packs/chimes/item.ogg" queued)))))

(ert-deftest emacsvox-aural-transport-prepares-mode-rule-at-source ()
  "A mode rule is concrete before text reaches the scratch buffer."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id elisp
        :match (:mode emacs-lisp-mode)
        :render (:content (:voice bolden)))))
    (with-temp-buffer
      (setq major-mode 'emacs-lisp-mode)
      (cl-letf (((symbol-function 'tts-get-voice-command)
                 (lambda (voice) (format "<%s>" voice))))
        (let* ((prepared (emacsvox-aural-prepare-text "form"))
               (plan (emacsvox-aural-concrete-plan-at 0 prepared))
               (content
                (emacsvox-aural-concrete-plan-content plan))
               (context
                (emacsvox-aural-concrete-plan-context plan)))
          (should (eq (plist-get context :mode) 'emacs-lisp-mode))
          (should
           (eq
            (plist-get context :source-buffer)
            (current-buffer)))
          (should
           (equal
            (emacsvox-aural-concrete-content-voice-command content)
            (emacsvox-test--transport-adapter-command
             'voice-bolden))))))))

(ert-deftest emacsvox-aural-transport-freezes-layered-face-presentation ()
  "Named faces select composable cues and voice before text is queued."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-face
        :match
        (:legacy-face font-lock-warning-face :occasion navigation)
        :render
        (:before
         ((:id warning-cue :kind cue :cue warn-user))
         :content (:voice bolden)))))
    (with-temp-buffer
      (cl-letf (((symbol-function 'tts-get-voice-command)
                 (lambda (voice) (format "<%s>" voice))))
        (let* ((text
                (propertize
                 "warning"
                 'face
                 '(font-lock-warning-face bold
                   font-lock-warning-face)))
               (prepared
                (emacsvox-aural-prepare-text
                 text nil
                 (emacsvox-aural-capture-context nil 'navigation)))
               (plan (emacsvox-aural-concrete-plan-at 0 prepared))
               (context (emacsvox-aural-concrete-plan-context plan))
               (content (emacsvox-aural-concrete-plan-content plan)))
          (should
           (equal
            (plist-get context :legacy-faces)
            '(font-lock-warning-face bold)))
          (should (eq (plist-get context :legacy-face-source) 'face))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-before plan))
            '(warn-user)))
          (should
           (equal
            (emacsvox-aural-concrete-content-voice-command content)
            (emacsvox-test--transport-adapter-command
             'voice-bolden))))))))

(ert-deftest emacsvox-aural-transport-normalizes-explicit-face-names ()
  "Symbol, string, list, and anonymous inherited source faces stay named."
  (should
   (equal
    (emacsvox-aural-face-names
     '("font-lock-warning-face"
       (:foreground "red" :inherit font-lock-keyword-face)
       font-lock-warning-face))
    '(font-lock-warning-face font-lock-keyword-face))))

(ert-deftest emacsvox-aural-transport-captures-overlay-face-precedence ()
  "The source snapshot orders overlays before both text face properties."
  (with-temp-buffer
    (insert
     (propertize
      "styled"
      'face "font-lock-keyword-face"
      'font-lock-face '(:inherit font-lock-warning-face)))
    (let ((weaker (make-overlay (point-min) (point-max)))
          (stronger (make-overlay (point-min) (point-max))))
      (overlay-put weaker 'priority 2)
      (overlay-put weaker 'face 'bold)
      (overlay-put stronger 'priority 9)
      (overlay-put stronger 'face "font-lock-comment-face")
      (overlay-put stronger 'font-lock-face 'italic)
      (let* ((snapshot
              (emacsvox-aural-capture-source-faces (point-min)))
             (copy
              (emacsvox-aural-source-substring
               (point-min) (point-max))))
        (should
         (equal
          (mapcar
           (lambda (entry) (plist-get entry :face))
           snapshot)
          '(font-lock-comment-face italic bold
            font-lock-keyword-face font-lock-warning-face)))
        (should
         (equal
          (get-text-property
           0 emacsvox-aural-source-faces-property copy)
          snapshot))
        (should-not
         (get-text-property
          (point-min) emacsvox-aural-source-faces-property))
        (should
         (equal
          (mapcar
           (lambda (entry) (plist-get entry :order))
           snapshot)
          '(0 1 2 3 4)))
        (should
         (equal
          (mapcar
           (lambda (entry)
             (list
              (plist-get entry :source)
              (plist-get entry :property)))
           snapshot)
          '((overlay face)
            (overlay font-lock-face)
            (overlay face)
            (text-property face)
            (text-property font-lock-face))))))))

(ert-deftest emacsvox-aural-transport-source-and-frozen-faces-agree ()
  "Frozen speech uses the same overlay snapshot captured at its source."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-overlay
        :match (:legacy-face font-lock-warning-face)
        :render
        (:before
         ((:id warning-overlay-cue :kind cue :cue warn-user))))))
    (with-temp-buffer
      (insert "warning")
      (let ((overlay (make-overlay (point-min) (point-max))))
        (overlay-put overlay 'priority '(nil . 7))
        (overlay-put overlay 'face "font-lock-warning-face")
        (let* ((snapshot
                (emacsvox-aural-capture-source-faces (point-min)))
               (source
                (emacsvox-aural-source-substring
                 (point-min) (point-max)))
               (prepared
                (emacsvox-aural-prepare-text source))
               (plan
                (emacsvox-aural-concrete-plan-at 0 prepared))
               (context
                (emacsvox-aural-concrete-plan-context plan)))
          (should
           (equal
            (plist-get context :legacy-faces)
            '(font-lock-warning-face)))
          (should
           (eq
            (plist-get context :legacy-face-source)
            'overlay-face))
          (should
           (equal
            (plist-get context :legacy-face-provenance)
            snapshot))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-before plan))
            '(warn-user))))))))

(ert-deftest emacsvox-aural-transport-detects-partially-prepared-text ()
  "A raw suffix prevents a mixed string from bypassing source preparation."
  (emacsvox-test--with-transport-scheme
    (let* ((prepared (emacsvox-aural-prepare-text "prepared"))
           (mixed (concat prepared " raw")))
      (should (emacsvox-aural-prepared-text-p prepared))
      (should-not (emacsvox-aural-prepared-text-p mixed)))))

(ert-deftest emacsvox-aural-transport-preserves-voice-lock-compatibility ()
  "Legacy personalities compile only when legacy voice locking is enabled."
  (emacsvox-test--with-transport-scheme
    (let ((text (propertize "styled" 'personality 'voice-explicit)))
      (cl-letf (((symbol-function 'tts-get-voice-command)
                 (lambda (voice) (format "<%s>" voice))))
        (let* ((voice-lock-mode t)
               (prepared (emacsvox-aural-prepare-text text))
               (content
                (emacsvox-aural-concrete-plan-content
                 (emacsvox-aural-concrete-plan-at 0 prepared))))
          (should
           (equal
            (emacsvox-aural-concrete-content-voice-command content)
            "<voice-explicit>")))
        (let* ((voice-lock-mode nil)
               (prepared (emacsvox-aural-prepare-text text))
               (content
                (emacsvox-aural-concrete-plan-content
                 (emacsvox-aural-concrete-plan-at 0 prepared))))
          (should-not
           (emacsvox-aural-concrete-content-voice-command content)))))))

(ert-deftest emacsvox-aural-transport-coalesces-equivalent-midword-runs ()
  "Equivalent formatting runs do not split one word at the speech server."
  (emacsvox-test--with-transport-scheme
    (let* ((text
            (concat
             (propertize "N" 'face 'bold)
             "etwork"))
           (context
            '(:module core
              :mode text-mode
              :mode-lineage (text-mode)
              :occasion continuous
              :face-presentation-enabled t
              :voice-lock-enabled nil))
           (prepared
            (emacsvox-aural-prepare-text text nil context))
           events)
      (with-temp-buffer
        (insert prepared)
        (cl-letf
            (((symbol-function 'tts-voice-reset-code)
              (lambda () "RESET"))
             ((symbol-function 'tts--protocol-queue-code)
              (lambda (code) (push (list 'code code) events)))
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (payload) (push (list 'text payload) events))))
          (tts-audio-format (point-min) (point-max))))
      (should
       (equal
        (nreverse events)
        '((code "RESET")
          (text "Network"))))
      (should (= (length emacsvox-aural-presentation-history) 2)))))

(ert-deftest emacsvox-aural-transport-keeps-real-midword-voice-boundaries ()
  "A genuine voice change remains separate at the speech server."
  (emacsvox-test--with-transport-scheme
    (let* ((text
            (concat
             (propertize "N" 'personality 'voice-bolden)
             "etwork"))
           (context
            '(:module core
              :mode text-mode
              :mode-lineage (text-mode)
              :occasion continuous
              :face-presentation-enabled t
              :voice-lock-enabled t))
           prepared
           events)
      (cl-letf
          (((symbol-function 'tts-get-voice-command)
            (lambda (voice) (format "<%s>" voice))))
        (setq prepared
              (emacsvox-aural-prepare-text text nil context)))
      (with-temp-buffer
        (insert prepared)
        (cl-letf
            (((symbol-function 'tts-voice-reset-code)
              (lambda () "RESET"))
             ((symbol-function 'tts--protocol-queue-code)
              (lambda (code) (push (list 'code code) events)))
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (payload) (push (list 'text payload) events))))
          (tts-audio-format (point-min) (point-max))))
      (should
       (equal
        (mapcar #'cadr
                (seq-filter
                 (lambda (event) (eq (car event) 'text))
                 (nreverse events)))
        '("N" "etwork"))))))

(ert-deftest emacsvox-aural-transport-face-rules-ignore-voice-lock ()
  "The face-rule toggle and legacy Voice Lock remain independent at source."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-face
        :match (:legacy-face font-lock-warning-face)
        :render
        (:before
         ((:id warning-cue :kind cue :cue warn-user))
         :content (:voice bolden)))))
    (cl-letf (((symbol-function 'tts-get-voice-command)
               (lambda (voice) (format "<%s>" voice))))
      (dolist
          (case
           '((t t t voice-bolden)
             (t nil t voice-bolden)
             (nil t nil voice-lighten)
             (nil nil nil nil)))
        (pcase-let
            ((`(,faces ,voice-lock ,expected-cue ,expected-voice) case))
          (let* ((emacsvox-aural-face-presentation-enabled faces)
                 (voice-lock-mode voice-lock)
                 (text
                  (propertize
                   "warning"
                   'face 'font-lock-warning-face
                   'personality 'voice-lighten))
                 (prepared (emacsvox-aural-prepare-text text))
                 (plan (emacsvox-aural-concrete-plan-at 0 prepared))
                 (context (emacsvox-aural-concrete-plan-context plan))
                 (voice-command
                  (emacsvox-aural-concrete-content-voice-command
                   (emacsvox-aural-concrete-plan-content plan))))
            (should
             (eq
              (plist-get context :face-presentation-enabled)
              faces))
            (should
             (eq (plist-get context :voice-lock-enabled) voice-lock))
            (should
             (eq
               (not
               (null
                (emacsvox-aural-concrete-plan-before plan)))
              expected-cue))
            (if expected-voice
                (should
                 (equal
                  voice-command
                  (emacsvox-test--transport-adapter-command
                   expected-voice)))
              (should-not voice-command))))))))

(ert-deftest emacsvox-aural-transport-inaudible-overrides-face-rule-voice ()
  "Compatibility inaudibility remains authoritative over a face-rule voice."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-face
        :match (:legacy-face font-lock-warning-face)
        :render
        (:before
         ((:id warning-cue :kind cue :cue warn-user))
         :content (:voice bolden)))))
    (let* ((voice-lock-mode t)
           (text
            (propertize
             "warning"
             'face 'font-lock-warning-face
             'personality 'inaudible))
           (prepared (emacsvox-aural-prepare-text text))
           (plan (emacsvox-aural-concrete-plan-at 0 prepared))
           (content (emacsvox-aural-concrete-plan-content plan)))
      (should-not (emacsvox-aural-concrete-content-speak content))
      (should-not
       (emacsvox-aural-concrete-content-voice-command content))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-cue
         (emacsvox-aural-concrete-plan-before plan))
        '(warn-user))))))

(ert-deftest emacsvox-aural-transport-freezes-local-suppression-at-source ()
  "Face and personality suppression become frozen source presentation policy."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-face
        :match (:legacy-face font-lock-warning-face)
        :render (:content (:voice bolden)))))
    (let ((voice-lock-mode t)
          (voice-setup-face-voice-table (make-hash-table :test #'eq)))
      (puthash
       'font-lock-warning-face 'voice-lighten
       voice-setup-face-voice-table)
      (dolist
          (text
           (list
            (propertize
             "face" 'face 'font-lock-warning-face)
            (propertize
             "personality" 'personality 'voice-lighten)))
        (with-temp-buffer
          (insert text)
          (goto-char (point-min))
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (voice-setup-toggle-silence-personality))
          (let* ((source
                  (emacsvox-aural-source-substring
                   (point-min) (point-max)))
                 (prepared (emacsvox-aural-prepare-text source))
                 (plan (emacsvox-aural-concrete-plan-at 0 prepared)))
            (should
             (eq
              (plist-get
               (emacsvox-aural-concrete-plan-context plan)
               :legacy-personality)
              'inaudible))
            (should-not
             (emacsvox-aural-concrete-content-speak
              (emacsvox-aural-concrete-plan-content plan)))))))))

(ert-deftest emacsvox-aural-transport-tts-speak-control-matrix ()
  "The three presentation controls remain independent through real TTS."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-face
        :match (:legacy-face font-lock-warning-face)
        :render
        (:before
         ((:id warning-cue :kind cue :cue warn-user))
         :content (:voice bolden)))))
    (let ((text
           (propertize
            "warning"
            'face 'font-lock-warning-face
            'personality 'voice-lighten
            'auditory-icon 'item)))
      (dolist
          (case
           '((t t t (item warn-user) voice-bolden)
             (t t nil (item warn-user) voice-bolden)
             (t nil t (item warn-user) voice-bolden)
             (t nil nil (item warn-user) voice-bolden)
             (nil t t (item) voice-lighten)
             (nil t nil (item) voice-lighten)
             (nil nil t (item) nil)
             (nil nil nil (item) nil)))
        (pcase-let
            ((`(,faces ,voice-lock ,icons ,cues ,voice) case))
          (let* ((result
                  (emacsvox-test--tts-source-policy-result
                   text faces voice-lock icons icons))
                 (context (plist-get result :context))
                 (resources (plist-get result :resources)))
            (should
             (eq
              (plist-get context :face-presentation-enabled)
              faces))
            (should
             (eq (plist-get context :voice-lock-enabled) voice-lock))
            (should (eq (plist-get context :icons-enabled) icons))
            (should (equal (plist-get result :cues) cues))
            (if voice
                (should
                 (equal
                  (plist-get result :voice-command)
                  (emacsvox-test--transport-adapter-command voice)))
              (should-not (plist-get result :voice-command)))
            (should
             (= (length resources)
                (if icons (length cues) 0)))))))))

(ert-deftest emacsvox-aural-transport-tts-speak-keeps-source-icon-policy ()
  "Scratch-buffer formatting honors the frozen source-local icon policy."
  (emacsvox-test--with-transport-scheme
    (let* ((text (propertize "item" 'auditory-icon 'item))
           (source-off
            (emacsvox-test--tts-source-policy-result
             text nil nil nil t))
           (source-on
            (emacsvox-test--tts-source-policy-result
             text nil nil t nil)))
      (should (equal (plist-get source-off :cues) '(item)))
      (should-not
       (plist-get
        (plist-get source-off :context)
        :icons-enabled))
      (should-not (plist-get source-off :resources))
      (should (equal (plist-get source-on :cues) '(item)))
      (should
       (plist-get
        (plist-get source-on :context)
        :icons-enabled))
      (should (= (length (plist-get source-on :resources)) 1)))))

(ert-deftest emacsvox-aural-transport-tts-speak-keeps-source-snapshot ()
  "Scratch-buffer formatting receives a plan resolved in the source mode."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id source-mode
        :match (:mode emacs-lisp-mode)
        :render (:content (:voice bolden)))))
    (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
      (kill-buffer scratch))
    (let ((tts-speaker-process 'speaker)
          (tts-stop-immediately nil)
          (tts-quiet nil)
          (emacsvox-pronounce-table nil)
          (emacsvox-pronounce-personality nil)
          captured)
      (unwind-protect
          (with-temp-buffer
            (setq major-mode 'emacs-lisp-mode)
            (cl-letf
                (((symbol-function 'process-live-p) (lambda (_) t))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice)))
                 ((symbol-function 'tts--protocol-sync) #'ignore)
                 ((symbol-function 'tts--protocol-dispatch) #'ignore)
                 ((symbol-function 'tts-audio-format)
                  (lambda (start _end)
                    (let ((plan
                           (emacsvox-aural-concrete-plan-at start)))
                      (setq
                       captured
                       (list
                        major-mode
                        (plist-get
                         (emacsvox-aural-concrete-plan-context plan)
                         :mode)
                        (emacsvox-aural-concrete-content-voice-command
                         (emacsvox-aural-concrete-plan-content plan)))))))
                 ((symbol-function 'tts-move-across-a-chunk)
                  (lambda (&rest _)
                    (goto-char (point-max))
                    t)))
              (tts-speak "form")))
        (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
          (kill-buffer scratch)))
      (should
       (equal
        captured
        `(fundamental-mode
          emacs-lisp-mode
          ,(emacsvox-test--transport-adapter-command
            'voice-bolden)))))))

(ert-deftest emacsvox-aural-transport-cleanup-preserves-frozen-plan ()
  "Scratch-buffer replacements retain the plan frozen at submission."
  (let ((plan (list :frozen-plan t))
        (property emacsvox-aural-concrete-plan-property)
        (emacsvox-pronounce-personality nil))
    (dolist
        (case
         (list
          (cons
           "[x]"
           (lambda () (tts-fix-brackets 'all)))
          (cons
           "xxxx"
           (lambda ()
             (let ((tts-cleanup-repeats '("x")))
               (tts-handle-repeating-patterns 'all))))
          (cons
           "word"
           (lambda ()
             (let ((table (make-hash-table :test #'equal)))
               (puthash "word" "replacement" table)
               (tts-apply-pronunciations table))))))
      (with-temp-buffer
        (insert (propertize (car case) property plan))
        (funcall (cdr case))
        (should
         (not
          (text-property-not-all
           (point-min) (point-max) property plan)))))))

(ert-deftest emacsvox-aural-transport-cap-prefixes-compile-at-source ()
  "Inserted capitalization prefixes and source content both stay concrete."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id source-mode
        :match (:role heading :mode emacs-lisp-mode)
        :render (:content (:voice bolden)))))
    (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
      (kill-buffer scratch))
    (let ((tts-speaker-process 'speaker)
          (tts-stop-immediately nil)
          (tts-quiet nil)
          (tts-caps t)
          (tts-caps-prefix
           (propertize "cap " 'personality 'cap-voice))
          (tts-allcaps-prefix
           (propertize "all caps " 'personality 'all-caps-voice))
          (emacsvox-aural-submission-facts
           '(:role heading :content "Word"))
          (emacsvox-pronounce-table nil)
          (emacsvox-pronounce-personality nil)
          queued)
      (unwind-protect
          (with-temp-buffer
            (setq
             major-mode 'emacs-lisp-mode
             voice-lock-mode t)
            (cl-letf
                (((symbol-function 'process-live-p) (lambda (_) t))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice)))
                 ((symbol-function 'tts--protocol-sync) #'ignore)
                 ((symbol-function 'tts--protocol-dispatch) #'ignore)
                 ((symbol-function 'emacsvox-aural-queue-concrete-plan)
                  (lambda (plan &optional text)
                    (push
                     (list
                      text
                      (emacsvox-aural-concrete-content-voice-command
                       (emacsvox-aural-concrete-plan-content plan)))
                     queued)))
                 ((symbol-function 'tts-move-across-a-chunk)
                  (lambda (&rest _)
                    (goto-char (point-max))
                    t)))
              (tts-speak "Word")))
        (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
          (kill-buffer scratch)))
      (should
       (equal
        (nreverse queued)
        `(("cap " "<cap-voice>")
          ("Word"
           ,(emacsvox-test--transport-adapter-command
             'voice-bolden))))))))

(ert-deftest emacsvox-aural-transport-notification-captures-before-logging ()
  "Notification logging cannot replace the source buffer context."
  (let ((destination (generate-new-buffer " *notification-log*"))
        captured)
    (unwind-protect
        (with-temp-buffer
          (setq major-mode 'emacs-lisp-mode)
          (let ((source (current-buffer))
                (tts-notify-process nil)
                (tts-speaker-process nil))
            (cl-letf
                (((symbol-function 'emacsvox-log-notification)
                  (lambda (_text) (set-buffer destination)))
                 ((symbol-function 'tts-speak)
                  (lambda (_text)
                    (setq
                     captured
                     (copy-tree
                      emacsvox-aural-submission-context)))))
              (tts-notify "ready"))
            (should
             (eq (plist-get captured :source-buffer) source))
            (should
             (eq (plist-get captured :mode) 'emacs-lisp-mode))
            (should
             (eq (plist-get captured :occasion) 'notification))))
      (kill-buffer destination))))

(ert-deftest emacsvox-aural-transport-immediate-icon-uses-concrete-cue ()
  "A one-cue compatibility plan uses the selected local concrete adapter."
  (emacsvox-test--with-transport-scheme
    (let ((emacsvox-use-icons t)
          played)
      (cl-letf
          (((symbol-function 'emacsvox-sounds-play-concrete-cue)
            (lambda (resource sample-id)
              (setq played (list resource sample-id)))))
        (emacsvox-icon 'item))
      (should (string-suffix-p "/packs/chimes/item.ogg" (car played)))
      (should
       (string-prefix-p
        "emacsvox-chimes-item-" (cadr played))))))

(ert-deftest emacsvox-aural-transport-direct-icon-inherits-submission-facts ()
  "A compatibility icon keeps semantic facts, module, and occasion in scope."
  (emacsvox-test--with-transport-scheme
    (let ((emacsvox-use-icons t)
          (emacsvox-aural-submission-facts
           '(:events (focus-entered)))
          (emacsvox-aural-submission-module 'python)
          (emacsvox-aural-submission-occasion 'navigation)
          played
          plan)
      (cl-letf
          (((symbol-function 'emacsvox-sounds-play-concrete-cue)
            (lambda (resource sample-id)
              (setq played (list resource sample-id)))))
        (setq plan (emacsvox-icon 'paragraph)))
      (should played)
      (should
       (equal
        (plist-get
         (emacsvox-aural-concrete-plan-facts plan)
         :events)
        '(focus-entered)))
      (should
       (eq
        (plist-get
         (emacsvox-aural-concrete-plan-context plan)
         :module)
        'python))
      (should
       (eq
        (plist-get
         (emacsvox-aural-concrete-plan-context plan)
         :occasion)
        'navigation)))))

(ert-deftest emacsvox-aural-transport-rich-icon-plan-uses-server-queue ()
  "A spoken replacement is queued whether or not cue audio is enabled."
  (emacsvox-test--with-transport-scheme
    (setq
     emacsvox-aural-user-rules
     '((:id speak-item
        :match (:legacy-cue item)
        :render
        (:before
         (:remove (legacy-cue)
          :append
          ((:id spoken-item :kind speech :text "item")))))))
    (dolist (icons-enabled '(t nil))
      (let ((tts-speaker-process 'speaker)
            (emacsvox-use-icons icons-enabled)
            events)
        (cl-letf
            (((symbol-function 'process-live-p) (lambda (_) t))
             ((symbol-function 'emacsvox-sounds-play-concrete-cue)
              (lambda (&rest _) (push 'local events)))
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (text) (push (list 'text text) events)))
             ((symbol-function 'tts--protocol-dispatch)
              (lambda () (push 'dispatch events))))
          (emacsvox-icon 'item))
        (should
         (equal
          (nreverse events)
          '((text "item") dispatch)))))))

(ert-deftest emacsvox-aural-transport-unknown-icon-falls-back-concretely ()
  "An unknown legacy cue is compiled to the concrete button fallback."
  (emacsvox-test--with-transport-scheme
    (let* ((context (emacsvox-test--transport-context))
           (plan
            (emacsvox-aural-compile-plan
             (emacsvox-aural-resolve-legacy-icon
              'not-registered context)
             nil context))
           (cue (car (emacsvox-aural-concrete-plan-before plan))))
      (should (eq (emacsvox-aural-concrete-action-cue cue) 'button))
      (should
       (string-suffix-p
        "/packs/chimes/button.ogg"
        (emacsvox-aural-concrete-action-resource cue)))
      (should (emacsvox-aural-concrete-plan-degradations plan)))))

(ert-deftest emacsvox-aural-transport-owns-and-releases-pulse-samples ()
  "Only successful Emacsvox uploads are cached and later unloaded."
  (let ((emacsvox-pactl "/usr/bin/pactl")
        (emacsvox-sounds-owned-samples
         (make-hash-table :test #'equal))
        calls)
    (cl-letf (((symbol-function 'call-process)
               (lambda (_program _in _destination _display &rest args)
                 (push args calls)
                 0)))
      (emacsvox-sounds-ensure-sample "/sounds/one.ogg" "owned-one")
      (emacsvox-sounds-ensure-sample "/sounds/one.ogg" "owned-one")
      (emacsvox-sounds-ensure-sample "/sounds/two.ogg" "owned-two")
      (emacsvox-sounds-release-samples '("owned-two"))
      (should-not
       (gethash "owned-one" emacsvox-sounds-owned-samples))
      (should
       (equal
        (gethash "owned-two" emacsvox-sounds-owned-samples)
        "/sounds/two.ogg"))
      (should
       (equal
        (nreverse calls)
        '(("upload-sample" "/sounds/one.ogg" "owned-one")
          ("upload-sample" "/sounds/two.ogg" "owned-two")
          ("unload-sample" "owned-one")))))))

(ert-deftest emacsvox-aural-transport-presents-mixed-face-heading-once ()
  "Formatting runs retain voices without repeating semantic heading feedback."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id heading-object
        :match (:role heading :requires (level))
        :render
        (:before
         ((:id heading-label :kind speech
           :text-template "Heading {level}")
          (:id heading-cue :kind cue :cue section))
         :after
         ((:id heading-state :kind speech :text "folded"))))
       (:id warning-run
        :match (:legacy-face font-lock-warning-face)
        :render
        (:before
         ((:id warning-cue :kind cue :cue warn-user))
        :content (:voice bolden)))
       (:id keyword-run
        :match (:legacy-face font-lock-keyword-face)
        :render (:content (:voice animate)))))
    (let ((text (copy-sequence "** TODO Mixed heading :tag:"))
          (voice-lock-mode t))
      (add-text-properties 0 2 '(face font-lock-comment-face) text)
      (add-text-properties 3 7 '(face font-lock-warning-face) text)
      (add-text-properties 8 21 '(face font-lock-keyword-face) text)
      (add-text-properties 22 27 '(face font-lock-constant-face) text)
      (cl-letf
          (((symbol-function 'tts-get-voice-command)
            (lambda (voice) (format "<%s>" voice))))
        (let* ((prepared
                (emacsvox-aural-prepare-text
                 text
                 '(:role heading :level 2 :states (folded)
                   :content "** TODO Mixed heading :tag:")
                 (emacsvox-test--transport-context 'org-mode)))
               (plans (emacsvox-test--concrete-plans-in prepared))
               (before-ids
                (mapcan
                 (lambda (plan)
                   (mapcar
                    #'emacsvox-aural-concrete-action-id
                    (emacsvox-aural-concrete-plan-before plan)))
                 plans))
               (after-ids
                (mapcan
                 (lambda (plan)
                   (mapcar
                    #'emacsvox-aural-concrete-action-id
                    (emacsvox-aural-concrete-plan-after plan)))
                 plans)))
          (should (> (length plans) 3))
          (should (= (cl-count 'heading-label before-ids) 1))
          (should (= (cl-count 'heading-cue before-ids) 1))
          (should (= (cl-count 'heading-state after-ids) 1))
          (should (= (cl-count 'warning-cue before-ids) 1))
          (should
           (equal
            (mapcar #'emacsvox-aural-concrete-plan-object-id plans)
            (make-list
             (length plans)
             (emacsvox-aural-concrete-plan-object-id (car plans)))))
          (should
           (emacsvox-aural-concrete-plan-object-start-p (car plans)))
          (should
           (emacsvox-aural-concrete-plan-object-end-p (car (last plans))))
          (should
           (equal
            (emacsvox-aural-concrete-content-voice-command
             (emacsvox-aural-concrete-plan-content
              (emacsvox-aural-concrete-plan-at 3 prepared)))
            (emacsvox-test--transport-adapter-command 'voice-bolden)))
          (should
           (equal
            (emacsvox-aural-concrete-content-voice-command
             (emacsvox-aural-concrete-plan-content
              (emacsvox-aural-concrete-plan-at 8 prepared)))
            (emacsvox-test--transport-adapter-command 'voice-animate))))))))

(ert-deftest emacsvox-aural-transport-infers-or-honors-object-boundaries ()
  "Fact changes split inferred objects while an explicit identifier groups."
  (emacsvox-test--with-transport-scheme
    (let ((text (copy-sequence "FirstSecond"))
          (context (emacsvox-test--transport-context)))
      (add-text-properties
       0 5
       (list emacsvox-aural-facts-property '(:role heading :level 1))
       text)
      (add-text-properties
       5 11
       (list emacsvox-aural-facts-property '(:role heading :level 2))
       text)
      (let* ((inferred (emacsvox-aural-prepare-text text nil context))
             (plans (emacsvox-test--concrete-plans-in inferred)))
        (should (= (length plans) 2))
        (should-not
         (equal
          (emacsvox-aural-concrete-plan-object-id (car plans))
          (emacsvox-aural-concrete-plan-object-id (cadr plans)))))
      (add-text-properties
       0 11 (list emacsvox-aural-object-property 'heading-one) text)
      (let* ((explicit (emacsvox-aural-prepare-text text nil context))
             (plans (emacsvox-test--concrete-plans-in explicit)))
        (should (= (length plans) 2))
        (should
         (equal
          (mapcar #'emacsvox-aural-concrete-plan-object-id plans)
          '(heading-one heading-one)))
        (should
         (emacsvox-aural-concrete-plan-object-start-p (car plans)))
        (should-not
         (emacsvox-aural-concrete-plan-object-end-p (car plans)))
        (should
         (emacsvox-aural-concrete-plan-object-end-p (cadr plans)))))))

(ert-deftest emacsvox-aural-transport-emits-transition-edges-once ()
  "Adjacent matching runs share one transition entry and exit."
  (emacsvox-test--with-transport-scheme
    (emacsvox-test--transport-scheme
     '((:id warning-transition
        :match (:legacy-face font-lock-warning-face)
        :render
        (:before
         ((:id warning-enter :kind speech :text "warning begins"
           :anchor transition))
        :after
        ((:id warning-leave :kind speech :text "warning ends"
          :anchor transition))))))
    (let ((text (copy-sequence "abcdef"))
          (voice-lock-mode t))
      (add-text-properties
       0 2 '(face font-lock-warning-face personality first) text)
      (add-text-properties
       2 4 '(face font-lock-warning-face personality second) text)
      (cl-letf
          (((symbol-function 'tts-get-voice-command)
            (lambda (voice) (format "<%s>" voice))))
        (let* ((prepared
                (emacsvox-aural-prepare-text
                 text nil (emacsvox-test--transport-context)))
               (plans (emacsvox-test--concrete-plans-in prepared))
               (before
                (mapcan
                 (lambda (plan)
                   (mapcar
                    #'emacsvox-aural-concrete-action-id
                    (emacsvox-aural-concrete-plan-before plan)))
                 plans))
               (after
                (mapcan
                 (lambda (plan)
                   (mapcar
                    #'emacsvox-aural-concrete-action-id
                    (emacsvox-aural-concrete-plan-after plan)))
                 plans)))
          (should (= (length plans) 3))
          (should (equal before '(warning-enter)))
          (should (equal after '(warning-leave))))))))

(provide 'emacsvox-aural-transport-tests)
;;; emacsvox-aural-transport-tests.el ends here
