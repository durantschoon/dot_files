# Guix Home is the primary workflow; native symlink setup is opt-in.
.DEFAULT_GOAL := apply

# Detect OS (modified from example https://stackoverflow.com/a/12099167)

OS_WINDOWS := windows
OS_MAC := mac
OS_LINUX := linux
OS_UNKNOWN := unknown
os := $(OS_UNKNOWN)

ARCH_X86 := x86
ARCH_AMD64 := amd64
ARCH_ARM := arm
ARCH_UNKNOWN := unknown
arch := $(ARCH_UNKNOWN)

FLAVOR_WSL := ubuntu # not currently used, but maybe someday?
FLAVOR_WSL := wsl
FLAVOR_UNKNOWN := unknown
flavor := $(FLAVOR_UNKNOWN)

PWD_CMD := pwd
WHICH_CMD := which

POWERLINE_FONT := 'Meslo LG'

ifeq ($(OS),Windows_NT)
	os := $(OS_WINDOWS)
	PWD_CMD := cd
	WHICH_CMD := where
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
		os := $(OS_LINUX)
    endif
    ifeq ($(UNAME_S),Darwin)
		os := $(OS_MAC)
    endif
    UNAME_P := $(shell uname -p)
    ifeq ($(UNAME_P),x86_64)
		arch := $(ARCH_AMD64)
    endif
    ifneq ($(filter %86,$(UNAME_P)),)
		arch := $(ARCH_X86)
    endif
    ifneq ($(filter arm%,$(UNAME_P)),)
		arch := $(ARCH_ARM)
    endif
endif

# families of OS'es will run the same commands
# this value will be blank if the detected OS isn't in the list
unix_family := $(filter $(os),$(OS_LINUX) $(OS_MAC))

MICROSOFT_CHECK := $(shell grep -i Microsoft /proc/version 2>/dev/null)
ifneq ($(MICROSOFT_CHECK),)
	flavor := $(FLAVOR_WSL)
	wsl_home := /home/durant
	HOME = $(wsl_home)
endif

ORBSTACK_CHECK := $(shell grep -i orbstack /proc/version 2>/dev/null)
ifneq ($(ORBSTACK_CHECK),)
	flavor := orbstack
endif

# The OrbStack foreign container runs guix-daemon with --disable-chroot.  Guix
# grafts then try to rewrite read-only store outputs in place and can leave a
# registered, unusable output after interruption.  The pinned foreign session
# uses the exact channel revisions, so skip grafts there; native Guix System
# sessions retain the default graft behavior.
GUIX_HOME_GRAFT_FLAGS :=
ifeq ($(flavor),orbstack)
	GUIX_HOME_GRAFT_FLAGS := --no-grafts
endif

# OrbStack is the macOS Docker provider; WSL uses Docker Desktop's default
# context (or a Docker Engine configured in WSL). Override this variable when
# a host uses another named context.
GUIX_DOCKER_CONTEXT ?= $(if $(filter $(OS_MAC),$(os)),orbstack,default)
GUIX_DOCKER_CONTEXT_ARG := $(if $(filter default,$(GUIX_DOCKER_CONTEXT)),,--context $(GUIX_DOCKER_CONTEXT))
GUIX_DOCKER := docker $(GUIX_DOCKER_CONTEXT_ARG)

# Detect package manager
PACKAGE_MANAGER := unknown
# brew is checked FIRST, not last: these are plain assignments, so the LAST
# matching branch wins. On a Linux box with linuxbrew alongside apt/yum/etc,
# the native manager below should win; on macOS nothing below matches, so brew
# survives. Without this, macOS reported "unknown" in `make help`.
ifneq ($(shell which brew 2>/dev/null),)
	PACKAGE_MANAGER := brew
endif
ifneq ($(shell which guix 2>/dev/null),)
	PACKAGE_MANAGER := guix
endif
ifneq ($(shell which apt-get 2>/dev/null),)
	PACKAGE_MANAGER := apt
endif
ifneq ($(shell which yum 2>/dev/null),)
	PACKAGE_MANAGER := yum
endif
ifneq ($(shell which pacman 2>/dev/null),)
	PACKAGE_MANAGER := pacman
endif

# Detect the login shell from the account database rather than $$SHELL, which
# make overwrites for its own recipes. Used by the emacs-env target.
LOGIN_USER := $(shell id -un)
LOGIN_SHELL := $(shell getent passwd "$$(id -un)" 2>/dev/null | cut -d: -f7)
ifeq ($(LOGIN_SHELL),)
	# macOS has no getent
	LOGIN_SHELL := $(shell dscl . -read /Users/$$(id -un) UserShell 2>/dev/null | awk '{print $$2}')
endif
ifeq ($(LOGIN_SHELL),)
	LOGIN_SHELL := /bin/zsh
endif

.PHONY: all setup-native set_up_links wsl help guix-root-install warn-dotfiles-home guard-native-over-guix

# Makefile and set_up_links assume the repo is at $(HOME)/dot_files (symlink is fine).
DOTFILES_HOME := $(HOME)/dot_files

warn-dotfiles-home:
	@dfhome="$(DOTFILES_HOME)"; \
	here="$$(pwd -P 2>/dev/null || pwd)"; \
	if [ ! -e "$$dfhome" ]; then \
	  if [ "$(flavor)" = "orbstack" ] && [[ "$$here" == /Users/* ]]; then \
	    echo "OrbStack detected: Linking $$dfhome -> $$here"; \
	    ln -snf "$$here" "$$dfhome"; \
	  else \
	    echo ""; \
	    echo "  *** dot_files: $$dfhome does not exist ***"; \
	    echo "  Put this repo there (clone or symlink), e.g.:"; \
	    echo "    ln -s $$(pwd) $$dfhome"; \
	    echo "  Then run make from $$dfhome so Guix Home paths and links match."; \
	    echo ""; \
	  fi; \
	else \
	  exp="$$(cd "$$dfhome" 2>/dev/null && pwd -P)"; \
	  if [ -n "$$exp" ] && [ "$$exp" != "$$here" ]; then \
	    if [ "$(flavor)" = "orbstack" ] && [[ "$$here" == /Users/* ]]; then \
	      if [ ! -L "$$dfhome" ] && [ -d "$$dfhome" ]; then \
	        echo "OrbStack detected: You are in $$here but $$dfhome exists as a directory."; \
	        echo "Consider replacing it with a symlink:"; \
	        echo "  rm -rf $$dfhome && ln -s $$here $$dfhome"; \
	      else \
	        echo "OrbStack detected: Updating link $$dfhome -> $$here"; \
	        ln -snf "$$here" "$$dfhome"; \
	      fi; \
	    else \
	      echo ""; \
	      echo "  *** dot_files: not in $$dfhome ***"; \
	      echo "  Current directory (resolved): $$here"; \
	      echo "  Expected (resolved):          $$exp"; \
	      echo "  Run: cd $$dfhome   # or: ln -s $$(pwd) $$dfhome"; \
	      echo ""; \
	    fi; \
	  fi; \
	fi

help:
	@echo "Available targets:"
	@echo ""
	@echo "  make setup-native  - Set up native dotfiles (symlinks ~/bin -> ~/dot_files/bin,"
	@echo "                       then installs Claude Code if missing)"
	@echo "  make all           - Compatibility alias for setup-native"
	@echo "  make set_up_links  - Create symlinks for dotfiles"
	@echo "  make install-claude - Install Claude Code (idempotent; patches the binary on Guix System)"
	@echo "  make install-uv     - Install uv on non-Guix hosts (idempotent; Guix gets it from make apply)"
	@echo "  make apply         - Apply Guix Home configuration (default; bare make runs this)"
	@echo "  make apply-wayland - Apply Guix Home Wayland config (espanso-wayland, etc.)"
	@echo "  make apply-ewm     - Deploy the EWM TRIAL home generation (home/ewm.scm;"
	@echo "                       roll back with 'guix home roll-back')"
	@echo "  make reconfigure   - Apply the SYSTEM config for this machine (Guix System only;"
	@echo "                       picks system/\$$(uname -n).scm, runs check-system first,"
	@echo "                       then sudo -i guix system reconfigure)"
	@echo "  make emacs-env     - Regenerate ~/.spacemacs.d/.spacemacs.env from a clean"
	@echo "                       login shell and push it into a running Emacs."
	@echo "                       Runs automatically after apply/apply-wayland/update."
	@echo "  make submodule-update - Init and update submodules (espanso/private)"
	@echo "  make submodule-pull  - Fast-forward each initialized submodule to the tip of its"
	@echo "                       remote default branch, detached HEAD included (the state"
	@echo "                       'make apply' leaves behind). Never forces, never merges a"
	@echo "                       divergence; a submodule that moved leaves the superproject's"
	@echo "                       gitlink MODIFIED -- record it with make claude-publish."
	@echo "  make submodule-push  - Push changes from each submodule"
	@echo "  make claude-publish  - Publish the claude/ submodule: push it, prove origin's default"
	@echo "                       branch really has the commit, then commit ONLY that gitlink"
	@echo "                       (refuses rather than record a pointer no other clone can fetch)"
	@echo "  make submodule-publish SUBMODULE=<path> - the same for any submodule path"
	@echo "  make guix-config   - Create Guix Home configuration structure in ~/guix-config"
	@echo "  make guix-root-install - Install Guix packages as root (run this first if needed)"
	@echo "  make setup-tailscale - Install tailscaled as a system LaunchDaemon (mac only;"
	@echo "                       runs at boot before login, unlike the menu-bar app)"
	@echo "  make check-tailscale - Verify the daemon is deployed, loaded and on the tailnet"
	@echo "  make setup-orbstack - Make OrbStack the sole startup container runtime (mac only;"
	@echo "                       disables Colima startup and selects the orbstack context)"
	@echo "  make check-orbstack - Verify startup ownership, CLI, context, and Docker engine"
	@echo "  make check-jobs    - Run the bin/job-tee, .jobs.zsh and .claude-jobs.zsh smoke tests (not part of 'make check': they start containers, tmux servers and a launchd agent)"
	@echo "                       (tests/jobs/tee-smoke.zsh runs first and needs none of that, so it works on any host)"
	@echo "  make check-jobs-live - Run the .jobs.zsh container assertions against a REAL engine"
	@echo "                       (needs a live container engine; skips loudly without one; not part of 'make check')"
	@echo "  make check-submodule-publish - Run the bin/submodule-publish and submodule-pull smoke test"
	@echo "                       (scratch repos in a mktemp dir only; not part of 'make check')"
	@echo "  make check-ssh-agent - Check gpg-agent is serving ssh keys to this shell, with fix hints"
	@echo "                       (not part of 'make check': depends on the calling shell and the passphrase cache)"
	@echo "  make setup-guix-github-key - Create a container-only GitHub SSH key and show its public key"
	@echo "  make emacs-serve   - Start Emacs daemon here + show how to attach over ssh"
	@echo "  make emacs-attach  - Attach to a remote daemon (make emacs-attach EMACS_HOST=minius)"
	@echo "  make emacs-unserve - Stop the Emacs daemon"
	@echo "  make wsl           - Show WSL setup instructions"
	@echo "  make help          - Show this help message"
	@echo ""
	@echo "  This Makefile assumes the repo lives at ~/dot_files (symlink ok)."
	@echo "  Targets apply, apply-wayland, and set_up_links warn if that is not the case."
	@echo ""
	@echo "Platform-specific notes:"
	@echo "  - Detected OS: $(os) $(arch)"
	@echo "  - Package manager: $(PACKAGE_MANAGER)"
	@echo "  - For native WSL setup: Run as 'HOME=/home/durant sudo make setup-native'"
	@echo ""

wsl: 
	@echo Need a reminder?
	@echo You should run this command like this:
	@echo HOME=$(wsl_home) sudo make setup-native
	@echo exiting...
	@exit 0

guix-root-install:
	@echo "Installing Guix packages as root..."
	@echo "This target installs packages that may require root privileges"
	@echo "Run this first, then run 'make setup-native' as your regular user"
ifeq ($(PACKAGE_MANAGER),guix)
	@echo "Checking what packages are already available..."
	@which zsh && echo "zsh: available" || echo "zsh: not found"
	@which curl && echo "curl: available" || echo "curl: not found"
	@which file && echo "file: available" || echo "file: not found"
	@echo "Attempting package installation..."
	sudo guix install zsh fontconfig curl file gcc-toolchain || echo "Package installation failed - container may not support package installation"
	@echo "If installation failed, packages may already be available or container may not support package installation"
else
	@echo "This target is only for Guix systems"
endif

all: setup-native

setup-native: set_up_links install-claude install-uv

# Install Claude Code as part of bootstrap. The script is idempotent (skips
# when `claude` already runs) and handles the Guix System non-FHS case by
# patchelf'ing the official binary; see bin/install-claude.sh for details.
# Native Windows has no bash, so just point at winget there.
.PHONY: install-claude
install-claude:
ifeq ($(os),$(OS_WINDOWS))
	@echo "Native Windows: install Claude Code with:"
	@echo "  winget install Anthropic.ClaudeCode"
	@echo "(from WSL, run 'make install-claude' in the WSL shell instead)"
else
	@bash bin/install-claude.sh
endif

# uv on hosts Guix Home does not manage (on Guix it is in %base-packages in
# home/common.scm).  Idempotent; see bin/install-uv.sh for the per-platform
# choice.  Native Windows gets winget, like install-claude.
.PHONY: install-uv
install-uv:
ifeq ($(os),$(OS_WINDOWS))
	@echo "Native Windows: install uv with:"
	@echo "  winget install astral-sh.uv"
	@echo "(from WSL, run 'make install-uv' in the WSL shell instead)"
else
	@bash bin/install-uv.sh
endif

# We're going to insist we're in this directory so we can run commands from here
dot_file_root_dir := $(wildcard ~/dot_files)
current_dir := $(shell $(PWD_CMD))

# Refuse, rather than warn, when Guix Home already owns this account's dotfiles.
#
# The two setups claim overlapping paths (.zshenv, .aliases, .mg,
# .wayland.zshenv, bin), so the one that ran last simply wins.  .zshenv is the
# sharpest case: under guix it is a two-line stub that sets ZDOTDIR to
# ~/.config/zsh, where the real .zshrc/.zprofile live, so overwriting it cuts
# off the ENTIRE guix zsh setup, not one file.  What makes all of this worth an
# abort instead of a notice is that the two kinds of link MEAN different things:
#
#   native:  ~/.aliases -> ~/dot_files/.aliases       live; edit, open a shell
#   guix:    ~/.aliases -> /gnu/store/...-aliases     read-only SNAPSHOT
#
# Going guix -> native is therefore not a visible break; it is a silent revert
# to whatever the store snapshot predates, and the failure shows up later as
# "my edit did nothing" with no obvious cause.  A warning printed among the
# dozens of lines set_up_links emits would not be read in time to matter.
#
# ~/.guix-home is the right probe: `guix home reconfigure' creates it as the
# symlink to the activated generation, so it exists if and only if a home
# generation has actually been activated for this user.  Merely having the guix
# BINARY installed (as on a box where guix is being trialled) does not create
# it, which is exactly the distinction we want -- trialling guix should not
# lock you out of the native path.
guard-native-over-guix:
	@if [ -e "$$HOME/.guix-home" ] && [ -z "$(FORCE_NATIVE)" ]; then \
	  echo ""; \
	  echo "  *** refusing to run set_up_links: Guix Home owns this account ***"; \
	  echo "  $$HOME/.guix-home exists, so a home generation is active and already"; \
	  echo "  owns .zshenv (and through ZDOTDIR, ~/.config/zsh), .aliases, .mg,"; \
	  echo "  .wayland.zshenv and bin."; \
	  echo "  Overwriting them with native symlinks would revert your shell to"; \
	  echo "  whatever the store snapshot holds, silently."; \
	  echo ""; \
	  echo "  To change dotfiles, edit the repo and run:  make apply"; \
	  echo "  To see who owns what right now:             make check-home-ownership"; \
	  echo "  To go native anyway (you will want to remove the guix home first):"; \
	  echo "                                              make set_up_links FORCE_NATIVE=1"; \
	  echo ""; \
	  exit 1; \
	fi

set_up_links: warn-dotfiles-home guard-native-over-guix
	@echo OS detected as $(os) $(arch)
	@echo ------------------------------
ifneq ("","$(unix_family)")
# we're in Unix land
# On OrbStack, we allow running from /Users if it looks like the right place
ifeq ($(flavor),orbstack)
	@if [[ "$(current_dir)" == /Users/* ]] && [[ "$(current_dir)" == */dot_files ]]; then \
		echo "OrbStack: Running from $(current_dir)"; \
	elif [ "$(current_dir)" != "$(dot_file_root_dir)" ]; then \
		if [ -z "$(dot_file_root_dir)" ]; then \
			echo "dot_file_root_dir did not resolve. We will continue as if you are root in WSL"; \
		else \
			echo "You should be in the $(dot_file_root_dir) directory to run this command"; \
			exit 1; \
		fi; \
	fi
else
ifneq ("$(current_dir)","$(dot_file_root_dir)")
ifeq (,$(dot_file_root_dir))
	@echo dot_file_root_dir did not resolve. We will continue as if you are root in WSL
