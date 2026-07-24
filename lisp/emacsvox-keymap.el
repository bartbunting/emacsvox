;;; emacsvox-keymap.el --- Setup   keybindings -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Module for setting up emacsvox keybindings
;; Keywords: Emacsvox
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4544 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;;
;; This file is not part of GNU Emacs, but the same permissions apply.
;;
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This module defines the emacsvox keybindings.
;; Note that the <fn> key found on laptops is denoted <XF86WakeUp>

;;; Code:

;;;  requires

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'subr-x))

;;;  Custom Widget Types:

(defun emacsvox-keymap-command-p (s)
  "Test if `s' can to be bound to a key."
  (or (commandp s) (keymapp s)))

(defsubst emacsvox-keymap-update (keymap binding)
  "Update keymap with  binding."
  (define-key keymap  (kbd (cl-first binding)) (cl-second binding)))

(defsubst emacsvox-keymap-bindings-update (keymap bindings)
  "Update keymap with  list of bindings."
  (cl-loop
   for binding in bindings
   do
   (define-key keymap (kbd (cl-first binding)) (cl-second binding))))

(define-widget 'ems-interactive-command 'restricted-sexp
  "An interactive command  or keymap that can be bound to a key."
  :completions
  (apply-partially #'completion-table-with-predicate
                   obarray 'emacsvox-keymap-command-p 'strict)
  :prompt-value 'widget-field-prompt-value
  :prompt-internal 'widget-symbol-prompt-internal
  :prompt-match 'emacsvox-keymap-command-p
  :prompt-history 'widget-function-prompt-value-history
  :action 'widget-field-action
  :match-alternatives '(emacsvox-keymap-command-p)
  :validate (lambda (widget)
              (unless (emacsvox-keymap-command-p (widget-value widget))
                (widget-put widget :error
                            (format "Invalid interactive command : %S"
                                    (widget-value widget)))
                widget))
  :value 'ignore
  :tag "Interactive Command")

;;;   variables:

(defvar emacsvox-prefix (kbd "C-e")
  "Emacsvox Prefix key. ")

(defvar emacsvox-keymap nil
  "Primary emacsvox keymap. ")

(defvar emacsvox-tts-submap nil
  "Submap used for TTS commands. ")

(defvar emacsvox-table-submap nil
  "Submap used for table  commands. ")

;;;    Binding keymap and submap

