;;; emacsvox.el --- The Complete Audio Desktop  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox: A speech interface to Emacs
;; Keywords: Emacsvox, Speech, Dectalk,
;; Version: 55.0
;; Package-Requires: ((emacs "31") (hydra "0.5"))
;;;   LCD Archive entry:
;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4642 $ |
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

;; Emacsvox extends Emacs to be a fully functional audio desktop.
;; This is the main emacsvox module.
;; It actually does very little:
;; @itemize
;; @item  It sets up Emacs to load package-specific
;; Emacsvox modules as and when a  package is loaded.
;; @item  It implements function emacsvox which loads the rest of the
;; system.
;; @item It provides affordances for  setting up consistent behavior in
;; programming modes.
;; @end itemize
;;; Code:

;;  Required modules: 

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-simple-editor)
(require 'emacsvox-aural-sound-packs)
(require 'emacsvox-aural-provider-org)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-provider-markdown)
(require 'emacsvox-aural-provider-notmuch)

;;;   Customize groups

(defgroup emacsvox nil
  "Emacsvox: The Complete Audio Desktop."
  :link '(url-link :tag "Source"
                   "https://github.com/robertmeta/emacsvox"
                   :help-echo "Emacsvox on GitHub")
  :group 'applications)

;;;  Package Setup Helper

;; This function adds the appropriate form to `after-load-alist' to
;; set up Emacsvox support for a given package.  Argument MODULE (a
;; symbol)specifies the emacsvox module that implements the
;; speech-enabling extensions for `package' (a string).
(defsubst emacsvox-package-setup (pair)
  "Setup Emacsvox extension for   PACKAGE by loading MODULE."
  (with-eval-after-load (cl-first pair) (require (cl-second pair))))

;; DocView
(declare-function doc-view-open-text "doc-view")

(with-eval-after-load "doc-view"
  (add-hook 'doc-view-mode-hook #'doc-view-open-text))

;; gptel speech-enabling moved to emacsvox-gptel.el

;;;  Setup package extensions
(defvar emacsvox-packages-to-prepare
  '(
    ("2048-game" emacsvox-2048)
    ("abc-mode" emacsvox-abc-mode)
    ("ace-window" emacsvox-ace-window)
    ("add-log" emacsvox-add-log)
    ("agent-shell" emacsvox-agent-shell)
    ("annotate" emacsvox-annotate)
    ("arc-mode" emacsvox-arc)
    ("avy" emacsvox-avy)
    ("bbdb" emacsvox-bbdb)
    ("bibtex" emacsvox-bibtex)
    ("bookmark" emacsvox-bookmark)
    ("browse-kill-ring" emacsvox-browse-kill-ring)
    ("bs" emacsvox-bs)
    ("buff-menu" emacsvox-buff-menu)
    ("calc" emacsvox-calc)
    ("calculator" emacsvox-calculator)
    ("calendar" emacsvox-calendar)
    ("calibredb" emacsvox-calibredb)
    ("cc-mode" emacsvox-c)
    ("chess" emacsvox-chess)
    ("cider" emacsvox-cider)
    ("clojure" emacsvox-clojure)
    ("cmuscheme" emacsvox-cmuscheme)
    ("combobulate" emacsvox-combobulate)
    ("comint"  emacsvox-comint)
    ("company" emacsvox-company)
    ("compile" emacsvox-compile)
    ("consult" emacsvox-consult)
    ("corfu" emacsvox-corfu)
    ("cperl-mode" emacsvox-cperl)
    ("cus-edit" emacsvox-custom)
    ("deadgrep" emacsvox-deadgrep)
    ("denote" emacsvox-denote)
    ("debugger" emacsvox-debugger)
    ("desktop" emacsvox-desktop)
    ("devdocs" emacsvox-devdocs)
    ("dictionary" emacsvox-dictionary)
    ("diff-mode" emacsvox-diff-mode)
    ("dired" emacsvox-dired)
    ("doctor" emacsvox-entertain)
    ("dumb-jump" emacsvox-dumb-jump)
    ("dunnet" emacsvox-entertain)
    ("eat" emacsvox-eat)
    ("ebuku" emacsvox-ebuku)
    ("embark" emacsvox-embark)
    ("ediff" emacsvox-ediff)
    ("eglot" emacsvox-eglot)
    ("ein" emacsvox-ein)
    ("ein-notebook" emacsvox-ein)
    ("elfeed" emacsvox-elfeed)
    ("elisp-refs" emacsvox-elisp-refs)
    ("ellama" emacsvox-ellama)
    ("elpher" emacsvox-elpher)
    ("elpy" emacsvox-elpy)
    ("embark" emacsvox-embark)
    ("emms" emacsvox-emms)
    ("empv" emacsvox-empv)
    ("enriched" emacsvox-enriched)
    ("enwc" emacsvox-enwc)
    ("epa" emacsvox-epa)
    ("erc" emacsvox-erc)
    ("eshell" emacsvox-eshell)
    ("ess" emacsvox-ess)
    ("eudc" emacsvox-eudc)
    ("evil" emacsvox-evil)
    ("eww" emacsvox-eww)
    ("exwm" emacsvox-exwm)
    ("ffap" emacsvox-ffap)
    ("find-file-in-project" emacsvox-ffip)
    ("flycheck" emacsvox-flycheck)
    ("flymake" emacsvox-flymake)
    ("flyspell" emacsvox-flyspell)
    ("folding" emacsvox-folding)
    ("forge" emacsvox-forge)
    ("forms" emacsvox-forms)
    ("gdb-ui" emacsvox-gud)
    ("geiser" emacsvox-geiser)
    ("github-explorer" emacsvox-github-explorer)
    ("gnuplot" emacsvox-gnuplot)
    ("gnus" emacsvox-gnus)
    ("go-mode" emacsvox-go-mode)
    ("gomoku" emacsvox-gomoku)
    ("gptel" emacsvox-gptel)
    ("gud" emacsvox-gud)
    ("hangman" emacsvox-entertain)
    ("haskell-mode" emacsvox-haskell)
    ("helm" emacsvox-helm)
    ("helpful" emacsvox-helpful)
    ("hide-lines" emacsvox-hide-lines)
    ("hideshow" emacsvox-hideshow)
    ("hydra" emacsvox-hydra)
    ("ibuffer" emacsvox-ibuffer)
    ("ido" emacsvox-ido)
    ("iedit" emacsvox-iedit)
    ("info" emacsvox-info)
    ("ispell" emacsvox-ispell)
    ("ivy" emacsvox-ivy)
    ("journalctl-mode" emacsvox-journalctl)
    ("js2-mode" emacsvox-js2)
    ("kmacro" emacsvox-kmacro)
    ("lispy" emacsvox-lispy)
    ("lua-mode" emacsvox-lua)
    ("magit" emacsvox-magit)
    ("make-mode" emacsvox-make-mode)
    ("man" emacsvox-man)
    ("marginalia" emacsvox-marginalia)
    ("markdown-mode" emacsvox-markdown)
    ("message" emacsvox-message)
    ("mines" emacsvox-mines)
    ("mpuz" emacsvox-entertain)
    ("muse-mode" emacsvox-muse)
    ("mu4e" emacsvox-mu4e)
    ("multiple-cursors" emacsvox-multiple-cursors)
    ("net-utils" emacsvox-net-utils)
    ("newsticker" emacsvox-newsticker)
    ("notmuch" emacsvox-notmuch)
    ("nov" emacsvox-nov)
    ("nxml-mode" emacsvox-nxml)
    ("org" emacsvox-org)
    ("orgalist" emacsvox-orgalist)
    ("outline" emacsvox-outline)
    ("package"emacsvox-package)
    ("paradox"emacsvox-paradox)
    ("perl-mode" emacsvox-perl)
    ("pipewire" emacsvox-pipewire)
    ("popup" emacsvox-popup)
    ("proced" emacsvox-proced)
    ("project" emacsvox-project)
    ("projectile" emacsvox-projectile)
    ("pydoc" emacsvox-pydoc)
    ("python" emacsvox-python)
    ("python-mode" emacsvox-py)
    ("racket-mode" emacsvox-racket)
    ("re-builder" emacsvox-re-builder)
    ("reftex" emacsvox-reftex)
    ("related" emacsvox-related)
    ("rg" emacsvox-rg)
    ("rmail" emacsvox-rmail)
    ("rpm-spec-mode" emacsvox-rpm-spec)
    ("rst" emacsvox-rst)
    ("ruby-mode" emacsvox-ruby)
    ("rust-mode" emacsvox-rust-mode)
    ("sage-shell-mode" emacsvox-sage)
    ("sdcv" emacsvox-sdcv)
    ("ses" emacsvox-ses)
    ("sgml-mode" emacsvox-sgml-mode)
    ("sh-script" emacsvox-sh-script)
    ("slime" emacsvox-slime)
    ("smartparens" emacsvox-smartparens)
    ("solitaire" emacsvox-solitaire)
    ("speedbar" emacsvox-speedbar)
    ("sql" emacsvox-sql)
    ("sudoku" emacsvox-sudoku)
    ("supercite" emacsvox-supercite)
    ("syslog" emacsvox-syslog)
    ("tab-bar" emacsvox-tab-bar)
    ("table" emacsvox-etable)
    ("tabulated-list" emacsvox-tabulated-list)
    ("tar-mode" emacsvox-tar)
    ("tcl" emacsvox-tcl)
    ("tempo" emacsvox-tempo)
    ("term" emacsvox-eterm)
    ("tetris" emacsvox-tetris)
    ("tex-site" emacsvox-auctex)
    ("texinfo" emacsvox-texinfo)
    ("threes" emacsvox-threes)
    ("todo-mode" emacsvox-todo-mode)
    ("transient" emacsvox-transient)
    ("treesit" emacsvox-treesit)
    ("typo" emacsvox-typo)
    ("vdiff" emacsvox-vdiff)
    ("vertico" emacsvox-vertico)
    ("view" emacsvox-view)
    ("vterm" emacsvox-vterm)
    ("wdired" emacsvox-wdired)
    ("which-key" emacsvox-which-key)
    ("wid-edit" emacsvox-widget)
    ("widget" emacsvox-widget)
    ("windmove" emacsvox-windmove)
    ("woman" emacsvox-woman)
    ("xkcd" emacsvox-xkcd)
    ("xref" emacsvox-xref)
    ("yaml-mode" emacsvox-yaml)
    ("yasnippet" emacsvox-yasnippet)
    )
  "Packages to  speech-enable.")
(defun emacsvox-prepare-emacs ()
  "Prepare Emacs to speech-enable packages when loaded."
  (unless (boundp 'Info-file-list-for-emacs) (require 'info))
  (push "emacsvox" Info-file-list-for-emacs)
  (setq-default line-move-visual nil)
  (setq use-dialog-box nil)
  (mapc #'emacsvox-package-setup emacsvox-packages-to-prepare)
  (message "emacsvox-prepare-emacs: done"))

;;;  setup programming modes

;; turn on automatic voice locking , split caps and punctuations in
;; programming  modes

;;;###autoload
(defsubst emacsvox-setup-programming-mode ()
  "Setup programming mode."
  
  (tts-set-punctuations 'all)
  (or tts-split-caps (tts-toggle-split-caps))
  (or tts-caps (tts-toggle-caps))
  (emacsvox-pronounce-refresh-pronunciations)
  (or emacsvox-audio-indentation (emacsvox-toggle-audio-indentation)))

(defun emacsvox-setup-programming-modes ()
  "Setup programming modes."
  (add-hook 'prog-mode-hook #'emacsvox-setup-programming-mode)
  (with-eval-after-load "generic-x"
    
    (mapc
     #'(lambda (hook)
         (add-hook hook #'emacsvox-setup-programming-mode ))
     generic-extras-enable-list))
  (mapc
   #'(lambda (hook)
       (add-hook hook #'emacsvox-setup-programming-mode))
   '(
     conf-unix-mode-hook html-helper-mode-hook
     markdown-mode-hook muse-mode-hook
     sgml-mode-hook xml-mode-hook nxml-mode-hook xsl-mode-hook
     TeX-mode-hook LaTeX-mode-hook bibtex-mode-hook)))

;;;  Emacsvox:

(defvar emacsvox-play-startup-icon t
  "If set to T, emacsvox plays its icon as it launches.
This cannot be set via custom; set this in your startup file before
  you load anything else.")

(defsubst emacsvox-easter-egg ()
  "Easter Egg"
  
  (let ((f (expand-file-name "ai/01-gemini.ogg" emacsvox-etc-directory)))
    (when
        (and
         emacsvox-play-startup-icon sox-play
         (file-exists-p f)
         (string= (format-time-string "%m-%d") (format-time-string "04-25")))
      (run-at-time 3 nil #'(lambda () (start-process "ogg" nil sox-play f))))))

(defvar emacsvox-startup
  (eval-when-compile
    (format
     "  Press %s to get an   overview of emacsvox  %s. \
 I am  completely operational,  and all my circuits are functioning perfectly!"
     (substitute-command-keys
      "\\[emacsvox-describe-emacsvox]")
     emacsvox-version))
  "Emacsvox startup message.")

(defcustom emacsvox-pip-enable
  (executable-find "piper")
  "Load pip if Piper-TTS is available."
  :type 'boolean
  :set
  #'(lambda (sym val)
      (set-default sym val )
      (when val (require 'pip)))
  :group 'emacsvox)

(defun emacsvox()
  "Start the Emacsvox Audio Desktop.
Use Emacs as you normally would, emacsvox provides spoken feedback.
Emacsvox also provides commands for having parts of the current buffer,
the mode-line etc to be spoken.

Commands invoked with prefix \\`C-e' provide the primary Emacsvox interface.

\\{emacsvox-keymap}

Commands invoked with prefix \\`C-e d' control text-to-speech.

\\{emacsvox-tts-submap}

Emacsvox provides a set of additional keymaps to give easy access to
Emacs' extensive facilities.  All of these bindings can be customized
via custom.

Press C-; to access keybindings in `emacsvox-hyper-keymap':
\\{emacsvox-hyper-keymap}

Press C-.  to access keybindings in `emacsvox-super-keymap':
\\{emacsvox-super-keymap}

Press C-, to access keybindings in `emacsvox-alt-keymap':
\\{emacsvox-alt-keymap}

Press C-' to access keybindings in `emacsvox-multi-keymap':
\\{emacsvox-multi-keymap}

Press C-v to access keybindings in `emacsvox-v-keymap':
\\{emacsvox-v-keymap}

Press C-x to access keybindings in `emacsvox-x-keymap':
\\{emacsvox-x-keymap}

Press C-y to access keybindings in `emacsvox-y-keymap':
\\{emacsvox-y-keymap}

Press C-z to access keybindings in `emacsvox-z-keymap':
\\{emacsvox-z-keymap}

See the online documentation \\[emacsvox-open-info] for individual
commands and options."
  (setenv "EMACSVOX_DIR" emacsvox-directory)
  (add-hook                           ; silence messages when quitting
   'kill-emacs-hook
   #'(lambda nil (setq-default emacsvox-speak-messages nil))
   -10)
  (tts-initialize)
  (emacsvox-aural-load-user-data)
  (emacsvox-aural-validate-scheme-registry)
  (emacsvox-sounds-select-theme
   (or
    (emacsvox-aural-effective-scheme-provider 'resource-pack)
    'chimes))
  (emacsvox-pronounce-load-dictionaries)
  (make-thread #'(lambda nil  (ems--fastload "emacsvox-advice")))
  (ems--fastload "emacsvox-websearch")
  (emacsvox-setup-programming-modes)
  (make-thread #'emacsvox-prepare-emacs)
  (setq line-number-mode nil column-number-mode nil)
  (global-visual-line-mode -1)
  (transient-mark-mode -1)
  (unless (fboundp 'Info-initialize)
    (require 'info)
    (info-initialize))
  (cl-pushnew emacsvox-info-directory Info-directory-list)
  (when emacsvox-wpctl
    (add-to-list
     'minor-mode-alist
     '(emacsvox-speak-show-volume (:eval
                                   (ems--show-current-volume)))))
  (message emacsvox-startup)
  (when   emacsvox-play-startup-icon
    (emacsvox-icon 'emacsvox)
    (emacsvox-easter-egg)))

(provide 'emacsvox)

;;;  end of file

;;; emacsvox.el ends here
