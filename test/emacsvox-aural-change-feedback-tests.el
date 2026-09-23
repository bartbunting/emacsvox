;;; emacsvox-aural-change-feedback-tests.el --- Guided feedback tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Exercise component isolation, preview without persistence, and guarded apply.
;;; Code:
(require 'emacsvox-aural-tools-tests)
(require 'emacsvox-aural-change-feedback)

(defmacro emacsvox-test--with-guided-feedback (&rest body)
  "Run BODY with an isolated source and a real resolved feedback example."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-home-context
     (let* ((facts '(:role heading :content "Example heading"))
            (context '(:mode org-mode :occasion navigation))
            (render (emacsvox-aural-resolve-active facts context))
            (concrete (emacsvox-aural-compile-plan render facts context)))
       (cl-letf (((symbol-function 'emacsvox-aural-tools--remap-source-input)
                  (lambda (&optional _)
                    (list :source source :facts facts :context context :render render :concrete concrete))))
         (emacsvox-aural-change-feedback))
       ,@body)))

(defun emacsvox-test--guided-choose (&rest answers)
  "Choose a component row, with scripted ANSWERS for its remaining fields."
  (let ((operation (pop answers)))
    (setq emacsvox-aural-change-feedback--expanded nil)
    (emacsvox-aural-change-feedback-change)
    (emacsvox-aural-ui-goto-row (list 'operation operation))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (pop answers))))
      (emacsvox-aural-change-feedback-open-row)
      (when (equal operation "Change the content voice")
        (should (emacsvox-aural-ui-goto-row (list 'voice (intern (pop answers)))))
        (emacsvox-aural-change-feedback-open-row)))))

(defun emacsvox-test--guided-proposed ()
  "Capture the real proposed concrete plan, without speech output."
  (let (proposed)
    (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan)
               (lambda (plan &rest _) (setq proposed plan))))
      (emacsvox-aural-change-feedback-proposed))
    proposed))

(ert-deftest emacsvox-aural-guided-back-keeps-voice-and-returns-one-level ()
  "q backs out of nested voice choices without selecting or losing the draft."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (let ((draft (copy-tree emacsvox-aural-change-feedback-render)) spoken dismissed)
      (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
                ((symbol-function 'emacsvox-aural-quit) (lambda (&rest _) (setq dismissed t))))
        (call-interactively (key-binding (kbd "q")))
        (should (eq emacsvox-aural-change-feedback--expanded 'operations))
        (should (equal (tabulated-list-get-id) '(operation "Change the content voice")))
        (should (equal spoken "Content voice"))
        (should-not dismissed)
        (call-interactively (key-binding (kbd "q")))
        (should-not emacsvox-aural-change-feedback--expanded)
        (should (eq (tabulated-list-get-id) 'change))
        (should (equal spoken "Change"))
        (should-not dismissed)
        (call-interactively (key-binding (kbd "q")))
        (should dismissed)
        (should (equal draft emacsvox-aural-change-feedback-render))))))

(ert-deftest emacsvox-aural-guided-remap-back-has-no-component-level ()
  "The simple voice mapping panel returns directly to Voice."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback--voice-remap t)
    (emacsvox-aural-change-feedback-change)
    (should (emacsvox-aural-ui-goto-row '(voice bolden)))
    (call-interactively (key-binding (kbd "q")))
    (should-not emacsvox-aural-change-feedback--expanded)
    (should (eq (tabulated-list-get-id) 'change))))

(ert-deftest emacsvox-aural-guided-voice-preview-before-lifetime ()
  "A voice change can be heard while all live layers remain unchanged."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (should-not emacsvox-aural-change-feedback-scope)
    (should-not emacsvox-aural-change-feedback-selector)
    (let* ((plan (emacsvox-test--guided-proposed))
           (content (emacsvox-aural-render-plan-content (emacsvox-aural-concrete-plan-source-plan plan))))
      (should (eq (emacsvox-aural-content-style-voice content) 'bolden)))
    (should-not emacsvox-aural-user-rules)
    (should-not emacsvox-aural-session-rules)
    (should-not (buffer-local-value 'emacsvox-aural-buffer-rules source))
    (should-error (emacsvox-aural-change-feedback-apply) :type 'user-error)))

(ert-deftest emacsvox-aural-guided-vocabulary-returns-to-matching-criteria ()
  "Vocabulary lookup preserves the draft and q still closes its match section."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (emacsvox-aural-change-feedback-match)
    (should (emacsvox-aural-ui-goto-row 'vocabulary))
    (let ((editor (current-buffer))
          (draft (copy-tree emacsvox-aural-change-feedback-render)))
      (emacsvox-aural-change-feedback-open-row)
      (should-not (eq (current-buffer) editor))
      (emacsvox-aural-quit)
      (should (eq (current-buffer) editor))
      (should (eq (tabulated-list-get-id) 'vocabulary))
      (emacsvox-aural-change-feedback--back)
      (should (eq (tabulated-list-get-id) 'match))
      (should-not emacsvox-aural-change-feedback--expanded)
      (should (equal draft emacsvox-aural-change-feedback-render)))))

(ert-deftest emacsvox-aural-guided-add-components-without-existing-cue ()
  "Sound, tone, and speech additions preserve spoken content and other phases."
  (emacsvox-test--with-guided-feedback
    (should-not (emacsvox-aural-change-feedback--components 'cue))
    (dolist (kind '(cue tone speech))
      (let ((numbers '(440 80)))
        (cl-letf (((symbol-function 'read-number) (lambda (&rest _) (pop numbers)))
                  ((symbol-function 'read-string) (lambda (&rest _) "expanded to")))
          (pcase kind
            ('cue (emacsvox-test--guided-choose "Add a sound" "Before content" "open-object"))
            ('tone (emacsvox-test--guided-choose "Add a tone" "Before content" "Pitch and duration"))
            ('speech (emacsvox-test--guided-choose "Add a spoken label" "Before content")))))
      (let* ((plan (emacsvox-test--guided-proposed))
             (action (car (emacsvox-aural-concrete-plan-before plan))))
        (should (eq (emacsvox-aural-concrete-action-kind action) kind))
        (should (emacsvox-aural-concrete-content-speak (emacsvox-aural-concrete-plan-content plan)))
        (should-not (emacsvox-aural-concrete-plan-after plan))
        (when (eq kind 'speech) (should (equal (emacsvox-aural-concrete-action-text action) "expanded to")))))
    (should-not emacsvox-aural-session-rules)))

(ert-deftest emacsvox-aural-guided-replace-and-suppress-one-component ()
  "Changing a before cue retains its identity and the same-ID cue after content."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-session-rules
          '((:id original-cues :match (:role heading)
                 :render (:before (:append ((:id cue :kind cue :cue open-object :volume 0.6 :anchor object)))
                          :after (:append ((:id cue :kind cue :cue close-object :anchor object)))))))
    (let* ((plan (emacsvox-aural-compile-plan (emacsvox-aural-resolve-active facts context) facts context)))
      (setq emacsvox-aural-change-feedback-input (plist-put emacsvox-aural-change-feedback-input :concrete plan)))
    (cl-letf (((symbol-function 'emacsvox-aural-change-feedback--choose-component)
               (lambda (&rest _) (cdar (emacsvox-aural-change-feedback--components 'cue)))))
      (emacsvox-test--guided-choose "Replace a sound" "select-object")
      (let ((plan (emacsvox-test--guided-proposed)))
        (should (eq (emacsvox-aural-concrete-action-cue (car (emacsvox-aural-concrete-plan-before plan))) 'select-object))
        (should (= (emacsvox-aural-concrete-action-requested-volume (car (emacsvox-aural-concrete-plan-before plan))) 0.6))
        (should (eq (emacsvox-aural-concrete-action-cue (car (emacsvox-aural-concrete-plan-after plan))) 'close-object)))
      (emacsvox-test--guided-choose "Suppress one component")
      (let ((plan (emacsvox-test--guided-proposed)))
        (should-not (emacsvox-aural-concrete-plan-before plan))
        (should (= 1 (length (emacsvox-aural-concrete-plan-after plan))))))))

(ert-deftest emacsvox-aural-guided-change-tone-and-suppress-content ()
  "A tone keeps its playback mode; suppressing content leaves the tone intact."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-session-rules
          '((:id original-tone :match (:role heading)
                 :render (:before (:append ((:id tone :kind tone :pitch 300 :duration 60 :audio-mode insert :anchor object)))))))
    (setq emacsvox-aural-change-feedback-input
          (plist-put emacsvox-aural-change-feedback-input :concrete
                     (emacsvox-aural-compile-plan (emacsvox-aural-resolve-active facts context) facts context)))
    (let ((values '(600 120)))
      (cl-letf (((symbol-function 'emacsvox-aural-change-feedback--choose-component)
                 (lambda (&rest _) (cdar (emacsvox-aural-change-feedback--components 'tone))))
                ((symbol-function 'read-number) (lambda (&rest _) (pop values))))
        (emacsvox-test--guided-choose "Change a tone" "Pitch and duration")))
    (let ((action (car (emacsvox-aural-concrete-plan-before (emacsvox-test--guided-proposed)))))
      (should (= (emacsvox-aural-concrete-action-pitch action) 600))
      (should (= (emacsvox-aural-concrete-action-duration action) 120))
      (should (eq (emacsvox-aural-concrete-action-audio-mode action) 'insert)))
    (emacsvox-test--guided-choose "Suppress one component" "Spoken content")
    (let ((plan (emacsvox-test--guided-proposed)))
      (should-not (emacsvox-aural-concrete-content-speak (emacsvox-aural-concrete-plan-content plan)))
      (should (= 1 (length (emacsvox-aural-concrete-plan-before plan)))))))

(ert-deftest emacsvox-aural-guided-cancel-choice-retains-draft ()
  "Aborting a later minibuffer leaves the previous candidate and live state intact."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (let ((before (copy-tree emacsvox-aural-change-feedback-render)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (signal 'quit nil))))
        (condition-case nil (emacsvox-aural-change-feedback--change "Add a sound") (quit nil)))
      (should (equal before emacsvox-aural-change-feedback-render)))
    (should (memq (current-buffer) (emacsvox-aural-home--pending-drafts)))
    (should-not emacsvox-aural-session-rules)))

(ert-deftest emacsvox-aural-guided-buffer-match-summary-and-apply ()
  "A buffer rule is described as affecting every matching item, and only that layer changes."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (setq emacsvox-aural-change-feedback-selector (emacsvox-aural-change-feedback--suggested-selector)
          emacsvox-aural-change-feedback-scope 'buffer)
    (should (string-match-p "all matching items in buffer" (emacsvox-aural-change-feedback--summary)))
    (emacsvox-aural-change-feedback-apply)
    (should emacsvox-aural-change-feedback-applied)
    (should-not emacsvox-aural-user-rules)
    (should-not emacsvox-aural-session-rules)
    (should (= 1 (length (buffer-local-value 'emacsvox-aural-buffer-rules source))))
    (emacsvox-test--guided-choose "Change the content voice" "lighten")
    (emacsvox-aural-change-feedback-apply)
    (should (= 1 (length (buffer-local-value 'emacsvox-aural-buffer-rules source))))))

(ert-deftest emacsvox-aural-guided-failed-save-rolls-back-and-retains-draft ()
  "A failed personal write cannot claim success or leave an applied override."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (setq emacsvox-aural-change-feedback-selector (emacsvox-aural-change-feedback--suggested-selector)
          emacsvox-aural-change-feedback-scope 'personal)
    (cl-letf (((symbol-function 'emacsvox-aural-save-user-data) (lambda (&rest _) (error "disk full"))))
      (emacsvox-aural-change-feedback-apply))
    (should-not emacsvox-aural-change-feedback-applied)
    (should emacsvox-aural-change-feedback-render)
    (should-not emacsvox-aural-user-rules)))

(ert-deftest emacsvox-aural-guided-edited-source-blocks-apply ()
  "A generated current-item draft does not silently apply after its example changed."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (setq emacsvox-aural-change-feedback-selector (emacsvox-aural-change-feedback--suggested-selector)
          emacsvox-aural-change-feedback-scope 'session
          emacsvox-aural-change-feedback-input
          (plist-put emacsvox-aural-change-feedback-input :source-guard
                     (emacsvox-aural-inspection-source-guard)))
    (with-current-buffer source (delete-char 1))
    (should-error (emacsvox-aural-change-feedback-apply) :type 'user-error)
    (should-not emacsvox-aural-session-rules)))

(ert-deftest emacsvox-aural-guided-later-rule-wins-an-equal-existing-match ()
  "An appended change follows the layer's explicit order, including saved rules."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback-scope 'session
          emacsvox-aural-change-feedback-selector (emacsvox-aural-change-feedback--suggested-selector)
          emacsvox-aural-session-rules
          (list (list :id 'previous :order 12 :match emacsvox-aural-change-feedback-selector
                      :render '(:content (:voice lighten)))))
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (let* ((plan (emacsvox-test--guided-proposed))
           (content (emacsvox-aural-render-plan-content (emacsvox-aural-concrete-plan-source-plan plan))))
      (should (eq (emacsvox-aural-content-style-voice content) 'bolden)))))

(ert-deftest emacsvox-aural-guided-dirty-editor-blocks-apply ()
  "A second interface cannot silently write over an unfinished editor."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (setq emacsvox-aural-change-feedback-selector (emacsvox-aural-change-feedback--suggested-selector)
          emacsvox-aural-change-feedback-scope 'session)
    (let ((draft (current-buffer))
          (editor (emacsvox-edit-aural-rules 'session nil source)))
      (with-current-buffer editor (setq emacsvox-aural-editor-dirty t))
      (with-current-buffer draft
        (should-error (emacsvox-aural-change-feedback-apply) :type 'user-error)))
    (should-not emacsvox-aural-session-rules)))

(ert-deftest emacsvox-aural-guided-history-selects-and-replays-exact-part ()
  "A multi-part record expands parts, keeps the selection frozen, and labels it."
  (emacsvox-test--with-guided-feedback
    (let* ((second-facts '(:role heading :content "Second part"))
           (second-plan (emacsvox-aural-compile-plan
                         (emacsvox-aural-resolve-active second-facts context) second-facts context))
           (record (emacsvox-aural--make-presentation-record
                    :id 123 :plan concrete :plans (list concrete second-plan)))
           played)
      (emacsvox-aural-change-feedback record)
      (should (emacsvox-aural-ui-goto-row '(part 2)))
      (call-interactively (key-binding (kbd "q")))
      (should (eq (tabulated-list-get-id) 'target))
      (should-not emacsvox-aural-change-feedback--part-number)
      (emacsvox-aural-change-feedback-open-row)
      (should (emacsvox-aural-ui-goto-row '(part 2)))
      (emacsvox-aural-change-feedback-open-row)
      (should (equal (plist-get (plist-get emacsvox-aural-change-feedback-input :facts) :content) "Second part"))
      (should (string-match-p "record 123, Part 2" (emacsvox-aural-change-feedback--summary)))
      (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan) (lambda (plan &rest _) (setq played plan))))
        (emacsvox-aural-change-feedback-original))
      (should (eq played second-plan)))))

(ert-deftest emacsvox-aural-guided-parts-stay-in-playback-order-and-retain-voices ()
  "More than nine parts stay ordered, and navigation uses frozen speech data."
  (emacsvox-test--with-guided-feedback
    (let* ((plans
            (cl-loop for n from 1 to 12
                     collect
                     (let* ((plan (copy-emacsvox-aural-concrete-plan concrete))
                            (content (copy-emacsvox-aural-concrete-content
                                      (emacsvox-aural-concrete-plan-content plan))))
                       (setf (emacsvox-aural-concrete-content-text content) (format "Example %d" n)
                             (emacsvox-aural-concrete-content-voice-request content) 'lighten
                             (emacsvox-aural-concrete-content-voice-style content) '(:echo 4)
                             (emacsvox-aural-concrete-content-voice-command content) "[[logical_voice lighten]]"
                             (emacsvox-aural-concrete-plan-content plan) content)
                       plan)))
           (record (emacsvox-aural--make-presentation-record
                    :id 124 :plan (car plans) :plans plans))
           spoken played)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (ert-fail "Parts must not use completion"))))
        (emacsvox-aural-change-feedback record))
      (should (equal (cl-loop for (id _) in tabulated-list-entries
                              when (eq (car-safe id) 'part) collect (cadr id))
                     (number-sequence 1 12)))
      (should-error (emacsvox-aural-change-feedback-change) :type 'user-error)
      (emacsvox-aural-ui-goto-row '(part 9))
      (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
                ((symbol-function 'emacsvox-aural-ui-speak)
                 (lambda (text) (funcall emacsvox-aural-ui-speech-function text)))
                ((symbol-function 'emacsvox-icon) #'ignore))
        (emacsvox-aural-ui-next-row))
      (should (equal (tabulated-list-get-id) '(part 10)))
      (let* ((plan (emacsvox-aural-concrete-plan-at (string-match "Example 10" spoken) spoken))
             (content (emacsvox-aural-concrete-plan-content plan)))
        (should (eq (emacsvox-aural-concrete-content-voice-request content) 'lighten))
        (should (equal (emacsvox-aural-concrete-content-voice-style content) '(:echo 4)))
        (should (equal (emacsvox-aural-concrete-content-voice-command content) "[[logical_voice lighten]]"))
        (should-not (emacsvox-aural-concrete-plan-before plan)))
      (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan)
                 (lambda (plan &rest _) (setq played plan))))
        (emacsvox-aural-change-feedback-original))
      (should (eq played (nth 9 plans)))
      (should (equal (emacsvox-aural-concrete-content-text
                      (emacsvox-aural-concrete-plan-content played)) "Example 10")))))

(ert-deftest emacsvox-aural-guided-voice-panel-identifies-original-and-proposal ()
  "Alias voices are identified first; alternatives stay ordered and visible."
  (emacsvox-test--with-guided-feedback
    (setf (emacsvox-aural-concrete-content-voice-request
           (emacsvox-aural-concrete-plan-content concrete)) 'voice-lighten)
    (cl-letf (((symbol-function 'emacsvox-aural-change-feedback--named-voice)
               (lambda (_) '(acss-default lighten)))
              ((symbol-function 'emacsvox-aural-tools--voice-remap-candidates)
               (lambda () '("lighten" "default" "bolden"))))
      (emacsvox-aural-change-feedback-change)
      (emacsvox-aural-ui-goto-row '(operation "Change the content voice"))
      (emacsvox-aural-change-feedback-open-row)
      (should (equal (cl-loop for (id _) in tabulated-list-entries
                              when (eq (car-safe id) 'voice) collect (cadr id))
                     '(lighten bolden default)))
      (emacsvox-aural-ui-goto-row '(voice bolden))
      (emacsvox-aural-change-feedback-open-row)
      (should (equal (tabulated-list-get-id) '(voice bolden)))
      (should (string-match-p "Selected for draft" (aref (tabulated-list-get-entry) 1)))
      (should (string-match-p "Original voice: Voice lighten; proposed: Content voice bolden"
                              (emacsvox-aural-change-feedback--voice-description)))
      (should (eq emacsvox-aural-change-feedback--expanded 'voices))
      (emacsvox-aural-change-feedback-change)
      (should-not emacsvox-aural-change-feedback--expanded)
      (should emacsvox-aural-change-feedback-render)
      (should-not emacsvox-aural-session-rules))))

(ert-deftest emacsvox-aural-guided-default-selects-the-palette-voice ()
  "Choosing default retains its named identity in the proposed rule."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "default")
    (should (equal emacsvox-aural-change-feedback-render
                   '(:content (:voice default))))))

(ert-deftest emacsvox-aural-guided-part-switch-keeps-unfinished-drafts ()
  "Returning to another part restores its draft and keeps it resumable from Home."
  (emacsvox-test--with-guided-feedback
    (emacsvox-aural-change-feedback
     (emacsvox-aural--make-presentation-record
      :id 125 :plan concrete :plans (list concrete concrete)))
    (emacsvox-aural-change-feedback--select-part 1)
    (emacsvox-test--guided-choose "Change the content voice" "bolden")
    (let ((draft (copy-tree emacsvox-aural-change-feedback-render)))
      (emacsvox-aural-change-feedback--select-part 2)
      (should-not emacsvox-aural-change-feedback-render)
      (should (memq (current-buffer) (emacsvox-aural-home--pending-drafts)))
      (emacsvox-aural-change-feedback--select-part 1)
      (should (equal draft emacsvox-aural-change-feedback-render))
      (setq emacsvox-aural-change-feedback-applied t)
      (should-not (memq (current-buffer) (emacsvox-aural-home--pending-drafts))))))

(ert-deftest emacsvox-aural-guided-match-can-ignore-notmuch-unread-state ()
  "Excluding unread matches read and unread authors while retaining other limits."
  (emacsvox-test--with-guided-feedback
    (emacsvox-test--guided-choose "Change the content voice" "lighten")
    (setq emacsvox-aural-change-feedback-selector
          '(:role field :states (unread) :field-kind authors :module notmuch))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (ert-fail "Matching must expand in the panel"))))
      (emacsvox-aural-change-feedback-match))
    (should (emacsvox-aural-ui-goto-row '(criterion (:states (unread)))))
    (should (equal (aref (tabulated-list-get-entry) 1) "Included"))
    (emacsvox-aural-change-feedback-open-row)
    (should (equal (tabulated-list-get-id) '(criterion (:states (unread)))))
    (should (equal (aref (tabulated-list-get-entry) 1) "Excluded"))
    (should (equal (emacsvox-aural-change-feedback--selector-description
                    emacsvox-aural-change-feedback-selector)
                   "Items with role field, with field kind authors, and from the notmuch integration"))
    (let ((rule (emacsvox-aural-compile-rule (emacsvox-aural-change-feedback--rule) 'user)))
      (dolist (states '(nil (unread)))
        (should (emacsvox-aural-rule-matches-p
                 rule (emacsvox-aural-normalize-input
                       (list :role 'field :field-kind 'authors :states states)
                       '(:module notmuch)))))
      (should-not (emacsvox-aural-rule-matches-p
                   rule (emacsvox-aural-normalize-input
                         '(:role field :field-kind subject) '(:module notmuch))))
      (should-not (emacsvox-aural-rule-matches-p
                   rule (emacsvox-aural-normalize-input
                         '(:role field :field-kind authors) '(:module gnus)))))
    ;; Closing and reopening preserves the exclusion and offers it for restoration.
    (emacsvox-aural-change-feedback-match)
    (emacsvox-aural-change-feedback-match)
    (should (emacsvox-aural-ui-goto-row '(criterion (:states (unread)))))
    (emacsvox-aural-change-feedback-open-row)
    (should (equal (plist-get emacsvox-aural-change-feedback-selector :states) '(unread)))
    (should-not emacsvox-aural-session-rules)
    (should-not emacsvox-aural-user-rules)))

(ert-deftest emacsvox-aural-guided-shell-match-summary-follows-included-conditions ()
  "The shell summary explains every limit and drops excluded conditions."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback-selector
          '(:module shell :mode shell-mode :occasion navigation
            :legacy-face comint-highlight-prompt))
    (emacsvox-aural-change-feedback-match)
    (should (equal (aref (cadr (assq 'match tabulated-list-entries)) 1)
                   (concat "Items from the shell integration, in shell mode, "
                           "during navigation, and with text style comint highlight prompt")))
    (should (emacsvox-aural-ui-goto-row '(criterion (:occasion navigation))))
    (emacsvox-aural-change-feedback-open-row)
    (should (equal (aref (tabulated-list-get-entry) 1) "Excluded"))
    (should (equal (aref (cadr (assq 'match tabulated-list-entries)) 1)
                   (concat "Items from the shell integration, in shell mode, "
                           "and with text style comint highlight prompt")))
    (should (equal emacsvox-aural-change-feedback-selector
                   '(:module shell :mode shell-mode :legacy-face comint-highlight-prompt)))))

(ert-deftest emacsvox-aural-guided-match-toggles-states-individually ()
  "Excluding one state preserves other states, and viewing keeps saved status."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback-selector
          '(:role field :states (unread selected) :module notmuch)
          emacsvox-aural-change-feedback-applied t)
    (emacsvox-aural-change-feedback-match)
    (should emacsvox-aural-change-feedback-applied)
    (emacsvox-aural-ui-goto-row '(criterion (:states (unread))))
    (emacsvox-aural-change-feedback-open-row)
    (should (equal (plist-get emacsvox-aural-change-feedback-selector :states) '(selected)))
    (should-not emacsvox-aural-change-feedback-applied)))

(ert-deftest emacsvox-aural-guided-match-retains-at-least-one-criterion ()
  "An empty match cannot be confused with matching criteria not yet chosen."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback-selector '(:module notmuch))
    (emacsvox-aural-change-feedback-match)
    (emacsvox-aural-ui-goto-row '(criterion (:module notmuch)))
    (should-error (emacsvox-aural-change-feedback-open-row) :type 'user-error)
    (should (equal emacsvox-aural-change-feedback-selector '(:module notmuch)))))

(ert-deftest emacsvox-aural-guided-match-preserves-required-role-on-invalid-toggle ()
  "A criterion needing a role cannot leave the draft with an invalid selector."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback-selector
          '(:role field :field-kind authors :module notmuch))
    (emacsvox-aural-change-feedback-match)
    (emacsvox-aural-ui-goto-row '(criterion (:role field)))
    (should-error (emacsvox-aural-change-feedback-open-row) :type 'emacsvox-aural-rule-error)
    (should (eq (plist-get emacsvox-aural-change-feedback-selector :role) 'field))))

(ert-deftest emacsvox-aural-guided-remap-matching-expands-under-applies-to ()
  "The simple remap view also exposes its matching criteria in the panel."
  (emacsvox-test--with-guided-feedback
    (setq emacsvox-aural-change-feedback--voice-remap t
          emacsvox-aural-change-feedback-selector '(:role heading :states (selected)))
    (emacsvox-aural-change-feedback-refresh 'target)
    (emacsvox-aural-change-feedback-open-row)
    (should (eq emacsvox-aural-change-feedback--expanded 'match))
    (should (emacsvox-aural-ui-goto-row '(criterion (:states (selected)))))
    (emacsvox-aural-change-feedback-open-row)
    (should (equal emacsvox-aural-change-feedback-selector '(:role heading)))
    (call-interactively (key-binding (kbd "q")))
    (should (eq (tabulated-list-get-id) 'target))
    (should-not emacsvox-aural-change-feedback--expanded)))

(ert-deftest emacsvox-aural-guided-graphical-minibuffer-history-follows-origin ()
  "Real lifetime prompts exclude Aural feedback but retain ordinary completion."
  (skip-unless (display-graphic-p))
  (require 'package)
  (package-initialize)
  (require 'vertico)
  (require 'emacsvox-vertico)
  (require 'emacsvox-advice)
  (message "Vertico %s: %s"
           (package-version-join (package-desc-version (cadr (assq 'vertico package-alist))))
           (symbol-file 'vertico--exhibit))
  (let ((original-vertico-mode vertico-mode))
    (unwind-protect
        (progn
          (vertico-mode 1)
          (emacsvox-test--with-guided-feedback
            (let ((editor (current-buffer))
                  (record (symbol-function 'emacsvox-aural-record-presentation))
                  (emacsvox-use-icons t)
                  (emacsvox-aural-plan-presented-hook nil)
                  (vertico-sort-function nil)
                  observed)
              (cl-letf
                  (((symbol-function 'tts-stop) #'ignore)
                   ((symbol-function 'emacsvox-icon)
                    (lambda (icon) (emacsvox-aural-present-legacy-icon icon)))
                   ((symbol-function 'emacsvox-sounds-play-concrete-cue) #'ignore)
                   ((symbol-function 'emacsvox-sounds-ensure-sample) (lambda (_resource sample-id) sample-id))
                   ;; Replace only speech delivery; keep native source planning,
                   ;; transaction history, and standalone icon recording real.
                   ((symbol-function 'tts-speak)
                    (lambda (text)
                      (let ((position 0))
                        (while (< position (length text))
                          (let ((plan (emacsvox-aural-concrete-plan-at position text))
                                (end (next-single-property-change
                                      position emacsvox-aural-concrete-plan-property text (length text))))
                            (when plan
                              (emacsvox-aural-record-presentation plan (substring text position end)))
                            (setq position end))))))
                   ((symbol-function 'emacsvox-aural-record-presentation)
                    (lambda (plan &rest arguments)
                      (when (string-match-p
                             "Minibuf-" (or (plist-get (emacsvox-aural-concrete-plan-context plan)
                                                       :source-buffer-name) ""))
                        (push plan observed))
                      (apply record plan arguments))))
                ;; Reuse the same minibuffer across both origins and settings.
                (dolist (case '((t nil nil) (t t t) (nil nil t) (t nil nil)))
                  (pcase-let ((`(,interface ,include ,retain) case))
                    (switch-to-buffer (if interface editor source))
                    (let ((emacsvox-aural-history-record-interface-presentations include)
                          (emacsvox-aural-presentation-history nil))
                      (setq observed nil)
                      (minibuffer-with-setup-hook
                          (lambda ()
                            (with-current-buffer source
                              (should-not (plist-get (emacsvox-aural-capture-context)
                                                     :history-recording-inhibited)))
                            (setq unread-command-events
                                  (listify-key-sequence (kbd "C-n C-p RET"))))
                        (if interface
                            (emacsvox-aural-change-feedback-lifetime)
                          (completing-read "Ordinary choice: " '("First" "Second") nil t)))
                      (should (cl-some (lambda (plan)
                                        (eq (plist-get (emacsvox-aural-concrete-plan-facts plan) :role)
                                            'candidate)) observed))
                      (dolist (cue '(open-object close-object))
                        (should (cl-some
                                 (lambda (plan)
                                   (cl-find cue (append (emacsvox-aural-concrete-plan-before plan)
                                                        (emacsvox-aural-concrete-plan-after plan))
                                            :key #'emacsvox-aural-concrete-action-cue)) observed)))
                      (should (eq (not (null emacsvox-aural-presentation-history)) retain))
                      (dolist (plan observed)
                        (should (eq (not (null (plist-get (emacsvox-aural-concrete-plan-context plan)
                                                         :history-recording-inhibited)))
                                    (not retain)))))))))))
      (vertico-mode (if original-vertico-mode 1 -1)))))

(provide 'emacsvox-aural-change-feedback-tests)
;;; emacsvox-aural-change-feedback-tests.el ends here
