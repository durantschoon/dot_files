# dot_files
My dotfiles except for ~/.emacs.d

I use [Zsh](http://www.zsh.org/). These dot files are for the common settings on different machines. Specific changes to the path, etc. should go in ~/.zshenv and would be expected to be different on different machines since environment variables for software on each machine can be different.

## Clone this to ~/dot_files

```sh
cd
git clone https://github.com/durantschoon/dot_files.git
```

## I also use oh-my-zsh

Which you can get from [here](https://github.com/robbyrussell/oh-my-zsh). But on Ubuntu, you should also check out [this](https://gist.github.com/tsabat/1498393).

I use the agnoster theme in oh-my-zsh which is best viewed with the [meslo powerline fonts](https://github.com/powerline/fonts) which you'll have to download for your system. Remember to set them in your terminal applications!

## Make links

Then run these in the shell

```sh
cd
ln -si ~/dot_files/.zshrc ~/
ln -si ~/dot_files/.aliases ~/

ln -si ~/dot_files/.osx.zshenv ~/.zshenv
# ln -si ~/dot_files/.zprofile ~/.zprofile # reads .bash_profile if I have it
ln -si ~/dot_files/.shared.zshrc ~/.shared.zshrc # read by .zshrc
```

## Create a file to decide to load home or work aliases

(credit to Paul Merrill for the idea)

At home
```sh
echo See ~/.aliases for the use of this file >> ~/.HOME
```

At work
```sh
echo See ~/.aliases for the use of this file >> ~/.WORK
```
