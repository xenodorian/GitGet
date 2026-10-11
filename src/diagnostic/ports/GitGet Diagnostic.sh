#!/bin/sh
# GitGet Diagnostic
# Read-only environment report for ArkOS handhelds such as the R36S.
#
# What it does:
#   Reads system information (kernel, CPU, memory, storage, display, input,
#   libraries, tools, network configuration, PortMaster layout) and writes one
#   plain-text report file. A missing tool is recorded as unavailable and is
#   never fatal.
# What it does not do:
#   It does not install anything, change settings, edit system files, contact
#   any server, read button presses, or record Wi-Fi names, keys, MAC
#   addresses, or device serial numbers.
# Output:
#   GitGet_Device_Report.txt in the gitget-diag folder next to this script.
#   Fallbacks, in order: this script's folder, /roms, /roms2, /tmp.
#
# Test hooks (not needed for normal use):
#   GITGET_DIAG_OUT_DIR=<dir>  try this folder first for the report
#   GITGET_DIAG_NO_SCREEN=1    do not draw on the handheld screen
#   GITGET_DIAG_NO_WAIT=1      do not pause at the end

GG_VERSION="1.0.0"
REPORT_NAME="GitGet_Device_Report.txt"
SHOW_SECONDS=20

PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
LC_ALL=C
export LC_ALL
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE
PYGAME_HIDE_SUPPORT_PROMPT=1
export PYGAME_HIDE_SUPPORT_PROMPT

case "$0" in
  /*) SELF="$0" ;;
  *) SELF="$(pwd)/$0" ;;
esac
SELF_DIR=$(dirname "$SELF")
APP_DIR="$SELF_DIR/gitget-diag"

LIBDIRS="/usr/lib/aarch64-linux-gnu /lib/aarch64-linux-gnu /usr/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf /usr/lib /lib /usr/local/lib /usr/lib64 /lib64 /usr/lib/x86_64-linux-gnu /opt/*/lib /opt/system/Tools/PortMaster/libs"
PM_DIRS="/opt/system/Tools/PortMaster /opt/tools/PortMaster /roms/tools/PortMaster /roms2/tools/PortMaster /roms/ports/PortMaster /roms2/ports/PortMaster ${XDG_DATA_HOME:-/nonexistent}/PortMaster"

PART=""
NEW=""
OUT_DIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

TMO=""
TMO_LONG=""
if have timeout; then
  if timeout 1 true >/dev/null 2>&1; then
    TMO="timeout 5"
    TMO_LONG="timeout 25"
  elif timeout -t 1 true >/dev/null 2>&1; then
    TMO="timeout -t 5"
    TMO_LONG="timeout -t 25"
  fi
fi

hdr() { printf '\n==== %s ====\n' "$1"; }
note() { printf '%s\n' "$*"; }
kv() { printf '%-34s %s\n' "$1" "$2"; }

# run MAXLINES command [args...]: bounded, timed, stdin closed.
run() {
  _n="$1"
  shift
  if ! have "$1"; then
    printf '[unavailable: %s]\n' "$1"
    return 0
  fi
  ( $TMO "$@" ) </dev/null 2>&1 | head -n "$_n" | cut -c1-240
}

# rf FILE [MAXLINES]: print the start of a readable file.
rf() {
  _f="$1"
  _n="${2:-60}"
  if [ -r "$_f" ]; then
    ( $TMO cat "$_f" ) </dev/null 2>/dev/null | tr '\000' ' ' | head -n "$_n" | cut -c1-240
  else
    printf '[unavailable: %s]\n' "$_f"
  fi
}

# rv FILE: first line of a file, or n/a.
rv() {
  if [ -r "$1" ]; then
    ( $TMO head -n 1 "$1" ) </dev/null 2>/dev/null | tr '\000' ' ' | cut -c1-200
  else
    printf 'n/a'
  fi
}

# elf_info FILE: word size and CPU type from the ELF header.
elf_info() {
  _ef="$1"
  if [ -z "$_ef" ] || [ ! -r "$_ef" ]; then
    printf 'n/a'
    return 0
  fi
  _magic=$(od -An -tx1 -N4 "$_ef" 2>/dev/null | tr -d ' \n')
  if [ "$_magic" != "7f454c46" ]; then
    printf 'not an ELF file'
    return 0
  fi
  _cls=$(od -An -tu1 -j4 -N1 "$_ef" 2>/dev/null | tr -d ' \n')
  _mach=$(od -An -tx1 -j18 -N2 "$_ef" 2>/dev/null | tr -d ' \n')
  case "$_cls" in
    1) _c="32-bit" ;;
    2) _c="64-bit" ;;
    *) _c="class-$_cls" ;;
  esac
  case "$_mach" in
    b700) _m="aarch64" ;;
    2800) _m="arm" ;;
    3e00) _m="x86_64" ;;
    0300) _m="x86" ;;
    *) _m="machine-$_mach" ;;
  esac
  printf '%s %s' "$_c" "$_m"
}

