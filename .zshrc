
# Load vcs_info
autoload -Uz vcs_info

# Configure vcs_info to show branch name
zstyle ':vcs_info:git:*' formats '%b'

setopt PROMPT_SUBST

precmd() {
    local exit_code=$?
    vcs_info
    # Construct the prompt
    PROMPT='%F{cyan}[%f%F{magenta}%n@%m '

    # Check for dotfiles bare repository
    if git --git-dir=$HOME/.cfg/ --work-tree=$HOME rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        local modified_count=$(git --git-dir=$HOME/.cfg/ --work-tree=$HOME status --porcelain | grep '^ M\|AM' | wc -l)
        local staged_count=$(git --git-dir=$HOME/.cfg/ --work-tree=$HOME diff --cached --name-status | grep 'A\|^M' | wc -l)
        local unpushed_count=$(git --git-dir=$HOME/.cfg/ --work-tree=$HOME log --not --remotes --count 2>/dev/null | grep "commit" | wc -l)

        # Check if there are any changes in dotfiles
        if [[ $modified_count -gt 0 || $staged_count -gt 0 || $unpushed_count -gt 0 ]]; then
            PROMPT+="%F{cyan}.{%f"
            
            [[ $modified_count -gt 0 ]] && PROMPT+="%F{yellow}!$modified_count%f"
            [[ $staged_count -gt 0 ]] && PROMPT+="%F{green}+$staged_count%f"
            [[ $unpushed_count -gt 0 ]] && PROMPT+="%F{magenta}↑$unpushed_count%f"
            
            PROMPT+="%F{cyan}}%f "
        fi
    fi

    PROMPT+='%F{blue}%~%f '

    # Check for regular Git repository (not the dotfiles bare repo)
    if [[ -z "$GIT_DIR" ]] && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        PROMPT+="%F{red}$branch%f"

        local modified_count=$(git ls-files --modified | wc -l)
        local staged_count=$(git diff --cached --name-status | grep '^M' | wc -l)
        local untracked_count=$(git ls-files --others --exclude-standard | wc -l)
        local unpushed_count=$(git log @{u}..HEAD --oneline 2>/dev/null | wc -l)

        PROMPT+=" "
    
        # Display counts if there are any changes
        [[ $modified_count -gt 0 ]] && PROMPT+="%F{yellow}!$modified_count%f"
        [[ $staged_count -gt 0 ]] && PROMPT+="%F{green}+$staged_count%f"
        [[ $untracked_count -gt 0 ]] && PROMPT+="%F{red}?$untracked_count%f"
        [[ $unpushed_count -gt 0 ]] && PROMPT+="%F{magenta}↑$unpushed_count%f"
    fi

    PROMPT+="%F{cyan}]%f"$'\n'
    
    # 0:    I just dont wanna see if its successful
    # 130:  That happens when I start trying a command then CTRL+C
    [[ $exit_code -ne 0 && $exit_code -ne 130 ]] && PROMPT+='%F{red}[%?]%f'
    
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

function _cfg_completion {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    _arguments -C \
        '1: :->command' \
        '*::arg:->args'

    case $state in
        command)
            _describe -t commands "git command" _git_commands
            ;;
        args)
            case $line[1] in
                add)
                    _arguments '*:file:_files'
                    ;;
                *)
                    _git
                    ;;
            esac
            ;;
    esac
}

compdef _cfg_completion cfg 
compdef _cfg_completion cfga

autoload -Uz compinit && compinit

# Edit command line in vim with Ctrl+F Ctrl+F
autoload -U edit-command-line
zle -N edit-command-line
bindkey '^F^F' edit-command-line

# Make sure it uses your preferred editor
export VISUAL="${EDITOR}"




