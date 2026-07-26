;;; emacsvox-markdown-tests.el --- Markdown advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'markdown-mode)
(load (expand-file-name "../lisp/emacsvox-markdown.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(defun emacsvox-markdown-test--presentation-snapshot ()
  "Return copied semantic state at the current output boundary."
  (list
   (copy-tree emacsvox-aural-submission-facts)
   emacsvox-aural-submission-module
   emacsvox-aural-submission-occasion
   (copy-tree emacsvox-aural-submission-context)))

(defun emacsvox-markdown-test--compatibility-cues (facts occasion)
  "Return compatibility cues resolved for FACTS and OCCASION."
  (let* ((context
          (list
           :module 'markdown
           :mode 'markdown-mode
           :mode-lineage '(markdown-mode text-mode)
           :occasion occasion))
         (plan (emacsvox-aural-resolve-active facts context)))
    (mapcar
     #'emacsvox-aural-action-cue
     (emacsvox-aural-render-plan-before plan))))

(ert-deftest emacsvox-markdown-current-advice-is-direct ()
  "Every available Markdown target uses native advice directly."
  (dolist (entry emacsvox-markdown--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (fboundp target)
        (should (advice-member-p function target))))))

(ert-deftest emacsvox-markdown-speak-line-calls-original-once ()
  "Ordinary buffers delegate to the original speaker exactly once."
  (with-temp-buffer
    (let ((calls 0))
      (should
       (eq
        'spoken
        (emacsvox--advice-markdown-speak-line-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (should (equal arguments '(1)))
           'spoken)
         1)))
      (should (= calls 1)))))

(ert-deftest emacsvox-markdown-delete-calls-original-once ()
  "Markdown deletion gives feedback and invokes its command once."
  (with-temp-buffer
    (insert "x")
    (let ((calls 0)
          (ems--interactive-fn-name 'markdown-outdent-or-delete))
      (cl-letf (((symbol-function 'tts-tone) #'ignore)
                ((symbol-function 'emacsvox-speak-this-char) #'ignore))
        (should
         (eq
          'deleted
          (emacsvox--advice-markdown-outdent-or-delete-around
           (lambda () (cl-incf calls) 'deleted)))))
      (should (= calls 1)))))

(ert-deftest emacsvox-markdown-aural-vocabulary-is-registered ()
  "Markdown roles, attributes, states, and events are available at startup."
  (dolist
      (id
       '(markdown-content markdown-list-item markdown-task markdown-link
         markdown-code-block markdown-table-row markdown-footnote
         markdown-separator markdown-language markdown-list-kind
         markdown-task-state markdown-navigation-kind checked unchecked
         markdown-heading-navigated markdown-link-navigated
         markdown-structure-navigated markdown-operation-completed
         markdown-completion-completed))
    (should (emacsvox-aural-semantic id)))
  (should
   (gethash
    'markdown-compatibility emacsvox-aural-module-fragment-registry)))

(ert-deftest emacsvox-markdown-headings-cover-atx-and-setext ()
  "ATX and Setext headings expose the same heading-level contract."
  (with-temp-buffer
    (insert "### ATX title ###\n\nSetext title\n------------\n")
    (setq major-mode 'markdown-mode)
    (goto-char (point-min))
    (should
     (equal
      (emacsvox-markdown-facts-at-point 'focus-entered 'line)
      '(:role heading :events (focus-entered) :level 3
        :visibility expanded :markdown-navigation-kind line)))
    (forward-line 2)
    (should
     (equal
      (emacsvox-markdown-facts-at-point 'focus-entered 'line)
      '(:role heading :events (focus-entered) :level 2
        :visibility expanded :markdown-navigation-kind line)))))

(ert-deftest emacsvox-markdown-structure-facts-are-specific ()
  "Tasks, code, tables, links, footnotes, and lists expose distinct intent."
  (dolist
      (entry
       '(("- [x] done" markdown-task
          (:states (checked) :markdown-list-kind unordered
           :markdown-task-state checked))
         ("```elisp" markdown-code-block
          (:markdown-language "elisp"))
         ("| one | two |" markdown-table-row nil)
         ("read [the guide](guide.md)" markdown-link nil)
         ("[^1]: detail" markdown-footnote nil)
         ("2. ordered" markdown-list-item
          (:markdown-list-kind ordered))
         ("---" markdown-separator nil)))
    (with-temp-buffer
      (insert (car entry))
      (setq major-mode 'markdown-mode)
      (let ((facts (emacsvox-markdown-facts-at-point)))
        (should (eq (plist-get facts :role) (cadr entry)))
        (let ((tail (caddr entry)))
          (while tail
            (should (equal (plist-get facts (car tail)) (cadr tail)))
            (setq tail (cddr tail))))))))

(ert-deftest emacsvox-markdown-line-and-command-share-heading-intent ()
  "Line and structural navigation identify the same Markdown heading."
  (with-temp-buffer
    (insert "## Shared heading\n")
    (setq major-mode 'markdown-mode)
    (goto-char (point-min))
    (let (line-presentation command-presentation)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (_)
              (setq line-presentation
                    (emacsvox-markdown-test--presentation-snapshot)))))
        (emacsvox--advice-markdown-speak-line-around #'ignore))
      (let ((ems--interactive-fn-name 'markdown-next-heading))
        (cl-letf
            (((symbol-function 'tts-speak)
              (lambda (_)
                (setq command-presentation
                      (emacsvox-markdown-test--presentation-snapshot)))))
          (emacsvox--advice-markdown-next-heading-after)))
      (let ((line-facts (car line-presentation))
            (command-facts (car command-presentation)))
        (should (eq (plist-get line-facts :role) 'heading))
        (should (eq (plist-get command-facts :role) 'heading))
        (should (= (plist-get line-facts :level) 2))
        (should (= (plist-get command-facts :level) 2))
        (should
         (equal
          (plist-get line-facts :events) '(focus-entered)))
        (should
         (equal
          (plist-get command-facts :events)
          '(markdown-heading-navigated)))
        (should (eq (cadr line-presentation) 'markdown))
        (should (eq (caddr line-presentation) 'navigation))
        (should (eq (cadr command-presentation) 'markdown))
        (should (eq (caddr command-presentation) 'navigation))))))

(ert-deftest emacsvox-markdown-compatibility-cues-remain-stable ()
  "Data-only Markdown defaults preserve established line and command cues."
  (should
   (equal
    (emacsvox-markdown-test--compatibility-cues
     '(:role heading :events (focus-entered) :level 2
       :visibility expanded :markdown-navigation-kind line)
     'navigation)
    '(section)))
  (should
   (equal
    (emacsvox-markdown-test--compatibility-cues
     '(:role heading :events (markdown-heading-navigated) :level 2
       :visibility expanded :markdown-navigation-kind structural)
     'navigation)
    '(large-movement)))
  (should
   (equal
    (emacsvox-markdown-test--compatibility-cues
     '(:role markdown-link :events (markdown-link-navigated)
       :markdown-navigation-kind structural)
     'navigation)
    '(button)))
  (should
   (equal
    (emacsvox-markdown-test--compatibility-cues
     '(:role markdown-content :events (markdown-operation-completed))
     'notification)
    '(task-done))))

(ert-deftest emacsvox-markdown-reading-mode-carries-task-state ()
  "Clean task speech retains task identity and checked state."
  (with-temp-buffer
    (insert "- [x] ship it")
    (setq major-mode 'markdown-mode)
    (let (speech presentation)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text)
              (setq speech text
                    presentation
                    (emacsvox-markdown-test--presentation-snapshot)))))
        (emacsvox-markdown--speak-line-clean))
      (should (equal speech "checked: ship it"))
      (should (eq (plist-get (car presentation) :role) 'markdown-task))
      (should
       (equal (plist-get (car presentation) :states) '(checked)))
      (should (eq (cadr presentation) 'markdown))
      (should (eq (caddr presentation) 'navigation)))))

(ert-deftest emacsvox-markdown-command-classification-is-semantic ()
  "Navigation, editing, visibility, and completion have distinct events."
  (should
   (equal
    (emacsvox-markdown--command-presentation 'markdown-forward-block)
    '(markdown-structure-navigated . navigation)))
  (should
   (equal
    (emacsvox-markdown--command-presentation 'markdown-insert-bold)
    '(object-changed . edit)))
  (should
   (equal
    (emacsvox-markdown--command-presentation 'markdown-hide-subtree)
    '(visibility-changed . state-change))))

(provide 'emacsvox-markdown-tests)
;;; emacsvox-markdown-tests.el ends here
