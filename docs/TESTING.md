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

Boot the ISO in a VM with UEFI firmware, at least 4 GB RAM, a 30 GB disk and 3D acceleration on if the hypervisor has it. Then:

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