else
	@echo You should be in the $(dot_file_root_dir) directory to run this command
	@echo You should be in the ~/dot_files directory to run this command
	exit 1
endif	
endif
endif
ifeq ($(flavor), $(FLAVOR_WSL))
	@echo We are in WSL ... NOTE MUST run make as sudo ... run `make wsl` to remind yourself how
	apt install autojump fontconfig

# this will fix error
# bash: warning: setlocale: LC_ALL: cannot change locale (en_US.UTF-8)
	echo "LC_ALL=en_US.UTF-8" >> /etc/environment
	echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf
	locale-gen en_US.UTF-8
	./install_fonts_wsl.sh

endif
ifeq ("$(os)","$(OS_LINUX)")
# you already installed git to get this far
ifeq ($(PACKAGE_MANAGER),apt)
	sudo apt-get update && sudo apt-get dist-upgrade -y
	@# mg rides along on this line rather than getting its own: unlike fastfetch
	@# below it has been in Debian/Ubuntu for years, so there is no fallback to
	@# arrange and no reason to let it fail separately.  It belongs on the apt
	@# path at all because set_up_links installs ~/.mg on EVERY platform, and a
	@# startup file for an editor that is not there is just a dangling symlink.
	@# The guix side gets mg from manifests/base.scm and home/common.scm.
	sudo apt-get install build-essential cmake curl file mg -y
	@# fastfetch is not packaged before Ubuntu 24.04, so ask for it but fall
	@# back to neofetch; .aliases defines a fastfetch shim when only neofetch
	@# is present, so the command name is the same on every machine.
	sudo apt-get install fastfetch -y || sudo apt-get install neofetch -y
	sudo apt install zsh -y && echo "Let's keep going!" || echo seems like you might have the latest version of zsh already
else ifeq ($(PACKAGE_MANAGER),guix)
	@echo "Detected Guix package manager - installing required packages"
	@echo "Installing zsh, fontconfig, curl, file, gcc-toolchain..."
	@echo "Checking what packages are already available..."
	@which zsh && echo "✓ zsh: available" || echo "✗ zsh: not found"
	@which curl && echo "✓ curl: available" || echo "✗ curl: not found"
	@which file && echo "✓ file: available" || echo "✗ file: not found"
	@echo "Attempting to install missing packages..."
	@which zsh && which curl && which file && echo "All core packages available - skipping installation" || { \
		echo "Some packages missing - attempting installation..."; \
		echo "If this fails, try: sudo make guix-root-install"; \
		guix install zsh cmake fontconfig curl file gcc-toolchain || echo "Package installation failed - continuing anyway"; \
	}
	@echo "Installing starship prompt..."
	@echo "Using curl from Guix profile..."
	@~/.guix-profile/bin/curl -sS https://starship.rs/install.sh | sh || echo "Starship installation failed"
	@echo "Verifying zsh installation..."
	@which zsh || echo "WARNING: zsh installation may have failed"
else ifeq ($(PACKAGE_MANAGER),yum)
	sudo yum update -y
	sudo yum groupinstall -y "Development Tools"
	sudo yum install -y cmake curl file zsh
else ifeq ($(PACKAGE_MANAGER),pacman)
	sudo pacman -Syu --noconfirm
	sudo pacman -S --noconfirm base-devel cmake curl file zsh
else
	@echo "Unknown package manager: $(PACKAGE_MANAGER)"
	@echo "Please install build tools, curl, file, and zsh manually"
endif
endif
ifeq ("$(os)","$(OS_MAC)")
	@# install svn if needed for the fonts
	@brew list svn > /dev/null || brew install svn
endif
# This powerline install should work on mac and linux
ifneq ($(flavor), $(FLAVOR_WSL))
ifneq ($(shell which fc-list 2>/dev/null),)
	@fc-list : file family | grep "/Library" | grep $(POWERLINE_FONT) > /dev/null && { \
		echo Found $(POWERLINE_FONT), not installing "\n"; \
	}
	@fc-list : file family | grep "/Library" | grep $(POWERLINE_FONT) > /dev/null || { \
		echo Installing $(POWERLINE_FONT); \
		git clone https://github.com/powerline/fonts.git --depth=1; \
		./fonts/install.sh; \
		rm -rf fonts; \
		echo; \
	}
else
	@echo "fc-list not available - skipping font installation"
	@echo "To install fonts manually, run: guix install fontconfig"
endif
endif
	@echo "Skipping oh-my-zsh installation - using starship instead"
# 2>/dev/null matters more than it looks: ifneq is evaluated at Makefile PARSE
# time, so this `which zsh` runs for EVERY target -- including `make apply` on a
# fresh Guix system where zsh does not exist yet (guix home is about to install
# it). Without the redirect, "which: no zsh in (...)" prints before any recipe
# runs and reads as an error in whatever target the user actually invoked.
# Every other parse-time which in this file already redirects; this one is load-
# bearing for first-run UX, not just consistency.
ifneq (,$(shell $(WHICH_CMD) zsh 2>/dev/null))
	@chsh -s $(shell $(WHICH_CMD) zsh) || echo tried to change shell to $(shell $(WHICH_CMD) zsh), but it failed;
endif

ifneq (,$(wildcard "~/.zshrc"))
	mv ~/.zshrc ~/.zshrc.bak # maybe created by oh-my-zsh and we don't care about clobbering it on rewrite
endif
	ln -si ~/dot_files/.zshrc.starship ~/.zshrc || echo
	ln -si ~/dot_files/.aliases ~ || echo

# DISABLED @echo ln -si ~/dot_files/.zprofile ~/.zprofile # reads .bash_profile if I have it
	ln -si ~/dot_files/.shared.zshenv ~/.shared.zshenv || echo # read by .zshenv
	ln -si ~/dot_files/.shared.zshrc ~/.shared.zshrc || echo  # read by .zshrc
	@# mg's startup file. Sets backup-to-home-directory so mg's foo~ backups land
	@# in ~/.mg.d instead of beside the file being edited.
	ln -si ~/dot_files/.mg ~/.mg || echo
	@# $(wildcard) is a make function: it does not expand ~ (a shell thing) and
	@# the quotes were literal pattern characters, so the pattern never matched
	@# and the guard collapsed to `[ -f  ]' -- one-argument test, which is TRUE
	@# for the non-empty string "-f".  The link was therefore made unconditionally
	@# and only worked because .linux.zshenv happens to exist.  Test the real path
	@# in the shell instead, and do not abort the recipe when it is absent.
	@if [ ! -f "$(CURDIR)/.$(os).zshenv" ]; then \
	  echo "NOTE: no .$(os).zshenv in this repo; leaving ~/.zshenv alone"; \
	elif [ -e ~/.zshenv ] && [ ! -L ~/.zshenv ]; then \
	  echo "NOTE: ~/.zshenv is a real file, not a symlink. Move it aside, then run make set_up_links again."; \
	else \
	  ln -sfn "$(CURDIR)/.$(os).zshenv" ~/.zshenv; \
	  echo "linked ~/.zshenv -> .$(os).zshenv"; \
	fi
ifeq ("$(os)","$(OS_LINUX)")
	ln -si ~/dot_files/.wayland.zshenv ~/.wayland.zshenv || echo
endif
	@mkdir -p ~/dot_files/bin
	@if [ ! -e "$$HOME/bin" ]; then \
		ln -si ~/dot_files/bin ~/bin || true; \
	elif [ -d "$$HOME/bin" ] && [ ! -L "$$HOME/bin" ]; then \
		echo "NOTE: ~/bin is a directory, not a symlink. Move or merge scripts into ~/dot_files/bin/, remove ~/bin, then run make set_up_links again."; \
	fi

	@if [ ! -e "$$HOME/.ipython" ]; then \
		ln -si ~/dot_files/.ipython ~/.ipython || true; \
	elif [ -d "$$HOME/.ipython" ] && [ ! -L "$$HOME/.ipython" ]; then \
		echo "NOTE: ~/.ipython is a directory, not a symlink. Move config to ~/dot_files/.ipython/, remove ~/.ipython, then run make set_up_links again."; \
	fi

	@if [ -t 0 ]; then \
		./unix_work_or_home.sh; \
	else \
		echo "Non-interactive mode: defaulting to HOME setup"; \
		touch ~/.HOME && echo "See ~/.aliases for the use of this file" >> ~/.HOME && echo "You are now set up for HOME"; \
	fi

else ifeq ($(os),$(OS_WINDOWS))
# TODO: check current dir here too
# MS also has a junction link type
# possibly try powershell here
	@echo Nothing set up for Windows, yet. Use WSL (Windows Subsystem for Linux) instead.
else
	@echo OS not recognized
endif

ifneq ("","$(unix_family)")
# Unix again
ifeq ("$flavor",$(FLAVOR_WSL))
	$(eval emacs_flag := wsl) # eval ensures that emacs_flag is set properly within the recipe scope
else
	$(eval emacs_flag := "$(os)")
