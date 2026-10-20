#!/bin/bash
# Signals for front ends such as Linux_Util Desktop.
#
# linux_util.sh sources this only when LINUX_UTIL_GUI=1 is set; a plain
# terminal run never loads it. Nothing here changes what a question asks or
# what answer it takes. It only tells the program running linux_util on a
# terminal when a question is waiting, with a private escape sequence that
# program strips from the output:
#
#   ESC ] 7701 ; wait ; <mode> ; <hidden> BEL   just before the read
#   ESC ] 7701 ; done BEL                        just after it
#
# <mode> is "key" when -n/-N reads a fixed number of keys, "line" otherwise.
# <hidden> is 1 when -s hides the input, 0 otherwise. Reads that are not from
# the terminal (a file, a pipe) and short timed reads (the menu drains Esc
# sequences with -t 0.05) send nothing. The format is fixed: Linux_Util
# Desktop releases already read it.

read() {
    local __lu_fd=0 __lu_mode=line __lu_hidden=0 __lu_t="" __lu_want="" __lu_a __lu_i __lu_c
    for __lu_a in "$@"; do
        # The value of an option given as its own word (-u 3, -t 10, -p "...").
        if [[ -n "$__lu_want" ]]; then
            case "$__lu_want" in
                u) __lu_fd=$__lu_a ;;
                t) __lu_t=$__lu_a ;;
            esac
            __lu_want=""
            continue
        fi
        case "$__lu_a" in
            --) break ;;
            -?*) ;;
            *) break ;;
        esac
        # Walk an option cluster such as -rsn1 or -rp.
        __lu_i=1
        while (( __lu_i < ${#__lu_a} )); do
            __lu_c=${__lu_a:__lu_i:1}
            (( __lu_i += 1 ))
            case "$__lu_c" in
                s) __lu_hidden=1 ;;
                n|N) __lu_mode=key ;;
            esac
            case "$__lu_c" in
                a|d|i|n|N|p|t|u)
                    # These take a value: the rest of this word, or the next one.
                    if (( __lu_i < ${#__lu_a} )); then
                        case "$__lu_c" in
                            u) __lu_fd=${__lu_a:__lu_i} ;;
                            t) __lu_t=${__lu_a:__lu_i} ;;
                        esac
                    else
                        __lu_want=$__lu_c
                    fi
                    break
                    ;;
            esac
        done
    done
    case "$__lu_t" in
        0|0.*|.*) builtin read "$@"; return ;;
    esac
    if ! [[ -t "$__lu_fd" ]] || ! { : >/dev/tty; } 2>/dev/null; then
        builtin read "$@"
        return
    fi
    printf '\033]7701;wait;%s;%s\007' "$__lu_mode" "$__lu_hidden" >/dev/tty
    builtin read "$@"
    local __lu_rc=$?
    printf '\033]7701;done\007' >/dev/tty 2>/dev/null
    return $__lu_rc
}

# Child bash scripts started by an installer inherit read() through the
# environment, but sudo drops exported functions. A step run as
# `sudo [-E] bash <script> ...` (Xen Guest Utilities' own installer, for one)
# therefore loads this file again inside root's bash before running it.
# Every other sudo call goes to the real sudo unchanged.
sudo() {
    local -a __lu_opts=()
    while [[ "${1:-}" == "-E" || "${1:-}" == "--preserve-env" ]]; do
        __lu_opts+=("$1")
        shift
    done
    if [[ "${1:-}" == "bash" && -r "${LINUX_UTIL_FRONT_END_LIB:-}" ]]; then
        shift
        command sudo "${__lu_opts[@]}" bash -c \
            '. "$1"; shift; export -f read; exec bash "$@"' \
            bash "$LINUX_UTIL_FRONT_END_LIB" "$@"
        return
    fi
    command sudo "${__lu_opts[@]}" "$@"
}
