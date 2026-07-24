;;; emacsvox-net-utils-tests.el --- Net Utils advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Net Utils advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-net-utils.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--net-utils-after-advice
  '((arp emacsvox--advice-arp-after)
    (route emacsvox--advice-route-after)
    (traceroute emacsvox--advice-traceroute-after)
    (ifconfig emacsvox--advice-ifconfig-after)
    (iwconfig emacsvox--advice-iwconfig-after)
    (ping emacsvox--advice-ping-after)
    (netstat emacsvox--advice-netstat-after)
    (dns-lookup-host emacsvox--advice-dns-lookup-host-after)
    (nslookup-host emacsvox--advice-nslookup-host-after))
  "Native after-advice registrations in the Net Utils integration.")

(ert-deftest emacsvox-net-utils-advice-is-directly-registered ()
  "Net Utils advice uses native advice directly."
  (dolist (entry emacsvox-test--net-utils-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-net-utils-feedback-is-target-aware ()
  "Only the matching network command announces its displayed results."
  (let ((ems--interactive-fn-name 'ping)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) events))))
      (emacsvox--advice-traceroute-after)
      (emacsvox--advice-ping-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        "Displayed results of ping in other window")))))

(provide 'emacsvox-net-utils-tests)
;;; emacsvox-net-utils-tests.el ends here
