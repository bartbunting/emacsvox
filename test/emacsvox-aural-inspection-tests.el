;;; emacsvox-aural-inspection-tests.el --- Aural inspection tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Source ownership, lifecycle, nested-interface, and explanation-context
;; tests for the shared inspection layer.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-explanation)
(require 'emacsvox-aural-feature-fragments)

(ert-deftest emacsvox-aural-inspection-propagates-nested-source ()
  "Nested interfaces retain the original ordinary inspection source."
  (let ((emacsvox-aural-inspection-last-source-buffer nil)
        (source (generate-new-buffer " *aural-inspection-source*"))
        (first (generate-new-buffer " *aural-inspection-first*"))
        (second (generate-new-buffer " *aural-inspection-second*")))
    (unwind-protect
        (progn
          (with-current-buffer source
            (should
             (eq
              (emacsvox-aural-inspection-remember-source-buffer)
              source)))
          (with-current-buffer first
            (emacsvox-aural-interface-mode)
            (emacsvox-aural-inspection-attach-source source)
            (should
             (eq
              (emacsvox-aural-inspection-source-buffer)
              source))
            (with-current-buffer second
              (emacsvox-aural-interface-mode)
              (emacsvox-aural-inspection-attach-source
               (with-current-buffer first
                 (emacsvox-aural-inspection-remember-source-buffer)))
              (should
               (eq
                (emacsvox-aural-inspection-source-buffer)
                source)))))
      (dolist (buffer (list source first second))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-aural-inspection-dead-source-does-not-drift ()
  "A dead explicit source does not become an unrelated recent buffer."
  (let ((emacsvox-aural-inspection-last-source-buffer nil)
        (source (generate-new-buffer " *aural-inspection-dead*"))
        (replacement (generate-new-buffer " *aural-inspection-new*"))
        (interface (generate-new-buffer " *aural-inspection-owner*")))
    (unwind-protect
        (progn
          (with-current-buffer source
            (emacsvox-aural-inspection-remember-source-buffer))
          (with-current-buffer interface
            (emacsvox-aural-interface-mode)
            (emacsvox-aural-inspection-attach-source source))
          (kill-buffer source)
          (with-current-buffer replacement
            (emacsvox-aural-inspection-remember-source-buffer))
          (with-current-buffer interface
            (should-not
             (emacsvox-aural-inspection-source-buffer))
            (should
             (local-variable-p
              'emacsvox-aural-ui-source-buffer))))
      (dolist (buffer (list source replacement interface))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-aural-inspection-distinguishes-fallback-from-none ()
  "An unattached legacy interface may fall back, but explicit nil may not."
  (let ((emacsvox-aural-inspection-last-source-buffer nil)
        (source (generate-new-buffer " *aural-inspection-fallback*")))
    (unwind-protect
        (progn
          (with-current-buffer source
            (emacsvox-aural-inspection-remember-source-buffer))
          (with-temp-buffer
            (emacsvox-aural-interface-mode)
            (should
             (eq
              (emacsvox-aural-inspection-source-buffer)
              source))
            (emacsvox-aural-inspection-attach-source nil)
            (should-not
             (emacsvox-aural-inspection-source-buffer))))
      (when (buffer-live-p source)
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-inspection-managers-propagate-source ()
  "Real manager opening commands attach source through a nested transition."
  (let ((emacsvox-aural-inspection-last-source-buffer nil)
        (source (generate-new-buffer " *aural-manager-source*")))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer source
            (emacsvox-list-aural-semantics))
          (with-current-buffer "*Aural Semantics*"
            (should
             (eq
              (emacsvox-aural-inspection-source-buffer)
              source))
            (emacsvox-aural-list-feature-fragments))
          (with-current-buffer "*Aural Feature Fragments*"
            (should
             (eq
              (emacsvox-aural-inspection-source-buffer)
              source))))
      (dolist
          (buffer
           (list
            source
            (get-buffer "*Aural Semantics*")
            (get-buffer "*Aural Feature Fragments*")))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-aural-inspection-explanation-reads-in-source ()
  "A manager without presentation history simulates in its attached source."
  (let ((emacsvox-aural-inspection-last-source-buffer nil)
        (source (generate-new-buffer " *aural-explanation-source*"))
        (interface (generate-new-buffer " *aural-explanation-manager*"))
        observed)
    (unwind-protect
        (progn
          (with-current-buffer interface
            (emacsvox-aural-interface-mode)
            (emacsvox-aural-inspection-attach-source source)
            (cl-letf
                (((symbol-function 'emacsvox-aural-last-presentation)
                  (lambda (&rest _) nil))
                 ((symbol-function
                   'emacsvox-aural-explanation--read-explanation-input)
                  (lambda (_)
                    (setq observed (current-buffer))
                    (list '(:role example)
                          '(:occasion inspection)))))
              (should
               (equal
                (emacsvox-aural-explanation--interactive-explanation-input nil)
                '((:role example) (:occasion inspection) nil)))))
          (should (eq observed source)))
      (dolist (buffer (list source interface))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(provide 'emacsvox-aural-inspection-tests)

;;; emacsvox-aural-inspection-tests.el ends here
