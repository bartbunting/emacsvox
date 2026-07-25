;;; emacsvox-notmuch-tests.el --- Notmuch advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'notmuch)
(load (expand-file-name "../lisp/emacsvox-notmuch.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-notmuch-advice-is-current-and-direct ()
  "Current Notmuch targets use native advice directly."
  (dolist (entry emacsvox-notmuch--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(defconst emacsvox-notmuch-test--search-result
  '(:authors "Alice Smith|Bob Jones"
    :subject "Project update"
    :date_relative "yesterday"
    :matched 2
    :total 5
    :tags ("inbox" "unread" "flagged" "work")
    :orig-tags ("inbox" "unread" "flagged" "work"))
  "Representative Notmuch search result used by speech tests.")

(ert-deftest emacsvox-notmuch-formats-semantic-search-result ()
  "Search results use semantic fields, native faces, and silent statuses."
  (let* ((summary
          (emacsvox-notmuch-format-search-result
           emacsvox-notmuch-test--search-result))
         (plain (substring-no-properties summary)))
    (should
     (equal
      plain
      "Alice Smith, Bob Jones, Project update, yesterday, 2 of 5, inbox work"))
    (should-not (string-match-p "unread\\|flagged" plain))
    (should
     (eq (get-text-property 0 'face summary)
         'notmuch-search-matching-authors))
    (should
     (eq
      (get-text-property (string-match "Bob Jones" summary) 'face summary)
      'notmuch-search-non-matching-authors))
    (should
     (eq
      (get-text-property (string-match "Project update" summary) 'face summary)
      'notmuch-search-subject))
    (should
     (eq
      (get-text-property (string-match "yesterday" summary) 'face summary)
      'notmuch-search-date))
    (should
     (eq
      (get-text-property (string-match "2 of 5" summary) 'face summary)
      'notmuch-search-count))))

(ert-deftest emacsvox-notmuch-search-result-fields-are-configurable ()
  "Search-result fields can be reordered and omitted."
  (let ((emacsvox-notmuch-search-result-fields '(subject authors))
        (emacsvox-notmuch-search-field-separator " / "))
    (should
     (equal
      (substring-no-properties
       (emacsvox-notmuch-format-search-result
        emacsvox-notmuch-test--search-result))
      "Project update / Alice Smith, Bob Jones"))))

(ert-deftest emacsvox-notmuch-search-status-uses-icons-not-words ()
  "Configured status tags play icons and remain out of speech."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text)
                 (push
                  (list 'speak (substring-no-properties text))
                  events))))
      (emacsvox-notmuch-speak-search-result
       emacsvox-notmuch-test--search-result))
    (should
     (equal
      (nreverse events)
      '((icon new-mail)
        (icon mark-object)
        (speak
         "Alice Smith, Bob Jones, Project update, yesterday, 2 of 5, inbox work"))))))

(ert-deftest emacsvox-notmuch-navigation-speaks-selected-result ()
  "Only the active interactive search-navigation command speaks."
  (let ((ems--interactive-fn-name 'notmuch-search-next-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-notmuch-speak-search-result)
               (lambda (&optional _result) (push 'result events))))
      (emacsvox--advice-notmuch-search-next-thread-after)
      (emacsvox--advice-notmuch-search-previous-thread-after))
    (should (equal events '(result)))))

(provide 'emacsvox-notmuch-tests)
;;; emacsvox-notmuch-tests.el ends here
