;;; emacsvox-muggle-outliner.el --- Outline navigation Muggle -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop muggles
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Independently loadable Outline navigation, without installing entry keys.
;; Deliberate entry enables Outline minor mode.  Exit preserves it and folds.
;;; Code:
(require 'hydra)
(require 'emacsvox-hydra)
(require 'outline)
(require 'emacsvox-outline)

;; Cloned from Hydra Wiki.
(defhydra emacsvox-muggles-outliner
          (:body-pre
           (progn
             (outline-minor-mode 1)
             (emacsvox-hydra-body-pre "Outline Navigation"))
           :pre emacsvox-hydra-pre :post emacsvox-hydra-post
           :color pink :hint nil)
          "
^Hide^             ^Show^           ^Move
^^^^^^------------------------------------------------------
_q_: sublevels     _a_: all         _u_: up
_t_: body          _e_: entry       _n_: next visible
_o_: other         _i_: children    _p_: previous visible
_c_: entry         _k_: branches    _f_: forward same level
_l_: leaves        _s_: subtree     _b_: backward same level
_d_: subtree

"
          ("?" (emacsvox-hydra-self-help "emacsvox-muggles-outliner"))
          ;; Hide
          ("q" outline-hide-sublevels)
          ("t" outline-hide-body)
          ("o" outline-hide-other)             ; Hide other branches
          ("c" outline-hide-entry)             ; Hide this entry's body
          ("l" outline-hide-leaves)
          ("d" outline-hide-subtree)
          ;; Show
          ("a" outline-show-all)               ; Show (expand) everything
          ("e" outline-show-entry)             ; Show this heading's body
          ("i" outline-show-children)
          ("k" outline-show-branches)
          ("s" outline-show-subtree)
          ;; Move
          ("u" outline-up-heading)               ; Up
          ("n" outline-next-visible-heading)     ; Next
          ("p" outline-previous-visible-heading) ; Previous
          ("f" outline-forward-same-level)       ; Forward - same level
          ("b" outline-backward-same-level)      ; Backward - same level
          ("z" nil "leave"))
(provide 'emacsvox-muggle-outliner)
;;; emacsvox-muggle-outliner.el ends here
