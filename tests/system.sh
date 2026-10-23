#!/usr/bin/env bash
# Checks run inside the booted system (`make test`); uses only tools the image ships.
# OWNER_NAME is the first owner that the installer created; LOCALE,
# KEYBOARD_LAYOUT, and TIME_ZONE are the settings it was given.
set -uo pipefail
: "${OWNER_NAME:?}" "${LOCALE:?}" "${KEYBOARD_LAYOUT:?}" "${TIME_ZONE:?}"

failed=0
check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failed=1; fi
}

if ! check "system finished booting without failed units" systemctl is-system-running --wait; then
  systemctl --failed --no-legend
fi

. /etc/os-release
check "os-release identifies ShapeBit OS" test "$ID" = shapebit
booted_by_bootc() { bootc status --format=json | jq -e '.status.booted != null' >/dev/null; }
check "booted by bootc" booted_by_bootc
check "Secure Boot is enabled" sh -c "mokutil --sb-state | grep -q 'SecureBoot enabled'"
booted_by_systemd_boot() { bootctl status 2>/dev/null | grep -Eq '^ +Product: systemd-boot '; }
check "booted by systemd-boot" booted_by_systemd_boot
check "booted from a UKI" test -e /sys/firmware/efi/efivars/StubInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
check "root is sealed by a composefs digest" grep -Eq '(^| )composefs=[0-9a-f]{128}( |$)' /proc/cmdline
check "root filesystem is Btrfs" test "$(findmnt -no FSTYPE /sysroot)" = btrfs
check "root filesystem is on the LUKS2 volume" test "$(findmnt -nvo SOURCE /sysroot)" = /dev/mapper/root
is_luks2() { cryptsetup status root | grep -Eq '^ +type: +LUKS2$'; }
check "root volume is LUKS2" is_luks2
luks_dump() { cryptsetup luksDump --dump-json-metadata /dev/disk/by-partlabel/shapebit; }
tpm2_policy() {
  luks_dump | jq -e '[.tokens[] | select(.type == "systemd-tpm2")] | length == 1 and
    (.[0]["tpm2-pcrs"] == [7]) and (.[0]["tpm2_pubkey_pcrs"] == [11])' >/dev/null
}
check "TPM2 key slot is bound to PCR 7 and signed PCR 11" tpm2_policy
has_recovery_key() { luks_dump | jq -e '[.tokens[] | select(.type == "systemd-recovery")] | length == 1' >/dev/null; }
check "recovery key is enrolled" has_recovery_key
only_tpm2_and_recovery() { luks_dump | jq -e '.keyslots | length == 2' >/dev/null; }
check "installation key is gone; no other key slots" only_tpm2_and_recovery
unlocked_by_tpm2() {
  local log
  log=$(journalctl -b -o cat -u systemd-cryptsetup@root.service)
  grep -q 'TPM2 token unlocks volume' <<<"$log" && ! grep -q 'falling back' <<<"$log"
}
check "unlocked by the TPM" unlocked_by_tpm2
machine_id_saved() { test -s /etc/machine-id && ! grep -q uninitialized /etc/machine-id && ! findmnt /etc/machine-id >/dev/null; }
check "machine ID is saved, not temporary" machine_id_saved
disk=/dev/$(lsblk -ndo PKNAME /dev/disk/by-partlabel/shapebit)
root_partition_fills_disk() {
  local free
  free=$(sfdisk --list-free "$disk" | sed -n 's/^Unpartitioned space .*, \([0-9]*\) bytes,.*/\1/p')
  test "$free" -lt $((2 * 1024 * 1024))
}
check "root partition fills the disk" root_partition_fills_disk
luks_fills_partition() {
  local offset size
  offset=$(cryptsetup status root | awk '$1 == "offset:" { print $2 }')
  size=$(cryptsetup status root | awk '$1 == "size:" { print $2 }')
  test $((offset + size)) -eq "$(blockdev --getsz /dev/disk/by-partlabel/shapebit)"
}
check "LUKS2 volume fills the root partition" luks_fills_partition
btrfs_fills_volume() {
  test "$(btrfs filesystem show --raw /sysroot | awk '$1 == "devid" { print $4 }')" -eq "$(blockdev --getsize64 /dev/mapper/root)"
}
check "Btrfs fills the LUKS2 volume" btrfs_fills_volume
check "@base is mounted at /sysroot" test "$(findmnt -no FSROOT /sysroot)" = /@base
check "@machine is mounted at /var" test "$(findmnt -no FSROOT /var)" = /@machine
check "@people is mounted at /var/home" test "$(findmnt -no FSROOT /var/home)" = /@people
has_recovery() { btrfs subvolume list /sysroot | grep -Eq ' path @recovery$'; }
check "@recovery subvolume exists" has_recovery
check "serial console karg is active" grep -q 'console=ttyS0' /proc/cmdline