endif
	@ZSH_CMD=""; \
	ZSH_DIR=""; \
	EXTRA_PATHS=""; \
	if command -v zsh >/dev/null 2>&1; then \
		ZSH_CMD=zsh; \
	elif [ -f ~/.guix-profile/bin/zsh ]; then \
		ZSH_CMD=~/.guix-profile/bin/zsh; \
		ZSH_DIR=~/.guix-profile/bin; \
	elif [ -f ~/.config/guix/current/bin/zsh ]; then \
		ZSH_CMD=~/.config/guix/current/bin/zsh; \
		ZSH_DIR=~/.config/guix/current/bin; \
	else \
		for zsh_path in /gnu/store/*zsh*/bin/zsh /gnu/store/*/bin/zsh; do \
			if [ -f "$$zsh_path" ] && [ -x "$$zsh_path" ]; then \
				ZSH_CMD="$$zsh_path"; \
				ZSH_DIR=$$(dirname "$$zsh_path"); \
				break; \
			fi; \
		done; \
	fi; \
	if [ -n "$$ZSH_CMD" ] && [ -f "$$ZSH_CMD" ]; then \
		echo "Installing Emacs with zsh (found at: $$ZSH_CMD)..."; \
		GUIX_BIN=""; \
		if command -v guix >/dev/null 2>&1; then \
			GUIX_BIN=guix; \
		elif [ -f /gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin/guix ]; then \
			GUIX_BIN=/gnu/store/c5591aalxj45nmfzf0srb83ljpmlv32f-profile/bin/guix; \
		fi; \
		for tool in git fc-cache rm wget; do \
			tool_found=0; \
			tool_search_paths=""; \
			if [ "$$tool" = "rm" ]; then \
				tool_search_paths="/gnu/store/*coreutils*/bin/rm /gnu/store/*rm*/bin/rm /gnu/store/*/bin/rm"; \
			else \
				tool_search_paths="/gnu/store/*$$tool*/bin/$$tool /gnu/store/*/bin/$$tool"; \
			fi; \
			for tool_path in $$tool_search_paths; do \
				if [ -f "$$tool_path" ] && [ -x "$$tool_path" ]; then \
					tool_dir=$$(dirname "$$tool_path"); \
					EXTRA_PATHS="$$EXTRA_PATHS:$$tool_dir"; \
					tool_found=1; \
					break; \
				fi; \
			done; \
			if [ $$tool_found -eq 0 ] && [ -n "$$GUIX_BIN" ] && [ "$$tool" = "git" ]; then \
				echo "git not found in store, attempting to build..."; \
				git_build_output=$$($$GUIX_BIN build git 2>&1); \
				for git_path in $$git_build_output; do \
					if [ -d "$$git_path" ] && [ -f "$$git_path/bin/git" ]; then \
						case "$$git_path" in \
							*credential*|*send-email*|*subtree*|*svn*|*gui*) \
								continue ;; \
							*) \
								EXTRA_PATHS="$$EXTRA_PATHS:$$git_path/bin"; \
								echo "✓ git found at $$git_path/bin"; \
								break 2 ;; \
						esac; \
					fi; \
				done; \
			fi; \
		done; \
		if [ -n "$$ZSH_DIR" ]; then \
			FINAL_PATH="$$ZSH_DIR$$EXTRA_PATHS:$$PATH"; \
		else \
			FINAL_PATH="$$EXTRA_PATHS:$$PATH"; \
		fi; \
		PATH="$$FINAL_PATH" GIT_SSL_NO_VERIFY=1 $$ZSH_CMD ./install_emacs.zsh --$(emacs_flag); \
	else \
		echo "⚠️  zsh not available - skipping Emacs installation"; \
		echo "   The install_emacs.zsh script requires zsh."; \
		echo "   Install zsh first (e.g., via Guix: guix install zsh), then run: make setup-native"; \
		echo "   Or install Emacs manually if needed."; \
	fi
endif

.PHONY: guix-config apply-wayland submodule-update submodule-pull submodule-push
.PHONY: submodule-publish claude-publish
guix-config:
	@echo "====================================================================="
	@echo "Creating Guix Home configuration structure in ~/guix-config"
	@echo "====================================================================="
	@if [ -d ~/guix-config ]; then \
		echo "Directory ~/guix-config already exists."; \
		if [ -f ~/guix-config/channels.scm ]; then \
			echo "Found existing channels.scm - will preserve it."; \
		fi; \
		read -p "Continue and populate directory? [y/N] " -n 1 -r; \
		echo; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "Aborted."; \
			exit 1; \
		fi; \
	else \
		echo "Creating new ~/guix-config directory..."; \
		mkdir -p ~/guix-config; \
	fi
	@echo ""
	@echo "Creating directory structure..."
	mkdir -p ~/guix-config/home/langs
	mkdir -p ~/guix-config/manifests
	mkdir -p ~/guix-config/templates
	@echo ""
	@if [ ! -f ~/guix-config/channels.scm ]; then \
		echo "Creating channels.scm with current Guix commit..."; \
		echo "(list (channel" > ~/guix-config/channels.scm; \
		echo "        (name 'guix)" >> ~/guix-config/channels.scm; \
		echo "        (url \"https://codeberg.org/guix/guix\")" >> ~/guix-config/channels.scm; \
		echo "        (branch \"master\")" >> ~/guix-config/channels.scm; \
		echo "        (introduction" >> ~/guix-config/channels.scm; \
		echo "          (make-channel-introduction" >> ~/guix-config/channels.scm; \
		echo "            \"9edb3f66fd807b096b48283debdcddccfea34bad\"" >> ~/guix-config/channels.scm; \
		echo "            (openpgp-fingerprint" >> ~/guix-config/channels.scm; \
		echo "              \"BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA\")))))" >> ~/guix-config/channels.scm; \
	else \
		echo "Preserving existing channels.scm"; \
	fi
	@echo ""
	@echo "Creating home/base.scm (minimal configuration)..."
	@echo "(use-modules (gnu home)" > ~/guix-config/home/base.scm
	@echo "             (gnu packages)" >> ~/guix-config/home/base.scm
	@echo "             (gnu services)" >> ~/guix-config/home/base.scm
	@echo "             (gnu home services shells)" >> ~/guix-config/home/base.scm
	@echo "             (guix gexp))" >> ~/guix-config/home/base.scm
	@echo "" >> ~/guix-config/home/base.scm
	@echo "(home-environment" >> ~/guix-config/home/base.scm
	@echo "  (packages (specifications->manifest" >> ~/guix-config/home/base.scm
	@echo "    '(\"zsh\"" >> ~/guix-config/home/base.scm
	@echo "      \"git\"" >> ~/guix-config/home/base.scm
	@echo "      \"ripgrep\"" >> ~/guix-config/home/base.scm
	@echo "      \"bat\"" >> ~/guix-config/home/base.scm
	@echo "      \"starship\")))" >> ~/guix-config/home/base.scm
	@echo "  (services" >> ~/guix-config/home/base.scm
	@echo "    (list" >> ~/guix-config/home/base.scm
	@echo "     (service home-zsh-service-type" >> ~/guix-config/home/base.scm
	@echo "              (home-zsh-configuration" >> ~/guix-config/home/base.scm
	@echo "               (zshrc '(\"eval \\\"\$$(starship init zsh)\\\"\"" >> ~/guix-config/home/base.scm
	@echo "                       \"alias ll='ls -lah'\")))))))" >> ~/guix-config/home/base.scm
	@echo ""
	@echo "Creating home/devtools.scm..."
	@echo "(use-modules (gnu packages))" > ~/guix-config/home/devtools.scm
	@echo "" >> ~/guix-config/home/devtools.scm
	@echo "(specifications->manifest" >> ~/guix-config/home/devtools.scm
	@echo "  '(\"eza\"" >> ~/guix-config/home/devtools.scm
	@echo "    \"fd\"" >> ~/guix-config/home/devtools.scm
	@echo "    \"zoxide\"" >> ~/guix-config/home/devtools.scm
	@echo "    \"fzf\"" >> ~/guix-config/home/devtools.scm
	@echo "    \"delta\"" >> ~/guix-config/home/devtools.scm
	@echo "    \"direnv\"))" >> ~/guix-config/home/devtools.scm
	@echo ""
	@echo "Creating templates/python.envrc..."
	@echo "# Auto-activate Guix shell + UV venv" > ~/guix-config/templates/python.envrc
	@echo "use guix python python-pip" >> ~/guix-config/templates/python.envrc
	@echo "layout uv" >> ~/guix-config/templates/python.envrc
	@echo ""
	@echo "Creating templates/haskell.envrc..."
	@echo "# Auto-activate Guix shell for Haskell" > ~/guix-config/templates/haskell.envrc
	@echo "use guix ghc ghc-cabal-install" >> ~/guix-config/templates/haskell.envrc
	@echo ""
	@echo "Creating Makefile in ~/guix-config..."
	@echo ".PHONY: apply update rollback clean" > ~/guix-config/Makefile
	@echo "" >> ~/guix-config/Makefile
	@echo "apply:" >> ~/guix-config/Makefile
	@echo "	guix pull --channels=channels.scm" >> ~/guix-config/Makefile
	@echo "	guix home reconfigure home/base.scm" >> ~/guix-config/Makefile
	@echo "" >> ~/guix-config/Makefile
	@echo "update:" >> ~/guix-config/Makefile
	@echo "	guix pull" >> ~/guix-config/Makefile
	@echo "	guix describe --format=channels > channels.scm" >> ~/guix-config/Makefile
	@echo "" >> ~/guix-config/Makefile
	@echo "rollback:" >> ~/guix-config/Makefile
	@echo "	guix home roll-back" >> ~/guix-config/Makefile
	@echo "" >> ~/guix-config/Makefile
	@echo "clean:" >> ~/guix-config/Makefile
	@echo "	guix home delete-generations 30d" >> ~/guix-config/Makefile
	@echo "	guix gc" >> ~/guix-config/Makefile
	@echo ""
	@echo "Creating .gitignore in ~/guix-config..."
	@echo "# Generated by Guix Home" > ~/guix-config/.gitignore
	@echo ".guix-profile" >> ~/guix-config/.gitignore
	@echo ".guix-home" >> ~/guix-config/.gitignore
	@echo "" >> ~/guix-config/.gitignore
	@echo "# Per-project Guix profiles" >> ~/guix-config/.gitignore
	@echo ".guix-profile/" >> ~/guix-config/.gitignore
	@echo "manifest-derived.scm" >> ~/guix-config/.gitignore
	@echo ""
	@echo "Creating README.md in ~/guix-config..."
	@echo "# Guix Home Configuration" > ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "Declarative home environment configuration using GNU Guix." >> ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "## Quick Start" >> ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "\`\`\`bash" >> ~/guix-config/README.md
	@echo "# Initial apply" >> ~/guix-config/README.md
	@echo "make apply" >> ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "# Update channels and lock" >> ~/guix-config/README.md
	@echo "make update" >> ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "# Rollback to previous generation" >> ~/guix-config/README.md
	@echo "make rollback" >> ~/guix-config/README.md
	@echo "\`\`\`" >> ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "## Directory Structure" >> ~/guix-config/README.md
	@echo "" >> ~/guix-config/README.md
	@echo "- \`channels.scm\` - Pinned Guix channel revisions" >> ~/guix-config/README.md
	@echo "- \`home/\` - Home environment configurations" >> ~/guix-config/README.md
	@echo "- \`manifests/\` - Per-project package manifests" >> ~/guix-config/README.md
	@echo "- \`templates/\` - Direnv and project templates" >> ~/guix-config/README.md
	@echo ""
	@echo "====================================================================="
	@echo "Done! Created guix-config structure at ~/guix-config"
	@echo "====================================================================="
	@echo ""
	@echo "Directory structure:"
	@tree -L 2 ~/guix-config 2>/dev/null || find ~/guix-config -type f | sort
	@echo ""
	@echo "Next steps:"
	@echo "  1. cd ~/guix-config"
	@echo "  2. Review the generated files"
	@echo "  3. Customize home/base.scm for your needs"
	@echo "  4. git add -A && git commit -m 'Initial Guix Home config'"
	@echo "  5. git push"
	@echo ""

# Guix Home bootstrap targets (non-invasive)
.PHONY: apply apply-wayland update install-manifest home-check emacs-env

# Regenerate ~/.spacemacs.d/.spacemacs.env after a home reconfigure.
#
# Why this exists instead of `M-x spacemacs/force-init-spacemacs-env': that
# function binds process-environment to `initial-environment' (core-env.el:112),
# i.e. the environment Emacs was LAUNCHED with. Poking a running Emacs after a
# reconfigure just re-records the pre-reconfigure values.
#
# Why env -i: ~/.guix-home/profile/etc/profile builds every search path as
# "$new${VAR:+:}$VAR", so a login shell PREPENDS the new generation and keeps
# the old one as a tail. Inheriting this make process's environment would drag
# the previous session's garbage-collected /gnu/store paths along -- which is
# exactly how a dead zsh path once ended up baked into .spacemacs.env. Starting
# from nothing forces .zprofile -> ~/.profile -> setup-environment to rebuild
# each path against the current generation.
#
# SHELL is seeded explicitly because env -i drops it and zsh will not re-derive
# it from passwd. Two passes mirror spacemacs//init-spacemacs-env: -lc picks up
# .zprofile (PATH), -ic picks up .zshrc (EDITOR, VISUAL).
#
# The __ENV_BEGIN__ sentinel and the identifier grep are both load-bearing: an
# interactive zsh writes to STDOUT before env runs -- a precmd xterm-title
# escape, and .zshrc's "Starship not found" notice. Without them the escape
# glues itself onto the first variable ("]2;...HOME=/home/durant") and the
# notice lands in the file as a bogus entry. The sentinel's trailing newline
# closes off the escape; the grep drops anything that is not NAME=VALUE.
SPACEMACS_ENV := $(HOME)/.spacemacs.d/.spacemacs.env

# Session-scoped values that must not be frozen into a file. Mirrors
# `spacemacs-ignored-environment-variables' plus shell bookkeeping.
EMACS_ENV_IGNORED := DBUS_SESSION_BUS_ADDRESS|DESKTOP_STARTUP_ID|DISPLAY|GPG_AGENT_INFO|ICEAUTHORITY|INVOCATION_ID|JOURNAL_STREAM|MANAGERPID|SESSION_MANAGER|SSH_AGENT_PID|SSH_AUTH_SOCK|SYSTEMD_EXEC_PID|XAUTHORITY|XDG_SESSION_TYPE|OLDPWD|PWD|SHLVL|TERM|STARSHIP_SESSION_KEY|WINDOWID|_

EMACS_CLEAN_ENV := env -i HOME="$(HOME)" USER="$(LOGIN_USER)" LOGNAME="$(LOGIN_USER)" TERM=dumb SHELL="$(LOGIN_SHELL)"

emacs-env:
	@if [ ! -d "$(HOME)/.spacemacs.d" ]; then \
	  echo "==> no ~/.spacemacs.d; skipping emacs-env"; \
	  exit 0; \
	fi; \
	{ \
	  printf '# Generated by dot_files/Makefile (make emacs-env).\n'; \
	  printf '# Captured from a CLEAN login+interactive shell (env -i) so that\n'; \
	  printf '# store paths from the pre-reconfigure session cannot leak in.\n'; \
	  printf '#\n'; \
	  printf '# Do NOT run spacemacs/force-init-spacemacs-env to refresh this --\n'; \
	  printf '# it re-reads initial-environment and would reintroduce stale paths.\n'; \
	  printf '# Run `make emacs-env` in ~/dot_files instead.\n\n'; \
	  { $(EMACS_CLEAN_ENV) "$(LOGIN_SHELL)" -lc 'printf "\n__ENV_BEGIN__\n"; env' 2>/dev/null; \
	    $(EMACS_CLEAN_ENV) "$(LOGIN_SHELL)" -ic 'printf "\n__ENV_BEGIN__\n"; env' 2>/dev/null; } \
	    | grep -aE '^[A-Za-z_][A-Za-z0-9_]*=' \
	    | grep -vE '^($(EMACS_ENV_IGNORED))=' | sort -u ; \
	} > "$(SPACEMACS_ENV).tmp" && mv "$(SPACEMACS_ENV).tmp" "$(SPACEMACS_ENV)"; \
	echo "==> wrote $$(grep -c '=' "$(SPACEMACS_ENV)") variables to $(SPACEMACS_ENV)"; \
	if grep -v '^#' "$(SPACEMACS_ENV)" | grep -q '/gnu/store/'; then \
	  echo "--- WARNING: raw store paths survived the clean capture ---"; \
	  grep -v '^#' "$(SPACEMACS_ENV)" | grep -o '/gnu/store/[^:]*' | sort -u; \
	  echo "These go stale on the next 'guix gc'. Check what sets them."; \
	fi; \
	if emacsclient -e t >/dev/null 2>&1; then \
	  if emacsclient -e '(load-env-vars "$(SPACEMACS_ENV)")' >/dev/null 2>&1; then \
	    echo "==> pushed into the running Emacs (exec-path rebuilt from PATH)"; \
	  else \
	    echo "==> running Emacs found but load-env-vars failed; restart it"; \
	  fi; \
	else \
	  echo "==> no running Emacs; the file loads on next GUI start"; \
	fi

# A reconfigure only rewrites ~/.gnupg/gpg-agent.conf -- the *running* agent
# keeps the config it read at startup, and herd reports it as "Replacement
# pending (restart to upgrade)" indefinitely.  That mostly goes unnoticed,
# because the setting rarely changes.  The trap is pinentry-program, which
# names an absolute store path: `guix pull' moves pinentry to a new path, the
# new conf points there, and the live agent still holds the old one.  It keeps
# working until a `guix gc' collects the old path, at which point gpg-agent
# cannot launch a pinentry and every ssh-add fails with the thoroughly
# unhelpful "agent refused operation" -- days after the reconfigure that
# actually caused it.  Restarting here keeps the live agent and the config in
# step, so that failure can never accumulate.
#
# Not fatal if it fails: shepherd is not running during a first-time install
# or a reconfigure from a bare TTY, and neither is a reason to fail the build.
.PHONY: restart-gpg-agent
restart-gpg-agent:
	@echo "==> restarting gpg-agent onto the new config"
	@herd restart gpg-agent 2>/dev/null \
	  || echo "    (skipped: no user shepherd -- the agent will pick this up at next login)"

# Is the gpg-ssh-agent layer actually usable from THIS shell?  Walks the chain
# a `git push' depends on, in order, and prints the fix at the first broken
# link:
#   1. gpg-agent's ssh socket exists (the shepherd service is up)
#   2. the pinentry named in gpg-agent.conf still exists -- see the GC trap
#      described above restart-gpg-agent
#   3. $SSH_AUTH_SOCK in the calling shell points at that socket, not at a
#      dead /tmp/ssh-* left by an `eval $(ssh-agent -s)'
#   4. keys have been imported (the one-time `ssh-add' per machine)
#   5. which of them are unlocked right now (cache-TTL state; informational)
#
# Deliberately NOT a prerequisite of `check': the answer depends on the
# calling shell's environment and on a passphrase cache that expires every
# hour, so it would make `check' fail for reasons that are not config drift.
# The socket test comes before any gpg-connect-agent call, because that
# command autostarts an agent and this target must not have side effects.
.PHONY: check-ssh-agent
check-ssh-agent:
	@echo "==> gpg-agent as ssh agent"
	@if ! command -v gpgconf >/dev/null 2>&1; then \
	  echo "    skipped: no gpgconf here (gpg-ssh-agent layer not deployed)"; \
	  exit 0; \
	fi; \
	rc=0; \
	sock=$$(gpgconf --list-dirs agent-ssh-socket); \
	if [ ! -S "$$sock" ]; then \
	  echo "    [--] agent    : no socket at $$sock"; \
	  echo "         fix: herd start gpg-agent   (or log in again)"; \
	  exit 1; \
	fi; \
	echo "    [ok] agent    : $$sock"; \
	pin=$$(sed -n 's/^pinentry-program[[:space:]]*//p' "$$HOME/.gnupg/gpg-agent.conf" 2>/dev/null); \
	if [ -n "$$pin" ] && [ ! -x "$$pin" ]; then \
	  rc=1; \
	  echo "    [--] pinentry : $$pin is gone (guix gc'd it)"; \
	  echo "         fix: make apply   (or at least: make restart-gpg-agent)"; \
	else \
	  echo "    [ok] pinentry : $${pin:-gpg default}"; \
	fi; \
	if [ "$$SSH_AUTH_SOCK" = "$$sock" ]; then \
	  echo "    [ok] this shell: SSH_AUTH_SOCK -> gpg-agent"; \
	else \
	  rc=1; \
	  echo "    [--] this shell: SSH_AUTH_SOCK=$${SSH_AUTH_SOCK:-<unset>}"; \
	  echo "         fix: export SSH_AUTH_SOCK=\"\$$(gpgconf --list-dirs agent-ssh-socket)\"; unset SSH_AGENT_PID"; \
	  echo "              (or open a new terminal; never 'eval \$$(ssh-agent -s)')"; \
	fi; \
	keys=$$(gpg-connect-agent 'keyinfo --ssh-list --ssh-fpr' /bye 2>/dev/null | grep '^S KEYINFO'); \
	if [ -z "$$keys" ]; then \
	  rc=1; \
	  echo "    [--] keys     : none imported into gpg-agent"; \
	  echo "         fix (once per machine, in a real terminal):"; \
	  echo "              gpg-connect-agent updatestartuptty /bye"; \
	  echo "              ssh-add $$(ls $$HOME/.ssh/id_* 2>/dev/null | grep -v '\.pub$$' | sed "s|^$$HOME|~|" | tr '\n' ' ')"; \
	else \
	  echo "$$keys" | while read -r _ _ _ _ _ _ cached _ fpr _; do \
	    comment=$$(SSH_AUTH_SOCK="$$sock" ssh-add -l 2>/dev/null | grep -F "$$fpr" | sed 's/^[0-9]* [^ ]* //'); \
	    if [ "$$cached" = 1 ]; then state=unlocked; else state="locked (next ssh/git push asks once)"; fi; \
	    echo "    [ok] key      : $${comment:-$$fpr} -- $$state"; \
	  done; \
	fi; \
	[ $$rc = 0 ] && echo "==> ssh agent OK" || { echo "==> ssh agent: fix the [--] lines above"; exit 1; }

# The guix to run AFTER a `guix pull': the one the pull just produced.
#
# `guix pull' installs into ~/.config/guix/current and does nothing else; it
# cannot change which guix a bare `guix' means.  That is decided by PATH, and
# on a foreign distro set up by guix-install.sh PATH reaches
# /usr/local/bin/guix -- ROOT's profile -- unless the login shell has already
# sourced ~/.config/guix/current/etc/profile.  On a machine where Guix Home
# has never been applied, nothing has arranged that yet, so the recipe pulled
# the revisions pinned in channels.scm and then built the home with root's
# unrelated guix: the pin silently ignored, and no nonguix channel at all.  The
# only trace was the `hint: Consider setting the necessary environment
# variables' that guix pull prints, which reads as boilerplate.
#
# So name the pulled guix outright instead of trusting PATH.  Resolved in the
# recipe's shell, at the moment of use, because on a first run the file does
# not exist until the `guix pull' a few lines earlier has finished -- a make
# variable expanded at parse time would miss it.  Falls back to PATH's guix
# where there is no per-user pull at all (Guix System before the first pull).
PULLED_GUIX = $$( g="$$HOME/.config/guix/current/bin/guix"; [ -x "$$g" ] && echo "$$g" || echo guix )

apply: warn-dotfiles-home
	@echo "==> git submodule update --init claude"
	@# home/base.scm reads ../claude/* via local-file, so an uninitialized
	@# submodule fails the reconfigure with an opaque "no such file" from the
	@# store builder. Deliberately NOT `|| true`: claude-config is private, and
	@# a missing SSH key should stop here with git's own message rather than
	@# surface later as a Guix error.
	@git submodule update --init claude
	@# Before the (slow) pull, and long before the activation: refuse while $$HOME
	@# holds something the symlink manager would walk through or choke on.  See
	@# check-home-ownership -- PREFLIGHT=1 fails on hazards only, never on a plain
	@# conflict, since resolving conflicts is what this target is for.
	@$(MAKE) --no-print-directory check-home-ownership PREFLIGHT=1
	@echo "==> guix pull (pinned if channels.scm exists)"
	@if [ -f channels.scm ]; then \
	  guix pull --allow-downgrades --channels=channels.scm || guix pull ; \
	else \
	  guix pull ; \
	fi
	@echo "==> guix home reconfigure home/base.scm  (guix: $(PULLED_GUIX))"
	@$(PULLED_GUIX) home reconfigure $(GUIX_HOME_GRAFT_FLAGS) --allow-downgrades home/base.scm
	@$(MAKE) --no-print-directory restart-gpg-agent
	@echo "==> refreshing .spacemacs.env against the new generation"
	@$(MAKE) --no-print-directory emacs-env
	@echo "==> ensuring Claude Code is installed (idempotent)"
	@$(MAKE) --no-print-directory install-claude
	@echo "==> done (Guix Home applied)"
	@echo ""
	@echo "--- NOTE: PATH ---"
	@echo "Anything just installed lives in ~/.guix-home/profile/bin, which"
	@echo "this shell's PATH may not include yet (rehash cannot fix that --"
	@echo "it only rescans directories already ON the PATH). Either:"
	@echo "  source ~/.profile      # fixes PATH in this shell"
	@echo "or log out and back in   # also starts user services (emacs daemon)"
	@if [ "$(flavor)" != orbstack ] && [ "$(flavor)" != wsl ] && [ ! -f /etc/keyd/default.conf ]; then \
		echo ""; \
		echo "--- NEXT STEP: KEYBINDINGS ---"; \
		echo "To finish system-wide Emacs keybindings setup, run:"; \
		echo "  sudo make setup-keyd"; \
		echo "------------------------------"; \
	fi

