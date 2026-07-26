;;; emacsvox-sounds-tests.el --- Sound compatibility tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Characterize auditory-icon lookup, theme caching, dispatch, and queued text
;; properties before the aural-presentation resolver replaces those paths.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-sounds)
(require 'tts-speak)

(defun emacsvox-test--sound-file (directory name)
  "Create an empty Ogg file named NAME in DIRECTORY and return its path."
  (let ((file (expand-file-name (concat name ".ogg") directory)))
    (write-region "" nil file nil 'silent)
    file))

(defmacro emacsvox-test--with-sound-tree (&rest body)
  "Run BODY with temporary prompt and theme directories."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "emacsvox-sounds-" t))
          (prompts (expand-file-name "prompts" root))
          (theme-one (expand-file-name "one" root))
          (theme-two (expand-file-name "two" root)))
     (make-directory prompts)
     (make-directory theme-one)
     (make-directory theme-two)
     (unwind-protect
         (progn ,@body)
       (delete-directory root t))))

(ert-deftest emacsvox-sounds-cache-rebuild-discovers-ogg-files ()
  "Cache rebuilding interns Ogg basenames and ignores other files."
  (emacsvox-test--with-sound-tree
    (let* ((ogg (emacsvox-test--sound-file theme-one "item"))
           (other (expand-file-name "notes.txt" theme-one))
           (emacsvox-sounds-cache (make-hash-table)))
      (write-region "" nil other nil 'silent)
      (emacsvox-sounds-cache-rebuild theme-one)
      (should (equal (gethash 'item emacsvox-sounds-cache) ogg))
      (should-not (gethash 'notes emacsvox-sounds-cache)))))

(ert-deftest emacsvox-sounds-cache-unknown-name-falls-back-to-button ()
  "An unknown legacy icon currently resolves silently to button."
  (let ((emacsvox-sounds-cache (make-hash-table)))
    (puthash 'button "/sounds/button.ogg" emacsvox-sounds-cache)
    (should
     (equal
      (emacsvox-sounds-cache-get 'not-registered)
      "/sounds/button.ogg"))))

(ert-deftest emacsvox-sounds-theme-overlays-prompt-with-same-name ()
  "The selected theme currently wins when it duplicates a prompt name."
  (emacsvox-test--with-sound-tree
    (let* ((prompt (emacsvox-test--sound-file prompts "button"))
           (themed (emacsvox-test--sound-file theme-one "button"))
           (emacsvox-prompts-dir prompts)
           (emacsvox-sounds-cache (make-hash-table))
           (emacsvox-play-program nil))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
        (emacsvox-sounds-select-theme theme-one))
      (should-not (equal prompt themed))
      (should
       (equal (gethash 'button emacsvox-sounds-cache) themed)))))

(ert-deftest emacsvox-sounds-theme-switch-must-not-leak-old-assets ()
  "Selecting a new theme removes assets supplied only by the old theme."
  (emacsvox-test--with-sound-tree
    (emacsvox-test--sound-file prompts "button")
    (emacsvox-test--sound-file theme-one "only-in-one")
    (emacsvox-test--sound-file theme-two "only-in-two")
    (let ((emacsvox-prompts-dir prompts)
          (emacsvox-sounds-cache (make-hash-table))
          (emacsvox-play-program nil))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
        (emacsvox-sounds-select-theme theme-one)
        (should (gethash 'only-in-one emacsvox-sounds-cache))
        (emacsvox-sounds-select-theme theme-two))
      (should-not (gethash 'only-in-one emacsvox-sounds-cache))
      (should (gethash 'only-in-two emacsvox-sounds-cache)))))

(ert-deftest emacsvox-sounds-selects-registered-pack-and-aliases ()
  "Registered selection records the pack and installs compatibility aliases."
  (let ((emacsvox-sounds-cache (make-hash-table))
        (emacsvox-play-program nil))
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
      (emacsvox-sounds-select-theme '3d))
    (should (eq emacsvox-sounds-current-pack '3d))
    (should
     (equal
      (directory-file-name emacsvox-sounds-current-theme)
      (directory-file-name
       (expand-file-name "3d" emacsvox-sounds-dir))))
    (should
     (string-suffix-p
      "/3d/repeat-end.ogg"
      (gethash 'repeat-stop emacsvox-sounds-cache)))
    (should
     (string-suffix-p
      "/3d/close-object.ogg"
      (gethash 'shutdown emacsvox-sounds-cache)))))

(ert-deftest emacsvox-sounds-selects-newly-discovered-pack ()
  "Programmatic theme selection refreshes dynamic sound-pack discovery."
  (emacsvox-test--with-sound-tree
    (let ((emacsvox-aural-resource-pack-registry
           (make-hash-table :test #'eq))
          (emacsvox-aural-resource-pack-discovery-roots nil)
          (emacsvox-sounds-cache (make-hash-table))
          (emacsvox-sounds-owned-samples (make-hash-table :test #'equal))
          (emacsvox-play-program nil))
      (let ((emacsvox-aural--resource-pack-discovery-registry
             emacsvox-aural-resource-pack-registry))
        (emacsvox-aural-register-bundled-resources root)
        (let ((bart (expand-file-name "bart" root)))
          (make-directory bart)
          (emacsvox-test--sound-file bart "button")
          (emacsvox-test--sound-file bart "item")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-sounds-select-theme 'bart))
          (should (eq emacsvox-sounds-current-pack 'bart))
          (should
           (string-suffix-p
            "/bart/item.ogg"
            (gethash 'item emacsvox-sounds-cache))))))))

(ert-deftest emacsvox-sounds-follows-active-aural-scheme ()
  "Selecting a scheme switches to its inherited registered sound pack."
  (let ((emacsvox-aural-scheme-registry
         (make-hash-table :test #'eq))
        (emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-active-scheme-changed-hook
         '(emacsvox-sounds-follow-aural-scheme))
        (emacsvox-sounds-cache (make-hash-table))
        (emacsvox-sounds-current-pack 'chimes)
        (emacsvox-use-icons nil)
        (emacsvox-play-program nil))
    (emacsvox-aural--register-default-scheme)
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id spatial
       :summary "Use bundled spatial cues"
       :parent default
       :resource-pack 3d
       :rules ()))
    (emacsvox-aural-select-scheme 'spatial)
    (should (eq emacsvox-sounds-current-pack '3d))
    (should
     (string-suffix-p
      "/3d/item.ogg"
      (gethash 'item emacsvox-sounds-cache)))))

(ert-deftest emacsvox-sounds-resource-reflects-player-contract ()
  "Server and SoX use paths while Pulse uses uploaded sample names."
  (let ((emacsvox-sounds-cache (make-hash-table))
        (emacsvox-pactl "/usr/bin/pactl"))
    (puthash 'item "/sounds/item.ogg" emacsvox-sounds-cache)
    (puthash 'button "/sounds/button.ogg" emacsvox-sounds-cache)
    (let ((emacsvox-play-program nil))
      (should
       (equal (emacsvox-sounds-resource 'item) "/sounds/item.ogg")))
    (let ((emacsvox-play-program "/usr/bin/play"))
      (should
       (equal (emacsvox-sounds-resource 'item) "/sounds/item.ogg")))
    (let ((emacsvox-play-program "/usr/bin/pactl"))
      (should (equal (emacsvox-sounds-resource 'item) "item"))
      (should (equal (emacsvox-sounds-resource 'unknown) "button")))))

(ert-deftest emacsvox-sounds-icon-dispatches-by-player-and-toggle ()
  "Immediate icons resolve concretely and continue to honor the toggle."
  (let (events)
    (cl-letf
        (((symbol-function 'emacsvox-sounds-play-concrete-cue)
          (lambda (resource sample-id)
            (push (list resource sample-id) events))))
      (let ((emacsvox-use-icons t)
            (emacsvox-play-program nil))
        (emacsvox-icon 'item))
      (let ((emacsvox-use-icons t)
            (emacsvox-play-program "/usr/bin/play"))
        (emacsvox-icon 'open-object))
      (let ((emacsvox-use-icons nil)
            (emacsvox-play-program nil))
        (emacsvox-icon 'close-object)))
    (should
     (= (length events) 2))
    (should
     (string-suffix-p
      "/chimes/item.ogg"
      (car (cadr events))))
    (should
     (string-suffix-p
      "/chimes/open-object.ogg"
      (caar events)))))

(ert-deftest emacsvox-sounds-concrete-cue-selects-server-or-sox ()
  "Concrete compatibility cues still honor the selected playback backend."
  (let ((tts-speaker-process 'speaker)
        events)
    (cl-letf
        (((symbol-function 'process-send-string)
          (lambda (process text)
            (push (list 'server process text) events)))
         ((symbol-function 'start-process)
          (lambda (_name _buffer program &rest args)
            (push (list 'local program args) events))))
      (let ((emacsvox-play-program nil))
        (emacsvox-sounds-play-concrete-cue
         "/sounds/item.ogg" "sample-item"))
      (let ((emacsvox-play-program "/usr/bin/play")
            (ems--play-args "-q"))
        (emacsvox-sounds-play-concrete-cue
         "/sounds/open.ogg" "sample-open")))
    (should
     (equal
      (nreverse events)
      '((server speaker "p /sounds/item.ogg\n")
        (local "/usr/bin/play" ("-q" "/sounds/open.ogg")))))))

(ert-deftest emacsvox-sounds-sox-applies-normalized-cue-balance ()
  "Local SoX playback turns normalized balance into a two-channel remix."
  (let ((sox-play "/usr/bin/play")
        (emacsvox-play-program "/usr/bin/play")
        (ems--play-args "-q")
        event)
    (cl-letf
        (((symbol-function 'start-process)
          (lambda (_name _buffer program &rest args)
            (setq event (list program args)))))
      (emacsvox-sounds-play-concrete-cue
       "/sounds/item.ogg" "sample-item" 0.25))
    (should
     (equal
      event
      (list
       sox-play
       '("-q" "/sounds/item.ogg"
         "channels" "2" "remix" "-m" "1v0.750000" "2v1.000000"))))))

(ert-deftest emacsvox-sounds-queued-icon-uses-concrete-resource ()
  "Queued legacy icons send the currently resolved concrete resource."
  (let ((tts-speaker-process 'speaker)
        writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (process text)
                 (push (list process text) writes))))
      (emacsvox-queue-icon 'item))
    (should
     (eq (caar writes) 'speaker))
    (should
     (string-suffix-p
      "/chimes/item.ogg\n"
      (cadar writes)))))

(ert-deftest emacsvox-sounds-auditory-property-precedes-text ()
  "An auditory-icon property currently queues before reset and spoken text."
  (with-temp-buffer
    (insert (propertize "heading" 'auditory-icon 'item))
    (let ((emacsvox-use-icons t)
          (voice-lock-mode nil)
          events)
      (cl-letf (((symbol-function 'emacsvox-queue-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-voice-reset-code)
                 (lambda () "reset"))
                ((symbol-function 'tts--protocol-queue-code)
                 (lambda (code) (push (list 'code code) events)))
                ((symbol-function 'tts--protocol-queue-text)
                 (lambda (text) (push (list 'text text) events))))
        (tts-audio-format (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((icon item)
          (code "reset")
          (text "heading")))))))

(ert-deftest emacsvox-sounds-auditory-property-honors-icon-toggle ()
  "Turning icons off suppresses a queued auditory-icon text property."
  (with-temp-buffer
    (insert (propertize "heading" 'auditory-icon 'item))
    (let ((emacsvox-use-icons nil)
          (voice-lock-mode nil)
          events)
      (cl-letf (((symbol-function 'emacsvox-queue-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-voice-reset-code)
                 (lambda () "reset"))
                ((symbol-function 'tts--protocol-queue-code) #'ignore)
                ((symbol-function 'tts--protocol-queue-text) #'ignore))
        (tts-audio-format (point-min) (point-max)))
      (should-not events))))

(provide 'emacsvox-sounds-tests)
;;; emacsvox-sounds-tests.el ends here
