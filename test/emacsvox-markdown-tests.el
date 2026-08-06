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
  "Every registered Markdown target exists and uses direct advice."
  (dolist (entry emacsvox-markdown--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-markdown--removed-targets)
    (should-not (fboundp target))))

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
  "A successful Markdown deletion is one native edit transaction."
  (with-temp-buffer
    (insert "x")
    (let ((calls 0)
          (ems--interactive-fn-name 'markdown-outdent-or-delete)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-markdown--submit-text)
            (lambda (&rest arguments)
              (push (cons 'submission arguments) events))))
        (should
         (eq
          'deleted
          (emacsvox--advice-markdown-outdent-or-delete-around
           (lambda ()
             (cl-incf calls)
             (push 'original events)
             (delete-char -1)
             'deleted)))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(original
          (submission
           "x"
           (:role markdown-content :events (object-changed)
            :edit-operation deletion)
           edit)))))))

(ert-deftest emacsvox-markdown-delete-no-op-stays-silent ()
  "A command that changes no text does not announce a deletion."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'markdown-outdent-or-delete)
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-markdown--submit-text)
            (lambda (&rest arguments)
              (push arguments submissions))))
        (should
         (eq
          'unchanged
          (emacsvox--advice-markdown-outdent-or-delete-around
           (lambda () 'unchanged)))))
      (should-not submissions))))

(ert-deftest emacsvox-markdown-aural-vocabulary-is-registered ()
  "Markdown roles, attributes, states, and events are available at startup."
  (dolist
      (id
       '(markdown-content markdown-list-item markdown-task markdown-link
         markdown-code-block markdown-table-row markdown-footnote
         markdown-separator markdown-language markdown-list-kind
         markdown-task-state markdown-navigation-kind
         markdown-reading-mode-state checked unchecked
         markdown-heading-navigated markdown-link-navigated
         markdown-structure-navigated markdown-operation-completed
         markdown-completion-completed markdown-code-edit-opened))
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
         ("|---|---|" markdown-separator nil)
         ("[ref]: https://example.test" markdown-link nil)
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
    '(task-done)))
  (should
   (equal
    (emacsvox-markdown-test--compatibility-cues
     '(:role markdown-code-block :events (markdown-code-edit-opened))
     'state-change)
    '(open-object))))

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

(ert-deftest emacsvox-markdown-line-feedback-is-one-native-transaction ()
  "Line cues and content are consolidated without repeating a source icon."
  (with-temp-buffer
    (insert (propertize "item" 'auditory-icon 'item))
    (goto-char (point-min))
    (let (submission)
      (cl-letf
          (((symbol-function 'emacsvox-speak-line-with-speaker)
            (lambda (speaker &optional _)
              (emacsvox-icon 'item)
              (funcall
               speaker
               (buffer-substring (point-min) (point-max)))))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox-markdown--present-current-line
         '(:role markdown-list-item :events (focus-entered)
           :markdown-navigation-kind line)
         'navigation))
      (pcase-let* ((`(,content . ,arguments) submission)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "item"))
        (should-not (get-text-property 0 'auditory-icon content))
        (should (= (length actions) 1))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value (car actions))
          'item))
        (should (eq (plist-get arguments :module) 'markdown))
        (should (eq (plist-get arguments :occasion) 'navigation))))))

(ert-deftest emacsvox-markdown-empty-line-keeps-first-class-condition ()
  "A blank Markdown line submits its semantic object and line condition once."
  (with-temp-buffer
    (let (submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox-markdown--present-current-line
         '(:role markdown-content :events (focus-entered)
           :markdown-navigation-kind line)
         'navigation))
      (should
       (equal
        (plist-get submission :facts)
        '(:role markdown-content :events (focus-entered)
          :markdown-navigation-kind line :line-condition empty)))
      (should (eq (plist-get submission :module) 'markdown))
      (should (eq (plist-get submission :occasion) 'navigation)))))

(ert-deftest emacsvox-markdown-structural-lines-submit-action-feedback ()
  "Table separators and reference definitions cannot leave stale speech."
  (dolist
      (case
       '(("|---|---|"
          (:role markdown-separator :events (focus-entered)
           :markdown-navigation-kind line :line-condition separator))
         ("[ref]: https://example.test"
          (:role markdown-link
           :events (focus-entered markdown-link-navigated)
           :markdown-navigation-kind line))))
    (with-temp-buffer
      (insert (car case))
      (setq major-mode 'markdown-mode)
      (let (submission)
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest _)
                (ert-fail "Structural Markdown line submitted speech")))
             ((symbol-function 'emacsvox-aural-submit-actions)
              (lambda (&rest arguments)
                (setq submission arguments))))
          (emacsvox-markdown--speak-line-clean))
        (should (equal (plist-get submission :facts) (cadr case)))
        (should (eq (plist-get submission :module) 'markdown))
        (should (eq (plist-get submission :occasion) 'navigation))))))

(ert-deftest emacsvox-markdown-structural-line-plans-are-audible ()
  "Default structural-line plans contain a tone or auditory cue."
  (dolist
      (case
       '(((:role markdown-separator :events (focus-entered)
           :markdown-navigation-kind line :line-condition separator)
          tone line-separator)
         ((:role markdown-link
           :events (focus-entered markdown-link-navigated)
           :markdown-navigation-kind line)
          cue button)))
    (pcase-let ((`(,facts ,kind ,value) case))
      (let* ((context
              '(:module markdown :mode markdown-mode
                :mode-lineage (markdown-mode text-mode)
                :occasion navigation :icons-enabled t))
             (plan (emacsvox-aural-resolve-active facts context))
             (action
              (cl-find
               kind (emacsvox-aural-render-plan-before plan)
               :key #'emacsvox-aural-action-kind)))
        (should action)
        (should
         (eq
          (if (eq kind 'tone)
              (emacsvox-aural-action-tone action)
            (emacsvox-aural-action-cue action))
          value))))))

(ert-deftest emacsvox-markdown-reading-mode-toggle-is-native ()
  "The user-facing reading-mode state is displayed and submitted once."
  (with-temp-buffer
    (let (submission)
      (cl-letf
          (((symbol-function 'emacsvox-markdown--submit-message)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox-markdown-reading-mode 1))
      (should emacsvox-markdown-reading-mode)
      (should
       (equal
        submission
        '("Markdown reading mode enabled"
          (:role markdown-content :events (state-changed)
           :markdown-reading-mode-state enabled)
          state-change))))))

(ert-deftest emacsvox-markdown-face-map-covers-current-interface ()
  "Every mapped Markdown face exists in the installed package."
  (dolist (entry emacsvox-markdown--face-voice-map)
    (should (facep (car entry)))))

(ert-deftest emacsvox-markdown-command-classification-is-semantic ()
  "Navigation, editing, visibility, and code editing have distinct events."
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
    (emacsvox-markdown--command-presentation 'markdown-indent-region)
    '(object-changed . edit)))
  (should
   (equal
    (emacsvox-markdown--command-presentation 'markdown-blockquote-region)
    '(object-changed . edit)))
  (should
   (equal
    (emacsvox-markdown--command-presentation 'markdown-edit-code-block)
    '(markdown-code-edit-opened . state-change))))

(ert-deftest emacsvox-markdown-cycle-classification-follows-context ()
  "Cycling reports table motion, heading visibility, or indentation accurately."
  (dolist
      (case
       '(("| a | b |" markdown-structure-navigated navigation)
         ("# heading" visibility-changed state-change)
         ("ordinary text" object-changed edit)))
    (with-temp-buffer
      (insert (car case))
      (should
       (equal
        (emacsvox-markdown--command-presentation 'markdown-cycle)
        (cons (cadr case) (caddr case))))))
  (with-temp-buffer
    (insert "ordinary text")
    (let ((current-prefix-arg '(4)))
      (should
       (equal
        (emacsvox-markdown--command-presentation 'markdown-cycle)
        '(visibility-changed . state-change))))))

(ert-deftest emacsvox-markdown-operation-feedback-names-the-result ()
  "Completed operations use a specific native message and lifecycle event."
  (with-temp-buffer
    (insert "content")
    (let ((ems--interactive-fn-name 'markdown-check-refs)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-markdown--submit-message)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox--advice-markdown-check-refs-after))
      (should
       (equal
        submission
        '("Markdown reference check complete"
          (:role markdown-content
           :events (markdown-operation-completed))
          notification))))))

(ert-deftest emacsvox-markdown-region-edits-are-not-task-completions ()
  "Indenting or blockquoting a region uses edit presentation."
  (dolist (target '(markdown-indent-region markdown-blockquote-region))
    (let ((ems--interactive-fn-name target)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-markdown--present-current-line)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (funcall
         (intern (format "emacsvox--advice-%s-after" target))))
      (should
       (equal
        (plist-get (car submission) :events)
        '(object-changed)))
      (should (eq (cadr submission) 'edit)))))

(provide 'emacsvox-markdown-tests)
;;; emacsvox-markdown-tests.el ends here
