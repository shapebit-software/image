#!/usr/bin/env bash
# Checks run inside the container image (`make check`); uses only tools the image ships.
set -uo pipefail

failed=0
check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

. /etc/os-release
check "os-release identifies ShapeBit OS" test "$ID" = shapebit
check "os-release carries the image version" test -n "${IMAGE_VERSION:-}"
check "default target is graphical" test "$(systemctl get-default)" = graphical.target
check "login screen is enabled" systemctl -q is-enabled sddm.service
login_setting() { grep -qx "$1" /usr/lib/sddm/sddm.conf.d/10-login.conf; }
check "login screen uses the login theme" login_setting Current=login
check "login theme is present" test -s /usr/share/sddm/themes/login/Main.qml
check "login screen lists systemd-homed users" login_setting MaximumUid=60513
has_login_font() { fc-list : family | grep -qx 'Instrument Sans'; }
check "login theme's font is installed" has_login_font
check "desktop session is installed" grep -qx 'TryExec=uwsm' /usr/share/wayland-sessions/desktop.desktop
only_desktop_session() { [[ $(ls /usr/share/wayland-sessions) == desktop.desktop ]] && ! compgen -G '/usr/share/xsessions/*' >/dev/null; }
check "login screen offers only the desktop session" only_desktop_session
has_command() { command -v "$1" >/dev/null; }
check "desktop session's compositor is installed" has_command start-hyprland
check "desktop shell is installed" test -s /usr/share/desktop/shell/shell.qml
check "desktop shell's runtime is installed" has_command qs
# Hyprland refuses to run as root and needs a runtime directory even to
# verify its configuration.
verify_compositor_config() {
  setpriv --reuid=nobody --regid=nobody --clear-groups sh -c \
    'XDG_RUNTIME_DIR=$(mktemp -d) exec Hyprland --verify-config --config /usr/share/desktop/compositor/hyprland.lua' >/dev/null
}
check "desktop compositor configuration is valid" verify_compositor_config
has_desktop_tools() { for tool in grim slurp wf-recorder xdg-user-dir; do has_command "$tool" || return 1; done; }
check "desktop's capture tools are installed" has_desktop_tools
check "desktop's idle handler is installed" has_command hypridle
check "desktop's portal is Hyprland's" grep -qx 'default=hyprland' /usr/share/xdg-desktop-portal/shapebit-portals.conf
check "Hyprland's portal is installed" test -s /usr/share/xdg-desktop-portal/portals/hyprland.portal
check "desktop's brightness control is installed" has_command brightnessctl
check "desktop's clipboard keeper is installed" has_command clipman
check "power profiles are enabled" systemctl -q is-enabled power-profiles-daemon.service
check "secret service is installed" has_command gnome-keyring-daemon
check "login unlocks the secret service" test -e /usr/lib64/security/pam_gnome_keyring.so
has_mono_font() { fc-list : family | grep -qx 'JetBrains Mono'; }
check "desktop's monospace font is installed" has_mono_font
no_copr_repo() { ! grep -rqs copr /etc/yum.repos.d; }
check "no third-party repository is left configured" no_copr_repo
check "sshd is enabled" systemctl -q is-enabled sshd.service
check "NetworkManager is enabled" systemctl -q is-enabled NetworkManager.service
check "systemd-homed is enabled" systemctl -q is-enabled systemd-homed.service
no_first_boot_prompt() { ! systemctl -q is-enabled systemd-homed-firstboot.service; }
check "no first-boot prompt: the installer creates the first owner" no_first_boot_prompt
check "PAM uses systemd-homed" grep -q pam_systemd_home /etc/pam.d/system-auth
initramfs_skips_var() { lsinitrd /usr/lib/modules/*/initramfs.img -f usr/lib/composefs/setup-root-conf.toml | grep -q '^mount = "none"'; }
check "initramfs leaves /var to fstab" initramfs_skips_var
check "signed systemd-boot is present" test -s /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed
has_uki() { compgen -G '/boot/EFI/Linux/*.efi' >/dev/null; }
check "UKI is present" has_uki
uki_has_pcr_policy() { grep -aq '\.pcrsig' /boot/EFI/Linux/*.efi && grep -aq '\.pcrpkey' /boot/EFI/Linux/*.efi; }
check "UKI carries a signed PCR policy" uki_has_pcr_policy
has_sb_keys() { for key in PK KEK db; do test -s "/usr/lib/bootc/install/secureboot-keys/auto/$key.auth" || return 1; done; }
check "Secure Boot keys are present" has_sb_keys

exit "$failed"