(define-prefix-command  'emacsvox-keymap)
(define-prefix-command   'emacsvox-tts-submap)
(define-prefix-command  'emacsvox-table-submap-command
                        'emacsvox-table-submap)

(global-set-key emacsvox-prefix 'emacsvox-keymap)

;;; Special keys:
(global-set-key (kbd "<XF86WakeUp>")  'emacsvox-speak-brief-time)
(global-set-key (kbd "<XF86AudioPlay>")  'emacsvox-silence)
(global-set-key (kbd "C-<f1>")  'amixer-volume-down)
(global-set-key (kbd "C-<f2>")  'amixer-volume-up)
(global-set-key (kbd "<XF86AudioLowerVolume>")  'amixer-volume-down)
(global-set-key (kbd "<XF86AudioRaiseVolume>") 'amixer-volume-up)

(define-key emacsvox-keymap "d"  'emacsvox-tts-submap)
(define-key emacsvox-keymap (kbd "C-t")  'emacsvox-table-submap-command)

;;;   The Emacsvox key  bindings.

;; help map additions:

(cl-loop
 for binding in
 '(
   ("'" describe-text-properties)
   ("," emacsvox-wizards-color-at-point)
   ("/" describe-face)
   (":" describe-help-keys)
   (";" describe-font)
   ("=" emacsvox-wizards-swap-fg-and-bg)
   ("B" customize-browse)
   ("C-<tab>" emacs-index-search)
   ("C-e"   emacsvox-describe-emacsvox)
   ("C-j" finder-commentary)
   ("C-k" describe-keymap)
   ("C-l" emacsvox-learn-emacs)
   ("C-m" man)
   ("C-r" info-display-manual)
   ("C-s" emacsvox-wizards-customize-saved)
   ("C-v" emacsvox-wizards-describe-voice)
   ("G" customize-group)
   ("M" emacsvox-speak-popup-messages)
   ("M-F" find-function-at-point)
   ("M-V" find-variable-at-point)
   ("M-f" find-function)
   ("M-k" find-function-on-key)
   ("M-m" describe-minor-mode-from-indicator)
   ("M-v" find-variable)
   ("N" emacsvox-view-notifications)
   ("SPC" customize-group)
   ("TAB" emacsvox-info-wizard)
   ("V" customize-variable)
   ("\"" emacsvox-wizards-list-voices)
   ("\\" emacsvox-wizards-color-diff-at-point)
   ("p" list-packages))
 do
 (emacsvox-keymap-update help-map binding))

;; emacsvox-keymap bindings:
(cl-loop
 for binding in
 '(
   ("!" emacsvox-speak-run-shell-command)
   ("#" emacsvox-gridtext)
   ("$" flyspell-mode)
   ("%" emacsvox-speak-current-percentage)
   ("&" emacsvox-wizards-shell-command-on-current-file)
   ("'" emacsvox-empv-play-file)
   ("(" amixer)
   (")" emacsvox-sounds-select-theme)
   ("," emacsvox-buffer-select)
   ("." emacsvox-buffer-select)
   ("/" emacsvox-websearch)
   ("1" emacsvox-speak-this-window)
   ("2" emacsvox-speak-other-window)
   ("3" amixer-volume-adjust)
   ("4" amixer-volume-adjust)
   (";" emacsvox-multimedia)
   ("<XF86WakeUp>" emacsvox-speak-brief-time)
   ("<delete>" emacsvox-speak-message-again)
   ("<backspace>" emacsvox-speak-message-again)
   ("<down>" emacsvox-read-next-line)
   ("<f11>" emacsvox-wizards-shell-toggle)
   ("<f1>" emacsvox-learn-emacs)
   ("<left>" emacsvox-speak-this-buffer-previous-display)
   ("<next>" end-of-buffer)
   ("<prior>" beginning-of-buffer)
   ("<right>" emacsvox-speak-this-buffer-next-display)
   ("<up>"  emacsvox-read-previous-line)
   ("=" emacsvox-speak-current-column)
   ("?" emacsvox-websearch)
   ("@" emacsvox-speak-message-at-time)
   ("A" emacsvox-appt-repeat-announcement)
   ("B" emacsvox-speak-buffer-interactively)
   ("C" emacsvox-customize)
   ("C-'" emacsvox-pianobar)
   ("C-." emacsvox-speak-face-browse)
   ("C-/" emacsvox-speak-this-buffer-other-window-display)
   ("C-<left>" emacsvox-select-this-buffer-previous-display)
   ("C-<return>" emacsvox-speak-continuously)
   ("C-<right>" emacsvox-select-this-buffer-next-display)
   ("C-@" emacsvox-speak-current-mark)
   ("C-M-c" emacsvox-clipfile-copy)
   ("C-M-q" emacsvox-toggle-speak-messages)
   ("C-M-y" emacsvox-clipfile-paste)
   ("C-SPC" emacsvox-speak-current-mark)
   ("C-a" emacsvox-toggle-icons)
   ("C-b" emacsvox-bookshare)
   ("C-c" emacsvox-selective-display)
   ("C-d" emacsvox-toggle-show-point)
   ("C-e" move-end-of-line)
   ("C-f" emacsvox-find-dired)
   ("C-i" emacsvox-open-info)
   ("C-j" emacsvox-hide-speak-block-sans-prefix)
   ("C-k" browse-kill-ring)
   ("C-l" what-line)
   ("C-m"  emacsvox-websearch-google)
   ("C-o" emacsvox-ocr)
   ("C-q" emacsvox-toggle-inaudible-or-comint-autospeak)
   ("C-r" restart-emacs)
   ("C-s" tts-restart)
   ("C-u" emacsvox-feeds-browse)
   ("C-v" view-mode)
   ("C-w" emacsvox-speak-window-information)
   ("C-x" emacsvox-speak-header-line)
   ("L" emacsvox-speak-line-interactively)
   ("M" emacsvox-speak-minor-mode-line)
   ("M-%" emacsvox-goto-percent)
   ("M-;" emacsvox-eww-play-media-at-point)
   ("M-C-SPC" emacsvox-speak-spaces-at-point)
   ("M-SPC" emacsvox-speak-completions-if-available)
   ("M-a" emacsvox-speak-message-again)
   ("M-b" emacsvox-speak-other-buffer)
   ("M-c" emacsvox-copy-current-file)
   ("M-d" emacsvox-pronounce-dispatch)
   ("M-e" emacsvox-epub)
   ("M-h" emacsvox-speak-hostname)
   ("M-l" emacsvox-speak-overlay-properties)
   ("M-m" emacsvox-toggle-mail-alert)
   ("M-o" emacsvox-toggle-comint-output-monitor)
   ("M-p" emacsvox-show-property-at-point)
   ("M-r" emacsvox-speak-extent)
   ("M-s" emacsvox-symlink-current-file)
   ("M-t" emacsvox-describe-tapestry)
   ("M-u" emacsvox-feeds-add-feed)
   ("M-v" emacsvox-show-style-at-point)
   ("M-w" emacsvox-speak-which-function)
   ("N" emacsvox-view-emacsvox-news)
   ("P" emacsvox-speak-paragraph-interactively)
   ("R" emacsvox-speak-rectangle)
   ("SPC" emacsvox-speak-windowful)
   ("T" emacsvox-view-emacsvox-tips)
   ("V" emacsvox-speak-version)
   ("W" emacsvox-select-window-by-name)
   ("[" emacsvox-speak-paragraph)
   ("\\" emacsvox-toggle-speak-line-invert-filter)
   ("]" emacsvox-speak-page)
   ("^" emacsvox-filtertext)
   ("`"  emacsvox-speak-net-id)
   ("a" emacsvox-speak-message-again)
   ("b" emacsvox-speak-buffer)
   ("c" emacsvox-speak-char)
   ("e" move-end-of-line)
   ("f" emacsvox-speak-buffer-filename)
   ("g" keyboard-quit)
   ("h" emacsvox-speak-help)
   ("i" emacsvox-speak-rest-of-buffer)
   ("j" emacsvox-hide-or-expose-block)
   ("k" emacsvox-speak-current-kill)
   ("l" emacsvox-speak-line)
   ("m" emacsvox-speak-mode-line)
   ("n" emacsvox-buffer-select)
   ("o" delete-blank-lines)
   ("p" emacsvox-buffer-select)
   ("r" emacsvox-speak-region)
   ("s" tts-stop)
   ("t" emacsvox-speak-time)
   ("u" emacsvox-url-template-fetch)
   ("w" emacsvox-speak-word)
   ("|" emacsvox-speak-line-set-column-filter)
   )
 do
 (emacsvox-keymap-update emacsvox-keymap binding))

(cl-loop
 for binding in
 '(
   ("=" tts-rate-adjust)
   ("+" tts-rate-adjust)
   ("-" tts-rate-adjust)
   ("," tts-toggle-punctuation-mode)
   ("." tts-notify-stop)
   ("C-c" tts-cloud)
   ("C-d" dectalk)
   ("C-e" espeak)
   ("C-s" dectalk-soft)
   ("C-j" tts-set-chunk-separator-syntax)
   ("C-n" tts-notify-initialize)
   ("C-o" outloud)
   ("C-v" global-voice-lock-mode)
   ("d" tts-select-server)
   ("L" tts-local-server)
   ("N" tts-set-next-language)
   ("P" tts-set-previous-language)
   ("R" tts-reset-state)
   ("S" tts-set-language)
   ("SPC" tts-toggle-splitting-on-white-space)
   ("V" tts-speak-version)
   ("a" tts-add-cleanup-pattern)
   ("c" tts-toggle-caps)
   ("f" tts-set-character-scale)
   ("i" emacsvox-toggle-audio-indentation)
   ("k" emacsvox-toggle-character-echo)
   ("l" emacsvox-toggle-line-echo)
   ("n" tts-toggle-speak-nonprinting-chars)
   ("o" tts-toggle-strip-octals)
   ("p" tts-set-punctuations)
   ("q" tts-toggle-quiet)
   ("r" tts-set-rate)
   ("s" tts-toggle-split-caps)
   ("v" voice-lock-mode)
   ("w" emacsvox-toggle-word-echo)
   ("z" emacsvox-zap-tts)
   )
 do
 (emacsvox-keymap-update emacsvox-tts-submap binding))

(dotimes (i 10)
  (define-key emacsvox-tts-submap
              (format "%s" i)   'tts-set-predefined-rate))

(cl-loop
 for binding in
 '(
   ("f" emacsvox-table-find-file)
   ("," emacsvox-table-find-csv-file)
   )
 do
 (emacsvox-keymap-update emacsvox-table-submap binding))

;; Put these in the global map:
(global-set-key [(shift left)] 'emacsvox-skip-space-backward)
(global-set-key [(shift right)] 'emacsvox-skip-space-forwar)
(global-set-key [(shift up)] 'emacsvox-skip-blank-lines-backward)
(global-set-key [(shift down)] 'emacsvox-skip-blank-lines-forward)
(global-set-key [27 up]  'emacsvox-owindow-previous-line)
(global-set-key  [27 down]  'emacsvox-owindow-next-line)
(global-set-key  [27 prior]  'emacsvox-owindow-scroll-down)
(global-set-key  [27 next]  'emacsvox-owindow-scroll-up)
(define-key esc-map "\M-:" 'emacsvox-wizards-show-eval-result)

;;;  emacsvox under X windows

;; Get hyper, alt, super, and multi:
(global-set-key (kbd "C-,") 'emacsvox-alt-keymap)
(global-set-key  (kbd "C-.") 'emacsvox-super-keymap)
(global-set-key  (kbd "C-;") 'emacsvox-hyper-keymap)
(global-set-key  (kbd "C-'") 'emacsvox-multi-keymap)

;; Our very own silence key on the console
(global-set-key '[silence] 'emacsvox-silence)

;;;  Create personal c-e v map

(defvar  emacsvox-v-keymap nil
  "Emacsvox v keymap")

(define-prefix-command 'emacsvox-v-keymap)

(defcustom emacsvox-v-keys
  '(
    ("SPC" emacsvox-speak-spaces)
    ("a" emacsvox-xslt-view-atom-file)
    ("b" ebuku)
    ("o" emacsvox-feeds-opml-display)
    ("r" emacsvox-xslt-view-rss-file)
    ("v" view-register)
    ("x" emacsvox-xslt-view-file)
    )
  "Key bindings for use with C-e v. "
  :group 'emacsvox
  :type
  '(repeat
    :tag "Emacsvox V Keymap"
    (list
     :tag "Key Binding"
     (key-sequence :tag "Key")
     (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (emacsvox-keymap-bindings-update emacsvox-v-keymap val)
      (set-default sym
                   (sort
                    val
                    #'(lambda (a b) (string-lessp (car a) (car b)))))))

;;;  Create a personal keymap for c-e x

;; Adding keys using custom:
(defvar  emacsvox-x-keymap nil
  "Emacsvox personal keymap")

(define-prefix-command 'emacsvox-x-keymap)

(defcustom emacsvox-x-keys
  '(
    ("," emacsvox-wizards-shell-directory-set)
    ("." emacsvox-wizards-shell-directory-reset)
    ("0" emacsvox-wizards-shell-by-key)
    ("1" emacsvox-wizards-shell-by-key)
    ("2" emacsvox-wizards-shell-by-key)
    ("3" emacsvox-wizards-shell-by-key)
    ("4" emacsvox-wizards-shell-by-key )
    ("5" emacsvox-wizards-shell-by-key)
                                        ;("6" emacsvox-speak-message-at-time)
    ("7" emacsvox-wizards-shell-command-on-current-file)
    ("8" calc)
    ("=" emacsvox-wizards-find-longest-line-in-region)
    ("[" emacsvox-wizards-find-longest-paragraph-in-region)
    ("]" emacsvox-wizards-find-longest-sentence-in-region)
    ("M-c" emacsvox-wizards-colors)
    (":" emacsvox-m-player-loop)
    (";" emacsvox-m-player-shuffle)
    ("b" battery)
    ("C-c" emacsvox-wizards-color-wheel)
    ("d" emacsvox-speak-load-directory-settings)
    ("e" emacsvox-we-xsl-map)
    ("f" emacsvox-wizards-remote-frame)
    ("h" emacsvox-wizards-how-many-matches)
    ("i" ibuffer)
    ("k" emacsvox-desktop-preserve)
    ("l" load-library)
    ("m" mspools-show)
    ("o" emacsvox-wizards-occur-header-lines)
    ("p" paradox-list-packages)
    ("t" emacsvox-speak-telephone-directory)
    ("u" emacsvox-wizards-units)
    ("v" emacsvox-wizards-vc-viewer)
    ("w" emacsvox-wizards-noaa-weather)
    ("x" exchange-point-and-mark)
    ("|" emacsvox-wizards-squeeze-blanks)
    ("" desktop-clear)
    )
  "Key bindings for  C-e x. "
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox x Keymap"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (emacsvox-keymap-bindings-update emacsvox-x-keymap val)
      (set-default
       sym
       (sort
        val
        #'(lambda (a b) (string-lessp (car a) (car b)))))))

(define-key emacsvox-keymap "v" 'emacsvox-v-keymap)
(define-key  emacsvox-keymap "x" 'emacsvox-x-keymap)
(define-key  emacsvox-keymap "y" 'emacsvox-y-keymap)

;;;  Create personal y map

(defvar  emacsvox-y-keymap nil
  "Emacsvox y keymap")

(define-prefix-command 'emacsvox-y-keymap)

(defcustom emacsvox-y-keys
  '(
    ("b" emacsvox-bookshare-eww)
    ("d" empv-download-youtube)
    ("e" emacsvox-epub-eww)
    ("l" emacsvox-empv-play-last)
    ("p" empv-youtube-playlist)
    ("s" emacsvox-empv-yt-search)
    ("t" empv-youtube-tabulated)
    ("y" emacsvox-empv-play-url)
    )
  "Key bindings for use with C-e y. "
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox Personal-Y Keymap"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (emacsvox-keymap-bindings-update emacsvox-y-keymap val)
      (set-default sym
                   (sort
                    val
                    #'(lambda (a b) (string-lessp (car a) (car b)))))))

;;;  Create a C-z keymap that is customizable

;; 2020: Suspending emacs with C-z is something I've not done in 30
;; years.
;; Turn it into a useful prefix key.

(defvar  emacsvox-z-keymap nil
  "Emacsvox ctl-z keymap")

(define-prefix-command 'emacsvox-z-keymap)
(global-set-key (kbd "C-z") 'emacsvox-z-keymap)
(defcustom emacsvox-ctl-z-keys
  '(
    ("SPC" flyspell-mode)
    ("b" emacsvox-wizards-view-buffers-filtered-by-this-mode)
    ("c" calibredb)
    ("d" magit-dispatch)
    ("e" emacsvox-wizards-eww-buffer-list)
    ("f" magit-file-dispatch)
    ("l" emacsvox-m-player-locate-media)
    ("n" emacsvox-wizards-buffer-select)
    ("p" emacsvox-wizards-buffer-select)
    ("r" restart-emacs)
    ("s" magit-status)
    ("z" suspend-frame)
    )
  "CTL-z keymap."
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox C-Z  Keys"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (emacsvox-keymap-bindings-update emacsvox-z-keymap val)
      (set-default sym
                   (sort
                    val
                    #'(lambda (a b) (string-lessp (car a) (car b)))))))

(define-key emacsvox-keymap  "z" 'emacsvox-z-keymap)

;;;  Create a hyper keymap that users can put personal commands

(defvar  emacsvox-hyper-keymap nil
  "Emacsvox hyper keymap")

(define-prefix-command 'emacsvox-hyper-keymap)

(defcustom emacsvox-hyper-keys
  '(
    ("C-;" emacsvox-amark-bookshelf)
    ("C-a" ansi-term)
    ("C-b" eww-list-bookmarks)
    ("C-d" dictionary-search)
    ("C-e" eshell)
    ("C-j" journalctl)
    ("C-l" emacsvox-librivox)
    ("C-t" emacsvox-wizards-tramp-open-location)
    ("DEL" emacsvox-wizards-snarf-sexp)
    ("TAB" hippie-expand)
    ("a" emacsvox-amark-browse)
    ("c" browse-url-chrome)
    ("d" magit-dispatch)
    ("f" magit-file-dispatch)
    ("g" gnus)
    ("h" emacsvox-m-player-from-history)
    ("i" ibuffer)
    ("j" emacsvox-zoxide)
    ("l" locate)
    ("m" vm)
    ("o" find-file)
    ("r" emacsvox-wizards-find-file-as-root)
    ("s" magit-status)
    ("u" list-unicode-display)
    ("w" emacsvox-wizards-noaa-weather)
    ("y" yas-expand)
    )
  "Hyper-Key bindings. "
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox Hyper Keys"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (emacsvox-keymap-bindings-update emacsvox-hyper-keymap val)
      (set-default sym
                   (sort
                    val
                    #'(lambda (a b) (string-lessp (car a) (car b)))))))
(global-set-key "\C-x@h" 'emacsvox-hyper-keymap)

;;;  Create a super keymap that users can put personal commands

(defvar  emacsvox-super-keymap nil
  "Emacsvox super keymap")

(define-prefix-command 'emacsvox-super-keymap)

(defcustom emacsvox-super-keys
  '(
    ("SPC"  scratch-buffer)
    ("." emacsvox-wizards-shell-directory-reset)
    ("R" emacsvox-webspace-feed-reader)
    ("b" eww-list-buffers)
    ("c" calculator)
    ("d" emacsvox-dired-downloads)
    ("e" elfeed)
    ("f" browse-url-firefox)
    ("g" emacsvox-google-tts)
    ("h" emacsvox-org-capture-link)
    ("l" emacsvox-wizards-locate-content)
    ("m" emacsvox-wizards-view-buffers-filtered-by-this-mode)
    ("n" emacsvox-wizards-google-news)
    ("p" proced)
    ("r" soundscape-restart)
    ("s" soundscape)
    ("t" soundscape-toggle)
    ("u" soundscape-update-mood))
  "Super key bindings. "
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox Super Keymap"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (emacsvox-keymap-bindings-update emacsvox-super-keymap  val)
      (set-default sym
                   (sort
                    val
                    #'(lambda (a b) (string-lessp (car a) (car b)))))))

(global-set-key "\C-x@s" 'emacsvox-super-keymap)

;;;  Create an  alt keymap that users can put personal commands

(defvar  emacsvox-alt-keymap nil "Emacsvox alt keymap")

(define-prefix-command 'emacsvox-alt-keymap)

(defcustom emacsvox-alt-keys
  '(
    ("," eldoc)
    ("a" emacsvox-feeds-atom-display)
    ("b" sox-binaural)
    ("c" gptel)
    ("d" deadgrep)
    ("e" eww)
    ("f" ffip)
    ("g" rg)
    ("C-l" ellama-chat)
    ("l" eww-open-file)
    ("p" emacsvox-wizards-pdf-open)
    ("r" emacsvox-feeds-rss-display)
    ("s" emacsvox-wizards-tune-in-radio-search)
    ("t" emacsvox-wizards-tune-in-radio-browse)
    ("u" emacsvox-m-player-url)
    ("v" visual-line-mode)
    ("w" define-word)
    ("SPC" emacsvox-eww-smart-tabs)
    )
  "Alt key bindings. "
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox Alt Keymap"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set #'(lambda (sym val)
           (emacsvox-keymap-bindings-update emacsvox-alt-keymap val)
           (set-default sym
                        (sort
                         val
                         #'(lambda (a b) (string-lessp (car a) (car b)))))))

(global-set-key "\C-x@a" 'emacsvox-alt-keymap)

;;;  Create a multi keymap that users can put personal commands

(defvar  emacsvox-multi-keymap nil "Emacsvox multi keymap")

(define-prefix-command 'emacsvox-multi-keymap)

(defcustom emacsvox-multi-keys
  '(
    ("'" emacsvox-pianobar)
    ("d" sdcv-search-input)
    ("f" ffap)
    ("l" emacsvox-m-player-locate-media)
    ("o" org-mode)
    ("m" notmuch-search)
    ("p" emacsvox-wizards-portfolio)
    ("y" emacsvox-google-yt-feed))
  "Multi key bindings. "
  :group 'emacsvox
  :type '(repeat
          :tag "Emacsvox Multi Keymap"
          (list
           :tag "Key Binding"
           (key-sequence :tag "Key")
           (ems-interactive-command :tag "Command")))
  :set #'(lambda (sym val)
           (emacsvox-keymap-bindings-update emacsvox-multi-keymap val)
           (set-default sym
                        (sort
                         val
                         #'(lambda (a b) (string-lessp (car a) (car b)))))))

;;; Windows Key As One More Map
(defcustom emacsvox-windows-keys nil
  "Key bindings on the windows  key. "
  :group 'emacsvox
  :type
  '(repeat
    :tag "Emacsvox windows Keys"
    (list
     :tag "Key Binding"
     (character :tag "Key")
     (ems-interactive-command :tag "Command")))
  :set
  #'(lambda (sym val)
      (when val
        (cl-loop
         for binding in val do
         (global-set-key
          (vector
           (event-apply-modifier (cl-first binding) 'super 23 "s-"))
          (cl-second binding))))
      (set-default
       sym
       (sort
        val
        #'(lambda (a b) (< (car a) (car b)))))))

;;;  Helper: recover end-of-line

(defun emacsvox-keymap-recover-eol ()
  "Recover EOL ."
  
  (global-set-key (concat emacsvox-prefix "e") 'move-end-of-line)
  (global-set-key (concat emacsvox-prefix emacsvox-prefix) 'move-end-of-line))
(add-hook 'after-change-major-mode-hook  'emacsvox-keymap-recover-eol)

;;;  Global Bindings From Other Modules:
(global-set-key (kbd "C-x r C-e") 'emacsvox-eww-marks-browse)
(global-set-key (kbd "C-x r e") 'emacsvox-eww-open-mark)

(provide 'emacsvox-keymap)
