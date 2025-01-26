export XDG_CURRENT_DESKTOP=Hyperland
export EDITOR="vi"
export TERM=alacritty

export PATH="$PATH:$(du "$HOME/.scripts/" | cut -f2 | tr '\n' ':' | sed 's/:*$//')"
export PATH="$PATH:$(du "$HOME/bin/" | cut -f2 | tr '\n' ':' | sed 's/:*$//')"

export GO111MODULE=on
export GOPATH="$HOME/go"
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

alias ws="workspacer -W=ws"

alias cls='clear'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -l --block-size=M  -aF'

# Aliases
alias tx="tmux -u"
alias txa="tmux -u a"

# Git bare repo for the dotconfigs

# alias cfg='git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
cfg() {
	git --git-dir=$HOME/.cfg/ --work-tree=$HOME "$@"
}

# alias cfga='git --git-dir=$HOME/.cfg/ --work-tree=$HOME add'
cfga() {
	git --git-dir=$HOME/.cfg/ --work-tree=$HOME add "$@"
}

alias cfgau='git --git-dir=$HOME/.cfg/ --work-tree=$HOME add -u'
alias cfgc='git --git-dir=$HOME/.cfg/ --work-tree=$HOME commit -m'
alias cfgp='git --git-dir=$HOME/.cfg/ --work-tree=$HOME push'
alias cfgs='git --git-dir=$HOME/.cfg/ --work-tree=$HOME status'

# Git aliases alias g="git" alias gaa="git add --all" alias ga="git add " alias gc="git commit -m"
alias gaa="git add --all"
alias gp="git push --no-verify"
alias gpl="git pull"
alias gs="git status"
alias gss="git submodule status"
alias gsa="git submodule add"
alias gd="git diff"
alias gf="git fetch"
alias gc="git commit -m"
alias gcs="git commit --no-verify -S -s -m"
# Open all modified git fil -ses in vim
alias gvi="git ls-files --modified | xargs nvim"
alias lg="lazygit"

# Squash all in the current branch
gqb() {
	commit_msg=$1
	master_branch=$(git symbolic-ref refs/remotes/origin/HEAD | grep -o '[^/]*$')
	current_branch=$(git branch --show-current)
	commit=$(git merge-base $master_branch $current_branch)
	git reset $commit
	git add --all

	[[ -z $commit_msg ]] && echo "\n\n\n\nAll done, create a commit and push with --force now" && kill -INT $$
	git commit -m $commit_msg
	git push --force
}

# Merging master to current
gmm() {
	ORIGINAL_BRANCH=$(git branch --show-current)
	MASTER_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | grep -o '[^/]*$')
	git checkout $MASTER_BRANCH
	git pull
	git checkout $ORIGINAL_BRANCH
	git merge $MASTER_BRANCH
}

# Stage all git files that can be grepped by a query
gas() {
	[ -z $1 ] && echo "Need parameter" && return 1
	echo "Query: "$1
	FILES=$(git ls-files --modified --others | grep "$1")
	echo $FILES
	echo $FILES | xargs git add
}

# For creating a new branch and automatically switching to it
gnb() {
	[ -z $1 ] && echo "Need name of branch" && return 1
	echo "Creating new git branch and switching to it " $1
	git branch $1
	git checkout $1
}

# For pushing upstream to a fresh branch
gpnu() {
	echo "Pushing to new branch upstream"
	git push --no-verify  --set-upstream origin $(git rev-parse --abbrev-ref HEAD)
}

# swapping vi for nvim
alias vi="nvim"
alias nvim-l="NVIM_APPNAME=nvim-l nvim"

function nvims() {
	items=("default" "nvim-l")
	config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" neovim config  " --height=~50% --layout=reverse --border --exit-0)
	if [[ -z $config ]]; then
		echo "nothing selected"
		return 0
	elif [[ $config == "default" ]]; then
		config=""
	fi
	NVIM_APPNAME=$config nvim $@
}

# bindkey -s ^a "nvims\n"

if [[ $(uname) = "Darwin" ]]; then
fi
if [[ $(uname) = "Linux" ]]; then
fi


