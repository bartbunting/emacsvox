;;; emacsvox-aural-providers-tests.el --- Aural provider tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify effective sound-pack and voice-palette precedence independently of
;; concrete compilation and queue transport.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-providers)

(ert-deftest emacsvox-aural-providers-select-resource-pack-by-precedence ()
  "Registered sound state precedes scheme selection and fallback."
  (cl-letf
      (((symbol-function 'emacsvox-aural-resource-pack)
        (lambda (id) (and (eq id 'active-pack) id)))
       ((symbol-function 'emacsvox-aural-effective-scheme-provider)
        (lambda (property &optional _)
          (and (eq property 'resource-pack) 'scheme-pack))))
    (let* ((emacsvox-sounds-current-pack 'active-pack)
           (selection (emacsvox-aural-resource-provider-selection)))
      (should
       (equal
        (list
         (emacsvox-aural-provider-selection-id selection)
         (emacsvox-aural-provider-selection-source selection))
        '(active-pack sound-state))))
    (let* ((emacsvox-sounds-current-pack 'unregistered)
           (selection (emacsvox-aural-resource-provider-selection)))
      (should
       (equal
        (list
         (emacsvox-aural-provider-selection-id selection)
         (emacsvox-aural-provider-selection-source selection))
        '(scheme-pack scheme)))))
  (cl-letf
      (((symbol-function 'emacsvox-aural-resource-pack) #'ignore)
       ((symbol-function 'emacsvox-aural-effective-scheme-provider)
        (lambda (&rest _) nil)))
    (let* ((emacsvox-sounds-current-pack nil)
           (selection (emacsvox-aural-resource-provider-selection)))
      (should
       (equal
        (list
         (emacsvox-aural-provider-selection-id selection)
         (emacsvox-aural-provider-selection-source selection))
        '(chimes fallback))))))

(ert-deftest emacsvox-aural-providers-select-voice-palette-by-precedence ()
  "Registered voice override precedes scheme selection and fallback."
  (cl-letf
      (((symbol-function 'emacsvox-aural-voice-palette)
        (lambda (id) (and (eq id 'active-palette) id)))
       ((symbol-function 'emacsvox-aural-effective-scheme-provider)
        (lambda (property &optional _)
          (and (eq property 'voice-palette) 'scheme-palette))))
    (let* ((emacsvox-aural-voice-palette-override 'active-palette)
           (selection (emacsvox-aural-voice-provider-selection)))
      (should
       (equal
        (list
         (emacsvox-aural-provider-selection-id selection)
         (emacsvox-aural-provider-selection-source selection))
        '(active-palette explicit-override))))
    (let* ((emacsvox-aural-voice-palette-override 'unregistered)
           (selection (emacsvox-aural-voice-provider-selection)))
      (should
       (equal
        (list
         (emacsvox-aural-provider-selection-id selection)
         (emacsvox-aural-provider-selection-source selection))
        '(scheme-palette scheme)))))
  (cl-letf
      (((symbol-function 'emacsvox-aural-voice-palette) #'ignore)
       ((symbol-function 'emacsvox-aural-effective-scheme-provider)
        (lambda (&rest _) nil)))
    (let* ((emacsvox-aural-voice-palette-override nil)
           (selection (emacsvox-aural-voice-provider-selection)))
      (should
       (equal
        (list
         (emacsvox-aural-provider-selection-id selection)
         (emacsvox-aural-provider-selection-source selection))
        '(acss-default fallback))))))

(provide 'emacsvox-aural-providers-tests)
;;; emacsvox-aural-providers-tests.el ends here
