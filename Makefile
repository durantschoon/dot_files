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

ifeq ($(OS),Windows_NT)
	os := $(OS_WINDOWS)
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

.PHONY: set_up_links

# We're going to insist we're in this directory so we can run commands from here
dot_file_root_dir := $(wildcard ~/dot_files)
current_dir := $(shell pwd)

set_up_links: 
	@echo "OS detected as $(os) $(arch)\n"
ifneq (,"$(unix_family)")
	# we're in Unix land
ifneq ("$(current_dir)","$(dot_file_root_dir)")
	@echo You should be in the $(dot_file_root_dir) directory to run this command
	exit 1
endif	
ifeq ("$(os)","$(OS_LINUX)")
	# ubuntu
	# you already installed git to get this far
	sudo apt-get update && sudo apt-get dist-upgrade -y
	sudo apt-get install build-essential curl file -y

# install zsh
	sudo apt install zsh -y
endif

# This powerline install should work on mac and linux
	git clone https://github.com/powerline/fonts.git --depth=1
	./fonts/install.sh
	rm -rf fonts

# install oh-my-zsh
ifneq (,$(wildcard "~/.oh-my-zsh"))
	epoch := $(shell date +%s)
	ee mv ~/.oh-my-zsh ~/.oh-my-zsh.bak.$(epoch)
endif
	curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -o install-oh-my-zsh.sh
	sh install-oh-my-zsh.sh
	rm install-oh-my-zsh.sh
	chsh -s $(shell which zsh)

ifneq (,$(wildcard "~/.zshrc"))
	mv ~/.zshrc ~/.zshrc.bak # maybe created by oh-my-zsh and we don't care about clobbering it on rewrite
endif
	ln -si ~/dot_files/.zshrc ~/
	ln -si ~/dot_files/.aliases ~/

	# DISABLED @echo ln -si ~/dot_files/.zprofile ~/.zprofile # reads .bash_profile if I have it
	ln -si ~/dot_files/.shared.zshenv ~/.shared.zshenv # read by .zshenv
	ln -si ~/dot_files/.shared.zshrc ~/.shared.zshrc # read by .zshrc
	[ -f $(wildcard "~/dot_files/.$(os).zshenv") ] && ln -si ~/dot_files/.$(os).zshenv ~/.zshenv

	# TODO make a general version of ./unix_work_or_home.sh that works on windows too
	./unix_work_or_home.sh

else ifeq ($(os),$(OS_WINDOWS))
	# TODO: where is my home directory on windows? /C or /H?
	# TODO: check current dir here too
	@echo mklink /H %USERPROFILE%\.zshrc %USERPROFILE%\dot_files\.zshrc
	@echo mklink /H %USERPROFILE%\.aliases %USERPROFILE%\dot_files\.aliases
	# DISABLED @echo mklink /H %USERPROFILE%\.zprofile %USERPROFILE%\dot_files\.zprofile
	@echo mklink /H %USERPROFILE%\.shared.zshrc %USERPROFILE%\dot_files\.shared.zshrc
else
	@echo "OS not recognized"
	exit 1
endif

	# End of setup_links
	zsh -c "./install_emacs.zsh --$(os)"