owner_is_admin() { id -nG "$OWNER_NAME" | grep -qw wheel; }
check "first owner exists and administers the machine" owner_is_admin
owner_home_is_luks() { homectl inspect -j "$OWNER_NAME" | jq -e '[.binding[].storage] == ["luks"]' >/dev/null; }
check "first owner has a LUKS2 home" owner_home_is_luks

check "login screen is running" systemctl -q is-active sddm.service
# SDDM starts its greeter after the system reports that it is up.
greeter_runs() {
  for _ in {1..30}; do
    pgrep -u sddm -f sddm-greeter >/dev/null && return
    sleep 1
  done
  return 1
}
check "login screen shows its greeter" greeter_runs
# SDDM lists the users that enumerate through NSS, within its UID range.
owner_is_listed() {
  local uid
  uid=$(getent passwd | awk -F: -v user="$OWNER_NAME" '$1 == user { print $3 }')
  [[ -n $uid ]] && ((uid >= 1000 && uid <= 60513))
}
check "login screen lists the first owner" owner_is_listed

# A throwaway systemd-homed user shows that homes are encrypted images in @people.
# It is small, since the test is about where homes live, not how big they get.
user=shapebit-test
password=$(head -c 24 /dev/urandom | base64)
check "homed creates a home" env NEWPASSWORD="$password" homectl create "$user" --disk-size=512M
home_binding() { homectl inspect -j "$user" | jq -e --arg image "/home/$user.home" \
  '[.binding[]] | length == 1 and .[0].storage == "luks" and .[0].imagePath == $image' >/dev/null; }