apply-wayland: warn-dotfiles-home
	@$(MAKE) --no-print-directory check-home-ownership PREFLIGHT=1
	@echo "==> guix pull (pinned if channels.scm exists)"
	@if [ -f channels.scm ]; then \
	  guix pull --allow-downgrades --channels=channels.scm || guix pull ; \
	else \
	  guix pull ; \
	fi
	@echo "==> git submodule update --init (espanso/private)"
	@git submodule update --init espanso/private 2>/dev/null || true
	@echo "==> git submodule update --init claude"
	@# Unlike espanso/private this is NOT optional: home/wayland.scm reads
	@# ../claude/* unconditionally, so let git's error stop the build.
	@git submodule update --init claude
	@echo "==> guix home reconfigure home/wayland.scm  (guix: $(PULLED_GUIX))"
	@$(PULLED_GUIX) home reconfigure --allow-downgrades home/wayland.scm
	@$(MAKE) --no-print-directory restart-gpg-agent
	@echo "==> refreshing .spacemacs.env against the new generation"
	@$(MAKE) --no-print-directory emacs-env
	@echo "==> ensuring Claude Code is installed (idempotent)"
	@$(MAKE) --no-print-directory install-claude
	@echo "==> done (Guix Home Wayland applied)"
	@echo ""
	@echo "--- NOTE: PATH ---"
	@echo "Anything just installed lives in ~/.guix-home/profile/bin, which"
	@echo "this shell's PATH may not include yet (rehash cannot fix that --"
	@echo "it only rescans directories already ON the PATH). Either:"
	@echo "  source ~/.profile      # fixes PATH in this shell"
	@echo "or log out and back in   # also starts user services (emacs daemon)"
	@if [ "$(flavor)" != orbstack ] && [ "$(flavor)" != wsl ] && [ ! -f /etc/keyd/default.conf ]; then \
		echo ""; \
		echo "--- NEXT STEP: KEYBINDINGS ---"; \
		echo "To finish system-wide Emacs keybindings setup, run:"; \
		echo "  sudo make setup-keyd"; \
		echo "------------------------------"; \
	fi

# apply-ewm -- deploy the EWM TRIAL home generation (docs/EWM_TRIAL_PLAN.md,
# home/ewm.scm).  Deliberately leaner than apply/apply-wayland: no guix pull,
# no .spacemacs.env refresh, no claude-install pass -- this is a generation
# you try and roll back from, not a daily driver, and every skipped step is
# one less difference to un-do.  Return with:
#   guix home roll-back
# The claude submodule IS still required: the claude-code layer reads
# ../claude/* via local-file, and an uninitialized submodule fails the
# reconfigure with an opaque "no such file" from the store builder.
apply-ewm: warn-dotfiles-home
	@echo "==> git submodule update --init claude"
	@git submodule update --init claude
	@$(MAKE) --no-print-directory check-home-ownership PREFLIGHT=1
	@echo "==> guix home reconfigure home/ewm.scm  (guix: $(PULLED_GUIX))"
	@$(PULLED_GUIX) home reconfigure --allow-downgrades home/ewm.scm
	@echo "==> done (EWM trial generation deployed)"
	@echo ""
	@echo "    GNOME keeps running on its VT; launch EWM from a fresh TTY"
	@echo "    per docs/EWM_TRIAL_PLAN.md.  Return to the GNOME-tuned home"
	@echo "    with:  guix home roll-back"

submodule-update:
	@echo "==> git submodule update --init --recursive"
	@git submodule update --init --recursive

# submodule-pull used to be `git submodule foreach git pull', which fails in
# exactly the state `make apply' leaves behind.  Measured on 2026-09-18 in a
# scratch superproject, on a submodule initialized the way apply does it:
#
#     $ git submodule foreach git pull
#     Entering 'sub'
#     You are not currently on a branch.
#     Please specify which branch you want to merge with.
#     ...
#     fatal: run_command returned non-zero status for sub
#     exit status: 128
#
# because `git submodule update --init' leaves the submodule on a detached
# HEAD (`git status -sb' prints `## HEAD (no branch)'), and `git pull' has no
# upstream to merge from there.  So the target no longer asks `pull' to guess:
# it asks the REMOTE for its default branch, fetches exactly that branch, and
# fast-forwards -- checking out the new tip when the submodule is detached and
# merging --ff-only when it is on a branch.
#
# It never forces and never merges a divergence.  A submodule carrying local
# commits that do not fast-forward is reported and left exactly as found; the
# other submodules are still attempted, and the target exits non-zero at the
# end so a script cannot mistake a partial run for a clean one.
#
# "Initialized" is tested as `[ -e <path>/.git ]', not with `git -C <path>
# rev-parse --git-dir': an uninitialized submodule is an EMPTY DIRECTORY inside
# this repo, so that rev-parse walks up out of it and answers with the
# superproject's own .git -- exit 0, and every uninitialized submodule silently
# treated as initialized.
submodule-pull:
	@echo "==> submodule-pull: fast-forward each initialized submodule to its remote default branch"
	@set -u; \
	rc=0; \
	if [ ! -f .gitmodules ]; then \
	  echo "    no .gitmodules here -- nothing to pull"; \
	  exit 0; \
	fi; \
	raw=$$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$$') || raw=''; \
	paths=$$(printf '%s\n' "$$raw" | awk 'NF { print $$2 }'); \
	if [ -z "$$paths" ]; then \
	  echo "    .gitmodules declares no submodule paths -- nothing to pull"; \
	  exit 0; \
	fi; \
	for p in $$paths; do \
	  if [ ! -e "$$p/.git" ]; then \
	    echo "    $$p: not initialized -- skipped (git submodule update --init -- $$p)"; \
	    continue; \
	  fi; \
	  dirty=$$(git -C "$$p" status --porcelain --untracked-files=no); \
	  if [ -n "$$dirty" ]; then \
	    echo "    $$p: uncommitted changes -- left untouched"; \
	    rc=1; continue; \
	  fi; \
	  symref=$$(git -C "$$p" ls-remote --symref origin HEAD 2>/dev/null) || { \
	    echo "    $$p: cannot reach its origin -- left untouched"; \
	    rc=1; continue; \
	  }; \
	  def=$$(printf '%s\n' "$$symref" | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$$|\1|p' | head -n 1); \
	  if [ -z "$$def" ]; then \
	    echo "    $$p: cannot determine origin's default branch -- left untouched"; \
	    rc=1; continue; \
	  fi; \
	  if ! git -C "$$p" fetch -q origin "+refs/heads/$$def:refs/remotes/origin/$$def"; then \
	    echo "    $$p: fetching origin/$$def failed -- left untouched"; \
	    rc=1; continue; \
	  fi; \
	  old=$$(git -C "$$p" rev-parse HEAD); \
	  new=$$(git -C "$$p" rev-parse "refs/remotes/origin/$$def"); \
	  olds=$$(git -C "$$p" rev-parse --short "$$old"); \
	  news=$$(git -C "$$p" rev-parse --short "$$new"); \
	  if [ "$$old" = "$$new" ]; then \
	    echo "    $$p: up to date ($$olds, origin/$$def)"; \
	    continue; \
	  fi; \
	  if ! git -C "$$p" merge-base --is-ancestor "$$old" "$$new"; then \
	    echo "    $$p: local commits do not fast-forward to origin/$$def -- left untouched"; \
	    echo "        HEAD $$olds, origin/$$def $$news"; \
	    rc=1; continue; \
	  fi; \
	  branch=$$(git -C "$$p" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=''; \
	  if [ -n "$$branch" ]; then \
	    git -C "$$p" merge --ff-only -q "refs/remotes/origin/$$def" || { \
	      echo "    $$p: fast-forwarding branch '$$branch' to origin/$$def failed -- left untouched"; \
	      rc=1; continue; \
	    }; \
	  else \
	    git -C "$$p" checkout -q --detach "$$new" || { \
	      echo "    $$p: checking out origin/$$def failed -- left untouched"; \
	      rc=1; continue; \
	    }; \
	  fi; \
	  echo "    $$p: $$olds -> $$news"; \
	done; \
	echo ""; \
	echo "    A submodule that moved leaves this superproject's gitlink MODIFIED."; \
	echo "    Record it with:  make claude-publish   (or: make submodule-publish SUBMODULE=<path>)"; \
	if [ "$$rc" != 0 ]; then \
	  echo ""; \
	  echo "    At least one submodule was left untouched (see above); nothing was forced."; \
	fi; \
	exit $$rc

submodule-push:
	@echo "==> git submodule foreach git push"
	@git submodule foreach git push

# bin/submodule-publish holds the invariant that gives this repo's gitlinks
# their meaning: a commit recorded here is one every other clone can fetch.
# The logic lives in a script rather than a recipe so it can be tested without
# make -- see tests/submodule/publish-smoke.zsh.  SUBMODULE_PUBLISH is spelled
# from MAKEFILE_LIST so the target works under `make -f /path/to/Makefile' from
# another directory, which is exactly how the test drives it.
SUBMODULE_PUBLISH := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))/bin/submodule-publish

claude-publish:
	@$(SUBMODULE_PUBLISH) claude

submodule-publish:
	@if [ -z "$(SUBMODULE)" ]; then \
	  echo "usage: make submodule-publish SUBMODULE=<path>" >&2; \
	  echo "   or: make claude-publish" >&2; \
	  exit 2; \
	fi
	@$(SUBMODULE_PUBLISH) $(SUBMODULE)

.PHONY: setup-keyd
# Guix System detection for setup-keyd.
#
# Deliberately NOT PACKAGE_MANAGER: that detects an INSTALLED package manager,
# not the OS, and guix installs happily on top of any distro -- Pop!_OS here.
#
# The probe order above happens to save us today: apt is assigned after guix,
# and last match wins, so a Pop!_OS box with guix installed still reports
# `apt`. But that is incidental. It relies both on assignment order and on the
# distro's native manager being one of the ones probed; on a distro using
# apk/zypper/nix, guix would win and this target would wrongly refuse to run
# on a machine where it works fine.
#
# /run/current-system is a direct test of the OS, so use that instead.
GUIX_SYSTEM := $(wildcard /run/current-system)

# This target runs under sudo, where HOME=/root -- but the keyd binary lives in
# the INVOKING user's guix home profile. Expanding $(HOME) here once produced a
# dangling /usr/local/bin/keyd -> /root/.guix-home/... and a silent 203/EXEC
# crash loop that went unnoticed because GNOME's ctrl:swapcaps masked it.
# Lazy `=`, not `:=`: a simple assignment runs getent at PARSE time, on every
# make invocation -- and macOS has no getent, so every target printed
# "getent: command not found" before doing anything. setup-keyd is
# Linux-only, so defer the lookup until the recipe below expands it.
REAL_HOME = $(shell getent passwd $${SUDO_USER:-$$USER} 2>/dev/null | cut -d: -f6)

setup-keyd:
ifeq ($(filter orbstack wsl,$(flavor)),)
ifneq ($(GUIX_SYSTEM),)
	@echo ""
	@echo "  *** setup-keyd is not for Guix System ***"
	@echo ""
	@echo "  Every step of this target assumes systemd and the FHS:"
	@echo "    /usr/local/bin           does not exist (no FHS)"
	@echo "    /etc/systemd/system      does not exist (Shepherd, not systemd)"
	@echo "    systemctl                does not exist"
	@echo "    ~/.guix-home/profile/bin is the USER profile; keyd needs root"
	@echo "                             for /dev/input/event* and /dev/uinput"
	@echo ""
	@echo "  On Guix, keyd is a SYSTEM service and belongs in your system"
	@echo "  config, not in dotfiles. Guix packages keyd but ships no"
	@echo "  keyd-service-type, so it is a hand-written shepherd-service"
	@echo "  alongside kernel-module-loader (uinput) and an etc-service-type"
	@echo "  entry for /etc/keyd/default.conf."
	@echo ""
	@echo "  That already exists in system/geeeks.scm, with (auto-start? #t)"
	@echo "  as of 2026-08-08 -- the config proved itself across many hand-"
	@echo "  started boots first. So on this class there is NOTHING to set up:"
	@echo "  keyd is running, or 'make reconfigure' brings it up."
	@echo ""
	@echo "  The care now belongs on EDITS to %keyd-config, which take effect"
	@echo "  at boot rather than when you choose to start them. Test one on"
	@echo "  the running system before reconfiguring:"
	@echo ""
	@echo "    sudo herd restart keyd"
	@echo "    # confirm Caps acts as Control, and that C-a and C-f still"
	@echo "    # reach applications as control characters (no arrow layer)"
	@echo ""
	@echo "  (Two things catch a bad keyd either way: ctrl:swapcaps in the"
	@echo "  system keyboard-layout works with keyd dead, and GRUB still"
	@echo "  lists the previous generation.)"
	@echo ""
	@exit 1
else
	@echo "Automating system-level links for keyd..."
	mkdir -p /etc/keyd
	ln -sf $(REAL_HOME)/.guix-home/profile/bin/keyd /usr/local/bin/keyd
	ln -sf $(shell pwd)/keyd.conf /etc/keyd/default.conf
	ln -sf $(shell pwd)/keyd.service /etc/systemd/system/keyd.service
	systemctl daemon-reload
	@# reset-failed: a prior dangling symlink left the unit in a start-limit
	@# lockout; without this, enable --now can refuse to start it.
	systemctl reset-failed keyd 2>/dev/null || true
	systemctl enable --now keyd
	@echo "Done! Emacs keys and Caps/Ctrl swap are now live."
	@echo ""
	@echo "If GNOME is also swapping (double-swap = keys look UNswapped), clear"
	@echo "it as your normal user (gsettings talks to the user session, not root):"
	@echo "  gsettings set org.gnome.desktop.input-sources xkb-options '[]'"
endif
else
	@echo "OrbStack container detected: keyd cannot control the Mac keyboard here."
	@echo "Configure keybindings on the macOS host instead; no container setup is needed."
endif

.PHONY: setup-tailscale check-tailscale setup-orbstack check-orbstack setup-guix-container check-guix-container setup-guix-github-key setup-protondrive check-protondrive


# Proton Drive, the sync layer that replaced Dropbox.
#
# On WSL the installer is a WINDOWS program: the Drive client syncs for the
# Windows user, and the Linux side sees the result through /mnt/c.  There is no
# Linux Proton Drive client to install here, so this target reaches across the
# interop boundary and drives winget -- the first place in this Makefile that
# does, which is why the powershell invocation is spelled out rather than
# assumed.
#
#   -NoProfile              the user's PowerShell profile is irrelevant and slow
#   --accept-source-agreements   winget otherwise blocks on the msstore terms
#                                prompt and dies with 0x8a150042 under a pipe
#   --disable-interactivity      no TTY across the interop boundary
#
# Idempotent: winget list is the probe, so a second run reports and exits 0.
WIN_POWERSHELL := /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
PROTONDRIVE_WINGET_ID := Proton.ProtonDrive

setup-protondrive:
ifeq ($(flavor),wsl)
	@test -x $(WIN_POWERSHELL) || { \
	  echo "  *** no Windows PowerShell at $(WIN_POWERSHELL) ***"; \
	  echo "  Is /mnt/c mounted and WSL interop enabled?"; exit 1; }
	@if $(WIN_POWERSHELL) -NoProfile -Command \
	    "winget list --id $(PROTONDRIVE_WINGET_ID) --accept-source-agreements --disable-interactivity" \
	    2>/dev/null | grep -q '$(PROTONDRIVE_WINGET_ID)'; then \
	  echo "Proton Drive already installed (winget id $(PROTONDRIVE_WINGET_ID))"; \
	else \
	  echo "==> installing Proton Drive via winget"; \
	  $(WIN_POWERSHELL) -NoProfile -Command \
	    "winget install --id $(PROTONDRIVE_WINGET_ID) --accept-source-agreements --accept-package-agreements --disable-interactivity"; \
	fi
	@echo ""
	@echo "--- NEXT STEP: sign in and let it sync ---"
	@echo "Proton Drive is a GUI app: launch it on Windows, sign in, and wait for"
	@echo "the first sync.  Until then the folder below does not exist."
	@echo "Then run: make check-protondrive"
else ifeq ($(os),$(OS_MAC))
	@echo "macOS: Proton Drive is installed from the app, not winget."
	@echo "Startup and the espanso handoff are already owned by:"
	@echo "  bin/protondrive-ensure-running.sh"
	@echo "  bin/ensure-proton-and-espanso.sh"
else
	@echo "No Proton Drive setup for this platform ($(os)/$(flavor))."
endif

