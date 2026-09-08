;;; emacsvox-aural-voice-context-tests.el --- Voice cascade editing contracts -*- lexical-binding: t; -*-
;;; Commentary:
;; Verify scoped partial edits and frozen context previews without saving bases.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-voice-editor-tests)
(require 'emacsvox-aural-voice-context)

(defun emacsvox-test--voice-context-input (&rest contributions)
  "Build captured heading input from ordered CONTRIBUTIONS."
  (list :facts '(:role heading) :context '(:mode fundamental-mode :voice-lock-enabled nil)
        :rules (cl-loop for (id voice) in contributions for order from 0
                        collect (emacsvox-aural-compile-rule
                                 (list :id id :order order :match '(:role heading)
                                       :render (list :content (list :voice voice))) 'user))))

(ert-deftest emacsvox-aural-voice-context-fields-preserve-nil-zero-and-other-components ()
  (let* ((rule '(:id test :match (:role heading) :render
                     (:before ((:id cue :kind cue :cue open-object))
                              :content (:voice (:average-pitch nil :gain 0) :speak t))))
         (changed (emacsvox-aural-voice-context--patch-field rule 'richness 'set 8))
         (inherited (emacsvox-aural-voice-context--patch-field changed 'richness 'inherit nil)))
    (should (equal rule inherited))
    (should (equal (plist-get (plist-get (plist-get changed :render) :content) :voice)
                   '(:average-pitch nil :gain 0 :richness 8)))
    (should-not (plist-member (plist-get (plist-get (plist-get changed :render) :content) :voice) :preset))
    (should-not (plist-get (emacsvox-aural-voice-context--patch-field
                            '(:id empty :match (:role heading) :render (:content (:voice (:richness 8))))
                            'richness 'inherit nil) :render))))

(ert-deftest emacsvox-aural-voice-context-existing-preset-reset-survives-field-edit ()
  (dolist (preset '(bolden nil))
    (let* ((rule (list :id 'test :match '(:role heading) :render (list :content (list :voice preset))))
           (changed (emacsvox-aural-voice-context--patch-field rule 'richness 'set 8))
           (voice (plist-get (plist-get (plist-get changed :render) :content) :voice)))
      (should (plist-member voice :preset))
      (should (eq (plist-get voice :preset) preset)))))

(ert-deftest emacsvox-aural-voice-context-independent-fields-precedence-and-base-masking ()
  (emacsvox-test--with-voice-editor
   (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
   (emacsvox-aural-voice-editor--put :automatic-sample nil)
   (emacsvox-aural-voice-editor--set 'average-pitch 8)
   (let* ((input (emacsvox-test--voice-context-input '(base bolden) '(pitch (:average-pitch 2))
                                                     '(rich (:richness 8)) '(rate-a (:rate-offset 2))
                                                     '(rate-b (:rate-offset 3))))
          (result (emacsvox-aural-voice-context--resolve
                   emacsvox-aural-voice-editor--context (emacsvox-aural-voice-editor--working) input)))
     (should (= (plist-get (plist-get result :requested) :average-pitch) 2))
     (should (= (plist-get (plist-get result :requested) :richness) 8))
     (should (= (plist-get (plist-get result :requested) :rate-offset) 3))
     (should (memq 'average-pitch (plist-get result :masked)))
     (should (eq (alist-get 'average-pitch (plist-get result :origins)) 'pitch))
     (should (eq (alist-get 'richness (plist-get result :origins)) 'rich))
     (should (= (plist-get (plist-get (emacsvox-aural-voice-editor--working) :definition) :average-pitch) 8)))))

(ert-deftest emacsvox-aural-voice-context-preset-reset-discards-earlier-fields ()
  (emacsvox-test--with-voice-editor
   (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
   (let* ((input (emacsvox-test--voice-context-input '(early (:richness 1 :average-pitch 7))
                                                     '(reset bolden) '(later (:stress 1))))
          (result (emacsvox-aural-voice-context--resolve
                   emacsvox-aural-voice-editor--context (emacsvox-aural-voice-editor--working) input)))
     (should (= (plist-get (plist-get result :requested) :average-pitch) 0))
     (should (= (plist-get (plist-get result :requested) :richness) 9))
     (should (= (plist-get (plist-get result :requested) :stress) 1))
     (should (equal (plist-get result :masked) '(stress))))))

(ert-deftest emacsvox-aural-voice-context-nil-keeps-acss-command-contract-but-clears-effects ()
  (emacsvox-test--with-voice-editor
   (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
   (emacsvox-aural-voice-editor--put :automatic-sample nil)
   (emacsvox-aural-voice-editor--set 'average-pitch 6)
   (emacsvox-aural-voice-editor--set 'echo 7)
   (let* ((result (emacsvox-aural-voice-context--resolve
                   emacsvox-aural-voice-editor--context (emacsvox-aural-voice-editor--working)
                   (emacsvox-test--voice-context-input '(base bolden) '(clear (:average-pitch nil :echo nil :pan 0)))))
          (entry (emacsvox-aural-voice-editing--preview (plist-get result :snapshot) 'reading-owned nil "Text")))
     (should-not (plist-get (plist-get result :requested) :average-pitch))
     (should (= (plist-get (plist-get entry :acss) :average-pitch) (/ 6.0 9)))
     (should-not (plist-get (plist-get entry :effects) :echo))
     (should (= (plist-get (plist-get entry :effects) :pan) 0)))))

(ert-deftest emacsvox-aural-voice-context-inherit-restores-weaker-value ()
  (let* ((input (emacsvox-test--voice-context-input '(weak (:richness 3)) '(strong (:richness 8))))
         (strong (emacsvox-aural-voice-context--patch-field
                  '(:id strong :order 1 :match (:role heading) :render (:content (:voice (:richness 8))))
                  'richness 'inherit nil)))
    (setf (cadr (plist-get input :rules)) (emacsvox-aural-compile-rule strong 'user))
    (should (= (plist-get (emacsvox-aural-content-style-voice
                           (emacsvox-aural-render-plan-content
                            (emacsvox-aural-resolve (plist-get input :facts) (plist-get input :context) (plist-get input :rules))))
                          :richness) 3))))

(ert-deftest emacsvox-aural-voice-context-preview-freezes-input-and-rejects-changed-source ()
  (emacsvox-test--with-voice-editor
   (let ((source (generate-new-buffer " *voice-context-source*")) view)
     (unwind-protect
         (progn
           (switch-to-buffer source)
           (insert "Heading") (goto-char (point-min))
           (emacsvox-aural-voice-editor-open 'reading-owned 'bolden source)
           (let ((base emacsvox-aural-voice-editor--context)
                 (input (emacsvox-test--voice-context-input '(base bolden) '(pitch (:average-pitch 2)))))
             (setq input (plist-put input :source source))
             (setq input (plist-put input :source-guard (with-current-buffer source (emacsvox-aural-inspection-source-guard))))
             (setq view (generate-new-buffer " *voice-context-view*"))
             (switch-to-buffer view) (emacsvox-aural-voice-context-mode)
             (setq emacsvox-aural-voice-context--base base emacsvox-aural-voice-context--input input)
             (emacsvox-aural-voice-context-refresh)
             (should (string-match-p "Simulation using captured facts" (buffer-string)))
             (emacsvox-aural-voice-context-compare)
             (should (= (length (car requests)) 4))
             (should (string-match-p "in context" (plist-get (caar requests) :text)))
             (should-not callbacks)
             (with-current-buffer source (insert "Changed"))
             (should-error (emacsvox-aural-voice-context-play) :type 'user-error)))
       (when (buffer-live-p view) (kill-buffer view)) (kill-buffer source)))))

(ert-deftest emacsvox-aural-voice-context-scoped-save-leaves-palette-unchanged ()
  (emacsvox-test--with-voice-editor
   (let* ((source (generate-new-buffer " *context-rule-source*"))
          (emacsvox-aural-session-rules nil)
          (emacsvox-aural-user-rules nil)
          (emacsvox-aural-session-rules-enabled t)
          (before (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
          (input (emacsvox-test--voice-context-input '(base bolden)))
          (answers '("this Emacs session" "richness" "Set value")) editor)
     (unwind-protect
         (progn
           (setq input (plist-put input :source source))
           (with-temp-buffer
             (setq emacsvox-aural-voice-context--input input)
             (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (pop answers)))
                       ((symbol-function 'read-string) (lambda (&rest _) "8")))
               (emacsvox-aural-voice-context-adjust)
               (setq editor (current-buffer))))
           (with-current-buffer editor
             (should (equal (plist-get (plist-get (plist-get (car emacsvox-aural-editor-rules) :render) :content) :voice)
                            '(:richness 8)))
             (emacsvox-aural-editor-save))
           (should (= (length emacsvox-aural-session-rules) 1))
           (should (equal before (emacsvox-aural-voice-drafts--palette-data 'reading-owned)))
           (should-not callbacks))
       (when (buffer-live-p editor) (kill-buffer editor)) (kill-buffer source)))))

(ert-deftest emacsvox-aural-voice-context-open-keeps-captured-source-position ()
  (emacsvox-test--with-voice-editor
   (let ((source (generate-new-buffer " *voice-context-open*")) view
         (rules (plist-get (emacsvox-test--voice-context-input '(base bolden)) :rules)))
     (unwind-protect
         (progn
           (switch-to-buffer source)
           (insert (propertize "Heading" emacsvox-aural-facts-property '(:role heading)))
           (insert "\nOther line") (goto-char (point-min))
           (emacsvox-aural-voice-editor-open 'reading-owned 'bolden source)
           (emacsvox-aural-voice-editor--locate 'context)
           (with-current-buffer source
             (goto-char (point-max))
             (when-let* ((window (get-buffer-window source)))
               (set-window-point window (point-max))))
           (cl-letf (((symbol-function 'emacsvox-aural-current-rules) (lambda (&rest _) rules))
                     ((symbol-function 'emacsvox-aural-presentation-at-point) (lambda (&rest _) nil)))
             (setq view (emacsvox-aural-voice-context-open)))
           (should (derived-mode-p 'emacsvox-aural-voice-context-mode))
           (should (eq (plist-get (plist-get emacsvox-aural-voice-context--input :facts) :role) 'heading))
           (should (equal (plist-get (emacsvox-aural-voice-context--current) :preset) 'bolden))
           (should-not callbacks)
           (with-current-buffer source (should (= (point) (point-max))))
           (with-current-buffer (marker-buffer emacsvox-aural-voice-context--origin)
             (emacsvox-aural-voice-editor-refresh))
           (emacsvox-aural-voice-context-return)
           (should (equal (get-text-property (point) 'voice-field) 'context)))
       (when (buffer-live-p view) (kill-buffer view)) (kill-buffer source)))))

(ert-deftest emacsvox-aural-voice-context-different-preset-and-silence-mask-base ()
  (emacsvox-test--with-voice-editor
   (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
   (dolist (preset '(nil inaudible))
     (let ((result (emacsvox-aural-voice-context--resolve
                    emacsvox-aural-voice-editor--context (emacsvox-aural-voice-editor--working)
                    (emacsvox-test--voice-context-input (list 'reset preset)))))
       (should-not (plist-get result :uses-base))
       (should (eq (not (plist-get result :speaks)) (eq preset 'inaudible)))))))

(ert-deftest emacsvox-aural-voice-context-explicit-source-choice-and-recapture-use-current-point ()
  (emacsvox-test--with-voice-editor
   (let ((source (generate-new-buffer " *voice-context-recapture*")) view
         (rules (plist-get (emacsvox-test--voice-context-input '(base bolden)) :rules)))
     (unwind-protect
         (progn
           (switch-to-buffer source)
           (insert (propertize "First\n" emacsvox-aural-facts-property '(:role heading :level 1)))
           (insert (propertize "Second" emacsvox-aural-facts-property '(:role heading :level 2)))
           (goto-char (point-min))
           (emacsvox-aural-voice-editor-open 'reading-owned 'bolden source)
           (with-current-buffer source
             (goto-char (point-max))
             (when-let* ((window (get-buffer-window source))) (set-window-point window (point-max))))
           (cl-letf (((symbol-function 'read-buffer) (lambda (&rest _) (buffer-name source)))
                     ((symbol-function 'emacsvox-aural-current-rules) (lambda (&rest _) rules))
                     ((symbol-function 'emacsvox-aural-presentation-at-point) (lambda (&rest _) nil)))
             (setq view (emacsvox-aural-voice-context-open t))
             (should (= (plist-get (plist-get emacsvox-aural-voice-context--input :facts) :level) 2))
             (emacsvox-aural-voice-context-recapture)
             (should (= (plist-get (plist-get emacsvox-aural-voice-context--input :facts) :level) 2))))
       (when (buffer-live-p view) (kill-buffer view)) (kill-buffer source)))))

(ert-deftest emacsvox-aural-voice-context-playback-ownership-and-unsupported-evidence ()
  (emacsvox-test--with-voice-editor
   (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
   (let* ((base emacsvox-aural-voice-editor--context)
          (source (current-buffer))
          (input (plist-put (emacsvox-test--voice-context-input '(base bolden) '(rich (:richness 8))) :source source))
          pending)
     (with-temp-buffer
       (emacsvox-aural-voice-context-mode)
       (setq emacsvox-aural-voice-context--base base emacsvox-aural-voice-context--input input)
       (cl-letf (((symbol-function 'tts-preview-voices)
                  (lambda (_ callback) (push callback pending))))
         (emacsvox-aural-voice-context-play)
         (emacsvox-aural-voice-context-play))
       (funcall (cadr pending) '(:status failed :message "obsolete"))
       (should-not emacsvox-aural-voice-context--playback)
       (funcall (car pending) '(:status completed :results
                                        ((:realizations ((:engine-id "eloquence" :voice-id "Reed"))
                                                        :degraded-acss (richness)))))
       (should (string-match-p "audio from eloquence/Reed" (buffer-string)))
       (should (string-match-p "unsupported adjustments: (richness)" (buffer-string)))
       (should (= (plist-get (plist-get (emacsvox-aural-voice-context--current) :requested) :richness) 8))
       (setq emacsvox-aural-voice-editor--preview-owner base)
       (emacsvox-aural-voice-context-stop)
       (should (eq emacsvox-aural-voice-editor--preview-owner base))))))

(provide 'emacsvox-aural-voice-context-tests)
;;; emacsvox-aural-voice-context-tests.el ends here
