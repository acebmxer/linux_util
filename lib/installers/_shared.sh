#!/bin/bash

# ============================================================================
# Shared helper functions used across multiple installer scripts.
# This file is sourced first (underscore prefix sorts before letters).
# ============================================================================

# Parse a multi-select string (e.g. "1,3-5") into deduplicated indices (input order preserved).
# Prints one index per line; returns 1 on invalid input.
_parse_multi_selection() {
    local input="$1" max="$2"
    local -a indices=()
    local part start end i

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part="${part// /}"
        [[ -z "$part" ]] && continue
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if (( start < 1 || end > max || start > end )); then
                return 1
            fi
            for (( i=start; i<=end; i++ )); do
                indices+=("$i")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            if (( part < 1 || part > max )); then
                return 1
            fi
            indices+=("$part")
        else
            return 1
        fi
    done

    (( ${#indices[@]} == 0 )) && return 1
    # Deduplicate while preserving the user's input order
    printf '%s\n' "${indices[@]}" | awk '!seen[$0]++'
}
