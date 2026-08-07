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

# Detect package manager
PACKAGE_MANAGER := unknown
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

.PHONY: set_up_links wsl help guix-root-install warn-dotfiles-home

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
	@echo "  make all           - Set up dotfiles (default target; symlinks ~/bin -> ~/dot_files/bin,"
	@echo "                       then installs Claude Code if missing)"
	@echo "  make set_up_links  - Create symlinks for dotfiles"
	@echo "  make install-claude - Install Claude Code (idempotent; patches the binary on Guix System)"
	@echo "  make apply         - Apply Guix Home configuration (reconfigure)"
	@echo "  make apply-wayland - Apply Guix Home Wayland config (espanso-wayland, etc.)"
	@echo "  make emacs-env     - Regenerate ~/.spacemacs.d/.spacemacs.env from a clean"
	@echo "                       login shell and push it into a running Emacs."
	@echo "                       Runs automatically after apply/apply-wayland/update."
	@echo "  make submodule-update - Init and update submodules (espanso/private)"
	@echo "  make submodule-pull  - Pull latest in each submodule"
	@echo "  make submodule-push  - Push changes from each submodule"
	@echo "  make guix-config   - Create Guix Home configuration structure in ~/guix-config"
	@echo "  make guix-root-install - Install Guix packages as root (run this first if needed)"
	@echo "  make wsl           - Show WSL setup instructions"
	@echo "  make help          - Show this help message"
	@echo ""
	@echo "  This Makefile assumes the repo lives at ~/dot_files (symlink ok)."
	@echo "  Targets apply, apply-wayland, and set_up_links warn if that is not the case."
	@echo ""
	@echo "Platform-specific notes:"
	@echo "  - Detected OS: $(os) $(arch)"
	@echo "  - Package manager: $(PACKAGE_MANAGER)"
	@echo "  - For WSL: Run as 'HOME=/home/durant sudo make all'"
	@echo ""

wsl: 
	@echo Need a reminder?
	@echo You should run this command like this:
	@echo HOME=$(wsl_home) sudo make all
	@echo exiting...
	@exit 0

guix-root-install:
	@echo "Installing Guix packages as root..."
	@echo "This target installs packages that may require root privileges"
	@echo "Run this first, then run 'make all' as your regular user"
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

all: set_up_links install-claude

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

# We're going to insist we're in this directory so we can run commands from here
dot_file_root_dir := $(wildcard ~/dot_files)
current_dir := $(shell $(PWD_CMD))

set_up_links: warn-dotfiles-home 
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
	sudo apt-get install build-essential cmake curl file -y
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
	[ -f $(wildcard "~/dot_files/.$(os).zshenv") ] && ln -si ~/dot_files/.$(os).zshenv ~/.zshenv
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
		echo "   Install zsh first (e.g., via Guix: guix install zsh), then run: make all"; \
		echo "   Or install Emacs manually if needed."; \
	fi
endif

.PHONY: guix-config apply-wayland submodule-update submodule-pull submodule-push
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

apply: warn-dotfiles-home
	@echo "==> git submodule update --init claude"
	@# home/base.scm reads ../claude/* via local-file, so an uninitialized
	@# submodule fails the reconfigure with an opaque "no such file" from the
	@# store builder. Deliberately NOT `|| true`: claude-config is private, and
	@# a missing SSH key should stop here with git's own message rather than
	@# surface later as a Guix error.
	@git submodule update --init claude
	@echo "==> guix pull (pinned if channels.scm exists)"
	@if [ -f channels.scm ]; then \
	  guix pull --allow-downgrades --channels=channels.scm || guix pull ; \
	else \
	  guix pull ; \
	fi
	@echo "==> guix home reconfigure home/base.scm"
	@guix home reconfigure --allow-downgrades home/base.scm
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
	@if [ ! -f /etc/keyd/default.conf ]; then \
		echo ""; \
		echo "--- NEXT STEP: KEYBINDINGS ---"; \
		echo "To finish system-wide Emacs keybindings setup, run:"; \
		echo "  sudo make setup-keyd"; \
		echo "------------------------------"; \
	fi

apply-wayland: warn-dotfiles-home
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
	@echo "==> guix home reconfigure home/wayland.scm"
	@guix home reconfigure --allow-downgrades home/wayland.scm
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
	@if [ ! -f /etc/keyd/default.conf ]; then \
		echo ""; \
		echo "--- NEXT STEP: KEYBINDINGS ---"; \
		echo "To finish system-wide Emacs keybindings setup, run:"; \
		echo "  sudo make setup-keyd"; \
		echo "------------------------------"; \
	fi

submodule-update:
	@echo "==> git submodule update --init --recursive"
	@git submodule update --init --recursive

submodule-pull:
	@echo "==> git submodule foreach git pull"
	@git submodule foreach git pull

submodule-push:
	@echo "==> git submodule foreach git push"
	@git submodule foreach git push

