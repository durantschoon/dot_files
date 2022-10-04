# Detect OS (modified from example https://stackoverflow.com/a/12099167)

OS_WINDOWS := "windows"
OS_MAC := "mac"
OS_LINUX := "linux"
OS_UNKNOWN := "unknown"
os := $(OS_UNKNOWN)

ARCH_X86 := "x86"
ARCH_AMD64 := "amd64"
ARCH_ARM := "arm"
ARCH_UNKNOWN := "unknown"
arch := $(ARCH_UNKNOWN)

ifeq ($(OS),Windows_NT)
    # CCFLAGS += -D WIN32
	os := $(OS_WINDOWS)
    # ifeq ($(PROCESSOR_ARCHITEW6432),AMD64)
    #     CCFLAGS += -D AMD64
    # else
    #     ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
    #         CCFLAGS += -D AMD64
    #     endif
    #     ifeq ($(PROCESSOR_ARCHITECTURE),x86)
    #         CCFLAGS += -D IA32
    #     endif
    # endif
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        # CCFLAGS += -D LINUX
		os := $(OS_LINUX)
    endif
    ifeq ($(UNAME_S),Darwin)
        # CCFLAGS += -D OSX
		os := $(OS_MAC)
    endif
    UNAME_P := $(shell uname -p)
    ifeq ($(UNAME_P),x86_64)
        # CCFLAGS += -D AMD64
		arch := $(ARCH_AMD64)
    endif
    ifneq ($(filter %86,$(UNAME_P)),)
        # CCFLAGS += -D IA32
		arch := $(ARCH_X86)
    endif
    ifneq ($(filter arm%,$(UNAME_P)),)
        # CCFLAGS += -D ARM
		arch := $(ARCH_ARM)
    endif
endif

# families of os'es will run the same commands
# this value will not be blank if the os is in the family
unix_family := $(filter $(os),$(OS_LINUX) $(OS_MAC))

.PHONY: set_up_links

# We're going to insist we're in this directory so we can run commands from here
dot_file_root_dir := $(wildcard ~/dot_files)
current_dir := $(shell pwd)

set_up_links: 
	@echo "OS detected as $(os) $(arch)\n"
ifneq ("$(unix_family)","")
ifneq ("$(current_dir)","$(dot_file_root_dir)")
	@echo You should be in the $(dot_file_root_dir) directory to run this command
	exit 1
endif	
ifeq ("$(os)","$(OS_LINUX)")
	# ubuntu
	# you already installed git to get this far
	@echo sudo apt-get update && sudo apt-get dist-upgrade -y
	@echo sudo apt-get install build-essential curl file fonts-powerline -y
	# install zsh and oh-my-zsh
	@echo sudo apt install zsh -y
	@echo sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
	@echo chsh -s `which zsh`
endif	
	@echo ln -si ~/dot_files/.zshrc ~/
	@echo ln -si ~/dot_files/.aliases ~/

	# DISABLED @echo ln -si ~/dot_files/.zprofile ~/.zprofile # reads .bash_profile if I have it
	@echo ln -si ~/dot_files/.shared.zshrc ~/.shared.zshrc # read by .zshrc
ifneq (,$(wildcard "~/dot_files/.$(os).zshenv)")
	@echo ln -si ~/dot_files/.$(os).zshenv ~/.zshenv
endif
	./unix_work_or_home.sh  

	# TODO : ask to install emacs with spacemacs dot files	

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

