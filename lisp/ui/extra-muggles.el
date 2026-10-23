;;; extra-muggles.el --- Additional Hydras -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop muggles
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; MUGGLES ==  Emacsvox spells for power-users.
;; These are extra hydras that I dont use very often,
;; And are being moved here from emacsvox-muggles to save time at
;; startup.
;; 
;; This module implements no new functionality --- contrast with
;; emacsvox-wizards.  Instead, it uses package hydra to provide
;; convenience key-bindings that access existing Emacsvox
;; functionality.
;; You need to install package Hydra first:
;; @samp{M-x package-install  hydra}.

;; Note that on newer versions of Emacs, loading this module will
;; attempt to automatically install package hydra if it is not found.
;; @subsection Using Hydras
;; See the high-level documentation for the Hydra package by executing
;; @kbd {C-h C-j } hydra @kbd{RET}.
;; The documentation in this section uses the same terminology as
;; shown in the hydra package documentation.

;; @subsection Extra Muggles

;; @itemize
;; @item  org-mode structure nav: @kbd{C-c C-SPC}  Navigation  for org-mode.
;; @item View-Mode: @kbd{C-. v} Temporarily behave like view-mode.
;; @item SmartParens: @kbd{C-c ,} Smart Parens
;; @item m-player: @kbd{s-m} Emacsvox-M-Player Commands
;; @item m-player: @kbd{s-;} Emacsvox-M-Player muggle
;; @item pianobar: @kbd{s-'} Emacsvox-M-pianobar Commands
;; @item origami: C-, / Origami   bindings.
;; @item outliner: <C-c .> Bindings from outline-minor-mode.
;; @item Info-Summary: <?> in Info Info Summary Muggle
;; @item Vuiet Explorer: @kbd{C-; v} Vuiet Music Explorer and Player
;; @end itemize

;; Emacsvox automatically speaks Hydra hints when displayed.
;; To silence all Hydra hints, set hydra-is-helpful to nil.  To
;; temporarily silence speaking of Hydra hints, Muggles can bind
;; command @code{emacsvox-hydra-toggle-talkative}.  As an
;; example, Muggle @samp{ViewMode} binds @code{s} to this command.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-dired)
(require 'hydra)
(require 'emacsvox-hydra)
(require 'org)
(require 'emacsvox-outline)
(require 'emacsvox-m-player)
(require 'view)
(require 'smartparens "smartparens" 'no-error)
(eval-when-compile
  (setq byte-compile-warnings '(not docstrings))
  (require 'emacsvox-hydra)
  
  (require 'vuiet nil 'no-error)
  (require 'hydra "hydra" 'no-error))
(require 'eww)
(with-no-warnings (require 'origami "origami" 'no-error))

;;;  Generate Muggles From Keymaps:

;; Generate A Muggle: Take a name of a keymap (symbol) And generate an
;; interactive command that can be bound to a key.  Invoking that
;; command temporarily activates the previously supplied keymap.  That
;; activated keymap remains active until the user presses a key that
;; is not bound in that keymap.  Inspired by the Hydra package.

(defun emacsvox-muggles-generate (k-map)
  "Generate a Muggle from specified k-map.
Argument `k-map' is a symbol  that names a keymap."
  (unless (and (symbolp k-map) (boundp k-map) (keymapp (symbol-value k-map)))
    (error "%s is not a keymap." k-map))
  (let ((cmd-name (intern (format "emacsvox-muggles-%s-cmd" k-map)))
        (doc-string (format "Temporarily use keymap %s" k-map)))
    (eval
     `(defun ,cmd-name ()
        ,doc-string
        (interactive)
        (let* ((key (read-key-sequence "Key: "))
               (cmd (lookup-key ,k-map key)))
          (while (commandp cmd)
            (call-interactively cmd)
            (setq key (read-key-sequence "Key: ")
                  cmd (lookup-key ,k-map key)))
          (call-interactively (lookup-key (current-global-map) key))
          (emacsvox-icon 'close-object))))))

;; Create a command to invoke our media player map:

(global-set-key
 (kbd "s-m")
 (emacsvox-muggles-generate 'emacsvox-m-player-mode-map))

;; Create one for pianobar
(when (featurep 'pianobar)
  (global-set-key
   (kbd "s-'")
   (emacsvox-muggles-generate 'pianobar-key-map)))

;;;  Media Player:

(declare-function emacsvox-amark-save "emacsvox-muggles" t)
(global-set-key
 (kbd "s-;")
 (defhydra emacsvox-muggles-m-player
           (:body-pre (emacsvox-hydra-body-pre "Media Player")
                      :pre emacsvox-hydra-pre :post emacsvox-hydra-post)
           (";" emacsvox-m-player)
           ("+" emacsvox-m-player-volume-up)
           ("," emacsvox-m-player-backward-10s)
           ("%" emacsvox-m-player-display-percent)
           ("-" emacsvox-m-player-volume-down)
           ("." emacsvox-m-player-forward-10s)
           ("<" emacsvox-m-player-backward-1min)
           ("<down>" emacsvox-m-player-forward-1min)
           ("<left>" emacsvox-m-player-backward-10s)
           ("<next>" emacsvox-m-player-forward-10min)
           ("<prior>" emacsvox-m-player-backward-10min)
           ("<right>" emacsvox-m-player-forward-10s)
           ("<up>" emacsvox-m-player-backward-1min)
           ("=" emacsvox-m-player-volume-up)
           (">" emacsvox-m-player-forward-1min)
           ("C" emacsvox-m-player-clear-filters)
           ("DEL" emacsvox-m-player-reset-speed)
           ("Q" emacsvox-m-player-quit "quit")
           ("R" emacsvox-m-player-edit-reverb)
           ("S" emacsvox-amark-save)
           ("SPC" emacsvox-m-player-pause)
           ("[" emacsvox-m-player-slower)
           ("]" emacsvox-m-player-faster)
           ("a" emacsvox-m-player-amark-add)
           ("b" emacsvox-m-player-balance)
           ("c" emacsvox-m-player-slave-command)
           ("d" emacsvox-m-player-delete-filter)
           ("e" emacsvox-m-player-add-equalizer)
           ("f" emacsvox-m-player-add-filter)
           ("g" emacsvox-m-player-seek-absolute)
           ("j" emacsvox-m-player-amark-jump)
           ("l" emacsvox-m-player-get-length)
           ("m" emacsvox-m-player-mode-line)
           ("n" emacsvox-m-player-next-track)
           ("p" emacsvox-m-player-previous-track)
           ("q" bury-buffer)
           ("r" emacsvox-m-player-seek-relative)
           ("s" emacsvox-m-player-scale-speed)
           ("u" emacsvox-m-player-url)
           ("v" emacsvox-m-player-volume-change)
           ("(" emacsvox-m-player-left-channel)
           (")" emacsvox-m-player-right-channel)
           ("{" emacsvox-m-player-half-speed)
           ("}" emacsvox-m-player-double-speed)
           ))

;;;  Outliner:
(require 'emacsvox-muggles-core)
(require 'emacsvox-muggle-outliner)
(emacsvox-muggles--legacy-enable 'outliner)

;;;  Info Summary:
(require 'emacsvox-muggle-info)
(emacsvox-muggles--legacy-enable 'info)

;;;  origami:

(declare-function origami-open-node "origami" (buffer point))
(declare-function origami-close-node "origami" (buffer point))
(declare-function origami-next-fold "origami" (buffer point))
(declare-function origami-previous-fold "origami" (buffer point))
(declare-function origami-forward-toggle-node "origami" (buffer point))
(declare-function origami-toggle-all-nodes "origami" (buffer))
(declare-function origami-mode "origami" (&optional arg))

(global-set-key
 (kbd "C-, /")
 (defhydra emacsvox-origami
           (:color red
                   :body-pre
                   (progn
                     (origami-mode 1)
                     (emacsvox-hydra-body-pre "Origami")
                     (emacsvox-hydra-toggle-talkative))
                   :hint nil
                   :pre emacsvox-hydra-pre :post emacsvox-hydra-post)
           "
    _o_pen node    _n_ext fold       toggle _f_orward
    _c_lose node   _p_revious fold   toggle _a_ll
    "
           ("o" origami-open-node)
           ("c" origami-close-node)
           ("n" origami-next-fold)
           ("p" origami-previous-fold)
           ("f" origami-forward-toggle-node)
           ("a" origami-toggle-all-nodes)))

;;;  Muggles Autoload Wizard:

(defvar emacsvox-muggles-pattern
  "emacsvox-muggles-.*/body$"
  "Pattern matching muggles we are interested in.")

(defun emacsvox-muggles-enumerate ()
  "Enumerate all interactive muggles."
  
  (let ((result nil))
    (mapatoms
     #'(lambda (s)
         (let ((name (symbol-name s)))
           (when
               (and
                (commandp s)
                (string-match emacsvox-muggles-pattern  name))
             (push s result)))))
    result))

(defun emacsvox-muggles-generate-autoloads ()
  "Generate autoload lines for all defined muggles.
Also generates global keybindings if any."
  (let ((muggles (emacsvox-muggles-enumerate))
        (buff
         (find-file-noselect
          (expand-file-name "emacsvox-muggles-autoloads.el"
                            emacsvox-lisp-directory))))
    (with-current-buffer buff
      (erase-buffer)
      (insert ";;; Auto Generated: Do Not Hand Edit.\n\n")
      (cl-loop
       for m in muggles do
       (let ((key  (where-is-internal m nil 'first)))
         (insert
          (format "(autoload '%s \"emacsvox-muggles\" \"%s\" t)\n" m m))
         (when key 
           (insert (format "(global-set-key %s '%s)\n" key m)))))
      (insert "\n(provide 'emacsvox-muggles-autoloads)\n")
      (save-buffer))
    (message "Generated autoloads for muggles.")))

;;;  Smartparens:
(require 'emacsvox-muggle-smartparens)
(emacsvox-muggles--legacy-enable 'smartparens)

;;;   View Mode:
(require 'emacsvox-muggle-view)
(emacsvox-muggles--legacy-enable 'view)

;;; Vuiet:

(declare-function emacsvox-vuiet-track-info "emacsvox-vuiet" nil)
(when (locate-library "vuiet")
  (with-no-warnings
    (global-set-key
     (kbd "C-; v")
     (defhydra emacsvox-muggles-vuiet
               (:body-pre
                (progn
                  (when hydra-is-helpful (emacsvox-hydra-toggle-talkative))
                  (emacsvox-hydra-body-pre "Vuiet  Explorer"))
                :pre emacsvox-hydra-pre :post emacsvox-hydra-post)
               (";" vuiet-playing-track-lyrics)
               ("=" vuiet-player-volume-inc)
               ("-" vuiet-player-volume-dec)
               ("A" vuiet-play-artist-loved-tracks)
               ("'" vuiet-play-loved-tracks)
               ("," vuiet-seek-backward)
               ("." vuiet-seek-forward)
               ("C-s" vuiet-artist-info-search)
               ("L" vuiet-playing-artist-lastfm-page)
               ("SPC" vuiet-play-pause)
               ("a" vuiet-artist-info)
               ("i" emacsvox-vuiet-track-info)
               ("l" vuiet-love-track)
               ("n" vuiet-next)
               ("p" vuiet-play-artist)
               ("r" vuiet-replay)
               ("s" vuiet-stop)
               ("t" vuiet-play-track)
               ("u" vuiet-unlove-track)))))

;;;  Org Mode Structure Navigation:

(require 'emacsvox-muggles-core)
(require 'emacsvox-muggle-org-navigation)
(emacsvox-muggles--legacy-enable 'org-navigation)

(provide 'extra-muggles)
;;;  end of file

;; byte-compile-warnings: (docstring noruntime )

;;; extra-muggles.el ends here
