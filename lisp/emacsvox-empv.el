;;; emacsvox-empv.el --- Speech-enable EMPV  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $s-mo
;; Description:  Speech-enable EMPV An Emacs Interface to empv
;; Keywords: Emacsvox,  Audio Desktop empv
;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;; Location https://github.com/tvraman/emacsvox

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
;; @code{EMPV}  ==  Emacs Front-End To @code{mpv}  --- the GNU media player ---
;; Provides better Youtube integration.
;; 
;; This section documents Emacsvox extensions to @code{EMPV} , the Emacs
;; interface of choice to the GNU @code{MPV}  media player.
;; This section should be read alongside the @code{EMPV}  documentation; Install
;; @code{EMPV}  from ELPA.
;; 
;; @subsection Interactive Commands
;; 
;; Emacsvox adds a few convenience commands to the those provided by
;; package @code{empv}:
;; 
;; @enumerate
;; @item
;; Command  @code{emacsvox-empv-play-url to play} 
;; a URL using @code{MPV} .
;; @item
;; Adds history tracking to our @code{EMPV}  commands.
;; @item
;; Command empv-play-last-url to play from our @code{EMPV}  history.
;; @item
;; Command  @code{emacsvox-empv-play-file  to play  local media and} 
;; Internet streams.
;; @end enumerate
;; 
;; @subsection Navigating In Time 
;; 
;; Emacsvox defines additional convenience commands to seek in  streams
;; at different time granularities, the names are self-documenting and
;; bound  in the empv-map.
;; 
;; @itemize
;; @item
;;  @code{emacsvox-empv-absolute-seek}  
;; @item
;;  @code{emacsvox-empv-backward-10-minutes} 
;; @item
;;  @code{emacsvox-empv-backward-10-seconds}  
;; @item
;;  @code{emacsvox-empv-backward-30-minutes} 
;; @item
;;  @code{emacsvox-empv-backward-5-minutes} 
;; @item
;;  @code{emacsvox-empv-backward-minute}  
;; @item
;;  @code{emacsvox-empv-forward-10-minutes} 
;; @item
;;  @code{emacsvox-empv-forward-10-seconds}  
;; @item
;;  @code{emacsvox-empv-forward-30-minutes} 
;; @item
;;  @code{emacsvox-empv-forward-5-minutes} 
;; @item
;;  @code{emacsvox-empv-forward-minute}  
;; @item
;;  @code{emacsvox-empv-percentage-seek}  
;; @item
;;  @code{emacsvox-empv-relative-seek}  
;; @end itemize
;; 
;; @subsection Toggling Filters
;; 
;; Command @code{mpv}  provides a number of audio filters. Emacsvox exposes a
;; select few for interactive use.
;; 
;; @enumerate
;; @item
;; Toggle active filter:  @code{emacsvox-empv-toggle-filter}  
;; @item
;; Toggle Audio Balance:  @code{emacsvox-empv-toggle-balance}  
;; @item
;; Clear any active filters:  @code{emacsvox-empv-clear-filter}  
;; @item
;; Toggle our custom filter:  @code{emacsvox-empv-toggle-custom}  
;; @item
;; Toggle left output:  @code{emacsvox-empv-toggle-left}  
;; @item
;; Toggle right output:  @code{emacsvox-empv-toggle-right}  
;; @end enumerate
;; 
;; 

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'gweb)
(require 'empv nil t)
(require 'iimage nil t)
(declare-function emacsvox-google-canonicalize-result-url
                  "emacsvox-google" (url))
(declare-function emacsvox-google-result-url-prefix "emacsvox-google" nil)

;;; Interactive Commands:

(cl-loop
 for f in
 '(
   aempv-current-loop-off empv-current-loop-on empv-lyrics-current
   empv-toggle empv-pause
   empv-file-loop-off empv-file-loop-on
   empv-playlist-loop-off empv-playlist-loop-on) do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-stop 'all)
       (emacsvox-icon 'button)))))

(defun ems--empv-lyrics-display-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'empv-lyrics-display-mode :after
            #'ems--empv-lyrics-display-mode-after)

(defun ems--empv-youtube-results-play-current-before (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'button)))

(advice-add 'empv-youtube-results-play-current :before
            #'ems--empv-youtube-results-play-current-before)

(defun ems--empv-youtube-results-inspect-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'empv-youtube-results-inspect :after
            #'ems--empv-youtube-results-inspect-after)

(defun ems--empv-youtube-tabulated-before (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'button)))

(advice-add 'empv-youtube-tabulated :before
            #'ems--empv-youtube-tabulated-before)

(defun ems--empv-exit-after (&rest _)
  "Icon." (repeat-exit)
  (when (ems-interactive-p)
    (dtk-stop 'all) (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(advice-add 'empv-exit :after #'ems--empv-exit-after)

;;; Additional Commands:

(defvar emacsvox-empv-history nil
  "Youtube history for EMpv.")

(defvar emacsvox-empv-history-max 128
  "Max number of history to preserve.")

;;;###autoload
(defun emacsvox-empv-play-url (url)
  "Play URL using mpv. "
  (interactive (list (ems--read-url 'emacsvox-empv-history)))
  (cl-declare (special emacsvox-empv-history-max
                       emacsvox-empv-history))
  (when
      (and url (stringp url)
           (string-prefix-p (emacsvox-google-result-url-prefix) url))
    (setq url  (emacsvox-google-canonicalize-result-url url)))
  (add-to-history 'emacsvox-empv-history url emacsvox-empv-history-max)
  (empv-play url))

(defun ems--empv-play-before (&rest _)
  "Record history."
  (cl-declare
   (special emacsvox-empv-history-max emacsvox-empv-history))
  (let ((url (ad-get-arg 0)))
    (when
        (and url (stringp url)
             (string-prefix-p (emacsvox-google-result-url-prefix) url))
      (setq url (emacsvox-google-canonicalize-result-url url)))
    (add-to-history 'emacsvox-empv-history url
                    emacsvox-empv-history-max)))

(advice-add 'empv-play :before #'ems--empv-play-before)

(defun emacsvox-empv-play-last ()
  "Play most recently played URL."
  (interactive )
  
  (emacsvox-empv-play-url (cl-first emacsvox-empv-history)))

(declare-function emacsvox-media-local-resource "emacsvox-empv" t)
(declare-function emacsvox-media-read-resource
                  "emacsvox-m-player" (&optional prefix))

;;;###autoload
(defun emacsvox-empv-play-file (file &optional _prefix)
  "Play file using mpv.
Interactive prefix arg plays directory.
If already playing, then read an empv key and invoke its command."
  (interactive
   (list
    (unless (and empv--process (process-live-p empv--process))
      (emacsvox-media-read-resource current-prefix-arg))
    current-prefix-arg))
  
  (cond
   ((null file)                         ; we're already playing
    (call-interactively
     (lookup-key  empv-map  (read-key-sequence "EMpv Key:"))))
   (t (dtk-notify (file-name-base file))
      (empv-play file))))

(defun emacsvox-empv-yt-search (query)
  "Tabulated results from Youtube search but with completion."
  (interactive (list (gweb-youtube-autocomplete)))
  (funcall-interactively #'empv-youtube-tabulated query))

(defun emacsvox-empv-accumulate-to-register ()
  "Accumulate media links to register u"
  (interactive)
  (emacsvox-accumulate-to-register ?u
                                   'empv-youtube-results--current-video-url))
(declare-function emacsvox-eww-yt-dl "emacsvox-eww" (url))

;;; Lyrics:
;; Let's use our Google searcher:
(declare-function emacsvox-websearch-google-lite "emacsvox-empv" t)
(with-no-warnings
  (defadvice empv--lyrics-on-not-found (around emacsvox pre act comp)
    "Override to use our own implementation."
    (setq ad-return-value nil)
    (funcall #'emacsvox-websearch-google-lite (ad-get-arg 0))))

;;; Seekers:
(defun emacsvox-empv-time-pos ()
  "Speak time and percent position."
  (interactive)
  (empv--let-properties '(time-pos percent-pos)
                        (message "%s.  %.2d%%"
                                 (ems--format-clock (or .time-pos 0))
                                 (or .percent-pos 0))))

(defsubst emacsvox-empv-post-nav ()
  "Post nav action"
  (when (called-interactively-p 'interactive)
    (call-interactively 'emacsvox-empv-time-pos)
    (emacsvox-icon 'tick-tick)))

(defun emacsvox-empv-relative-seek (target)
  "Relative seek in seconds,see `empv-seek'"
  (interactive (list (read-number "Target:" 30 )))
  (empv-seek target)
  (emacsvox-empv-post-nav))

(defun emacsvox-empv-absolute-seek (target)
  "Absolute seek in seconds,see `empv-seek'"
  (interactive "nTarget:")
  (empv-seek target '("absolute"))
  (emacsvox-empv-post-nav))

(defun emacsvox-empv-backward-10-seconds ()
  "Move back  10 seconds."
  (interactive )
  (empv-seek -10))

(defun emacsvox-empv-forward-10-seconds ()
  "Move forward 10 seconds."
  (interactive)
  (empv-seek 10))

;; Generate other navigators:

(defun emacsvox-empv-backward-minute (&optional count)
  "Move back  count  minutes."
  (interactive "p")
  (or count (setq count 1))
  (empv-seek (* count -60))
  (emacsvox-empv-post-nav))

(defun emacsvox-empv-forward-minute (&optional count)
  "Move forward count  minutes."
  (interactive "p")
  (or count (setq count 1))
  (empv-seek (* count 60))
  (emacsvox-empv-post-nav))

;; Generate other navigators:

(defun ems--empv-gen-nav (duration)
  "Generate time navigator."
  (eval
   `(defun ,(intern  (format "emacsvox-empv-forward-%s-minutes" duration)) ()
      ,(format "Move forward by %s minutes" duration )
      (interactive )
      (funcall-interactively 'emacsvox-empv-forward-minute ,duration)))
  (eval
   `(defun ,(intern  (format "emacsvox-empv-backward-%s-minutes" duration)) ()
      ,(format "Move backward by %s minutes" duration )
      (interactive )
      (funcall-interactively 'emacsvox-empv-backward-minute ,duration))))

;; Use it:
(mapc #'ems--empv-gen-nav '(5 10 30))

(defun emacsvox-empv-percentage-seek (target)
  "Percentage seek in seconds,see `empv-seek'"
  (interactive "nTarget:")
  (empv-seek target '("absolute-percent"))
  (when (called-interactively-p 'interactive)
    (call-interactively 'emacsvox-empv-time-pos)
    (emacsvox-icon 'button)))

;;; Setup:
;; empv-youtube-tabulated-new-entries-hook
(add-hook
 'empv-youtube-results-mode-hook
 #'(lambda nil
     (emacsvox-icon 'open-object)
     (emacsvox-pronounce-refresh-pronunciations)))

(add-hook
 'empv-youtube-tabulated-new-entries-hook
 #'(lambda (e &rest _) (message (alist-get 'title (cl-first e)))))
(defun emacsvox-empv-current-title ()
  "Speak title of currently selected item."
  (interactive)
  (emacsvox-icon 'select-object)
  (message (cdr (assq 'title (empv-youtube-results--current-item)))))

(defun ems--empv-youtube-results-copy-current-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object)
    (message (current-kill 0 'dont-move))))

(advice-add 'empv-youtube-results-copy-current :after
            #'ems--empv-youtube-results-copy-current-after)

(defun ems--empv--youtube-tabulated-entries-append-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll)
    (dtk-notify
     (format "%s: %s results"
             (cdr
              (assoc 'title
                     (cl-first
                      (empv--yt-search-results
                       empv--last-youtube-search))))
             (length
              (empv--yt-search-results empv--last-youtube-search))))))

(advice-add 'empv--youtube-tabulated-entries-append :after
            #'ems--empv--youtube-tabulated-entries-append-after)

(defun emacsvox-empv-setup ()
  "Emacsvox setup for empv."
  (cl-declare (special empv-map
                       empv-youtube-results-mode-map))
  (define-key empv-youtube-results-mode-map
              (kbd "t") 'emacsvox-empv-current-title)
  (define-key empv-youtube-results-mode-map
              (kbd "C-v") 'empv-youtube-results-load-more)
  (define-key empv-youtube-results-mode-map
              "o" 'empv-youtube-results-play-current)
  (cl-loop
   for b in
   '(
     ("%" emacsvox-empv-percentage-seek)
     ("'" empv-current-loop-on)
     ("," emacsvox-empv-toggle-left)
     ("." emacsvox-empv-toggle-right)
     ("\\" emacsvox-empv-toggle-custom)
     ("<" emacsvox-empv-backward-10-seconds)
     (">" emacsvox-empv-forward-10-seconds)
     ("0" empv-volume-up)
     ("9" empv-volume-down)
     (";" emacsvox-empv-toggle-filter)
     ("<down>" emacsvox-empv-forward-10-minutes)
     ("<left>" emacsvox-empv-backward-5-minutes)
     ("<next>" emacsvox-empv-forward-30-minutes)
     ("<prior>" emacsvox-empv-backward-30-minutes)
     ("<right>" emacsvox-empv-forward-5-minutes)
     ("<up>" emacsvox-empv-backward-10-minutes)
     ("=" emacsvox-empv-time-pos)
     ("DEL" emacsvox-empv-clear-filter)
     ("M" emacsvox-empv-backward-minute)
     ("SPC" empv-toggle)
     ("b" emacsvox-empv-toggle-balance)
     ("k" empv-exit)
     ("l" empv-lyrics-current)
     ("m" emacsvox-empv-forward-minute)
     ("r" emacsvox-empv-relative-seek)
     ("s" emacsvox-empv-absolute-seek)
     ("v" empv-set-volume))
   do
   (emacsvox-keymap-update empv-map b)))

(emacsvox-empv-setup)

;; Repeat:
(mapc
 #'(lambda (c) (put c 'repeat-map 'empv-map))
 '(
   empv-youtube-results-play-current
   empv-set-volume empv-display-current  empv-toggle
   emacsvox-empv-play-last emacsvox-empv-play-url
   emacsvox-empv-play-file emacsvox-empv-play-local
   emacsvox-empv-backward-10-seconds emacsvox-empv-forward-10-seconds
   emacsvox-empv-forward-minute emacsvox-empv-backward-minute
   emacsvox-empv-forward-5-minutes emacsvox-empv-backward-5-minutes
   emacsvox-empv-forward-10-minutes emacsvox-empv-backward-10-minutes
   emacsvox-empv-forward-15-minutes emacsvox-empv-backward-15-minutes
   emacsvox-empv-forward-30-minutes emacsvox-empv-backward-30-minutes
   emacsvox-empv-time-pos emacsvox-empv-clear-filter
   emacsvox-empv-toggle-custom emacsvox-empv-toggle-filter
   emacsvox-empv-toggle-left emacsvox-empv-toggle-right
   emacsvox-empv-absolute-seek  emacsvox-empv-percentage-seek
   emacsvox-empv-relative-seek))

(defvar emacsvox-empv-filter-history nil
  "History of filters used.")
(defconst emacsvox-empv-filters
  '(
    "asubboost" "bs2b" "bs2b=cmoy" "bs2b=jmeier"
    "extrastereo" "extrastereo=1.5" "haas" "headphone"
    "stereowiden=4.25:.1:735:.8"
    "stereotools=mutel=true"
    "stereotools=muter=true"
    "surround=7.1" "virtualbass"
    )
  "Table of MPV filters.")

;;;  Toggling Filters
(defun emacsvox-empv-toggle-filter (filter)
  "Toggle Filter.
Filter is of the  form name=arg-1:arg-2:..."
  (interactive
   (list
    (completing-read   "Filter:"
                       emacsvox-empv-filters nil nil nil
                       'emacsvox-empv-filter-history)))
  
  (cl-pushnew filter emacsvox-empv-filter-history :test #'string=)
  (empv--send-command (list "af" "toggle" filter)))

(defun emacsvox-empv-toggle-balance (value)
  "Set balance to value --- range is -1.0..1.0 "
  (interactive (list (read-minibuffer "Balance: ")))
  (funcall-interactively #'emacsvox-empv-toggle-filter
                         (format "stereotools=balance_out=%f" value)))

(defun emacsvox-empv-clear-filter ()
  "Clear all filters. "
  (interactive)
  (empv--send-command (list "af" "clr" "" ))
  (message "Cleared filters")
  (emacsvox-icon 'delete-object))

(defcustom emacsvox-empv-custom-filters
  '("extrastereo" "stereowiden=4.25:.1:735:.8" "haas")
  "List of custom filters to turn on/off at one shot
The default value is suitable for classical instrumental music."
  :type '(repeat  :tag "Filters" (string :tag "Filter"))
  :group 'emacsvox-empv)

(defun emacsvox-empv-toggle-custom ()
  "Toggle our custom filters."
  (interactive)
  
  (when emacsvox-empv-custom-filters
    (mapc
     #'(lambda (filter) (empv--send-command (list "af" "toggle" filter)))
     emacsvox-empv-custom-filters)
    (emacsvox-icon 'button)
    (message "Toggled custom filters")))

(defun emacsvox-empv-toggle-left ()
  "Toggle output to being just on the left."
  (interactive)
  (empv--send-command (list "af" "toggle" "stereotools=muter=true"))
  (emacsvox-icon 'button)
  (message "Toggled output left"))

(defun emacsvox-empv-toggle-right ()
  "Toggle output to being just on the right."
  (interactive)
  (empv--send-command (list "af" "toggle" "stereotools=mutel=true"))
  (emacsvox-icon 'button)
  (message "Toggled output right"))
;;; YT Date Search:

(declare-function calendar-cursor-to-date "calendar" (&optional error event))

;;;###autoload
(defun emacsvox-empv-yt-after ()
  "Youtube Search  from calendar --- add after:date-at-point.."
  (interactive)
  (cl-assert (eq major-mode 'calendar-mode) t "Not in calendar.")
  (let ((date
         (format " after:%d/%02d/%02d"
                 (cl-third (calendar-cursor-to-date))
                 (cl-first (calendar-cursor-to-date))
                 (cl-second (calendar-cursor-to-date)))))
    (funcall-interactively
     'empv-youtube-tabulated
     (concat (read-from-minibuffer "YT Search After") date))))

(defun emacsvox-empv-yt-before ()
  "Youtube Search  from calendar --- add before:date-at-point.."
  (interactive)
  (cl-assert (eq major-mode 'calendar-mode) t "Not in calendar.")
  (let ((date
         (format " before:%d/%02d/%02d"
                 (cl-third (calendar-cursor-to-date))
                 (cl-first (calendar-cursor-to-date))
                 (cl-second (calendar-cursor-to-date)))))
    (funcall-interactively
     'empv-youtube-tabulated
     (concat (read-from-minibuffer "YT Search Before") date))))

(provide 'emacsvox-empv)
;;;  end of file

                                        ;
                                        ;
                                        ;
