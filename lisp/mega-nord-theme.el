;;; mega-nord-theme.el --- The Nord palette, for a terminal  -*- lexical-binding: t; -*-

;;; Commentary:

;; MEGA's first theme.  The palette is https://www.nordtheme.com/;
;; `comment' is Nord's own "brightened nord3", because plain nord3 is too
;; dim to read on nord0.
;;
;; Which face gets which of these colours is in mega-themes.el.  To use it,
;; in local.el:
;;
;;   (setq mega-theme 'mega-nord)
;;
;; or `M-x mega-theme' to try it for a session.

;;; Code:

(require 'mega-themes)

(deftheme mega-nord
  "The Nord palette for the faces MEGA uses, terminal-first.")

(defconst mega-nord-palette
  '((bg . "#2E3440") (bg1 . "#3B4252") (bg2 . "#434C5E") (bg3 . "#4C566A")
    (comment . "#616E88")
    (fg . "#D8DEE9") (fg1 . "#E5E9F0") (fg2 . "#ECEFF4")
    (teal . "#8FBCBB") (cyan . "#88C0D0") (blue . "#81A1C1") (deep . "#5E81AC")
    (red . "#BF616A") (orange . "#D08770") (yellow . "#EBCB8B")
    (green . "#A3BE8C") (purple . "#B48EAD"))
  "The Nord palette.  The only place a colour of this theme is written down.")

(mega-themes-set 'mega-nord mega-nord-palette)

(provide-theme 'mega-nord)
;;; mega-nord-theme.el ends here
