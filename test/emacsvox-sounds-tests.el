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

(ert-deftest emacsvox-sounds-arbitrary-theme-does-not-govern-icon-resolver ()
  "Characterize compatibility cache selection being ignored by icons."
  (emacsvox-test--with-sound-tree
    (let* ((custom (emacsvox-test--sound-file theme-one "item"))
           (emacsvox-prompts-dir prompts)
           (emacsvox-sounds-cache (make-hash-table))
           (emacsvox-sounds-owned-samples (make-hash-table :test #'equal))
           (emacsvox-sounds-current-pack 'chimes)
           (emacsvox-sounds-current-theme nil)
           (emacsvox-sounds--silent-theme-selection t)
           (emacsvox-use-icons t)
           (emacsvox-play-program nil)
           played)
      (emacsvox-sounds-select-theme theme-one)
      (should-not emacsvox-sounds-current-pack)
      (should (equal (gethash 'item emacsvox-sounds-cache) custom))
      (cl-letf
          (((symbol-function 'emacsvox-sounds-play-concrete-cue)
            (lambda (resource _sample-id)
              (setq played resource))))
        (emacsvox-icon 'item))
      (should
       (string-suffix-p "/packs/chimes/item.ogg" played))
      (should-not (equal played custom)))))

(ert-deftest emacsvox-sounds-reconciles-removed-active-pack ()
  "Discovery removal selects the scheme pack and discards stale cache entries."
  (emacsvox-test--with-sound-tree
    (let* ((bart (expand-file-name "bart" root))
           (chimes-button (emacsvox-test--sound-file theme-one "button"))
           (emacsvox-aural-resource-pack-registry
            (make-hash-table :test #'eq))
           (emacsvox-aural-resource-overlay-registry
            (make-hash-table :test #'eq))
           (emacsvox-aural-resource-packs-changed-hook
            '(emacsvox-sounds-refresh-resource-providers))
           (emacsvox-aural-resource-pack-discovery-roots nil)
           (emacsvox-aural-personal-sound-packs-directory nil)
           (emacsvox-aural-configuration-generation 0)
           (emacsvox-aural-configuration-changed-hook nil)
           (emacsvox-aural--current-rules-cache
            (make-hash-table :test #'equal))
           (emacsvox-aural--provider-cache
            (make-hash-table :test #'equal))
           (emacsvox-sounds-current-pack nil)
           (emacsvox-sounds-current-theme nil)
           (emacsvox-sounds-cache (make-hash-table))
           (emacsvox-play-program nil))
      (make-directory bart)
      (emacsvox-test--sound-file bart "button")
      (emacsvox-aural-register-resource-pack
       'chimes :summary "Fallback pack" :directory theme-one)
      (emacsvox-aural-discover-resource-packs root)
      (setq
       emacsvox-sounds-current-pack 'bart
       emacsvox-sounds-current-theme bart)
      (puthash 'stale-only
               (expand-file-name "stale.ogg" bart)
               emacsvox-sounds-cache)
      (delete-directory bart t)
      (emacsvox-aural-discover-resource-packs root)
      (should (eq emacsvox-sounds-current-pack 'chimes))
      (should-not (gethash 'stale-only emacsvox-sounds-cache))
      (should (equal (gethash 'button emacsvox-sounds-cache)
                     chimes-button)))))

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
       (expand-file-name "packs/3d" emacsvox-sounds-dir))))
    (should
     (string-suffix-p
      "/packs/3d/repeat-end.ogg"
      (gethash 'repeat-stop emacsvox-sounds-cache)))
    (should
     (string-suffix-p
      "/packs/3d/close-object.ogg"
      (gethash 'shutdown emacsvox-sounds-cache)))))

(ert-deftest emacsvox-sounds-selects-newly-discovered-pack ()
  "Programmatic theme selection refreshes dynamic sound-pack discovery."
  (emacsvox-test--with-sound-tree
    (let ((emacsvox-aural-resource-pack-registry
           (make-hash-table :test #'eq))
          (emacsvox-aural-personal-sound-packs-directory nil)
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

(ert-deftest emacsvox-sounds-refreshes-live-module-earcon-overlays ()
  "Registering or disabling a module overlay refreshes the active sound cache."
  (emacsvox-test--with-sound-tree
    (let* ((notmuch-directory (expand-file-name "notmuch" theme-one))
           (emacsvox-aural-cue-registry
            (copy-hash-table emacsvox-aural-cue-registry))
           (emacsvox-aural-resource-pack-registry
            (make-hash-table :test #'eq))
           (emacsvox-aural-resource-overlay-registry
            (make-hash-table :test #'eq))
           (emacsvox-aural-disabled-resource-overlays nil)
           (emacsvox-aural-resource-overlays-changed-hook
            '(emacsvox-sounds-refresh-resource-providers))
           (emacsvox-sounds-current-pack 'bart)
           (emacsvox-sounds-cache (make-hash-table))
           (module-default
            (emacsvox-test--sound-file
             theme-two "notmuch-attachment"))
           module-override
           fallback)
      (make-directory notmuch-directory)
      (emacsvox-test--sound-file theme-one "button")
      (setq
       fallback (emacsvox-test--sound-file theme-one "item")
       module-override
       (emacsvox-test--sound-file
        notmuch-directory "notmuch-attachment"))
      (emacsvox-aural-register-cue
       'notmuch-attachment
       :summary "A Notmuch attachment was reached"
       :fallback 'item
       :owner 'notmuch)
      (emacsvox-aural-register-resource-pack
       'bart :summary "Bart sounds" :directory theme-one)
      (emacsvox-aural-register-resource-overlay
       'notmuch-earcons
       :summary "Notmuch-specific earcons"
       :owner 'notmuch
       :directory theme-two)
      (should-not (equal module-default module-override))
      (should
       (equal
        (gethash 'notmuch-attachment emacsvox-sounds-cache)
        module-override))
      (emacsvox-aural-set-disabled-resource-overlays
       '(notmuch-earcons))
      (should
       (equal
        (gethash 'notmuch-attachment emacsvox-sounds-cache)
        fallback)))))

(ert-deftest emacsvox-sounds-follows-active-aural-scheme ()
  "Selecting a scheme switches to its inherited registered sound pack."
  (let ((emacsvox-aural-scheme-registry
         (make-hash-table :test #'eq))
        (emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-active-scheme-changed-hook nil)
        (emacsvox-aural-effective-resource-pack-changed-hook
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
    (let ((generation emacsvox-aural-configuration-generation))
      (emacsvox-aural-select-scheme 'spatial)
      (should
       (= emacsvox-aural-configuration-generation
          (1+ generation))))
    (should (eq emacsvox-sounds-current-pack '3d))
    (should
     (string-suffix-p
      "/packs/3d/item.ogg"
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
      "/packs/chimes/item.ogg"
      (car (cadr events))))
    (should
     (string-suffix-p
      "/packs/chimes/open-object.ogg"
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
      '((server speaker "p \"/sounds/item.ogg\"\n")
        (local "/usr/bin/play" ("-q" "/sounds/open.ogg")))))))

(ert-deftest emacsvox-sounds-server-commands-quote-resource-paths ()
  "Every server cue command should preserve one hostile resource word."
  (let* ((resource
          "/tmp/cue space {brace} unmatched} quote\" back\\slash; dollar$ [command] λ\n.ogg")
         (emacsvox-play-program nil)
         (emacsvox-sounds-cache (make-hash-table))
         (tts-speaker-process 'speaker)
         commands)
    (puthash 'served resource emacsvox-sounds-cache)
    (cl-letf
        (((symbol-function 'process-send-string)
          (lambda (_process command) (push command commands))))
      (emacsvox-queue-resource resource)
      (emacsvox-sounds-play-concrete-cue resource "sample")
      (emacsvox-serve-icon 'served))
    (setq commands (nreverse commands))
    (should (= (length commands) 3))
    (let ((expected
           (mapconcat
            (lambda (byte) (format "%02x" byte))
            (encode-coding-string resource 'utf-8-unix)
            "")))
      (with-temp-buffer
        (insert
         "set values {}\n"
         "proc a {value} {lappend ::values $value}\n"
         "proc p {value} {lappend ::values $value}\n"
         (apply #'concat commands)
         (concat
          "foreach value $values {puts [binary encode hex "
          "[encoding convertto utf-8 $value]]}\n"))
        (should
         (zerop
          (call-process-region
           (point-min) (point-max) "tclsh" t t nil)))
        (should
         (equal
          (split-string (string-trim (buffer-string)) "\n")
          (make-list 3 expected)))))))

(ert-deftest emacsvox-sounds-server-playback-does-not-reevaluate-paths ()
  "Server-side playback should launch decoded paths directly and asynchronously."
  (let* ((resource "/tmp/cue;set ::injected 1;#")
         (emacsvox-play-program nil)
         (tts-speaker-process 'speaker)
         command)
    (cl-letf
        (((symbol-function 'process-send-string)
          (lambda (_process value) (setq command value))))
      (emacsvox-sounds-play-concrete-cue resource "sample"))
    (with-temp-buffer
      (insert
       (format
        "catch {source %s} source_error\n"
        (emacsvox-sounds--tcl-word
         (expand-file-name "servers/tts-lib.tcl" emacsvox-directory)))
       "rename exec emacsvox_test_exec\n"
       "proc exec args {set ::exec_arguments $args; return {}}\n"
       "proc speech_task {} {}\n"
       "array set tts {play player debug 0}\n"
       "set ::injected 0\n"
       command
       "puts $::injected\n"
       (concat
        "puts [binary encode hex [encoding convertto utf-8 "
        "[lindex $::exec_arguments 1]]]\n")
       "puts [lindex $::exec_arguments 0]\n"
       "puts [lindex $::exec_arguments end]\n")
      (should
       (zerop
        (call-process-region
         (point-min) (point-max) "tclsh" t t nil)))
      (let ((lines (split-string (string-trim (buffer-string)) "\n")))
        (should (equal (car lines) "0"))
        (should
         (equal
          (cadr lines)
          (mapconcat
           (lambda (byte) (format "%02x" byte))
           (encode-coding-string resource 'utf-8-unix)
           "")))
        (should (equal (nth 2 lines) "player"))
        (should (equal (nth 3 lines) "&")))))
  (dolist (relative '("servers/outloud" "servers/dtk-soft"
                      "servers/dtk-exp" "servers/espeak"))
    (with-temp-buffer
      (insert-file-contents (expand-file-name relative emacsvox-directory))
      (should (re-search-forward "tts_start_cue \\$sound" nil t))
      (goto-char (point-min))
      (should-not
       (re-search-forward
        "exec[ \t]+\\$tts(play).*\\$sound" nil t)))))

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
      "/packs/chimes/item.ogg\"\n"
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
