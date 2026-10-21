;;; mega-ayu-theme.el --- Ayu Dark, for a terminal  -*- lexical-binding: t; -*-

;;; Commentary:

;; Ayu Dark, as Zed ships it: a background of deep blue-black, warm grey
;; text, keywords orange, functions yellow, types blue and strings green.
;; The colours are Ayu's, by Ike Ku (https://github.com/dempfi/ayu, MIT
;; licence), taken from Zed's copy; three are Ayu's own older ones where
;; the newer would not read: the error red, the brightest text, and a
;; selection that is blue as Ayu's is but solid.
;;
;; Which face gets which of these colours is in mega-themes.el.  To use it,
;; in local.el:
;;
;;   (setq mega-theme 'mega-ayu)
;;
;; or `M-x mega-theme' to try it for a session.

;;; Code:

(require 'mega-themes)

(deftheme mega-ayu
  "Ayu Dark for the faces MEGA uses, terminal-first.")

(defconst mega-ayu-palette
  '((bg . "#0D1016") (bg1 . "#1F2127") (bg2 . "#253340") (bg3 . "#4B4C4E")
    (comment . "#5C6773")
    (fg . "#BFBDB6") (fg1 . "#CBCCCD") (fg2 . "#F3F0E6")
    (accent . "#FFB454") (keyword . "#FF8F40") (preproc . "#F29668")
    (type . "#59C2FF") (string . "#AAD94C") (constant . "#D2A6FF")
    (warning . "#E6B673") (notice . "#95E6CB") (error . "#D95757"))
  "The Ayu Dark palette.  The only place a colour of this theme is written down.")

(mega-themes-set 'mega-ayu mega-ayu-palette)

(provide-theme 'mega-ayu)
;;; mega-ayu-theme.el ends here
