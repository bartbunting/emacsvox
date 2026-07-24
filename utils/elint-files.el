;;;$Id: elint-files.el 7425 2011-11-22 01:55:17Z tv.raman.tv $  -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'advice)
(require 'derived)
(push default-directory load-path)
(push (expand-file-name "g-client" default-directory) load-path)
(require 'emacsvox-preamble)
(load-file (expand-file-name "emacsvox-loaddefs.el" emacsvox-lisp-directory))
(require 'emacsvox-sounds)
(load-library "g-loaddefs")
(require 'elint)
(require 'emacsvox-preamble)
(defun batch-elint-files ()
  "Batch elint  elisp files in directory."
  (let ((file-list (directory-files default-directory nil "\\.el\\'")))
    (cl-loop
     for f in file-list do
     (unless
         (or (string-match "emacsvox-loaddefs.el" f)
             (string-match "emacsvox-autoload.el" f)
             (string-match ".skeleton.el" f))
       (elint-file f)))))

(batch-elint-files)
