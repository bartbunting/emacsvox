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
  "Choose a component change with scripted minibuffer ANSWERS."
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (pop answers))))
    (emacsvox-aural-change-feedback-change)))

(defun emacsvox-test--guided-proposed ()
  "Capture the real proposed concrete plan, without speech output."
  (let (proposed)
    (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan)
               (lambda (plan &rest _) (setq proposed plan))))
      (emacsvox-aural-change-feedback-proposed))
    proposed))

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
    (let ((before (copy-tree emacsvox-aural-change-feedback-render)) (count 0))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (if (= (cl-incf count) 1) "Add a sound" (signal 'quit nil)))))
        (condition-case nil (emacsvox-aural-change-feedback-change) (quit nil)))
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
  "A multi-part record prompts for the part, keeps it frozen, and labels the target."
  (emacsvox-test--with-guided-feedback
    (let* ((second-facts '(:role heading :content "Second part"))
           (second-plan (emacsvox-aural-compile-plan
                         (emacsvox-aural-resolve-active second-facts context) second-facts context))
           (record (emacsvox-aural--make-presentation-record
                    :id 123 :plan concrete :plans (list concrete second-plan)))
           played)
      (cl-letf (((symbol-function 'completing-read) (lambda (_prompt choices &rest _) (caadr choices))))
        (emacsvox-aural-change-feedback record))
      (should (equal (plist-get (plist-get emacsvox-aural-change-feedback-input :facts) :content) "Second part"))
      (should (string-match-p "record 123, Part 2" (emacsvox-aural-change-feedback--summary)))
      (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan) (lambda (plan &rest _) (setq played plan))))
        (emacsvox-aural-change-feedback-original))
      (should (eq played second-plan)))))

(provide 'emacsvox-aural-change-feedback-tests)
;;; emacsvox-aural-change-feedback-tests.el ends here
