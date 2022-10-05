# dot_files
My dotfiles except for ~/.emacs.d (but now UNDER_CONSTRUCTION the makefile in this repo is transitioning to becoming the single-stop-shop for setting up my dotfiles. It will ask to install emacs with my [spacemacs dotfiles](https://github.com/durantschoon/.spacemacs.d) -- also on my mind is that I should look up [other people's solutions](https://dotfiles.github.io/utilities/) and ditch all this at some point, but with so many choices, how am I to choose, ha ha.)

I use [Zsh](http://www.zsh.org/) with [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh). I use the [agnoster theme](https://github.com/agnoster/agnoster-zsh-theme) which is best viewed with the [meslo powerline fonts](https://github.com/powerline/fonts) which should be installed by the cross-system [Makefile](./Makefile) in this repo.

These dot files are for the common settings on three operating systems: mac, linux (ubuntu), and windows. Specific changes to the path, etc. should go in ~/.zshenv and would be expected to be different on different machines since environment variables for software on each machine can be different. Someday I might get around to creating all three files: `.(mac|linux|windows).zshenv`

## Bootstraps by Operating system

### Ubuntu

```sh
sudo apt-get install git make -y
cd
git clone git@github.com:durantschoon/dot_files.git
cd dot_files
make
```

for reference: [zsh on ubuntu](https://gist.github.com/tsabat/1498393)

### Mac

*from memory, test this*

```sh
brew install git
cd
git clone git@github.com:durantschoon/dot_files.git
cd dot_files
make
```
### Windows

TODO

