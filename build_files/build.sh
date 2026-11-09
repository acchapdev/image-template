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

### Sanity checks: every package landed and each compositor has a login session
sed 's/#.*//' /ctx/packages.txt | xargs rpm -q
for session in mango niri hyprland; do
  test -f "/usr/share/wayland-sessions/${session}.desktop"
done
rpm -q --qf 'mango (mangowm) %{VERSION}\n' mangowm
# The login screen must be the Dux greeter running on mango
grep -q '^command = "/usr/bin/dms-greeter --command mango"' /etc/greetd/config.toml

### Services
systemctl enable podman.socket

# Login screen: greetd + Dux greeter (base-main has no other display manager).
# This is what `dms-greeter enable` would do; the greeter user, group and
# cache dir come from dux-greeter's sysusers.d/tmpfiles.d entries.
systemctl enable greetd.service
systemctl set-default graphical.target

### Clean up before finalizing the image
rm -rf /run/selinux-policy
rm -rf /run/dnf
rm -rf /tmp/*
rm -rf /var/tmp/*
dnf5 clean all
rm -rf /var/cache/dnf /var/lib/dnf/repos /var/lib/dnf/system-repo.lock
