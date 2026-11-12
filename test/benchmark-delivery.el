;;; benchmark-delivery.el --- Repeated muted delivery measurements -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run in a fresh -Q --batch Emacs from the repository root.  Set
;; EMACSVOX_DELIVERY_LOAD=compiled to measure current byte-code.  This uses
;; real preparation and dispatch with isolated registered pipe fixtures.
;; Writes are captured, terminal replies are simulated, and no audio is sent.
;; The copy-bypass comparison exists only in this diagnostic process.

;;; Code:
(require 'cl-lib)
(require 'jka-compr)
(defconst delivery-benchmark--root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defconst delivery-benchmark--mode (or (getenv "EMACSVOX_DELIVERY_LOAD") "source"))
(unless (member delivery-benchmark--mode '("source" "compiled")) (error "Invalid load mode"))
(add-to-list 'load-path (expand-file-name "lisp" delivery-benchmark--root))
(add-to-list 'load-path (expand-file-name "test" delivery-benchmark--root))
(setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" delivery-benchmark--root))
(setq ring-bell-function #'ignore)
(fset 'ding #'ignore)
(let ((load-suffixes (if (equal delivery-benchmark--mode "source") '(".el") load-suffixes))
      (load-prefer-newer nil))
  (load "emacsvox-preamble.el" nil t)
  (require 'omnivox-choice-consumer-tests)
  (when (getenv "EMACSVOX_DELIVERY_RECORDING")
    (require 'emacsvox-aural-recording)))

(defun delivery-benchmark--code ()
  "Prepare a real fontified Lisp excerpt outside the measured delivery."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "test/fixtures/delivery-code.el.txt" delivery-benchmark--root))
    (emacs-lisp-mode)
    (font-lock-ensure)
    ;; Use the fixture's registered emphasis voice for fontified tokens.
    (let ((position (point-min)))
      (while (< position (point-max))
        (let ((end (next-single-property-change position 'face nil (point-max))))
          (when (get-text-property position 'face)
            (put-text-property position end 'personality 'voice-bolden))
          (setq position end))))
    (buffer-string)))

(defun delivery-benchmark--percentile (values fraction)
  "Return FRACTION's nearest rank from sorted VALUES."
  (nth (max 0 (1- (ceiling (* fraction (length values))))) values))

(defun delivery-benchmark--run (name content iterations copy-p)
  "Measure NAME's CONTENT for ITERATIONS with COPY-P ownership enabled.
The symbol `record' also captures each delivery; arming is outside timing."
  (omnivox-choice-consumer-test--with-speech
   (let ((copier (symbol-function 'emacsvox-aural--own-candidate-data))
         (builder (symbol-function 'emacsvox-aural--build-structured-timeline))
         (gc-cons-threshold (string-to-number (or (getenv "EMACSVOX_DELIVERY_GC_BYTES") "800000")))
         (gc-cons-percentage 0.1)
         built samples canonical copy-samples recording-bytes recording-complete
         (copy-collections 0))
     (cl-letf (((symbol-function 'emacsvox-aural--own-candidate-data)
                (lambda (data)
                  (let ((start (current-time)) (collections gcs-done))
                    (prog1 (if copy-p (funcall copier data) data)
                      (push (* 1000 (float-time (time-since start))) copy-samples)
                      (cl-incf copy-collections (- gcs-done collections))))))
               ((symbol-function 'emacsvox-aural--build-structured-timeline)
                (lambda (&rest args) (setq built (apply builder args)))))
       (cl-labels
           ((arm ()
              (when (eq copy-p 'record)
                (emacsvox-aural-recording--clear)
                (let ((inhibit-message t))
                  (emacsvox-aural-record-next-delivery 'main))))
            (submit ()
              (setq writes nil built nil)
              (emacsvox-aural-submit content :delivery-policy 'ordered :interruption-policy 'none)
              (unless (and built writes) (error "No structured output for %s" name)))
            (retire ()
              (dolist (lane (list speaker notification))
                (let (ids)
                  (maphash (lambda (id ticket)
                             (when (eq (tts--marker-dispatch-process ticket) lane) (push id ids)))
                           tts--marker-dispatches)
                  (dolist (id ids)
                    (tts--speaker-process-filter lane (format "__EMACSVOX_TRACKED__ %d completed\n" id)))
                  (tts--dispatch-drain lane)))))
         (dotimes (_ 5) (arm) (submit) (retire))
         (setq copy-samples nil copy-collections 0)
         (setq canonical (copy-sequence (car built)))
         (setf (plist-get canonical :generation) 1 (plist-get canonical :dispatch_id) 1)
         (garbage-collect)
         (let ((collections gcs-done) (gc-time gc-elapsed)
               (allocations (memory-use-counts)))
           (dotimes (_ iterations)
             (arm)
             (let ((start (current-time)))
               (submit)
               (push (* 1000 (float-time (time-since start))) samples))
             ;; Retire each owner without retaining all wire or history.
             (retire))
           (when (eq copy-p 'record)
             (let ((bundle (emacsvox-aural-recording--bundle)))
               (setq recording-bytes (length (emacsvox-aural-recording--json bundle))
                     recording-complete (gethash "complete" bundle)))
             (emacsvox-aural-recording--clear))
           (setq samples (sort samples #'<) copy-samples (sort copy-samples #'<))
           (list :case name :ownership copy-p :iterations iterations
                 :recording-bytes recording-bytes :recording-complete recording-complete
                 :text-bytes (string-bytes content)
                 :spans (length (plist-get (car built) :spans))
                 :protocol (plist-get (car built) :protocol_version)
                 :wire-bytes (apply #'+ (mapcar (lambda (write) (string-bytes (cdr write))) writes))
                 :median-ms (delivery-benchmark--percentile samples 0.5)
                 :p95-ms (delivery-benchmark--percentile samples 0.95)
                 :max-ms (car (last samples))
                 :copy-median-ms (delivery-benchmark--percentile copy-samples 0.5)
                 :copy-p95-ms (delivery-benchmark--percentile copy-samples 0.95)
                 :copy-gc-count copy-collections
                 :gc-count (- gcs-done collections) :gc-seconds (- gc-elapsed gc-time)
                 :allocations (cl-mapcar #'- (memory-use-counts) allocations)
                 :retained-owners (hash-table-count tts--marker-dispatches)
                 :document-sha256 (secure-hash 'sha256 (encode-coding-string (json-serialize canonical) 'utf-8))
                 :samples-ms samples)))))))

(dolist (function (append '(emacsvox-aural-submit emacsvox-aural--build-structured-timeline
                    emacsvox-aural--own-candidate-data emacsvox-aural--bind-timeline-candidate
                    tts--dispatch-write-packet)
                         (when (getenv "EMACSVOX_DELIVERY_RECORDING")
                           '(emacsvox-aural-recording--event))))
  (let ((path (symbol-file function 'defun)))
    (unless (and (file-in-directory-p path delivery-benchmark--root)
                 (string-suffix-p (if (equal delivery-benchmark--mode "compiled") ".elc" ".el") path))
      (error "Wrong loaded implementation: %s %s" function path))
    (princ (format "Loaded %s from %s\n" function path))))
(princ (format "Environment: %S\n" (list :emacs emacs-version :mode delivery-benchmark--mode
                                       :gc-cons-threshold (string-to-number (or (getenv "EMACSVOX_DELIVERY_GC_BYTES") "800000"))
                                       :gc-cons-percentage 0.1
                                       :warmup 5 :collection-between-iterations nil)))
(let* ((paragraph "A presentation combines its text, emphasis and cues. Moving to the next item should interrupt obsolete speech while preserving independent notifications. ")
       (table (mapconcat (lambda (index)
                          (concat (propertize (format "Item %d " index) 'personality 'voice-bolden)
                                  "status ready; modified today; owner local.\n"))
                        (number-sequence 1 40) ""))
       (cases (list (list 'navigation "Next heading" 120)
                    (list 'paragraph (concat paragraph paragraph paragraph) 100)
                    (list 'table-40-rows table 50)
                    (list 'fontified-code (delivery-benchmark--code) 30)
                    (list 'long-prose (apply #'concat (make-list 100 paragraph)) 20))))
  ;; Alternate order across rounds to expose warm-cache and timing noise.
  (dotimes (round 3)
    (dolist (case cases)
      (let (digests)
        (dolist (copy-p (if (getenv "EMACSVOX_DELIVERY_RECORDING")
                           (if (cl-evenp round) '(t record) '(record t))
                         (if (cl-evenp round) '(nil t) '(t nil))))
          (let ((result (apply #'delivery-benchmark--run (append case (list copy-p)))))
            (push (plist-get result :document-sha256) digests)
            (unless (zerop (plist-get result :retained-owners)) (error "Leaked delivery owner"))
            (princ (format "Repeated delivery: %S\n" (append (list :round round) result)))))
        (unless (equal (car digests) (cadr digests)) (error "Copy comparison changed document: %s" (car case)))))))

;;; benchmark-delivery.el ends here
