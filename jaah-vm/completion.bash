# Bash completion for jaah-vm
# Install: cp completion.bash /etc/bash_completion.d/jaah-vm

_jaah_vm() {
    local cur prev words cword
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -n : || return
    else
        # Minimal fallback if bash-completion package not installed
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]:-}"
        cword=$COMP_CWORD
    fi

    local subcommands="create rerun list status shell destroy doctor types"
    local types="tiny small medium large xl 2xl"
    local envs="dev staging prod"

    # First word after `jaah-vm`
    if [ "$cword" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcommands --version --help" -- "$cur") )
        return 0
    fi

    local sub="${COMP_WORDS[1]}"

    # Subcommands that take a managed VM name or VMID
    if [[ "$sub" =~ ^(shell|status|destroy|rerun)$ ]] && [ "$cword" -eq 2 ]; then
        local vms=""
        if command -v jaah-vm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
            vms=$(jaah-vm list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null)
        fi
        COMPREPLY=( $(compgen -W "$vms" -- "$cur") )
        return 0
    fi

    # `create` flag completion
    if [ "$sub" = "create" ]; then
        case "$prev" in
            --type)    COMPREPLY=( $(compgen -W "$types" -- "$cur") ); return 0;;
            --env)     COMPREPLY=( $(compgen -W "$envs" -- "$cur") ); return 0;;
            --snippet) COMPREPLY=( $(compgen -f -- "$cur") ); return 0;;
            --cpu)     COMPREPLY=( $(compgen -W "x86-64-v2-AES x86-64-v3 host" -- "$cur") ); return 0;;
            --node)
                local nodes
                nodes=$(pvecm nodes 2>/dev/null | awk 'NR>3{print $3}')
                COMPREPLY=( $(compgen -W "$nodes" -- "$cur") ); return 0;;
            --storage)
                local stos
                stos=$(pvesm status 2>/dev/null | awk 'NR>1{print $1}')
                COMPREPLY=( $(compgen -W "$stos" -- "$cur") ); return 0;;
        esac
        local flags="--name --type --env --snippet --snippet-allow-exec --set-password
                     --start --wait-ssh --dry-run --json --replace --advanced
                     --vmid --cores --memory --disk --storage --bridge --vlan
                     --ip --gw --dns --cpu --i-know-this-breaks-migration
                     --ssh-timeout --node --tags --help"
        COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
        return 0
    fi

    # `doctor` flag completion
    if [ "$sub" = "doctor" ] && [ "$cword" -eq 2 ]; then
        COMPREPLY=( $(compgen -W "--rebuild-template" -- "$cur") )
        return 0
    fi

    return 0
}
complete -F _jaah_vm jaah-vm
