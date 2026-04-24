autoload -Uz vcs_info

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '%b'
zstyle ':vcs_info:git:*' actionformats '%b|%a'

setopt PROMPT_SUBST

# Parse git status --porcelain -b into counts (single git call)
# Usage: _git_counts [git-flags...]
# Sets: _staged, _modified, _untracked, _ahead
_git_counts() {
    _staged=0 _modified=0 _untracked=0 _ahead=0
    local line
    while IFS= read -r line; do
        if [[ "$line" == '##'* ]]; then
            [[ "$line" =~ '\[ahead ([0-9]+)' ]] && _ahead=${match[1]}
        elif [[ "${line[1,2]}" == '??' ]]; then
            (( _untracked++ ))
        else
            [[ "${line[1]}" == [MADRC] ]] && (( _staged++ ))
            [[ "${line[2]}" == [MD] ]] && (( _modified++ ))
        fi
    done < <("$@" status --porcelain -b 2>/dev/null)
}

precmd() {
    local exit_code=$?
    vcs_info

    PROMPT='%F{cyan}[%f%F{magenta}%n@%m '

    # Dotfiles bare repo (-uno skips untracked since work-tree is $HOME)
    if [[ -d "$HOME/.cfg" ]]; then
        _git_counts git --git-dir="$HOME/.cfg/" --work-tree="$HOME" -c status.showUntrackedFiles=no
        if (( _modified + _staged + _ahead > 0 )); then
            PROMPT+="%F{cyan}.{%f"
            (( _modified > 0 )) && PROMPT+="%F{yellow}!${_modified}%f"
            (( _staged > 0 )) && PROMPT+="%F{green}+${_staged}%f"
            (( _ahead > 0 )) && PROMPT+="%F{magenta}↑${_ahead}%f"
            PROMPT+="%F{cyan}}%f "
        fi
    fi

    PROMPT+='%F{blue}%~%f '

    # Regular git repo (vcs_info detects branch)
    if [[ -n "${vcs_info_msg_0_}" ]]; then
        PROMPT+="%F{red}${vcs_info_msg_0_}%f "
        _git_counts git
        (( _modified > 0 )) && PROMPT+="%F{yellow}!${_modified}%f"
        (( _staged > 0 )) && PROMPT+="%F{green}+${_staged}%f"
        (( _untracked > 0 )) && PROMPT+="%F{red}?${_untracked}%f"
        (( _ahead > 0 )) && PROMPT+="%F{magenta}↑${_ahead}%f"
    fi

    PROMPT+="%F{cyan}]%f"$'\n'

    # 0:    I just dont wanna see if its successful
    # 130:  That happens when I start trying a command then CTRL+C
    [[ $exit_code -ne 0 && $exit_code -ne 130 ]] && PROMPT+='%F{red}[%?]%f'

    PROMPT+='%F{black}$ '
}

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






# Codex desktop notifications wrapper.
if [[ -x "$HOME/.codex/codex-with-notify.sh" ]]; then
  codex() {
    "$HOME/.codex/codex-with-notify.sh" "$@"
  }
  alias codexn="$HOME/.codex/codex-with-notify.sh"
fi

# opencode
export PATH=/home/darthvader/.opencode/bin:$PATH
