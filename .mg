# mg -- normal startup file (~/.mg).  Read at startup; one interactive command
# per line, exactly as you would type them.  Comments start with ; or #.
#
# Keep mg's foo~ backups out of the working tree.  Without this, mg writes the
# backup next to the file, which is what litters checkouts with foo~ and what
# `clean' in .aliases exists to sweep.  With it, backups go to ~/.mg.d instead,
# keeping their full path names inside that directory so two files with the
# same basename cannot collide.
#
# Requires make-backup-files to stay on (it is, by default) -- this redirects
# backups rather than disabling them, so the safety net is still there.
#
# Emacs proper needs no equivalent here: .spacemacs.d's init.el already sets
# backup-directory-alist to ~/.emacs_backups.
backup-to-home-directory
