# Load vcs_info
autoload -Uz vcs_info

# Pre-command hook to gather vcs_info
precmd() {
    vcs_info
}

# Configure vcs_info to show branch name
zstyle ':vcs_info:git:*' formats '%b'

setopt PROMPT_SUBST

precmd() {
    local exit_code=$?
    # Construct the prompt
    PROMPT='%F{cyan}[%f%F{magenta}%n@%m '

    if git --git-dir=$HOME/.cfg/ --work-tree=$HOME rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        # Explicitly set the branch to 'master' for a bare repo
        local current_branch="master"

        # Use 'git --git-dir=$HOME/.cfg/ --work-tree=$HOME' for all git commands
        local modified_count=$(git --git-dir=$HOME/.cfg/ --work-tree=$HOME status --porcelain | grep '^ M\|AM' | wc -l)
        local staged_count=$(git --git-dir=$HOME/.cfg/ --work-tree=$HOME diff --cached --name-status | grep 'A\|^M' | wc -l)
        local unpushed_count=$(git --git-dir=$HOME/.cfg/ --work-tree=$HOME log --branches --not --remotes --count 2>/dev/null | grep "commit" | wc -l)

    # Check if there are any changes
        if [[ $modified_count -gt 0 || $staged_count -gt 0 || $unpushed_count -gt 0 ]]; then
            PROMPT+="%F{cyan}.{%f"
            
            if [[ $modified_count -gt 0 ]]; then
                PROMPT+="%F{yellow}!$modified_count%f"
            fi

            if [[ $staged_count -gt 0 ]]; then
                PROMPT+="%F{green}+$staged_count%f"
            fi

            if [[ $unpushed_count -gt 0 ]]; then
                PROMPT+="%F{magenta}↑$unpushed_count%f"
            fi
            PROMPT+="%F{cyan}}%f "
        fi
    fi

    PROMPT+='%F{blue}%~%f %F{red}${vcs_info_msg_0_}%f'

    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        vcs_info

        # local modified_count=$(git status --porcelain | grep '^[ M]' | wc -l)
        local modified_count=$(git ls-files --modified | wc -l)
        local staged_count=$(git diff --cached --name-status | grep '^M' | wc -l)
        local untracked_count=$(git status --porcelain | grep '??'  | wc -l)
	local unpushed_count=$(git log @{u}..HEAD --oneline | wc -l)

        PROMPT+=" "
    
        # Display counts if there are any changes
        if [[ $modified_count -gt 0 ]]; then
            PROMPT+="%F{yellow}!$modified_count%f"
        fi

        if [[ $staged_count -gt 0 ]]; then
            PROMPT+="%F{green}+$staged_count%f"
        fi

        if [[ $untracked_count -gt 0 ]]; then
            PROMPT+="%F{red}?$untracked_count%f"
        fi

        if [[ $unpushed_count -gt 0 ]]; then
            PROMPT+="%F{magenta}↑$unpushed_count%f"
        fi
    fi



    
    # PROMPT+='$(if [[ -n $GLEX_SESSION ]]; then echo "%F{yellow}glex%f "; fi)'
    PROMPT+="%F{cyan}]%f"$'\n'
    
    # 0:    I just dont wanna see if its successful
    # 130:  That happens when I start trying a command then CTRL+C
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ]; then
        PROMPT+='%F{red}[%?]%f'
    fi
    
    PROMPT+='%F{white}$ '
}

PROMPT='$(precmd)'

####################


# The following lines were added by compinstall
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle :compinstall filename '/home/darthvader/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall
# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
setopt autocd extendedglob notify
bindkey -v
# to make backspace work again
bindkey "^?" backward-delete-char

# Set up case-insensitive autocompletion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

zstyle ':completion:*' menu select

# End of lines configured by zsh-newuser-install

# Make zsh autocomplete with up arrow
# For some reason this needs to be at the bottom of the file...
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search # Up
bindkey "^[[B" down-line-or-beginning-search # Down
####################


source ~/.profile
