;; geeeks -- Framework 13 AMD (Ryzen AI 300 / Strix Point), dual-booting Pop!_OS
;; Revised 2026-08-02.
;;
;; `geeeks' is a HOST CLASS, not one particular laptop: a name for the set of
;; installs similar enough to share this config -- same silicon, same firmware,
;; same disk layout, same answer to "what does any user need here".  What belongs
;; in here is decided by the hardware and by needs every user has (it boots, it
;; reaches a network, it is secure); what one person happens to prefer belongs in
;; home/ instead.  See system/README.md for the test.
;;
;; The file name is the class name and matches (host-name "geeeks") below, which
;; `make check-system-hosts' enforces.  It is not decoration: this record
;; hardcodes disk labels, firmware and a bootloader target, and `guix system
;; reconfigure' will apply any config you hand it, so the file name is what tells
;; you which one belongs to the box you are sitting at.  Another class (a cloud
;; VM, say) gets its own system/<class>.scm beside this.
;;
;; Changes from the previously deployed /etc/config.scm:
;;
;;   1. kernel-arguments now APPENDS to %default-kernel-arguments instead of
;;      replacing it, and "nomodeset" is gone.
;;
;;      %default-kernel-arguments is (list "modprobe.blacklist=usbmouse,usbkbd"
;;      "quiet").  Replacing it dropped the usbkbd blacklist, which upstream
;;      sets because usbkbd races usbhid (bugs.gnu.org/35574).
;;
;;      "nomodeset" disabled kernel modesetting while this same config loads
;;      amdgpu and linux-firmware.  It cannot supply missing firmware; it only
;;      guarantees an unaccelerated console.
;;
;;   2. initrd-modules is now %base-initrd-modules, unmodified.
;;
;;      - "amdgpu" removed: not needed to mount root, and loading the GPU
;;        driver from the initrd also requires its firmware in the initrd,
;;        which is a second way to fail before any console exists.
;;      - "usbhid" removed: already in %base-initrd-modules.  Also irrelevant
;;        to this laptop's internal keyboard, which is i8042
;;        ("AT Translated Set 2 keyboard", IRQ 1), not USB.
;;      - "i2c_piix4" removed: SMBus for sensors, nothing to do with booting.
;;      - The (remove ...) filter on "nvme" / "xhci_pci" was a no-op: neither
;;        name appears in %base-initrd-modules (see default-initrd-modules in
;;        gnu/system/linux-initrd.scm).  Hardcoding "built into 6.6.16" is also
;;        a claim about one pinned kernel; under a newer pin it would
;;        eventually strip a module needed to mount root.
;;
;;   3. Everything else is unchanged, deliberately -- including
;;      (initrd microcode-initrd), which is correct on AMD, and the /data
;;      file-system using (flags '(no-atime)) rather than (options "noatime").
;;
;; Build with the pinned channels, NOT with the host guix:
;;   guix time-machine -C system/channels-geeeks.scm -- \
;;     system init system/geeeks.scm /mnt/guixroot

(use-modules (gnu)
             (gnu packages base)       ;glibc, for the ld.so compatibility symlink
             (gnu packages linux)
             (gnu packages shells)     ;zsh, for the declared login shell
             (gnu packages ssh)        ;openssh
             (gnu packages version-control) ;git
             (gnu services desktop)    ;%desktop-services, gnome-desktop-service-type
             (gnu services linux)      ;kernel-module-loader-service-type
             (gnu services shepherd)   ;shepherd-service, shepherd-root-service-type
             (gnu system nss)
             (guix channels)           ;channel, make-channel-introduction
             (nongnu packages linux)
             (nongnu system linux-initrd)
             (srfi srfi-1))

;; Channels pinned 2026-08-01, mirrored from the installer into this system.
;; The guix service writes these to /etc/guix/channels.scm at activation.
;;
;; Named %system-channels rather than %geeeks-channels so every host class config
;; in system/ uses the same identifier: `make check-channels-sync' is then one
;; loop over system/*.scm pairing each with its system/channels-<class>.scm,
;; instead of a pattern that has to be edited for every new class.
(define %system-channels
  (list (channel
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
            "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))))

;; The nonguix substitute server's signing key, verbatim from
;; https://substitutes.nonguix.org/signing-key.pub -- embedded rather than
;; fetched so the config evaluates on a machine with no network yet.
(define %nonguix-signing-key
  (plain-file "nonguix.pub"
              "(public-key
 (ecc
  (curve Ed25519)
  (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)
  )
 )"))

;; Pop!_OS chainload entry, emitted only when Pop!_OS is actually installed.
;;
;; Decided at CONFIG EVALUATION time, not at boot: `file-exists?' runs on
;; whichever machine is evaluating this file, so the ESP has to be reachable
;; from here.  That is two different paths depending on when you run:
;;
;;   /boot/efi                  a running, installed system (guix system reconfigure)
;;   /mnt/guixroot/boot/efi     the installer, mid `guix system init'
;;
;; so both are probed.  Getting it wrong is cosmetic rather than fatal -- a
;; stale entry only makes GRUB report "file not found" when you pick it -- but
;; a Framework WITHOUT Pop!_OS should not advertise a Pop!_OS entry at all.
;;
;; The check FAILS OPEN, and the distinction is not academic.  An ESP is vfat
;; mounted umask=0077, so only root can stat anything under it -- `file-exists?'
;; answers #f for "not there" and for "you may not look" alike.  reconfigure and
;; init both run as root and see the truth, but a user-level `guix system build'
;; does not, and would quietly produce a system with no way back to Pop!_OS from
;; GRUB.  So three states, not two: present and unknown both keep the entry,
;; only a definite ENOENT drops it.  A spurious entry costs a "file not found"
;; at the GRUB prompt; a missing one costs the boot menu route to your other OS.
;; keyd: Caps<->Control swap, and nothing else.  Inlined rather than read from
;; ~/dot_files/keyd.conf: a system config that reaches into a user's home to
;; build cannot be evaluated by root during `guix system init', and would
;; silently change meaning if the checkout moved.  Keep this in sync by hand
;; with dot_files/keyd.conf, which carries the same content and the long-form
;; version of the note below.
(define %keyd-config
  (plain-file "keyd-default.conf"
              "[ids]
*

[main]
# Swap CapsLock and Control.  \"capslock = control\" is NOT valid keyd --
# 2.6 skips the line (\"invalid key or action\"), which is how Control got
# lost entirely on first rollout: only the reverse mapping applied.
# layer(control) makes held CapsLock a real Control.
capslock = layer(control)
leftcontrol = capslock

# NO [control:C] Emacs layer here, deliberately.
#
# There used to be one (n/p/f/b -> arrows, a/e -> home/end, h -> backspace,
# d -> delete, k -> S-end).  keyd rewrites keys at the evdev level, below
# the compositor and below every application, so a C-f consumed here is not
# \"C-f plus a helpful default\" -- the control character never exists, and
# nothing downstream can recover it.  That cost C-x C-f in Emacs, rang the
# terminal bell on C-a, and took out the C-h help prefix, C-d and C-k.
#
# It was redundant besides: Emacs and readline implement all of those
# natively, and GTK applications get them from gtk-key-theme=Emacs, which
# guix home sets in emacs-keybindings-activation.
"))

(define %popos-boot-loader "/EFI/systemd/systemd-bootx64.efi")

(define %esp-mount-candidates
  '("/boot/efi" "/mnt/guixroot/boot/efi" "/mnt/boot/efi"))

(define (popos-loader-state esp)
  "Return 'present, 'absent, or 'unknown for the Pop!_OS loader under ESP."
  (catch 'system-error
    (lambda ()
      (stat (string-append esp %popos-boot-loader))
      'present)
    (lambda args
      (if (= (system-error-errno args) ENOENT) 'absent 'unknown))))

(define %popos-menu-entries
  (let ((states (map popos-loader-state %esp-mount-candidates)))
    (cond
     ((memq 'present states)
      (list (menu-entry
             (label "Pop!_OS 24.04 LTS")
             ;; The ESP is matched by LABEL, not device path: partition
             ;; numbering on a dual-boot disk is whatever the other OS's
             ;; installer left behind.  GRUB renders this as `search --label'
             ;; followed by `chainloader'.
             (device (file-system-label "EFI"))
             (chain-loader %popos-boot-loader))))
     ((memq 'unknown states)
      (format (current-error-port)
              "note: cannot read the ESP (run as root to check); keeping the Pop!_OS entry~%")
      (list (menu-entry
             (label "Pop!_OS 24.04 LTS")
             (device (file-system-label "EFI"))
             (chain-loader %popos-boot-loader))))
     (else
      (format (current-error-port)
              "note: no Pop!_OS boot loader under ~a; omitting its GRUB entry~%"
              %esp-mount-candidates)
      '()))))

(operating-system
 (host-name "geeeks")
 (timezone "America/New_York")
 (locale "en_US.utf8")

 (keyboard-layout
  (keyboard-layout "us"
                   #:options '("ctrl:swapcaps")))

 ;; Linux kernel with proprietary firmware support (from nonguix).
 ;; At the pinned nonguix commit this is 7.1, well past the 6.10 that
 ;; gfx11.5 (Radeon 890M, 1002:1114) support requires.
 (kernel linux)
 (initrd microcode-initrd)
 (firmware (list linux-firmware))

 ;; The initrd only has to mount root; udev loads everything else once the
 ;; real system is up.  See note 2 in the header.
 (initrd-modules %base-initrd-modules)

 ;; APPEND, never replace.  See note 1 in the header.
 (kernel-arguments (append '("loglevel=3") %default-kernel-arguments))

 (bootloader
  (bootloader-configuration
   (bootloader grub-efi-bootloader)
   (targets '("/boot/efi"))
   (timeout 5)
   ;; Chainload Pop!_OS's systemd-boot from Guix's GRUB, so switching back does
   ;; not require the firmware boot menu.  Guix and Pop!_OS live in separate
   ;; directories on the one shared ESP (\EFI\Guix\ and \EFI\systemd\), so this
   ;; just hands control to the other bootloader; it does not modify it.
   ;;
   ;; Conditional on Pop!_OS actually being present -- see %popos-menu-entries
   ;; above.  On a machine without it this is the empty list and GRUB shows
   ;; only the Guix generations.
   (menu-entries %popos-menu-entries)))

 (file-systems
  (cons* (file-system
          (mount-point "/")
          (device (file-system-label "GUIX_ROOT"))
          (type "ext4"))
         (file-system
          (mount-point "/boot/efi")
          (device (file-system-label "EFI"))
          (type "vfat"))
         (file-system
          (mount-point "/data")
          (device (file-system-label "DATA"))
          (type "ext4")
          ;; no-atime belongs in flags (mount(2) bits), never in options
          ;; (filesystem-specific data string).  "ext4: Unknown parameter
          ;; 'noatime'" makes file-system-/data fail, which fails the
          ;; file-systems target, which means no login ttys at all.
          (flags '(no-atime)))
         %base-file-systems))

 (users (cons* (user-account
                (name "durant")
                (comment "Durant Schoon")
                (group "users")
                (home-directory "/home/durant")
                (supplementary-groups '("wheel" "netdev"))
                ;; There is deliberately no (password ...) here.
                ;;
                ;; The field exists, defaults to #f, and setting it is the
                ;; obvious-looking way to make the account reproducible.  Do
                ;; not.  Whatever you put there is spliced verbatim into an
                ;; activation gexp -- (gnu system shadow), user-account->gexp --
                ;; which means it is materialised in /gnu/store.  The store is
                ;; world-readable, so the hash is legible to every local user on
                ;; this machine no matter who can read the git history.  Making
                ;; this repo private would not help.
                ;;
                ;; The idiom you will find in examples is worse than it looks:
                ;;
                ;;   (password (crypt "hunter2" "$6$somesalt"))
                ;;
                ;; `crypt' runs when the CONFIG is evaluated, so that form keeps
                ;; your plaintext password in this file, in git, forever.  (Note
                ;; the field is `password'; `hashed-password' is NixOS's name
                ;; and does nothing here.)
                ;;
                ;; Set it with `passwd' on the machine instead.  One command,
                ;; once, and nothing to leak.  `make check-system-secrets'
                ;; enforces this; system/README.md lists the same treatment for
                ;; wifi PSKs and private keys.
                ;; The login shell is a SYSTEM setting, declared here -- not
                ;; something guix home or chsh can provide.
                ;;
                ;; guix home installs zsh into ~/.guix-home/profile and writes
                ;; its config, but /etc/passwd still says bash until this field
                ;; changes it, so every login ignores that config.  And chsh is
                ;; futile on Guix: user accounts are regenerated from this
                ;; declaration on each reconfigure, which reverts any imperative
                ;; edit.
                ;;
                ;; file-append pulls zsh into the SYSTEM closure, so the shell
                ;; binary exists from first boot -- before guix home has ever
                ;; run.  Order matters on a fresh install: were the login shell
                ;; only present in the home profile, the account would briefly
                ;; point at a shell that does not exist yet.
                ;;
                ;; A user preferring a different shell changes this one field
                ;; (bash users delete it -- bash is the default and already in
                ;; %base-packages).
                (shell (file-append zsh "/bin/zsh")))
               %base-user-accounts))

 ;; Minimal packages, plus the two omissions that strand a fresh install.
 ;;
 ;; %base-packages is %base-packages-interactive + -linux + -networking +
 ;; -utils, and the networking set is exactly (inetutils isc-dhcp iproute wget
 ;; nss-certs iw wireless-tools).  It contains NEITHER git NOR openssh --
 ;; inetutils supplies telnet and ftp, not ssh.  A freshly booted system
 ;; therefore cannot clone a dotfiles repo over SSH, which is the first thing
 ;; you actually want to do, and the only way out is `guix install'.
 ;;
 ;; These belong in the SYSTEM profile rather than a user profile because the
 ;; user profile does not exist yet at that point: on this setup the user
 ;; profile is built by `guix home', from a repo that has to be cloned first.
 ;; Putting them here also keeps them available to root and in a rescue shell.
 ;;
 ;; gnu-make is the third omission: %base-packages has no make, and the very
 ;; first thing the dotfiles workflow runs on a fresh system is `make apply'.
 ;; (zsh is NOT needed here -- the login shell's file-append above already
 ;; pulls it into the system closure.)
 ;;
 ;; Everything else stays out; `guix home' owns the user-level package set.
 (packages (append (list git openssh gnu-make) %base-packages))

 ;; Desktop services: GNOME on Wayland, plus networking.
 ;;
 ;; This machine's only network interface is a MediaTek MT7925 wireless card
 ;; (14c3:0717, driver mt7925e).  There is no built-in ethernet -- Framework 13
 ;; uses expansion cards -- so without WiFi the installed system has no network
 ;; at all and cannot even guix pull to repair itself.
 ;;
 ;; NetworkManager, wpa-supplicant, dbus-root, polkit and ntp are NOT listed
 ;; below because %desktop-services already supplies all five.  Both directions
 ;; here are real errors, so the reason is worth recording:
 ;;
 ;;   on %base-services  they MUST be declared.  %base-services provides only
 ;;                      loopback and instantiates neither dbus nor polkit,
 ;;                      while network-manager-service-type declares
 ;;                      service-extensions onto both -- Guix aborts with
 ;;                      "no target of type ...".  That was this config's
 ;;                      previous shape.
 ;;   on %desktop-services declaring them again produces duplicate service
 ;;                      instances and the reconfigure fails.
 ;;
 ;; So do not let postinstall/customize option 2 do this conversion: it runs a
 ;; global sed, s|%base-services|%desktop-services|g, which rewrites the prose
 ;; in these comments as well as the code, and leaves the five duplicates in
 ;; place.
 ;;
 ;; gdm is in %desktop-services too, and gdm-configuration defaults to
 ;; (wayland? #t), so GNOME comes up as a Wayland session.  To force X11:
 ;;   (modify-services %desktop-services
 ;;     (gdm-service-type config => (gdm-configuration
 ;;                                  (inherit config) (wayland? #f))))
 ;;
 ;; The mt7925e driver does not exist before Linux 6.7, which is why the
 ;; previously installed 6.6.16 system had no wireless driver at all.  Its
 ;; firmware (mediatek/mt7925/*) comes from nonguix's linux-firmware, declared
 ;; above.
 ;;
 ;; After booting: log in on tty1, then run `nmtui' (curses UI, works on a
 ;; plain console) or:
 ;;   nmcli device wifi list
 ;;   nmcli device wifi connect "SSID" password "..."
 ;; nmcli/nmtui land on PATH automatically -- the service extends
 ;; profile-service-type.
 ;;
 ;; The guix service is reconfigured rather than taken as-is:
 ;;
 ;;   channels        Neither %base-services nor %desktop-services carries a
 ;;                   channel list, so the installed
 ;;                   system knows only the "guix" channel.  Reconfiguring this
 ;;                   very config then fails with "no code for module
 ;;                   (nongnu packages linux)" -- observed on this laptop
 ;;                   2026-08-02 -- and a bare "guix pull" would abandon the
 ;;                   pin and jump to HEAD.
 ;;   substitute-urls Authorizing a key and querying a server are two different
 ;;                   settings.  %default-substitute-urls omits nonguix, so
 ;;                   with the key alone guix never asks and just compiles
 ;;                   Linux from source.
 (services
  (append
   (list (service gnome-desktop-service-type)

         ;; keyd, as a SYSTEM service.
         ;;
         ;; It cannot be a guix home service: keyd reads /dev/input/event* and
         ;; writes /dev/uinput, both root-only.  That is also why the Makefile's
         ;; `make setup-keyd' target refuses on Guix instead of symlinking a
         ;; user-profile binary into /usr/local/bin -- which does not exist here
         ;; anyway, any more than systemctl or /etc/systemd/system do.
         ;;
         ;; Guix packages keyd (2.6.0) but ships no keyd-service-type, so the
         ;; shepherd service is written out by hand.
         ;;
         ;; uinput is what keyd creates its virtual keyboard through.  Requiring
         ;; kernel-module-loader (one-shot, itself requiring udev) is what keeps
         ;; keyd from starting before the module is in.
         (service kernel-module-loader-service-type '("uinput"))

         (simple-service 'keyd-config etc-service-type
                         (list `("keyd/default.conf" ,%keyd-config)))

         (simple-service
          'keyd-daemon shepherd-root-service-type
          (list (shepherd-service
                 (provision '(keyd))
                 (requirement '(udev kernel-module-loader))
                 (documentation "keyd key remapping daemon.")
                 ;; keyd runs in the foreground -- the systemd unit this
                 ;; replaces was Type=simple -- so forkexec is correct.
                 (start #~(make-forkexec-constructor
                           (list #$(file-append keyd "/bin/keyd"))))
                 (stop #~(make-kill-destructor))
                 ;; Matches the old unit's Restart=always.  Shepherd throttles
                 ;; and then disables a service that respawns too fast, so a
                 ;; broken config cannot become a tight crash loop.
                 (respawn? #t)
                 ;; DELIBERATELY NOT auto-started on the first deploy.
                 ;;
                 ;; keyd grabs the physical keyboard and re-emits through a
                 ;; virtual device; if that goes wrong you have no console
                 ;; input, at boot, with no way to type a rollback.  This
                 ;; machine has already lost its internal keyboard once (the
                 ;; noapic/nolapic episode, docs/FRAMEWORK_STARTUP_HANG_FIX.md)
                 ;; and it is an i8042 device either way.
                 ;;
                 ;; So: reconfigure, then `sudo herd start keyd', confirm Caps
                 ;; acts as Control and Control-n/p/f/b move the cursor, and
                 ;; only then set this to #t and reconfigure again.  Leaving it
                 ;; #f costs one command per boot; getting it wrong costs the
                 ;; keyboard.
                 (auto-start? #f))))

         ;; The FHS dynamic loader, as one symlink.
         ;;
         ;; Guix has no /lib64, so a generic x86-64 Linux binary cannot be
         ;; exec'd at all: the kernel reads the ELF INTERP header, looks for
         ;; /lib64/ld-linux-x86-64.so.2, finds nothing, and the exec fails
         ;; before any of the program's own code runs.  The error surfaces as
         ;; a bare "No such file or directory" naming the binary that plainly
         ;; does exist, which is why it is worth annotating here.
         ;;
         ;; Claude Code's native build is exactly such a binary
         ;; (~/.local/share/claude/versions/<v>, INTERP
         ;; /lib64/ld-linux-x86-64.so.2, needing libc/librt/libpthread/libdl/libm).
         ;;
         ;; Only the loader needs the symlink.  Guix's own ld.so has its store
         ;; library directory compiled in as the default search path, so the
         ;; libraries above resolve out of /gnu/store -- no /lib, no
         ;; LD_LIBRARY_PATH, no copies of glibc outside the store.  glibc >= 2.34
         ;; also keeps librt/libpthread/libdl as stubs, so binaries linked
         ;; against the pre-2.34 split still resolve.
         ;;
         ;; This is a general escape hatch, not a Claude-specific one: it makes
         ;; ANY generic Linux binary runnable, which is a deliberate loosening
         ;; of Guix's usual guarantee that nothing outside the store is
         ;; required.  Consistent with this platform already depending on
         ;; nonguix for firmware, but worth stating rather than smuggling in.
         ;;
         ;; Alternatives, both rejected for daily use:
         ;;   guix shell --container --emulate-fhs -- ...
         ;;       no system change, but wraps every single invocation
         ;;   patchelf --set-interpreter ...
         ;;       rewrites the binary in place, so Claude Code's auto-updater
         ;;       silently un-patches it on the next release
         (extra-special-file "/lib64/ld-linux-x86-64.so.2"
                             (file-append glibc "/lib/ld-linux-x86-64.so.2")))
   (modify-services %desktop-services
     (guix-service-type
      config => (guix-configuration
                 (inherit config)
                 (channels %system-channels)
                 (substitute-urls
                  (cons "https://substitutes.nonguix.org"
                        %default-substitute-urls))
                 (authorized-keys
                  (cons %nonguix-signing-key
                        %default-authorized-guix-keys))))))))
