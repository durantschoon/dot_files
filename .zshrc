# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
# ZSH_THEME="random"

# Only set theme if it's not yet set, so I can do:
# xterm -e "export ZSH_THEME='clean';/bin/zsh" &
# until I can get meslo to work in xterm

[ ! -n "${ZSH_THEME+x}" ] && ZSH_THEME="agnoster"

# ZSH_THEME="xiong-chiamiov-plus"
# ZSH_THEME="bira"
# ZSH_THEME="smt"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git osx emacs)

# User configuration

# for git and other things
export PATH=/usr/local/bin:${PATH:gs#/usr/local/bin:##}

# for brew (mac)
export PATH=/usr/local/sbin:${PATH:gs#/usr/local/sbin:##}

# penv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if which pyenv > /dev/null; then eval "$(pyenv init -)"; fi

# export PATH=$HOME/bin:/usr/local/bin:$PATH
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
source $HOME/.aliases

# currently causes an error
# if [ -f ~/.git-completion.zsh ]; then
#     . ~/.git-completion.zsh
# fi

# obvious?
setopt HIST_IGNORE_ALL_DUPS
setopt AUTO_PUSHD
setopt SHARE_HISTORY

# Use these lines to enable search by globs, e.g. gcc*foo.c
bindkey "^R" history-incremental-pattern-search-backward
bindkey "^S" history-incremental-pattern-search-forward

# path
# from http://stackoverflow.com/questions/9347478/how-to-edit-path-variable-in-zsh
# if (( ${path[(i)/anaconda/bin]} > ${#path} )) then
#     path+=/anaconda/bin
# fi
# path=($^path(N))

# from http://www.zsh.org/mla/users/2011/msg00281.html
HISTSIZE=1000
if (( ! EUID )); then
  HISTFILE=~/.history_root
else
  HISTFILE=~/.history
fi
SAVEHIST=1000

# this says it's depercated when it's run
# source ~/.git-completion.sh

# causes an error now that I set up .bash files
# zstyle ':completion:*:*:git:*' script ~/.git-completion.zsh

# look for file in ~/.zsh/_git

fpath=(~/.zsh $fpath)

# The N glob qualifier selects only the matches that exist. Add the -/
# to the qualifier list (i.e. (-/N) or (N-/)) if you're worried that
# one of the elements may be something other than a directory or a
# symbolic link to one (e.g. a broken symlink). The ^ parameter
# expansion flag ensures that the glob qualifier applies to each array
# element separately.
# You can also use the N qualifier to add an element only if it
# exists. Note that you need globbing to happen, so
# path+=/usr/local/mysql/bin(N) wouldn't work.
# durant: use
# path+=(/usr/local/bin/mysql/bin(N-/))