check "home is a LUKS2 image in /home" home_binding
check "home image is in @people" test "$(findmnt -no FSROOT -T "/var/home/$user.home")" = /@people
home_resolves() { getent passwd "$user" >/dev/null; }
check "home user resolves through NSS" home_resolves
check "home activates with its password" env PASSWORD="$password" homectl activate "$user"
home_mounted() { [[ $(findmnt -no FSTYPE,SOURCE "/home/$user") =~ ^btrfs\ /dev/mapper/home- ]]; }
check "active home is Btrfs on dm-crypt" home_mounted
# The login screen starts the desktop in a home: signed in automatically, since
# the home is already unlocked. The autologin setting lasts only for this check.
# An application that starts with every session, for the autostart check.
autologin=/etc/sddm.conf.d/zz-desktop-check.conf
autostart=/etc/xdg/autostart/zz-desktop-check.desktop
autostarted=/tmp/desktop-autostart-check
rm -f "$autostarted"
desktop_starts() {
  mkdir -p "${autologin%/*}"
  printf '[Autologin]\nUser=%s\nSession=desktop.desktop\n' "$user" >"$autologin"
  printf '[Desktop Entry]\nType=Application\nName=Check\nExec=touch %s\n' "$autostarted" >"$autostart"
  systemctl restart sddm.service
  for _ in {1..60}; do
    pgrep -u "$user" -x Hyprland >/dev/null && pgrep -u "$user" -x qs >/dev/null && return
    sleep 1
  done
  return 1
}
check "login screen starts the desktop in a home" desktop_starts
# The desktop's hypridle delays sleep until the screen is locked.
sleep_waits_for_lock() {
  for _ in {1..10}; do
    systemd-inhibit --list --no-legend | grep -Eq "^hypridle .* $user .* sleep .* delay" && return
    sleep 1
  done
  return 1
}
check "desktop locks the screen before sleep" sleep_waits_for_lock
uid=$(id -u "$user")
graphical_session() {
  for _ in {1..20}; do
    [[ $(systemctl --user -M "$user@" is-active graphical-session.target) == active ]] && return
    sleep 1
  done
  return 1
}
check "desktop session reaches graphical-session.target" graphical_session
autostart_ran() {
  for _ in {1..20}; do
    [[ $(stat -c %U "$autostarted" 2>/dev/null) == "$user" ]] && return
    sleep 1
  done
  return 1
}
check "desktop session starts XDG autostart applications" autostart_ran
# Services that applications reach on the session bus, started on demand.
answers() { busctl --user -M "$user@" call "$1" "$2" org.freedesktop.DBus.Peer Ping >/dev/null 2>&1; }
check "desktop session offers the secret service" answers org.freedesktop.secrets /org/freedesktop/secrets
screencast() {
  busctl --user -M "$user@" get-property org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.ScreenCast version >/dev/null 2>&1
}
check "desktop session shares the screen through the portal" screencast
# Applications in Flatpak read the window buttons through the portal.
portal_window_buttons() {
  busctl --user -M "$user@" call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings ReadOne ss org.gnome.desktop.wm.preferences button-layout 2>/dev/null |
    grep -qx 'v s ":"'
}
check "desktop session's applications show no window buttons" portal_window_buttons
# Opening and saving files, and screenshots: the portal offers them, D-Bus
# starts the shell's backend in the session, and the shell listens for its
# questions.
shell_portal() {
  local interface
  for interface in FileChooser Screenshot; do
    busctl --user -M "$user@" get-property org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
      "org.freedesktop.portal.$interface" version >/dev/null 2>&1 || return 1
  done
  answers org.freedesktop.impl.portal.desktop.shell /org/freedesktop/portal/desktop &&
    compgen -G "/run/user/$uid/desktop/portal-wayland-*.sock" >/dev/null
}
check "desktop session opens files and takes screenshots through the shell" shell_portal
# An action that needs an administrator makes the shell ask for the password
# (its "authorization" surface); the question is left unanswered.
asks_for_admin() {
  local asked=1
  setpriv --reuid="$user" --regid="$user" --init-groups env XDG_RUNTIME_DIR="/run/user/$uid" \
    hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("pkexec true")' >/dev/null
  for _ in {1..15}; do
    if setpriv --reuid="$user" --regid="$user" --init-groups env XDG_RUNTIME_DIR="/run/user/$uid" \
      hyprctl --instance 0 layers | grep -q 'namespace: authorization'; then
      asked=0
      break
    fi
    sleep 1
  done
  pkill -u "$user" -x pkexec
  return "$asked"
}
check "desktop session asks for an administrator's password" asks_for_admin
notification_server() {
  busctl --user -M "$user@" call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications GetServerInformation 2>/dev/null | grep -q '"quickshell"'
}
check "desktop session shows notifications" notification_server
keeps_copies() { pgrep -u "$user" -f "clipman store" >/dev/null; }
check "desktop session keeps copied text" keeps_copies
# Log out as the account panel does: Hyprland's exit.
logs_out() {
  setpriv --reuid="$user" --regid="$user" --init-groups env XDG_RUNTIME_DIR="/run/user/$uid" \
    hyprctl --instance 0 dispatch 'hl.dsp.exit()' >/dev/null
  for _ in {1..30}; do
    loginctl list-sessions --no-legend | awk -v user="$user" '$3 == user && $6 != "manager" { found = 1 } END { exit !found }' || return 0
    sleep 1
  done
  return 1
}
check "logging out ends the desktop session" logs_out
rm -f "$autologin" "$autostart" "$autostarted"
loginctl terminate-user "$user"
# homed is busy with the home while the session ends; it may also deactivate
# the home itself then.
home_state() { homectl inspect "$user" | awk '$1 == "State:" { print $2 }'; }
for _ in {1..30}; do
  case $(home_state) in
    inactive) break ;;
    active) homectl deactivate "$user" 2>/dev/null && break ;;
  esac
  sleep 1
done
# Restarting the login screen again may exceed its start limit.
systemctl reset-failed sddm.service
systemctl restart sddm.service
check "homed removes the home" homectl remove "$user"

# localectl and timedatectl report what systemd read from /etc.
locale_is_set() { localectl status | grep -q "System Locale: LANG=$LOCALE\$"; }
check "locale is the one given to the installer" locale_is_set
keymap_is_set() { localectl status | grep -Eq "VC Keymap: +$KEYBOARD_LAYOUT\$" && localectl status | grep -Eq "X11 Layout: +$KEYBOARD_LAYOUT\$"; }
check "keyboard layout is the one given to the installer" keymap_is_set
check "time zone is the one given to the installer" test "$(timedatectl show --property=Timezone --value)" = "$TIME_ZONE"

exit "$failed"
