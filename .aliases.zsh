source ~/.aliases

alias s.z='source ~/.zshrc'
alias s.ze='source ~/.zshenv'
# . regular file, o sorted, m mod time, 1 first
alias lth='ls -lt | head; latest=`ls *(.om[1])`'	
# . regular file, o sorted, m mod time, 1 first
alias lthd='ls -lt | head; latest=`ls -d *(/om[1])`'	
alias wh=which
# z move?
# zmv -W '*.lis' '*.txt'
alias zmvw='zmv -W'

# try these
alias -g latestd='*(/om[1])' # newest directory
alias -g latestf='*(.om[1])' # newest file

alias llrm='echo "Paste ls -lt output for files to delete and ^D when done"; /bin/rm -rf `awk '\''{print $9}'\''`'

# unalias rm
rm () { mv $* ~/.Trash }

# alias pd='pushd; ds'
function pd () {
	 pushd $1
	 ds
}

function p () {
	 ls -d $PWD/$1
}

# -----

# old method - delete when git repo is working

function push_dots () {

    files=(~/.alias* ~/.bash*  ~/.config* ~/.emacs*  ~/.freemind  ~/.git*  ~/.ipython*  ~/.saves  ~/.zsh*  ~/.Xdefaults )
    dest_dir=~/Dropbox/work_files/dot_files

    echo "\n=== Copying Files ==="
    for f in $files
    do
	print $f
	cp -r $f $dest_dir
    done
    echo "\n=== DONE === $dest_dir"
    ls -a ~/Dropbox/work_files/dot_files

    unset files dest_dir
}


# $1 = type; 0 - both, 1 - tab, 2 - title
# rest = text
setTerminalText () {
    # echo works in bash & zsh
    local mode=$1 ; shift
    echo -ne "\033]$mode;$@\007"
}
stt_both  () { setTerminalText 0 $@; }
stt_tab   () { setTerminalText 1 $@; }
stt_title () { setTerminalText 2 $@; }

# mac

###############################################################################
# global aliases
# example: C

# from: http://grml.org/zsh/zsh-lovers.html

# $latest alias -g C='| wc -l'
# $ grep alias ~/.zsh/* C
# 443

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'
alias -g CA="2>&1 | cat -A"
alias -g C='| wc -l'
alias -g D="DISPLAY=:0.0"
alias -g DN=/dev/null
alias -g ED="export DISPLAY=:0.0"
alias -g EG='|& egrep'
alias -g EH='|& head'
alias -g EL='|& less'
alias -g ELS='|& less -S'
alias -g ETL='|& tail -20'
alias -g ET='|& tail'
alias -g F=' | fmt -'
alias -g G='| egrep'
alias -g H='| head'
alias -g HL='|& head -20'
alias -g Sk="*~(*.bz2|*.gz|*.tgz|*.zip|*.z)"
alias -g LL="2>&1 | less"
alias -g L="| less"
alias -g LS='| less -S'
alias -g MM='| most'
alias -g M='| more'
alias -g NE="2> /dev/null"
alias -g NS='| sort -n'
alias -g NUL="> /dev/null 2>&1"
alias -g PIPE='|'
alias -g R=' > /c/aaa/tee.txt '
alias -g RNS='| sort -nr'
alias -g S='| sort'
alias -g TL='| tail -20'
alias -g T='| tail'
alias -g US='| sort -u'
alias -g VM=/var/log/messages
alias -g X0G='| xargs -0 egrep'
alias -g X0='| xargs -0'
alias -g XG='| xargs egrep'
alias -g X='| xargs'

###############################################################################
# for work, zsh only


# function_exists() {
#     declare -f -F $1 > /dev/null
#     return $?
# }
# function_exists wood && unfunction wood #  || echo No such function
# wood () { 
#     cat > ~/woodhouse.txt ;
#     echo '\n==========\n' ;
#     cat ~/woodhouse.txt | perl -pe 's/Queue Statistics:/Queue Statistics:\n/;' | perl -pe 's/(\s)(\d+)(\s)(\w+)/\$1\$2\n\$3\$4/g;' ;
# }


