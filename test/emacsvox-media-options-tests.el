;;; emacsvox-media-options-tests.el --- Media option binding tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Ensure compiled playback helpers dynamically extend MPlayer options.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-dired-tests)

(defvar emacsvox-m-player-options)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-amark.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  (load module nil nil))

(ert-deftest emacsvox-amark-play-passes-seek-option-to-player ()
  "Playing an AMark dynamically adds its seek position."
  (let* ((media-file (make-temp-file "emacsvox-amark-"))
         (amark
          (make-emacsvox-amark
           :path media-file :name "Test" :position 42))
         (emacsvox-m-player-options '("--base"))
         seen-options
         seen-resource)
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-m-player)
                   (lambda (resource &optional _play-list)
                     (setq seen-options
                           (copy-sequence emacsvox-m-player-options)
                           seen-resource resource)))
                  ((symbol-function 'message) #'ignore))
          (emacsvox-amark-play amark))
      (delete-file media-file))
    (should (equal seen-resource media-file))
    (should (equal seen-options '("--base" "-ss" 42)))))

(ert-deftest emacsvox-dired-playlist-passes-shuffle-option-to-player ()
  "A shuffled Locate playlist dynamically adds the shuffle option."
  (let ((playlist-buffer (generate-new-buffer " *emacsvox-playlist*"))
        (files '("/tmp/one.mp3" "/tmp/two.mp3" nil))
        (emacsvox-m-player-options '("--base"))
        seen-contents
        seen-options
        seen-play-list
        seen-presentation
        seen-resource)
    (unwind-protect
        (with-temp-buffer
          (setq major-mode 'locate-mode)
          (cl-letf (((symbol-function 'dired-next-line) #'ignore)
                    ((symbol-function 'dired-file-name-at-point)
                     (lambda () (pop files)))
                    ((symbol-function 'make-temp-file)
                     (lambda (&rest _) "/tmp/emacsvox-playlist.m3u"))
                    ((symbol-function 'find-file-noselect)
                     (lambda (&rest _) playlist-buffer))
                    ((symbol-function 'save-buffer) #'ignore)
                    ((symbol-function 'emacsvox-dired--submit-message)
                     (lambda (&rest arguments)
                       (setq seen-presentation arguments)))
                    ((symbol-function 'emacsvox-m-player)
                     (lambda (resource &optional play-list)
                       (setq seen-contents
                             (with-current-buffer playlist-buffer
                               (buffer-string))
                             seen-options
                             (copy-sequence emacsvox-m-player-options)
                             seen-play-list play-list
                             seen-resource resource))))
            (emacsvox-locate-play-results-as-playlist t)))
      (kill-buffer playlist-buffer))
    (should (equal seen-resource "/tmp/emacsvox-playlist.m3u"))
    (should (eq seen-play-list 'play-list))
    (should (equal seen-options '("--base" "-shuffle")))
    (should (equal seen-contents "/tmp/one.mp3\n/tmp/two.mp3\n"))
    (should
     (equal
      seen-presentation
      '("2 tracks matching"
        (:role filesystem-operation
         :filesystem-operation-kind playlist
         :events (operation-started))
        state-change progress)))))

(provide 'emacsvox-media-options-tests)
;;; emacsvox-media-options-tests.el ends here