# Report where Proton Drive actually landed.  The Windows client syncs to a
# per-user folder whose name it decides; probe rather than hardcode, and print
# the path so the espanso handoff can be pointed at it.
check-protondrive:
ifeq ($(flavor),wsl)
	@found=0; \
	for d in /mnt/c/Users/*/"Proton Drive" /mnt/c/Users/*/ProtonDrive; do \
	  if [ -d "$$d" ]; then echo "    sync folder: $$d"; found=1; fi; \
	done; \
	if [ "$$found" = 0 ]; then \
	  echo "    no Proton Drive sync folder yet -- sign in on Windows first"; \
	fi
	@if $(WIN_POWERSHELL) -NoProfile -Command \
	    "winget list --id $(PROTONDRIVE_WINGET_ID) --accept-source-agreements --disable-interactivity" \
	    2>/dev/null | grep -q '$(PROTONDRIVE_WINGET_ID)'; then \
	  echo "    winget:      $(PROTONDRIVE_WINGET_ID) installed"; \
	else \
	  echo "    winget:      NOT installed (run: make setup-protondrive)"; \
	fi
else
	@echo "check-protondrive: WSL only ($(os)/$(flavor) here)."
endif

# The external store/database volumes must be restored together when moving
# machines. Compose deliberately refuses to silently replace a missing store.
setup-guix-container:
	 $(GUIX_DOCKER) volume create guix-dev-home
	 $(GUIX_DOCKER) compose -f compose.guix.yaml up -d
	 $(GUIX_DOCKER) exec guix-dev sh -lc 'guix package --install make git zsh less curl openssh guile nss-certs --install-from-expression="(@ (gnu packages base) glibc-utf8-locales)"'
	 $(MAKE) check-guix-container

# Create a key that belongs only to the persistent Guix container volume.  The
# private key never comes from the host and is never checked into this repo.
setup-guix-github-key: setup-guix-container
	 $(GUIX_DOCKER) exec -it guix-dev /root/dot_files/build-aux/setup-guix-github-key.sh

check-guix-container:
	 $(GUIX_DOCKER) compose -f compose.guix.yaml ps
	 $(GUIX_DOCKER) exec guix-dev sh -lc 'guix build --no-offload -f build-aux/guix-container-check.scm'
	 $(GUIX_DOCKER) exec guix-dev sh -lc 'export GUIX_PROFILE=/root/.guix-profile; . "$$GUIX_PROFILE/etc/profile"; make --version; git --version; less --version | head -1; ssh -V; guile --version | head -1; zsh --version'
	 $(GUIX_DOCKER) exec guix-dev sh -lc 'set -eu; diagnostics=$$(mktemp); trap '\''rm -f "$$diagnostics"'\'' EXIT; make help >/dev/null 2>"$$diagnostics"; if [ -s "$$diagnostics" ]; then cat "$$diagnostics" >&2; exit 1; fi'

# OrbStack as the one macOS container runtime.
#
# There are two independent pieces of state to own here.  launchd decides which
# VM starts at login, while ~/.docker/config.json decides which engine every
# later `docker' invocation talks to.  Colima can therefore be stopped while
# Docker still targets its dead socket, or Docker can target OrbStack while a
# hidden Colima VM starts and consumes resources.  setup-orbstack changes both.
#
# This is a user LaunchAgent rather than a system LaunchDaemon: OrbStack belongs
# to the graphical login session and keeps all VM state under the user's home.
# The source plist is copied because launchd state should not depend on this
# checkout being mounted when the user logs in.  check-orbstack catches drift.
#
# Deliberately NOT deleted: ~/.colima and any legacy Colima Docker contexts. They
# may contain the only copies of containers, images, or volumes.  Once their
# contents are known to be disposable they can be removed as a separate,
# explicitly destructive cleanup; they are inert after this target.
ORBSTACK_LABEL     := com.durantschoon.orbstack-start
ORBSTACK_PLIST_SRC := system/launchd/$(ORBSTACK_LABEL).plist
ORBSTACK_PLIST_DST := $(HOME)/Library/LaunchAgents/$(ORBSTACK_LABEL).plist
ORBSTACK_BIN       := /usr/local/bin/orb
DOCKER_BIN         := /usr/local/bin/docker
COLIMA_LABEL       := homebrew.mxcl.colima
DOCKER_DESKTOP_LABELS := com.docker.vmnetd com.docker.socket
# Prefer the Apple Silicon installation when both Homebrew prefixes exist.
# Deriving brew from the Colima path matters on this Mac: /usr/local/bin/brew
# is Intel Homebrew, while the installed Colima service belongs to /opt/homebrew.
COLIMA_BIN         := $(firstword $(wildcard /opt/homebrew/bin/colima /usr/local/bin/colima))
COLIMA_BREW        := $(patsubst %/colima,%/brew,$(COLIMA_BIN))

setup-orbstack:
ifneq ("$(os)","$(OS_MAC)")
	@echo ""
	@echo "  *** setup-orbstack is mac-only (detected $(os)) ***"
	@echo ""
	@exit 1
else
	@test -x $(ORBSTACK_BIN) || { \
	  echo "  *** OrbStack CLI not found at $(ORBSTACK_BIN) ***"; \
	  echo "  Install/open OrbStack first, then run this target again."; \
	  exit 1; \
	}
	@test -x $(DOCKER_BIN) || { \
	  echo "  *** OrbStack Docker CLI not found at $(DOCKER_BIN) ***"; \
	  echo "  Open OrbStack once so it can install its command-line links."; \
	  exit 1; \
	}
	@echo "==> stopping and disabling Colima's login service"
	@if [ -x "$(COLIMA_BREW)" ]; then \
	  "$(COLIMA_BREW)" services stop colima > /dev/null 2>&1 || true; \
	fi
	@launchctl bootout gui/$$(id -u)/$(COLIMA_LABEL) 2>/dev/null || true
	@if [ -x "$(COLIMA_BIN)" ]; then \
	  "$(COLIMA_BIN)" stop > /dev/null 2>&1 || true; \
	fi
	@# Colima 0.9 can leave Lima's shared usernet helper orphaned after its VM
	@# stops.  Signal only PIDs from Colima's own network pidfiles, and only
	@# after verifying the live command is limactl usernet rooted in ~/.colima.
	@for pidfile in "$(HOME)/.colima/_lima/_networks/"*/usernet_*.pid; do \
	  [ -f "$$pidfile" ] || continue; \
	  pid=$$(sed -n '1p' "$$pidfile"); \
	  case "$$pid" in ''|*[!0-9]*) continue ;; esac; \
	  cmd=$$(ps -p "$$pid" -o command= 2>/dev/null); \
	  case "$$cmd" in \
	    *'/limactl usernet '*'.colima/'*) \
	      echo "    stopping orphaned Colima usernet helper (pid $$pid)"; \
	      kill -TERM "$$pid" 2>/dev/null || true; \
	      n=0; \
	      while kill -0 "$$pid" 2>/dev/null; do \
	        n=$$((n+1)); \
	        if [ $$n -gt 50 ]; then \
	          echo "  *** Colima usernet pid $$pid did not stop after 5s ***"; \
	          exit 1; \
	        fi; \
	        sleep 0.1; \
	      done ;; \
	  esac; \
	done
	@launchctl disable gui/$$(id -u)/$(COLIMA_LABEL)
	@echo "==> stopping and disabling Docker Desktop's privileged helpers"
	@for label in $(DOCKER_DESKTOP_LABELS); do \
	  sudo launchctl bootout system/$$label 2>/dev/null || true; \
	  sudo launchctl disable system/$$label || exit 1; \
	done
	@echo "==> installing OrbStack login agent"
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	@install -m 644 $(ORBSTACK_PLIST_SRC) $(ORBSTACK_PLIST_DST)
	@launchctl bootout gui/$$(id -u)/$(ORBSTACK_LABEL) 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) $(ORBSTACK_PLIST_DST)
	@echo "==> starting OrbStack"
	@$(ORBSTACK_BIN) start
	@echo "==> selecting Docker context: orbstack"
	@$(DOCKER_BIN) context inspect orbstack > /dev/null
	@$(DOCKER_BIN) context use orbstack > /dev/null
	@echo ""
	@$(MAKE) --no-print-directory check-orbstack
endif

check-orbstack:
	@echo "==> OrbStack container runtime"
ifneq ("$(os)","$(OS_MAC)")
	@echo "    skipped: mac-only (detected $(os))"
else
	@rc=0; \
	if [ ! -x $(ORBSTACK_BIN) ]; then \
	  rc=1; echo "    MISSING: $(ORBSTACK_BIN)"; \
	else \
	  echo "    CLI:     $(ORBSTACK_BIN)"; \
	fi; \
	if [ ! -f $(ORBSTACK_PLIST_DST) ]; then \
	  rc=1; echo "    NOT DEPLOYED: $(ORBSTACK_PLIST_DST)"; \
	elif ! diff -u $(ORBSTACK_PLIST_SRC) $(ORBSTACK_PLIST_DST) > /dev/null 2>&1; then \
	  rc=1; echo "    DRIFT: deployed OrbStack LaunchAgent differs from the repo"; \
	  diff -u $(ORBSTACK_PLIST_SRC) $(ORBSTACK_PLIST_DST) || true; \
	elif launchctl print gui/$$(id -u)/$(ORBSTACK_LABEL) > /dev/null 2>&1; then \
	  echo "    startup: $(ORBSTACK_LABEL) (in sync, loaded)"; \
	else \
	  rc=1; echo "    NOT LOADED: gui/$$(id -u)/$(ORBSTACK_LABEL)"; \
	fi; \
	if launchctl print gui/$$(id -u)/$(COLIMA_LABEL) > /dev/null 2>&1; then \
	  rc=1; echo "    CONFLICT: $(COLIMA_LABEL) is still loaded"; \
	elif [ ! -x "$(COLIMA_BIN)" ] && [ ! -d "$(HOME)/.colima" ] \
	     && [ ! -d "$(HOME)/Library/Application Support/colima" ]; then \
	  echo "    Colima:  not installed"; \
	elif launchctl print-disabled gui/$$(id -u) 2>/dev/null \
	     | grep -Eq '"$(COLIMA_LABEL)" => (true|disabled)'; then \
	  echo "    Colima:  startup disabled"; \
	else \
	  rc=1; echo "    Colima:  not loaded, but not persistently disabled"; \
	fi; \
	colima_procs=$$(pgrep -fl '(/colima( |$$)|/limactl .*[/]\.colima[/])' 2>/dev/null || true); \
	if [ -z "$$colima_procs" ]; then \
	  echo "    process: no Colima/Lima helpers running"; \
	else \
	  rc=1; echo "    CONFLICT: Colima-related processes remain:"; \
	  echo "$$colima_procs" | sed 's/^/              /'; \
	fi; \
	for label in $(DOCKER_DESKTOP_LABELS); do \
	  if launchctl print system/$$label > /dev/null 2>&1; then \
	    rc=1; echo "    CONFLICT: Docker Desktop helper $$label is loaded"; \
	  elif launchctl print-disabled system 2>/dev/null \
	       | grep -Eq "\"$$label\" => (true|disabled)"; then \
	    echo "    Desktop: $$label disabled"; \
	  else \
	    rc=1; echo "    Desktop: $$label is not persistently disabled"; \
	  fi; \
	done; \
	desktop_procs=$$(pgrep -fl '(/Applications/Docker.app/|/Library/PrivilegedHelperTools/com\.docker\.)' 2>/dev/null || true); \
	if [ -z "$$desktop_procs" ]; then \
	  echo "    process: no Docker Desktop helpers running"; \
	else \
	  rc=1; echo "    CONFLICT: Docker Desktop processes remain:"; \
	  echo "$$desktop_procs" | sed 's/^/              /'; \
	fi; \
	cli=$$(readlink $(DOCKER_BIN) 2>/dev/null); \
	case "$$cli" in \
	  *OrbStack.app*) echo "    Docker:  $(DOCKER_BIN) -> $$cli" ;; \
	  *) rc=1; echo "    WRONG CLI: $(DOCKER_BIN) -> $${cli:-not a symlink}" ;; \
	esac; \
	context=$$($(DOCKER_BIN) context show 2>/dev/null); \
	if [ "$$context" = orbstack ]; then \
	  echo "    context: orbstack"; \
	else \
	  rc=1; echo "    WRONG CONTEXT: $${context:-unavailable} (wanted orbstack)"; \
	fi; \
	server=$$($(DOCKER_BIN) version --format '{{.Server.Version}}' 2>/dev/null); \
	if [ -n "$$server" ]; then \
	  echo "    engine:  reachable (Docker $$server)"; \
	else \
	  rc=1; echo "    ENGINE DOWN: Docker server did not answer"; \
	fi; \
	exit $$rc
endif

# Tailscale, as a system daemon rather than a menu-bar app.
#
# Deployed by COPY, not by symlink like everything else here: launchd rejects a
# daemon plist that is a symlink or is writable by a non-root user, and a plist
# in a user-owned checkout is both.  check-tailscale diffs the two so the copy
# cannot drift silently -- the same bargain check-keyd-sync makes.
#
# TWO daemons, because the exit node needs kernel IP forwarding and tailscaled
# will not set it on darwin -- see the header of the ip-forwarding plist.  The
# label IS the file name in both directions, so every path below derives from
# it and the loops stay uniform.
TAILSCALED_LABEL     := com.tailscale.tailscaled
TAILSCALE_FWD_LABEL  := com.tailscale.ip-forwarding
TAILSCALE_LABELS     := $(TAILSCALED_LABEL) $(TAILSCALE_FWD_LABEL)
TAILSCALED_PLIST_SRC := system/launchd/$(TAILSCALED_LABEL).plist
TAILSCALED_PLIST_DST := /Library/LaunchDaemons/$(TAILSCALED_LABEL).plist
TAILSCALED_BIN       := /opt/homebrew/bin/tailscaled
TAILSCALE_BIN        := /opt/homebrew/bin/tailscale

setup-tailscale:
ifneq ("$(os)","$(OS_MAC)")
	@echo ""
	@echo "  *** setup-tailscale is mac-only (detected $(os)) ***"
	@echo ""
	@echo "  launchd, /Library/LaunchDaemons and the utun driver are all"
	@echo "  Darwin.  On Linux, tailscaled is a distro package with a systemd"
	@echo "  unit, and on Guix System it belongs in system/<class>.scm as a"
	@echo "  service alongside keyd -- not in a Makefile target."
	@echo ""
	@exit 1
else
	@command -v brew > /dev/null 2>&1 || { \
	  echo "  *** Homebrew not found ***"; \
	  echo "  The daemon variant comes from the tailscale FORMULA (not the"; \
	  echo "  cask, which installs the per-user GUI app)."; \
	  exit 1; \
	}
	@# The formula, deliberately: `brew install --cask tailscale' gets you the
	@# standalone GUI app, which cannot run before login either.
	@test -x $(TAILSCALED_BIN) || brew install tailscale
	@# One tailnet client per machine.  The App Store app and this daemon keep
	@# separate state and would register as two nodes with the same hostname,
	@# then fight over routes and the default DNS resolver.
	@if /usr/sbin/scutil --nc list 2>/dev/null | grep -q '^\* (Connected).*io\.tailscale\.ipn\.macos'; then \
	  echo ""; \
	  echo "  *** the App Store Tailscale is CONNECTED ***"; \
	  echo "  Disconnect it before bootstrapping the daemon, or the two will"; \
	  echo "  register as separate nodes and fight over the default route."; \
	  echo ""; \
	  exit 1; \
	fi
	@echo "==> /Library/Tailscale (state dir; see the plist for why it is pinned)"
	@sudo mkdir -p /Library/Tailscale
	@# 700: tailscaled.state holds this node's private key.
	@sudo chmod 700 /Library/Tailscale
	@echo "==> /Library/LaunchDaemons (copies of system/launchd/*.plist)"
	@for label in $(TAILSCALE_LABELS); do \
	  echo "    $$label"; \
	  sudo install -o root -g wheel -m 644 \
	    system/launchd/$$label.plist /Library/LaunchDaemons/$$label.plist || exit 1; \
	done
	@echo "==> launchctl bootstrap system"
	@# bootout first: bootstrap on an already-loaded label is an error, not a
	@# no-op, so without this the target is not idempotent.  Then WAIT, because
	@# bootout is asynchronous: it returns as soon as launchd has signalled the
	@# job, not when the job is gone, and tailscaled still has to tear down its
	@# utun interfaces and close its DERP connections.  Bootstrapping into that
	@# window fails with the gloriously unhelpful "Bootstrap failed: 5:
	@# Input/output error" and leaves the machine OFF the tailnet -- old
	@# instance dead, new one refused.
	@for label in $(TAILSCALE_LABELS); do \
	  sudo launchctl bootout system/$$label 2>/dev/null || true; \
	  n=0; \
	  while launchctl print system/$$label > /dev/null 2>&1; do \
	    n=$$((n+1)); \
	    if [ $$n -gt 100 ]; then \
	      echo ""; \
	      echo "  *** $$label still loaded after 10s ***"; \
	      echo "  Something is holding the label.  Inspect it with:"; \
	      echo "    sudo launchctl print system/$$label"; \
	      echo ""; \
	      exit 1; \
	    fi; \
	    sleep 0.1; \
	  done; \
	  echo "    $$label"; \
	  sudo launchctl bootstrap system /Library/LaunchDaemons/$$label.plist || exit 1; \
	done
	@echo ""
	@echo "  tailscaled is running and will come back at boot, before login."
	@echo ""
	@echo "  It starts LOGGED OUT -- state does not carry over from the App"
	@echo "  Store app, whose keys live in its own sandbox container.  Auth"
	@echo "  this node once (opens a browser):"
	@echo ""
	@echo "    sudo $(TAILSCALE_BIN) up --advertise-exit-node"
	@echo ""
	@echo "  (--advertise-exit-node preserves what this machine already does:"
	@echo "   it advertises 0.0.0.0/0 and ::/0.  Approve it in the admin"
	@echo "   console afterwards; re-approval is needed because this is a new"
	@echo "   node key.)"
	@echo ""
	@echo "  Then stop the App Store app from coming back at login: quit it and"
	@echo "  turn off 'Run at login' in its settings, or delete Tailscale.app."
	@echo ""
	@echo "  Verify with: make check-tailscale"
	@echo ""
