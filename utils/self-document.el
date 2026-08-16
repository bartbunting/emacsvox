;;; self-document.el --- Documentation Generator   -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Documentation Generator
;; Keywords: Emacsvox, Audio Desktop self-document
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;; $Date: 2007-05-03 18:13:44 -0700 (Thu, 03 May 2007) $ |
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;


;;;   Copyright:
;;Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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
;; MERCHANTABILITY or FITNSELF-DOCUMENT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston,MA 02110-1301, USA.


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;   introduction

;;; Commentary:

;; Generate documentation for Emacsvox commands and options.

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-use-icons)
(defvar sd-emacsvox-prefixes)
(defvar self-document-files)
(defvar self-document-keymap-list)
(defvar self-document-map)
(defvar self-document-patterns)
(defvar tts-program)
(defvar emacsvox-user-directory)

(defvar self-document-temporary-user-directory nil
  "Temporary Emacsvox data directory used while loading documented modules.")

;;;   Required modules

(require 'cl-lib)
(require 'cl-extra)
(require 'lisp-mnt)
(require 'subr-x)
(require 'regexp-opt)


;;;  Load All Modules

;; Setup load-path
(defconst self-document-lisp-directory
  (expand-file-name "../lisp" (file-name-directory load-file-name))
  "Emacsvox Lisp directory.")

(add-to-list 'load-path self-document-lisp-directory)

(load "emacsvox-preamble")
(load "plain-voices")
(load "voice-setup")
(load "emacsvox-loaddefs")

(defconst self-document-files
  (directory-files self-document-lisp-directory nil "\\.elc$")
  "List of elisp modules  to document.")

(defvar emacsvox-muggles-activate-p t)
(defvar self-document-fn-key
  "<XF86WakeUp>"
  "Notation for Laptop <fn> key.")

(defvar self-document-map
  (make-hash-table :test #'equal)
  "Maps modules to commands and options they define.")

(cl-defstruct self-document name commentary commands options)

(defun self-document-load-modules ()
  "Load all Emacsvox modules."
  (let* ((file-name-handler-alist nil)
         (load-source-file-function nil)
         (tts-program "log-null")
         (temporary-user-directory
          (file-name-as-directory
           (make-temp-file "emacsvox-self-document-" t)))
         (emacsvox-user-directory temporary-user-directory))
    (setq self-document-temporary-user-directory temporary-user-directory)
    (unwind-protect
        (progn
          (package-initialize)        ; bootstrap emacs package system
          ;; Silently bootstrap Emacsvox without reading personal data.
          (load-library "emacsvox-setup")
          (setq-default emacsvox-use-icons nil)
          ;; Load all Emacsvox modules:
          (cl-loop
           for f in self-document-files do
           (unless (string-match "emacsvox-setup" f) ; avoid loading setup twice
             (condition-case nil
                 (load-library f)
               (error (message "Warn: Did not load %s" f))))))
      (when (file-directory-p temporary-user-directory)
        (delete-directory temporary-user-directory t)))))

(defconst self-document-patterns
  (concat "^"
          (regexp-opt
           '("amixer"
             "dectalk" "espeak" "mac-"
             "emacsvox" "xbacklight-" "light-" "extra-muggles"
             "g-"    "gm-" "gmap"  "gweb" "omaps"
             "ladspa" "pip-"  "soundscape" "outloud" "sox-"   "tts-" "voice-")))
  "Patterns to match command names.")

(defvar self-document-command-count 0
  "Global count of commands.")

(defsubst self-document-command-p (f)
  "Predicate to check if  this command it to be documented."
  (when (and (fboundp f) (commandp f)
             (string-match self-document-patterns (symbol-name f)) ; candidate
             (if  (string-match  "/" (symbol-name f)) ; filter repeat muggles
                 (string-match "/body$" (symbol-name f))
               f))
    (cl-incf self-document-command-count)
    f))

(defvar self-document-option-count 0
  "Global count of options.")

(defsubst self-document-option-p (o)
  "Predicate to test if we document this option."
  (when (and
         (custom-variable-p o)
         (string-match self-document-patterns (symbol-name o)))
    (cl-incf self-document-option-count)
    o))

(defun self-document-map-command (f)
  "Add   this command symbol to our sym->file map."
  (let ((file  (symbol-file f 'defun))
        (entry nil))
    (unless file (setq file "emacsvox")) ; capture orphans if any
    (when file
      (setq file (file-name-sans-extension(file-name-nondirectory file )))
      (when (string-match "loaddefs" file) (setq file "emacsvox"))
      (setq entry  (gethash file self-document-map))
      (unless entry (message "Warn: %s: Entry not found for file %s" f file))
      (when entry (push f (self-document-commands  entry))))))

(defun self-document-map-option (f)
  "Add this option symbol to our map."
  (let ((file  (symbol-file f 'defvar))
        (entry nil))
    (unless file (setq file "emacsvox")); capture orphans if any
    (when (string-match "loaddefs" file) (setq file "emacsvox"))
    (when file
      (setq file (file-name-sans-extension(file-name-nondirectory file)))
      (setq entry  (gethash file self-document-map))
      (when entry (push f (self-document-options  entry))))))

(defun self-document-map-symbol (f)
  "Map command and options to its defining module."
  (when (self-document-command-p f) (self-document-map-command f))
  (when (self-document-option-p f) (self-document-map-option f)))

(defun sd-cleanup-commentary (commentary )
  "Cleanup commentary."
  (with-temp-buffer
    (insert commentary)
    (goto-char (point-min))
    (flush-lines "{{{")
    (goto-char (point-min))
    (flush-lines "}}}")
    (goto-char (point-min))
    (delete-blank-lines)
    (goto-char (point-min))
    (while (re-search-forward "^;+ ?" nil t)
      (replace-match "" nil nil))
    (buffer-string)))

(defun sd-get-commentary (name)
  "Get commentary for named module"
  (let* ((lib (locate-library name))
         (f (if (string-match ".el$" lib) lib (substring lib 0 -1)))
         (lmc (lm-commentary f)))
    (unless (zerop (call-process "grep" f nil nil ";;; Code:"))
      (message "Warn: %s missing Code: tag" f))
    (if lmc
        (setq lmc (sd-cleanup-commentary lmc)))))

;; initialize table
(defun self-document-build-map()
  "Build a map of module names to commands and options."
  (let ((file-name-handler-alist nil))
    (cl-loop
     for f in self-document-files do
     (let ((module (file-name-sans-extension f)))
       (puthash module
                (make-self-document :name module
                                    :commentary (sd-get-commentary module))
                self-document-map)))
    (mapatoms #'self-document-map-symbol )))


;;;  Document Commands In A Module

(defun sd-texinfo-escape (string)
  "Escape texinfo special chars"
  (when string
    (with-temp-buffer
      (insert string)
      (goto-char (point-min))
      (while (re-search-forward "[{}@]" nil t)
        (replace-match "@\\&"))
      (buffer-string))))

(defun self-document-module-preamble (self)
  "Generate preamble for module documentation."
  (let ((name (self-document-name self))
        (file-name-handler-alist nil)
        (lmc (self-document-commentary self)))
    (insert (format "\n@node %s\n@section %s\n\n\n" name name))
    (insert (format "\n\n%s\n\n"
                    (or lmc
                        (format "### %s: No Commentary\n" name))))))

(defun self-document--portable-default-value (value)
  "Render VALUE without embedding this build machine's absolute paths."
  (let* ((root
          (file-name-as-directory
           (expand-file-name ".." self-document-lisp-directory)))
         (user-home (file-name-as-directory (expand-file-name "~/")))
         (rendered
          (with-temp-buffer
            (cl-prettyprint value)
            (buffer-substring-no-properties (point-min) (point-max)))))
    (when self-document-temporary-user-directory
      (setq rendered
            (replace-regexp-in-string
             (regexp-quote self-document-temporary-user-directory)
             "~/.emacsvox/" rendered t t)))
    (setq rendered
          (replace-regexp-in-string
           "~/\\.emacsvox//+" "~/.emacsvox/" rendered t t))
    (setq rendered
          (replace-regexp-in-string
           (regexp-quote root) "<emacsvox-root>/" rendered t t))
    (replace-regexp-in-string
     (regexp-quote user-home) "~/" rendered t t)))

(defun self-document-option (o)
  "Document this option."
  (let ((doc (sd-texinfo-escape
              (documentation-property  o 'variable-documentation)))
        (value (symbol-value  o)))
    (insert (format "\n\n@defvar {User Option} %s\n" o))
    (insert (format "@verbatim\n%s\n@end verbatim\n\n"
                    (or doc
                        (format "###%s: Not Documented\n" o))))
    (insert
     (format "\nDefault Value: \n@verbatim\n%s\n@end verbatim\n\n"
             (self-document--portable-default-value value)))
    (insert "\n@end defvar\n\n")))

(defun self-document-module-options (self)
  "Document options for this module."
  (let ((name (self-document-name self))
        (file-name-handler-alist nil)
        (options  nil))
    (insert (format "@subsection %s Options\n\n" name))
    (setq options
          (sort
           (self-document-options self)
           #'(lambda (a b) (string-lessp (symbol-name a) (symbol-name b)))))
    (mapc #'self-document-option options)))

(defun self-document-command (c)
  "Document this command."
  (let ((key (where-is-internal c))
        (keys nil))
    (insert
     (format "\n\n@subsubsection %s\n@deffn {Command} %s  %s\n"
             c c
             (or (help-function-arglist c t) " ")))
    (when key
      (setq keys (mapcar #'sd-texinfo-escape (mapcar #'key-description key )))
      (insert "@table @kbd\n")
      (cl-loop for k in keys do
               (insert (format "@item %s\n" k))
               (insert (format "@kindex %s\n" k)))
      (insert "@end table\n\n"))
    (insert (format "@findex %s\n\n" c))
    (insert
     (if
         (documentation c)
         (format "@format\n%s\n@end format"
                 (sd-texinfo-escape (documentation c)))
       (format "### %s: Not Documented\n" c)))
    (insert "\n@end deffn\n\n")))

(defun self-document-module-commands (self)
  "Document commands for this module."
  (let ((name (self-document-name self))
        (file-name-handler-alist nil)
        (commands  nil))
    (insert (format "@subsection %s Commands\n\n" (capitalize name)))
    (setq commands
          (sort
           (self-document-commands self)
           #'(lambda (a b) (string-lessp (symbol-name a) (symbol-name b)))))
    (mapc #'self-document-command commands)))

(defun self-document-module-documentable-p (self)
  "Return non-nil when SELF has documentation worth emitting."
  (or (self-document-commentary self)
      (self-document-commands self)
      (self-document-options self)))

(defun self-document-module (self)
  "Generate documentation for commands and options in a module."
  (let ((file-name-handler-alist nil))
    ;; Only generate in non-degenerate case
    (when (self-document-module-documentable-p self)
      (self-document-module-preamble self)
      (when (self-document-commands self) (self-document-module-commands self))
      (when (self-document-options self)(self-document-module-options
                                         self))))
  (message "Done: %s " (self-document-name self) ))


;;; Document Keybindings For Various Prefix Maps:

(cl-declaim (special emacsvox-prefix))
(defvar sd-emacsvox-prefixes
  (list
   emacsvox-prefix
   (kbd "C-;") (kbd "C-'") (kbd "C-.") (kbd "C-,") (kbd "C-z")
   (kbd "C-e x") (kbd "C-e y" )   (kbd "C-e z") (kbd "C-e '"))
  "Key prefixes  for which we generate a help section."
  )
;; not used:
(defun sd-describe-keys (buffer)
  "Generate a Texinfo section in `buffer' listing commands bound
 to prefix in `sd-emacsvox-prefixes'."
  (with-current-buffer buffer
    (insert "@section Commands Organized By Keymaps\n")
    (insert "@node Commands Organized By Keymaps\n\n")
    (cl-loop
     for prefix in sd-emacsvox-prefixes
     do
     (insert
      (format "@subsection Commands on prefix %s" (key-description prefix)))
     (insert "\n\n@code{@verb{|")
     (describe-buffer-bindings (current-buffer) prefix)
     (insert "|}}\n")
     )))


;;;  Iterate over all modules

(declare-function
 emacsvox-url-template-generate-texinfo-documentation
 (buffer))
(defun self-document-fix-quotes ()
  "Fix UTF8 curved quotes since makeinfo doesn't handle them well."
  (goto-char (point-min))
  (while
      (search-forward (format "%c" 8216) (point-max) 'no-error)
    (replace-match "``"))
  (goto-char (point-min))
  (while
      (search-forward (format "%c" 8217) (point-max) 'no-error)
    (replace-match "''")))

(defun self-document-fix-fn-key ()
  "Change <XF86WakeUp> to <fn>."
  (goto-char (point-min))
  (while
      (search-forward self-document-fn-key (point-max) 'no-error)
    (replace-match "<fn>")))

(defun self-document-fix-bs ()
  "Change literal backspace to <DEL>"
  (goto-char (point-min))
  (while
      (search-forward (format "%c" 127) (point-max) 'no-error)
    (replace-match "<DEL>")))

(defun self-document-insert-module-menu (keys)
  "Insert a Texinfo menu for the documentable modules in KEYS."
  (insert "@menu\n")
  (dolist (module keys)
    (let ((entry (gethash module self-document-map)))
      (when (self-document-module-documentable-p entry)
        (let* ((library (locate-library (format "%s.el" module)))
               (summary (and library (lm-summary library))))
          (insert (format "* %s::" module))
          (when summary
            (insert (format " %s" (sd-texinfo-escape summary)))
            (unless (string-match-p "[.!?]\\='" summary)
              (insert ".")))
          (insert "\n")))))
  (insert "* URL Templates:: Generated web-search templates.\n")
  (insert "@end menu\n\n"))

(defun self-document-all-modules()
  "Generate documentation for all modules."
  (self-document-all-keymaps)
  (let ((file-name-handler-alist nil)
        (output (find-file-noselect "docs.texi"))
        (keys nil))
    (self-document-load-modules)
    (self-document-build-map)
    (setq keys
          (sort
           (cl-loop for k being  the hash-keys of self-document-map collect k)
           #'string-lessp))
    (with-current-buffer output
      (erase-buffer)
      (insert "@c Auto-generated, do not hand-edit.\n")
      (insert
       (format
        "@node Emacsvox Commands And Options \n
@chapter Emacsvox Commands And Options \n\n
@include intro-docs.texi\n\n
This chapter documents a total of %d commands and %d options.\n\n"
        self-document-command-count self-document-option-count ))
      (self-document-insert-module-menu keys)
      (cl-loop
       for k in keys do
       (self-document-module (gethash k self-document-map)))
      (emacsvox-url-template-generate-texinfo-documentation (current-buffer))
      (flush-lines "^Commentary: *$" (point-min) (point-max))
      (self-document-fix-fn-key)
      (self-document-fix-bs)
      (delete-trailing-whitespace (point-min) (point-max))
      (shell-command-on-region          ; squeeze blanks
       (point-min) (point-max)
       "cat -s" (current-buffer) 'replace)
      (save-buffer)))
  (message "Done!"))


;;;  Document all keybindings:

(defun sd-sort-keymap (key-entries)
  "Safely sort and return keymap entries."
  (let ((temp (copy-sequence key-entries)))
    (cl-sort
     temp
     #'(lambda (a b)
         (cond
          ((and (characterp (car a)) (characterp (car b)))
           (< (car a) (car b)))
          (t nil))))))

(defvar self-document-keymap-list
  '(
    emacsvox-keymap emacsvox-tts-submap
    emacsvox-hyper-keymap emacsvox-super-keymap emacsvox-alt-keymap
    emacsvox-multi-keymap
    emacsvox-v-keymap emacsvox-x-keymap
    emacsvox-y-keymap  emacsvox-z-keymap
    )
  "List of keymaps that we document.")

(defun self-document-keymap (keymap)
  "Output Texinfo documentation for bindings in keymap."
  (cl-assert  (keymapp keymap) t "Not a valid keymap: %s")
  (let ((entries (sd-sort-keymap (cdr (copy-keymap keymap )))))
    (insert "@table @kbd\n")
    (cl-loop
     for binding in entries
     when (and (characterp (car binding))
               (not (keymapp  (cdr binding))))
     do
     (insert
      (format "@item %s  %s\n"
              (sd-texinfo-escape (key-description (format "%c" (car binding))))
              (cdr binding))))
    (insert "@end table\n")))

(defun self-document-all-keymaps()
  "Generate documentation for all Emacsvox keymaps."
  (let ((output (find-file-noselect "keys.texi"))
        (title nil))
    (with-current-buffer output
      (erase-buffer)
      (texinfo-mode)
      (insert "@node Emacsvox Keymaps\n @chapter Emacsvox Keymaps\n\n ")
      (cl-loop
       for keymap in self-document-keymap-list do
       (setq title (format "Emacsvox Keybindings On %s" (symbol-name keymap)))
       (insert (format "\n@node %s\n @section %s\n\n" title title))
       (self-document-keymap (symbol-value keymap)))
      (delete-trailing-whitespace (point-min) (point-max))
      (shell-command-on-region          ; squeeze blanks
       (point-min) (point-max)
       "cat -s" (current-buffer) 'replace)
      (save-buffer))))


;;;  Tests:

(defun self-document-load-test ()
  "Dump out command map in /tmp"
  (setq debug-on-error t)
  (let ((output (find-file-noselect (make-temp-file "self-command-map")))
        (c-count 0)
        (o-count 0))
    (self-document-load-modules)
    (self-document-build-map)
    (with-current-buffer output
      (insert
       (format "Global Counts: Commands: %d Options: %d\n"
               self-document-command-count self-document-option-count))
      (maphash
       #'(lambda (f self)
           (insert
            (format
             "\fModule: %s Commands: %d Options: %d\n"
             f
             (length (self-document-commands self))
             (length (self-document-options self))))
           (unless (zerop (length (self-document-commands self)))
             (insert
              (format "Commands: \n%s\n"
                      (mapconcat #'symbol-name (self-document-commands self)
                                 "\n"))))
           (unless (zerop (length (self-document-options self)))
             (insert
              (format "Options: \n%s\n"
                      (mapconcat #'symbol-name (self-document-options self)
                                 "\n"))))
           (cl-incf c-count (length (self-document-commands self)))
           (cl-incf o-count (length (self-document-options self))))
       self-document-map)
      (insert (format "Commands: %d Options: %d\n" c-count o-count))
      (save-buffer))))

(defun self-document-module-test ()
  "Test documentation generator."
  (setq debug-on-error t)
  (let ((output (find-file-noselect (make-temp-file "doc" nil ".texi"))))
    (self-document-load-modules)
    (self-document-build-map)
    (with-current-buffer output
      (insert
       (format
        "@node Emacsvox Commands And Options \n
@chapter Emacsvox Commands And Options \n\n
This chapter documents a total of %d commands and %d options.\n\n"
        self-document-command-count self-document-option-count ))
      (cl-loop
       for v being the hash-values of self-document-map  do
       (self-document-module v))
      (save-buffer))))


(provide 'self-document)
;;;  end of file

;; local variables:
;; folded-file: t
;; end:
