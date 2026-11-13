;;; profile-delivery.el --- Muted integration allocation profiles -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run from the repository root in a fresh -Q --batch Emacs.  Set
;; EMACSVOX_PROFILE_DEPS to the matching pinned test dependency directory.
;; EMACSVOX_DELIVERY_LOAD selects source (default) or compiled implementation.
;; EMACSVOX_PROFILE_STAGES=1 enables inclusive function instrumentation;
;; keep it off for latency comparisons.  No audio or external agent is started.
;; EMACSVOX_PROFILE_ACCOUNTING=string restores the former accounting expression
;; in this diagnostic process only, for comparisons with the same loaded code.
;; Use compare for alternating paired blocks (without stage instrumentation).

;;; Code:
(require 'cl-lib)
(require 'jka-compr)
(defconst delivery-profile--root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defconst delivery-profile--mode (or (getenv "EMACSVOX_DELIVERY_LOAD") "source"))
(defconst delivery-profile--deps (getenv "EMACSVOX_PROFILE_DEPS"))
(unless (and delivery-profile--deps
             (member delivery-profile--mode '("source" "compiled")))
  (error "Select a load mode and matching EMACSVOX_PROFILE_DEPS"))
(dolist (package '(compat acp shell-maker agent-shell eat cond-let transient
                         llama with-editor magit markdown-mode))
  (add-to-list 'load-path (expand-file-name (symbol-name package) delivery-profile--deps)))
(add-to-list 'load-path (expand-file-name "lisp" delivery-profile--root))
(add-to-list 'load-path (expand-file-name "test" delivery-profile--root))
(setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" delivery-profile--root))
(setq ring-bell-function #'ignore)
(fset 'ding #'ignore)
(let ((load-suffixes (if (equal delivery-profile--mode "source") '(".el") load-suffixes))
      (load-prefer-newer nil))
  (load "emacsvox-preamble.el" nil t)
  (require 'omnivox-choice-consumer-tests)
  (require 'magit)
  (require 'agent-shell)
  (require 'org)
  (require 'emacsvox-magit)
  (require 'emacsvox-agent-shell)
  (require 'emacsvox-org))

(defun delivery-profile--string-bytes (value)
  "Measure VALUE using the original allocating expression for comparison."
  (string-bytes (prin1-to-string value)))
(defconst delivery-profile--accounting
  (or (getenv "EMACSVOX_PROFILE_ACCOUNTING") "buffer"))
(unless (member delivery-profile--accounting '("buffer" "string" "compare"))
  (error "Unknown accounting comparison"))
(when (and (equal delivery-profile--accounting "compare")
           (getenv "EMACSVOX_PROFILE_STAGES"))
  (error "Keep paired timing separate from stage instrumentation"))
(defconst delivery-profile--buffer-printer (symbol-function 'tts--dispatch-data-bytes))
(defconst delivery-profile--string-printer
  (if (equal delivery-profile--mode "compiled")
      (byte-compile #'delivery-profile--string-bytes)
    (symbol-function 'delivery-profile--string-bytes)))
(when (equal (getenv "EMACSVOX_PROFILE_ACCOUNTING") "string")
  (unless (fboundp 'tts--dispatch-data-bytes) (error "Missing accounting helper"))
  (fset 'tts--dispatch-data-bytes delivery-profile--string-printer))

(defconst delivery-profile--functions
  '(emacsvox-aural-submit
    emacsvox-aural-prepare-text
    emacsvox-aural--resolve-inputs-for-anchors
    emacsvox-aural-compile-voice-style
    emacsvox-aural-record-presentation
    emacsvox-aural-queue-concrete-runs
    emacsvox-aural--build-structured-timeline
    emacsvox-aural--bind-timeline-candidate
    emacsvox-aural--frame-structured-timeline
    tts--dispatch-copy-data
    prin1-to-string
    tts--dispatch-data-bytes))
(defvar delivery-profile--active nil)
(defvar delivery-profile--stats nil)

(defun delivery-profile--measure (name function &rest args)
  "Measure inclusive time and allocation counts for NAME calling FUNCTION ARGS."
  (if (not delivery-profile--active) (apply function args)
    (let ((counts (memory-use-counts)) (start (current-time)))
      (prog1 (apply function args)
        (let* ((elapsed (float-time (time-since start)))
               (allocated (cl-mapcar #'- (memory-use-counts) counts))
               (prior (gethash name delivery-profile--stats)))
          (puthash name (list (1+ (or (car prior) 0))
                             (+ elapsed (or (cadr prior) 0))
                             (if prior (cl-mapcar #'+ allocated (caddr prior)) allocated))
                   delivery-profile--stats))))))

(defun delivery-profile--fixtures ()
  "Return isolated buffers and real integration producers; rendering is setup."
  (let ((magit (generate-new-buffer " *delivery-profile-magit*"))
        (org (generate-new-buffer " *delivery-profile-org*"))
        (agent (generate-new-buffer " *delivery-profile-agent*")))
    (with-current-buffer magit
      (magit-section-mode)
      (emacsvox-magit-enable-aural-context)
      (let ((inhibit-read-only t))
        (magit-insert-section (root)
          (magit-insert-section (recent)
            (magit-insert-heading "Recent commits")
            (magit-insert-section (commit "123456789")
              (insert (propertize "123456789" 'font-lock-face 'magit-hash)
                      " Preserve cancellation and independent notification speech\n")
              (magit-insert-heading)))))
      (goto-char (point-min))
      (forward-line 1))
    (with-current-buffer org
      (org-mode)
      (insert "* TODO Measure repeated presentation preparation :speech:performance:\n"
              "Keep text, emphasis, completion and notification ownership intact.\n")
      (font-lock-ensure)
      (goto-char (point-min)))
    (with-current-buffer agent
      (insert "## Investigation result\n\n"
              "Preserve **cancellation** and *independent notifications*.\n\n"
              "| Stage | Status |\n|---|---|\n| Preparation | measured |\n| Delivery | bounded |\n\n"
              "```elisp\n"
              (with-temp-buffer
                (insert-file-contents
                 (expand-file-name "test/fixtures/delivery-code.el.txt" delivery-profile--root))
                (buffer-string))
              "\n```\n")
      (agent-shell--render-markdown :render-images nil :external-renderers nil :complete t)
      (goto-char (point-min)))
    (list (list 'magit-commit magit
                (lambda () (emacsvox-magit-present-line nil 'navigation)))
          (list 'org-heading org
                (lambda () (emacsvox-org-speak-line-semantically 'navigation 'focus-entered)))
          (list 'agent-shell-response agent
                (lambda ()
                  (emacsvox-agent-shell--submit-text-feedback
                   (emacsvox-agent-shell--remove-visual-chrome-for-speech (buffer-string))
                   '(:role agent-response :events (focus-entered)) 'navigation nil 'ordered))))))

(defun delivery-profile--retire (lanes)
  "Simulate terminal replies and release owners on LANES."
  (dolist (lane lanes)
    (let (ids)
      (maphash (lambda (id ticket)
                 (when (eq (tts--marker-dispatch-process ticket) lane) (push id ids)))
               tts--marker-dispatches)
      (dolist (id ids)
        (tts--speaker-process-filter lane (format "__EMACSVOX_TRACKED__ %d completed\n" id)))
      (tts--dispatch-drain lane))))

(defun delivery-profile--run (fixture)
  "Measure FIXTURE with warmed caches, bounded history and no per-read collection."
  (omnivox-choice-consumer-test--with-speech
   (with-current-buffer (cadr fixture)
     (let* ((gc-cons-threshold (string-to-number (or (getenv "EMACSVOX_DELIVERY_GC_BYTES") "800000")))
            (gc-cons-percentage 0.1)
            (iterations (string-to-number (or (getenv "EMACSVOX_PROFILE_ITERATIONS") "30")))
            (delivery-profile--stats (make-hash-table :test #'eq))
            (producer (caddr fixture)) samples digest spans wire-bytes)
       (cl-labels ((submit () (setq writes nil) (funcall producer)
                     (unless writes (error "Missing output for %s" (car fixture))))
                   (check ()
                     (let (documents)
                       (dolist (write (reverse writes))
                         (when (string-match-p "emacsvox_timeline {" (cdr write))
                           (let ((document (omnivox-choice-consumer-test--timeline write)))
                             (setf (plist-get document :generation) 1
                                   (plist-get document :dispatch_id) 1)
                             (push document documents))))
                       (unless documents (error "No structured document for %s: %S" (car fixture) writes))
                       (setq spans (apply #'+ (mapcar (lambda (doc) (length (plist-get doc :spans))) documents))
                             wire-bytes (apply #'+ (mapcar (lambda (write) (string-bytes (cdr write))) writes)))
                       (let ((next (secure-hash 'sha256 (prin1-to-string documents))))
                         (when (and digest (not (equal digest next))) (error "Unstable document"))
                         (setq digest next)))))
         (dotimes (_ 5) (submit) (check) (delivery-profile--retire (list speaker notification)))
         (garbage-collect)
         (let ((counts (memory-use-counts)) (collections gcs-done) (gc-time gc-elapsed))
           (dotimes (_ iterations)
             (let ((start (current-time))
                   (delivery-profile--active (getenv "EMACSVOX_PROFILE_STAGES")))
               (submit)
               (push (* 1000 (float-time (time-since start))) samples))
             (delivery-profile--retire (list speaker notification)))
           (let ((allocated (cl-mapcar #'- (memory-use-counts) counts)))
             (check)
             (unless (zerop (hash-table-count tts--marker-dispatches)) (error "Leaked owner"))
             (setq samples (sort samples #'<))
             (list :case (car fixture) :iterations iterations :spans spans
                   :input-sha256 (secure-hash 'sha256 (buffer-string))
                   :input-bytes (string-bytes (buffer-string))
                   :document-sha256 digest :wire-bytes wire-bytes :retained-owners 0
                   :median-ms (nth (1- (ceiling (* 0.5 iterations))) samples)
                   :p95-ms (nth (1- (ceiling (* 0.95 iterations))) samples)
                   :gc-count (- gcs-done collections) :gc-seconds (- gc-elapsed gc-time)
                   :allocation-counts allocated :samples-ms samples
                   :inclusive-stages
                   (let (entries)
                     (maphash (lambda (name value) (push (cons name value) entries)) delivery-profile--stats)
                     (sort entries (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b))))))))))))))

(dolist (function '(emacsvox-aural-submit tts--dispatch-copy-data
                   emacsvox-magit-present-line emacsvox-org-speak-line-semantically
                   emacsvox-agent-shell--submit-text-feedback))
  (let ((path (symbol-file function 'defun)))
    (unless (and (file-in-directory-p path delivery-profile--root)
                 (string-suffix-p (if (equal delivery-profile--mode "compiled") ".elc" ".el") path))
      (error "Wrong implementation for %s: %s" function path))
    (princ (format "Loaded: %S\n" (list function path)))))
(dolist (function '(magit-section-mode agent-shell--render-markdown org-mode))
  (princ (format "Dependency: %S\n" (list function (symbol-file function 'defun)))))
(princ (format "Environment: %S\n"
               (list :emacs emacs-version :mode delivery-profile--mode
                     :deps delivery-profile--deps
                     :manifest-sha256 (with-temp-buffer
                                        (insert-file-contents-literally (expand-file-name "manifest.json" delivery-profile--deps))
                                        (secure-hash 'sha256 (current-buffer)))
                     :gc-threshold (or (getenv "EMACSVOX_DELIVERY_GC_BYTES") "800000")
                     :gc-percentage 0.1 :warmup 5 :history-limit emacsvox-aural-presentation-history-limit
                     :accounting delivery-profile--accounting
                     :instrumented (and (getenv "EMACSVOX_PROFILE_STAGES") t))))
(let ((fixtures (omnivox-choice-consumer-test--with-speech
                 (delivery-profile--fixtures))) advices)
  (unwind-protect
      (progn
        (when (getenv "EMACSVOX_PROFILE_STAGES")
          (dolist (name (seq-filter #'fboundp delivery-profile--functions))
            (let ((advice (apply-partially #'delivery-profile--measure name)))
              (advice-add name :around advice)
              (push (cons name advice) advices))))
        (dotimes (round (if (getenv "EMACSVOX_PROFILE_STAGES") 1 3))
          (dolist (fixture (if (cl-evenp round) fixtures (reverse fixtures)))
            (if (not (equal delivery-profile--accounting "compare"))
                (princ (format "Profile: %S\n" (append (list :round round) (delivery-profile--run fixture))))
              (let (digests)
                (dolist (method (if (cl-evenp round) '(buffer string) '(string buffer)))
                  (let ((result
                         (cl-letf (((symbol-function 'tts--dispatch-data-bytes)
                                    (if (eq method 'buffer) delivery-profile--buffer-printer
                                      delivery-profile--string-printer)))
                           (delivery-profile--run fixture))))
                    (push (plist-get result :document-sha256) digests)
                    (princ (format "Profile: %S\n" (append (list :round round :accounting method) result)))))
                (unless (equal (car digests) (cadr digests)) (error "Accounting changed document")))))))
    (dolist (advice advices) (advice-remove (car advice) (cdr advice)))
    (dolist (fixture fixtures) (kill-buffer (cadr fixture)))))

;;; profile-delivery.el ends here