endif

# Answers "is this machine actually on the tailnet, and will it still be after
# a reboot?" -- which are different questions.  A running daemon that was
# started by hand satisfies the first and not the second, so the deployed plist
# is checked as carefully as the process.
#
# It also asserts the NAME, because the name is load-bearing here: EMACS_HOST
# defaults to `minius' and the `eam' alias hardcodes it, so both reach this
# machine by its MagicDNS name.  When a node re-registers while its name is
# still held by another node -- which is exactly what happened moving off the
# App Store app, since the daemon generates a fresh node key rather than
# inheriting the app's -- the control plane silently appends -1.  Nothing
# breaks loudly; `make emacs-attach' just starts dialling a node that no longer
# answers.  Comparing the registered name against the requested one turns that
# into a failed check.
#
# "Requested" is the daemon's own pref when set -- `tailscale set --hostname'
# lands in prefs and so survives re-auth, which a rename done in the admin
# console does not -- and otherwise macOS's LocalHostName, lowercased the way
# Tailscale would lowercase it.  (LocalHostName, not `uname -n': the latter is
# MiniUs.local here, and the .local would never match.)
check-tailscale:
	@echo "==> tailscaled system daemon"
ifneq ("$(os)","$(OS_MAC)")
	@echo "    skipped: mac-only (detected $(os))"
else
	@rc=0; \
	prog=$$(sed -n 's|^[[:space:]]*<string>\(/.*tailscaled\)</string>.*|\1|p' $(TAILSCALED_PLIST_SRC) | head -1); \
	if [ ! -x "$$prog" ]; then \
	  rc=1; \
	  echo "    MISSING: $$prog is not executable"; \
	  echo "             (the plist hardcodes the Apple Silicon brew prefix;"; \
	  echo "              an Intel Mac puts it under /usr/local)"; \
	else \
	  echo "    binary:  $$prog"; \
	fi; \
	for label in $(TAILSCALE_LABELS); do \
	  src=system/launchd/$$label.plist; dst=/Library/LaunchDaemons/$$label.plist; \
	  if [ ! -f $$dst ]; then \
	    rc=1; echo "    NOT DEPLOYED: $$dst -- run 'make setup-tailscale'"; \
	    continue; \
	  fi; \
	  if ! diff -u $$src $$dst > /dev/null 2>&1; then \
	    rc=1; \
	    echo "    DRIFT in $$label -- deployed copy and repo copy disagree:"; \
	    diff -u $$src $$dst || true; \
	    continue; \
	  fi; \
	  owner=$$(/usr/bin/stat -f '%Su:%Sg %Lp' $$dst); \
	  case "$$owner" in \
	    "root:wheel 644"|"root:wheel 600") ;; \
	    *) rc=1; \
	       echo "    BAD PERMS on $$label: $$owner"; \
	       echo "               (launchd wants root:wheel, not group/world writable)"; \
	       continue ;; \
	  esac; \
	  if launchctl print system/$$label > /dev/null 2>&1; then \
	    echo "    daemon:  $$label (in sync, $$owner, loaded)"; \
	  else \
	    rc=1; echo "    NOT LOADED: launchctl has no system/$$label"; \
	  fi; \
	done; \
	state=$$($(TAILSCALE_BIN) status --json 2>/dev/null \
	         | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -1); \
	case "$$state" in \
	  Running) echo "    tailnet: Running" ;; \
	  "")      rc=1; echo "    NO ANSWER from $(TAILSCALE_BIN) (daemon down, or socket path mismatch)" ;; \
	  *)       rc=1; echo "    BackendState=$$state -- try: sudo $(TAILSCALE_BIN) up --advertise-exit-node" ;; \
	esac; \
	want=$$($(TAILSCALE_BIN) debug prefs 2>/dev/null \
	        | sed -n 's/.*"Hostname": *"\([^"]*\)".*/\1/p' | head -1); \
	[ -n "$$want" ] || want=$$(scutil --get LocalHostName 2>/dev/null | tr 'A-Z' 'a-z'); \
	got=$$($(TAILSCALE_BIN) status --peers=false 2>/dev/null | awk 'NR==1{print $$2}'); \
	if [ -z "$$got" ]; then \
	  :; \
	elif [ "$$got" = "$$want" ]; then \
	  echo "    name:    $$got"; \
	else \
	  rc=1; \
	  echo "    NAME DRIFT: registered as '$$got', wanted '$$want'"; \
	  echo "                A node cannot claim a name another node still"; \
	  echo "                holds, so the control plane appended -N.  Delete"; \
	  echo "                the stale node in the admin console, then:"; \
	  echo "                  sudo $(TAILSCALE_BIN) set --hostname=$$want"; \
	fi; \
	v4=$$(sysctl -n net.inet.ip.forwarding 2>/dev/null); \
	v6=$$(sysctl -n net.inet6.ip6.forwarding 2>/dev/null); \
	if [ "$$v4" = "1" ] && [ "$$v6" = "1" ]; then \
	  echo "    forward: ipv4=1 ipv6=1"; \
	else \
	  rc=1; \
	  echo "    IP FORWARDING OFF: ipv4=$$v4 ipv6=$$v6"; \
	  echo "                Exit-node clients get silently dropped by the"; \
	  echo "                kernel.  tailscaled warns about this but has no"; \
	  echo "                code to set it on darwin, which is why"; \
	  echo "                $(TAILSCALE_FWD_LABEL) exists.  Fix:"; \
	  echo "                  make setup-tailscale"; \
	fi; \
	if /usr/sbin/scutil --nc list 2>/dev/null | grep -q '^\* (Connected).*io\.tailscale\.ipn\.macos'; then \
	  rc=1; \
	  echo "    CONFLICT: the App Store Tailscale is also connected"; \
	  echo "              (two nodes, same hostname, fighting over routes)"; \
	fi; \
	exit $$rc
endif

update: warn-dotfiles-home
	@echo "==> guix pull"
	@guix pull
	@echo "==> pin channels.scm"
	@# `guix describe' reports the guix that RUNS it, so this must be the
	@# pulled one: PATH's guix would pin root's revision, not the pull's.
	@$(PULLED_GUIX) describe --format=channels > channels.scm
	@echo "==> guix home reconfigure  (guix: $(PULLED_GUIX))"
	@$(PULLED_GUIX) home reconfigure home/base.scm
	@echo "==> refreshing .spacemacs.env against the new generation"
	@$(MAKE) --no-print-directory emacs-env
	@echo "==> ensuring Claude Code is installed (idempotent; re-patches if broken)"
	@$(MAKE) --no-print-directory install-claude

install-manifest:
	@echo "==> guix package -m manifests/base.scm"
	@guix package -m manifests/base.scm

home-check:
	@echo "==> arch & guix"
	@uname -m && guix --version
	@echo "==> weather for base manifest (bordeaux often best for aarch64)"
	@guix weather -m manifests/base.scm --substitute-urls="https://ci.guix.gnu.org https://bordeaux.guix.gnu.org" || true

# End Guix Home bootstrap targets

# ---------------------------------------------------------------------------
# system/ integrity checks
#
# A host class config in system/ has to be evaluable by root from the installer
# ISO during `guix system init', when no home directory exists and this checkout
# may be anywhere.  That forces it to INLINE what it needs rather than read
# ../keyd.conf or system/channels-<class>.scm beside it -- see
# system/README.md.  The price is duplicated text in three places, and
# duplicated text drifts: that is how the [control:C] keyd layer survived being
# removed from one copy, and how home/wayland.scm fell six packages behind
# home/base.scm.  These targets make the duplication checkable instead.
# ---------------------------------------------------------------------------
# If you ADD a check here, stage this Makefile in the same commit as the files it
# guards.  githooks/pre-commit runs these against the index, Makefile included, so
# an unstaged new target makes the hook fail with "No rule to make target" instead
# of a real finding -- which still blocks the commit and so reads like a catch.
# The hook warns when this Makefile has unstaged changes; see the note there.
.PHONY: check check-system check-keyd-sync check-channels-sync check-system-secrets
.PHONY: check-system-hosts install-hooks add-pkg reconfigure
.PHONY: check-session-coupling

# add-pkg -- add a package spec to home/common.scm.
#
#   make add-pkg PKG=htop                     %base-packages: every session
#   make add-pkg PKG=foo WAYLAND_ONLY=1       %wayland-packages: Wayland only
#
# Since the 2026-08-13 fold there is ONE file to edit -- both package lists
# live in home/common.scm, and the old both-files dance (with its documented
# misses: aspell a9503ff; cmake, openjdk, clojure-tools, just 6cae015) is
# structurally impossible to repeat.  WAYLAND_ONLY now selects the LIST, not
# the file: %wayland-packages reaches only sessions whose record says
# (wayland? . #t).
#
# Note what WAYLAND_ONLY does NOT cover: firefox-style packages, gated on
# nonguix-substitutes? rather than wayland?, are wired in dotfiles-home by
# hand -- they are a conditional in code, not a member of either list, and a
# package that must not reach foreign-distro daemons needs that treatment,
# not a list entry.  See the firefox conditional in common.scm.
#
# The spec is resolved against channels.scm -- the pin `make apply' pulls --
# rather than against whatever guix happens to be on PATH. Those differ, and the
# difference is not academic: on this box the ambient root guix has nonguix and
# resolves "firefox" happily, while channels.scm may not, so an ambient check
# would accept a spec that then fails the reconfigure. That is the trap
# common.scm documents in its librewolf comment. FAST=1 uses the
# ambient guix when you would rather have the seconds back; SKIP_CHECK=1 skips
# resolution entirely, which is what you want when adding a package from a
# channel you are adding in the same commit.
ADD_PKG_FILES := home/common.scm
ADD_PKG_LIST := %base-packages
ifdef WAYLAND_ONLY
ADD_PKG_LIST := %wayland-packages
endif

add-pkg:
	@test -n "$(PKG)" || { \
	  echo "usage: make add-pkg PKG=<spec> [WAYLAND_ONLY=1] [FAST=1] [SKIP_CHECK=1]"; \
	  exit 2; \
	}
	@if [ -n "$(SKIP_CHECK)" ]; then \
	  echo "==> resolving \"$(PKG)\": skipped (SKIP_CHECK)"; \
	elif [ -n "$(FAST)" ]; then \
	  echo "==> resolving \"$(PKG)\" against the ambient guix (FAST)"; \
	  guix show $(PKG) >/dev/null 2>&1 || { \
	    echo "    \"$(PKG)\" does not resolve. Typo, or wrong channel."; exit 1; }; \
	else \
	  echo "==> resolving \"$(PKG)\" against channels.scm"; \
	  guix time-machine -C channels.scm -- show $(PKG) >/dev/null 2>&1 || { \
	    echo "    \"$(PKG)\" does not resolve against channels.scm."; \
	    echo "    A typo, or a package from a channel channels.scm does not declare."; \
	    echo "    Re-run with SKIP_CHECK=1 if you are adding that channel in this commit."; \
	    exit 1; }; \
	fi
	@echo "==> adding \"$(PKG)\" to $(ADD_PKG_FILES)"
	@t=$$(mktemp -d); trap 'rm -rf $$t' EXIT; \
	for f in $(ADD_PKG_FILES); do cp $$f $$t/$$(basename $$f); done; \
	for f in $(ADD_PKG_FILES); do \
	  guile --no-auto-compile -s build-aux/add-pkg.scm $$f "$(PKG)" "$(ADD_PKG_LIST)" || { \
	    echo "    failed on $$f -- restoring every file this target touched"; \
	    for g in $(ADD_PKG_FILES); do cp $$t/$$(basename $$g) $$g; done; \
	    exit 1; }; \
	done
	@# A spec whose NAME trips the compositor-coupling regex (gnome-tweaks,
	@# gdm-settings...) fails here, at add time, rather than at commit time --
	@# route it through the session record or tag the inserted line.
	@$(MAKE) --no-print-directory check-session-coupling
	@# Which config this machine deploys is a property of the MACHINE, not of the
	@# session: $$WAYLAND_DISPLAY is unset when you log into a tty on the very box
	@# that deploys wayland.scm, and would offer to apply the wrong config. The
	@# Guix System box is the one that deploys wayland.scm, so test for that.
	@# Gated on a tty so the pre-commit hook and any non-interactive caller do not
	@# hang waiting on a read that will never come.
	@if [ ! -t 0 ]; then \
	  echo "==> not a terminal; not offering to apply"; \
	elif [ -d /run/current-system ]; then \
	  printf '==> run `make apply-wayland` now? [y/N] '; read r; \
	  case "$$r" in [Yy]*) $(MAKE) apply-wayland ;; *) echo "    skipped" ;; esac; \
	else \
	  printf '==> run `make apply` now? [y/N] '; read r; \
	  case "$$r" in [Yy]*) $(MAKE) apply ;; *) echo "    skipped" ;; esac; \
	fi

