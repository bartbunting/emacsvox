;;; emacsvox-org-srs-tests.el --- Org-srs speech tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit coverage for the optional Org-srs integration.  These tests stub the
;; package API so the core Emacsvox suite does not require Org-srs to be
;; installed.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'org)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-org-srs.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  (load module nil nil))

(defmacro emacsvox-test--capture-org-srs-submissions (&rest body)
  "Evaluate BODY and return Org-srs submissions in call order."
  (declare (indent 0) (debug t))
  `(let (captured)
     (cl-letf (((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push (cons content arguments) captured))))
       ,@body)
     (nreverse captured)))

(defun emacsvox-test--activate-org-srs-mode ()
  "Activate Org mode without unrelated full-startup speech setup."
  (let ((org-mode-hook
         (remove #'emacsvox-org-mode-setup (copy-sequence org-mode-hook))))
    (org-mode)))

(ert-deftest emacsvox-org-srs-provider-registers-review-semantics ()
  "Org-srs semantic vocabulary and compatibility fragment are registered."
  (dolist (semantic
           '(learning-session learning-item learning-phase learning-item-kind
             learning-rating learning-next-interval learning-pending-count
             learning-session-started learning-question-presented
             learning-answer-revealed learning-item-rated
             learning-session-finished learning-session-stopped))
    (should (emacsvox-aural-semantic semantic)))
  (should (gethash 'org-srs-review-feedback
                   emacsvox-aural-module-fragment-registry)))

(ert-deftest emacsvox-org-srs-card-selects-front-and-back-correctly ()
  "Normal and reversed cards speak the visible side, then the hidden side."
  (with-temp-buffer
    (emacsvox-test--activate-org-srs-mode)
    (insert "* Front\nWhat is the capital?\n* Back\nCanberra\n")
    (let ((front (cons (point-min)
                       (save-excursion
                         (goto-char (point-min))
                         (search-forward "* Back")
                         (line-beginning-position))))
          (back (cons (save-excursion
                        (goto-char (point-min))
                        (search-forward "* Back")
                        (line-beginning-position))
                      (point-max))))
      (cl-letf (((symbol-function 'org-srs-item-card-regions)
                 (lambda () (cl-values front back))))
        (should (equal (emacsvox-org-srs--card-content 'back nil)
                       "What is the capital?"))
        (should (equal (emacsvox-org-srs--card-content 'back t)
                       "Canberra"))
        (should (equal (emacsvox-org-srs--card-content 'front nil)
                       "Canberra"))
        (should (equal (emacsvox-org-srs--card-content 'front t)
                       "What is the capital?"))))))

(ert-deftest emacsvox-org-srs-cloze-question-hides-answer-and-metadata ()
  "Cloze questions expose the hint but neither answer nor SRS log drawer."
  (with-temp-buffer
    (emacsvox-test--activate-org-srs-mode)
    (insert "* Capitals\nThe capital is {{1}{Canberra}{city}}.\n"
            ":SRSITEMS:\nsecret scheduling data\n:END:\n")
    (let* ((start (save-excursion
                    (goto-char (point-min))
                    (search-forward "{{")
                    (- (point) 2)))
           (end (save-excursion
                  (goto-char start)
                  (search-forward "}}")
                  (point))))
      (cl-letf (((symbol-function 'org-srs-item-cloze-collect)
                 (lambda (&rest _)
                   (list (list 1 start end "Canberra" "city"))))
                ((symbol-function 'org-srs-item-cloze-visibility)
                 (lambda () nil)))
        (let ((question (emacsvox-org-srs--cloze-question '(1))))
          (should (string-match-p "\\[blank, hint: city\\]" question))
          (should-not (string-match-p "Canberra" question))
          (should-not (string-match-p "secret scheduling" question)))
        (should (equal (emacsvox-org-srs--cloze-answer '(1))
                       "Canberra"))))))

(ert-deftest emacsvox-org-srs-question-starts-accessible-review ()
  "The first question combines session state and semantic item facts."
  (with-temp-buffer
    (emacsvox-test--activate-org-srs-mode)
    (let ((emacsvox-org-srs--session-active-p nil)
          (emacsvox-org-srs--pending-result nil))
      (cl-letf (((symbol-function 'emacsvox-org-srs--item-content)
                 (lambda (&rest _) "Capital of Australia?"))
                ((symbol-function 'org-srs-review-upcoming-items)
                 (lambda (&rest _) '(one two)))
                ((symbol-function 'org-srs-review-add-hook-once)
                 (lambda (&rest _) nil)))
        (pcase-let* ((submissions
                      (emacsvox-test--capture-org-srs-submissions
                        (emacsvox-org-srs--before-confirm 'card 'back)))
                     (`((,content . ,arguments)) submissions)
                     (facts (plist-get arguments :facts)))
          (should
           (equal content
                  "Review started. 2 items pending. Question: Capital of Australia?"))
          (should (eq (plist-get facts :role) 'learning-item))
          (should (equal (plist-get facts :events)
                         '(learning-question-presented
                           learning-session-started)))
          (should (eq (plist-get facts :learning-phase) 'question))
          (should (= (plist-get facts :learning-pending-count) 2))
          (should emacsvox-org-srs-review-mode)
          (should (eq org-srs-item-confirm
                      #'org-srs-item-confirm-command)))))))

(ert-deftest emacsvox-org-srs-reveal-speaks-only-the-answer ()
  "Answer reveal produces one ordered semantic answer submission."
  (with-temp-buffer
    (emacsvox-test--activate-org-srs-mode)
    (cl-letf (((symbol-function 'emacsvox-org-srs--item-content)
               (lambda (_type _args answer-p)
                 (if answer-p "Canberra" "Capital of Australia?"))))
      (pcase-let* ((submissions
                    (emacsvox-test--capture-org-srs-submissions
                      (emacsvox-org-srs--after-review 'card 'back)))
                   (`((,content . ,arguments)) submissions)
                   (facts (plist-get arguments :facts)))
        (should (equal content "Answer: Canberra"))
        (should (equal (plist-get facts :events)
                       '(learning-answer-revealed)))
        (should (eq (plist-get facts :learning-phase) 'answer))
        (should (eq (plist-get arguments :delivery-policy) 'ordered))))))

(ert-deftest emacsvox-org-srs-rating-is-combined-with-next-question ()
  "Rating and due interval wait for, and prefix, the next question."
  (with-temp-buffer
    (emacsvox-test--activate-org-srs-mode)
    (cl-progv '(org-srs-review-rating org-srs-review-item)
        '(:good ((card back) "id"))
      (let ((emacsvox-org-srs--session-active-p t)
            (emacsvox-org-srs--pending-result nil))
        (cl-letf (((symbol-function 'org-srs-item-due-time)
                   (lambda (&rest _) '(172800 0 0 0)))
                  ((symbol-function 'org-srs-time-now)
                   (lambda () '(0 0 0 0)))
                  ((symbol-function 'org-srs-time-difference)
                   (lambda (&rest _) 172800))
                  ((symbol-function 'emacsvox-org-srs--item-content)
                   (lambda (&rest _) "Next question"))
                  ((symbol-function 'org-srs-review-add-hook-once)
                   (lambda (&rest _) nil)))
          (emacsvox-org-srs--after-rate)
          (should (equal (plist-get emacsvox-org-srs--pending-result :text)
                         "Good. Next review in 2 days."))
          (pcase-let* ((submissions
                        (emacsvox-test--capture-org-srs-submissions
                          (emacsvox-org-srs--before-confirm 'card 'back)))
                       (`((,content . ,arguments)) submissions)
                       (facts (plist-get arguments :facts)))
            (should
             (equal content
                    "Good. Next review in 2 days. Question: Next question"))
            (should (equal (plist-get facts :events)
                           '(learning-question-presented learning-item-rated)))
            (should (eq (plist-get facts :learning-rating) 'good))
            (should (= (plist-get facts :learning-next-interval) 172800))
            (should-not emacsvox-org-srs--pending-result)))))))

(ert-deftest emacsvox-org-srs-finish-includes-final-rating ()
  "The last rating and completion are spoken in one transaction."
  (let ((emacsvox-org-srs--session-active-p t)
        (emacsvox-org-srs--pending-result
         '(:event learning-item-rated :rating easy :interval 86400
           :text "Easy. Next review in 1 day.")))
    (pcase-let* ((submissions
                  (emacsvox-test--capture-org-srs-submissions
                    (emacsvox-org-srs--finish)))
                 (`((,content . ,arguments)) submissions)
                 (facts (plist-get arguments :facts)))
      (should (equal content
                     "Easy. Next review in 1 day. Review complete."))
      (should (eq (plist-get facts :role) 'learning-session))
      (should (equal (plist-get facts :events)
                     '(learning-session-finished)))
      (should-not emacsvox-org-srs--session-active-p)
      (should-not emacsvox-org-srs--pending-result))))

(ert-deftest emacsvox-org-srs-rating-requires-answer-reveal ()
  "Numeric rating commands reject a still-hidden answer."
  (cl-letf (((symbol-function 'org-srs-item-confirm-pending-p)
             (lambda (&rest _) t)))
    (should-error (emacsvox-org-srs-rate-good) :type 'user-error)))

(ert-deftest emacsvox-org-srs-quit-does-not-speak-hidden-answer ()
  "Confirmation cleanup during quit cannot expose the hidden answer."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'org-srs-review-quit)
          (emacsvox-org-srs--session-active-p t))
      (pcase-let* ((submissions
                    (emacsvox-test--capture-org-srs-submissions
                      (emacsvox-org-srs--around-quit
                       (lambda ()
                         (emacsvox-org-srs--after-review 'card 'back)))))
                   (`((,content . ,arguments)) submissions)
                   (facts (plist-get arguments :facts)))
        (should (equal content "Review stopped."))
        (should (equal (plist-get facts :events)
                       '(learning-session-stopped)))
        (should-not emacsvox-org-srs--session-active-p)))))

(ert-deftest emacsvox-org-srs-secondary-feedback-is-target-aware ()
  "Only the directly invoked Org-srs operation queues feedback."
  (let ((ems--interactive-fn-name 'org-srs-review-postpone)
        (emacsvox-org-srs--pending-result nil))
    (emacsvox-org-srs--around-suspend #'ignore)
    (should-not emacsvox-org-srs--pending-result)
    (emacsvox-org-srs--around-postpone #'ignore)
    (should (equal (plist-get emacsvox-org-srs--pending-result :event)
                   'learning-item-postponed))))

(provide 'emacsvox-org-srs-tests)
;;; emacsvox-org-srs-tests.el ends here
