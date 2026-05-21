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

    local subcommands="wizard create list status shell exec start stop restart reboot snapshot snap migrate rebuild rerun destroy terminate doctor types"
    local types="tiny small medium large xl 2xl"
    local envs="dev staging prod"

    # First word after `jaah-vm`
    if [ "$cword" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcommands --version --help" -- "$cur") )
        return 0
    fi

    local sub="${COMP_WORDS[1]}"

    # Subcommands that take a managed VM name or VMID (cword 2)
    if [[ "$sub" =~ ^(shell|status|exec|start|stop|restart|reboot|snapshot|snap|migrate|destroy|terminate|rebuild|rerun)$ ]] && [ "$cword" -eq 2 ]; then
        local vms=""
        # Tier A: world-readable plain-text cache (works as any user, even
        # during a jaah-vm upgrade). Refreshed by cmd_create / _do_destroy.
        if [ -r /var/lib/jaah-vm/names.cache ]; then
            vms=$(cat /var/lib/jaah-vm/names.cache 2>/dev/null)
        # Tier B: fallback — read manifests directly via jq.
        elif [ -d /etc/pve/jaah-vm ] && command -v jq >/dev/null 2>&1; then
            vms=$(for f in /etc/pve/jaah-vm/*.json; do
                [ -e "$f" ] && jq -r '.name' "$f" 2>/dev/null
            done)
        fi
        COMPREPLY=( $(compgen -W "$vms" -- "$cur") )
        return 0
    fi

    # `migrate` second arg = target node (after the VM name)
    if [ "$sub" = "migrate" ] && [ "$cword" -eq 3 ]; then
        local nodes
        nodes=$(pvecm nodes 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {gsub(/\(local\)/,""); print $3}' | sed 's/[[:space:]]//g')
        COMPREPLY=( $(compgen -W "$nodes --offline --targetstorage" -- "$cur") )
        return 0
    fi

    # `migrate` flag completion (after target node)
    if [ "$sub" = "migrate" ]; then
        case "$prev" in
            --targetstorage)
                local stos
                stos=$(pvesm status 2>/dev/null | awk 'NR>1{print $1}')
                COMPREPLY=( $(compgen -W "$stos" -- "$cur") ); return 0;;
        esac
        if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "--offline --targetstorage" -- "$cur") )
            return 0
        fi
    fi

    # `exec` flag completion (after VM name + --)
    if [ "$sub" = "exec" ] && [ "$cword" -ge 3 ]; then
        case "$prev" in
            --timeout) COMPREPLY=(); return 0;;
        esac
        if [ "$cword" -eq 3 ] && [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "-- --timeout" -- "$cur") )
            return 0
        fi
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
                nodes=$(pvecm nodes 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {gsub(/\(local\)/,""); print $3}')
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
