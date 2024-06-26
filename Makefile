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

ifneq ($(grep -i Microsoft /proc/version), "")
	flavor := $(FLAVOR_WSL)
	wsl_home := /home/tallyfor/home_durant
	HOME = $(wsl_home)
endif

.PHONY: set_up_links wsl

wsl: 
	@echo Need a reminder?
	@echo You should run this command like this:
	@echo HOME=$(wsl_home) sudo make all
	@echo exiting...
	@exit 0

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
	sudo apt-get update && sudo apt-get dist-upgrade -y
	sudo apt-get install build-essential curl file -y

# install zsh

	sudo apt install zsh -y && echo "Let's keep going!" || echo seems like you might have the latest version of zsh already
endif
ifeq ("$(os)","$(OS_MAC)")
	@# install svn if needed for the fonts
	@brew list svn > /dev/null || brew install svn
endif
# This powerline install should work on mac and linux
ifneq ($(flavor), $(FLAVOR_WSL))
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
	./install_oh_my_zsh_with_backup.sh || echo seems like you might have the latest version of zsh already
endif
ifneq (,$(shell $(WHICH_CMD) zsh))
	@chsh -s $(shell $(WHICH_CMD) zsh) || echo tried to change shell to $(shell $(WHICH_CMD) zsh), but it failed;
endif

ifneq (,$(wildcard "~/.zshrc"))
	mv ~/.zshrc ~/.zshrc.bak # maybe created by oh-my-zsh and we don't care about clobbering it on rewrite
endif
	ln -si ~/dot_files/.zshrc ~ || echo
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
	zsh -c "./install_emacs.zsh --$(emacs_flag)"
endif
