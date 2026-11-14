#!/bin/bash
# Java JDK installer functions
#
# OpenJDK with the compiler, from the distro's own packages: default-jdk on
# Debian and Ubuntu; on the others the newest of the long-term-support builds
# the repositories carry (25, then 21, then 17): java-N-openjdk-devel on Fedora,
# RHEL clones and openSUSE, jdk-openjdk on Arch. Alpine
# installs openjdk25-jdk through alpine_packages.sh.

# --- Java JDK ---

_java_candidates() {
    case "$DISTRO_FAMILY" in
        debian) echo "default-jdk" ;;
        fedora) echo "java-25-openjdk-devel java-21-openjdk-devel java-17-openjdk-devel" ;;
        rhel)   echo "java-25-openjdk-devel java-21-openjdk-devel java-17-openjdk-devel" ;;
        suse)   echo "java-25-openjdk-devel java-21-openjdk-devel java-17-openjdk-devel" ;;
        arch)   echo "jdk-openjdk" ;;
    esac
}

# The JDK package this system's repositories carry.
_java_package() {
    local p
    for p in $(_java_candidates); do
        pkg_in_repo "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

_java_installed_package() {
    local p
    for p in $(_java_candidates); do
        pkg_check_installed "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

check_java_jdk() { _have_cmd javac || _java_installed_package >/dev/null; }

install_java_jdk() {
    info "Installing the Java JDK..."
    pkg_refresh
    local pkg
    pkg=$(_java_package) || { error "No OpenJDK is in the ${DISTRO_NAME:-system} repositories."; return 1; }
    pkg_install "$pkg" || return 1
    info "Java JDK installed (package ${pkg})."
}

uninstall_java_jdk() {
    info "Uninstalling the Java JDK..."
    local pkg
    pkg=$(_java_installed_package) || return 0
    pkg_remove "$pkg"
}

update_java_jdk() {
    info "Updating the Java JDK..."
    local pkg
    pkg=$(_java_installed_package) || return 1
    pkg_upgrade "$pkg"
}

get_version_java_jdk() {
    local v
    v=$(_run_native javac -version 2>&1 | grep -oP '[0-9]+(\.[0-9]+)*' | head -1)
    printf '%s\n' "$v"
}
