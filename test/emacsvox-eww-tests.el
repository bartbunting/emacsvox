;;; emacsvox-eww-tests.el --- EWW advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated EWW advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-eww.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--eww-ui-after-targets
  '(eww-up-url eww-top-url eww-next-url eww-previous-url
    eww-back-url eww-forward-url
    eww eww-open-in-new-buffer eww-reload eww-open-file
    eww-add-bookmark eww-beginning-of-text eww-end-of-text
    eww-bookmark-browse eww-bookmark-kill eww-bookmark-yank
    eww-list-bookmarks eww-next-bookmark eww-previous-bookmark
    eww-change-select eww-toggle-checkbox eww-submit
    shr-next-link shr-previous-link
    eww-list-buffers eww-buffer-kill eww-buffer-select
    eww-buffer-show-next eww-buffer-show-previous
    eww-restore-history)
  "EWW navigation and UI targets expected to use direct native advice.")

(ert-deftest emacsvox-eww-ui-advice-is-directly-registered ()
  "EWW navigation and UI advice uses native advice directly."
  (dolist (target emacsvox-test--eww-ui-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-eww-does-not-create-obsolete-quit-command ()
  "Loading the integration does not recreate removed `eww-quit'."
  (should-not (fboundp 'eww-quit)))

(ert-deftest emacsvox-eww-renderers-are-buffer-local ()
  "EWW renderers do not change links rendered by other SHR clients."
  (should
   (memq #'emacsvox-eww--setup-renderers eww-mode-hook))
  (should-not
   (eq (default-value 'shr-external-rendering-functions)
       emacsvox-eww-filter-renderers))
  (let ((default-renderers
         (default-value 'shr-external-rendering-functions)))
    (with-temp-buffer
      (emacsvox-eww--setup-renderers)
      (should
       (local-variable-p 'shr-external-rendering-functions))
      (should
       (eq shr-external-rendering-functions
           emacsvox-eww-filter-renderers)))
    (should
     (eq (default-value 'shr-external-rendering-functions)
         default-renderers))))

(ert-deftest emacsvox-eww-autospeak-uses-automatic-punctuation-policy ()
  "EWW autospeak applies prose policy without creating an override."
  (let (post-action)
    (cl-letf (((symbol-function 'add-hook)
               (lambda (hook function &rest _)
                 (when (eq hook 'emacsvox-eww-post-hook)
                   (setq post-action function)))))
      (emacsvox-eww-autospeak))
    (should post-action)
    (with-temp-buffer
      (setq major-mode 'eww-mode)
      (let ((tts-speaker-process nil))
        (cl-letf (((symbol-function 'emacsvox-speak-windowful) #'ignore))
          (funcall post-action))
        (should (eq tts-punctuation-mode 'some))
        (should-not tts-punctuation-mode-override)))))

(ert-deftest emacsvox-eww-url-navigation-feedback-is-target-aware ()
  "Only matching EWW URL navigation cues and speaks the header."
  (let ((ems--interactive-fn-name 'eww-forward-url)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-header-line)
               (lambda () (push 'speak-header events))))
      (emacsvox--advice-eww-back-url-after)
      (emacsvox--advice-eww-forward-url-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-header)))))

(ert-deftest emacsvox-eww-open-feedback-is-target-aware ()
  "Only the matching EWW open command emits its cue."
  (let ((ems--interactive-fn-name 'eww-open-file)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-eww-after "https://example.test")
      (emacsvox--advice-eww-open-file-after "page.html"))
    (should (equal events '(open-object)))))

(ert-deftest emacsvox-eww-bookmark-movement-keeps-unconditional-speech ()
  "Bookmark movement always speaks, but only interactive movement cues."
  (let ((ems--interactive-fn-name 'eww-next-bookmark)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-eww-previous-bookmark-after)
      (emacsvox--advice-eww-next-bookmark-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon select-object) speak-line)))))

(ert-deftest emacsvox-eww-link-navigation-preserves-feedback ()
  "Interactive link movement selects an icon and speaks the link."
  (with-temp-buffer
    (insert (propertize "link" 'help-echo "Link"))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'shr-next-link)
          (emacsvox-we-url-executor nil)
          (emacsvox-eww-url-at-point
           (lambda () "https://reddit.com/r/emacs"))
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list 'speak-region start end) events))))
        (emacsvox--advice-shr-next-link-after))
      (should
       (equal
        (nreverse events)
        '((icon item) (speak-region 1 5)))))))

(ert-deftest emacsvox-eww-buffer-select-feedback-preserves-order ()
  "Selecting an EWW buffer cues, speaks the mode line, then opens."
  (let ((ems--interactive-fn-name 'eww-buffer-select)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-eww-buffer-select-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-mode-line (icon open-object))))))

(ert-deftest emacsvox-eww-restore-history-refreshes-caches ()
  "Restoring EWW history always invalidates and rebuilds DOM caches."
  (let ((emacsvox-eww-cache-updated t)
        prepared)
    (cl-letf (((symbol-function 'emacsvox-eww-prepare-eww)
               (lambda () (setq prepared t))))
      (emacsvox--advice-eww-restore-history-after nil))
    (should-not emacsvox-eww-cache-updated)
    (should prepared)))

(defconst emacsvox-test--eww-url-around-advice
  '((eww-follow-link
     emacsvox--advice-eww-follow-link-around)
    (shr-copy-url
     emacsvox--advice-shr-copy-url-around)
    (shr-maybe-probe-and-copy-url
     emacsvox--advice-shr-maybe-probe-and-copy-url-around)
    (eww-browse-with-external-browser
     emacsvox--advice-eww-browse-with-external-browser-around))
  "EWW URL functions expected to use direct native around advice.")

(ert-deftest emacsvox-eww-url-advice-is-directly-registered ()
  "EWW URL and media advice uses native advice directly."
  (dolist (entry emacsvox-test--eww-url-around-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-url-http-user-agent-string-filter-return
    'url-http-user-agent-string))
  (dolist (target
           '(url-retrieve-internal url-truncate-url-for-viewing eww))
    (should
     (advice-member-p
      #'emacsvox--advice-google-url-filter-args target))))

(ert-deftest emacsvox-eww-user-agent-filter-reflects-masquerade ()
  "The user-agent result filter selects the configured identity."
  (let ((emacsvox-eww-masquerade t)
        (emacsvox-eww-masquerade-as "User-Agent: Test\r\n"))
    (should
     (equal
      (emacsvox--advice-url-http-user-agent-string-filter-return
       "ignored")
      "User-Agent: Test\r\n")))
  (let ((emacsvox-eww-masquerade nil))
    (should
     (equal
      (emacsvox--advice-url-http-user-agent-string-filter-return
       "ignored")
      "User-Agent: URL/Emacs \r\n"))))

(ert-deftest emacsvox-eww-google-url-filter-replaces-only-first-argument ()
  "Google result canonicalisation preserves all non-URL arguments."
  (let ((arguments
         '("https://google.test/result?id=1" callback (state) t)))
    (cl-letf (((symbol-function 'emacsvox-google-result-url-prefix)
               (lambda () "https://google.test/result"))
              ((symbol-function
                'emacsvox-google-canonicalize-result-url)
               (lambda (url) (concat "canonical:" url))))
      (should
       (equal
        (emacsvox--advice-google-url-filter-args arguments)
        '("canonical:https://google.test/result?id=1"
          callback (state) t)))))
  (let ((arguments '("https://example.test/" callback)))
    (cl-letf (((symbol-function 'emacsvox-google-result-url-prefix)
               (lambda () "https://google.test/result")))
      (should
       (eq
        (emacsvox--advice-google-url-filter-args arguments)
        arguments)))))

(ert-deftest emacsvox-eww-copy-url-calls-original-once ()
  "Interactive URL copying preserves one silenced call and its result."
  (let ((ems--interactive-fn-name 'shr-copy-url)
        (emacsvox-speak-messages t)
        (inhibit-message nil)
        (kill-ring nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-google-result-url-prefix)
               (lambda () "https://google.test/result"))
              ((symbol-function
                'emacsvox-google-canonicalize-result-url)
               (lambda (_) "https://example.test/canonical"))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-current-kill)
               (lambda () (push 'speak-kill events))))
      (should
       (eq
        (emacsvox--advice-shr-copy-url-around
         (lambda (url)
           (cl-incf calls)
           (push
            (list 'original url emacsvox-speak-messages inhibit-message)
            events)
           (setq kill-ring (list url))
           'copied)
         "https://google.test/result?id=1")
        'copied)))
    (should (= calls 1))
    (should (equal (car kill-ring) "https://example.test/canonical"))
    (should
     (equal
      (nreverse events)
      '((original "https://google.test/result?id=1" nil t)
        (icon delete-object)
        speak-kill)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-eww-follow-link-can-use-custom-executor ()
  "Interactive custom link execution skips the original and returns its value."
  (with-temp-buffer
    (insert (propertize "link" 'shr-url "https://example.test/"))
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'eww-follow-link)
           (emacsvox-eww-masquerade nil)
           (calls 0)
           observed
           events
           (emacsvox-we-url-executor
            (lambda (url)
              (setq observed (list url emacsvox-eww-masquerade))
              'executed)))
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'y-or-n-p)
                 (lambda (&rest _) t)))
        (should
         (eq
          (emacsvox--advice-eww-follow-link-around
           (lambda (&rest _)
             (cl-incf calls)
             'followed))
          'executed)))
      (should (= calls 0))
      (should (equal observed '("https://example.test/" t)))
      (should (equal events '((icon button)))))))

(ert-deftest emacsvox-eww-media-dispatch-selects-player-or-original ()
  "External browsing sends media to the player and other URLs onward."
  (let ((emacsvox-media-extensions "\\.mp3\\'")
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-m-player)
               (lambda (url)
                 (push (list 'player url) events)
                 'played)))
      (should
       (eq
        (emacsvox--advice-eww-browse-with-external-browser-around
         (lambda (&rest _)
           (cl-incf calls)
           'browsed)
         "https://example.test/audio.MP3")
        'played))
      (should
       (eq
        (emacsvox--advice-eww-browse-with-external-browser-around
         (lambda (url)
           (cl-incf calls)
           (push (list 'browser url) events)
           'browsed)
         "https://example.test/page")
        'browsed)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((player "https://example.test/audio.MP3")
        (browser "https://example.test/page"))))))

(defconst emacsvox-test--eww-shr-tags
  '(h1 h2 h3 h4 h5 h6 div math
    ul ol dl li dt dd p pre blockquote
    a b i em span table)
  "SHR renderers expected to receive Emacsvox tag-property advice.")

(ert-deftest emacsvox-eww-shr-advice-is-directly-registered ()
  "SHR tag and DOM property advice uses native advice directly."
  (dolist (tag emacsvox-test--eww-shr-tags)
    (let* ((target (intern (format "shr-tag-%s" tag)))
           (function
            (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry
           '((shr-tag-table-1
              emacsvox--advice-shr-tag-table-1-around)
             (shr-tag-div
              emacsvox--advice-shr-tag-div-dom-around)))
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should-not (fboundp 'shr-tag-form))
  (should-not (fboundp 'shr-tag-it)))

(ert-deftest emacsvox-eww-shr-heading-advice-calls-original-once ()
  "Heading rendering preserves its result and adds navigation properties."
  (with-temp-buffer
    (let ((calls 0)
          (dom '(h1 nil "Heading")))
      (should
       (eq
        (emacsvox--advice-shr-tag-h1-around
         (lambda (argument)
           (cl-incf calls)
           (should (eq argument dom))
           (insert "Heading\n")
           'rendered)
         dom)
        'rendered))
      (should (= calls 1))
      (should (eq (get-text-property 1 'h1) 'shr-tag))
      (should (eq (get-text-property 1 'h) 'shr-tag))
      (should-not (get-text-property 8 'h1)))))

(ert-deftest emacsvox-eww-shr-table-advice-calls-original-once ()
  "Table rendering preserves its result and caches the table DOM once."
  (with-temp-buffer
    (let ((calls 0)
          (dom '(table nil (tr nil (td nil "Cell")))))
      (should
       (eq
        (emacsvox--advice-shr-tag-table-1-around
         (lambda (argument)
           (cl-incf calls)
           (should (eq argument dom))
           (insert "Cell")
           'table-rendered)
         dom)
        'table-rendered))
      (should (= calls 1))
      (should (eq (get-text-property 1 'table-dom) dom))
      (should (eq (get-text-property 1 'auditory-icon) 'fill-object))
      (should (= (get-text-property 1 'table-start) 1))
      (should (= (get-text-property 1 'table-end) 4)))))

(ert-deftest emacsvox-eww-shr-div-advice-calls-original-once ()
  "Div rendering preserves its result and caches the div DOM once."
  (with-temp-buffer
    (let ((calls 0)
          (dom '(div ((class . "content")) "Text")))
      (should
       (eq
        (emacsvox--advice-shr-tag-div-dom-around
         (lambda (argument)
           (cl-incf calls)
           (should (eq argument dom))
           (insert "Text")
           'div-rendered)
         dom)
        'div-rendered))
      (should (= calls 1))
      (should (eq (get-text-property 1 'eww-dom) dom)))))

(defconst emacsvox-test--eww-lifecycle-advice
  '((eww-reload :around emacsvox--advice-eww-reload-around)
    (eww-display-html :before
     emacsvox--advice-eww-display-html-before)
    (eww-readable :around emacsvox--advice-eww-readable-around)
    (eww-display-image :around
     emacsvox--advice-eww-display-image-around))
  "Remaining EWW lifecycle advice and its native placement.")

(ert-deftest emacsvox-eww-lifecycle-advice-is-directly-registered ()
  "EWW lifecycle advice uses native advice directly."
  (dolist (entry emacsvox-test--eww-lifecycle-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-eww-reload-calls-default-original-once ()
  "Ordinary EWW reload preserves one original call and its result."
  (let ((emacsvox-eww-post-hook nil)
        (emacsvox-eww-feed nil)
        (emacsvox-eww-url-template nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'eww-current-url)
               (lambda () "https://example.test/"))
              ((symbol-function 'sox-sin)
               (lambda (&rest arguments)
                 (push (cons 'sox arguments) events))))
      (should
       (eq
        (emacsvox--advice-eww-reload-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (cons 'original arguments) events)
           'reloaded)
         t 'encode)
        'reloaded)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original t encode)
        (sox 0.5 "%-2:%-1" "fade h .1 .5 .4 gain -8 "))))))

(ert-deftest emacsvox-eww-readable-calls-original-once ()
  "Readable conversion preserves result and emits feedback afterwards."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-buffer)
               (lambda () (push 'speak-buffer events))))
      (should
       (eq
        (emacsvox--advice-eww-readable-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments inhibit-read-only)
            events)
           'readable)
         2)
        'readable)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original (2) t)
        (icon open-object)
        speak-buffer)))))

(ert-deftest emacsvox-eww-display-image-honours-inhibition ()
  "Image display calls once when enabled and is skipped when inhibited."
  (let ((emacsvox-eww-inhibit-images nil)
        (calls 0))
    (should
     (eq
      (emacsvox--advice-eww-display-image-around
       (lambda (buffer)
         (cl-incf calls)
         (should (eq buffer 'image-buffer))
         'displayed)
       'image-buffer)
      'displayed))
    (setq emacsvox-eww-inhibit-images t)
    (should-not
     (emacsvox--advice-eww-display-image-around
      (lambda (&rest _)
        (cl-incf calls))
      'image-buffer))
    (should (= calls 1))))

(ert-deftest emacsvox-eww-dom-filter-matches-nested-text ()
  "DOM filtering searches text nested inside inline elements."
  (let ((dom
         '(html nil
                (body nil
                      (p ((id . "match"))
                         "Read " (strong nil "accessible") " text")
                      (p ((id . "miss")) "Unrelated text"))))
        selected)
    (cl-letf (((symbol-function 'emacsvox-eww-current-dom)
               (lambda () dom))
              ((symbol-function 'eww-current-url)
               (lambda () "https://example.test/"))
              ((symbol-function 'dom-html-from-nodes)
               (lambda (nodes _url)
                 (setq selected nodes)
                 "<html></html>"))
              ((symbol-function 'emacsvox-eww-view-helper) #'ignore)
              ((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'emacsvox-speak-header-line) #'ignore))
      (eww-view-dom-element-having-text 'p "accessible"))
    (should (= (length selected) 1))
    (should (equal (dom-attr (car selected) 'id) "match"))))

(provide 'emacsvox-eww-tests)
;;; emacsvox-eww-tests.el ends here
