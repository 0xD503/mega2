;;; mega-hacker-theme.el --- Green on black, as a terminal was  -*- lexical-binding: t; -*-

;;; Commentary:

;; A dark theme after the green screens: a background that is all but black,
;; text in the green of phosphor, and what stands out from it bright.  The
;; colours are MEGA's own.  They are chosen by measure as well as by eye:
;; against the background every colour that text is written in has a
;; contrast of 4.5 to 1 or more, which a test checks.
;;
;; Which face gets which of these colours is in mega-themes.el.  To use it,
;; in local.el:
;;
;;   (setq mega-theme 'mega-hacker)
;;
;; or `M-x mega-theme' to try it for a session.

;;; Code:

(require 'mega-themes)

(deftheme mega-hacker
  "Green on black for the faces MEGA uses, terminal-first.")

(defconst mega-hacker-palette
  '((bg . "#0A0F0C") (bg1 . "#15231B") (bg2 . "#1F3327") (bg3 . "#2C4435")
    (comment . "#668A71")
    (fg . "#A6E3B4") (fg1 . "#C6F2CF") (fg2 . "#E4FFEA")
    (teal . "#35D6A8") (cyan . "#4FE3F2") (blue . "#5DB2FF") (deep . "#3A8FC4")
    (red . "#EE3F55") (orange . "#FF9E42") (yellow . "#FFD34E")
    (green . "#4DFF88") (purple . "#D391FF"))
  "The palette.  The only place a colour of this theme is written down.")

(mega-themes-set 'mega-hacker mega-hacker-palette)

(provide-theme 'mega-hacker)
;;; mega-hacker-theme.el ends here
