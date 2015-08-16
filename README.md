# dot_files
My dotfiles except for ~/.emacs.d

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
