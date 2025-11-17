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

.PHONY: set_up_links wsl help guix-root-install

help:
	@echo "Available targets:"
	@echo ""
	@echo "  make all           - Set up dotfiles (default target)"
	@echo "  make set_up_links  - Create symlinks for dotfiles"
	@echo "  make guix-config   - Create Guix Home configuration structure in ~/guix-config"
	@echo "  make guix-root-install - Install Guix packages as root (run this first if needed)"
	@echo "  make wsl           - Show WSL setup instructions"
	@echo "  make help          - Show this help message"
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

all: set_up_links

# We're going to insist we're in this directory so we can run commands from here
dot_file_root_dir := $(wildcard ~/dot_files)
current_dir := $(shell $(PWD_CMD))

set_up_links: 
	@echo OS detected as $(os) $(arch)
	@echo ------------------------------
ifneq ("","$(unix_family)")
# we're in Unix land
ifneq ("$(current_dir)","$(dot_file_root_dir)")
ifeq (,$(dot_file_root_dir))
	@echo dot_file_root_dir did not resolve. We will continue as if you are root in WSL
else
	@echo You should be in the $(dot_file_root_dir) directory to run this command
	@echo You should be in the ~/dot_files directory to run this command
	exit 1
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
	sudo apt-get install build-essential curl file -y
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
		guix install zsh fontconfig curl file gcc-toolchain || echo "Package installation failed - continuing anyway"; \
	}
	@echo "Installing starship prompt..."
	@echo "Using curl from Guix profile..."
	@~/.guix-profile/bin/curl -sS https://starship.rs/install.sh | sh || echo "Starship installation failed"
	@echo "Verifying zsh installation..."
	@which zsh || echo "WARNING: zsh installation may have failed"
else ifeq ($(PACKAGE_MANAGER),yum)
	sudo yum update -y
	sudo yum groupinstall -y "Development Tools"
	sudo yum install -y curl file zsh
else ifeq ($(PACKAGE_MANAGER),pacman)
	sudo pacman -Syu --noconfirm
	sudo pacman -S --noconfirm base-devel curl file zsh
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
ifneq (,$(shell $(WHICH_CMD) zsh))
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

	./unix_work_or_home.sh

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
	@if command -v zsh >/dev/null 2>&1 || [ -f ~/.guix-profile/bin/zsh ] || [ -f ~/.config/guix/current/bin/zsh ]; then \
		if command -v zsh >/dev/null 2>&1; then \
			ZSH_CMD=zsh; \
		elif [ -f ~/.guix-profile/bin/zsh ]; then \
			ZSH_CMD=~/.guix-profile/bin/zsh; \
		else \
			ZSH_CMD=~/.config/guix/current/bin/zsh; \
		fi; \
		echo "Installing Emacs with zsh..."; \
		$$ZSH_CMD -c "./install_emacs.zsh --$(emacs_flag)"; \
	else \
		echo "⚠️  zsh not available - skipping Emacs installation"; \
		echo "   The install_emacs.zsh script requires zsh."; \
		echo "   Install zsh first (e.g., via Guix: guix install zsh), then run: make all"; \
		echo "   Or install Emacs manually if needed."; \
	fi
endif

.PHONY: guix-config
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
		echo "        (url \"https://git.savannah.gnu.org/git/guix.git\")" >> ~/guix-config/channels.scm; \
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
	@echo ".PHONY: setup update rollback clean" > ~/guix-config/Makefile
	@echo "" >> ~/guix-config/Makefile
	@echo "setup:" >> ~/guix-config/Makefile
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
	@echo "# Initial setup" >> ~/guix-config/README.md
	@echo "make setup" >> ~/guix-config/README.md
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
