# dot_files
My dotfiles except for ~/.emacs.d (but now the makefile in this repo has become the single-stop-shop for setting up my dotfiles including asking to install emacs with my [spacemacs dotfiles](https://github.com/durantschoon/.spacemacs.d)).

*Also on my mind is that maybe I should look up [other people's solutions](https://dotfiles.github.io/utilities/) and ditch all this at some point, but with so many choices and the further I get to making this how I want it, seems like I could end up sticking with this.*

I use [Zsh](http://www.zsh.org/) with [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh). I use the [agnoster theme](https://github.com/agnoster/agnoster-zsh-theme) which is best viewed with the [meslo powerline fonts](https://github.com/powerline/fonts) which should be installed by the cross-system [Makefile](./Makefile) in this repo.

These dot files are for the common settings on three operating systems: mac, linux (ubuntu), and windows. Specific changes to the path, etc. should go in the OS specific version of ~/.zshenv (remember: .zshenv is sourced every time and .zshrc is for interactive shells). The Windows set up is not really set up, yet. Since ubuntu now runs on Windows, I've been using that and have installed a few things by hand still without yet adding those things to the automation in this repo.

Note to self: The name `.shared.zshrc` is an old name which meant shared between work and home (both mac). TODO: rename and refactor this so it makes sense on the 3 operating systems.

## Bootstraps by Operating system

### Ubuntu

```sh
sudo apt-get install git make -y
cd
git clone https://github.com/durantschoon/dot_files.git
cd dot_files
make
```

for reference: [zsh on ubuntu](https://gist.github.com/tsabat/1498393)

### Mac

Forgot how to get `brew` on the mac? Go [here](https://brew.sh/) and run the one-liner. 

```sh
brew install git
cd
git clone https://github.com/durantschoon/dot_files.git
cd dot_files
make
```

Also note, until I have dotfiles for iTerm, be sure to edit preferences in iTerm and under Profiles > (Default) > Text, flick on "Use built-in Powerline glyphs."

### Windows

#### WSL

1. It's important to be in your home directory so run `cd` before cloning this directory. By default in WSL I end up in a user data directory when I first log in.

2. Do not rely on setxkbmap in ubuntu under WSL to alter the keyboard mapping. Set that up manually by downloading the .exe from https://github.com/microsoft/PowerToys

 ```sh
cd
git clone https://github.com/durantschoon/dot_files.git
cd dot_files
make
```

Remember to set fonts in terminal programs for your agnoster glyphs:
* ConEmu > (hamburger menu in top right) > Settings > General > Fonts > Main Console Font : set to one fo the meslos, like **Meslo LG S DZ for Powerline**
* VS Code terminal: `"terminal.integrated.fontFamily": "Meslo LG M DZ for Powerline"`

*In current tests, seems to be working mostly as is with Windows Subsystem for Linux ([WSL](https://learn.microsoft.com/en-us/windows/wsl/install))... but I'm still debugging this...*

#### Powershell

 1. Install [choco](https://chocolatey.org/install#individual)

Something like this, maybe the choco command has to be run as admin

 ```sh
cd
choco install make
git clone https://github.com/durantschoon/dot_files.git
cd dot_files
make
```
