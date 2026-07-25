;;; emacsvox-aural-transport-tests.el --- Concrete transport tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test source-boundary capture, concrete cue and voice compilation, strict
;; queue ordering, legacy adapters, and owned Pulse/PipeWire sample lifecycles.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-sounds)
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
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-sounds-current-pack 'chimes))
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

(ert-deftest emacsvox-aural-transport-captures-source-context ()
  "Source buffer, name, mode, module, and occasion are frozen together."
  (with-temp-buffer
    (rename-buffer "transport-source" t)
    (setq
     major-mode 'emacs-lisp-mode
     emacsvox-aural-module 'elisp)
    (let ((context (emacsvox-aural-capture-context nil 'navigation)))
      (should (eq (plist-get context :source-buffer) (current-buffer)))
      (should
       (equal
        (plist-get context :source-buffer-name)
        "transport-source"))
      (should (eq (plist-get context :mode) 'emacs-lisp-mode))
      (should (eq (plist-get context :module) 'elisp))
      (should (eq (plist-get context :occasion) 'navigation)))))

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
          "/chimes/item.ogg"
          (emacsvox-aural-concrete-action-resource cue)))
        (should
         (string-prefix-p
          "emacsvox-chimes-item-"
          (emacsvox-aural-concrete-action-sample-id cue)))
        (should
         (equal
          (emacsvox-aural-concrete-content-voice-command
           (emacsvox-aural-concrete-plan-content plan))
          "<voice-bolden>"))))))

(ert-deftest emacsvox-aural-transport-compiles-raw-acss ()
  "A raw ACSS style is named before the selected adapter compiles it."
  (let ((style (make-acss :average-pitch 4 :richness 6))
        events)
    (cl-letf (((symbol-function 'voice-from-acss)
               (lambda (value)
                 (push (list 'acss value) events)
                 'generated-voice))
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
        '((code "<voice-annotate>")
          (text "Heading")
          (code "RESET")
          (cue "item")
          (pause 40)
          (code "RESET")
          (code "<voice-bolden>")
          (text "Title")
          (code "RESET")
          (text "folded")))))))

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
      (should (string-suffix-p "/chimes/item.ogg" queued)))))

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
            "<voice-bolden>")))))))

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
        '(fundamental-mode emacs-lisp-mode "<voice-bolden>"))))))

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
            (setq major-mode 'emacs-lisp-mode)
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
        '(("cap " "<cap-voice>")
          ("Word" "<voice-bolden>")))))))

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
      (should (string-suffix-p "/chimes/item.ogg" (car played)))
      (should
       (string-prefix-p
        "emacsvox-chimes-item-" (cadr played))))))

(ert-deftest emacsvox-aural-transport-rich-icon-plan-uses-server-queue ()
  "A spoken replacement joins the ordered server queue instead of racing it."
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
    (let ((tts-speaker-process 'speaker)
          (emacsvox-use-icons t)
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
        '((text "item") dispatch))))))

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
        "/chimes/button.ogg"
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

(provide 'emacsvox-aural-transport-tests)
;;; emacsvox-aural-transport-tests.el ends here