# dirinfo DIR: existence, writability (permission bits only), free space.
dirinfo() {
  _d="$1"
  if [ ! -d "$_d" ]; then
    printf '%-30s absent\n' "$_d"
    return 0
  fi
  _w=no
  [ -w "$_d" ] && _w=yes
  _line=$(df -Pk "$_d" 2>/dev/null | tail -n 1)
  set -- $_line
  _mp="${6:-n/a}"
  _avail="${4:-n/a}"
  _ft=n/a
  if [ -r /proc/mounts ]; then
    while read -r _dev _mnt _typ _rest; do
      [ "$_mnt" = "$_mp" ] && _ft="$_typ"
    done < /proc/mounts
  fi
  printf '%-30s present writable=%s free_kb=%s mount=%s fstype=%s\n' "$_d" "$_w" "$_avail" "$_mp" "$_ft"
}

# first_lib PREFIX: first shared library whose file name starts with PREFIX.
first_lib() {
  for _d in $LIBDIRS; do
    for _f in $_d/$1*; do
      if [ -e "$_f" ]; then
        printf '%s' "$_f"
        return 0
      fi
    done
  done
  printf 'not found'
}

first_pm_dir() {
  for _d in $PM_DIRS; do
    if [ -d "$_d" ]; then
      printf '%s' "$_d"
      return 0
    fi
  done
  printf 'not found'
}

# ---------------------------------------------------------------------------
# Screen (best effort; failure to draw is never fatal)
# ---------------------------------------------------------------------------
screen_clear() {
  [ "${GITGET_DIAG_NO_SCREEN:-0}" = "1" ] && return 0
  [ -w /dev/tty1 ] || return 0
  printf '\033c' > /dev/tty1 2>/dev/null
  return 0
}

screen_msg() {
  [ "${GITGET_DIAG_NO_SCREEN:-0}" = "1" ] && return 0
  [ -w /dev/tty1 ] || return 0
  for _line in "$@"; do
    printf '%s\n' "$_line" > /dev/tty1 2>/dev/null
  done
  return 0
}

fold_path() {
  if have fold; then
    printf '%s\n' "$1" | fold -w 38
  else
    printf '%s\n' "$1"
  fi
}

