export XDG_CURRENT_DESKTOP=Hyperland
export EDITOR="nvim"
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
alias ga="git add "
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


dump_folder_contents() {
	local folder="."
	local ignore_pattern=""

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--ignore)
				ignore_pattern="$2"
				shift 2
				;;
			*)
				folder="$1"
				shift
				;;
		esac
	done

	echo "Dumping all files inside $folder/ with contents..."

	# Find all files in the folder, ignoring permission errors
	find "$folder" -type f 2>/dev/null | while read -r file; do
		# If an ignore pattern is specified, skip matching files
		if [[ -n "$ignore_pattern" && "$file" =~ $ignore_pattern ]]; then
			continue
		fi

		# Skip non-text files
		if ! file --mime-type "$file" | grep -q 'text'; then
			continue
		fi
		
		# Print the file contents
		echo -e "\nFile: $file"
		echo "-----------------------------------------------"
		cat "$file"
		echo -e "\n"
	done
}

# swapping vi for nvim
alias vi="nvim-l"
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
	export XDG_DATA_DIRS=/usr/share:/usr/local/share
	yay() {
	    # Store the original command arguments
	    local args=("$@")
	    
	    # Run the original yay command
	    command yay "$@"
	    local exit_status=$?

	    if [ $exit_status -eq 0 ]; then
		local packages_file="$HOME/.config/installed_packages/common.txt"

		if [[ "$*" == *"-S "* ]]; then
		    # Installation: Add packages
		    echo "Adding package(s) to $packages_file"
		    for pkg in $(echo "$@" | grep -oP '(?<=-S\s)\S+'); do
			echo "$pkg" >> "$packages_file"
		    done
		elif [[ "$*" == *"-R"* ]]; then
		    # Removal: Remove packages
		    echo "Removing package(s) from $packages_file"
		    for pkg in $(echo "$@" | grep -oP '(?<=-R\s)\S+'); do
			sed -i "/^$pkg$/d" "$packages_file"
		    done
		fi

		# Remove duplicates and sort the file
		sort -u "$packages_file" -o "$packages_file"
	    fi

	    return $exit_status
	}
fi


