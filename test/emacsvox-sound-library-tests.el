;;; emacsvox-sound-library-tests.el --- Recording assignment tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Verify separation, durable assignments, conflict safety and browser return.
;;; Code:
(require 'emacsvox-aural-sound-packs-tests)
(require 'emacsvox-sound-library)

(defmacro emacsvox-test--with-library (&rest body)
  "Run BODY with one candidate and isolated writable packs."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-sound-workbench
     (let* ((emacsvox-sound-library-directory (make-temp-file "recording-library-" t))
            (emacsvox-sound-library-preview-timing 'alongside)
            (emacsvox-sound-library--cache (make-hash-table :test #'equal))
            (candidate (expand-file-name "soft-click.ogg" emacsvox-sound-library-directory)))
       (unwind-protect
           (cl-letf (((symbol-function 'emacsvox-sound-library--duration) (lambda (_) 0.25))
                     ((symbol-function 'emacsvox-aural-ui-speak)
                      (lambda (text)
                        (when emacsvox-aural-ui-speech-function
                          (funcall emacsvox-aural-ui-speech-function text)))))
             (write-region "candidate audio bytes" nil candidate nil 'silent)
             ,@body)
         (dolist (buffer (buffer-list))
           (when (with-current-buffer buffer (derived-mode-p 'emacsvox-sound-library-mode))
             (kill-buffer buffer)))
         (delete-directory emacsvox-sound-library-directory t)))))

(ert-deftest emacsvox-sound-library-missing-duration-tool-is-looked-up-once ()
  "Cold files share a negative lookup; warm metadata does not search PATH."
  (let ((emacsvox-sound-library-directory (make-temp-file "library-tool-" t))
        (emacsvox-sound-library--cache (make-hash-table :test #'equal))
        (lookups 0))
    (unwind-protect
        (progn
          (dotimes (i 10)
            (write-region (format "recording %d" i) nil
                          (expand-file-name (format "%d.wav" i) emacsvox-sound-library-directory)
                          nil 'silent))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (program &optional _remote)
                       (should (equal program "ffprobe"))
                       (cl-incf lookups) nil))
                    ((symbol-function 'make-process)
                     (lambda (&rest _) (ert-fail "Missing tool must not be run"))))
            (should (= (length (emacsvox-sound-library--scan)) 10))
            (should (= lookups 1))
            (emacsvox-sound-library--scan)
            (should (= lookups 1))
            (clrhash emacsvox-sound-library--cache)
            (emacsvox-sound-library--scan)
            (should (= lookups 2))))
      (delete-directory emacsvox-sound-library-directory t))))

(ert-deftest emacsvox-sound-library-duration-tool-selection-is-scoped ()
  "Scans use the resolved path and standalone calls see a changed PATH."
  (let ((emacsvox-sound-library-directory (make-temp-file "library-tool-" t))
        (emacsvox-sound-library--cache (make-hash-table :test #'equal))
        (program "/first/ffprobe") calls)
    (unwind-protect
        (let ((file (expand-file-name "one.wav" emacsvox-sound-library-directory)))
          (write-region "one recording" nil file nil 'silent)
          (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) program))
                    ((symbol-function 'emacsvox-sound-library--probe-duration)
                     (lambda (executable _file)
                       (push executable calls) 0.25)))
            (should (= (plist-get (car (emacsvox-sound-library--scan)) :duration) 0.25))
            (setq program "/second/ffprobe")
            (should (= (emacsvox-sound-library--duration file) 0.25))
            (should (equal (nreverse calls) '("/first/ffprobe" "/second/ffprobe")))))
      (delete-directory emacsvox-sound-library-directory t))))

(defmacro emacsvox-test--with-duration-child (expression &rest body)
  "Run BODY with real probe processes evaluating EXPRESSION in child Emacs."
  (declare (indent 1) (debug t))
  `(let ((launch (symbol-function 'make-process))
         (emacs (expand-file-name invocation-name invocation-directory))
         (probe-count 0) probe-command probe-process probe-errors probe-output)
     (unwind-protect
         (cl-letf (((symbol-function 'make-process)
                    (lambda (&rest args)
                      (cl-incf probe-count)
                      (setq probe-command (plist-get args :command)
                            probe-errors (plist-get args :stderr)
                            probe-output (plist-get args :buffer)
                            probe-process
                            (apply launch
                                   (plist-put args :command
                                              (list emacs "-Q" "--batch" "--eval"
                                                    (prin1-to-string ,expression))))))))
           ,@body
           (should-not (process-live-p probe-process))
           (should-not (process-live-p probe-errors))
           (should-not (buffer-live-p probe-output)))
       (dolist (child (list probe-process probe-errors))
         (when (processp child) (delete-process child)))
       (when (buffer-live-p probe-output) (kill-buffer probe-output)))))

(ert-deftest emacsvox-sound-library-duration-child-validates-output-and-cleans-up ()
  "Valid duration survives stderr; invalid and unsuccessful output is unknown."
  (dolist (case '(((progn (princ "1.25\n") (message "Diagnostic")) 1.25)
                  ((princ "N/A\n") nil)
                  ((princ "not a duration\n") nil)
                  ((progn (princ "1.25\n") (kill-emacs 1)) nil)))
    (emacsvox-test--with-duration-child (car case)
      (should (equal (emacsvox-sound-library--probe-duration
                      "/tool path/ffprobe" "/recording path/sample.wav") (cadr case)))
      (should (equal (car probe-command) "/tool path/ffprobe"))
      (should (equal (last probe-command 2) '("-i" "/recording path/sample.wav"))))))

(ert-deftest emacsvox-sound-library-duration-timeout-stops-probing-that-scan ()
  "One hung probe cannot repeat its full timeout for every recording."
  (let ((emacsvox-sound-library-directory (make-temp-file "library-stall-" t))
        (emacsvox-sound-library--cache (make-hash-table :test #'equal))
        (emacsvox-sound-library--duration-timeout 0.1)
        ticked)
    (unwind-protect
        (progn
          (dotimes (i 5)
            (write-region (format "recording %d" i) nil
                          (expand-file-name (format "%d.wav" i) emacsvox-sound-library-directory)
                          nil 'silent))
          (emacsvox-test--with-duration-child '(sleep-for 60)
            (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/tool/ffprobe")))
              (let ((timer (run-at-time 0.01 nil (lambda () (setq ticked t)))))
                (unwind-protect
                    (let ((recordings (emacsvox-sound-library--scan)))
                      (should (= (length recordings) 5))
                      (should (cl-every (lambda (r) (null (plist-get r :duration))) recordings)))
                  (cancel-timer timer)))
              (should ticked)
              (should (= probe-count 1))
              ;; The disabled tool belongs to this scan only.
              (clrhash emacsvox-sound-library--cache)
              (should (= (length (emacsvox-sound-library--scan)) 5))
              (should (= probe-count 2)))))
      (delete-directory emacsvox-sound-library-directory t))))

(ert-deftest emacsvox-sound-library-duration-quit-and-output-limit-clean-up ()
  "Quit propagates; excessive output degrades optional metadata without leaks."
  (emacsvox-test--with-duration-child '(sleep-for 60)
    (cl-letf (((symbol-function 'accept-process-output) (lambda (&rest _) (signal 'quit nil))))
      (should (condition-case nil
                  (progn (emacsvox-sound-library--probe-duration "/tool/ffprobe" "file") nil)
                (quit t)))))
  (let ((emacsvox-sound-library--duration-tool (list "/tool/ffprobe")))
    (emacsvox-test--with-duration-child '(princ (make-string 8192 ?x))
      (should-not (emacsvox-sound-library--probe-duration "/tool/ffprobe" "file"))
      (should-not (car emacsvox-sound-library--duration-tool)))))

(ert-deftest emacsvox-sound-library-preview-and-selection-are-private ()
  (emacsvox-test--with-library
    (let ((before (emacsvox-aural-resolve-cue 'button 'overlay))
          (manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay)))
          seen)
      (save-window-excursion
        (emacsvox-sound-library 'overlay 'button)
        (cl-letf (((symbol-function 'emacsvox-aural-preview-play-cue)
                   (lambda (file &rest _) (setq seen file))))
          (call-interactively (key-binding (kbd "SPC")))
          (should (equal seen candidate))
          (should-not (plist-get emacsvox-sound-library--target :drafts)))
        (emacsvox-sound-library-select)
        (should (plist-get emacsvox-sound-library--target :drafts))
        (should (equal before (emacsvox-aural-resolve-cue 'button 'overlay)))
        (should (equal manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
        (should-not (emacsvox-aural-cue 'soft-click))
        (emacsvox-aural-quit)))))

(ert-deftest emacsvox-sound-library-cache-releases-removed-files-and-former-roots ()
  "The metadata cache follows the current library without deleting recordings."
  (emacsvox-test--with-library
    (emacsvox-sound-library--scan)
    (should (= (hash-table-count emacsvox-sound-library--cache) 1))
    (delete-file candidate)
    (should-not (emacsvox-sound-library--scan))
    (should (zerop (hash-table-count emacsvox-sound-library--cache)))
    (write-region "restored recording" nil candidate nil 'silent)
    (emacsvox-sound-library--scan)
    (let ((other-root (make-temp-file "another-library-" t)))
      (unwind-protect
          (let ((emacsvox-sound-library-directory other-root))
            (write-region "another recording" nil (expand-file-name "other.wav" other-root) nil 'silent)
            (emacsvox-sound-library--scan)
            (should (= (hash-table-count emacsvox-sound-library--cache) 1))
            (should-not (gethash candidate emacsvox-sound-library--cache))
            (should (file-exists-p candidate)))
        (delete-directory other-root t)))))

(ert-deftest emacsvox-sound-library-cache-keeps-the-last-complete-scan-on-error ()
  "An incomplete metadata scan does not publish or retain a partial new cache."
  (emacsvox-test--with-library
    (emacsvox-sound-library--scan)
    (let ((previous emacsvox-sound-library--cache))
      (write-region "new recording" nil (expand-file-name "new.wav" emacsvox-sound-library-directory) nil 'silent)
      (cl-letf (((symbol-function 'emacsvox-aural--recording-digest)
                 (lambda (&rest _) (error "Cannot read recording"))))
        (should-error (emacsvox-sound-library--scan)))
      (should (eq emacsvox-sound-library--cache previous))
      (should (= (hash-table-count emacsvox-sound-library--cache) 1)))))

(ert-deftest emacsvox-sound-library-arrows-preview-only-successful-row-moves ()
  "Row navigation previews candidates without cancelling labels or assigning."
  (emacsvox-test--with-library
   (write-region "another recording" nil
                 (expand-file-name "another.ogg" emacsvox-sound-library-directory)
                 nil 'silent)
   (save-window-excursion
     (emacsvox-sound-library 'overlay 'button)
     (let* ((first (emacsvox-sound-library--recording))
            (manifest (emacsvox-sound-library--manifest-id
                       (emacsvox-aural-resource-pack 'overlay)))
            (press (lambda (key)
                     (if (display-graphic-p)
                         (execute-kbd-macro (kbd key))
                       (call-interactively (key-binding (kbd key))))))
            events)
       (let ((emacsvox-aural-ui-speech-function
              (lambda (text) (push (list 'speech text) events))))
         (cl-letf (((symbol-function 'emacsvox-aural-preview-structured-style-supported-p)
                    (lambda () nil))
                   ((symbol-function 'emacsvox-sounds-play-concrete-cue)
                    (lambda (file &rest _) (push (list 'audio file) events)))
                   ((symbol-function 'tts-stop)
                    (lambda (&rest _) (push '(stop) events))))
           (funcall press "<down>")
           (should (equal (mapcar #'car (reverse events)) '(stop speech audio)))
           (should (equal (cadar events) candidate))
           ;; At a boundary or while reading columns, do not replay the row.
           (setq events nil)
           (funcall press "<down>")
           (funcall press "<right>")
           (should-not (assq 'audio events))
           ;; Row movement also previews while browsing a metadata column.
           (setq events nil)
           (funcall press "<up>")
           (should (= 1 (emacsvox-aural-ui-tabulated-column-index)))
           (should (equal (mapcar #'car (reverse events)) '(stop speech audio)))
           (should (equal (cadar events) (plist-get first :file)))
           (setq events nil)
           (funcall press "<up>")
           (should-not (assq 'audio events))
           (emacsvox-sound-library-search "no matching recording")
           (setq events nil)
           (funcall press "<down>")
           (funcall press "<up>")
           (should-not (assq 'audio events))))
       (should-not (plist-get emacsvox-sound-library--target :drafts))
       (should (equal manifest (emacsvox-sound-library--manifest-id
                                (emacsvox-aural-resource-pack 'overlay))))))))

(ert-deftest emacsvox-sound-library-timings-reach-one-cancellable-timeline ()
  "Each row sends a stop then one timeline containing speech and its recording."
  (require 'omnivox-voices)
  (emacsvox-test--with-library
   (write-region "another recording" nil
                 (expand-file-name "another.ogg" emacsvox-sound-library-directory)
                 nil 'silent)
   (save-window-excursion
     (emacsvox-sound-library)
     (let* ((process (make-pipe-process :name "library-preview-test" :noquery t))
            (tts-speaker-process process)
            (tts-program "omnivox")
            (emacsvox-aural-submission-delivery-policy nil)
            writes)
       (unwind-protect
           (progn
             (process-put process emacsvox-aural--structured-timeline-process-property 3)
             (process-put process tts--tracked-playback-completion-property t)
             (cl-letf (((symbol-function 'process-send-string)
                        (lambda (_ command) (push command writes)))
                       ((symbol-function 'tts-voice-reset-code) (lambda () "")))
               (dolist (timing '(before alongside after))
                 (setq emacsvox-sound-library-preview-timing timing writes nil)
                 (emacsvox-sound-library-next)
                 (emacsvox-sound-library-previous)
                 (let ((wire (apply #'concat (reverse writes))) (start 0) timelines)
                   (while (string-match "emacsvox_timeline {\\([^}]+\\)}" wire start)
                     (setq start (match-end 0))
                     (push (json-parse-string
                            (decode-coding-string (base64-decode-string (match-string 1 wire)) 'utf-8)
                            :object-type 'plist :array-type 'list)
                           timelines))
                   (should (= 2 (length timelines)))
                   ;; A second movement interrupts pending playback before replacement.
                   (should (equal (delq nil (mapcar
                                             (lambda (line)
                                               (cond ((equal line "s") 'stop)
                                                     ((string-prefix-p "emacsvox_timeline " line) 'timeline)))
                                             (split-string wire "\n" t)))
                                  '(stop timeline stop timeline)))
                   (dolist (timeline timelines)
                     (let* ((span (car (plist-get timeline :spans)))
                            (audio (seq-filter (lambda (action) (equal (plist-get action :type) "audio"))
                                               (plist-get timeline :actions)))
                            (action (car audio)))
                       (should (= 1 (length audio)))
                       (should (string-match-p "another\\|soft-click" (plist-get span :text)))
                       (should (file-in-directory-p (plist-get action :path)
                                                    emacsvox-sound-library-directory))
                       (should (equal (plist-get action :mode)
                                      (if (eq timing 'before) "insert" "overlay")))
                       (should (equal (plist-get (plist-get action :position) :affinity)
                                      (if (eq timing 'after) "after" "before")))))))))
         (delete-process process))))))

(ert-deftest emacsvox-sound-library-off-retains-speech-and-explicit-replay ()
  "Off cancels old playback and speaks; Space still plays the selected recording."
  (emacsvox-test--with-library
   (write-region "another recording" nil
                 (expand-file-name "another.ogg" emacsvox-sound-library-directory)
                 nil 'silent)
   (save-window-excursion
     (emacsvox-sound-library)
     (let* ((emacsvox-sound-library-preview-timing 'off)
            events
            (emacsvox-aural-ui-speech-function
             (lambda (text) (push (list 'speech text) events))))
       (cl-letf (((symbol-function 'tts-stop) (lambda () (push '(stop) events)))
                 ((symbol-function 'emacsvox-sounds-play-concrete-cue)
                  (lambda (file &rest _) (push (list 'audio file) events))))
         (emacsvox-sound-library-next)
         (should (equal (mapcar #'car (reverse events)) '(stop speech)))
         (should (string-match-p "soft-click" (cadar events)))
         (call-interactively (key-binding (kbd "SPC")))
         (should (equal (mapcar #'car (reverse events)) '(stop speech stop audio)))
         (should (equal (cadar events) candidate)))))))

(ert-deftest emacsvox-sound-library-ordered-preview-explains-unsupported-backend ()
  "An unsupported backend still identifies the row and never fakes sequencing."
  (emacsvox-test--with-library
   (write-region "another recording" nil
                 (expand-file-name "another.ogg" emacsvox-sound-library-directory)
                 nil 'silent)
   (save-window-excursion
     (emacsvox-sound-library)
     (let ((emacsvox-sound-library-preview-timing 'before) spoken)
       (let ((emacsvox-aural-ui-speech-function (lambda (text) (setq spoken text))))
         (cl-letf (((symbol-function 'emacsvox-aural-preview-structured-style-supported-p) (lambda () nil))
                   ((symbol-function 'tts-stop) #'ignore)
                   ((symbol-function 'emacsvox-sounds-play-concrete-cue)
                    (lambda (&rest _) (ert-fail "Unsupported ordered preview played audio"))))
           (should-error (emacsvox-sound-library-next) :type 'user-error)
           (should (string-match-p "soft-click" spoken))))))))

(ert-deftest emacsvox-sound-library-save-survives-rename-and-pack-relocation ()
  (emacsvox-test--with-library
    (let* ((target (emacsvox-sound-library--capture 'overlay 'button))
           (recording (car (emacsvox-sound-library--scan)))
           (id (plist-get recording :id))
           (emacsvox-sounds-current-pack 'base))
      (emacsvox-sound-library--put-draft target recording)
      (emacsvox-sound-library--commit target)
      (should (eq emacsvox-sounds-current-pack 'base))
      (should (equal (emacsvox-sound-library--uses id) '("overlay / button")))
      (should (equal "assigned" (plist-get (emacsvox-aural-sound-packs--exact-asset 'button 'overlay) :availability)))
      (with-temp-buffer
        (should
         (zerop
          (call-process
           (expand-file-name invocation-name invocation-directory) nil t nil
           "-Q" "--batch" "-L" emacsvox-lisp-directory "-l" "emacsvox-preamble"
           "--eval"
           (prin1-to-string
            `(let ((emacsvox-aural-resource-pack-discovery-roots (list ,root)))
               (emacsvox-aural-register-resource-pack 'base :summary "Base" :directory ,base-directory)
               (emacsvox-aural-refresh-discovered-resource-packs)
               (princ (emacsvox-aural--recording-digest
                       (emacsvox-aural-resolve-cue 'button 'overlay))))))))
        (should (string-match-p (regexp-quote id) (buffer-string))))
      (rename-file candidate (expand-file-name "renamed.ogg" emacsvox-sound-library-directory))
      (should (equal id (plist-get (car (emacsvox-sound-library--scan)) :id)))
      (let* ((relocated (expand-file-name "relocated" root))
             (emacsvox-aural-resource-pack-discovery-roots (list root)))
        (copy-directory overlay-directory relocated nil t t)
        (emacsvox-aural-refresh-discovered-resource-packs)
        (let ((resolved (emacsvox-aural-resolve-cue 'button 'relocated)))
          (should (file-in-directory-p resolved relocated))
          (should (equal id (emacsvox-aural--recording-digest resolved))))))))

(ert-deftest emacsvox-sound-library-reset-retains-local-original-and-reveals-parent ()
  (emacsvox-test--with-library
    (let ((target (emacsvox-sound-library--capture 'overlay 'button)))
      (emacsvox-sound-library--put-draft target (car (emacsvox-sound-library--scan)))
      (emacsvox-sound-library--commit target)
      (emacsvox-sound-library--put-draft target 'inherit)
      (emacsvox-sound-library--commit target)
      (should (file-exists-p (expand-file-name "button.ogg" overlay-directory)))
      (should (equal (emacsvox-aural-resolve-cue 'button 'overlay)
                     (expand-file-name "button.ogg" base-directory)))
      (should (equal "inherited" (plist-get (emacsvox-aural-sound-packs--exact-asset 'button 'overlay) :availability))))))

(ert-deftest emacsvox-sound-library-conflicts-and-failed-publication-retain-assignment ()
  (emacsvox-test--with-library
    (let* ((target (emacsvox-sound-library--capture 'overlay 'button))
           (before (emacsvox-aural-resolve-cue 'button 'overlay))
           (manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
      (emacsvox-sound-library--put-draft target (car (emacsvox-sound-library--scan)))
      (cl-letf (((symbol-function 'emacsvox-aural-refresh-discovered-resource-packs)
                 (lambda () (error "Injected publication failure"))))
        (should-error (emacsvox-sound-library--commit target)))
      (should (equal before (emacsvox-aural-resolve-cue 'button 'overlay)))
      (should (equal manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
      (write-region "changed" nil candidate nil 'silent)
      (should-error (emacsvox-sound-library--commit target) :type 'user-error)
      (write-region "; external edit\n" nil (expand-file-name emacsvox-aural-resource-pack-manifest overlay-directory) t 'silent)
      (should-error (emacsvox-sound-library--commit target) :type 'user-error))))

(ert-deftest emacsvox-sound-library-explicit-assignment-overrides-module-sound ()
  "Assignment and Reset use the same precedence in playback and provenance."
  (let ((emacsvox-aural-cue-registry (copy-hash-table emacsvox-aural-cue-registry)))
    (emacsvox-test--with-library
      (let* ((module (expand-file-name "module-default" root))
             (themed (expand-file-name "library-test" overlay-directory)))
        (make-directory module)
        (make-directory themed)
        (emacsvox-aural-register-cue 'library-test-cue :owner 'library-test
                                     :summary "Library test cue" :fallback 'button)
        (emacsvox-test--sound-workbench-file module 'library-test-cue)
        (emacsvox-test--sound-workbench-file themed 'library-test-cue)
        (emacsvox-aural-register-resource-overlay 'library-test-overlay
                                                  :owner 'library-test :summary "Test overlay" :directory module)
        (let ((target (emacsvox-sound-library--capture 'overlay 'library-test-cue)))
          (emacsvox-sound-library--put-draft target (car (emacsvox-sound-library--scan)))
          (emacsvox-sound-library--commit target)
          (should (equal (emacsvox-aural--recording-digest candidate)
                         (emacsvox-aural--recording-digest
                          (emacsvox-aural-resolve-cue 'library-test-cue 'overlay))))
          (should (equal "assigned" (plist-get (emacsvox-aural-sound-packs--exact-asset 'library-test-cue 'overlay) :availability)))
          (emacsvox-sound-library--put-draft target 'inherit)
          (emacsvox-sound-library--commit target)
          (should (equal (expand-file-name "library-test-cue.ogg" module)
                         (emacsvox-aural-resolve-cue 'library-test-cue 'overlay)))
          (should (equal "module default"
                         (emacsvox-aural-sound-cue-detail-availability
                          (emacsvox-aural-sound-packs--cue-detail 'library-test-cue 'overlay)))))))))

(ert-deftest emacsvox-sound-library-rejects-unsafe-manifests ()
  (emacsvox-test--with-library
    (let* ((r (car (emacsvox-sound-library--scan)))
           (id (plist-get r :id)))
      (dolist (file (list candidate "../soft-click.ogg" "recordings/assigned/wrong.ogg"))
        (should-error (emacsvox-aural--validate-pack-assignments
                       `((button :recording ,id :file ,file :name "Candidate")) overlay-directory)))
      (let ((target (emacsvox-sound-library--capture 'overlay 'button)))
        (emacsvox-sound-library--put-draft target r)
        (emacsvox-sound-library--commit target)
        (write-region "tampered" nil (emacsvox-aural-resolve-cue 'button 'overlay) nil 'silent)
        (should-error (emacsvox-aural--read-resource-pack-manifest overlay-directory))))))

(ert-deftest emacsvox-sound-library-import-and-filter-do-not-register-cues ()
  (emacsvox-test--with-library
    (let ((copy (emacsvox-sound-library-import candidate "Clicks")))
      (should (file-exists-p candidate))
      (should (file-exists-p copy))
      (should (= 1 (length (emacsvox-sound-library--scan))))
      (should-error (emacsvox-sound-library-import candidate "../escape") :type 'user-error)
      (should-error (emacsvox-sound-library-import candidate ".hidden") :type 'user-error))
    (save-window-excursion
      (emacsvox-sound-library)
      (emacsvox-sound-library-search "NO MATCH")
      (should-not tabulated-list-entries)
      (emacsvox-sound-library-search "click")
      (should (= 1 (length tabulated-list-entries)))
      (should-not (emacsvox-aural-cue 'soft-click)))))

(ert-deftest emacsvox-sound-library-import-creates-a-new-library-root ()
  "The first import creates its library and collection without moving the source."
  (emacsvox-test--with-library
    (let ((emacsvox-sound-library-directory (expand-file-name "new-library" root)))
      (should-not (file-exists-p emacsvox-sound-library-directory))
      (let ((copy (emacsvox-sound-library-import candidate "Clicks")))
        (should (file-exists-p copy))
        (should (file-exists-p candidate))
        (should (equal (emacsvox-aural--recording-digest candidate)
                       (emacsvox-aural--recording-digest copy)))))))

(ert-deftest emacsvox-sound-library-delete-refuses-assigned-recording ()
  "Deletion must explain known assignments and leave the candidate intact."
  (emacsvox-test--with-library
    (save-window-excursion
      (emacsvox-sound-library 'overlay 'button)
      (emacsvox-sound-library-select)
      (emacsvox-sound-library-save)
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (&rest _) (ert-fail "Assigned audio must not reach deletion confirmation"))))
        (should-error (emacsvox-sound-library-delete) :type 'user-error))
      (should (file-exists-p candidate)))))

(ert-deftest emacsvox-sound-library-graphical-cue-return-keeps-row ()
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-library
    (save-window-excursion
      (emacsvox-aural-list-sound-pack-cues 'overlay)
      (emacsvox-aural-ui-goto-row 'button)
      (execute-kbd-macro (kbd "a RET"))
      (should (derived-mode-p 'emacsvox-sound-library-mode))
      (let ((library (current-buffer)))
        ;; Reopening preserves pending choices and the original return destination.
        (emacsvox-sound-library 'overlay 'button)
        (should (= 1 (length (plist-get emacsvox-sound-library--target :drafts))))
        (execute-kbd-macro (kbd "q"))
        (should (derived-mode-p 'emacsvox-aural-sound-pack-cues-mode))
        (should (eq (tabulated-list-get-id) 'button))
        (should-not (buffer-local-value 'emacsvox-sound-library--target library))))))

(ert-deftest emacsvox-sound-library-assignment-graphical-alphabetical-prompts ()
  "Assignment displays alphabetical pack and cue choices despite frontend sorting."
  (skip-unless (display-graphic-p))
  (skip-unless (require 'vertico nil t))
  (emacsvox-test--with-library
    (save-window-excursion
      (let ((was-enabled vertico-mode)
            (vertico-map (copy-keymap vertico-map))
            (vertico-sort-override-function nil)
            (vertico-sort-function
             (lambda (items)
               (sort (copy-sequence items)
                     (lambda (a b) (< (length a) (length b))))))
            seen)
        (unwind-protect
            (progn
              (vertico-mode 1)
              (define-key vertico-map (kbd "<f9>")
                (lambda ()
                  (interactive)
                  (vertico--exhibit)
                  (push (copy-sequence vertico--candidates) seen)
                  (let ((choice (if (string-prefix-p "Assign" (minibuffer-prompt))
                                    "overlay" "button")))
                    (delete-minibuffer-contents)
                    (insert choice)
                    (exit-minibuffer))))
              (emacsvox-sound-library)
              (execute-kbd-macro (kbd "a <f9> <f9>"))
              (should (= (length seen) 2))
              (dolist (choices seen)
                (should (equal choices (sort (copy-sequence choices) #'string-lessp))))
              (should (eq (plist-get emacsvox-sound-library--target :cue) 'button))
              (should (eq (plist-get emacsvox-sound-library--target :pack) 'overlay))
              (should-not (emacsvox-aural-resource-pack-assignments
                           (emacsvox-aural-resource-pack 'overlay))))
          (unless was-enabled (vertico-mode -1)))))))

(ert-deftest emacsvox-sound-library-selection-shows-pending ()
  "Selection immediately changes row status and speech without saving."
  (emacsvox-test--with-library
    (save-window-excursion
      (emacsvox-sound-library 'overlay 'button)
      (emacsvox-sound-library-select)
      (should (equal (aref (tabulated-list-get-entry) 3) "Pending: overlay / button"))
      (let (spoken)
        (cl-letf (((symbol-function 'emacsvox-aural-ui-speak)
                   (lambda (text &rest _) (setq spoken text))))
          (emacsvox-sound-library-speak-current))
        (should (string-match-p "Pending: overlay / button" spoken)))
      (should-error (emacsvox-sound-library-delete) :type 'user-error)
      (should (file-exists-p candidate)))))

(ert-deftest emacsvox-sound-library-multiple-assignments-share-buffer-and-save ()
  "Three recordings queue independently and publish in one manifest write."
  (emacsvox-test--with-library
    (write-region "second audio" nil (expand-file-name "second.ogg" emacsvox-sound-library-directory) nil 'silent)
    (write-region "third audio" nil (expand-file-name "third.ogg" emacsvox-sound-library-directory) nil 'silent)
    (save-window-excursion
      (emacsvox-sound-library)
      (let ((library (current-buffer))
            (manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay)))
            (cues '(button item close-object))
            (replies '("overlay" "button" "item" "close-object"))
            expected)
        (cl-letf (((symbol-function 'emacsvox-sound-library--read-choice)
                   (lambda (&rest _) (pop replies))))
          (dolist (recording emacsvox-sound-library--recordings)
            (let ((cue (pop cues)) (id (plist-get recording :id)))
              (push (cons cue id) expected)
              (emacsvox-aural-ui-goto-row id)
              (emacsvox-sound-library-assign)
              (should (eq library (current-buffer)))
              (should (equal (tabulated-list-get-id) id))
              (should (equal (aref (tabulated-list-get-entry) 3)
                             (format "Pending: overlay / %s" cue))))))
        (should-not replies)
        (emacsvox-sound-library-unassigned)
        (should (= 3 (length tabulated-list-entries)))
        (should (equal manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
        (should-not (emacsvox-aural-resource-pack-assignments (emacsvox-aural-resource-pack 'overlay)))
        (emacsvox-sound-library-unassigned)
        (let ((writer (symbol-function 'emacsvox-aural-sound-packs--write-manifest)) (writes 0))
          (cl-letf (((symbol-function 'emacsvox-aural-sound-packs--write-manifest)
                     (lambda (&rest args) (cl-incf writes) (apply writer args))))
            (emacsvox-sound-library-save))
          (should (= writes 1)))
        (should-not (plist-get emacsvox-sound-library--target :drafts))
        (should (equal (tabulated-list-get-id) (cdar expected)))
        (dolist (entry expected)
          (should (equal (cdr entry) (emacsvox-aural--recording-digest
                                      (emacsvox-aural-resolve-cue (car entry) 'overlay)))))
        (dolist (row tabulated-list-entries)
          (should (string-prefix-p "Saved: overlay / " (aref (cadr row) 3))))))))

(ert-deftest emacsvox-sound-library-batch-failure-and-replacement ()
  "A failed batch retains all drafts; replacing one cue preserves the others."
  (emacsvox-test--with-library
    (let ((second (expand-file-name "second.ogg" emacsvox-sound-library-directory)))
      (write-region "second audio" nil second nil 'silent)
      (save-window-excursion
        (emacsvox-sound-library 'overlay 'button)
        (let* ((records emacsvox-sound-library--recordings)
               (one (car records)) (two (cadr records))
               (manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
          (emacsvox-aural-ui-goto-row (plist-get one :id))
          (emacsvox-sound-library-select)
          (emacsvox-aural-ui-goto-row (plist-get two :id))
          (cl-letf (((symbol-function 'emacsvox-sound-library--read-choice) (lambda (&rest _) "item")))
            (emacsvox-sound-library-assign))
          (cl-letf (((symbol-function 'emacsvox-aural-refresh-discovered-resource-packs)
                     (lambda () (error "Injected batch publication failure"))))
            (should-error (emacsvox-sound-library-save)))
          (should (= 2 (length (plist-get emacsvox-sound-library--target :drafts))))
          (should (equal manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
          (should-not (emacsvox-aural-resource-pack-assignments (emacsvox-aural-resource-pack 'overlay)))
          ;; Force failure after another recording could already have been copied.
          (write-region "changed" nil (plist-get one :file) nil 'silent)
          (should-error (emacsvox-sound-library-save) :type 'user-error)
          (should (= 2 (length (plist-get emacsvox-sound-library--target :drafts))))
          (should (equal manifest (emacsvox-sound-library--manifest-id (emacsvox-aural-resource-pack 'overlay))))
          (should-not (emacsvox-aural-resource-pack-assignments (emacsvox-aural-resource-pack 'overlay)))
          (cl-letf (((symbol-function 'emacsvox-sound-library--read-choice) (lambda (&rest _) "button")))
            (emacsvox-sound-library-assign))
          (should-not (emacsvox-sound-library--pending-uses (plist-get one :id)))
          (should (equal (aref (tabulated-list-get-entry) 3)
                         "Pending: overlay / button, overlay / item"))
          (emacsvox-sound-library-reset)
          (should (equal (aref (tabulated-list-get-entry) 3) "Pending: overlay / item"))
          (emacsvox-sound-library-save)
          (should (equal (emacsvox-aural-resolve-cue 'button 'overlay)
                         (expand-file-name "button.ogg" base-directory)))
          (should (equal (plist-get two :id) (emacsvox-aural--recording-digest
                                             (emacsvox-aural-resolve-cue 'item 'overlay)))))))))

(ert-deftest emacsvox-sound-library-graphical-batch-cancel-and-return ()
  "Keyboard assignments stay in one buffer; q discards even with a menu return."
  (skip-unless (display-graphic-p))
  (emacsvox-test--with-library
    (save-window-excursion
      (emacsvox-sound-library)
      (let ((library (current-buffer))
            (replies '("overlay" "button" "item" "close-object")) returned)
        (cl-letf (((symbol-function 'emacsvox-sound-library--read-choice)
                   (lambda (&rest _) (pop replies))))
          (execute-kbd-macro (kbd "a a a")))
        (should (eq library (current-buffer)))
        (should (= 3 (length (plist-get emacsvox-sound-library--target :drafts))))
        (should (string-match-p "Pending: overlay / button, overlay / close-object, overlay / item"
                                (aref (tabulated-list-get-entry) 3)))
        (setq emacsvox-aural-ui--return-function (lambda () (setq returned t)))
        (execute-kbd-macro (kbd "q"))
        (should returned)
        (should-not (buffer-local-value 'emacsvox-sound-library--target library))
        (should-not (emacsvox-aural-resource-pack-assignments (emacsvox-aural-resource-pack 'overlay)))
        (emacsvox-sound-library)
        (should (equal (aref (tabulated-list-get-entry) 3) "Unassigned"))))))

(provide 'emacsvox-sound-library-tests)
;;; emacsvox-sound-library-tests.el ends here