.PHONY: setup-keyd
# Guix System detection for setup-keyd.
#
# Deliberately NOT PACKAGE_MANAGER: that is set to `guix` whenever `which guix`
# succeeds, which is true on Pop!_OS too (Guix is installed there as a package
# manager alongside apt). Gating on it would disable this target on the very
# machine where it works. /run/current-system exists only on Guix System.
GUIX_SYSTEM := $(wildcard /run/current-system)

# This target runs under sudo, where HOME=/root -- but the keyd binary lives in
# the INVOKING user's guix home profile. Expanding $(HOME) here once produced a
# dangling /usr/local/bin/keyd -> /root/.guix-home/... and a silent 203/EXEC
# crash loop that went unnoticed because GNOME's ctrl:swapcaps masked it.
REAL_HOME := $(shell getent passwd $${SUDO_USER:-$$USER} | cut -d: -f6)

setup-keyd:
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
	@echo "  That already exists in system/framework-dual.scm. It ships"
	@echo "  with (auto-start? #f) on purpose, so after reconfiguring:"
	@echo ""
	@echo "    sudo herd start keyd"
	@echo "    # confirm Caps acts as Control, and that C-a and C-f still"
	@echo "    # reach applications as control characters (no arrow layer)"
	@echo "    # then set (auto-start? #t) and reconfigure again"
	@echo ""
	@echo "  keyd grabs the physical keyboard; auto-starting an unverified"
	@echo "  config can leave you with no console input at boot."
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

update: warn-dotfiles-home
	@echo "==> guix pull"
	@guix pull
	@echo "==> pin channels.scm"
	@guix describe --format=channels > channels.scm
	@echo "==> guix home reconfigure"
	@guix home reconfigure home/base.scm
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
# system/framework-dual.scm has to be evaluable by root from the installer ISO
# during `guix system init', when no home directory exists and this checkout
# may be anywhere.  That forces it to INLINE what it needs rather than read
# ../keyd.conf or system/channels-framework-dual.scm beside it -- see
# system/README.md.  The price is duplicated text in three places, and
# duplicated text drifts: that is how the [control:C] keyd layer survived being
# removed from one copy, and how home/wayland.scm fell six packages behind
# home/base.scm.  These targets make the duplication checkable instead.
# ---------------------------------------------------------------------------
.PHONY: check-system check-keyd-sync check-channels-sync check-system-secrets install-hooks

check-system: check-keyd-sync check-channels-sync check-system-secrets
	@echo "==> system/: all checks passed"

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
	@echo "    pre-commit runs check-system when system/, keyd.conf or the"
	@echo "    Makefile are staged; bypass with git commit --no-verify"

# Compares FUNCTIONAL lines only (comments and blanks stripped), so the two
# copies may explain themselves differently -- keyd.conf carries the long-form
# rationale -- while the bindings themselves must match exactly.
check-keyd-sync:
	@echo "==> keyd.conf vs %keyd-config in system/framework-dual.scm"
	@a=$$(mktemp); b=$$(mktemp); \
	grep -vE '^[[:space:]]*#|^[[:space:]]*$$' keyd.conf > $$a; \
	sed -n '/plain-file "keyd-default.conf"/,/^"))/p' system/framework-dual.scm \
	  | sed '1d;$$d' | sed 's/^[[:space:]]*"//' \
	  | grep -vE '^[[:space:]]*#|^[[:space:]]*$$' > $$b; \
	if diff -u $$a $$b > /dev/null 2>&1; then \
	  echo "    in sync"; rm -f $$a $$b; \
	else \
	  echo "    DRIFT -- the deployed keyd config and the repo copy disagree:"; \
	  diff -u $$a $$b || true; rm -f $$a $$b; exit 1; \
	fi

# Compares channel names, URLs, commits and fingerprints as an unordered set,
# so formatting and the (define ...) wrapper are free to differ.
check-channels-sync:
	@echo "==> system/channels-framework-dual.scm vs %framework-dual-channels"
	@a=$$(mktemp); b=$$(mktemp); \
	pat='\(name .[a-z]+|"[0-9a-f]{40}"|https://[^"]+|[0-9A-F]{4} [0-9A-F ]+[0-9A-F]{4}'; \
	grep -oE "$$pat" system/channels-framework-dual.scm | sort > $$a; \
	sed -n '/define %framework-dual-channels/,/^$$/p' system/framework-dual.scm \
	  | grep -oE "$$pat" | sort > $$b; \
	if diff -u $$a $$b > /dev/null 2>&1; then \
	  echo "    in sync"; rm -f $$a $$b; \
	else \
	  echo "    DRIFT -- the install-time pin and the deployed pin disagree:"; \
	  diff -u $$a $$b || true; rm -f $$a $$b; exit 1; \
	fi

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
# example in framework-dual.scm does not trip it.
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
