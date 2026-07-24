;;; emacsvox-newsticker-tests.el --- Newsticker advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'newsticker)
(load
 (expand-file-name "../lisp/emacsvox-newsticker.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(defconst emacsvox-test--newsticker-silent-targets
  '(newsticker--cache-remove newsticker--get-news-by-url-callback
    newsticker-get-news newsticker--cache-save))

(defconst emacsvox-test--newsticker-navigation-targets
  '(newsticker-next-item newsticker-previous-item
    newsticker-next-new-item newsticker-previous-new-item
    newsticker-previous-feed newsticker-next-feed))

(ert-deftest emacsvox-newsticker-advice-is-directly-registered ()
  (dolist (target emacsvox-test--newsticker-silent-targets)
    (let ((function (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :around function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-test--newsticker-navigation-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-newsticker-silent-operation-runs-once ()
  (let ((calls 0))
    (should
     (eq 'result
         (emacsvox--advice-newsticker-get-news-around
          (lambda (&rest args)
            (setq calls (1+ calls))
            (should (equal args '("feed")))
            (should-not emacsvox-speak-messages)
            'result)
          "feed")))
    (should (= calls 1))))

(ert-deftest emacsvox-newsticker-navigation-is-target-aware ()
  (let ((ems--interactive-fn-name 'newsticker-next-feed) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-newsticker-summarize-item)
               (lambda () (push 'summary events))))
      (emacsvox--advice-newsticker-previous-feed-after)
      (emacsvox--advice-newsticker-next-feed-after))
    (should (equal (nreverse events) '(large-movement summary)))))

(ert-deftest emacsvox-newsticker-omits-removed-entry-points ()
  (dolist
      (target
       '(newsticker-callback-enter newsticker-retrieval-tick
         newsticker-get-news-with-delay))
    (should-not (fboundp target))))

(provide 'emacsvox-newsticker-tests)
