#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# hector_recorder_completion.bash – wrapper and autocompletion for 'bag_recorder'
# -----------------------------------------------------------------------------

# -------------------------
# Main command
# -------------------------
bag_recorder() {
    ros2 run hector_recorder record "$@"
}

# -------------------------
# Autocompletion-function
# -------------------------
_bag_recorder_completion() {
    local cur prev opts
    COMPREPLY=()

    # Get current and previous word (bash-completion helper)
    if declare -F _get_comp_words_by_ref >/dev/null 2>&1; then
      _get_comp_words_by_ref -n : cur prev
    else
      cur="${COMP_WORDS[COMP_CWORD]}"
      prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi

    # List of all args for the command.
    opts=(
        -o --output
        -s --storage
        -t --topics
        --services
        --topic-types
        -a --all
        --all-topics
        --all-services
        -e --regex
        --exclude-regex
        --exclude-topic-types
        --exclude-topics
        --exclude-services
        --include-unpublished-topics
        --include-hidden-topics
        --no-discovery
        -p --polling-interval
        --publish-status
        --ignore-leaf-topics
        -f --serialization-format
        -b --max-bag-size
        --gb --max-bag-size-gb
        -d --max-bag-duration
        --max-cache-size
        --disable-keyboard-controls
        --start-paused
        --use-sim-time
        --node-name
        --custom-data
        --snapshot-mode
        --compression-queue-size
        --compression-threads
        --compression-threads-priority
        --compression-mode
        --compression-format
        -c --config
        -h --help
        --publish-status-topic
        --ros-args
    )

    # Options that accept multiple values
    is_multi_value_option() {
        case "$1" in
            -t|--topics|--exclude-topics|--services|--exclude-services|--topic-types|--exclude-topic-types)
                return 0 ;;
            *) return 1 ;;
        esac
    }

    # Determine if we are currently completing values for a multi-value option
    local current_option=""
    local i
    for (( i=COMP_CWORD-1; i >= 0; i-- )); do
        local word="${COMP_WORDS[i]}"
        if [[ "$word" == -* ]]; then
            if is_multi_value_option "$word"; then
                current_option="$word"
            fi
            break
        fi
    done

    # Path completions for specific options
    case "$prev" in
        -o|--output|-s|--storage)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        -c|--config)
            COMPREPLY=( $(compgen -f -- "$cur" | xargs -I {} bash -c '[[ -f "{}" ]] && echo "{}"') )
            return 0
            ;;
    esac

    # If starting a new option, suggest options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "${opts[*]}" -- "$cur") )
        return 0
    fi

    # Completions for multi-value options
    case "$current_option" in
        -t|--topics|--exclude-topics)
            COMPREPLY=( $(compgen -W "$(ros2 topic list 2>/dev/null)" -- "$cur") )
            return 0
            ;;
        --services|--exclude-services)
            COMPREPLY=( $(compgen -W "$(ros2 service list 2>/dev/null)" -- "$cur") )
            return 0
            ;;
        --topic-types|--exclude-topic-types)
            COMPREPLY=( $(compgen -W "$(ros2 topic list -t 2>/dev/null | awk '{print $2}' | sort -u)" -- "$cur") )
            return 0
            ;;
    esac

    # Default: no completion
    return 0
}

# -------------------------
# Autocomplete-registration
# -------------------------
complete -F _bag_recorder_completion bag_recorder