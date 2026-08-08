;; channels.scm -- the pin `make apply' / `make apply-wayland' pull before
;; reconfiguring guix home.  The HOME side; the system side pins separately in
;; system/channels-<class>.scm, and the two are deliberately not required to
;; match (this file is pulled by the user, that one by root at install time).
;;
;; nonguix is here for exactly one package: firefox.
;;
;; Guix proper cannot ship Firefox -- Mozilla's trademark policy keeps the
;; branded build out -- so the packaged alternatives are librewolf and icecat.
;; Both were tried and both have a disqualifying problem for this user:
;; icecat's LibreJS blocks the nonfree JavaScript claude.ai is built from, and
;; librewolf keeps its profiles in ~/.librewolf rather than ~/.mozilla/firefox
;; while defaulting privacy.resistFingerprinting to #t, which breaks the QR
;; code on 1Password's web sign-in.  The years of configured Firefox profiles
;; on this machine's other OS are the deciding factor: nonguix's firefox reads
;; them from the standard path, unmodified.
;;
;; A SUBSTITUTE WARNING, because getting this wrong costs hours.  Declaring the
;; channel is what makes the package RESOLVE; it is not what makes it
;; DOWNLOADABLE.  The daemon needs nonguix's substitute URL and its signing key
;; authorised, or it will cheerfully build Firefox from source.  On this Guix
;; System box that is already done -- system/geeeks.scm sets both on
;; guix-service-type -- but it is a property of the MACHINE, not of this file.
;;
;; That is why "firefox" is declared in home/wayland.scm and NOT in
;; home/base.scm.  base.scm is the foreign-distro config, whose daemon has
;; neither the URL nor the key.  check-home-sync verifies base SUBSET-OF
;; wayland precisely so wayland-only additions like this one are legal.

;; CHANNEL COMMITS ARE PAIRED, NOT INDEPENDENT.
;;
;; This file used to pin guix to codeberg 17c2142 alone, which was fine while
;; guix was the only channel.  Adding nonguix at 73baab3 to that commit does not
;; build:
;;
;;   building /gnu/store/...-nonguix.drv...
;;   (exception unbound-variable ... (value (linux-libre-7.1)))
;;
;; nonguix references `linux-libre-7.1', which that guix no longer defines.  A
;; channel is Scheme compiled against the guix it is paired with, so the two
;; commits are a matched pair and bumping one can break the other.
;;
;; So both commits below are the pair ALREADY PROVEN on this machine: it is what
;; root's guix runs, and what built the running system.  Verify with
;; `sudo -i guix describe'.  It also makes the home and system halves agree on
;; one guix commit, which they previously did not.
;;
;; The cost is that this is a DOWNGRADE for an existing user guix pulled from
;; codeberg -- `make apply' already passes --allow-downgrades, so it proceeds.
;;
;; If you bump either commit, bump them together and actually build:
;;   guix time-machine -C channels.scm -- show firefox
(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master")
  (commit "df2d121208127ac22f10e0f7c2f38d6c74e106a3")
  (introduction
   (make-channel-introduction
    "9edb3f66fd807b096b48283debdcddccfea34bad"
    (openpgp-fingerprint
     "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (branch "master")
  (commit "73baab37361b3a81f326aa3fdec78840f5acc577")
  (introduction
   (make-channel-introduction
    "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
    (openpgp-fingerprint
     "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5")))))
