# dot_files
My dotfiles except for ~/.emacs.d

I use [[http://www.zsh.org/][Zsh]]. These dot files are for the common settings on different machines. Specific changes to the path, etc. should go in ~/.zshenv and would be expected to be different on different machines since environment variables for software on each machine can be different. 

## Clone this to ~/dot_files

```sh
cd
git clone https://github.com/durantschoon/dot_files.git
```

## Make links

Then run these in the shell

```sh
ln -si ~/dot_files/.zshrc ~/
ln -si ~/dot_files/.aliases ~/
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
