#!/usr/bin/busybox sh
set -e

XPKG_VERSION="0.1.0"

: "${XPKG_PREFIX:=}"
: "${XPKG_STORE:=${XPKG_PREFIX}/xpkg-store}"

echo "PREFIX: ${XPKG_PREFIX:-/}"
echo "STORE: $XPKG_STORE"

bootstrap=0
clean=0
dont_ask=0
skip_if_modified='^etc\/'
pending_pkgs=""
pkgs_to_archive=""

# :: () -> () [[no_return]]
main()
{
    local opt
    local has_any_arg
    local fullpkg
    local pkgname
    local op
    local failure_count

    has_any_arg=0
    while getopts hi:u:a:k:cby opt; do
        has_any_arg=1
        case "$opt" in
            h) help ;;

            i)
                if ! [[ -f "$OPTARG" ]]; then
                    >&2 printf "\e[1m ERROR \e[0m Invalid file: %s\n" "$OPTARG"
                    exit 1
                fi

                if echo "$OPTARG" | grep -qv '\.tar\.gz$'; then
                    >&2 printf "\e[1m ERROR \e[0m Path must ends with \".tar.gz\": %s\n" "$OPTARG"
                    exit 1
                fi

                fullpkg="$(basename "$OPTARG" .tar.gz)"
                validate_full_package_name "$fullpkg"
                pkgname="${fullpkg%@*}"

                if fullpkg="$(resolve_full_package_name "$pkgname" 2>/dev/null)"; then
                    pending_pkgs="$pending_pkgs${pending_pkgs:+ }uninstall:$fullpkg"
                fi
                pending_pkgs="$pending_pkgs${pending_pkgs:+ }install:$OPTARG"
                ;;

            u)
                fullpkg="$(resolve_full_package_name "$OPTARG")"
                pending_pkgs="$pending_pkgs${pending_pkgs:+ }uninstall:$fullpkg"
                ;;

            a)
                fullpkg="$(resolve_full_package_name "$OPTARG")"
                pkgs_to_archive="$pkgs_to_archive${pkgs_to_archive:+ }$fullpkg"
                ;;

            k) skip_if_modified="$OPTARG" ;;
            c) clean=1 ;;
            b) bootstrap=1 ;;
            y) dont_ask=1 ;;

            *)
                >&2 printf "\e[1m ERROR \e[0m Invalid argument: %s\n" "$opt"
                help 1
                ;;
        esac
    done
    shift $((OPTIND - 1))
    [[ -n "$*" ]] && help 1
    [[ "$has_any_arg" == 0 ]] && help

    mkdir -p "${XPKG_PREFIX:-/}"
    mkdir -p "${XPKG_STORE}"

    # Deduplicate PLAN
    pending_pkgs="$(
        for plan in $pending_pkgs; do
            printf "%s\n" "$plan"
        done | awk '!x[$0]++'
    )"

    # Ask the user for permission of executing PLAN
    printf "\e[1;34mPLAN\e[0m"
    [[ "$clean" == 0 ]] && printf " (skip /$skip_if_modified/ if modified, unimplemented)"
    [[ "$clean" != 0 ]] && printf " (no skip)"
    printf "\n"
    [[ "$bootstrap" != 0 ]] && printf "  bootstrap\n"
    for pkg in $pkgs_to_archive; do
        printf "  archive:%s (unimplemented)\n" "$pkg"
    done
    for plan in $pending_pkgs; do
        printf "  %s\n" "$plan"
    done
    ask_Yn_or_quit "Execute the plan?"

    # Execute PLAN
    failure_count=0

    if [[ "$bootstrap" != 0 ]]; then
        if ! bootstrap; then
            printf "\e[1;31m FAILED    \e[0m %s\n" "bootstrap"
            : $((failure_count++))
        fi
    fi

    for plan in $pending_pkgs; do
        op="${plan%%:*}"
        fullpkg="${plan#*:}"
        if ! ${op}_package "$fullpkg"; then
            printf "\e[1;31m FAILED    \e[0m %s\n" "$plan"
            : $((failure_count++))
        fi
    done

    if [[ "$failure_count" != 0 ]]; then
        >&2 printf "\e[1;31m ERROR \e[0m Failed %d plans.\n" "$failure_count"
        exit 1
    fi

    exit 0
}

# :: () -> ()
help()
{
    printf "\n"
    printf "xpkg v%s - extraction-based package manager\n" "$XPKG_VERSION"
    printf "\n"
    printf "USAGE\n"
    printf "  %s [OPTIONS] [--]\n" "$0"
    printf "\n"
    printf "OPTIONS\n"
    printf "  -h                        Display this text.\n"
    printf "  -i /some/pkg@ver.tar.gz   Add package to install queue.\n"
    printf "  -u pkg                    Add package to uninstall queue.\n"
    printf "  -a pkg                    Archive: create package file from installed package.\n"
    printf "  -k regex                  Skip the matched path if modified (default '^etc\\/').\n"
    printf "  -c                        Clean: ignore skipped filenames.\n"
    printf "  -b                        Bootstrap: install this script as an xpkg package.\n"
    printf "  -y                        Yes: don't ask questions.\n"
    exit "${1:-0}"
}

