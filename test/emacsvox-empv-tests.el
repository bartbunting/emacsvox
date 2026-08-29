;;; emacsvox-empv-tests.el --- EMPV advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(require 'emacsvox-optional-module-test-utils)
(package-initialize)
(require 'empv)
(load (expand-file-name "../lisp/emacsvox-empv.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-empv-loads-without-empv ()
  "The integration module should load before optional EMPV is installed."
  (emacsvox-optional-module-test-load
   "emacsvox-empv.el"
   '(when (locate-library "empv")
      (error "EMPV unexpectedly available in clean Emacs"))
   '(unless (and (featurep 'emacsvox-empv)
                 (not (featurep 'empv)))
      (error "Emacsvox EMPV did not load independently"))))

(ert-deftest emacsvox-empv-setup-installs-keymaps ()
  "Loading EMPV should install Emacsvox's integration bindings."
  (should
   (eq (lookup-key empv-youtube-results-mode-map (kbd "t"))
       'emacsvox-empv-current-title))
  (should
   (eq (lookup-key empv-map (kbd "%"))
       'emacsvox-empv-percentage-seek)))

(ert-deftest emacsvox-empv-advice-is-current-and-direct ()
  "Current EMPV targets use native advice directly."
  (dolist (entry emacsvox-empv--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-empv--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-empv-feedback-is-target-aware ()
  "Only the matching interactive EMPV toggle command provides feedback."
  (let ((ems--interactive-fn-name 'empv-toggle)
        events)
    (cl-letf (((symbol-function 'tts-stop)
               (lambda (scope) (push scope events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-empv-pause-after)
      (emacsvox--advice-empv-toggle-after))
    (should (equal (nreverse events) '(all button)))))

(ert-deftest emacsvox-empv-play-history-uses-url-argument ()
  "EMPV history advice records the URL passed by native advice."
  (let ((emacsvox-empv-history nil)
        (emacsvox-empv-history-max 4))
    (cl-letf (((symbol-function 'emacsvox-google-result-url-prefix)
               (lambda () "google:"))
              ((symbol-function 'emacsvox-google-canonicalize-result-url)
               (lambda (url) (concat "canonical:" url))))
      (emacsvox--advice-empv-play-before "https://example.test/media"))
    (should
     (equal emacsvox-empv-history '("https://example.test/media")))))

(ert-deftest emacsvox-empv-lyrics-fallback-preserves-override ()
  "The EMPV lyrics override does not call the original function."
  (let ((original-calls 0)
        query)
    (cl-letf (((symbol-function 'emacsvox-websearch-google-lite)
               (lambda (song) (setq query song))))
      (should-not
       (emacsvox--advice-empv--lyrics-on-not-found-around
        (lambda (&rest _) (cl-incf original-calls))
        "Artist Song")))
    (should (= original-calls 0))
    (should (equal query "Artist Song"))))

(provide 'emacsvox-empv-tests)
;;; emacsvox-empv-tests.el ends here
