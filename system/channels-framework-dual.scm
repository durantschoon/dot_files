;; system/channels-framework-dual.scm
;;
;; Pinned guix + nonguix for the Framework 13 (AMD Ryzen AI 300).
;; Resolved from channel HEAD on 2026-08-01.
;;
;; Replaces the wingolog-era (2024-02-16) pin, which predates this laptop's
;; silicon by ~5 months and therefore cannot supply its amdgpu firmware
;; (psp_14_0_4, gc_11_5_*, dcn_3_5_*).
;;
;; At this pin, nonguix's `linux' is 7.1 and `linux-lts' is 6.18. Both are well
;; past the 6.10 that gfx11.5 support requires.
;;
;; These commits are duplicated as %framework-dual-channels inside
;; framework-dual.scm, which mirrors them into /etc/guix/channels.scm on the
;; installed system.  The duplication is deliberate -- see system/README.md --
;; and `make check-channels-sync' fails if the two drift apart.
;;
;; Usage (from a checkout of this repo, on the installer ISO):
;;   guix time-machine -C system/channels-framework-dual.scm -- system init ...

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
