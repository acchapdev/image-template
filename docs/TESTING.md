# Testing owlOS

owlOS images are x86_64 only, because `ghcr.io/ublue-os/base-main` is published for amd64 only. Testing needs an x86_64 machine: a Linux host with KVM (virt-manager, GNOME Boxes or `just run-vm-*`), or real hardware. Emulating x86 on Apple Silicon (UTM) works but is very slow for a Wayland desktop.

## 1. Get the installer ISO

1. Make sure the latest **Build container image** run on `main` succeeded. That run publishes `ghcr.io/acchapdev/owlos:latest`.
2. In GitHub, go to **Actions → Build disk images → Run workflow**, choose `platform: amd64`, and leave "Upload to S3" off.
3. When it finishes, download the `owlos-anaconda-iso` artifact from the run page (`owlos-qcow2` is the qcow2).

From the command line:

```bash
gh workflow run build-disk.yml -R acchapdev/owlOS -f platform=amd64
gh run watch -R acchapdev/owlOS "$(gh run list -R acchapdev/owlOS -w build-disk.yml -L 1 --json databaseId --jq '.[0].databaseId')"
gh run download -R acchapdev/owlOS -n owlos-anaconda-iso -D owlos-iso   # the ISO; owlos-qcow2 is the qcow2
```

On a Linux host with podman you can build the ISO locally instead: `just build-iso ghcr.io/acchapdev/owlos latest`.

## 2. Install

Boot the ISO in a VM with UEFI firmware, Secure Boot off, at least 4 GB RAM and a 30 GB disk. Secure Boot is off because ublue kernels are signed with ublue's key, which a stock Secure Boot setup doesn't trust.

**The VM needs 3D acceleration.** niri refuses software rendering ("software EGL renderers are skipped"), so without a 3D-capable virtual GPU a niri session is a blank screen. Hyprland needs a GPU too. Mango runs either way. With libvirt on a host that has a GPU (no display needed), use a virgl device and render it headless, keeping VNC to watch:

```bash
virt-install ... --video virtio,model.acceleration.accel3d=yes \
  --graphics egl-headless,gl.rendernode=/dev/dri/renderD128 \
  --graphics vnc,listen=127.0.0.1,password=<up to 8 chars>
```

Inside the guest, `journalctl -k | grep "\[drm\] features"` should show `+virgl`. macOS Screen Sharing needs the VNC password: without one it asks for a password anyway and then hangs. Connect with `ssh -L 5900:127.0.0.1:5900 <host>`, then `vnc://localhost:5900`.

Then:

1. In Anaconda, choose the disk, **create a user** (tick "Make this user administrator") and set the timezone. owlOS has no first-boot setup wizard, so this user is the only way to log in.
2. Finish the install and reboot.

The kickstart `%post` runs `bootc switch` to `ghcr.io/acchapdev/owlos:latest`, so future updates come from the registry.

## 3. Checklist

| # | Check | How | Expected |
|---|---|---|---|
| 1 | Boots to the Dux greeter | Reboot after install | The Dux login screen, not a text console or GDM |
| 2 | mango is preselected | Look at the session picker on the greeter | **Mango** |
| 3 | Log in to mango | Log in | Dux bar and shell appear |
| 4 | Default terminal | Super+Return (also Super+T on mango) | ghostty opens, with the Dux colors |
| 5 | `$TERMINAL` | In ghostty: `echo $TERMINAL` | `ghostty` |
| 6 | Firefox installed | Wait a few minutes after first boot with network, then `flatpak list --app` | `org.mozilla.firefox`. If not, `systemctl status owlos-flatpak-preinstall` |
| 7 | No Firefox RPM | `rpm -q firefox` | `package firefox is not installed` |
| 8 | Default browser | `xdg-open https://fedoraproject.org` and `xdg-settings get default-web-browser` | Opens Firefox, `org.mozilla.firefox.desktop` |
| 9 | Terminal launcher | `xdg-terminal-exec` | Opens ghostty |
| 10 | niri | Log out, pick **Niri**, log in | Dux appears, Super+Return opens ghostty |
| 11 | Hyprland | Log out, pick **Hyprland**, log in | Dux appears, Super+Return opens ghostty |
| 12 | Last session remembered | Log out after niri | The greeter now preselects **Niri** for that user |
| 13 | Image and signature | `sudo bootc status` | Booted from `ghcr.io/acchapdev/owlos:latest` |
| 14 | No extra repos left on | `dnf5 repolist` | Only Fedora repos. No duxlabs, Hyprland or Terra repos enabled |

## 4. Updates

1. Merge a change (or wait for the daily build) so that a newer `ghcr.io/acchapdev/owlos:latest` exists.
2. Run `sudo bootc upgrade`, then reboot.
3. Run `sudo bootc status`: the new image is booted and the previous one is kept for rollback (`sudo bootc rollback`).
4. Re-check items 1–4. For a Flatpak list change, also check that the app was added or removed after the reboot.

## Quick test without the installer (qcow2)

`disk_config/disk.toml` creates no user, and owlOS has no first-boot wizard, so a plain qcow2 boots to a login screen nobody can log in to. For quick local tests, add a throwaway user to a **local, uncommitted** copy of `disk.toml`:

```toml
[[customizations.user]]
name = "test"
password = "test"   # local testing only, never commit this
groups = ["wheel"]
```

Then run `just build-qcow2 ghcr.io/acchapdev/owlos latest && just run-vm-qcow2 ghcr.io/acchapdev/owlos latest` on a Linux host. The VM's web console is at http://localhost:8006.

## Known issues

- **`systemd-remount-fs.service` fails at boot** (`overlay: No changes allowed in reconfigure`). Anaconda writes a `/` entry with `ro` into `/etc/fstab`. On owlOS's composefs/overlay root that remount isn't allowed, so the unit fails. This is harmless: the system runs normally. Ignore it in `systemctl --failed`.
- **The ISO used to boot to a text console instead of the greeter.** Anaconda writes its own default target (`multi-user.target` for a text install) over the image's `graphical.target`. `disk_config/iso.toml` now runs `systemctl set-default graphical.target` in `%post`. If an install ever lands on a `login:` prompt, check `systemctl get-default`.
- **macOS Screen Sharing: Cmd doesn't work as Super in mango.** Over VNC from macOS Screen Sharing, Cmd+Enter, Cmd+T and Cmd+Q do nothing in a mango session, though Cmd works as Super in niri and Hyprland. The bindings themselves are fine: the same keys sent straight into the VM's keyboard work (`virsh send-key <vm> KEY_LEFTMETA KEY_ENTER` opens ghostty). It's how the VNC client sends Cmd, not owlOS. On real hardware the Super key works. To test mango bindings in a VM, use `virsh send-key` or a VNC client that sends Super. To act inside the session without the keyboard, use mango's IPC from a shell with the session's `MANGO_INSTANCE_SIGNATURE`: `mmsg dispatch spawn,ghostty` or `mmsg get all-clients`.
