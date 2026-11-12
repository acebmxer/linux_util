#!/bin/bash
# Multimedia Codecs installer functions
#
# Full audio/video playback and encoding (H.264, HEVC, AAC and the rest) for
# FFmpeg and GStreamer apps (Firefox, Totem, Dolphin previews, Kdenlive).
#   Fedora   RPM Fusion; Fedora's ffmpeg-free swapped for RPM Fusion's ffmpeg,
#            then the multimedia group, which adds RPM Fusion's GStreamer
#            plugins (the steps RPM Fusion's own guide gives)
#   RHEL     RPM Fusion for EL; ffmpeg and the GStreamer plugins by name
#            (EL has no multimedia group with RPM Fusion's packages in it)
#   Debian   ffmpeg and the GStreamer plugin sets; Ubuntu needs universe
#   Arch     ffmpeg and the GStreamer plugin sets
#   openSUSE opi codecs, openSUSE's own tool: adds Packman and switches the
#            codec packages to its full builds

# GStreamer libav plugin package on RHEL clones: EL 8 calls it gstreamer1-libav,
# EL 9 and later gstreamer1-plugin-libav.
_codecs_rhel_libav() {
    if [[ "${DISTRO_VERSION_ID%%.*}" == "8" ]]; then echo gstreamer1-libav; else echo gstreamer1-plugin-libav; fi
}

# Packages whose presence means the codecs are installed, one per line.
_codecs_packages() {
    case "$DISTRO_FAMILY" in
        fedora) printf '%s\n' ffmpeg gstreamer1-plugin-libav gstreamer1-plugins-ugly gstreamer1-plugins-bad-freeworld ;;
        rhel)   printf '%s\n' ffmpeg "$(_codecs_rhel_libav)" gstreamer1-plugins-ugly gstreamer1-plugins-bad-freeworld gstreamer1-plugins-good ;;
        debian) printf '%s\n' ffmpeg gstreamer1.0-libav gstreamer1.0-plugins-ugly gstreamer1.0-plugins-bad gstreamer1.0-plugins-good ;;
        arch)   printf '%s\n' ffmpeg gst-libav gst-plugins-ugly gst-plugins-bad gst-plugins-good ;;
        suse)   printf '%s\n' gstreamer-plugins-libav gstreamer-plugins-ugly gstreamer-plugins-bad ;;
    esac
}

_codecs_packman_enabled() {
    zypper --non-interactive lr -u 2>/dev/null | grep -qi 'packman'
}

check_multimedia_codecs() {
    local pkg
    case "$DISTRO_FAMILY" in
        fedora|rhel) rpmfusion_enabled free || return 1 ;;
        suse)        _codecs_packman_enabled || return 1 ;;
        debian|arch) ;;
        *)           return 1 ;;
    esac
    while IFS= read -r pkg; do
        pkg_check_installed "$pkg" || return 1
    done < <(_codecs_packages)
    _have_cmd ffmpeg
}

install_multimedia_codecs() {
    info "Installing multimedia codecs..."
    local -a pkgs=()
    mapfile -t pkgs < <(_codecs_packages)

    case "$DISTRO_FAMILY" in
        fedora)
            ensure_rpmfusion nonfree || return 1
            # Fedora's ffmpeg-free leaves out the patent-encumbered codecs.
            if pkg_check_installed ffmpeg-free; then
                run_with_spinner "Replacing ffmpeg-free with RPM Fusion's ffmpeg" \
                    sudo "$PKG_MGR" swap -y ffmpeg-free ffmpeg --allowerasing || {
                    error "Failed to replace ffmpeg-free with ffmpeg."
                    return 1
                }
            else
                pkg_install ffmpeg || return 1
            fi
            # PackageKit's GStreamer plugin pops up "install codec?" prompts
            # that are no longer needed once the codecs are present.
            run_with_spinner "Installing the multimedia group" \
                sudo "$PKG_MGR" group install -y multimedia \
                    --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin || {
                error "Failed to install the multimedia group."
                return 1
            }
            ;;
        rhel)
            ensure_rpmfusion free || return 1
            pkg_install "${pkgs[@]}" || return 1
            ;;
        debian)
            pkg_install "${pkgs[@]}" || {
                [[ "$DISTRO_ID" =~ ^(ubuntu|kubuntu|neon)$ ]] && \
                    warn "These packages are in Ubuntu's universe component; enable it in Software & Updates and try again."
                return 1
            }
            ;;
        arch)
            pkg_install "${pkgs[@]}" || return 1
            ;;
        suse)
            pkg_check_installed opi || pkg_install opi || return 1
            # -n answers opi's prompts itself: adds Packman on its first
            # mirror, imports its key and adds the openh264 repository.
            run_with_spinner "Installing codecs from Packman (opi codecs)" sudo opi -n codecs || {
                error "opi codecs failed."
                return 1
            }
            ;;
        *)
            error "Multimedia codecs are not supported on ${DISTRO_NAME}."
            return 1
            ;;
    esac
    info "Multimedia codecs installed."
}

uninstall_multimedia_codecs() {
    warn "The codecs are shared libraries that media apps (VLC, OBS, HandBrake, browsers) link against."
    warn "Removing them can remove or break those apps, so this operation is not supported."
    return 1
}

update_multimedia_codecs() {
    info "Updating multimedia codecs..."
    local -a pkgs=()
    mapfile -t pkgs < <(_codecs_packages)
    # On openSUSE the packages stay with Packman's vendor once opi has switched
    # them, so a plain upgrade keeps taking Packman's builds.
    (( ${#pkgs[@]} )) && pkg_upgrade "${pkgs[@]}"
}

# The FFmpeg version from the first line of `ffmpeg -version` on stdin:
# "ffmpeg version 9.0.2 Copyright..." (Fedora), "7.1.5-0+deb13u1" (Debian),
# "n7.1" (some builds). Prints nothing for anything else.
_codecs_version_from_output() {
    head -1 | grep -oP '^ffmpeg version n?\K[0-9]+(\.[0-9]+)+' || true
}

# Reported as the FFmpeg version.
get_version_multimedia_codecs() {
    local bin
    bin=$(_native_command ffmpeg) || { echo ""; return 0; }
    "$bin" -version 2>/dev/null | _codecs_version_from_output
}
