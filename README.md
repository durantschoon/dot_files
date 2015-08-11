# dot_files
My dotfiles except for ~/.emacs.d

## Clone this to ~/dot_files

cd
git clone https://github.com/durantschoon/dot_files.git

## Make links

Then run these in the shell

<pre>
ln -si ~/dot_files/.zshrc ~/
ln -si ~/dot_files/.aliases ~/
</pre>

## Create a file to decide to load home or work dot files

At home
<pre>
echo See ~/.aliases for the use of this file >> ~/.HOME
</pre>

At work
<pre>
echo See ~/.aliases for the use of this file >> ~/.WORK
</pre>