# The host class configs -- every system/*.scm that is not a channel pin.
# Written as a filter-out over two wildcards rather than a `system/[!c]*' style
# glob so that a future class whose name happens to start with "c" is not
# silently dropped from every check below.
SYSTEM_PINS    := $(wildcard system/channels-*.scm)
SYSTEM_CONFIGS := $(filter-out $(SYSTEM_PINS),$(wildcard system/*.scm))

.PHONY: setup-espanso-windows check-espanso-windows

# espanso on a WSL machine runs on the WINDOWS side -- a Linux espanso cannot
# see keystrokes typed into Windows apps, which is why the espanso layer is
# off in %foreign-session and check-home-ownership reports its files as
# "absent -- OK".  The config is the one Proton Drive already syncs (the same
# folder bin/ensure-proton-and-espanso.sh points the Mac at), so all that is
# needed is to make Windows espanso read it instead of its own private copy in
# AppData\Roaming\espanso: ESPANSO_CONFIG_DIR, persisted with setx.
#
# Three things learned the hard way, each load-bearing below:
#   - cd /mnt/c first.  Windows programs inherit the cwd, a WSL cwd is a
#     \\wsl.localhost UNC path, and cmd.exe (espanso.cmd is a cmd script)
#     refuses UNC: "UNC paths are not supported".
#   - the restart is a detached Start-Process, never `espanso restart' in a
#     pipeline.  The daemon it spawns inherits the pipe and holds it open, so
#     the recipe would hang long after the restart itself had finished.
#   - the PowerShell lives in build-aux/*.ps1 and is fed on stdin
#     (-Command -).  Inlined in a recipe, make's backslash-newlines survive
#     inside the shell's single quotes and PowerShell chokes on every one;
#     -File is no better, since the script's path would be a UNC path too.
#   - setx only affects processes started LATER, so the variable is also set
#     in the PowerShell session that does the restart; otherwise the new
#     daemon would come up still reading the old directory until next login.
#
# The Proton folder is found by glob (Proton Drive\<account>\My files\espanso):
# this repo is public and the account name does not belong in it.
setup-espanso-windows:
ifeq ($(flavor),wsl)
	@cd /mnt/c && $(WIN_POWERSHELL) -NoProfile -Command - \
	  < "$(CURDIR)/build-aux/espanso-windows-setup.ps1"
	@$(MAKE) --no-print-directory check-espanso-windows
else
	@echo "setup-espanso-windows: WSL only ($(os)/$(flavor) here)."
endif

check-espanso-windows:
ifeq ($(flavor),wsl)
	@echo "==> espanso on the Windows side"
	@cd /mnt/c && $(WIN_POWERSHELL) -NoProfile -Command - \
	  < "$(CURDIR)/build-aux/espanso-windows-check.ps1"
else
	@echo "check-espanso-windows: WSL only ($(os)/$(flavor) here)."
endif

.PHONY: check-home-ownership

# Who actually owns each dotfile in $$HOME: Guix Home, the native symlinks, or
# neither.  The point is to make a half-migrated account visible, because that
# state is otherwise silent -- both kinds of link are just symlinks, and `ls'
# does not tell you which system intends to manage them.
#
# The claimed set is DERIVED, not restated, so this cannot drift as the config
# grows.  It is the union of three sources, because no single one is complete:
#
#   home/common.scm, grepped  home-files-service-type entries written as
#                            `(".aliases" ,(local-file ...)).  Works BEFORE the
#                            first apply, which is when it matters most, but
#                            misses any entry whose name is computed (the
#                            per-skill .claude/skills/<name> entries are).
#   ~/.guix-home/files       what the active generation really deployed: exact,
#                            computed entries included, but only exists once a
#                            generation has been activated.
#   GUIX_ZSH_OWNED           home-zsh-service-type SYNTHESISES its files out of
#                            the zshrc/zshenv/zprofile field lists, so before
#                            an apply they appear nowhere.  Note WHERE they
#                            land: under ~/.config/zsh, with only a
#                            ZDOTDIR-setting stub at ~/.zshenv.  ~/.zshrc is
#                            NOT claimed -- with ZDOTDIR set, zsh never reads
#                            it, so a leftover native ~/.zshrc is dead weight,
#                            not a conflict.  That layout is fixed by the
#                            service type, not by our config, so naming it here
#                            is a constant rather than a duplicated fact.
#
# Beyond ownership it reports two HAZARDS.  Both are states in which `guix home
# reconfigure' does damage or dies, both come from the symlink manager's backup
# step (gnu/home/services/symlink-manager.scm), and both were found the hard
# way on the first WSL apply:
#
#   symlinked ancestor   ~/.ipython -> ~/dot_files/.ipython, guix claims
#                        .ipython/profile_default/startup/x.py.  The manager
#                        backs up a colliding path only when it is NOT a
#                        directory, and it asks with file-is-directory?, which
#                        FOLLOWS symlinks.  So the symlink is kept, mkdir's
#                        EEXIST is swallowed, and the walk continues through it
#                        -- deleting the real files on the far side and leaving
#                        /gnu/store symlinks INSIDE THE GIT REPO.
#   real directory       guix wants a symlink where a real directory stands.
#                        The backup is a copy-file, which cannot copy a
#                        directory: "sendfile: Is a directory", and the
#                        activation aborts half-done, before ~/.guix-home
#                        exists, with some paths already switched over.
#
# An ABSENT path gets one more distinction once a generation is active: if
# common.scm declares it but ~/.guix-home/files does not contain it, its layer
# is simply off for this session (espanso under %foreign-session, say), and the
# report says so instead of leaving a bare "absent" that reads like a fault.
# That is derived from the generation, not from a list of layers kept here.
#
# The path column is coloured (cyan) so the two columns stay apart even where a
# long path overruns its 28 characters and the padding disappears.  Only on a
# terminal, and never with NO_COLOR set or TERM=dumb: piped into a file, a
# pager or `grep', the output stays plain text with no escape codes in it.
#
# Exit status.  Normally: non-zero only when a generation is active and
# something is wrong, so `make check' stays green on a native-only machine
# where none of this applies.  With PREFLIGHT=1 (how `apply' calls it):
# non-zero iff a hazard exists, active generation or not -- and conflicts are
# NOT fatal there, because applying is precisely what resolves a conflict.
GUIX_ZSH_OWNED := .zshenv .config/zsh/.zshenv .config/zsh/.zshrc .config/zsh/.zprofile

check-home-ownership:
	@echo "==> \$$HOME dotfiles: Guix Home vs native symlinks"
	@guix_home=0; [ -e "$$HOME/.guix-home" ] && guix_home=1; \
	deployed=""; \
	if [ $$guix_home -eq 1 ]; then \
	  deployed="$$(cd "$$HOME/.guix-home/files/" 2>/dev/null && find . -mindepth 1 ! -type d | sed 's|^\./||')"; \
	fi; \
	claimed="$$( { printf '%s\n' $(GUIX_ZSH_OWNED) $$deployed; \
	              grep -oE '`\("[^"]+"' home/common.scm | sed 's/^`("//; s/"$$//'; } | sort -u)"; \
	dfroot="$$(cd "$(DOTFILES_HOME)" 2>/dev/null && pwd -P)"; \
	[ -n "$$dfroot" ] || dfroot="/nonexistent"; \
	conflicts=0; hazards=0; inactive=0; espanso_off=0; \
	c1=""; c0=""; \
	if [ -t 1 ] && [ -z "$$NO_COLOR" ] && [ "$$TERM" != dumb ]; then \
	  c1="$$(printf '\033[36m')"; c0="$$(printf '\033[0m')"; \
	fi; \
	for p in $$claimed; do \
	  t="$$HOME/$$p"; \
	  anc=""; rest="$$p"; via=""; \
	  while case "$$rest" in */*) true ;; *) false ;; esac; do \
	    anc="$${anc:+$$anc/}$${rest%%/*}"; rest="$${rest#*/}"; \
	    if [ -L "$$HOME/$$anc" ]; then via="$$anc"; break; fi; \
	  done; \
	  if [ -n "$$via" ]; then \
	    printf '    %s%-28s%s %s\n' "$$c1" "$$p" "$$c0" "HAZARD: ~/$$via is a symlink -> $$(readlink "$$HOME/$$via")"; \
	    hazards=1; continue; \
	  fi; \
	  if [ ! -e "$$t" ] && [ ! -L "$$t" ]; then \
	    owner="absent"; \
	    if [ $$guix_home -eq 1 ] && ! printf '%s\n' $$deployed | grep -qxF "$$p"; then \
	      owner="absent -- OK: not part of this session"; inactive=1; \
	      case "$$p" in .config/espanso/*) espanso_off=1 ;; esac; \
	    fi; \
	  elif [ -L "$$t" ]; then \
	    dest="$$(readlink -f "$$t" 2>/dev/null)"; \
	    case "$$dest" in \
	      /gnu/store/*) owner="guix" ;; \
	      "$$dfroot"/*) owner="native" ;; \
	      *) owner="other -> $$dest" ;; \
	    esac; \
	  elif [ -d "$$t" ]; then \
	    owner="real directory"; \
	  else \
	    owner="real file"; \
	  fi; \
	  case "$$owner" in \
	    "real directory") \
	      printf '    %s%-28s%s %s\n' "$$c1" "$$p" "$$c0" "HAZARD: real directory where guix wants a symlink"; \
	      hazards=1 ;; \
	    native|"real file") \
	      if [ $$guix_home -eq 1 ]; then \
	        printf '    %s%-28s%s %s\n' "$$c1" "$$p" "$$c0" "CONFLICT: $$owner, but Guix Home is active"; \
	        conflicts=1; \
	      else \
	        printf '    %s%-28s%s %s\n' "$$c1" "$$p" "$$c0" "$$owner"; \
	      fi ;; \
	    *) printf '    %s%-28s%s %s\n' "$$c1" "$$p" "$$c0" "$$owner" ;; \
	  esac; \
	done; \
	if [ $$guix_home -eq 0 ]; then \
	  echo "    (no ~/.guix-home: no home generation active, so native ownership is expected)"; \
	fi; \
	if [ $$inactive -eq 1 ]; then \
	  echo ""; \
	  echo "    \"absent -- OK\" = home/common.scm declares the path, but the ACTIVE generation"; \
	  echo "    does not deploy it: its layer is switched off for this session (the apply"; \
	  echo "    output says which, as \"inactive (unmet session facts)\").  Wanted, not broken."; \
	  if [ $$espanso_off -eq 1 ] && [ "$(flavor)" = wsl ]; then \
	    echo "    espanso in particular: this is guix inside WSL, and we want it this way --"; \
	    echo "    a Linux espanso cannot see keystrokes typed into Windows apps, so espanso"; \
	    echo "    runs on the WINDOWS side, reading the same config out of Proton Drive."; \
	    echo "    See: make check-espanso-windows"; \
	  fi; \
	fi; \
	if [ $$hazards -eq 1 ]; then \
	  echo ""; \
	  echo "    HAZARD = \`guix home reconfigure' will do damage or abort half-done here."; \
	  echo "      symlinked ancestor: guix walks THROUGH it and replaces the files on the"; \
	  echo "        far side (your git repo) with store symlinks.  Fix: rm the symlink --"; \
	  echo "        only the link; guix then makes a real directory in its place."; \
	  echo "      real directory: guix backs up with copy-file, which cannot copy a"; \
	  echo "        directory (\"sendfile: Is a directory\").  Fix: mv it aside, e.g. to"; \
	  echo "        <name>.native_BAK, and move any contents you need back afterwards."; \
	fi; \
	if [ $$conflicts -eq 1 ]; then \
	  echo ""; \
	  echo "    CONFLICT = claimed by Guix Home but currently something else, so Guix Home"; \
	  echo "    will not see your repo edits for it.  Run: make apply  (guix backs up a"; \
	  echo "    colliding FILE by itself, into ~/<timestamp>-guix-home-legacy-configs-backup)."; \
	fi; \
	if [ -n "$(PREFLIGHT)" ]; then \
	  [ $$hazards -eq 0 ]; \
	elif [ $$guix_home -eq 1 ]; then \
	  [ $$hazards -eq 0 ] && [ $$conflicts -eq 0 ]; \
	fi

# check-protondrive earns its place here for the same reason check-tailscale
# does: it only probes.  `winget list' and a few [ -d ] tests read state and
# change none of it, so the no-side-effects contract below still holds, and off
# WSL the target degrades to a single printed line.  (check-guix-container is
# absent by contrast because it needs a running container, not because reaching
# across to Windows is itself disqualifying.)
check: check-system check-session-coupling check-tailscale check-orbstack check-protondrive check-espanso-windows check-home-ownership
	@echo "==> all checks passed"

check-system: check-system-hosts check-keyd-sync check-channels-sync check-system-secrets
	@echo "==> system/: all checks passed"

# The end-to-end gate for .jobs.zsh and bin/job-tee.  Deliberately NOT a
# prerequisite of `check': every other check above only reads files, while this
# one starts two tmux servers, a container and a launchd agent (all under a
# per-run scratch $TMPDIR that its EXIT trap removes).  `check' must stay
# something you can run on any machine at any time without side effects.
# tee-smoke.zsh goes first because it is the only one of the three that runs
# ANYWHERE: bin/job-tee needs a scratch directory, a real /bin/sh and a signal,
# none of which are a machine's to refuse, while the two below need tmux and
# launchd. It is also the layer underneath them, so a failure there explains
# failures in the others rather than being explained by them.
.PHONY: check-jobs
check-jobs:
	@./tests/jobs/tee-smoke.zsh
	@./tests/jobs/smoke.zsh
	@./tests/jobs/claude-smoke.zsh

# The container half of .jobs.zsh against a REAL engine -- the one thing
# check-jobs above cannot do, because its `docker' and `podman' are scratch-dir
# scripts that record argv and so can only prove what was ASKED, never what was
# ANSWERED.  Needs a live container engine (podman or docker); without one the
# script prints one SKIP line and exits 0, so it is safe to invoke anywhere.
# Like check-jobs, deliberately NOT a prerequisite of `check': it starts real
# containers, and `check' must stay something you can run on any machine at any
# time without side effects.
.PHONY: check-jobs-live
check-jobs-live:
	@./tests/jobs/podman-live.zsh

# bin/submodule-publish and the rewritten submodule-pull, against scratch repos
# built in a `mktemp -d' area the test removes again: a bare "remote", a clone
# acting as a submodule's origin, and superprojects carrying them.  No network,
# and this repo's own `claude' and `espanso/private' are never touched.
#
# Deliberately NOT a prerequisite of `check', for the same reason as check-jobs:
# it makes commits and pushes (inside the scratch area), and `check' must stay
# something you can run on any machine at any time without side effects.
.PHONY: check-submodule-publish
check-submodule-publish:
	@./tests/submodule/publish-smoke.zsh

# The file name IS the host class, and a machine of that class takes the class
# name as its host name -- so you pick a config to reconfigure with by reading
# `hostname' and reaching for system/<that>.scm.  Nothing enforces the pairing at
# deploy time: `guix system reconfigure' will happily apply another class's
# config, which hardcodes disk labels, firmware and a bootloader target.  The
# naming convention is the only signal, so this check keeps it honest rather than
# letting a rename quietly point a name at the wrong hardware.
check-system-hosts:
	@echo "==> system/*.scm file name vs (host-name ...)"
	@rc=0; \
	for f in $(SYSTEM_CONFIGS); do \
	  want=$$(basename $$f .scm); \
	  got=$$(sed -n 's/^[[:space:]]*(host-name[[:space:]]*"\([^"]*\)").*/\1/p' $$f | head -1); \
	  if [ -z "$$got" ]; then \
	    rc=1; echo "    $$f: no (host-name ...) found"; \
	  elif [ "$$want" = "$$got" ]; then \
	    echo "    $$f: host-name \"$$got\""; \
	  else \
	    rc=1; \
	    echo "    $$f: MISMATCH -- host-name is \"$$got\", so this file should be system/$$got.scm"; \
	  fi; \
	done; \
	exit $$rc

# check-home-sync used to live here: home/wayland.scm was a divergent COPY of
# home/base.scm, and the check verified base SUBSET-OF wayland after packages
# kept landing in one file and silently never reaching the machine deploying
# the other (aspell a9503ff; cmake, openjdk, clojure-tools, just, the IPython
# startup files, claude-code-ide 6cae015).  The 2026-08-13 fold made both
# files three-line entries into home/common.scm, so there are no longer two
# copies to drift and nothing for the check to check.  If a second home
# variant ever grows back as a COPY rather than a session record in
# common.scm, resurrect this from git history -- or better, do not let it.

# core.hooksPath rather than copying into .git/hooks: the hook stays a tracked
# file, so editing githooks/pre-commit takes effect immediately with no second
# install step to forget.  It is repo-local config and therefore not something
# a fresh clone inherits -- run this once per clone.
#
# Safe here because .git/hooks holds nothing but the stock .sample files; if you
# ever add a hook of your own, put it in githooks/ too, since hooksPath replaces
# that directory wholesale rather than merging with it.
install-hooks:
	@chmod +x githooks/pre-commit
	@git config core.hooksPath githooks
	@echo "==> core.hooksPath -> githooks"
	@echo "    pre-commit runs the checks when home/, system/, keyd.conf or the"
	@echo "    Makefile are staged; bypass with git commit --no-verify"

# Compares FUNCTIONAL lines only (comments and blanks stripped), so the two
# copies may explain themselves differently -- keyd.conf carries the long-form
# rationale -- while the bindings themselves must match exactly.
#
# Only configs that actually inline a keyd config are checked.  keyd is a laptop
# concern (it remaps a physical keyboard); a headless cloud machine has no
# %keyd-config and must not be reported as drifted for not having one.  If NO
# config inlines it, that is reported rather than passing silently -- a check
# that quietly matches nothing is worse than no check.
check-keyd-sync:
	@echo "==> keyd.conf vs %keyd-config in system/*.scm"
	@rc=0; found=0; \
	for f in $(SYSTEM_CONFIGS); do \
	  grep -q 'plain-file "keyd-default.conf"' $$f || continue; \
	  found=1; \
	  a=$$(mktemp); b=$$(mktemp); \
	  grep -vE '^[[:space:]]*#|^[[:space:]]*$$' keyd.conf > $$a; \
	  sed -n '/plain-file "keyd-default.conf"/,/^"))/p' $$f \
	    | sed '1d;$$d' | sed 's/^[[:space:]]*"//' \
	    | grep -vE '^[[:space:]]*#|^[[:space:]]*$$' > $$b; \
	  if diff -u $$a $$b > /dev/null 2>&1; then \
	    echo "    $$f: in sync"; \
	  else \
	    rc=1; \
	    echo "    $$f: DRIFT -- the deployed keyd config and the repo copy disagree:"; \
	    diff -u $$a $$b || true; \
	  fi; \
	  rm -f $$a $$b; \
	done; \
	if [ $$found -eq 0 ]; then \
	  echo "    NOTE: no system config inlines keyd; keyd.conf is unguarded"; \
	fi; \
	exit $$rc

# Compares channel names, URLs, commits and fingerprints as an unordered set,
# so formatting and the (define ...) wrapper are free to differ.
#
# Each host class config pairs with system/channels-<class>.scm.  A missing pin
# is a FAILURE, not a skip: the pin is what `guix time-machine -C' consumes to
# rebuild a machine of that class from the installer ISO, and noticing it is
# absent on the ISO -- with no network and no editor -- is the worst possible
# time.
check-channels-sync:
	@echo "==> system/channels-<class>.scm vs %system-channels"
	@rc=0; \
	pat='\(name .[a-z]+|"[0-9a-f]{40}"|https://[^"]+|[0-9A-F]{4} [0-9A-F ]+[0-9A-F]{4}'; \
	for f in $(SYSTEM_CONFIGS); do \
	  host=$$(basename $$f .scm); pin=system/channels-$$host.scm; \
	  if [ ! -f $$pin ]; then \
	    rc=1; echo "    $$f: MISSING $$pin (the pin guix time-machine -C needs)"; \
	    continue; \
	  fi; \
	  a=$$(mktemp); b=$$(mktemp); \
	  grep -oE "$$pat" $$pin | sort > $$a; \
	  sed -n '/define %system-channels/,/^$$/p' $$f | grep -oE "$$pat" | sort > $$b; \
	  if [ ! -s $$b ]; then \
	    rc=1; echo "    $$f: no %system-channels found -- did the define get renamed?"; \
	  elif diff -u $$a $$b > /dev/null 2>&1; then \
	    echo "    $$f: in sync with $$pin"; \
	  else \
	    rc=1; \
	    echo "    $$f: DRIFT -- the install-time pin and the deployed pin disagree:"; \
	    diff -u $$a $$b || true; \
	  fi; \
	  rm -f $$a $$b; \
	done; \
	exit $$rc