bootstrap()
{
    local bootstrap_prefix
    local rootfs
    local pkgpath
    local file
    local fullpkg

    bootstrap_prefix="$XPKG_STORE/bootstrap"
    pkgpath="$bootstrap_prefix/xpkg@$XPKG_VERSION.tar.gz"
    printf "\e[1;35m CREATE   \e[0m %s\n" "$pkgpath"

    rootfs="$bootstrap_prefix/rootfs"
    rm -rf -- "$rootfs"

    install -Dm 755 -- "$0" "$rootfs/usr/bin/xpkg" || return 1

    tar czvf "$pkgpath" -C "$rootfs" usr | while read -r file; do
        if [[ -f "$rootfs/$file" ]]; then
            printf "    collect %s\n" "$rootfs/$file"
        fi
    done || return 1

    rm -rf -- "$rootfs"

    if fullpkg="$(resolve_full_package_name "xpkg" 2>/dev/null)"; then
        uninstall_package "$fullpkg" || return 1
    fi
    install_package "$pkgpath" || return 1

    return 0
}

install_package()
{
    local path
    local fullpkg
    local has_any_conflict
    local file
    local md5

    path="$1"
    printf "\e[1;32m INSTALL   \e[0m %s\n" "$path"

    fullpkg="$(basename "$path" .tar.gz)"
    validate_full_package_name "$fullpkg" || return 1

    has_any_conflict=0
    tar tf "$path" | (
        while read -r file; do
            if [[ -f "$XPKG_PREFIX/$file" ]]; then
                >&2 printf "    \e[0;31mfile exists\e[0m %s\n" "$XPKG_PREFIX/$file"
                has_any_conflict=1
            fi
        done
        exit "$has_any_conflict"
    ) || return 1

    pkgstore="$XPKG_STORE/$fullpkg"
    tar xzvf "$path" -C "$XPKG_PREFIX" | while read -r file; do
        if [[ -f "$XPKG_PREFIX/$file" ]]; then
            printf "    extract %s\n" "$XPKG_PREFIX/$file"
            md5="$(md5sum "$XPKG_PREFIX/$file")"
            printf "%s %s\n" "${md5% *}" "$file" >> "$pkgstore"
        fi
    done || return 1

    return 0
}

uninstall_package()
{
    local fullpkg
    local md5
    local path
    local fullpath

    fullpkg="$1"
    printf "\e[1;33m UNINSTALL \e[0m %s\n" "$fullpkg"

    cat "$XPKG_STORE/$fullpkg" | while read -r md5 path; do
        [[ -z "$path" ]] && continue

        fullpath="$XPKG_PREFIX/$path"
        printf "    remove %s\n" "$fullpath"

        if ! rm -f -- "$fullpath"; then
            return 1
        fi
    done

    if ! rm -f -- "$XPKG_STORE/$fullpkg"; then
        return 1
    fi

    return 0
}

# :: (string pkgname) -> (string fullpkg)
# fullpkg: pkgname@pkgver
resolve_full_package_name()
{
    local paths
    local fullpkg

    paths="$(echo "$XPKG_STORE/$1@"*)"

    if echo "$paths" | grep -q '\*'; then
        >&2 printf "\e[1m ERROR \e[0m No such package: %s\n" "$1"
        return 1
    fi

    if echo "$paths" | grep -q '\s'; then
        >&2 printf "\e[1m ERROR \e[0m Multiple version of same package: %s\n" "$1"
        return 1
    fi

    fullpkg="$(basename "$paths")"
    validate_full_package_name "$fullpkg" || return 1
    echo "$fullpkg"

    return 0
}

# :: (string fullpkg) -> ()
validate_full_package_name()
{
    if echo "$1" | grep -qv '^[a-z0-9-]\+@[a-z0-9.]\+$'; then
        >&2 printf "\e[1m ERROR \e[0m Invalid full package name: %s\n" "$1"
        return 1
    else
        return 0
    fi
}

# :: (string prompt) -> ()
# Returns if user typed Y/y or newline.
# No return (exit) otherwise.
ask_Yn_or_quit()
{
    local prompt
    if [[ $dont_ask == 0 ]]; then
        prompt="$(printf "\e[1;37m%s\e[0m [Y/n] " "$1")"
        read -n1 -d $'\0' -p "$prompt"
        [[ "$REPLY" != $'\n' ]] && printf "\n"
        [[ "$REPLY" == y || "$REPLY" == Y || "$REPLY" == $'\n' ]] || exit 0
    fi
}

main "$@"

