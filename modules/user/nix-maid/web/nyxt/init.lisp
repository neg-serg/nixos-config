;; Nyxt init (HM-managed). Safe defaults + Vim-friendly tweaks.
(in-package :nyxt-user)

;; Use vi-normal-mode by default
(define-configuration nyxt:buffer
  ((default-modes (cons 'nyxt/vi-mode:vi-normal-mode %slot-default%))))

;; Minimal UI/UX tweaks
(define-configuration nyxt:buffer
  ((download-directory #p"@DL_DIR@/")
   (confirm-before-quit :always-ask)))

;; Custom Dark Theme (Kitty/Neovim 'neg' palette)
;; (define-configuration browser
;;   ((theme (nyxt/theme:make-theme
;;            :dark-p t
;;            :background-color "#000000"
;;            :on-background-color "#6C7E96"
;;            :accent-color "#367bbf"
;;            :on-accent-color "#000000"
;;            :primary-color "#0d1824"
;;            :on-primary-color "#6C7E96"
;;            :secondary-color "#0d1824"
;;            :on-secondary-color "#6C7E96"
;;            :warning-color "#8A2F58"
;;            :on-warning-color "#000000"))))

;; Add a few vi-like bindings (t: new tab, x: close, H/L: history)
;; Wrapped defensively to avoid breaking on missing symbols between Nyxt versions.
(handler-case
  (progn
    (define-configuration nyxt/vi-mode:vi-normal-mode
      ((keymap
         (let ((map %slot-default%))
           (when (fboundp 'nyxt:make-buffer)
             (define-key map "t" 'nyxt:make-buffer))
           (when (fboundp 'nyxt:delete-buffer)
             (define-key map "x" 'nyxt:delete-buffer))
           (when (fboundp 'nyxt:list-buffers)
             (define-key map "T" 'nyxt:list-buffers))
           (when (fboundp 'nyxt:history-backwards)
             (define-key map "H" 'nyxt:history-backwards))
           (when (fboundp 'nyxt:history-forwards)
             (define-key map "L" 'nyxt:history-forwards))
           (when (fboundp 'nyxt:reload-current-buffer)
             (define-key map "r" 'nyxt:reload-current-buffer))
           
           ;; Navigation (hjkl, gg, G)
           (when (fboundp 'nyxt:scroll-left)
             (define-key map "h" 'nyxt:scroll-left))
           (when (fboundp 'nyxt:scroll-down)
             (define-key map "j" 'nyxt:scroll-down))
           (when (fboundp 'nyxt:scroll-up)
             (define-key map "k" 'nyxt:scroll-up))
           (when (fboundp 'nyxt:scroll-right)
             (define-key map "l" 'nyxt:scroll-right))
           (when (fboundp 'nyxt:scroll-to-top)
             (define-key map "g g" 'nyxt:scroll-to-top))
           (when (fboundp 'nyxt:scroll-to-bottom)
             (define-key map "G" 'nyxt:scroll-to-bottom))

           ;; Hints and Search
           (when (fboundp 'nyxt/mode/hint:follow-hint)
             (define-key map "f" 'nyxt/mode/hint:follow-hint))
           (when (fboundp 'nyxt/mode/hint:follow-hint-new-buffer)
             (define-key map "F" 'nyxt/mode/hint:follow-hint-new-buffer))
           (when (fboundp 'nyxt/mode/search-buffer:search-buffer)
             (define-key map "/" 'nyxt/mode/search-buffer:search-buffer))

           ;; Tabs and Buffers
           (when (fboundp 'nyxt:delete-buffer)
             (define-key map "d" 'nyxt:delete-buffer))
           (when (fboundp 'nyxt:reopen-buffer)
             (define-key map "u" 'nyxt:reopen-buffer))
           (when (fboundp 'nyxt:switch-buffer)
             (define-key map "b" 'nyxt:switch-buffer))

           ;; Clipboard
           (when (fboundp 'nyxt:copy-url)
             (define-key map "y y" 'nyxt:copy-url))
           (when (fboundp 'nyxt:paste-url)
             (define-key map "p" 'nyxt:paste-url))
           
           map))))
  (error (c)
    (declare (ignore c))
    ;; Ignore keybinding errors to keep startup resilient.
    nil))
