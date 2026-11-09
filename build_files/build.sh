#!/bin/bash

set -ouex pipefail

### Repos
# Every repo enabled here is disabled again below, so none ship turned on.
COPRS=(
  duxlabs/dms         # Dux shell (dms)
  duxlabs/dux-repo    # quickshell, matugen, dux-greeter, dux-* apps, ghostty
  lionheartp/Hyprland # Hyprland (not in Fedora)
)
for copr in "${COPRS[@]}"; do
  dnf5 -y copr enable "${copr}"
done

# Terra, for mango only (packaged as mangowm; needs scenefx from Terra too)
# $releasever is expanded by dnf, not the shell.
# shellcheck disable=SC2016
dnf5 -y install --nogpgcheck \
  --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
  terra-release

# Keep the broad repos from replacing what Dux depends on: the Hyprland COPR
# also ships git snapshots of quickshell/matugen/cliphist that would otherwise
# win over the duxlabs/Fedora builds, and Terra may only supply mango.
dnf5 -y config-manager setopt \
  "copr:copr.fedorainfracloud.org:lionheartp:Hyprland.excludepkgs=quickshell*,matugen*,cliphist*" \
  "terra.includepkgs=mangowm,scenefx*"

### Install packages
# build_files/packages.txt: one or more names per line, '#' starts a comment
sed 's/#.*//' /ctx/packages.txt | xargs dnf5 -y install --refresh

# base-main ships the Firefox RPM; owlOS uses Firefox from Flathub instead
# (flatpaks.list), so drop the RPM to avoid two Firefoxes.
dnf5 -y remove firefox firefox-langpacks

### Disable the extra repos again
for copr in "${COPRS[@]}"; do
  dnf5 -y copr disable "${copr}"
done
dnf5 -y config-manager setopt terra.enabled=0

### Copy the contents of system_files/ of the git repo to /
# Done after the package install so our files win over package defaults: the
# greetd RPM ships its own /etc/greetd/config.toml, and dux-greeter's %post
# rewrites any config that doesn't use dms-greeter (to niri).
cp -avf "/ctx/system_files"/. /
rm -f /etc/greetd/config.toml.rpmnew /etc/greetd/config.toml.rpmsave

### Default user configs in /etc/skel
# Dux's own `dms setup headless` writes the mango, niri and Hyprland configs
# (each starts Dux with `dms run`, terminal binds use ghostty) plus the ghostty
# config, so they always match the Dux version in the image. useradd copies
# /etc/skel into every new home, so the configs exist before the first login:
# greetd starts mango straight from mango.desktop and mango reads its config at
# startup, which a first-login user service would be too late for.
# dms refuses to run as root, so it runs as nobody in a scratch HOME.
SKEL_HOME="$(mktemp -d)"
chown 65534:65534 "${SKEL_HOME}"
for wm in mango niri hyprland; do
  setpriv --reuid=65534 --regid=65534 --clear-groups \
    env -i HOME="${SKEL_HOME}" PATH=/usr/bin:/usr/sbin TERMINAL=ghostty \
    dms setup headless --compositor "${wm}" --terminal ghostty --skip-existing --no-systemd
done
mkdir -p /etc/skel/.config
cp -a "${SKEL_HOME}/.config/." /etc/skel/.config/
chown -R root:root /etc/skel/.config
rm -rf "${SKEL_HOME}"

### Default Flatpak apps
# Turn /usr/share/owlos/flatpaks.list (one Flathub app ID per line) into a
# flatpak preinstall file; owlos-flatpak-preinstall.service applies it at boot.
# Flathub apps live on the "stable" branch (preinstall defaults to "master").
mkdir -p /usr/share/flatpak/preinstall.d
sed 's/#.*//' /usr/share/owlos/flatpaks.list | xargs -n1 |
  while read -r app; do
    printf '[Flatpak Preinstall %s]\nBranch=stable\n\n' "${app}"
  done >/usr/share/flatpak/preinstall.d/owlos.preinstall
cat /usr/share/flatpak/preinstall.d/owlos.preinstall

### Sanity checks: every package landed and each compositor has a login session
sed 's/#.*//' /ctx/packages.txt | xargs rpm -q
for session in mango niri hyprland; do
  test -f "/usr/share/wayland-sessions/${session}.desktop"
done
rpm -q --qf 'mango (mangowm) %{VERSION}\n' mangowm
# The login screen must be the Dux greeter running on mango
grep -q '^command = "/usr/bin/dms-greeter --command mango"' /etc/greetd/config.toml
# Every compositor's default config starts Dux and opens ghostty, never another terminal
grep -q '^exec_once=dms run' /etc/skel/.config/mango/config.conf
grep -q 'spawn-at-startup "dms" "run"' /etc/skel/.config/niri/config.kdl
grep -q 'exec_cmd("dms run")' /etc/skel/.config/hypr/hyprland.lua
grep -q 'bind=SUPER,Return,spawn,ghostty' /etc/skel/.config/mango/dms/binds.conf
grep -q 'Mod+Return .*spawn "ghostty"' /etc/skel/.config/niri/dms/binds.kdl
grep -q 'SUPER + Return", hl.dsp.exec_cmd("ghostty")' /etc/skel/.config/hypr/dms/binds.lua
test -f /etc/skel/.config/ghostty/config
# (`! cmd` is exempt from set -e, so these use explicit exits)
if grep -qE 'alacritty|kitty' /etc/skel/.config/{mango,niri,hypr}/dms/binds.*; then exit 1; fi
if grep -rq "${SKEL_HOME}" /etc/skel/.config; then exit 1; fi
# Default apps: Firefox comes from Flathub (no RPM), ghostty is the terminal
if rpm -q firefox; then exit 1; fi
grep -q '^\[Flatpak Preinstall org.mozilla.firefox\]$' /usr/share/flatpak/preinstall.d/owlos.preinstall
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
grep -qx 'com.mitchellh.ghostty.desktop' /usr/share/xdg-terminal-exec/xdg-terminals.list
# Disk images (qcow2/ISO) need a default root filesystem
grep -q '^type = "btrfs"' /usr/lib/bootc/install/20-owlos.toml

### Services
systemctl enable podman.socket

# Login screen: greetd + Dux greeter (base-main has no other display manager).
# This is what `dms-greeter enable` would do; the greeter user, group and
# cache dir come from dux-greeter's sysusers.d/tmpfiles.d entries.
systemctl enable greetd.service
systemctl set-default graphical.target

# Default Flatpak apps (Flathub itself is added by ublue's flatpak-add-fedora-repos.service)
systemctl enable owlos-flatpak-preinstall.service

# Tailscale daemon (Fedora's tailscale package doesn't enable it); it stays idle
# until a user runs `sudo tailscale up`
systemctl enable tailscaled.service

### Clean up before finalizing the image
rm -rf /run/selinux-policy
rm -rf /run/dnf
rm -rf /tmp/*
rm -rf /var/tmp/*
dnf5 clean all
rm -rf /var/cache/dnf /var/lib/dnf/repos /var/lib/dnf/system-repo.lock
