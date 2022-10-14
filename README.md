# dot_files
My dotfiles except for ~/.emacs.d (but now the makefile in this repo has become the single-stop-shop for setting up my dotfiles including asking to install emacs with my [spacemacs dotfiles](https://github.com/durantschoon/.spacemacs.d)).

*Also on my mind is that maybe I should look up [other people's solutions](https://dotfiles.github.io/utilities/) and ditch all this at some point, but with so many choices and the further I get to making this how I want it, seems like I could end up sticking with this.*

I use [Zsh](http://www.zsh.org/) with [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh). I use the [agnoster theme](https://github.com/agnoster/agnoster-zsh-theme) which is best viewed with the [meslo powerline fonts](https://github.com/powerline/fonts) which should be installed by the cross-system [Makefile](./Makefile) in this repo.

These dot files are for the common settings on three operating systems: mac, linux (ubuntu), and windows. Specific changes to the path, etc. should go in the OS specific version of ~/.zshenv (remember: .zshenv is sourced every time and .zshrc is for interactive shells). The Windows set up is not really set up, yet. Last time I was on my Windows machine I was playing with and I think I had emacs on both or something weird like that and I should figure out what I did and what I want to do in this repo. 

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

*In current tests, seems to be working mostly as is with Windows Subsystem for Linux ([WSL](https://learn.microsoft.com/en-us/windows/wsl/install))... but I'm still debugging this...*