# ---------------------------------------------------------------------------
# Report body
# ---------------------------------------------------------------------------
collect() {
  hdr "1. REPORT INFO"
  note "Tool: GitGet Diagnostic $GG_VERSION"
  note "Date (device clock, UTC): $(date -u '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo n/a)"
  note "Script location: $SELF"
  note "Running as: uid=$(id -u 2>/dev/null) user=$(id -un 2>/dev/null)"
  note "Interpreter: $(readlink "/proc/$$/exe" 2>/dev/null || echo unknown)"
  note "Command timeout helper: ${TMO:-none}"
  note "This report was produced read-only. No network request was made, nothing was installed, and no settings were changed."

  hdr "2. OS AND KERNEL"
  run 2 uname -a
  rf /proc/version 2
  note "--- Kernel command line"
  rf /proc/cmdline 3
  note "--- /etc/os-release"
  rf /etc/os-release 20
  note "--- Release or version files in /etc"
  ls /etc 2>/dev/null | grep -i -E 'ark|release|version|issue|lsb' | head -n 20
  for _f in /etc/issue /etc/lsb-release /etc/debian_version; do
    if [ -r "$_f" ]; then
      note "--- $_f"
      rf "$_f" 6
    fi
  done
  note "--- Package architecture (dpkg)"
  run 1 dpkg --print-architecture
  run 5 dpkg --print-foreign-architectures
  note "--- Selected installed packages (dpkg)"
  if have dpkg-query; then
    dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' 2>/dev/null </dev/null | grep -i -E '^(libsdl|sdl|libegl|libgles|libgl1|libmali|libgbm|libdrm|libcurl|curl |wget |openssl |libssl|ca-certificates|python3 |python3\.|python3-|libpython|lua|libasound|alsa|libinput|libudev|libts|libwayland|libfreetype|libpng|zlib1g|libc6|libstdc|libgcc|network-manager|wpasupplicant|iw |iproute|rfkill|unzip |zip )' | head -n 150
  else
    note "[unavailable: dpkg-query]"
  fi

  hdr "3. BOARD AND DEVICE TREE"
  for _f in /proc/device-tree/model /proc/device-tree/compatible /sys/firmware/devicetree/base/model /sys/firmware/devicetree/base/compatible; do
    if [ -r "$_f" ]; then
      printf '%s: ' "$_f"
      ( $TMO cat "$_f" ) </dev/null 2>/dev/null | tr '\000' ' ' | cut -c1-240
      printf '\n'
    fi
  done
  note "--- /proc/cpuinfo hardware lines (serial numbers are skipped)"
  grep -i -E '^(hardware|model|machine)[[:space:]]*:' /proc/cpuinfo 2>/dev/null | sort -u | head -n 5

  hdr "4. CPU AND ARCHITECTURE"
  kv "Kernel machine (uname -m)" "$(uname -m 2>/dev/null)"
  kv "getconf LONG_BIT" "$(getconf LONG_BIT 2>/dev/null || echo n/a)"
  kv "Logical CPUs" "$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
  kv "CPUs online" "$(rv /sys/devices/system/cpu/online)"
  note "--- /proc/cpuinfo (selected fields)"
  grep -i -E '^(model name|cpu implementer|cpu architecture|cpu variant|cpu part|cpu revision|features|flags)[[:space:]]*:' /proc/cpuinfo 2>/dev/null | sort -u | head -n 20 | cut -c1-400
  note "--- Userspace word size and CPU type from ELF headers"
  kv "/bin/sh" "$(elf_info /bin/sh)"
  kv "$(command -v ls 2>/dev/null)" "$(elf_info "$(command -v ls 2>/dev/null)")"
  for _c in python3 curl wget; do
    _p=$(command -v "$_c" 2>/dev/null)
    [ -n "$_p" ] && kv "$_p" "$(elf_info "$_p")"
  done
  note "--- C library and dynamic linker"
  ls -d /lib/ld-* /lib64/ld-* /lib/*/ld-* /usr/lib/*/ld-* 2>/dev/null | head -n 8
  run 1 getconf GNU_LIBC_VERSION
  if have ldd; then
    ( $TMO ldd --version ) </dev/null 2>&1 | head -n 1 | cut -c1-200
  fi
  if ls /lib/ld-musl-* >/dev/null 2>&1; then
    note "musl dynamic linker present"
  fi
  note "--- CPU frequency and governor"
  for _c in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$_c/cpufreq" ] || continue
    printf '%s cur=%s min=%s max=%s governor=%s\n' "$(basename "$_c")" "$(rv "$_c/cpufreq/scaling_cur_freq")" "$(rv "$_c/cpufreq/cpuinfo_min_freq")" "$(rv "$_c/cpufreq/cpuinfo_max_freq")" "$(rv "$_c/cpufreq/scaling_governor")"
  done | head -n 8
  note "--- Temperatures (millidegrees C)"
  for _t in /sys/class/thermal/thermal_zone[0-9]*; do
    [ -d "$_t" ] || continue
    printf '%s type=%s temp=%s\n' "$(basename "$_t")" "$(rv "$_t/type")" "$(rv "$_t/temp")"
  done | head -n 6

  hdr "5. MEMORY AND LIMITS"
  grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|CmaTotal|CmaFree|Shmem):' /proc/meminfo 2>/dev/null
  rf /proc/swaps 5
  rf /proc/loadavg 1
  run 2 uptime
  note "--- Shell limits"
  ( ulimit -a ) 2>&1 | head -n 20

  hdr "6. STORAGE AND WRITABLE LOCATIONS"
  run 40 df -h
  note "--- Mounts (options that could hold credentials are redacted)"
  if [ -r /proc/mounts ]; then
    ( $TMO cat /proc/mounts ) </dev/null 2>/dev/null | sed -e 's/password=[^, ]*/password=REDACTED/g' -e 's/pass=[^, ]*/pass=REDACTED/g' -e 's/credentials=[^, ]*/credentials=REDACTED/g' -e 's/username=[^, ]*/username=REDACTED/g' -e 's/user=[^, ]*/user=REDACTED/g' | cut -c1-240 | head -n 60
  else
    note "[unavailable: /proc/mounts]"
  fi
  note "--- Partitions"
  rf /proc/partitions 30
  note "--- Block device nodes"
  ls -l /dev/mmcblk* 2>/dev/null | head -n 20
  note "--- Candidate locations (writable reflects permission bits only; nothing was written to test)"
  for _d in /roms /roms2 /roms/ports /roms2/ports /roms/tools /roms2/tools /storage /home/ark /opt/system/Tools /tmp /var/tmp "$SELF_DIR" "$APP_DIR"; do
    dirinfo "$_d"
  done

  hdr "7. DISPLAY AND GPU"
  for _fb in /sys/class/graphics/fb[0-9]*; do
    [ -d "$_fb" ] || continue
    printf '%s name=%s size=%s bpp=%s stride=%s rotate=%s\n' "$_fb" "$(rv "$_fb/name")" "$(rv "$_fb/virtual_size")" "$(rv "$_fb/bits_per_pixel")" "$(rv "$_fb/stride")" "$(rv "$_fb/rotate")"
    rf "$_fb/modes" 4
  done
  note "--- Device nodes"
  ls -l /dev/fb* /dev/dri/* /dev/mali* /dev/galcore /dev/ion /dev/tty1 2>/dev/null | head -n 30
  note "--- fbset"
  run 12 fbset -s
  note "--- DRM connectors"
  for _c in /sys/class/drm/card[0-9]*-*; do
    [ -d "$_c" ] || continue
    printf '%s status=%s enabled=%s\n' "$_c" "$(rv "$_c/status")" "$(rv "$_c/enabled")"
    rf "$_c/modes" 4
  done
  for _c in /sys/class/drm/card[0-9]; do
    [ -e "$_c/device/driver" ] && printf '%s driver=%s\n' "$_c" "$(basename "$(readlink "$_c/device/driver")")"
  done
  note "--- GPU frequency scaling"
  for _g in /sys/class/devfreq/*; do
    [ -d "$_g" ] || continue
    printf '%s cur=%s governor=%s\n' "$(basename "$_g")" "$(rv "$_g/cur_freq")" "$(rv "$_g/governor")"
  done | head -n 10
  note "--- GPU related kernel modules"
  if have lsmod; then
    lsmod 2>/dev/null | grep -i -E 'mali|panfrost|lima|drm|rockchip|gpu' | head -n 15
  else
    note "[unavailable: lsmod]"
  fi

  hdr "8. INPUT DEVICES (names and capabilities only; no button presses are read)"
  if [ -r /proc/bus/input/devices ]; then
    ( $TMO cat /proc/bus/input/devices ) </dev/null 2>/dev/null | grep -v -E '^(U|P): ' | cut -c1-240 | head -n 150
  else
    note "[unavailable: /proc/bus/input/devices]"
  fi
  note "--- /dev/input"
  ls -l /dev/input/ 2>/dev/null | head -n 40
  note "--- Joystick nodes"
  for _j in /sys/class/input/js[0-9]*; do
    [ -e "$_j" ] && printf '%s name=%s\n' "$(basename "$_j")" "$(rv "$_j/device/name")"
  done
  note "--- uinput (needed by controller to keyboard mapping tools)"
  ls -l /dev/uinput /dev/input/uinput 2>/dev/null
  note "--- EmulationStation input configuration"
  rf /etc/emulationstation/es_input.cfg 60

  hdr "9. AUDIO AND POWER"
  rf /proc/asound/cards 12
  ls /dev/snd 2>/dev/null | head -n 20
  run 15 aplay -l
  note "--- Power supplies"
  for _p in /sys/class/power_supply/*; do
    [ -d "$_p" ] || continue
    printf '%s type=%s status=%s capacity=%s\n' "$(basename "$_p")" "$(rv "$_p/type")" "$(rv "$_p/status")" "$(rv "$_p/capacity")"
  done | head -n 8

  hdr "10. COMMAND-LINE TOOLS AND RUNTIMES"
  for _c in sh bash dash busybox sed awk grep find xargs sort uniq cut tr tee head tail od xxd dd cat ls cp mv rm mkdir chmod mktemp date sleep timeout stty setfont fold file ldd readelf objdump strings ldconfig dpkg python python3 perl lua luajit node ruby java gcc cc make cmake git curl wget openssl unzip zip tar gzip xz sha256sum md5sum jq dialog whiptail evtest fbset aplay amixer ip ifconfig iw iwconfig rfkill nmcli wpa_cli wpa_supplicant lsusb lsmod modprobe systemctl sudo; do
    _p=$(command -v "$_c" 2>/dev/null)
    if [ -n "$_p" ]; then
      printf '%-14s %s\n' "$_c" "$_p"
    else
      printf '%-14s missing\n' "$_c"
    fi
  done
  note "--- Versions"
  for _c in python python3 lua luajit node ruby gcc make git curl wget openssl jq tar busybox; do
    have "$_c" || continue
    case "$_c" in
      python|python3|lua|luajit|node) _a="-v" ;;
      *) _a="--version" ;;
    esac
    case "$_c" in
      python|python3) _a="-V" ;;
      busybox) _a="" ;;
      openssl) _a="version" ;;
    esac
    printf '%-10s ' "$_c"
    ( $TMO "$_c" $_a ) </dev/null 2>&1 | head -n 1 | cut -c1-160
  done
  if have java; then
    printf '%-10s ' java
    ( $TMO java -version ) </dev/null 2>&1 | head -n 1 | cut -c1-160
  fi
  if have perl; then
    printf '%-10s ' perl
    ( $TMO perl -e 'print $], "\n"' ) </dev/null 2>&1 | head -n 1
  fi
  note "--- Python modules and TLS (offline checks only)"
  if have python3; then
    ( $TMO_LONG python3 -c '
import sys, importlib
sys.dont_write_bytecode = True
print("python", sys.version.replace("\n", " ")[:100])
print("executable", sys.executable, "pointer-bits", 64 if sys.maxsize > 2**32 else 32)
for m in ("ssl", "json", "urllib.request", "http.client", "zipfile", "hashlib", "sqlite3", "ctypes", "curses", "tkinter", "pygame", "sdl2", "PIL", "requests", "urllib3", "certifi", "numpy"):
    try:
        importlib.import_module(m)
        print(m + ": ok")
    except Exception as e:
        print(m + ": missing (" + type(e).__name__ + ")")
try:
    import ssl
    print("openssl", ssl.OPENSSL_VERSION)
    c = ssl.create_default_context()
    print("default CA store", c.cert_store_stats())
    print("verify paths", ssl.get_default_verify_paths())
except Exception as e:
    print("ssl check failed", type(e).__name__)
' ) </dev/null 2>&1 | head -n 40 | cut -c1-240
  else
    note "[unavailable: python3]"
  fi

  hdr "11. LIBRARIES (SDL, GL, TLS, CURL, PYTHON)"
  note "Search folders: $LIBDIRS"
  for _pat in libSDL2-2 libSDL2.so libSDL2_image libSDL2_ttf libSDL2_mixer libSDL2_net libSDL- libEGL libGLESv2 libGLESv1 libGL.so libGLdispatch libmali libgbm libdrm libwayland libinput libudev libcurl libssl libcrypto libz.so libpng libjpeg libfreetype libasound libpulse libts libpython liblua libluajit libgnutls libmbedtls libffi libstdc++ libgcc_s libm.so libpthread libdl; do
    _found=""
    for _d in $LIBDIRS; do
      for _f in $_d/$_pat*; do
        [ -e "$_f" ] && _found="$_found $_f"
      done
    done
    if [ -n "$_found" ]; then
      printf '%s:\n' "$_pat"
      ls -l $_found 2>/dev/null | cut -c1-200 | head -n 6
    else
      printf '%s: not found\n' "$_pat"
    fi
  done
  note "--- ldconfig cache (selected)"
  if have ldconfig; then
    ldconfig -p 2>/dev/null | grep -i -E 'SDL|EGL|GLES|mali|gbm|drm|curl|ssl|crypto' | head -n 80 | cut -c1-200
  else
    note "[unavailable: ldconfig]"
  fi
  note "--- sdl2-config and pkg-config"
  run 1 sdl2-config --version
  run 3 pkg-config --list-all

  hdr "12. LIBRARIES USED BY SYSTEM PROGRAMS"
  for _b in /usr/bin/emulationstation/emulationstation /usr/bin/emulationstation /opt/retroarch/bin/retroarch /usr/bin/retroarch; do
    if [ -x "$_b" ] && [ ! -d "$_b" ]; then
      note "--- $_b ($(elf_info "$_b"))"
      run 45 ldd "$_b"
    fi
  done
  for _c in python3 curl; do
    _p=$(command -v "$_c" 2>/dev/null)
    if [ -n "$_p" ]; then
      note "--- $_p ($(elf_info "$_p"))"
      run 30 ldd "$_p"
    fi
  done

  hdr "13. PORTMASTER AND PORTS LAYOUT"
  note "Candidate PortMaster folders: $PM_DIRS"
  for _cf in $PM_DIRS; do
    [ -d "$_cf" ] || continue
    note "--- $_cf"
    ls -A "$_cf" 2>/dev/null | head -n 60
    for _f in control.txt device_info.txt gptokeyb gamecontrollerdb.txt mapper.txt version; do
      [ -e "$_cf/$_f" ] && ls -l "$_cf/$_f" 2>/dev/null | cut -c1-200
    done
    [ -f "$_cf/gptokeyb" ] && kv "gptokeyb binary" "$(elf_info "$_cf/gptokeyb")"
    if [ -r "$_cf/version" ]; then
      note "version file:"
      rf "$_cf/version" 3
    fi
    if [ -r "$_cf/device_info.txt" ]; then
      note "device_info.txt (first lines):"
      rf "$_cf/device_info.txt" 60
    fi
    if [ -r "$_cf/control.txt" ]; then
      note "control.txt lines naming key variables (the file was not run):"
      grep -n -E 'ESUDO|SDL_GAMECONTROLLERCONFIG|DEVICE_ARCH|CFW_NAME|directory=|param_device' "$_cf/control.txt" 2>/dev/null | head -n 40 | cut -c1-200
    fi
    if [ -d "$_cf/runtimes" ]; then
      note "runtimes:"
      ls -l "$_cf/runtimes" 2>/dev/null | head -n 40 | cut -c1-200
    fi
    if [ -d "$_cf/libs" ]; then
      note "libs:"
      ls -l "$_cf/libs" 2>/dev/null | head -n 40 | cut -c1-200
    fi
  done
  note "--- Installed ports (names only)"
  for _pd in /roms/ports /roms2/ports; do
    if [ -d "$_pd" ]; then
      note "$_pd:"
      ls -1 "$_pd" 2>/dev/null | head -n 100
    fi
  done
  note "--- /opt/system and /opt/system/Tools (names only)"
  ls -1 /opt/system 2>/dev/null | head -n 40
  ls -1 /opt/system/Tools 2>/dev/null | head -n 40

  hdr "14. NETWORK, TLS AND CLOCK (local settings only)"
  note "--- Interfaces (no addresses recorded)"
  for _i in /sys/class/net/*; do
    [ -e "$_i" ] || continue
    printf '%s state=%s type=%s driver=%s wireless=%s\n' "$(basename "$_i")" "$(rv "$_i/operstate")" "$(rv "$_i/type")" "$(basename "$(readlink "$_i/device/driver" 2>/dev/null)" 2>/dev/null)" "$([ -d "$_i/wireless" ] && echo yes || echo no)"
  done | head -n 20
  if have ip; then
    kv "IPv4 addresses assigned" "$(ip -4 -o addr show 2>/dev/null | grep -v ' lo ' | wc -l | tr -d ' ')"
    kv "Default routes" "$(ip route 2>/dev/null | grep -c '^default')"
  else
    note "[unavailable: ip]"
  fi
  kv "DNS servers configured" "$(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null)"
  note "--- Wireless statistics (interface names only)"
  rf /proc/net/wireless 6
  note "--- rfkill"
  run 10 rfkill list
  note "--- Network related kernel modules"
  if have lsmod; then
    lsmod 2>/dev/null | grep -i -E '8188|8723|8821|rtl|brcm|mt76|ath|wlan|cfg80211|bluetooth|usbnet|r8152' | head -n 20
  fi
  note "--- USB devices"
  run 20 lsusb
  note "--- Network management programs (presence only)"
  for _c in nmcli wpa_cli wpa_supplicant iw iwconfig connmanctl; do
    if have "$_c"; then
      printf '%-16s present\n' "$_c"
    else
      printf '%-16s missing\n' "$_c"
    fi
  done
  note "--- HTTP clients and TLS tools"
  if have curl; then
    ( $TMO curl --version ) </dev/null 2>&1 | head -n 3 | cut -c1-240
  else
    note "[unavailable: curl]"
  fi
  if have wget; then
    ( $TMO wget --version ) </dev/null 2>&1 | head -n 2 | cut -c1-240
  else
    note "[unavailable: wget]"
  fi
  run 2 openssl version
  run 2 openssl version -d
  note "--- Certificate authority locations"
  for _f in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/pki/tls/certs/ca-bundle.crt /usr/share/ca-certificates /etc/ssl/certs; do
    if [ -e "$_f" ]; then
      if [ -d "$_f" ]; then
        printf '%s directory entries=%s\n' "$_f" "$(ls -1 "$_f" 2>/dev/null | wc -l | tr -d ' ')"
      else
        ls -l "$_f" 2>/dev/null | cut -c1-200
      fi
    else
      printf '%s missing\n' "$_f"
    fi
  done
  note "--- Clock"
  note "date: $(date 2>/dev/null)"
  _y=$(date +%Y 2>/dev/null)
  case "$_y" in
    ''|*[!0-9]*) note "Clock year could not be read." ;;
    *)
      if [ "$_y" -lt 2025 ]; then
        note "WARNING: the clock year is $_y. HTTPS to GitHub will fail until the time is correct."
      else
        note "Clock year $_y looks plausible."
      fi
      ;;
  esac
  ls /sys/class/rtc 2>/dev/null | head -n 4

  hdr "15. PROCESSES AND ENVIRONMENT"
  note "--- Running program names (counts)"
  if have ps; then
    ps -eo comm= 2>/dev/null | sort | uniq -c | sort -rn | head -n 30
  fi
  note "--- Running services"
  run 30 systemctl list-units --type=service --state=running --no-pager --plain
  note "--- Selected environment variables (a fixed list; nothing else is recorded)"
  for _v in PATH LD_LIBRARY_PATH LD_PRELOAD HOME USER LOGNAME SHELL TERM LANG TZ DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_DATA_HOME XDG_CONFIG_HOME SDL_GAMECONTROLLERCONFIG_FILE SDL_VIDEODRIVER SDL_AUDIODRIVER SDL_NOMOUSE SDL_VIDEO_GL_DRIVER SDL_VIDEO_EGL_DRIVER ESUDO controlfolder CFW_NAME DEVICE_ARCH directory; do
    eval "_val=\${$_v-__unset__}"
    if [ "$_val" = "__unset__" ]; then
      printf '%s=(unset)\n' "$_v" | cut -c1-240
    else
      printf '%s=%s\n' "$_v" "$_val" | cut -c1-240
    fi
  done

  hdr "END OF REPORT"
  note "Generated by GitGet Diagnostic $GG_VERSION"
}

# ---------------------------------------------------------------------------
# Summary placed at the top of the report
# ---------------------------------------------------------------------------
summary() {
  note "GITGET DEVICE REPORT"
  note "Tool version: $GG_VERSION"
  note "Generated (device clock, UTC): $(date -u '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo n/a)"
  note ""
  note "KEY FINDINGS (each line is derived from the evidence further down)"
  kv "Board model" "$(tr '\000' ' ' < /proc/device-tree/model 2>/dev/null | cut -c1-120)"
  kv "Kernel machine (uname -m)" "$(uname -m 2>/dev/null)"
  kv "Userspace (/bin/sh ELF header)" "$(elf_info /bin/sh)"
  kv "dpkg architecture" "$(dpkg --print-architecture 2>/dev/null || echo n/a)"
  kv "dpkg foreign architectures" "$(dpkg --print-foreign-architectures 2>/dev/null | tr '\n' ' ')"
  kv "glibc version" "$(getconf GNU_LIBC_VERSION 2>/dev/null || echo 'unknown or not glibc')"
  kv "Logical CPUs" "$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
  _kb=$(sed -n 's/^MemTotal:[[:space:]]*\([0-9][0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)
  if [ -n "$_kb" ]; then
    kv "Total RAM (MB)" "$((_kb / 1024))"
  else
    kv "Total RAM (MB)" "n/a"
  fi
  kv "Framebuffer fb0 size" "$(rv /sys/class/graphics/fb0/virtual_size) at $(rv /sys/class/graphics/fb0/bits_per_pixel) bpp"
  _conn=""
  for _c in /sys/class/drm/card[0-9]*-*; do
    [ -d "$_c" ] || continue
    [ "$(rv "$_c/status")" = "connected" ] && _conn="$_conn $(basename "$_c")"
  done
  kv "DRM connectors connected" "${_conn:-none seen}"
  if have python3; then
    kv "python3" "$( ( $TMO python3 -V ) </dev/null 2>&1 | head -n 1)"
    if ( $TMO_LONG python3 -c 'import ssl' ) </dev/null >/dev/null 2>&1; then
      kv "python3 ssl module" "ok"
    else
      kv "python3 ssl module" "missing"
    fi
  else
    kv "python3" "missing"
  fi
  kv "SDL2 library" "$(first_lib libSDL2-2)"
  kv "EGL library" "$(first_lib libEGL)"
  kv "GLES2 library" "$(first_lib libGLESv2)"
  kv "libcurl" "$(first_lib libcurl)"
  kv "libssl" "$(first_lib libssl)"
  for _c in curl wget openssl; do
    if have "$_c"; then
      kv "$_c" "present: $(command -v "$_c")"
    else
      kv "$_c" "missing"
    fi
  done
  _ca="none found"
  for _f in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/pki/tls/certs/ca-bundle.crt; do
    if [ -s "$_f" ]; then
      _ca="$_f"
      break
    fi
  done
  kv "CA certificate bundle" "$_ca"
  kv "Clock year" "$(date +%Y 2>/dev/null)"
  kv "PortMaster folder" "$(first_pm_dir)"
  for _d in /roms /roms2; do
    if [ -d "$_d" ]; then
      _w=no
      [ -w "$_d" ] && _w=yes
      kv "$_d" "present, writable=$_w"
    else
      kv "$_d" "absent"
    fi
  done
  _wl=no
  for _i in /sys/class/net/*; do
    [ -d "$_i/wireless" ] && _wl=yes
  done
  kv "Wireless interface present" "$_wl"
  kv "Joystick device nodes" "$(ls /dev/input/js* 2>/dev/null | wc -l | tr -d ' ')"
  if [ -e /dev/uinput ] || [ -e /dev/input/uinput ]; then
    kv "uinput" "present"
  else
    kv "uinput" "absent"
  fi
  kv "Sound cards" "$(grep -c '^ *[0-9]' /proc/asound/cards 2>/dev/null)"
  note ""
  note "Details follow. Sections are numbered 1 to 15."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
cleanup_tmp() {
  [ -n "$NEW" ] && rm -f "$NEW" 2>/dev/null
  return 0
}
trap cleanup_tmp EXIT
trap '[ -n "$PART" ] && rm -f "$PART"; exit 1' INT TERM HUP

screen_clear
screen_msg "GitGet Diagnostic $GG_VERSION" "" "Reading device information." "This is read-only." "Please wait up to 60 seconds."

for _dir in "${GITGET_DIAG_OUT_DIR:-}" "$APP_DIR" "$SELF_DIR" /roms /roms2 /tmp; do
  [ -n "$_dir" ] || continue
  [ -d "$_dir" ] || continue
  if ( : > "$_dir/$REPORT_NAME.part" ) 2>/dev/null; then
    OUT_DIR="$_dir"
    PART="$_dir/$REPORT_NAME.part"
    break
  fi
done

if [ -z "$OUT_DIR" ]; then
  screen_clear
  screen_msg "GitGet Diagnostic: FAILED" "" "Could not write the report to any" "folder. Nothing was changed." "" "Closing in $SHOW_SECONDS seconds."
  [ "${GITGET_DIAG_NO_WAIT:-0}" = "1" ] || sleep "$SHOW_SECONDS"
  screen_clear
  exit 1
fi

collect >> "$PART" 2>&1

FINAL="$OUT_DIR/$REPORT_NAME"
NEW="$FINAL.new"
if { summary; printf '\n'; cat "$PART"; } > "$NEW" 2>/dev/null && mv -f "$NEW" "$FINAL" 2>/dev/null; then
  rm -f "$PART" 2>/dev/null
  PART=""
  screen_clear
  screen_msg "GitGet Diagnostic: DONE" "" "Report saved to:"
  _shown=$(fold_path "$FINAL")
  screen_msg "$_shown" "" "Shut down the handheld normally," "then upload that file to the chat." "" "This screen closes in $SHOW_SECONDS seconds."
  [ "${GITGET_DIAG_NO_WAIT:-0}" = "1" ] || sleep "$SHOW_SECONDS"
  screen_clear
  exit 0
fi

screen_clear
screen_msg "GitGet Diagnostic: FAILED" "" "The report could not be finished." "A partial file may be here:" "$(fold_path "$PART")" "" "Closing in $SHOW_SECONDS seconds."
[ "${GITGET_DIAG_NO_WAIT:-0}" = "1" ] || sleep "$SHOW_SECONDS"
screen_clear
exit 1