# Anything an operating-system record puts in the store is world-readable ON THE
# MACHINE -- activation scripts included -- so an inlined secret leaks to every
# local user no matter who can read this repo.  Secrets get referenced by path
# and deployed out of band; see the table in system/README.md.
#
# The field is `password', NOT `hashed-password' -- that is NixOS's name, and
# grepping for it catches nothing on Guix.  See (gnu system accounts) line 75:
#
#   (password  user-account-password (default #f))
#
# `(password #f)' is the safe value and the default, so the pattern below
# deliberately allows `#' after the field name and rejects everything else.
# `(crypt ...)' gets its own alternative because the common idiom embeds the
# PLAINTEXT: (password (crypt "hunter2" "$6$salt")).
#
# The leading ^[^;]* confines the match to code: a Scheme comment starts with
# `;', which the character class cannot cross, so documentation like the nmcli
# example in geeeks.scm does not trip it.
check-system-secrets:
	@echo "==> system/*.scm for inlined credentials"
	@if grep -nE '^[^;]*(\(password[[:space:]]+[^#)[:space:]]|\(crypt[[:space:]]|hashed-password|private-key|psk|BEGIN [A-Z ]*PRIVATE KEY)' system/*.scm; then \
	  echo ""; \
	  echo "    FAIL: that belongs on the machine, not in a config."; \
	  echo "    Whatever goes here is spliced into an activation gexp"; \
	  echo "    (gnu/system/shadow.scm:422) and lands in /gnu/store, which is"; \
	  echo "    world-readable -- so this leaks locally even in a private repo."; \
	  echo ""; \
	  echo "    account password -> leave (password #f), set it with passwd"; \
	  echo "    wifi PSK         -> NetworkManager keeps it in /etc/NetworkManager/system-connections/"; \
	  echo "    private keys     -> reference a path, deploy the file separately"; \
	  exit 1; \
	else \
	  echo "    clean"; \
	fi

# check-session-coupling -- compositor reliance stays behind the session
# records in home/common.scm.
#
# The trap this guards is a GNOME assumption that works today and fails only
# when the session changes -- silently, months later, with nothing connecting
# the symptom to the cause.  The espanso backend was the motivating case: on
# GNOME Wayland, Mutter lacks wlr-data-control, so espanso's clipboard path
# pastes stale clipboard contents instead of the expansion.  The fix is one
# YAML line, and NOTHING about that line says "GNOME" -- under a compositor
# that has the protocol it becomes wrong in the opposite direction, and grep
# would never find it.  docs/EWM_TRIAL_PLAN.md used to carry the inventory as prose;
# prose drifts, so this makes it mechanical, same as check-keyd-sync.
#
# The contract: every CODE line (comments stripped) matching the coupling
# pattern must carry a `[session]' tag in a comment on that same line.  The
# tag asserts "this line is session-aware" -- it is either part of the
# %session record itself, or a consumer gated through session-ref.  An
# untagged match is a new naked coupling: route it through %session, or tag
# it if it genuinely is the switch.
#
# Two scope notes, said out loud rather than discovered:
#
#   - Comment-stripping is the same `;.*' heuristic check-system-secrets
#     uses, so a `;' inside a code string false-strips the rest of that line.
#     That can only HIDE a coupling on such lines, never false-fail, which is
#     the right direction for a lint.
#   - ALL of home/*.scm is walked since the 2026-08-13 fold: base.scm and
#     wayland.scm are three-line entries into common.scm now, and the session
#     records all live in common.scm, so the old base.scm exemption has
#     nothing left to exempt.
#   - The [ -e ] guard keeps the hook's staged-tree runs honest: a commit
#     touching only system/ exports no home/, and an unexpanded home/*.scm
#     glob would otherwise hand awk a nonexistent file.
check-session-coupling:
	@echo "==> compositor coupling confined to [session]-tagged lines"
	@rc=0; \
	for f in home/*.scm $(SYSTEM_CONFIGS); do \
	  [ -e "$$f" ] || continue; \
	  hits=$$(awk '{ orig=$$0; code=$$0; sub(/;.*/, "", code); \
	    if (tolower(code) ~ /gnome|gsettings|gdm|mutter|wlr-data|desktop-services|pinentry-gnome/ \
	        && orig !~ /\[session\]/) \
	      printf "    %s:%d: %s\n", FILENAME, FNR, orig }' $$f); \
	  if [ -n "$$hits" ]; then rc=1; echo "$$hits"; fi; \
	done; \
	if [ $$rc -eq 0 ]; then \
	  echo "    clean"; \
	else \
	  echo ""; \
	  echo "    FAIL: naked compositor coupling."; \
	  echo "    Route it through the session records in home/common.scm (facts"; \
	  echo "    in the record, consequences at the consumer), or tag the line"; \
	  echo "    with ;[session] if it IS the switch or a gated consumer."; \
	fi; \
	exit $$rc

# reconfigure -- deploy this machine's host class config.
#
# The `guix home' counterpart is `make apply'. This is the system half, and it
# stayed prose in system/README.md for a while because three of its details are
# easy to get wrong in a way that either fails loudly at the worst moment or,
# worse, succeeds against the wrong config:
#
#   sudo -i, not sudo   There are two guix installations on a Guix System box.
#                       Root's is pulled at install time from
#                       system/channels-<class>.scm and therefore has nonguix;
#                       a user's has whatever that user last pulled. Every
#                       config here needs nonguix for `linux' and
#                       `linux-firmware', so the wrong one dies with
#                       "no code for module (nongnu packages linux)". `-i'
#                       starts a root LOGIN shell, which resolves `guix' to
#                       root's regardless of the invoker's PATH.
#   $(CURDIR), not a    `sudo -i' also cds to /root, so a relative
#   relative path       system/geeeks.scm is simply not there. CURDIR is
#                       already absolute and already resolved, so this works
#                       through the ~/dot_files symlink too.
#   uname -n, not a     `guix system reconfigure' applies whatever config you
#   hardcoded class     hand it, and a config hardcodes disk labels, firmware
#                       and a bootloader target. check-system-hosts asserts
#                       that system/<x>.scm calls itself <x> -- it cannot
#                       assert that <x> is the machine you are sitting at,
#                       because it does not know. Selecting the file FROM the
#                       running host name is what closes that gap, and it is
#                       why this target takes no argument to override it.
#
# `uname -n' rather than `hostname': coreutils is guaranteed here and this
# Makefile already leans on uname for OS detection, whereas `hostname' comes
# from inetutils and is one more thing to be absent in a rescue shell.
#
# check-system runs first as a prerequisite, so a drifted keyd config or an
# inlined credential stops the deploy rather than being baked into a generation.
reconfigure: check-system
	@if [ -z "$(GUIX_SYSTEM)" ]; then \
	  echo ""; \
	  echo "  *** make reconfigure is only for Guix System ***"; \
	  echo ""; \
	  echo "  /run/current-system does not exist here, so there is no"; \
	  echo "  operating-system generation to replace. Guix as a PACKAGE"; \
	  echo "  MANAGER on Pop!_OS or Ubuntu still gets you 'make apply'"; \
	  echo "  (guix home); it does not get you this."; \
	  echo ""; \
	  exit 1; \
	fi
	@host=$$(uname -n); \
	config="$(CURDIR)/system/$$host.scm"; \
	if [ ! -f "$$config" ]; then \
	  echo ""; \
	  echo "  no host class config for this machine"; \
	  echo ""; \
	  echo "    uname -n says:  $$host"; \
	  echo "    looked for:     $$config"; \
	  echo ""; \
	  echo "  Host classes present:"; \
	  for f in $(SYSTEM_CONFIGS); do echo "    $$(basename $$f .scm)"; done; \
	  echo ""; \
	  echo "  Either this machine belongs to an existing class and its host"; \
	  echo "  name is wrong, or it is a new class needing system/$$host.scm"; \
	  echo "  and system/channels-$$host.scm (see system/README.md)."; \
	  echo ""; \
	  exit 1; \
	fi; \
	echo "==> sudo -i guix system reconfigure $$config"; \
	sudo -i guix system reconfigure "$$config"
	@echo "==> done (system reconfigured)"
	@echo ""
	@echo "--- NEXT STEPS ---"
	@echo "A reconfigure builds and activates the new generation, but it does"
	@echo "not restart already-running services onto their new config:"
	@echo "  sudo herd restart keyd     # if %keyd-config changed"
	@echo "  sudo herd status           # what is running now"
	@echo ""
	@echo "The previous generation stays in the GRUB menu, so a bad boot is a"
	@echo "reboot away from being undone."

# ---------------------------------------------------------------------------
# Emacs daemon for remote (ssh) terminal clients
#
#   make emacs-serve   - start the daemon here, then print how to attach to it
#   make emacs-unserve - shut the daemon down
#
# Run this on the machine that HOLDS the Emacs session (the main desktop);
# other machines attach with `ssh -t <host> emacsclient -t`.
# ---------------------------------------------------------------------------
.PHONY: emacs-serve emacs-receive-ssh emacs-unserve emacs-attach emacs-connect-ssh

# Host running `make emacs-serve`. Override: make emacs-attach EMACS_HOST=geeeks
EMACS_HOST ?= minius
# Use a full path here if ssh's non-interactive shell can't find emacsclient,
# e.g. make emacs-attach REMOTE_EMACSCLIENT=/opt/homebrew/bin/emacsclient
REMOTE_EMACSCLIENT ?= emacsclient

# Kept as an alias because "receive ssh" describes the intent.
emacs-receive-ssh: emacs-serve
emacs-connect-ssh: emacs-attach

emacs-serve:
	@EMACS_BIN="$$(command -v emacs 2>/dev/null)"; \
	if [ -z "$$EMACS_BIN" ] && [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ]; then \
	  EMACS_BIN=/Applications/Emacs.app/Contents/MacOS/Emacs; \
	fi; \
	EMACSCLIENT_BIN="$$(command -v emacsclient 2>/dev/null)"; \
	SHORT_HOST="$$(hostname -s 2>/dev/null || hostname)"; \
	TS_BIN="$$(command -v tailscale 2>/dev/null)"; \
	if [ -z "$$TS_BIN" ] && [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then \
	  TS_BIN=/Applications/Tailscale.app/Contents/MacOS/Tailscale; \
	fi; \
	echo ""; \
	echo "=== Starting Emacs daemon on $$SHORT_HOST ==="; \
	if [ -z "$$EMACS_BIN" ]; then \
	  echo "  ERROR: no emacs binary found (brew install emacs-plus / guix install emacs)"; \
	  exit 1; \
	fi; \
	if [ -n "$$EMACSCLIENT_BIN" ] && "$$EMACSCLIENT_BIN" -a false -e '(emacs-version)' >/dev/null 2>&1; then \
	  echo "  Daemon already running - leaving it alone."; \
	else \
	  echo "  $$EMACS_BIN --daemon"; \
	  "$$EMACS_BIN" --daemon || { echo "  ERROR: daemon failed to start (see output above)"; exit 1; }; \
	fi; \
	echo ""; \
	echo "=== Requirements ==="; \
	echo "  [ok] emacs       : $$EMACS_BIN"; \
	if [ -n "$$EMACSCLIENT_BIN" ]; then \
	  echo "  [ok] emacsclient : $$EMACSCLIENT_BIN"; \
	else \
	  echo "  [--] emacsclient : NOT on PATH (needed on BOTH ends)"; \
	fi; \
	SSHD_OK=no; \
	if command -v nc >/dev/null 2>&1; then \
	  nc -z -w 1 127.0.0.1 22 >/dev/null 2>&1 && SSHD_OK=yes; \
	elif command -v ss >/dev/null 2>&1; then \
	  ss -ltn 2>/dev/null | grep -q ':22 ' && SSHD_OK=yes; \
	fi; \
	if [ "$$SSHD_OK" = yes ]; then \
	  echo "  [ok] sshd        : listening on port 22"; \
	else \
	  echo "  [--] sshd        : not listening on port 22 - enable it:"; \
	  if [ "$(os)" = "$(OS_MAC)" ]; then \
	    echo "         sudo systemsetup -setremotelogin on"; \
	    echo "         (or System Settings > General > Sharing > Remote Login)"; \
	  else \
	    echo "         sudo systemctl enable --now sshd    # or: herd start sshd"; \
	  fi; \
	fi; \
	TS_HOST=""; TS_FQDN=""; \
	if [ -n "$$TS_BIN" ]; then \
	  TS_IP="$$("$$TS_BIN" ip -4 2>/dev/null | head -1)"; \
	  if [ -n "$$TS_IP" ]; then \
	    TS_HOST="$$("$$TS_BIN" status 2>/dev/null | awk -v ip="$$TS_IP" '$$1==ip {print $$2; exit}')"; \
	    TS_FQDN="$$("$$TS_BIN" status --json 2>/dev/null | tr ',' '\n' | grep -m1 '"DNSName"' | sed 's/.*: *"//; s/\.*"$$//')"; \
	    echo "  [ok] tailscale   : up as $$TS_HOST ($$TS_IP)"; \
	  else \
	    echo "  [--] tailscale   : installed but not connected - run: $$TS_BIN up"; \
	  fi; \
	else \
	  echo "  [--] tailscale   : not installed (only needed to reach this box off-LAN)"; \
	fi; \
	echo ""; \
	echo "=== Attach from another machine ==="; \
	echo "  # Same LAN:"; \
	echo "  ssh -t $$SHORT_HOST.local emacsclient -t"; \
	if [ -n "$$TS_HOST" ]; then \
	  echo ""; \
	  echo "  # Anywhere, over Tailscale (both machines must be on the tailnet):"; \
	  echo "  ssh -t $$TS_HOST emacsclient -t"; \
	  [ -n "$$TS_FQDN" ] && echo "  ssh -t $$TS_FQDN emacsclient -t   # if MagicDNS short names are off"; \
	fi; \
	echo ""; \
	echo "  # Or, from a checkout of this repo on the other machine:"; \
	echo "  make emacs-attach EMACS_HOST=$${TS_HOST:-$$SHORT_HOST.local}"; \
	echo ""; \
	echo "=== Read-only peek (no attaching, no stray keystrokes) ==="; \
	if [ -n "$$TS_HOST" ]; then TRAMP_HOST="$$TS_HOST"; else TRAMP_HOST="$$SHORT_HOST.local"; fi; \
	echo "  # From your local Spacemacs, TRAMP into the session logs:"; \
	echo "  C-x C-f /ssh:$$TRAMP_HOST:~/.claude/projects/"; \
	echo "  # In dired: 's' then 't' sorts by time -> newest sessions are the active ones."; \
	echo "  # Open a .jsonl, then M-x auto-revert-tail-mode to follow it live."; \
	echo "  # If a transcript gets unwieldy: ~/.claude/bin/claude-slim-transcript <file>"; \
	echo ""; \
	echo "=== Notes ==="; \
	echo "  * -t forces a tty; without it emacsclient -t cannot open a terminal frame."; \
	echo "  * C-x C-c closes the remote frame only; the daemon keeps running."; \
	echo "  * ssh runs a non-interactive shell, so ~/.zshrc PATH edits may not apply."; \
	echo "    If 'command not found', use the full path:"; \
	echo "      ssh -t $$SHORT_HOST.local $$EMACSCLIENT_BIN -t"; \
	echo "  * The daemon must be started by the SAME user you ssh in as (socket is"; \
	echo "    per-user under \$$TMPDIR/emacs\$$UID/)."; \
	echo "  * Stop it with: make emacs-unserve"; \
	echo ""

# Run this on the machine you are sitting at; it attaches to EMACS_HOST's daemon.
emacs-attach:
	@echo ""
	@echo "=== Attaching to the Emacs daemon on $(EMACS_HOST) ==="
	@echo ""
	@echo "  ssh -t $(EMACS_HOST) $(REMOTE_EMACSCLIENT) -t"
	@echo ""
	@echo "  ssh -t ......... force a tty, else emacsclient has no terminal to draw in"
	@echo "  emacsclient -t . open a terminal frame on the existing daemon"
	@echo "  C-x C-c ........ closes THIS frame only; the daemon keeps running"
	@echo ""
	@echo "  Other host?  make emacs-attach EMACS_HOST=geeeks"
	@echo "  Read-only?   C-x C-f /ssh:$(EMACS_HOST):~/.claude/projects/   (TRAMP, no keystrokes sent)"
	@echo ""
	@ssh -t $(EMACS_HOST) $(REMOTE_EMACSCLIENT) -t

emacs-unserve:
	@if emacsclient -a false -e '(kill-emacs)' >/dev/null 2>&1; then \
	  echo "Emacs daemon stopped."; \
	else \
	  echo "No Emacs daemon was running."; \
	fi
