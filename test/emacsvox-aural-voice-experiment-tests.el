;;; emacsvox-aural-voice-experiment-tests.el --- Physical tuner tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Verify in-memory exploration and separately recoverable persistence.
;;; Code:
(require 'emacsvox-aural-voice-workbench-tests)
(require 'emacsvox-aural-voice-experiment)

(defmacro emacsvox-test--with-voice-experiment (&rest body)
  "Run BODY with a disposable exact physical voice experiment."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-voice-workbench
     (let ((emacsvox-aural-voice-palette-registry (copy-hash-table emacsvox-aural-voice-palette-registry))
           (emacsvox-aural-voice-palette-override nil)
           (emacsvox-aural-voice-palette-changed-hook nil)
           (before-buffers (buffer-list))
           (pair (car (emacsvox-aural-voice-workbench--all-engine-voices))))
       (unwind-protect
           (save-window-excursion
             (cl-letf (((symbol-function 'emacsvox-aural-voice-tuner--play-text) #'ignore))
               (emacsvox-aural-voice-experiment-open pair (current-buffer) "Identical sample.")
               ,@body))
         (dolist (buffer (buffer-list))
           (unless (memq buffer before-buffers) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-experiment-adjustment-does-not-change-live-state ()
  "Opening, adjustment, undo, reset, and comparison perform no save or apply."
  (emacsvox-test--with-voice-workbench
    (let ((palette emacsvox-aural-voice-palette-override)
          (routing (copy-tree emacsvox-aural-voice-workbench-staged-profile))
          (buffers (buffer-list)))
      (unwind-protect
          (save-window-excursion
            (cl-letf (((symbol-function 'emacsvox-aural-save-user-data)
                       (lambda (&rest _) (ert-fail "Unexpected style write")))
                      ((symbol-function 'emacsvox-aural-save-routing-profiles)
                       (lambda (&rest _) (ert-fail "Unexpected route write")))
                      ((symbol-function 'tts-apply-voice-configuration)
                       (lambda (&rest _) (ert-fail "Unexpected configuration apply")))
                      ((symbol-function 'emacsvox-aural-voice-tuner--play-text) #'ignore))
              (let* ((source (current-buffer))
                     (pair (car (emacsvox-aural-voice-workbench--all-engine-voices)))
                     (experiment (emacsvox-aural-voice-experiment-open pair source "Same sample")))
                (should-not emacsvox-aural-voice-tuner-palette)
                (should-not emacsvox-aural-voice-tuner-dirty)
                (emacsvox-aural-ui-goto-row 'average-pitch)
                (emacsvox-aural-voice-tuner-increase)
                (should emacsvox-aural-voice-tuner-dirty)
                (should (eq experiment (emacsvox-aural-voice-experiment-open pair source "Another sample")))
                (should (equal emacsvox-aural-voice-tuner-preview-text "Same sample"))
                (emacsvox-aural-voice-experiment-undo)
                (should-not emacsvox-aural-voice-tuner-dirty)
                (emacsvox-aural-voice-experiment-reset)
                (emacsvox-aural-voice-experiment-compare)
                (should (eq palette emacsvox-aural-voice-palette-override))
                (with-current-buffer source
                  (should (equal routing emacsvox-aural-voice-workbench-staged-profile))))))
        (dolist (buffer (buffer-list))
          (unless (memq buffer buffers) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-experiment-sweep-is-exact-and-nonmutating ()
  "Three labelled values share one cancellable sequence and unchanged sample text."
  (emacsvox-test--with-voice-experiment
    (emacsvox-aural-ui-goto-row 'average-pitch)
    (let ((values '(2 5 8)) entries
          (before (emacsvox-aural-voice-experiment--snapshot)))
      (cl-letf (((symbol-function 'read-number) (lambda (&rest _) (pop values)))
                ((symbol-function 'tts-preview-voices) (lambda (value _callback) (setq entries value))))
        (emacsvox-aural-voice-experiment-sweep))
      (should (= (length entries) 6))
      (should (equal (mapcar (lambda (i) (plist-get (nth i entries) :text)) '(1 3 5))
                     '("Identical sample." "Identical sample." "Identical sample.")))
      (should (equal (plist-get (plist-get (car entries) :selector) :voice-id) "eci:Reed"))
      (should (= (plist-get (plist-get (nth 1 entries) :acss) :average-pitch) (/ 2.0 9.0)))
      (should (equal before (emacsvox-aural-voice-experiment--snapshot))))))

(ert-deftest emacsvox-aural-experiment-keep-proposal-has-separate-destinations ()
  "Preparing all three keep variants does not change either registry or selection."
  (emacsvox-test--with-voice-experiment
    (let ((style (emacsvox-aural-voice-experiment--prepare-keep 'style 'example 'experiment-test))
          (route (emacsvox-aural-voice-experiment--prepare-keep 'route 'voice-bolden nil))
          (both (emacsvox-aural-voice-experiment--prepare-keep 'both 'bolden 'experiment-test)))
      (should (plist-get style :palette)) (should-not (plist-get style :routing))
      (should (plist-get route :routing)) (should-not (plist-get route :palette))
      (should (plist-get both :palette)) (should (plist-get both :routing))
      (should-not (emacsvox-aural-voice-palette 'experiment-test))
      (should-not emacsvox-aural-voice-palette-override)
      (should (eq emacsvox-aural-active-routing-profile 'workstation)))))

(ert-deftest emacsvox-aural-experiment-partial-save-is-retryable ()
  "A successful style write survives a routing write failure and is not repeated."
  (emacsvox-test--with-voice-experiment
    (let ((origin (current-buffer))
          (plan (emacsvox-aural-voice-experiment--prepare-keep 'both 'bolden 'experiment-test))
          (style-writes 0) (route-writes 0) (fail-route t))
      (with-temp-buffer
        (emacsvox-aural-voice-experiment-keep-mode)
        (setq emacsvox-aural-voice-experiment-origin origin
              emacsvox-aural-voice-experiment-keep-plan plan)
        (cl-letf (((symbol-function 'emacsvox-aural-save-user-data)
                   (lambda (&rest _) (cl-incf style-writes)))
                  ((symbol-function 'emacsvox-aural-save-routing-profiles)
                   (lambda (&rest _) (cl-incf route-writes) (when fail-route (error "Disk full"))))
                  ((symbol-function 'tts-apply-voice-configuration)
                   (lambda (callback) (funcall callback '(:status applied)))))
          (emacsvox-aural-voice-experiment-save-and-apply)
          (should (plist-get plan :palette-saved))
          (should-not (plist-get plan :route-saved))
          (should (eq (plist-get plan :apply-status) 'failed))
          (should (string-match-p "Disk full" (plist-get plan :failure)))
          (setq fail-route nil)
          (emacsvox-aural-voice-experiment-save-and-apply)
          (should (plist-get plan :route-saved))
          (should (eq (plist-get plan :apply-status) 'applied))
          (should (= style-writes 1))
          (should (= route-writes 2)))))))

(ert-deftest emacsvox-aural-experiment-apply-failure-retains-saved-result ()
  "An adapter failure leaves the saved desired routes available for retry."
  (emacsvox-test--with-voice-experiment
    (let ((plan (emacsvox-aural-voice-experiment--prepare-keep 'route 'voice-bolden nil))
          (writes 0) (status 'failed))
      (with-temp-buffer
        (emacsvox-aural-voice-experiment-keep-mode)
        (setq emacsvox-aural-voice-experiment-keep-plan plan)
        (cl-letf (((symbol-function 'emacsvox-aural-save-routing-profiles)
                   (lambda (&rest _) (cl-incf writes)))
                  ((symbol-function 'tts-apply-voice-configuration)
                   (lambda (callback) (funcall callback (list :status status)))))
          (emacsvox-aural-voice-experiment-save-and-apply)
          (should (plist-get plan :route-saved))
          (should (eq (plist-get plan :apply-status) 'failed))
          (setq status 'applied)
          (emacsvox-aural-voice-experiment-save-and-apply)
          (should (= writes 1))
          (should (eq (plist-get plan :apply-status) 'applied)))))))

(ert-deftest emacsvox-aural-experiment-refuses-stale-keep-proposals ()
  "A changed destination is not overwritten by an older reviewed proposal."
  (emacsvox-test--with-voice-experiment
    (let ((plan (emacsvox-aural-voice-experiment--prepare-keep 'route 'voice-bolden nil)))
      (remhash 'workstation emacsvox-aural-routing-profile-registry)
      (emacsvox-aural-register-routing-profile-data
       (plist-put (copy-tree emacsvox-test--workbench-routing-profile) :summary "Changed elsewhere") "test")
      (with-temp-buffer
        (emacsvox-aural-voice-experiment-keep-mode)
        (setq emacsvox-aural-voice-experiment-keep-plan plan)
        (cl-letf (((symbol-function 'emacsvox-aural-save-routing-profiles)
                   (lambda (&rest _) (ert-fail "Stale proposal wrote routing"))))
          (emacsvox-aural-voice-experiment-save-and-apply))
        (should (eq (plist-get plan :apply-status) 'failed))
        (should (string-match-p "Routing changed" (plist-get plan :failure)))))))

(ert-deftest emacsvox-aural-experiment-feedback-uses-exact-working-settings ()
  "Navigation uses the working selector and normalized parameters; old callbacks are ignored."
  (emacsvox-test--with-voice-workbench
    (with-temp-buffer
      (emacsvox-aural-voice-experiment-mode)
      (setq emacsvox-aural-voice-tuner-route-selector
            '(:kind exact :scope session :engine-id "eloquence" :voice-id "eci:Reed")
            emacsvox-aural-voice-tuner-route-engine
            (car (plist-get emacsvox-test--workbench-inventory :engines))
            emacsvox-aural-voice-tuner-working-style '(:average-pitch 4 :gain 5 :pan 5)
            emacsvox-aural-voice-tuner-initial-style '(:average-pitch 4 :gain 5 :pan 5))
      (emacsvox-aural-voice-tuner-refresh)
      (let (requests callbacks)
        (cl-letf (((symbol-function 'tts-preview-voice)
                   (lambda (text selector &rest arguments)
                     (push (list text selector arguments) requests)
                     (push (plist-get arguments :callback) callbacks)))
                  ((symbol-function 'tts-speak)
                   (lambda (&rest _) (ert-fail "Working voice unexpectedly fell back")))
                  ((symbol-function 'emacsvox-icon) #'ignore))
          (emacsvox-aural-ui-next-row)
          (emacsvox-aural-voice-tuner--speak-text "Help in the working voice")
          (should (= (length requests) 2))
          (should (equal (plist-get (cadar requests) :voice-id) "eci:Reed"))
          (should (= (plist-get (plist-get (caddar requests) :acss) :average-pitch) (/ 4.0 9.0)))
          (should (= (plist-get (plist-get (caddar requests) :effects) :gain) 0.5))
          (should (= (plist-get (plist-get (caddar requests) :effects) :pan) 0.5))
          (funcall (cadr callbacks) '(:status failed))
          (should (eq (plist-get emacsvox-aural-voice-tuner-preview-result :status) 'running))
          (funcall (car callbacks) '(:status completed :degraded-acss (stress)))
          (should (equal (emacsvox-aural-voice-tuner--effective-value 'stress) "reported omitted"))
          (should (string-match-p "exact value not reported"
                                  (emacsvox-aural-voice-tuner--effective-value 'average-pitch))))))))

(provide 'emacsvox-aural-voice-experiment-tests)
;;; emacsvox-aural-voice-experiment-tests.el ends here
