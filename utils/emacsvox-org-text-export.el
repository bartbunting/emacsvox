;;; emacsvox-org-text-export.el --- Export the Org manual as plain text -*- lexical-binding: t; -*-

;;; Commentary:

;; Export the canonical Org manual source to UTF-8 plain text.  The manual
;; writes keys, cross references, and acronyms as inline Texinfo export
;; snippets, which the stock ASCII backend drops.  This derived backend
;; renders those snippets as readable text instead.

;;; Code:

(require 'emacsvox-org-export)
(require 'org)
(require 'ox-ascii)
(require 'subr-x)

(defconst emacsvox-org-text-export--glyphs
  '(("NDash" . "–") ("MDash" . "—") ("dots" . "…") ("tie" . " ")
    ("comma" . ",") ("TeX" . "TeX") ("LaTeX" . "LaTeX"))
  "Texinfo glyph commands and their plain-text rendering.")

(defun emacsvox-org-text-export--arguments (text)
  "Split Texinfo command argument TEXT on top-level commas."
  (let ((depth 0) (start 0) (index 0) arguments)
    (dolist (char (string-to-list text))
      (pcase char
        (?\{ (setq depth (1+ depth)))
        (?\} (setq depth (1- depth)))
        (?, (when (zerop depth)
              (push (substring text start index) arguments)
              (setq start (1+ index)))))
      (setq index (1+ index)))
    (push (substring text start) arguments)
    (mapcar #'string-trim (nreverse arguments))))

(defun emacsvox-org-text-export--reference (command arguments)
  "Render cross-reference COMMAND with Texinfo ARGUMENTS as text."
  (let* ((node (nth 0 arguments))
         (label (nth 1 arguments))
         (manual (or (nth 4 arguments) (nth 3 arguments)))
         (external (not (string-empty-p (or manual ""))))
         (target (cond
                  ((not (string-empty-p (or label ""))) label)
                  ((and external (string-equal node "Top")) manual)
                  (t node)))
         (target (if (and external (not (string-equal target manual)))
                     (format "%s (%s)" target manual)
                   target)))
    (pcase command
      ("xref" (concat "See " target))
      ("pxref" (concat "see " target))
      (_ target))))

(defun emacsvox-org-text-export--texinfo (text)
  "Render inline Texinfo TEXT as plain text."
  (let ((case-fold-search nil)
        (pattern "@\\([a-zA-Z]+\\){\\([^{}]*\\)}"))
    ;; Resolve innermost commands first so nested @key inside @kbd works.
    (while (string-match pattern text)
      (let* ((command (match-string 1 text))
             (argument (match-string 2 text))
             (rendered
              (cond
               ((assoc command emacsvox-org-text-export--glyphs)
                (cdr (assoc command emacsvox-org-text-export--glyphs)))
               ((member command '("anchor" "cindex" "findex" "kindex"
                                  "vindex" "footnote"))
                "")
               ((member command '("ref" "xref" "pxref"))
                (emacsvox-org-text-export--reference
                 command (emacsvox-org-text-export--arguments argument)))
               (t argument))))
        (setq text (replace-match rendered t t text))))
    (replace-regexp-in-string
     "@\\([@{}]\\)" "\\1"
     (replace-regexp-in-string "@\\*\\|@ \\|@\\." "" text t t))))

(defun emacsvox-org-text-export--export-snippet (snippet _contents info)
  "Render Texinfo SNIPPET as text; defer others to the ASCII backend with INFO."
  (if (eq (org-export-snippet-backend snippet) 'texinfo)
      (emacsvox-org-text-export--texinfo
       (org-element-property :value snippet))
    (org-ascii-export-snippet snippet nil info)))

(defun emacsvox-org-text-export--export-block (block contents info)
  "Drop Texinfo export BLOCK; defer others to ASCII with CONTENTS and INFO."
  (unless (string-equal "TEXINFO" (org-element-property :type block))
    (org-ascii-export-block block contents info)))

(unless (org-export-get-backend 'emacsvox-text)
  (org-export-define-derived-backend 'emacsvox-text 'ascii
    :translate-alist
    '((export-snippet . emacsvox-org-text-export--export-snippet)
      (export-block . emacsvox-org-text-export--export-block))))

(defun emacsvox-org-text-export (source output)
  "Export Org SOURCE as UTF-8 text OUTPUT and return OUTPUT."
  (let* ((source (expand-file-name source))
         (output (expand-file-name output)))
    (unless (file-regular-p source)
      (error "Org manual source is not a regular file: %s" source))
    (make-directory (file-name-directory output) t)
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source
            default-directory (file-name-directory source))
      (delay-mode-hooks (org-mode))
      (let ((org-export-time-stamp-file nil)
            (org-export-use-babel nil)
            (coding-system-for-write 'utf-8-unix))
        (org-export-to-file 'emacsvox-text output nil nil nil nil
                            '(:ascii-charset utf-8
                              :with-broken-links mark))))
    output))

(defun emacsvox-org-text-export-batch ()
  "Export the Org manual named by the batch environment as text."
  (condition-case condition
      (message "Exported Org manual to %s"
               (emacsvox-org-text-export
                (emacsvox-org-export--required-environment
                 "EMACSVOX_ORG_SOURCE")
                (emacsvox-org-export--required-environment
                 "EMACSVOX_ORG_OUTPUT")))
    (error
     (message "Org manual text export failed: %s"
              (error-message-string condition))
     (let ((kill-emacs-hook nil)
           (kill-emacs-query-functions nil))
       (kill-emacs 1)))))

(provide 'emacsvox-org-text-export)
;;; emacsvox-org-text-export.el ends here
