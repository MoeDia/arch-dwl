#!/usr/bin/env bash
# =============================================================================
#  arch-dwl-setup.sh  -  install + wire up an Arch Linux / dwl (Wayland) desktop
#
#  Installs and sets up packages, services, and the session plumbing, and
#  themes everything in Dracula (or catppuccin/nord/tokyonight) by default.
#  Config files are only written if they don't already exist (set THEME_FORCE=1
#  to overwrite the theme-generated ones).
#
#  Run as your NORMAL user (not root), on an existing Arch install, with internet:
#      chmod +x arch-dwl-setup.sh && ./arch-dwl-setup.sh
#
#  Re-running is safe (idempotent). Everything is overridable via env vars:
#
#    SKIP=apps,docker      comma list of phases to skip. Phases:
#                          pacman paru security amd base codecs dwl visual qol
#                          fonts office apps gaming torrent theme lazyvim ai
#                          docker session services snapshots verify
#    AUR_REVIEW=0|1        0 (default) = unattended, PKGBUILDs are NOT reviewed
#                          1 = paru shows PKGBUILDs and asks (recommended if you
#                              want to read what you're building)
#    WITH_CHAOTIC=0|1      add Chaotic-AUR (3rd-party prebuilt binaries). Default 0.
#    WITH_PPFEATUREMASK=1  add amdgpu.ppfeaturemask=0xffffffff to kernel cmdline
#    WITH_XWAYLAND=1       build dwl with XWayland support
#    DWL_REF=<tag|branch>  dwl ref to build. Default: latest release tag
#    DWL_PATCHES="ipc genericgaps pertag swallow"   patches from dwl-patches
#    DWL_SRC=~/.local/src/dwl
#    KB_LAYOUT=us,ara      KB_OPTIONS=grp:alt_shift_toggle
#    TORRENT_PORT=         open this TCP/UDP port in ufw (e.g. 6881)
#    WITH_BROWSER=0        install Firefox (opt-in only; VA-API hw decode + Widevine)
#    WITH_VLC=0            also install VLC (pulls Qt; mpv already covers everything)
#    WITH_DISC_DECRYPT=0   libdvdcss + libaacs (disc-decryption libs; check your local law)
#    WITH_UNVERIFIED=0     also try splatty / nikki-cli (could not confirm they exist)
#    THEME=dracula         dracula | catppuccin | nord | tokyonight | none
#    THEME_FORCE=1         rewrite theme configs even if they already exist
#    WITH_LAZYVIM=1        clone LazyVim starter to ~/.config/nvim if absent
#    WITH_AI=1             npm i -g @anthropic-ai/claude-code + LazyVim ai extras
#    WITH_TORRENT=1        prowlarr-bin (holistic torrent search) + aria2
#    WITH_GAMING=1         steam + gamescope + gamemode + mangohud + proton-ge
#
#  Modes:
#    ./arch-dwl-setup.sh --check-packages   dry run: does every package exist, do its
#                                           dependencies resolve? (installs nothing)
#    ./arch-dwl-setup.sh --verify           run the full test suite on the live system
# =============================================================================
set -uo pipefail

: "${SKIP:=}"
: "${AUR_REVIEW:=0}"
: "${WITH_CHAOTIC:=0}"
: "${WITH_PPFEATUREMASK:=1}"
: "${WITH_XWAYLAND:=1}"
: "${DWL_REF:=}"
: "${DWL_PATCHES:=ipc genericgaps pertag swallow}"
: "${DWL_SRC:=$HOME/.local/src/dwl}"
: "${DWL_PATCH_DIR:=$HOME/.local/src/dwl-patches}"
: "${KB_LAYOUT:=us,ara}"
: "${KB_OPTIONS:=grp:alt_shift_toggle}"
: "${TORRENT_PORT:=}"
: "${WITH_BROWSER:=0}"
: "${WITH_VLC:=0}"
: "${WITH_DISC_DECRYPT:=0}"
: "${WITH_UNVERIFIED:=0}"
: "${THEME:=dracula}"
: "${THEME_FORCE:=0}"
: "${WITH_LAZYVIM:=1}"
: "${WITH_AI:=1}"
: "${WITH_TORRENT:=1}"
: "${WITH_GAMING:=1}"

# ------------------------------------------------------- package registry ----
# One place defines every package. The phases install from these arrays,
# --check-packages inspects them, and --verify tests them.
# A_* entries are 'a|b|c' groups: the first candidate that exists/installs wins.
P_SECURITY=(ufw)
P_AMD=(mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon mesa-utils vulkan-tools libva-utils amd-ucode linux-firmware lact)
P_BASE=(pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol pamixer playerctl
        polkit xdg-utils xdg-user-dirs wl-clipboard wlr-randr brightnessctl wmenu
        xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
        xorg-xwayland xcb-util-wm libnotify unzip zip 7zip jq man-db man-pages
        networkmanager network-manager-applet bluez bluez-utils blueman)
P_DWL_DEPS=(wayland wayland-protocols libinput libxkbcommon pkgconf pixman libdrm libxcb xcb-util-wm foot)
P_CODECS=(ffmpeg mpv yt-dlp libplacebo shaderc vulkan-icd-loader libva libva-utils libass mediainfo
          gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
          gst-plugin-va gst-plugin-pipewire libdvdread libdvdnav libbluray argyllcms
          dav1d x264 x265 svt-av1 libde265
          libjxl libavif libheif libwebp openjpeg2
          mkvtoolnix-cli
          opus lame flac libvorbis vorbis-tools wavpack
          gst-plugin-gtk)
P_CODECS_DISC=(libdvdcss libaacs)
P_VLC=(vlc vlc-plugins-all)
P_BROWSER=(firefox)
P_VISUAL=(waybar rofi foot mako swayosd zsh zsh-autosuggestions zsh-syntax-highlighting
          zsh-completions starship eza bat fd ripgrep zoxide fzf)
A_VISUAL=("awww|swww" "wttrbar|wttrbar-bin")
P_QOL=(udiskie udisks2 yazi poppler imagemagick cliphist grim slurp satty wf-recorder
       hyprpicker hyprpolkitagent swayidle swaylock btop
       imv chafa oxipng jpegoptim fastfetch gammastep batsignal liquidctl openrgb easyeffects
       calc zstd pigz atool gsimplecal)
A_QOL=("xdg-desktop-portal-termfilechooser|xdg-desktop-portal-termfilechooser-boydaihungst-git|xdg-desktop-portal-termfilechooser-hunkyburrito-git"
       "wlogout")
P_FONTS=(noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra ttf-jetbrains-mono-nerd
         ttf-firacode-nerd ttf-cascadia-code-nerd ttf-hack-nerd ttf-roboto-mono-nerd ttf-ubuntu-nerd
         ttf-nerd-fonts-symbols otf-font-awesome
         ttf-scheherazade-new aribb24
         nwg-look qt6ct qt5ct kvantum gtk3 gtk4 papirus-icon-theme)
A_FONTS=("ttf-amiri" "vazirmatn-fonts")
P_OFFICE=(abiword gnumeric zathura zathura-pdf-mupdf zathura-cb zathura-djvu zathura-ps
          ttf-liberation ttf-carlito ttf-caladea hunspell-en_us
          presenterm xournalpp qpdf mupdf-tools)
A_OFFICE=("zathura-epub-mupdf")
P_APPS=(neovim lazygit nodejs npm tree-sitter-cli gcc make solaar piper)
# Verified to exist in the AUR/repos when this script was written (Oct 2026):
A_APPS=("endcord|endcord-lite|endcord-git" "syncplay-nogui|syncplay"
        "superseedr-bin|superseedr" "spotatui-bin|spotatui" "clock-tui|clock-tui-bin"
        "localsend-bin|localsend")
# Names from the original guide that I could NOT confirm exist. Off by default (WITH_UNVERIFIED=1 to try).
A_UNVERIFIED=("splatty|splatty-bin|splatty-git" "nikki-cli|nikki-cli-git")
P_GAMING=(steam gamescope gamemode lib32-gamemode mangohud lib32-mangohud goverlay
          protontricks winetricks wine lib32-gnutls lib32-pipewire lib32-libpulse lib32-alsa-lib
          vkd3d lib32-vkd3d)
A_GAMING=("proton-ge-custom-bin")
P_TORRENT=(aria2)
A_TORRENT=("prowlarr-bin")
A_THEME=("dracula-gtk-theme" "dracula-cursors-git" "dracula-grub-theme-git")
P_DOCKER=(docker docker-compose docker-buildx fuse-overlayfs slirp4netns rootlesskit)
A_DOCKER=("docker-rootless-extras")
P_SESSION=(greetd greetd-tuigreet)
P_SNAP=(timeshift cronie inotify-tools)
A_SNAP=("timeshift-autosnap")

WARNINGS=()
FAILED=()
APPLIED=()
NEEDS_GRUB_REGEN=0
KEEPALIVE_PID=""

# ------------------------------------------------------------------ helpers --
log()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*"; WARNINGS+=("$*"); }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
skip() { [[ ",${SKIP}," == *",$1,"* ]]; }
run_phase() { local n="$1"; shift; if skip "$n"; then log "Skipping phase: $n"; else "$@"; fi; }

if [[ "$AUR_REVIEW" == "1" ]]; then PARU_FLAGS=(); else PARU_FLAGS=(--noconfirm --skipreview); fi

# Install via paru (handles repo + AUR). Batch first, then one-by-one so a single
# bad/missing package never aborts the whole run.
inst() {
  [[ $# -gt 0 ]] || return 0
  paru -S --needed "${PARU_FLAGS[@]}" "$@" && return 0
  warn "Batch install failed, retrying one by one: $*"
  local p
  for p in "$@"; do
    paru -S --needed "${PARU_FLAGS[@]}" "$p" || { FAILED+=("$p"); warn "FAILED: $p"; }
  done
  return 0
}

# Install the first candidate that works (for packages whose name is uncertain).
inst_any() {
  local p
  for p in "$@"; do
    if paru -S --needed "${PARU_FLAGS[@]}" "$p"; then return 0; fi
  done
  FAILED+=("one of: $*")
  warn "FAILED: none of these installed: $*"
  return 1
}

inst_group() { local -a c; IFS='|' read -ra c <<<"$1"; inst_any "${c[@]}"; }
inst_groups() { local g; for g in "$@"; do inst_group "$g"; done; return 0; }

write_root() { sudo install -Dm644 /dev/stdin "$1"; }
write_root_exec() { sudo install -Dm755 /dev/stdin "$1"; }
write_user_if_absent() {  # usage: write_user_if_absent path [mode] < content
  local f="$1" mode="${2:-644}"
  if [[ -e "$f" ]]; then cat >/dev/null; info "exists, left untouched: $f"; return 0; fi
  mkdir -p "$(dirname "$f")" && install -m "$mode" /dev/stdin "$f" && info "wrote $f"
}

keepalive() {
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 45; done ) &
  KEEPALIVE_PID=$!
}
cleanup() { [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null; return 0; }
trap cleanup EXIT

# hex -> "0.xxxx, 0.yyyy, 0.zzzz" (for dwl's float colors)
hex2rgb() {
  local c="$1" r g b
  printf -v r "%d" "0x${c:1:2}"; printf -v g "%d" "0x${c:3:2}"; printf -v b "%d" "0x${c:5:2}"
  awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN{printf "%.4f, %.4f, %.4f", r/255, g/255, b/255}'
}

# --------------------------------------------------------------- preflight ---
preflight() {
  log "Preflight"
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root (makepkg refuses root; sudo is used where needed)."
  [[ -f /etc/arch-release ]] || die "This is not Arch Linux."
  command -v sudo >/dev/null || die "sudo is missing. As root: pacman -S sudo, then add yourself to wheel."
  sudo -v || die "sudo authentication failed."
  keepalive
  # Minimal installs have no curl yet: use bash's own TCP stack first, curl if present.
  if command -v curl >/dev/null; then
    curl -fsI --max-time 10 https://archlinux.org >/dev/null 2>&1 || die "No internet connection."
  elif ! timeout 10 bash -c 'cat < /dev/null > /dev/tcp/archlinux.org/443' 2>/dev/null; then
    die "No internet connection."
  fi
  if command -v lspci >/dev/null && ! lspci 2>/dev/null | grep -qiE 'AMD/ATI|Advanced Micro Devices.*(VGA|Display)'; then
    warn "No AMD GPU detected by lspci. The AMD phase will still run; use SKIP=amd to avoid it."
  fi
  if [[ "$AUR_REVIEW" != "1" ]]; then
    exec > >(tee -a "$HOME/arch-dwl-setup.log") 2>&1
  fi
  info "user=$USER  AUR_REVIEW=$AUR_REVIEW  theme=$THEME  skip='${SKIP}'"
}

# ---------------------------------------------------------- 1. pacman/base ---
setup_chaotic() {
  grep -q '^\[chaotic-aur\]' /etc/pacman.conf && return 0
  warn "Adding Chaotic-AUR: a third-party binary repo. You are trusting its maintainers with root-level installs."
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com \
    && sudo pacman-key --lsign-key 3056513887B78AEB \
    && sudo pacman -U --noconfirm \
         'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
         'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' \
    && printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null \
    || warn "Chaotic-AUR setup failed; continuing without it."
}

phase_pacman() {
  log "Configuring pacman + full system upgrade"
  sudo cp -n /etc/pacman.conf /etc/pacman.conf.bak-dwlsetup
  sudo sed -i -e 's/^#Color$/Color/' -e 's/^#VerbosePkgLists$/VerbosePkgLists/' \
              -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
  grep -q '^ParallelDownloads' /etc/pacman.conf || sudo sed -i '/^\[options\]/a ParallelDownloads = 5' /etc/pacman.conf
  grep -q '^ILoveCandy' /etc/pacman.conf || sudo sed -i '/^Color$/a ILoveCandy' /etc/pacman.conf
  # lib32-* packages (steam, wine) need [multilib]; the original guide forgot to enable it.
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
  fi
  grep -q '^\[multilib\]' /etc/pacman.conf || die "Could not enable [multilib] in /etc/pacman.conf."
  [[ "$WITH_CHAOTIC" == "1" ]] && setup_chaotic
  sudo pacman -Syu --noconfirm || die "System upgrade failed."
  sudo pacman -S --needed --noconfirm base-devel git curl pacman-contrib || die "base-devel install failed."
  sudo systemctl enable --now paccache.timer fstrim.timer || warn "Could not enable paccache/fstrim timers."
}

phase_paru() {
  log "AUR helper (paru)"
  if command -v paru >/dev/null; then info "paru already installed"; return 0; fi
  local tmp; tmp="$(mktemp -d)"
  # paru-bin = prebuilt; avoids a long Rust compile. Swap for 'paru' if you prefer building from source.
  git clone --depth=1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" \
    && (cd "$tmp/paru-bin" && makepkg -si --noconfirm) \
    || die "Could not install paru."
  rm -rf "$tmp"
}

# ------------------------------------------------------------ 2. security ----
phase_security() {
  log "Security baseline (ufw + sysctl)"
  inst "${P_SECURITY[@]}"
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  if systemctl is-active --quiet sshd; then
    sudo ufw limit ssh && info "sshd is running: kept SSH reachable (rate-limited)"
  fi
  [[ -n "$TORRENT_PORT" ]] && sudo ufw allow "$TORRENT_PORT"
  sudo ufw --force enable
  sudo systemctl enable --now ufw.service

  # NOTE: no 'net.ipv4.ip_forward=0' on purpose - Docker (non-rootless), VPNs and
  # libvirt need forwarding. Also no unprivileged_userns restriction: it breaks
  # Chromium/Electron sandboxes, Flatpak and rootless Docker.
  write_root /etc/sysctl.d/99-hardening.conf <<'EOF'
# --- installed by arch-dwl-setup.sh ---
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
EOF
  sudo sysctl --system >/dev/null || warn "sysctl --system reported errors"
}

# ------------------------------------------------------------- bootloader ----
add_karg() {  # add_karg key=value   (idempotent; supports GRUB, systemd-boot)
  local arg="$1" key="${1%%=*}"
  if [[ -f /etc/default/grub ]] && command -v grub-mkconfig >/dev/null; then
    if grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -q "$key"; then
      info "kernel arg '$key' already present (GRUB)"; return 0
    fi
    sudo cp -n /etc/default/grub /etc/default/grub.bak-dwlsetup
    sudo sed -i -E "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/(['\"])\$/ ${arg}\\1/" /etc/default/grub
    NEEDS_GRUB_REGEN=1
    info "added '$arg' to GRUB_CMDLINE_LINUX_DEFAULT"
  elif command -v bootctl >/dev/null && bootctl is-installed >/dev/null 2>&1; then
    local esp f; esp="$(bootctl --print-esp-path 2>/dev/null)"
    for f in "$esp"/loader/entries/*.conf; do
      [[ -e "$f" && "$f" != *fallback* ]] || continue
      grep -q "$key" "$f" || { sudo sed -i -E "/^options / s|\$| ${arg}|" "$f"; info "added '$arg' to $f"; }
    done
    pacman -Q amd-ucode >/dev/null 2>&1 && info "systemd-boot: make sure entries have 'initrd /amd-ucode.img' before the main initrd"
  else
    warn "Unknown bootloader/UKI setup. Add this kernel parameter yourself: $arg"
  fi
}

# ------------------------------------------------------------------ 3. AMD ---
phase_amd() {
  log "AMD GPU stack"
  inst "${P_AMD[@]}"
  # RDNA4 needs a recent kernel + mesa + linux-firmware; the full -Syu above covers it.
  local kv; kv="$(uname -r | cut -d- -f1)"
  if [[ "$(printf '%s\n6.15\n' "$kv" | sort -V | head -1)" != "6.15" ]]; then
    warn "Running kernel $kv is older than 6.15. RDNA4 needs a newer kernel: reboot into the freshly installed one."
  fi
  pacman -Q lact >/dev/null 2>&1 && sudo systemctl enable lactd.service   # daemon for clocks, fans, undervolting
  if [[ "$WITH_PPFEATUREMASK" == "1" ]]; then add_karg "amdgpu.ppfeaturemask=0xffffffff"; fi
}

# ------------------------------------------------------ 4. base desktop bits --
phase_base() {
  log "Audio, portals, network, session basics"
  inst "${P_BASE[@]}"
  sudo systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
    || warn "Could not globally enable pipewire user units."
  # Proper network manager: NM handles ethernet/vpn; nm-applet lives in the tray.
  # (Desktop PC: ethernet only, no wifi needed - the bar shows ethernet status.)
  sudo systemctl enable --now NetworkManager.service || warn "Could not enable NetworkManager."
  # Bluetooth stack for controllers, headsets, speakers.
  sudo systemctl enable --now bluetooth.service || warn "Could not enable bluetooth.service."
  if systemctl is-active --quiet systemd-networkd && ! systemctl is-enabled --quiet NetworkManager; then
    warn "systemd-networkd is active. Decide which one you want: 'sudo systemctl disable --now systemd-networkd' after checking its configs."
  fi
  if systemctl is-active --quiet NetworkManager && ! nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q ':connected'; then
    info "no active connection yet: run 'nmtui' (or the tray icon) to connect to wifi"
  fi
  xdg-user-dirs-update 2>/dev/null || true
  # NOTE: seatd is intentionally NOT installed. On systemd Arch, wlroots/libseat talks to
  # systemd-logind (via greetd's PAM session), which already grants GPU/input access.
  # No 'video'/'input' group membership is needed for that.
}

# ---------------------------------------------------------------- 5. dwl -----
dwl_build() { ( cd "$DWL_SRC" && make clean >/dev/null && make -j"$(nproc)" ); }

phase_dwl() {
  log "Building dwl from source"
  inst "${P_DWL_DEPS[@]}"
  mkdir -p "$(dirname "$DWL_SRC")" "$DWL_PATCH_DIR"

  if [[ -f "$DWL_SRC/.dwlsetup-prepared" && "${DWL_RESET:-0}" != "1" ]]; then
    warn "dwl source already prepared at $DWL_SRC - rebuilding only (set DWL_RESET=1 to re-clone/re-patch; your edits are kept)."
  else
    rm -rf "$DWL_SRC"
    git clone https://codeberg.org/dwl/dwl.git "$DWL_SRC" || die "Could not clone dwl."
    local ref="$DWL_REF"
    [[ -n "$ref" ]] || ref="$(git -C "$DWL_SRC" tag --list 'v*' | sort -V | tail -1)"
    [[ -n "$ref" ]] || ref="main"
    git -C "$DWL_SRC" checkout -q "$ref" || die "No such dwl ref: $ref"
    info "dwl ref: $ref"

    # Install the wlroots version this dwl ref was written for.
    local pc ver; pc="$(grep -oE 'wlroots-[0-9]+\.[0-9]+' "$DWL_SRC/config.mk" | head -1)"; ver="${pc#wlroots-}"
    if [[ -n "$ver" ]]; then inst_any "wlroots${ver}" wlroots; else inst wlroots; fi
    if [[ -n "$pc" ]] && ! pkg-config --exists "$pc"; then
      die "dwl $ref needs $pc but it is not installed. Try DWL_REF=<an older tag matching your wlroots>."
    fi

    # Patches. Applied only if they apply cleanly; conflicts are skipped, not forced.
    local name f
    for name in $DWL_PATCHES; do
      f="$DWL_PATCH_DIR/$name.patch"
      if [[ ! -s "$f" ]]; then
        curl -fsSL "https://codeberg.org/dwl/dwl-patches/raw/branch/main/patches/$name/$name.patch" -o "$f" \
          || { rm -f "$f"; warn "patch '$name': download failed. Put your own at $f and re-run with DWL_RESET=1."; continue; }
      fi
      if (cd "$DWL_SRC" && patch -p1 --dry-run -s <"$f" >/dev/null 2>&1); then
        (cd "$DWL_SRC" && patch -p1 -s <"$f") && APPLIED+=("$name") && info "applied patch: $name"
      else
        warn "patch '$name' does not apply cleanly on dwl $ref (conflicts with an earlier patch or targets another version) - skipped."
      fi
    done

    [[ -f "$DWL_SRC/config.h" ]] || cp "$DWL_SRC/config.def.h" "$DWL_SRC/config.h"
    if [[ "$WITH_XWAYLAND" == "1" ]]; then
      sed -i -e 's/^#XWAYLAND *=/XWAYLAND =/' -e 's/^#XLIBS *=/XLIBS =/' "$DWL_SRC/config.mk"
    fi
    touch "$DWL_SRC/.dwlsetup-prepared"
  fi

  if ! dwl_build; then
    if ((${#APPLIED[@]})); then
      warn "Patched build failed (${APPLIED[*]}). Falling back to vanilla dwl."
      git -C "$DWL_SRC" checkout -q -f && rm -f "$DWL_SRC/config.h" && cp "$DWL_SRC/config.def.h" "$DWL_SRC/config.h"
      [[ "$WITH_XWAYLAND" == "1" ]] && sed -i -e 's/^#XWAYLAND *=/XWAYLAND =/' -e 's/^#XLIBS *=/XLIBS =/' "$DWL_SRC/config.mk"
      APPLIED=()
      dwl_build || die "Vanilla dwl build failed too. Check wlroots/dwl version pairing."
    else
      die "dwl build failed."
    fi
  fi
  sudo make -C "$DWL_SRC" PREFIX=/usr/local install || die "dwl install failed."

  # Rebuild helper + pacman hook (replaces what the AUR package used to do on wlroots updates).
  sed -e "s|__SRC__|$DWL_SRC|" -e "s|__USER__|$USER|" <<'EOF' | write_root_exec /usr/local/bin/dwl-rebuild
#!/usr/bin/env bash
# Rebuild + reinstall dwl from your source tree (edit config.h, then run: dwl-rebuild).
set -euo pipefail
SRC="__SRC__"; OWNER="__USER__"
as_owner() { if [[ $EUID -eq 0 ]]; then runuser -u "$OWNER" -- "$@"; else "$@"; fi; }
as_owner make -C "$SRC" clean
as_owner make -C "$SRC" -j"$(nproc)"
if [[ $EUID -eq 0 ]]; then make -C "$SRC" PREFIX=/usr/local install; else sudo make -C "$SRC" PREFIX=/usr/local install; fi
echo "dwl rebuilt. Log out and back in to run the new binary."
EOF
  write_root /etc/pacman.d/hooks/dwl-rebuild.hook <<EOF
[Trigger]
Operation = Upgrade
Type = Package
Target = wlroots*

[Action]
Description = Rebuilding dwl against updated wlroots...
When = PostTransaction
Exec = /usr/local/bin/dwl-rebuild
EOF
  info "installed: /usr/local/bin/dwl (+ dwl-rebuild, and a pacman hook that rebuilds dwl when wlroots updates)"
  info "if wlroots jumps to a new minor version (0.x -> 0.y) the hook will fail: re-run this script with DWL_RESET=1."
}

# ----------------------------------------------------------- 6. visual layer -
phase_visual() {
  log "Visual layer packages (installed; themed in the theme phase)"
  inst "${P_VISUAL[@]}"
  inst_groups "${A_VISUAL[@]}"   # awww (renamed from swww in Oct 2025); wttrbar (waybar weather)
  if command -v rofi >/dev/null && ! ldd "$(command -v rofi)" 2>/dev/null | grep -q libwayland-client; then
    warn "Your 'rofi' build has no Wayland backend (rofi >= 2.0 has it built in). Update the system."
  fi
}

# ------------------------------------------------------- 7. quality of life --
phase_qol() {
  log "Quality-of-life tools"
  inst "${P_QOL[@]}"
  inst_groups "${A_QOL[@]}"   # termfilechooser portal; wlogout (power menu)

  # Portal routing so screen capture + file pickers work under a plain wlroots compositor.
  {
    echo "[preferred]"
    echo "default=gtk"
    echo "org.freedesktop.impl.portal.ScreenCast=wlr"
    echo "org.freedesktop.impl.portal.Screenshot=wlr"
    [[ -e /usr/share/xdg-desktop-portal/portals/termfilechooser.portal ]] \
      && echo "org.freedesktop.impl.portal.FileChooser=termfilechooser"
  } | write_user_if_absent "$HOME/.config/xdg-desktop-portal/portals.conf"

  local wrapper=/usr/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh
  if [[ ! -x "$wrapper" ]]; then
    warn "termfilechooser's yazi-wrapper.sh not at $wrapper - check 'pacman -Ql xdg-desktop-portal-termfilechooser' and fix 'cmd=' in ~/.config/xdg-desktop-portal-termfilechooser/config"
  fi
  cat <<EOF | write_user_if_absent "$HOME/.config/xdg-desktop-portal-termfilechooser/config"
[filechooser]
cmd=$wrapper
default_dir=\$HOME
env=TERMCMD='foot -T termfilechooser'
open_mode=suggested
save_mode=last
EOF
}

# ------------------------------------------------------- 8. fonts, shell, ar -
phase_fonts() {
  log "Fonts, Arabic fontconfig, shell"
  inst "${P_FONTS[@]}"
  inst_groups "${A_FONTS[@]}"   # ttf-amiri, vazirmatn-fonts (AUR)

  # Arabic: prefer Naskh over Nastaliq (strong, only when lang=ar) plus a weak last-resort
  # fallback for apps (Chromium/Electron) that don't pass a language hint.
  write_user_if_absent "$HOME/.config/fontconfig/conf.d/99-arabic.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Path 1 (strong): language is Arabic -> Noto Naskh Arabic first -->
  <match target="pattern">
    <test name="lang" compare="contains"><string>ar</string></test>
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Naskh Arabic</string></edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>ar</string></test>
    <test name="family"><string>serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Naskh Arabic</string></edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>ar</string></test>
    <test name="family"><string>monospace</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Naskh Arabic</string></edit>
  </match>
  <!-- Path 2 (weak): no lang hint -> only used when nothing else has the glyphs -->
  <match target="pattern">
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="append" binding="weak"><string>Noto Naskh Arabic</string></edit>
  </match>
</fontconfig>
EOF
  fc-cache -f >/dev/null 2>&1
  info "fc-match for Arabic sans: $(fc-match 'sans-serif:lang=ar' 2>/dev/null)"

  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/zsh" ]]; then
    sudo chsh -s /usr/bin/zsh "$USER" && info "login shell -> zsh (takes effect next login)"
  fi
  write_user_if_absent "$HOME/.zshrc" <<'EOF'
# Minimal starter (written once by arch-dwl-setup.sh). Make it yours.
HISTFILE=~/.zsh_history; HISTSIZE=50000; SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS AUTO_CD
autoload -Uz compinit && compinit
alias ls='eza --icons' ll='eza -l --icons' cat='bat --paging=never'
alias fetch='fastfetch'
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
}

# --------------------------------------------------------------- 9. apps -----
phase_apps() {
  log "Applications"
  inst "${P_APPS[@]}"
  inst_groups "${A_APPS[@]}"   # endcord, syncplay, superseedr, spotatui, clock-tui (binary: tclock), LocalSend
  [[ "$WITH_UNVERIFIED" == "1" ]] && inst_groups "${A_UNVERIFIED[@]}"
}

# ------------------------------------------------------------ 9b. gaming -----
phase_gaming() {
  log "Gaming: Steam + performance stack"
  inst "${P_GAMING[@]}"
  inst_groups "${A_GAMING[@]}"   # proton-ge-custom-bin: latest GE-Proton
  info "usage: 'gamemoderun %command%' as a Steam launch option; gamescope via:"
  info "  gamescope -W 1920 -H 1080 -r 120 -- gamemoderun %command%"
  info "mangohud: launch with MANGOHUD=1 %command% (tweak in goverlay)."
  info "Proton: Steam -> Settings -> Compatibility -> enable, then pick GE-Proton per game."
}

# ---------------------------------------------------------- 9c. torrent ------
phase_torrent() {
  log "Torrents: holistic search (Prowlarr) + aria2"
  inst "${P_TORRENT[@]}"
  inst_groups "${A_TORRENT[@]}" || { warn "Prowlarr did not install; torrent search skipped."; return 0; }
  if [[ -f /usr/lib/systemd/system/prowlarr.service ]]; then
    sudo systemctl enable --now prowlarr.service || warn "Could not enable prowlarr.service."
    info "Prowlarr: http://localhost:9696  (first visit: Settings -> General -> Authentication -> disable for localhost,"
    info "  then Indexers -> Add -> pick public trackers like 1337x/TorrentGalaxy)."
  else
    warn "prowlarr.service unit not found - start it manually (see the book, 'Torrents')."
  fi
  info "aria2: paste a magnet into 'aria2c <magnet>' or use it as a download backend."
}

# ---------------------------------------------------------- 9d. lazyvim ------
phase_lazyvim() {
  log "LazyVim (Neovim distribution)"
  if [[ -d "$HOME/.config/nvim" ]]; then info "~/.config/nvim exists, left untouched"; return 0; fi
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim" || { warn "LazyVim clone failed."; return 0; }
  rm -rf "$HOME/.config/nvim/.git"
  info "LazyVim installed. First 'nvim' run downloads plugins + treesitter parsers."
  if [[ "$WITH_AI" == "1" ]] && command -v jq >/dev/null && [[ -f "$HOME/.config/nvim/lazyvim.json" ]]; then
    jq '.extras = ((.extras // []) + ["lazyvim.plugins.extras.ai.avante", "lazyvim.plugins.extras.ai.claudecode"] | unique)' \
      "$HOME/.config/nvim/lazyvim.json" >"$HOME/.config/nvim/lazyvim.json.tmp" \
      && mv "$HOME/.config/nvim/lazyvim.json.tmp" "$HOME/.config/nvim/lazyvim.json"
    info "enabled LazyVim extras: ai.avante + ai.claudecode (API keys: see the book, 'AI workflow')"
  fi
}

# -------------------------------------------------------------- 9e. ai ------
phase_ai() {
  log "AI tooling: Claude Code (npm) + DeepSeek-ready"
  command -v npm >/dev/null || { warn "npm missing - install nodejs/npm first (apps phase)."; return 0; }
  # Arch's pacman npm can't write to /usr as a normal user -> install to ~/.local
  # (already on PATH), no sudo needed.
  npm config set prefix "$HOME/.local" 2>/dev/null
  npm install -g @anthropic-ai/claude-code || warn "claude-code install failed."
  info "Keys are NEVER stored in config files. Export them per shell (or via a keyring):"
  info "  export ANTHROPIC_API_KEY=sk-ant-..."
  info "  DeepSeek as Claude Code backend: export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic"
  info "  export ANTHROPIC_API_KEY=<deepseek-key>  (claude-opus maps to deepseek-v4-pro)"
}

# ------------------------------------------------------------- 10. docker ----
phase_docker() {
  log "Rootless Docker"
  inst "${P_DOCKER[@]}"
  inst_groups "${A_DOCKER[@]}" || { warn "docker-rootless-extras unavailable; rootless Docker not configured."; return 0; }
  grep -q "^$USER:" /etc/subuid 2>/dev/null || sudo usermod --add-subuids 100000-165535 "$USER"
  grep -q "^$USER:" /etc/subgid 2>/dev/null || sudo usermod --add-subgids 100000-165535 "$USER"
  sudo systemctl disable --now docker.service docker.socket >/dev/null 2>&1 || true   # rootful daemon OFF
  mkdir -p "$HOME/.config/dwl"
  grep -qs 'DOCKER_HOST' "$HOME/.config/dwl/env" 2>/dev/null \
    || echo 'export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"' >> "$HOME/.config/dwl/env"
  # The AUR package ships its own user unit: dockerd-rootless.service (not docker.service).
  if systemctl --user show-environment >/dev/null 2>&1; then
    command -v dockerd-rootless-setuptool.sh >/dev/null && { dockerd-rootless-setuptool.sh check || warn "rootless pre-flight check reported problems (read the output above)"; }
    systemctl --user enable --now dockerd-rootless.service \
      || warn "Could not start dockerd-rootless.service; after first login run: systemctl --user enable --now dockerd-rootless.service"
  else
    warn "No systemd user session here. After your first dwl login run:  systemctl --user enable --now dockerd-rootless.service"
  fi
  info "Do NOT add yourself to the 'docker' group - that is root-equivalent and defeats rootless mode."
}

# ------------------------------------------------------------- 11. theme ----
theme_palette() {  # sets BG BG2 BG3 FG CMT ACC ACC2 OK WARN ERR YEL CYN ORN
  case "${THEME:-none}" in
    catppuccin)
      BG='#1e1e2e'; BG2='#181825'; BG3='#313244'; FG='#cdd6f4'; CMT='#6c7086'
      ACC='#cba6f7'; ACC2='#f5c2e7'; OK='#a6e3a1'; WARN='#fab387'; ERR='#f38ba8'; YEL='#f9e2af'; CYN='#89dceb'; ORN='#fab387' ;;
    nord)
      BG='#2e3440'; BG2='#272c36'; BG3='#3b4252'; FG='#d8dee9'; CMT='#4c566a'
      ACC='#b48ead'; ACC2='#81a1c1'; OK='#a3be8c'; WARN='#d08770'; ERR='#bf616a'; YEL='#ebcb8b'; CYN='#88c0d0'; ORN='#d08770' ;;
    tokyonight)
      BG='#1a1b26'; BG2='#16161e'; BG3='#292e42'; FG='#c0caf5'; CMT='#565f89'
      ACC='#bb9af7'; ACC2='#f7768e'; OK='#9ece6a'; WARN='#e0af68'; ERR='#f7768e'; YEL='#e0af68'; CYN='#7dcfff'; ORN='#e0af68' ;;
    *)
      BG='#282a36'; BG2='#1d1f2a'; BG3='#44475a'; FG='#f8f8f2'; CMT='#6272a4'
      ACC='#bd93f9'; ACC2='#ff79c6'; OK='#50fa7b'; WARN='#ffb86c'; ERR='#ff5555'; YEL='#f1fa8c'; CYN='#8be9fd'; ORN='#ffb86c' ;;
  esac
  # ANSI names used by tuireet's ratatui theme string
  ANSI_BORDER='magenta'; ANSI_TEXT='white'; ANSI_PROMPT='magenta'; ANSI_INPUT='white'
  ANSI_ACTION='bright-blue'; ANSI_BUTTON='bright-red'; ANSI_CONTAINER='black'
}

theme_write() {  # theme_write mode "path" < content   (respects THEME_FORCE)
  local mode="$1" f="$2"
  if [[ -e "$f" && "$THEME_FORCE" != "1" ]]; then cat >/dev/null; info "exists, left untouched: $f"; return 0; fi
  mkdir -p "$(dirname "$f")" && install -m "$mode" /dev/stdin "$f" && info "wrote $f"
}

theme_wallpaper() {
  local wp="$HOME/.config/dwl/wallpaper.png"
  [[ -s "$wp" && "$THEME_FORCE" != "1" ]] && { info "wallpaper exists: $wp"; return 0; }
  mkdir -p "$HOME/.config/dwl"
  # tasteful dark gradient + soft accent glow, dithered so it never bands on the IPS panel
  magick -size 1920x1080 "gradient:${BG2}-${BG}" \
    \( -size 800x800 "radial-gradient:${ACC}-none" \) -gravity northwest -geometry +80+40 -compose screen -composite \
    \( -size 900x900 "radial-gradient:${ACC2}-none" \) -gravity southeast -geometry +120+80 -compose screen -composite \
    -attenuate 0.03 +noise Gaussian -define png:compression-level=9 "$wp" \
    || { warn "ImageMagick wallpaper generation failed - wallpaper skipped."; return 0; }
  info "wrote wallpaper: $wp"
}

theme_dwl_colors() {
  # Theme dwl's border/focus/root/urgent colors + gaps + border width - only when
  # the config.h lines still look vanilla (sed simply won't match user edits).
  local h="$DWL_SRC/config.h"
  [[ -f "$h" ]] || return 0
  local line_rgb focus_rgb root_rgb
  line_rgb="$(hex2rgb "$BG3")"; focus_rgb="$(hex2rgb "$ACC")"; root_rgb="$(hex2rgb "$BG2")"
  sed -i \
    -e "s|^static const float bordercolor\[\].*|static const float bordercolor[]           = {${line_rgb}, 1.0};|" \
    -e "s|^static const float focuscolor\[\].*|static const float focuscolor[]            = {${focus_rgb}, 1.0};|" \
    -e "s|^static const float rootcolor\[\].*|static const float rootcolor[]              = {${root_rgb}, 1.0};|" \
    -e "s|^static const float urgentcolor\[\].*|static const float urgentcolor[]           = {1.0000, 0.3333, 0.3333, 1.0};|" \
    "$h"
  # genericgaps patch defaults: 10 -> 12 for a breathable 8px-grid look
  sed -i -e 's|^static const int gappih = 10;|static const int gappih = 12;|' \
         -e 's|^static const int gappiv = 10;|static const int gappiv = 12;|' \
         -e 's|^static const int gappoh = 10;|static const int gappoh = 12;|' \
         -e 's|^static const int gappov = 10;|static const int gappov = 12;|' \
         -e 's|^static const unsigned int borderpx = 1;|static const unsigned int borderpx = 2;|' "$h"
  return 0
}

theme_dwl_keys() {
  # MODKEY Super + rofi launcher + terminal/zoom swap + extra keybinds (61-key
  # friendly + XF86). Every edit only matches vanilla lines (never user edits).
  local h="$DWL_SRC/config.h" tmp
  [[ -f "$h" ]] || return 0
  # 1. Super as the mod key (dwl documents WLR_MODIFIER_LOGO for this).
  sed -i 's|^#define MODKEY WLR_MODIFIER_ALT|#define MODKEY WLR_MODIFIER_LOGO|' "$h"
  grep -q 'MODKEY WLR_MODIFIER_LOGO' "$h" && info "dwl MODKEY -> Super" || warn "MODKEY line not vanilla - left as-is (your keybinds below may use a different mod)"
  # 2. Terminal on Mod+Return, zoom on Mod+Shift+Return (# delimiter: patterns contain |).
  sed -i \
    -e 's#{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return,      spawn,            {.v = termcmd} },#{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return,      zoom,             {0} },#' \
    -e 's#{ MODKEY,                    XKB_KEY_Return,      zoom,             {0} },#{ MODKEY,                    XKB_KEY_Return,      spawn,            {.v = termcmd} },#' "$h"
  # 3. Launcher = rofi (icons-only apps) instead of wmenu-run.
  sed -i 's|static const char \*menucmd\[\] = { "wmenu-run", NULL };|static const char *menucmd[] = { "rofi", "-show", "drun", NULL };|' "$h"
  grep -q '"rofi", "-show", "drun"' "$h" && info "dwl launcher -> rofi (drun)" || warn "menucmd line not vanilla - launcher left as wmenu-run"
  # 4. Append the extra keybinds after dwl's vanilla tag-quit key.
  if grep -q 'dwlsetup keys' "$h"; then info "dwl keybinds already present"; return 0; fi
  grep -q 'XKB_KEY_q, *quit,' "$h" \
    || { warn "dwl keys[] anchor not found in config.h - keybinds skipped (add them by hand or DWL_RESET=1)."; return 0; }
  tmp="$(mktemp)"
  cat >"$tmp" <<'EOF'
	/* --- dwlsetup keys (61-key friendly: no Print, no XF86 needed) --- */
	{ MODKEY, XKB_KEY_Up, spawn, SHCMD("swayosd-client --output-volume raise") },
	{ MODKEY, XKB_KEY_Down, spawn, SHCMD("swayosd-client --output-volume lower") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Up, spawn, SHCMD("swayosd-client --output-volume mute-toggle") },
	{ MODKEY, XKB_KEY_Right, spawn, SHCMD("brightnessctl set +5%") },
	{ MODKEY, XKB_KEY_Left, spawn, SHCMD("brightnessctl set 5%-") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_s, spawn, SHCMD("dwl-screenshot region") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_f, spawn, SHCMD("dwl-screenshot full") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_w, spawn, SHCMD("dwl-wallpaper --next") },
	{ MODKEY, XKB_KEY_w, spawn, SHCMD("dwl-wallpaper --menu") },
	{ MODKEY, XKB_KEY_x, spawn, SHCMD("dwl-quick") },
	{ MODKEY, XKB_KEY_slash, spawn, SHCMD("dwl-help") },
	{ 0, XKB_KEY_XF86AudioRaiseVolume, spawn, SHCMD("swayosd-client --output-volume raise") },
	{ 0, XKB_KEY_XF86AudioLowerVolume, spawn, SHCMD("swayosd-client --output-volume lower") },
	{ 0, XKB_KEY_XF86AudioMute, spawn, SHCMD("swayosd-client --output-volume mute-toggle") },
	{ 0, XKB_KEY_XF86MonBrightnessUp, spawn, SHCMD("brightnessctl set +5%") },
	{ 0, XKB_KEY_XF86MonBrightnessDown, spawn, SHCMD("brightnessctl set 5%-") },
	{ 0, XKB_KEY_Print, spawn, SHCMD("dwl-screenshot region") },
	/* --- end dwlsetup keys --- */
EOF
  sed -i -e "/XKB_KEY_q, *quit,/r $tmp" "$h"
  rm -f "$tmp"
  grep -q 'dwlsetup keys' "$h" && info "added dwl keybinds (Super+arrows = volume/brightness, Super+Shift+S/F = screenshots)" \
    || warn "keybind insert failed - check config.h"
}

phase_theme() {
  [[ "${THEME:-none}" == "none" ]] && { log "Theme: none requested"; return 0; }
  log "Theme: $THEME (dracula-style, everything consistent)"
  theme_palette

  inst_groups "${A_THEME[@]}"   # dracula-gtk-theme, dracula-cursors-git, dracula-grub-theme-git

  # ---- foot ----
  # NOTE: foot wants RRGGBB *without* '#', and current versions read
  # [colors-dark] (plain [colors] is kept for older foot releases).
  cat <<EOF | theme_write 644 "$HOME/.config/foot/foot.ini"
# foot - written by arch-dwl-setup.sh (theme: $THEME)
[main]
font=JetBrainsMono Nerd Font:size=11.5
pad=8x8 center
[colors]
foreground=${FG#\#}
background=${BG#\#}
regular0=${BG3#\#}
regular1=${ERR#\#}
regular2=${OK#\#}
regular3=${YEL#\#}
regular4=${ACC#\#}
regular5=${ACC2#\#}
regular6=${CYN#\#}
regular7=${FG#\#}
bright0=${CMT#\#}
bright1=${ERR#\#}
bright2=${OK#\#}
bright3=${YEL#\#}
bright4=${ACC#\#}
bright5=${ACC2#\#}
bright6=${CYN#\#}
bright7=${FG#\#}
[colors-dark]
foreground=${FG#\#}
background=${BG#\#}
regular0=${BG3#\#}
regular1=${ERR#\#}
regular2=${OK#\#}
regular3=${YEL#\#}
regular4=${ACC#\#}
regular5=${ACC2#\#}
regular6=${CYN#\#}
regular7=${FG#\#}
bright0=${CMT#\#}
bright1=${ERR#\#}
bright2=${OK#\#}
bright3=${YEL#\#}
bright4=${ACC#\#}
bright5=${ACC2#\#}
bright6=${CYN#\#}
bright7=${FG#\#}
[cursor]
color=${FG#\#} ${FG#\#}
blink=yes
EOF

  # ---- waybar ----
  cat <<EOF | theme_write 644 "$HOME/.config/waybar/config"
{
    "layer": "top",
    "position": "top",
    "height": 32,
    "spacing": 4,
    "modules-left": ["dwl/tags", "dwl/title"],
    "modules-center": ["mpris"],
    "modules-right": ["custom/weather", "network", "bluetooth", "pulseaudio", "clock", "tray"],
    "dwl/tags": {
        "num-tags": 9
    },
    "dwl/title": {
        "max-length": 60,
        "format": "{title}"
    },
    "mpris": {
        "format": "♪ {title} — {artist}",
        "format-paused": "♪ {title} — {artist}",
        "max-length": 70,
        "tooltip-format": "{player} · {title} · {album}"
    },
    "custom/weather": {
        "format": "{}°C",
        "tooltip": true,
        "interval": 3600,
        "exec": "wttrbar",
        "return-type": "json"
    },
    "network": {
        "format-ethernet": "🌐 {ifname} {ipaddr}",
        "format-disconnected": "🌐 off",
        "tooltip-format": "{ifname}: {ipaddr}/{cidr}"
    },
    "bluetooth": {
        "format": "🔵 off",
        "format-on": "🔵 on",
        "format-connected": "🔵 {num_connections}",
        "tooltip-format": "{status}"
    },
    "pulseaudio": {
        "format": "🔊 {volume}%",
        "format-muted": "🔇 muted",
        "on-click": "pavucontrol",
        "tooltip": false
    },
    "clock": {
        "format": "📅 {:%a %d %b %H:%M:%S}",
        "interval": 1,
        "on-click": "gsimplecal",
        "tooltip-format": "{:%B %Y}"
    },
    "tray": {
        "spacing": 8
    }
}
EOF
  cat <<EOF | theme_write 644 "$HOME/.config/waybar/style.css"
/* waybar - written by arch-dwl-setup.sh (theme: $THEME) */
* {
    font-family: "JetBrainsMono Nerd Font";
    font-size: 12px;
    min-height: 0;
    border: none;
    border-radius: 0;
}
window#waybar {
    background: rgba(40, 42, 54, 0.85);
    color: $FG;
}
#workspaces,
.modules-left, .modules-center, .modules-right {
    padding: 0 6px;
}
.modules-left > widget > label { color: $FG; }
#tags button {
    color: $CMT;
    background: transparent;
    margin: 3px 2px;
    padding: 0 10px;
    border-radius: 4px;
}
#tags button.occupied { color: $FG; background: $BG3; }
#tags button.focused { color: $BG; background: $ACC; font-weight: bold; }
#title { color: $FG; padding: 0 10px; }
#mpris { color: $ACC2; }
#custom-weather { color: $YEL; }
#network { color: $CYN; }
#bluetooth { color: $CYN; }
#pulseaudio { color: $OK; }
#clock { color: $CYN; }
#tray { padding: 0 4px; }
#tray menu { background: $BG; color: $FG; }
label:disabled { color: $CMT; }
EOF

  # ---- mako ----
  cat <<EOF | theme_write 644 "$HOME/.config/mako/config"
# mako - written by arch-dwl-setup.sh (theme: $THEME)
font=JetBrainsMono Nerd Font 11
background-color=$BG
text-color=$FG
border-color=$ACC
border-size=1
border-radius=8
margin=12
padding=12
default-timeout=5000
max-visible=5
icons=1
layer=overlay
anchor=top-right
[urgency=high]
border-color=$ERR
[urgency=low]
border-color=$BG3
EOF

  # ---- rofi (apps only: icon + name) ----
  cat <<EOF | theme_write 644 "$HOME/.config/rofi/config.rasi"
// rofi - written by arch-dwl-setup.sh (theme: $THEME)
configuration {
    show-icons: true;
    modi: "drun";
    drun-display-format: "{name}";
    display-drun: "Apps";
    disable-history: true;
}
* {
    font: "JetBrainsMono Nerd Font 12";
    background-color: transparent;
    text-color: $FG;
}
window {
    location: north;
    anchor: north;
    y-offset: 8;
    width: 480px;
    padding: 12px;
    border: 1px;
    border-radius: 12px;
    border-color: $ACC;
    background-color: $BG;
}
inputbar {
    padding: 8px 12px;
    border-radius: 8px;
    background-color: $BG3;
    children: [ prompt, entry ];
}
prompt { text-color: $ACC2; padding: 0 8px 0 0; }
listview {
    lines: 8;
    columns: 1;
    scrollbar: false;
}
element {
    padding: 8px 12px;
    border-radius: 8px;
    spacing: 12px;
}
element selected {
    background-color: $ACC;
    text-color: $BG;
}
element-icon { size: 26px; }
element-text { horizontal-align: 0.0; }
EOF

  # ---- starship ----
  cat <<EOF | theme_write 644 "$HOME/.config/starship.toml"
# starship - written by arch-dwl-setup.sh (theme: $THEME)
format = "\$directory\$git_branch\$character"
[character]
success_symbol = "[➜](${ACC})"
error_symbol = "[➜](${ERR})"
[directory]
style = "bold $CYN"
truncation_length = 3
[git_branch]
symbol = " "
style = "$ACC2"
EOF

  # ---- fastfetch (tiny bat logo in theme colors) ----
  cat <<EOF | theme_write 644 "$HOME/.config/fastfetch/config.jsonc"
// fastfetch - written by arch-dwl-setup.sh (theme: $THEME)
{
    "logo": {
        "type": "small",
        "padding": { "top": 2, "right": 2 },
        "source": "  (       )\n (         )\n(           )\n (         )\n  (       )\n"
    },
    "display": {
        "separator": "  "
    },
    "modules": [
        { "type": "title", "format": "{user-name}@{host-name}" },
        { "type": "os", "key": "OS" },
        { "type": "kernel", "key": "Kernel" },
        { "type": "uptime", "key": "Uptime" },
        { "type": "packages", "key": "Packages" },
        { "type": "shell", "key": "Shell" },
        { "type": "display", "key": "Display" },
        { "type": "wm", "key": "WM" },
        { "type": "terminal", "key": "Terminal" },
        { "type": "cpu", "key": "CPU" },
        { "type": "gpu", "key": "GPU" },
        { "type": "memory", "key": "Memory" },
        "break",
        { "type": "colors", "symbol": "block", "paddingLeft": 2 }
    ]
}
EOF

  # ---- GTK3 / GTK4 ----
  cat <<EOF | theme_write 644 "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Dracula
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Dracula-cursors
gtk-font-name=JetBrainsMono Nerd Font 10
gtk-application-prefer-dark-theme=1
EOF
  cat <<EOF | theme_write 644 "$HOME/.config/gtk-4.0/settings.ini"
[Settings]
gtk-theme-name=Dracula
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Dracula-cursors
gtk-font-name=JetBrainsMono Nerd Font 10
gtk-application-prefer-dark-theme=1
EOF

  # ---- Qt (qt6ct / qt5ct) ----
  for qt in qt6ct qt5ct; do
    cat <<EOF | theme_write 644 "$HOME/.config/$qt/$qt.conf"
[Appearance]
style=Fusion
standard_dialogs=default
custom_palette=true
[ColorScheme]
active_colors=$BG, $FG, $BG2, $BG3, $FG, $BG, $FG, $ERR, $BG3, $FG, $BG, $FG, $ACC
disabled_colors=$BG2, $CMT, $BG2, $BG3, $CMT, $BG2, $CMT, $ERR, $BG3, $CMT, $BG2, $CMT, $ACC
inactive_colors=$BG, $FG, $BG2, $BG3, $FG, $BG, $FG, $ERR, $BG3, $FG, $BG, $FG, $ACC
EOF
  done

  # ---- dwl colors + gaps + modkey + launcher + keybinds + rebuild ----
  theme_dwl_colors
  theme_dwl_keys
  if [[ -f "$DWL_SRC/config.h" ]] && grep -qE 'dwlsetup|MODKEY WLR_MODIFIER_LOGO|"rofi", "-show", "drun"' "$DWL_SRC/config.h"; then
    log "Rebuilding dwl with theme colors, gaps, Super modkey and keybinds"
    dwl_build && sudo make -C "$DWL_SRC" PREFIX=/usr/local install \
      || warn "dwl rebuild failed after theme edits - restore $DWL_SRC/config.h and run dwl-rebuild."
  fi

  # ---- wallpaper + wallpaper manager + quick settings + screenshot helper ----
  theme_wallpaper
  cat <<'EOF' | theme_write 755 "$HOME/.local/bin/dwl-wallpaper"
#!/usr/bin/env bash
# dwl-wallpaper - local wallpaper library + live wallhaven.cc toplist fetcher.
#   dwl-wallpaper <file>      set that file
#   dwl-wallpaper --add F...  copy files into the library
#   dwl-wallpaper --remove    pick one from a menu and delete it
#   dwl-wallpaper --list      pick one from a menu and set it
#   dwl-wallpaper --browse    view the whole library in imv
#   dwl-wallpaper --next      cycle to the next wallpaper
#   dwl-wallpaper --random    random wallpaper from the library
#   dwl-wallpaper --fetch     wallhaven.cc top-30 toplist, live thumbnail preview, pick -> set
#   dwl-wallpaper --menu      interactive menu (no args = same)
set -uo pipefail
shopt -s nullglob
LIB="${XDG_PICTURES_DIR:-$HOME/Pictures}/wallpapers"
CACHE="$HOME/.cache/wallhaven"
KEYFILE="$HOME/.config/wallhaven.key"
mkdir -p "$LIB" "$CACHE"

set_wp() {
  if pgrep -x awww-daemon >/dev/null 2>&1; then awww img "$1" 2>/dev/null
  elif pgrep -x swww-daemon >/dev/null 2>&1; then swww img "$1" --transition-type fade --transition-duration 0.5 2>/dev/null
  else notify-send "wallpaper" "wallpaper daemon not running (start awww-daemon)" 2>/dev/null || true; fi
  notify-send "wallpaper" "wallpaper set: $(basename "$1")" 2>/dev/null || true
}

pick() { find "$LIB" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' \) -printf '%f\n' | sort | wmenu -p "wallpaper"; }

case "${1:-}" in
  --add) shift; for f in "$@"; do [[ -f "$f" ]] && cp -n "$f" "$LIB/" && notify-send "wallpaper" "added: $(basename "$f")" 2>/dev/null || true; done ;;
  --remove)
    sel="$(pick)"; [[ -n "$sel" ]] && rm "$LIB/$sel" && notify-send "wallpaper" "removed: $sel" 2>/dev/null || true ;;
  --list) sel="$(pick)"; [[ -n "$sel" ]] && set_wp "$LIB/$sel" ;;
  --browse) imv -b '#1d1f2a' "$LIB"/* 2>/dev/null || imv "$LIB"/* ;;
  --next)
    files=("$LIB"/*); n="${#files[@]}"; (( n > 0 )) || { echo "library is empty: dwl-wallpaper --add <file>"; exit 1; }
    idx=$(cat "$CACHE/idx" 2>/dev/null || echo 0); (( idx = (idx + 1) % n ))
    [[ -f "${files[idx]}" ]] || { echo "library is empty"; exit 1; }
    echo "$idx" >"$CACHE/idx"; set_wp "${files[idx]}" ;;
  --random)
    files=("$LIB"/*); (( ${#files[@]} > 0 )) || { echo "library is empty"; exit 1; }
    set_wp "${files[RANDOM % ${#files[@]}]}" ;;
  --set-apikey) read -rsp "wallhaven API key (from wallhaven.cc/settings/account): " k; echo; echo "$k" >"$KEYFILE"; chmod 600 "$KEYFILE"; echo "key saved (600) to $KEYFILE" ;;
  --fetch)
    command -v jq >/dev/null || { echo "jq is required"; exit 1; }
    command -v chafa >/dev/null || { echo "chafa is required"; exit 1; }
    command -v magick >/dev/null || { echo "imagemagick is required"; exit 1; }
    key="$(cat "$KEYFILE" 2>/dev/null || true)"
    [[ -n "$key" ]] || { echo "wallhaven needs a free API key:  dwl-wallpaper --set-apikey  (wallhaven.cc -> Settings -> API)"; exit 1; }
    echo "fetching wallhaven.cc top-30 toplist..."
    json=$(curl -fsSL "https://wallhaven.cc/api/v1/search?sorting=toplist&order=desc&categories=111&purity=100&apikey=$key") || { echo "fetch failed"; exit 1; }
    rm -rf "$CACHE/thumbs"; mkdir -p "$CACHE/thumbs"
    echo "$json" | jq -r '.data[:30][] | "\(.id) \(.thumbs.large) \(.resolution) \(.path)"' >"$CACHE/list.tsv"
    i=1
    while read -r id thumb res path; do
      curl -fsSL "$thumb" -o "$CACHE/thumbs/$(printf '%02d' "$i")_${id}.jpg" &
      i=$((i+1))
    done <"$CACHE/list.tsv"
    wait
    magick montage "$CACHE/thumbs"/*.jpg -tile 5x6 -geometry 300x169+6+6 -background '#1d1f2a' -fill '#f8f8f2' -pointsize 22 -label '%t' "$CACHE/grid.png"
    chafa --format symbols "$CACHE/grid.png"
    read -rp "pick 1-30 or q: " n
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "aborted"; exit 0; }
    line=$(sed -n "${n}p" "$CACHE/list.tsv"); read -r id thumb res path <<<"$line"
    out="$LIB/wallhaven-${id}.jpg"
    echo "downloading $res → $out"
    curl -fL "$path" -o "$out" && set_wp "$out"
    ;;
  --menu)
    sel=$(printf '%s\n' "Next wallpaper" "Random wallpaper" "Pick from library" "Browse library (imv)" "Fetch wallhaven top-30" "Add a wallpaper file" "Remove a wallpaper" | wmenu -p "wallpapers")
    case "$sel" in
      "Next wallpaper") exec "$0" --next ;;
      "Random wallpaper") exec "$0" --random ;;
      "Pick from library") exec "$0" --list ;;
      "Browse library (imv)") exec "$0" --browse ;;
      "Fetch wallhaven top-30") exec "$0" --fetch ;;
      "Add a wallpaper file")
        f=$(find "$HOME/Downloads" "$HOME/Pictures" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.webp' \) -printf '%f\n' 2>/dev/null | sort | wmenu -p "add from"); [[ -n "$f" ]] && "$0" --add "$HOME/Downloads/$f" 2>/dev/null || "$0" --add "$HOME/Pictures/$f" 2>/dev/null || true ;;
      "Remove a wallpaper") exec "$0" --remove ;;
    esac ;;
  *) [[ -f "$1" ]] && set_wp "$1" || exec "$0" --menu ;;
esac
EOF
  cat <<'EOF' | theme_write 755 "$HOME/.local/bin/dwl-help"
#!/usr/bin/env bash
# dwl-help - searchable cheatsheet + action menu (Super+/).
# Type to filter, Enter: runs actions, shows info for the rest.
set -uo pipefail
NAMES=(
"WINDOWS — Super+Return: terminal"
"WINDOWS — Super+P: app launcher (rofi)"
"WINDOWS — Super+X: quick settings"
"WINDOWS — Super+/: this help menu"
"WINDOWS — Super+1..9: switch workspace | Super+Shift+1..9: move window there"
"WINDOWS — Super+J/K: focus next/previous window"
"WINDOWS — Super+H/L: shrink/grow master area"
"WINDOWS — Super+T/M/F: tiling / monocle / floating layout"
"WINDOWS — Super+Space: cycle layouts | Super+Shift+Space: float toggle"
"WINDOWS — Super+E: fullscreen toggle | Super+Tab: last workspace"
"WINDOWS — Super+Shift+C: kill window | Super+Shift+Q: quit dwl"
"MEDIA — Super+Up/Down: volume up/down"
"MEDIA — Super+Shift+Up: mute toggle"
"MEDIA — Super+Left/Right: screen brightness"
"MEDIA — mpv keys: Left/Right seek 5s, Up/Down seek 1min, F fullscreen, S shot, M mute, I stats"
"SCREEN — Super+Shift+S: region screenshot (annotate in satty)"
"SCREEN — Super+Shift+F: fullscreen screenshot"
"WALLPAPER — Super+W: wallpaper menu"
"WALLPAPER — Super+Shift+W: next wallpaper"
"WALLPAPER — fetch wallhaven top-30 (live preview, pick a number)"
"WALLPAPER — add/remove local wallpapers"
"NET — ethernet status is in the bar (NetworkManager)"
"NET — open connection editor (nmtui)"
"BLUETOOTH — pair headset/controller (terminal)"
"BLUETOOTH — graphical manager (blueman)"
"APPS — files (yazi)"
"APPS — system monitor (btop)"
"APPS — calculator (calc)"
"APPS — calendar popup"
"APPS — AI coding agent (claude)"
"SYSTEM — lock screen"
"SYSTEM — power menu (wlogout)"
"SYSTEM — night light on/off (3500K)"
"SYSTEM — update everything (paru -Syu)"
"SYSTEM — rebuild dwl from config.h"
"LEARN — search all torrents: Prowlarr at localhost:9696"
"LEARN — re-run the system test suite"
"LEARN — read the full book (arch-dwl-setup-guide.pdf)"
)
CMDS=(
"foot" "rofi -show drun" "dwl-quick" "dwl-help" "" "" "" "" "" "" ""
"swayosd-client --output-volume raise" "swayosd-client --output-volume mute-toggle" "brightnessctl set +5%" ""
"dwl-screenshot region" "dwl-screenshot full" "dwl-wallpaper --menu" "dwl-wallpaper --next"
"foot dwl-wallpaper --fetch" "dwl-wallpaper --menu"
"" "foot nmtui" "foot bluetoothctl" "blueman-manager"
"foot yazi" "foot btop" "foot calc" "gsimplecal" "foot claude"
"swaylock -f" "wlogout" "pkill -x gammastep || (gammastep -O 3500 &)"
"foot sh -c 'paru -Syu; echo DONE; read -r _'" "foot sh -c 'dwl-rebuild; echo DONE; read -r _'"
"" "" ""
)
menu="$(for i in "${!NAMES[@]}"; do printf '(%d) %s\n' "$i" "${NAMES[$i]}"; done)"
sel="$(printf '%s\n' "$menu" | wmenu -l 20 -p "help (type to search)")" || exit 0
[[ -n "$sel" ]] || exit 0
n="${sel%%)*}"; n="${n#(}"
cmd="${CMDS[$n]:-}"
if [[ -z "$cmd" ]]; then
  notify-send "help" "${NAMES[$n]}" 2>/dev/null || echo "${NAMES[$n]}"
else
  # shellcheck disable=SC2086
  $cmd & disown 2>/dev/null
fi
EOF
  cat <<'EOF' | theme_write 755 "$HOME/.local/bin/dwl-screenshot"
#!/usr/bin/env bash
# dwl-screenshot region|full - grim + slurp -> satty (annotate, then save)
set -uo pipefail
case "${1:-region}" in
  region) grim -g "$(slurp)" - | satty -f - ;;
  full)   grim - | satty -f - ;;
esac
EOF
  cat <<'EOF' | theme_write 755 "$HOME/.local/bin/dwl-quick"
#!/usr/bin/env bash
# dwl-quick - quick settings menu (Super+X): brightness, volume, night light, screenshots, power.
set -uo pipefail
notify() { notify-send "$1" "$2" 2>/dev/null || true; }
night() {
  if pgrep -x gammastep >/dev/null 2>&1; then pkill -x gammastep; notify "Night light" "off"
  else gammastep -O 3500 & disown; notify "Night light" "on (3500K)"; fi
}
sel=$(printf '%s\n' \
  "☀  Brightness +5%" "☀  Brightness -5%" \
  "🔊 Volume up" "🔊 Volume down" "🔇 Mute" \
  "🌐 Ethernet status" "🌐 Network settings (nmtui)" \
  "🔵 Bluetooth on/off" "🔵 Bluetooth manager" \
  "🌙 Night light on/off" \
  "📷 Region screenshot" "🖥  Full screenshot" \
  "🖼  Next wallpaper" "🖼  Wallpaper picker" \
  "🔒 Lock" "⏻ Power menu" \
  | wmenu -l 16 -p "quick settings")
case "$sel" in
  "☀  Brightness +5%") brightnessctl set +5% ;;
  "☀  Brightness -5%") brightnessctl set 5%- ;;
  "🔊 Volume up")      swayosd-client --output-volume raise ;;
  "🔊 Volume down")    swayosd-client --output-volume lower ;;
  "🔇 Mute")           swayosd-client --output-volume mute-toggle ;;
  "🌐 Ethernet status") notify "network" "$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | tr '\n' ' ')" ;;
  "🌐 Network settings (nmtui)") foot nmtui & disown ;;
  "🔵 Bluetooth on/off")
    if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then bluetoothctl power off; notify "bluetooth" "off"
    else bluetoothctl power on; notify "bluetooth" "on"; fi ;;
  "🔵 Bluetooth manager") blueman-manager & disown ;;
  "🌙 Night light on/off") night ;;
  "📷 Region screenshot") dwl-screenshot region ;;
  "🖥  Full screenshot")   dwl-screenshot full ;;
  "🖼  Next wallpaper")    dwl-wallpaper --next ;;
  "🖼  Wallpaper picker")  dwl-wallpaper --menu ;;
  "🔒 Lock")           swaylock -f ;;
  "⏻ Power menu")      wlogout 2>/dev/null || systemctl poweroff -i ;;
esac
EOF

  # ---- greeter theme (tuigreet: hidden time/status, dracula colors, minimal) ----
  write_root /etc/tuigreet/config.toml <<EOF
# tuigreet theme - written by arch-dwl-setup.sh (theme: $THEME)
[display]
show_time = false
issue = false
[layout]
width = 48
window_padding = 2
container_padding = 1
prompt_padding = 1
[layout.widgets]
time_position = "hidden"
status_position = "hidden"
[secret]
mode = "characters"
characters = "*"
[theme]
border = "$ANSI_BORDER"
text = "$ANSI_TEXT"
container = "$ANSI_CONTAINER"
prompt = "$ANSI_PROMPT"
input = "$ANSI_INPUT"
action = "$ANSI_ACTION"
button = "$ANSI_BUTTON"
EOF

  # ---- GRUB theme (if GRUB + the dracula grub package installed) ----
  if pacman -Q dracula-grub-theme-git >/dev/null 2>&1 && [[ -f /etc/default/grub ]]; then
    if [[ -f /usr/share/grub/themes/dracula/theme.txt ]] && ! grep -q '^GRUB_THEME=' /etc/default/grub; then
      sudo cp -n /etc/default/grub /etc/default/grub.bak-dwlsetup
      echo 'GRUB_THEME="/usr/share/grub/themes/dracula/theme.txt"' | sudo tee -a /etc/default/grub >/dev/null
      NEEDS_GRUB_REGEN=1
      info "GRUB themed (dracula)"
    fi
  fi

  fc-cache -f >/dev/null 2>&1
}

# ------------------------------------------------------- 12. codecs / video ---
set_default_app() {  # set_default_app foo.desktop mime1 mime2 ...
  local desktop="$1"; shift
  [[ -e "/usr/share/applications/$desktop" ]] || return 0
  xdg-mime default "$desktop" "$@" 2>/dev/null || true
}

phase_codecs() {
  log "Codecs, hardware video decode, media players"
  # ffmpeg (Arch's build) already links x264/x265/dav1d/libaom/svt-av1/libvpx/opus/etc. and has
  # VA-API + Vulkan hwaccels. The VA-API *driver* now ships inside 'mesa' itself:
  # libva-mesa-driver was merged into mesa in late 2024, so there is nothing extra to install.
  inst "${P_CODECS[@]}"
  [[ "$WITH_DISC_DECRYPT" == "1" ]] && inst "${P_CODECS_DISC[@]}"
  [[ "$WITH_VLC" == "1" ]]          && inst "${P_VLC[@]}"
  [[ "$WITH_BROWSER" == "1" ]]      && inst "${P_BROWSER[@]}"

  write_user_if_absent "$HOME/.config/mpv/mpv.conf" <<'EOF'
# Starter written once by arch-dwl-setup.sh (see the book, chapter "Video, codecs and colour").
# libplacebo renderer on Vulkan: the best-quality path on AMD + Wayland.
vo=gpu-next
gpu-api=vulkan
# auto-safe picks VA-API on AMD and falls back to software cleanly.
hwdec=auto-safe
# Lock frame pacing to the display refresh rate (smoothest playback).
video-sync=display-resample
interpolation=no
ao=pipewire
keep-open=yes
save-position-on-quit=yes
#
# ---- colour management / your LG 24G411A-B (23.8" IPS, ~99% sRGB) -----------
# This panel is plain sRGB, 8-bit, ~250 nits, 120/144 Hz. It accepts an HDR10
# signal but is NOT an HDR panel - keep HDR OFF in the monitor's OSD.
#  * sRGB panel -> no icc-profile needed (mpv already targets sRGB for SDR).
#  * 120 Hz = 24 fps x 5 exactly -> films play without judder at 120 Hz.
#  * if you ever get a wide-gamut monitor, uncomment:
#icc-profile=~/.local/share/icc/monitor.icc
#icc-profile-auto=yes
EOF

  mkdir -p "$HOME/.local/share/icc"
  set_default_app mpv.desktop video/mp4 video/x-matroska video/webm video/x-msvideo video/quicktime \
                              video/mpeg video/x-flv audio/flac audio/mpeg audio/ogg audio/x-opus+ogg
}

# ------------------------------------------------------------- 13. office ----
phase_office() {
  log "Office: AbiWord + Gnumeric + zathura (PDF/ebooks/comics) + presenterm + PDF toolkit"
  # Deliberately NOT LibreOffice (~1 GB installed). AbiWord ~22 MB, Gnumeric ~46 MB.
  inst "${P_OFFICE[@]}"
  inst_groups "${A_OFFICE[@]}"   # zathura-epub-mupdf (ebooks)
  fc-cache -f >/dev/null 2>&1
  set_default_app zathura.desktop application/pdf application/epub+zip application/x-cbz
  set_default_app abiword.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document \
                  application/msword application/vnd.oasis.opendocument.text application/rtf
  set_default_app gnumeric.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet \
                  application/vnd.ms-excel application/vnd.oasis.opendocument.spreadsheet text/csv
  info "PDF toolkit (no more online converters):"
  info "  split: qpdf in.pdf --pages . 1-5 -- out.pdf | merge: qpdf a.pdf b.pdf --pages . 1-5 . 1-3 -- out.pdf"
  info "  extract images: pdfimages -png doc.pdf prefix | merge images: magick *.png out.pdf"
  info "  pdfseparate/pdfunite (poppler), mutool clean/convert, zathura for ebooks+comics, xournalpp to annotate/sign"
}

# ================================================ --check-packages (dry run) ==
PKG_ARRAYS=(P_SECURITY P_AMD P_BASE P_DWL_DEPS P_CODECS P_VISUAL P_QOL P_FONTS P_OFFICE P_APPS P_GAMING P_TORRENT P_DOCKER P_SESSION P_SNAP)
GRP_ARRAYS=(A_VISUAL A_QOL A_FONTS A_OFFICE A_APPS A_GAMING A_TORRENT A_THEME A_DOCKER A_SNAP)
OPT_ARRAYS=(P_CODECS_DISC P_VLC P_BROWSER)

pkg_source() {  # echoes repo|aur|provided|missing
  local p="$1"
  if pacman -Si "$p" >/dev/null 2>&1; then echo repo
  elif command -v paru >/dev/null && paru -Si "$p" >/dev/null 2>&1; then echo aur
  elif pacman -Sp "$p" >/dev/null 2>&1; then echo provided
  else echo missing; fi
}

check_command_coverage() {
  # Every command the keybinds and helper scripts call must resolve to an
  # installable package (repo/AUR) - catches typos and renamed packages early.
  # NPM:/SRC: entries are special-cased (not pacman packages).
  log "Critical command coverage"
  local entry cmd pkg src miss=0
  local -a map=(
    "swayosd-client:swayosd" "brightnessctl:brightnessctl"
    "grim:grim" "slurp:slurp" "satty:satty" "wf-recorder:wf-recorder"
    "wmenu:wmenu" "rofi:rofi" "foot:foot" "mako:mako" "waybar:waybar"
    "nmcli:networkmanager" "nmtui:networkmanager" "bluetoothctl:bluez-utils" "blueman-manager:blueman"
    "playerctl:playerctl" "pavucontrol:pavucontrol" "pamixer:pamixer"
    "wl-copy:wl-clipboard" "wl-paste:wl-clipboard" "cliphist:cliphist"
    "swayidle:swayidle" "swaylock:swaylock" "udiskie:udiskie"
    "hyprpolkitagent:hyprpolkitagent" "hyprpicker:hyprpicker"
    "wlr-randr:wlr-randr" "wttrbar:wttrbar|A" "awww:awww|A"
    "mpv:mpv" "ffmpeg:ffmpeg" "ffprobe:ffmpeg" "yt-dlp:yt-dlp" "mediainfo:mediainfo"
    "mkvmerge:mkvtoolnix-cli" "mkvextract:mkvtoolnix-cli" "mkvinfo:mkvtoolnix-cli"
    "gst-inspect-1.0:gstreamer" "gst-launch-1.0:gstreamer"
    "abiword:abiword" "ssconvert:gnumeric" "zathura:zathura" "xournalpp:xournalpp" "presenterm:presenterm"
    "qpdf:qpdf" "mutool:mupdf-tools" "pdfimages:poppler"
    "magick:imagemagick" "montage:imagemagick" "chafa:chafa" "imv:imv"
    "oxipng:oxipng" "jpegoptim:jpegoptim" "fastfetch:fastfetch" "calc:calc"
    "zstd:zstd" "pigz:pigz" "aunpack:atool" "gsimplecal:gsimplecal"
    "aria2c:aria2" "prowlarr:prowlarr-bin|A"
    "steam:steam" "gamescope:gamescope" "gamemoderun:gamemode" "mangohud:mangohud" "goverlay:goverlay"
    "protontricks:protontricks" "winetricks:winetricks"
    "solaar:solaar" "ratbagctl:libratbag" "openrgb:openrgb" "liquidctl:liquidctl"
    "easyeffects:easyeffects" "gammastep:gammastep" "batsignal:batsignal"
    "nvim:neovim" "lazygit:lazygit" "node:nodejs" "npm:nodejs" "jq:jq" "curl:curl" "git:git"
    "wlogout:wlogout|A" "localsend_app:localsend-bin|A" "tclock:clock-tui|A"
    "superseedr:superseedr-bin|A" "syncplay-nogui:syncplay-nogui|A" "spotatui:spotatui-bin|A" "endcord:endcord|A"
    "docker:docker" "timeshift:timeshift" "greetd:greetd" "tuigreet:greetd-tuigreet"
    "claude:NPM:nodejs" "dwl:SRC:built by the dwl phase" "dwl-rebuild:SRC:built by the dwl phase"
    "dwl-wallpaper:SRC:written by the theme phase" "dwl-quick:SRC:written by the theme phase"
    "dwl-screenshot:SRC:written by the theme phase" "dwl-help:SRC:written by the theme phase"
  )
  for entry in "${map[@]}"; do
    cmd="${entry%%:*}"; pkg="${entry#*:}"
    if [[ "$pkg" == NPM:* ]]; then
      src="$(pkg_source "${pkg#NPM:}")"
      [[ "$src" == missing ]] && { printf '  \033[31mFAIL\033[0m %s needs npm package host %s (missing)\n' "$cmd" "${pkg#NPM:}"; miss=$((miss+1)); } \
        || printf '  \033[32mOK\033[0m   %-22s via npm (host %s present)\n' "$cmd" "${pkg#NPM:}"
      continue
    fi
    if [[ "$pkg" == SRC:* ]]; then printf '  \033[36msrc\033[0m   %-22s %s\n' "$cmd" "${pkg#SRC:}"; continue; fi
    if [[ "$pkg" == *"|A" ]]; then
      pkg="${pkg%|A}"
      src="$(pkg_source "$pkg")"
      if [[ "$src" == missing ]]; then
        # try AUR explicitly (pkg_source already does, but be explicit for groups)
        if command -v paru >/dev/null && paru -Si "$pkg" >/dev/null 2>&1; then src="aur"; fi
      fi
    else
      src="$(pkg_source "$pkg")"
    fi
    if [[ "$src" == missing ]]; then printf '  \033[31mFAIL\033[0m %s <- %s NOT FOUND\n' "$cmd" "$pkg"; miss=$((miss+1))
    else printf '  \033[32mOK\033[0m   %-22s <- %s (%s)\n' "$cmd" "$pkg" "$src"; fi
  done
  log "Command coverage: $miss missing provider(s)"
  return $((miss > 0))
}

check_packages() {
  command -v pacman >/dev/null || die "pacman not found - run this on Arch."
  local have_paru=0; command -v paru >/dev/null && have_paru=1
  local -a repo_pkgs=() aur_pkgs=()
  local missing=0 n=0 src arr name g c found

  log "Package availability + dependency pre-check (installs nothing)"
  info "sync DB age: $(date -r /var/lib/pacman/sync/extra.db '+%F %R' 2>/dev/null || echo unknown). Run 'sudo pacman -Syu' first for a fresh answer."
  local dbage=999999999
  [[ -f /var/lib/pacman/sync/extra.db ]] && dbage=$(($(date +%s) - $(stat -c %Y /var/lib/pacman/sync/extra.db)))
  (( dbage > 14*86400 )) && warn "sync DBs are over 14 days old (or missing) - run 'sudo pacman -Sy' first or every result above is suspect"
  ((have_paru)) || warn "paru not installed yet: AUR packages can't be checked until it is (run the real script once, SKIP=everything-but-paru works)."

  for arr in "${PKG_ARRAYS[@]}" "${OPT_ARRAYS[@]}"; do
    local -n ref="$arr"
    for name in "${ref[@]}"; do
      n=$((n+1)); src="$(pkg_source "$name")"
      case "$src" in
        repo)     repo_pkgs+=("$name"); printf '  \033[32mrepo    \033[0m %-44s [%s]\n' "$name" "$arr" ;;
        aur)      aur_pkgs+=("$name");  printf '  \033[33mAUR     \033[0m %-44s [%s]\n' "$name" "$arr" ;;
        provided) repo_pkgs+=("$name"); printf '  \033[32mprovided\033[0m %-44s [%s]\n' "$name" "$arr" ;;
        *)        missing=$((missing+1)); printf '  \033[31mMISSING \033[0m %-44s [%s]\n' "$name" "$arr" ;;
      esac
    done
    unset -n ref
  done

  for arr in "${GRP_ARRAYS[@]}"; do
    local -n gref="$arr"
    for g in "${gref[@]}"; do
      n=$((n+1)); found=""
      IFS='|' read -ra cands <<<"$g"
      for c in "${cands[@]}"; do
        src="$(pkg_source "$c")"
        if [[ "$src" != missing ]]; then
          found="$c"; [[ "$src" == aur ]] && aur_pkgs+=("$c") || repo_pkgs+=("$c"); break
        fi
      done
      if [[ -n "$found" ]]; then printf '  \033[36mgroup   \033[0m %-44s -> %s [%s]\n' "$g" "$found" "$arr"
      else missing=$((missing+1)); printf '  \033[31mMISSING \033[0m %-44s (no candidate found) [%s]\n' "$g" "$arr"; fi
    done
    unset -n gref
  done

  local u
  for g in "${A_UNVERIFIED[@]}"; do
    IFS='|' read -ra cands <<<"$g"; found=""
    for u in "${cands[@]}"; do [[ "$(pkg_source "$u")" != missing ]] && { found="$u"; break; }; done
    if [[ -n "$found" ]]; then printf '  \033[36moptional\033[0m %-44s -> %s exists (WITH_UNVERIFIED=1 would install it)\n' "$g" "$found"
    else printf '  \033[90moptional\033[0m %-44s not found (skipped by default)\n' "$g"; fi
  done
  local w
  for w in wlroots0.20 wlroots0.19 wlroots0.18 wlroots; do
    [[ "$(pkg_source "$w")" != missing ]] && printf '  \033[36mwlroots \033[0m %-44s available (dwl picks the one it needs)\n' "$w"
  done

  log "Dependency resolution for official-repo packages"
  local out rc
  out="$(pacman -Sp --needed --print-format '%n %s' "${repo_pkgs[@]}" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '  \033[32mOK\033[0m   resolvable: %s packages to install, ~%s MiB to download (excludes already-installed)\n' \
      "$(grep -c . <<<"$out")" "$(awk '{s+=$2} END{printf "%.0f", s/1048576}' <<<"$out")"
  else
    printf '  \033[31mFAIL\033[0m dependency/conflict problem:\n%s\n' "$(sed 's/^/        /' <<<"$out")"; missing=$((missing+1))
  fi

  if ((have_paru && ${#aur_pkgs[@]})); then
    log "Dependency check for AUR packages (depends must exist in repos or AUR)"
    local p d deps bad
    for p in "${aur_pkgs[@]}"; do
      deps="$(paru -Si "$p" 2>/dev/null | awk -F': *' '/^Depends On/{print $2}')"
      bad=""
      for d in $deps; do
        [[ "$d" == None ]] && continue
        d="${d%%[<>=]*}"; d="${d%%:*}"
        [[ "$(pkg_source "$d")" == missing ]] && bad+=" $d"
      done
      if [[ -z "$bad" ]]; then printf '  \033[32mOK\033[0m   %s\n' "$p"
      else printf '  \033[31mFAIL\033[0m %s: unresolvable depends:%s\n' "$p" "$bad"; missing=$((missing+1)); fi
    done
  fi

  log "Summary: $n entries checked, $missing problem(s)"
  check_command_coverage || missing=$((missing+1))
  ((missing == 0))
}

# ========================================================= --verify (tests) ==
T_PASS=0; T_FAIL=0; T_WARN=0; T_SKIP=0; VERIFY_FAILS=()
t_head() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
t_pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; T_PASS=$((T_PASS+1)); }
t_fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; T_FAIL=$((T_FAIL+1)); VERIFY_FAILS+=("$*"); }
t_warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; T_WARN=$((T_WARN+1)); }
t_skip() { printf '  \033[90mSKIP\033[0m  %s\n' "$*"; T_SKIP=$((T_SKIP+1)); }
t_ok()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then t_pass "$d"; else t_fail "$d"; fi; }
need() {  # verify-section guard: skip the whole section when a required phase was skipped
  local p
  for p in "$@"; do
    if skip "$p"; then t_skip "section needs phase '$p' (skipped)"; return 1; fi
  done
  return 0
}

verify_packages() {
  t_head "Packages installed (dependencies satisfied)"
  local phase arr p g c ok
  declare -A MAP=([P_SECURITY]=security [P_AMD]=amd [P_BASE]=base [P_DWL_DEPS]=dwl [P_CODECS]=codecs
    [P_VISUAL]=visual [P_QOL]=qol [P_FONTS]=fonts [P_OFFICE]=office [P_APPS]=apps [P_GAMING]=gaming
    [P_TORRENT]=torrent [P_DOCKER]=docker [P_SESSION]=session [P_SNAP]=snapshots
    [A_VISUAL]=visual [A_QOL]=qol [A_FONTS]=fonts [A_OFFICE]=office [A_APPS]=apps [A_GAMING]=gaming [A_TORRENT]=torrent
    [A_THEME]=theme [A_DOCKER]=docker [A_SNAP]=snapshots)
  local -a todo=("${PKG_ARRAYS[@]}" "${GRP_ARRAYS[@]}")
  [[ "$WITH_DISC_DECRYPT" == 1 ]] && { MAP[P_CODECS_DISC]=codecs; todo+=(P_CODECS_DISC); }
  [[ "$WITH_VLC" == 1 ]]          && { MAP[P_VLC]=codecs; todo+=(P_VLC); }
  [[ "$WITH_BROWSER" == 1 ]]      && { MAP[P_BROWSER]=codecs; todo+=(P_BROWSER); }
  local root_btrfs=0; [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs ]] && root_btrfs=1
  for arr in "${todo[@]}"; do
    phase="${MAP[$arr]}"
    if skip "$phase"; then continue; fi
    if [[ "$phase" == snapshots && $root_btrfs -eq 0 ]]; then continue; fi
    local -n ref="$arr"
    for p in "${ref[@]}"; do
      if [[ "$arr" == A_* ]]; then
        ok=""; IFS='|' read -ra cands <<<"$p"
        for c in "${cands[@]}"; do pacman -T "$c" >/dev/null 2>&1 && { ok="$c"; break; }; done
        if [[ -n "$ok" ]]; then t_pass "$ok  (from group $p)"
        elif [[ "$arr" == A_APPS ]]; then t_warn "none of [$p] installed (niche AUR app; see summary)"
        else t_fail "none of [$p] installed"; fi
      else
        if pacman -T "$p" >/dev/null 2>&1; then t_pass "$p"; else t_fail "$p is NOT installed"; fi
      fi
    done
    unset -n ref
  done
}

ldd_clean() {  # no unresolved shared libraries
  local f; f="$(command -v "$1" 2>/dev/null)" || return 1
  head -c4 "$f" 2>/dev/null | grep -q 'ELF' || return 0
  ! ldd "$f" 2>&1 | grep -q 'not found'
}

verify_binaries() {
  t_head "Binaries on PATH, with no broken shared-library links"
  local b
  local -a bins=()
  bins_if() { local ph="$1"; shift; skip "$ph" || bins+=("$@"); }
  # Each binary is only expected when its phase ran - a skipped phase must
  # never produce FAILs.
  bins_if security ufw
  bins_if amd vainfo vulkaninfo
  bins_if dwl dwl
  bins_if base wl-copy wl-paste wlr-randr pamixer playerctl pavucontrol nmcli nmtui bluetoothctl blueman-manager
  bins_if codecs ffmpeg ffprobe mpv mediainfo yt-dlp mkvmerge mkvinfo
  bins_if visual waybar rofi foot mako swayosd-server starship eza bat fd rg zoxide fzf zsh
  bins_if qol udiskie yazi cliphist grim slurp satty wf-recorder hyprpicker swayidle swaylock btop \
    imv chafa fastfetch oxipng jpegoptim calc zstd pigz aunpack gammastep liquidctl openrgb easyeffects gsimplecal wlogout
  bins_if office abiword gnumeric ssconvert zathura xournalpp presenterm qpdf mutool pdfimages
  bins_if apps nvim solaar ratbagctl
  bins_if gaming gamemoderun gamescope mangohud steam
  bins_if torrent aria2c
  [[ "$WITH_BROWSER" == 1 ]] && ! skip codecs && bins+=(firefox)
  [[ "$WITH_AI" == 1 ]] && ! skip ai && bins+=(claude)
  skip docker || bins+=(docker)
  for b in "${bins[@]}"; do
    if ! command -v "$b" >/dev/null 2>&1; then t_fail "$b not found in PATH"
    elif ! ldd_clean "$b"; then t_fail "$b has unresolved libraries"
    else t_pass "$b"; fi
  done
  if ! skip apps; then
    if command -v localsend_app >/dev/null || command -v localsend >/dev/null; then t_pass "localsend"; else t_fail "localsend not found in PATH"; fi
  else t_skip "localsend (apps phase skipped)"; fi
  if ! skip visual; then
    if command -v awww-daemon >/dev/null || command -v swww-daemon >/dev/null; then t_pass "wallpaper daemon (awww/swww)"; else t_fail "no wallpaper daemon (awww-daemon / swww-daemon)"; fi
  else t_skip "wallpaper daemon (visual phase skipped)"; fi
  skip dwl || { [[ -x /usr/local/bin/dwl ]] && t_pass "dwl installed to /usr/local/bin" || t_fail "/usr/local/bin/dwl missing"; }
}

verify_files() {
  t_head "Config + session files"
  local f
  if ! skip session; then
    for f in /usr/local/bin/start-dwl /usr/share/wayland-sessions/dwl.desktop /etc/greetd/config.toml; do
      [[ -e "$f" ]] && t_pass "$f" || t_fail "$f missing"
    done
    bash -n /usr/local/bin/start-dwl 2>/dev/null || sh -n /usr/local/bin/start-dwl 2>/dev/null \
      && t_pass "start-dwl parses" || t_fail "start-dwl has a syntax error"
  else t_skip "session files (phase skipped)"; fi
  if ! skip dwl; then
    [[ -e /usr/local/bin/dwl-rebuild ]] && t_pass "/usr/local/bin/dwl-rebuild" || t_fail "dwl-rebuild missing"
    [[ -e /etc/pacman.d/hooks/dwl-rebuild.hook ]] && t_pass "dwl rebuild hook file" || t_fail "dwl rebuild hook missing"
  else t_skip "dwl files (phase skipped)"; fi
  if ! skip security; then
    [[ -e /etc/sysctl.d/99-hardening.conf ]] && t_pass "/etc/sysctl.d/99-hardening.conf" || t_fail "sysctl conf missing"
  else t_skip "security files (phase skipped)"; fi
  for f in "$HOME/.config/dwl/autostart.sh" "$HOME/.config/fontconfig/conf.d/99-arabic.conf" \
           "$HOME/.config/xdg-desktop-portal/portals.conf" "$HOME/.config/mpv/mpv.conf"; do
    [[ -e "$f" ]] && t_pass "$f" || t_warn "$f missing (skipped phase, or you removed it)"
  done
  if ! skip pacman; then
    grep -q '^\[multilib\]' /etc/pacman.conf && t_pass "[multilib] enabled" || t_fail "[multilib] not enabled"
    grep -q '^ParallelDownloads' /etc/pacman.conf && t_pass "pacman ParallelDownloads set" || t_warn "ParallelDownloads not set"
  else t_skip "pacman.conf checks (phase skipped)"; fi
}

verify_services() {
  t_head "Services"
  local u
  for u in fstrim.timer paccache.timer; do
    if skip pacman; then t_skip "$u (pacman phase skipped)"
    elif systemctl is-enabled "$u" >/dev/null 2>&1; then t_pass "$u enabled"; else t_fail "$u not enabled"; fi
  done
  if skip services; then t_skip "greetd.service (services phase skipped)"
  elif systemctl is-enabled greetd.service >/dev/null 2>&1; then t_pass "greetd.service enabled"; else t_fail "greetd.service not enabled"; fi
  for u in NetworkManager.service bluetooth.service; do
    if skip base; then t_skip "$u (base phase skipped)"
    elif systemctl is-enabled "$u" >/dev/null 2>&1; then t_pass "$u enabled"; else t_fail "$u not enabled"; fi
  done
  if skip security; then t_skip "ufw.service (security phase skipped)"
  elif systemctl is-active --quiet ufw.service; then t_pass "ufw.service active"; else t_fail "ufw.service not active"; fi
  if skip security; then t_skip "ufw rules (security phase skipped)"
  elif sudo -n true 2>/dev/null; then
    sudo -n ufw status verbose 2>&1 | grep -q 'deny (incoming)' && t_pass "ufw default: deny incoming" || t_fail "ufw not denying incoming"
  else t_skip "ufw rules (needs sudo; run: sudo ufw status verbose)"; fi
  if skip base; then t_skip "pipewire units (base phase skipped)"
  else
    for u in pipewire.socket pipewire-pulse.socket wireplumber.service; do
      systemctl --global is-enabled "$u" >/dev/null 2>&1 && t_pass "$u enabled for all users" || t_fail "$u not enabled globally"
    done
  fi
  if skip amd; then t_skip "lactd (amd phase skipped)"
  else systemctl is-enabled lactd.service >/dev/null 2>&1 && t_pass "lactd.service enabled" || t_warn "lactd.service not enabled"; fi
  if [[ "$WITH_TORRENT" == 1 ]] && ! skip torrent; then
    systemctl is-enabled prowlarr.service >/dev/null 2>&1 && t_pass "prowlarr.service enabled" || t_warn "prowlarr.service not enabled (torrent search won't run)"
  else t_skip "prowlarr.service (torrent disabled or skipped)"; fi
  if skip services; then t_skip "display-manager check (services phase skipped)"
  else
    local dm; dm="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)"
    [[ "$dm" == *greetd* ]] && t_pass "display-manager -> greetd" || t_warn "display-manager points to: ${dm:-nothing}"
  fi
  if skip security; then t_skip "sysctl check (security phase skipped)"
  elif [[ "$(sysctl -n kernel.kptr_restrict 2>/dev/null)" == 2 ]]; then t_pass "sysctl hardening live (kptr_restrict=2)"
  else t_fail "sysctl hardening not applied"; fi
}

verify_gpu() {
  need amd || return 0
  t_head "GPU, Vulkan, VA-API"
  lsmod | grep -q '^amdgpu' && t_pass "amdgpu kernel module loaded" || t_fail "amdgpu not loaded (rebooted into the new kernel?)"
  compgen -G '/dev/dri/renderD*' >/dev/null && t_pass "render nodes: $(echo /dev/dri/renderD* | tr '\n' ' ')" || t_fail "no /dev/dri/renderD* nodes"
  if command -v vulkaninfo >/dev/null; then
    local vk; vk="$(vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName' | sort -u | tr -s ' ' | tr '\n' ';')"
    if grep -qi radv <<<"$vk"; then t_pass "Vulkan via RADV: $vk"; else t_fail "Vulkan: RADV not detected ($vk)"; fi
  fi
  local pm; pm="/sys/module/amdgpu/parameters/ppfeaturemask"
  if [[ "$WITH_PPFEATUREMASK" == 1 ]]; then
    if [[ -r "$pm" ]] && [[ "$(cat "$pm")" == 4294967295 || "$(cat "$pm")" == 0xffffffff ]]; then t_pass "ppfeaturemask active (overclock controls unlocked)"
    elif grep -qs 'amdgpu.ppfeaturemask' /etc/default/grub /boot/loader/entries/*.conf /efi/loader/entries/*.conf 2>/dev/null; then t_warn "ppfeaturemask configured but not active yet - REBOOT"
    else t_warn "ppfeaturemask not found in bootloader config"; fi
  fi
  HWNODE=""
  local node out prof
  for node in /dev/dri/renderD*; do
    [[ -e "$node" ]] || continue
    out="$(vainfo --display drm --device "$node" 2>&1)"
    if grep -q 'VAProfile' <<<"$out"; then
      t_pass "VA-API works on $node: $(grep -m1 'Driver version' <<<"$out" | sed 's/.*Driver version: //')"
      for prof in H264 HEVCMain HEVCMain10 VP9Profile0 VP9Profile2 AV1Profile0; do
        grep -q "VAProfile${prof}.*VAEntrypointVLD" <<<"$out" && t_pass "   $node hardware decode: $prof" || t_warn "   $node: no hardware decode for $prof"
      done
      HWNODE="$node"
    else t_warn "VA-API did not initialise on $node"; fi
  done
  [[ -n "$HWNODE" ]] || t_fail "No working VA-API device: hardware video decode will not work"
}

verify_codecs() {
  need codecs || return 0
  t_head "Codecs built into ffmpeg"
  command -v ffmpeg >/dev/null || { t_fail "ffmpeg missing"; return; }
  local encs decs hwa x
  encs="$(ffmpeg -hide_banner -encoders 2>/dev/null)"; decs="$(ffmpeg -hide_banner -decoders 2>/dev/null)"; hwa="$(ffmpeg -hide_banner -hwaccels 2>/dev/null)"
  for x in libx264 libx265 libsvtav1 libaom-av1 libvpx-vp9 libopus libmp3lame flac wavpack libjxl libwebp libopenjpeg; do
    grep -qE "[[:space:]]${x}[[:space:]]" <<<"$encs" && t_pass "encoder $x" || t_fail "encoder $x missing"
  done
  for x in h264 hevc av1 libdav1d vp9 mpeg2video mpeg4 vc1 prores ac3 eac3 dca truehd opus flac wavpack aac theora; do
    grep -qE "[[:space:]]${x}[[:space:]]" <<<"$decs" && t_pass "decoder $x" || t_fail "decoder $x missing"
  done
  for x in jpeg2000 webp mjpeg; do
    grep -qE "[[:space:]]${x}[[:space:]]" <<<"$decs" && t_pass "image decoder $x" || t_fail "image decoder $x missing"
  done
  for x in vaapi vulkan; do grep -qw "$x" <<<"$hwa" && t_pass "ffmpeg hwaccel $x" || t_fail "ffmpeg hwaccel $x missing"; done

  t_head "Real decode tests (software vs. hardware VA-API)"
  local d name f t0 t1 err rc fps
  d="$(mktemp -d)"
  gen() { local n="$1"; shift; ffmpeg -v error -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=3" "$@" "$d/$n" 2>/dev/null; }
  gen h264.mp4   -c:v libx264 -preset ultrafast -pix_fmt yuv420p
  gen hevc8.mp4  -c:v libx265 -preset ultrafast -pix_fmt yuv420p -x265-params log-level=error
  gen hevc10.mp4 -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le -x265-params log-level=error
  gen vp9.webm   -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -pix_fmt yuv420p
  gen av1.mkv    -c:v libsvtav1 -preset 12 -pix_fmt yuv420p || gen av1.mkv -c:v libaom-av1 -cpu-used 8 -usage realtime -pix_fmt yuv420p
  for name in h264.mp4 hevc8.mp4 hevc10.mp4 vp9.webm av1.mkv; do
    f="$d/$name"
    [[ -s "$f" ]] || { t_warn "could not generate test clip $name"; continue; }
    t0=$(date +%s.%N); ffmpeg -v error -i "$f" -f null - 2>/dev/null; rc=$?; t1=$(date +%s.%N)
    fps="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.0f", 90/(b-a)}')"
    [[ $rc -eq 0 ]] && t_pass "software decode $name (~${fps} fps incl. startup)" || t_fail "software decode failed: $name"
    if [[ -z "${HWNODE:-}" ]]; then t_skip "hardware decode $name (no VA-API device)"; continue; fi
    t0=$(date +%s.%N)
    err="$(ffmpeg -v error -hwaccel vaapi -hwaccel_device "$HWNODE" -hwaccel_output_format vaapi -i "$f" -f null - 2>&1)"; rc=$?
    t1=$(date +%s.%N); fps="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.0f", 90/(b-a)}')"
    if [[ $rc -eq 0 ]] && ! grep -qiE 'failed setup|hwaccel initialisation|no usable' <<<"$err"; then t_pass "HARDWARE decode $name on $HWNODE (~${fps} fps incl. startup)"
    else t_fail "hardware decode FAILED for $name: $(head -1 <<<"$err")"; fi
  done

  t_head "Image codec round trips (real encode -> decode)"
  local img
  ffmpeg -v error -y -f lavfi -i "testsrc2=size=640x360:rate=1:duration=1" "$d/src.png" 2>/dev/null
  if [[ -s "$d/src.png" ]]; then
    for img in webp jpg jxl jp2; do
      case "$img" in
        webp) ffmpeg -v error -y -i "$d/src.png" -c:v libwebp "$d/rt.webp" 2>/dev/null ;;
        jpg)  ffmpeg -v error -y -i "$d/src.png" -c:v mjpeg "$d/rt.jpg" 2>/dev/null ;;
        jxl)  ffmpeg -v error -y -i "$d/src.png" -c:v libjxl "$d/rt.jxl" 2>/dev/null ;;
        jp2)  ffmpeg -v error -y -i "$d/src.png" -c:v libopenjpeg "$d/rt.jp2" 2>/dev/null ;;
      esac
      if [[ -s "$d/rt.$img" ]] && ffmpeg -v error -y -i "$d/rt.$img" "$d/back-$img.png" 2>/dev/null && [[ -s "$d/back-$img.png" ]]; then
        t_pass "$img: encode + decode round trip"
      else t_fail "$img round trip failed"; fi
    done
  else t_warn "could not generate source image for round trips"; fi

  t_head "MKV tooling round trip (mkvmerge -> mkvextract)"
  if [[ -s "$d/h264.mp4" ]]; then
    mkvmerge -q -o "$d/rt.mkv" "$d/h264.mp4" && [[ -s "$d/rt.mkv" ]] \
      && t_pass "mkvmerge: MP4 -> MKV" || t_fail "mkvmerge failed"
    if [[ -s "$d/rt.mkv" ]]; then
      mkvextract tracks "$d/rt.mkv" 0:"$d/extract.mp4" >/dev/null 2>&1 && [[ -s "$d/extract.mp4" ]] \
        && t_pass "mkvextract: track 0 back out of MKV" || t_fail "mkvextract failed"
    fi
    mediainfo "$d/rt.mkv" >/dev/null 2>&1 && t_pass "mediainfo reads the MKV" || t_warn "mediainfo failed"
  else t_warn "no test clip for MKV round trip"; fi

  t_head "GStreamer pipeline (gst-libav provides ffmpeg codecs)"
  if command -v gst-inspect-1.0 >/dev/null; then
    gst-inspect-1.0 avdec_h264 >/dev/null 2>&1 && t_pass "gst-inspect: avdec_h264 present" || t_fail "avdec_h264 missing (gst-libav not wired)"
    if [[ -s "$d/h264.mp4" ]]; then
      gst-launch-1.0 -q filesrc location="$d/h264.mp4" ! decodebin ! fakesink >/dev/null 2>&1 \
        && t_pass "gst pipeline: decodebin plays the test clip" || t_fail "gst decodebin pipeline failed"
    fi
  else t_fail "gst-inspect-1.0 missing"; fi

  t_head "mpv"
  if command -v mpv >/dev/null; then
    mpv --version 2>/dev/null | grep -qi libplacebo && t_pass "mpv built with libplacebo (gpu-next ready)" || t_warn "mpv version string lacks libplacebo"
    if [[ -z "${HWNODE:-}" ]]; then t_skip "mpv hardware-decode test (no VA-API device)"
    elif [[ -s "$d/h264.mp4" ]]; then
      out="$(mpv --no-config --vo=null --ao=null --hwdec=vaapi-copy --vaapi-device="$HWNODE" --frames=30 --msg-level=vd=v "$d/h264.mp4" 2>&1)"
      grep -q 'Using hardware decoding (vaapi' <<<"$out" && t_pass "mpv hardware-decodes H.264 via VA-API" || t_fail "mpv did not use VA-API hardware decoding"
      out="$(mpv --no-config --vo=null --ao=null --hwdec=vaapi-copy --vaapi-device="$HWNODE" --frames=30 --msg-level=vd=v "$d/av1.mkv" 2>&1)"
      grep -q 'Using hardware decoding (vaapi' <<<"$out" && t_pass "mpv hardware-decodes AV1 via VA-API" || t_warn "mpv did not hardware-decode AV1 (GPU may lack AV1 decode)"
    fi
    if [[ -s "$d/h264.mp4" ]]; then
      out="$(mpv --vo=null --ao=null --frames=1 "$d/h264.mp4" 2>&1)"
      grep -qiE 'error parsing|unknown option|not found' <<<"$out" && t_fail "mpv.conf has an error" || t_pass "your mpv.conf parses cleanly"
    fi
  else t_fail "mpv missing"; fi
  rm -rf "$d"
}

verify_fonts_shell() {
  need fonts || return 0
  t_head "Fonts and shell"
  fc-match 'sans-serif:lang=ar' 2>/dev/null | grep -qiE 'naskh|amiri|scheherazade' \
    && t_pass "Arabic resolves to a proper Arabic face: $(fc-match 'sans-serif:lang=ar')" \
    || t_fail "Arabic does not resolve to an Arabic face: $(fc-match 'sans-serif:lang=ar' 2>&1)"
  fc-list 2>/dev/null | grep -qi 'Noto.*Naskh' && t_pass "Noto Naskh Arabic present" || t_warn "Noto Naskh missing (noto-fonts-extra)"
  fc-list 2>/dev/null | grep -qi 'Amiri' && t_pass "Amiri present" || t_warn "Amiri missing (AUR ttf-amiri)"
  fc-list 2>/dev/null | grep -qi 'Scheherazade' && t_pass "Scheherazade New present" || t_warn "Scheherazade missing"
  fc-list 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd' && t_pass "Nerd Font (JetBrains Mono) present" || t_warn "Nerd Font not found"
  for nf in FiraCodeNerd HackNerd 'CaskaydiaCove Nerd' RobotoMonoNerd UbuntuMonoNerd; do
    fc-list 2>/dev/null | grep -qi "$nf" && t_pass "Nerd variant present: $nf" || t_warn "Nerd variant missing: $nf"
  done
  fc-list 2>/dev/null | grep -qi 'Liberation' && t_pass "Liberation fonts (Arial/Times-compatible) present" || t_warn "Liberation fonts missing"
  grep -q 'XKB_DEFAULT_LAYOUT=.*ara' /usr/local/bin/start-dwl 2>/dev/null \
    && t_pass "Arabic keyboard wired (us,ara, Alt+Shift toggles)" || t_warn "Arabic layout not found in start-dwl"
  fc-list 2>/dev/null | grep -qi 'Carlito' && t_pass "Carlito (Calibri-compatible) present" || t_warn "Carlito missing"
  [[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/zsh ]] && t_pass "login shell is zsh" || t_warn "login shell is not zsh yet"
  if command -v zsh >/dev/null && [[ -f "$HOME/.zshrc" ]]; then
    zsh -i -c exit 2>&1 | grep -qiE 'no such file|command not found' && t_fail "your .zshrc prints errors on startup" || t_pass "your .zshrc loads without errors"
  fi
}

verify_dwl_smoke() {
  need dwl || return 0
  t_head "dwl smoke test (headless backend, 4 seconds)"
  if ! command -v dwl >/dev/null; then t_skip "dwl not installed"; return; fi
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then t_skip "no XDG_RUNTIME_DIR (log in on a TTY, not a bare su/ssh)"; return; fi
  local log; log="$(mktemp)"
  WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 timeout 4 dwl >"$log" 2>&1; local rc=$?
  if [[ $rc -eq 124 ]]; then t_pass "dwl starts, initialises wlroots and keeps running"
  else t_fail "dwl exited early (rc=$rc): $(tail -2 "$log" | tr '\n' ' ')"; fi
  rm -f "$log"
}

verify_office() {
  need office || return 0
  t_head "Office"
  local d; d="$(mktemp -d)"
  if command -v ssconvert >/dev/null; then
    printf 'x,y\n2,3\n4,5\n' >"$d/t.csv"
    ssconvert "$d/t.csv" "$d/t.xlsx" >/dev/null 2>&1 && [[ -s "$d/t.xlsx" ]] && t_pass "Gnumeric: CSV -> XLSX conversion" || t_fail "Gnumeric: CSV -> XLSX failed"
    ssconvert "$d/t.xlsx" "$d/t2.csv" >/dev/null 2>&1 && diff -q "$d/t.csv" "$d/t2.csv" >/dev/null && t_pass "Gnumeric: XLSX round-trip preserves data" || t_fail "Gnumeric: XLSX round-trip differs"
    ssconvert "$d/t.xlsx" "$d/t.pdf" >/dev/null 2>&1 && head -c4 "$d/t.pdf" | grep -q '%PDF' && t_pass "Gnumeric: PDF export" || t_warn "Gnumeric: PDF export failed (may need a display)"
  else t_fail "ssconvert (Gnumeric) missing"; fi
  if command -v abiword >/dev/null; then
    printf 'Hello from AbiWord\n' >"$d/t.txt"
    if timeout 25 abiword --to=pdf --to-name="$d/a.pdf" "$d/t.txt" >/dev/null 2>&1 && head -c4 "$d/a.pdf" 2>/dev/null | grep -q '%PDF'; then t_pass "AbiWord: TXT -> PDF export"
    else t_warn "AbiWord CLI export needs a display session; re-run --verify inside dwl"; fi
  else t_fail "abiword missing"; fi
  command -v zathura >/dev/null && t_pass "zathura present (PDF viewer)" || t_fail "zathura missing"
  [[ -e /usr/lib/zathura/libpdf-mupdf.so ]] && t_pass "zathura PDF plugin (mupdf)" || t_warn "zathura PDF plugin missing"
  [[ -e /usr/lib/zathura/libepub-mupdf.so ]] && t_pass "zathura EPUB plugin (ebooks)" || t_warn "zathura EPUB plugin missing (zathura-epub-mupdf from AUR)"
  ls /usr/lib/zathura/ 2>/dev/null | grep -q cb && t_pass "zathura comic-book plugin (cbz)" || t_warn "zathura cb plugin missing"
  command -v xournalpp >/dev/null && t_pass "xournalpp present (annotate + sign PDFs)" || t_fail "xournalpp missing"
  command -v presenterm >/dev/null && t_pass "presenterm present (terminal slides)" || t_fail "presenterm missing"

  t_head "PDF toolkit round trips"
  if command -v qpdf >/dev/null; then
    # build a 3-page PDF, split, re-merge
    if command -v magick >/dev/null; then
      magick -size 400x300 xc:white -fill black -pointsize 40 -gravity center -annotate 0 "P1" "$d/p1.png" 2>/dev/null
      magick -size 400x300 xc:white -fill black -pointsize 40 -gravity center -annotate 0 "P2" "$d/p2.png" 2>/dev/null
      magick -size 400x300 xc:white -fill black -pointsize 40 -gravity center -annotate 0 "P3" "$d/p3.png" 2>/dev/null
      magick "$d/p1.png" "$d/p2.png" "$d/p3.png" "$d/in.pdf" 2>/dev/null
      [[ -s "$d/in.pdf" ]] || t_warn "could not build test PDF"
    else t_warn "magick missing - PDF test skipped"; fi
    if [[ -s "$d/in.pdf" ]]; then
      qpdf "$d/in.pdf" --pages . 2 -- "$d/one.pdf" 2>/dev/null && [[ -s "$d/one.pdf" ]] && t_pass "qpdf: extract page 2" || t_fail "qpdf page extraction failed"
      qpdf "$d/in.pdf" --pages "$d/in.pdf" 1 "$d/in.pdf" 2-3 -- "$d/merge.pdf" 2>/dev/null && [[ -s "$d/merge.pdf" ]] && t_pass "qpdf: re-merge pages" || t_fail "qpdf merge failed"
      pages="$(qpdf --show-npages "$d/merge.pdf" 2>/dev/null)"
      [[ "$pages" == "3" ]] && t_pass "qpdf: merged PDF has 3 pages" || t_fail "qpdf: expected 3 pages, got '$pages'"
    fi
    if [[ -s "$d/p1.png" ]]; then
      magick "$d/p1.png" "$d/img.pdf" 2>/dev/null
      if [[ -s "$d/img.pdf" ]]; then
        pdfimages -png "$d/img.pdf" "$d/x" >/dev/null 2>&1 && compgen -G "$d/x*.png" >/dev/null && t_pass "pdfimages: extracted the embedded image" || t_fail "pdfimages extraction failed"
      fi
    fi
  else t_fail "qpdf missing"; fi
  command -v mutool >/dev/null && t_ok "mutool info on a PDF" mutool info "$d/in.pdf" || true
  rm -rf "$d"
}

verify_images() {
  need qol || return 0
  t_head "Image tools"
  local d; d="$(mktemp -d)"
  if command -v magick >/dev/null; then
    magick -size 640x360 gradient:'#bd93f9'-'#282a36' "$d/src.png" 2>/dev/null
    magick "$d/src.png" -resize 320x180 "$d/small.png" 2>/dev/null
    sz="$(magick identify -format '%wx%h' "$d/small.png" 2>/dev/null)"
    [[ "$sz" == "320x180" ]] && t_pass "magick: resize 640x360 -> 320x180" || t_fail "magick resize failed ($sz)"
    magick "$d/src.png" "$d/out.jpg" 2>/dev/null && [[ -s "$d/out.jpg" ]] && t_pass "magick: PNG -> JPG conversion" || t_fail "magick conversion failed"
  else t_fail "magick (imagemagick) missing"; fi
  if command -v oxipng >/dev/null && [[ -s "$d/src.png" ]]; then
    cp "$d/src.png" "$d/oxi.png"; oxipng -q -o 1 "$d/oxi.png" && t_pass "oxipng: optimized a PNG" || t_fail "oxipng failed"
  elif command -v oxipng >/dev/null; then t_pass "oxipng present"; else t_fail "oxipng missing"; fi
  if command -v jpegoptim >/dev/null && [[ -s "$d/out.jpg" ]]; then
    jpegoptim -q "$d/out.jpg" && t_pass "jpegoptim: optimized a JPG" || t_fail "jpegoptim failed"
  elif command -v jpegoptim >/dev/null; then t_pass "jpegoptim present"; else t_fail "jpegoptim missing"; fi
  command -v imv >/dev/null && t_pass "imv (image viewer) present" || t_fail "imv missing"
  command -v chafa >/dev/null && t_pass "chafa (terminal image preview) present" || t_fail "chafa missing"
  rm -rf "$d"
}

verify_torrent() {
  need torrent || return 0
  t_head "Torrents + network"
  command -v aria2c >/dev/null && t_pass "aria2c present" || t_fail "aria2c missing"
  if [[ "$WITH_TORRENT" == 1 ]]; then
    command -v prowlarr >/dev/null 2>&1 || [[ -x /usr/lib/prowlarr/bin/Prowlarr ]] \
      && t_pass "prowlarr installed" || t_fail "prowlarr missing"
    systemctl is-enabled prowlarr.service >/dev/null 2>&1 && t_pass "prowlarr.service enabled" || t_warn "prowlarr.service not enabled"
  else t_skip "torrent phase disabled (WITH_TORRENT=0)"; fi
  systemctl is-active --quiet NetworkManager.service && t_pass "NetworkManager active" || t_fail "NetworkManager not active"
  nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q ':connected' && t_pass "network connected via NM" || t_warn "no active NM connection (nmtui to connect)"
}

verify_gaming() {
  need gaming || return 0
  t_head "Gaming stack"
  command -v steam >/dev/null && t_pass "steam present" || t_fail "steam missing"
  command -v gamescope >/dev/null && t_pass "gamescope present (Wayland game compositor)" || t_fail "gamescope missing"
  command -v gamemoderun >/dev/null && t_pass "gamemode present" || t_fail "gamemode missing"
  command -v mangohud >/dev/null && t_pass "mangohud present (FPS overlay)" || t_fail "mangohud missing"
  pacman -Q proton-ge-custom-bin >/dev/null 2>&1 && t_pass "proton-ge-custom-bin installed" || { [[ "$WITH_GAMING" == 1 ]] && t_warn "proton-ge-custom-bin not installed" || t_skip "proton-ge (WITH_GAMING=0)"; }
  pacman -Q lib32-vulkan-radeon >/dev/null 2>&1 && t_pass "32-bit Vulkan (RADV) for 32-bit games" || t_warn "lib32-vulkan-radeon missing"
  command -v goverlay >/dev/null && t_pass "goverlay (mangohud config GUI)" || t_warn "goverlay missing"
}

verify_theme() {
  need theme || return 0
  t_head "Theme ($THEME)"
  if [[ "${THEME:-none}" == "none" ]]; then t_skip "THEME=none"; return; fi
  local f
  for f in "$HOME/.config/foot/foot.ini" "$HOME/.config/waybar/config" "$HOME/.config/waybar/style.css" \
           "$HOME/.config/mako/config" "$HOME/.config/rofi/config.rasi" "$HOME/.config/starship.toml" \
           "$HOME/.config/fastfetch/config.jsonc" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" \
           "$HOME/.config/qt6ct/qt6ct.conf" "$HOME/.config/qt5ct/qt5ct.conf" "$HOME/.config/dwl/wallpaper.png" \
           "$HOME/.local/bin/dwl-wallpaper" "$HOME/.local/bin/dwl-quick" "$HOME/.local/bin/dwl-screenshot" \
           "$HOME/.local/bin/dwl-help" \
           /etc/tuigreet/config.toml; do
    [[ -s "$f" ]] && t_pass "$f" || t_fail "$f missing or empty"
  done
  bash -n "$HOME/.local/bin/dwl-wallpaper" && bash -n "$HOME/.local/bin/dwl-quick" && bash -n "$HOME/.local/bin/dwl-screenshot" && bash -n "$HOME/.local/bin/dwl-help" \
    && t_pass "wallpaper/quick/screenshot/help scripts parse" || t_fail "a dwl helper script has a syntax error"
  if [[ -f "$DWL_SRC/config.h" ]]; then
    grep -q 'dwlsetup keys' "$DWL_SRC/config.h" && t_pass "dwl keybinds in config.h" || t_warn "dwl keybinds not in config.h"
    grep -q 'MODKEY WLR_MODIFIER_LOGO' "$DWL_SRC/config.h" && t_pass "dwl MODKEY = Super" || t_warn "dwl MODKEY is not Super (Alt still?)"
    grep -q '"rofi", "-show", "drun"' "$DWL_SRC/config.h" && t_pass "dwl launcher = rofi (Super+P)" || t_warn "dwl launcher is not rofi"
    grep -qE '\{ MODKEY, +XKB_KEY_Return, +spawn,' "$DWL_SRC/config.h" && t_pass "terminal on Super+Return" || t_warn "terminal/zoom swap not applied"
    grep -qE 'static const int gapp(i|o)[hv] = 12;' "$DWL_SRC/config.h" && t_pass "window gaps set (12px)" || t_warn "gaps not set (genericgaps patch not applied?)"
  fi
  grep -q 'Dracula' "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null && t_pass "GTK theme set" || t_warn "GTK theme not set"
  grep -qE '^foreground=[0-9a-fA-F]{6}$' "$HOME/.config/foot/foot.ini" 2>/dev/null \
    && t_pass "foot colors in RRGGBB format (no #)" || t_warn "foot.ini foreground line unexpected"
  grep -q '^\[colors-dark\]$' "$HOME/.config/foot/foot.ini" 2>/dev/null \
    && t_pass "foot [colors-dark] section present" || t_warn "foot [colors-dark] missing"
  fc-list 2>/dev/null | grep -qi 'Papirus' && t_pass "Papirus icon theme installed" || t_warn "Papirus missing"
  if [[ -f /etc/default/grub ]]; then
    grep -q '^GRUB_THEME=' /etc/default/grub && t_pass "GRUB themed" || t_warn "GRUB theme not set (optional)"
  fi
}

verify_hardware() {
  need qol || return 0
  t_head "Hardware extras (RGB, mouse, sound, cooler)"
  command -v openrgb >/dev/null && t_pass "openrgb (RGB control) present" || t_fail "openrgb missing"
  command -v solaar >/dev/null && t_pass "solaar (Logitech receiver) present" || t_fail "solaar missing"
  command -v ratbagctl >/dev/null && t_pass "ratbagctl (mouse DPI/buttons) present" || t_fail "ratbagctl missing"
  command -v easyeffects >/dev/null && t_pass "easyeffects (EQ for good sound) present" || t_fail "easyeffects missing"
  command -v gammastep >/dev/null && t_pass "gammastep (night light) present" || t_fail "gammastep missing"
  if command -v liquidctl >/dev/null; then
    if sudo -n true 2>/dev/null; then
      out="$(sudo -n liquidctl list 2>&1 || true)"
      grep -qi 'device' <<<"$out" && t_pass "liquidctl: found device(s)" || t_warn "liquidctl: no supported device detected (book: Jungle Leopard coolers have no official Linux driver)"
    else t_warn "liquidctl list needs sudo - run: sudo liquidctl list"; fi
  else t_fail "liquidctl missing"; fi
}

verify_ai() {
  t_head "AI + LazyVim"
  if [[ "$WITH_AI" == 1 ]] && ! skip ai; then
    command -v claude >/dev/null && t_pass "claude (Claude Code CLI) present" || t_warn "claude not on PATH (npm global bin not in PATH?)"
  else t_skip "AI tools (WITH_AI=0 or ai phase skipped)"; fi
  if [[ "$WITH_LAZYVIM" == 1 ]] && ! skip lazyvim; then
    [[ -d "$HOME/.config/nvim" ]] && t_pass "~/.config/nvim exists (LazyVim)" || t_warn "~/.config/nvim missing"
    if [[ -f "$HOME/.config/nvim/lazyvim.json" ]]; then
      jq -e '.extras | index("lazyvim.plugins.extras.ai.avante") != null' "$HOME/.config/nvim/lazyvim.json" >/dev/null 2>&1 \
        && t_pass "LazyVim extra: ai.avante enabled" || t_warn "ai.avante extra not in lazyvim.json"
      jq -e '.extras | index("lazyvim.plugins.extras.ai.claudecode") != null' "$HOME/.config/nvim/lazyvim.json" >/dev/null 2>&1 \
        && t_pass "LazyVim extra: ai.claudecode enabled" || t_warn "ai.claudecode extra not in lazyvim.json"
    fi
  else t_skip "LazyVim (WITH_LAZYVIM=0 or lazyvim phase skipped)"; fi
}

verify_monitor() {
  t_head "Monitor (LG 24G411A-B: sRGB IPS, 120/144 Hz)"
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wlr-randr >/dev/null; then
    out="$(wlr-randr 2>/dev/null)"
    grep -qiE 'preferred, current' <<<"$out" && t_pass "display active: $(grep -m1 -E 'preferred, current' <<<"$out" | sed 's/^ *//')" || t_warn "wlr-randr output:\n$out"
    grep -qiE '@?60\.000Hz' <<<"$out" && t_warn "display running at 60 Hz - for film-smooth playback set it to 120 Hz (OSD or wlr-randr --output <name> --mode ...@120Hz)" || true
  else t_skip "monitor check (needs a running dwl session: wlr-randr)"; fi
}

verify_extras() {
  t_head "Docker (rootless), snapshots, hooks"
  if skip docker; then t_skip "docker phase skipped"
  elif [[ -S "${XDG_RUNTIME_DIR:-/nonexistent}/docker.sock" ]]; then
    DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless \
      && t_pass "Docker daemon running in ROOTLESS mode" || t_fail "Docker daemon reachable but not rootless"
  else t_warn "rootless Docker socket not found (finish setup after first dwl login)"; fi
  if skip snapshots || [[ "$(findmnt -no FSTYPE / 2>/dev/null)" != btrfs ]]; then t_skip "snapshots (not Btrfs, or phase skipped)"
  else
    command -v timeshift >/dev/null && t_pass "timeshift installed" || t_fail "timeshift missing"
    sudo -n timeshift --list 2>/dev/null | grep -qi 'baseline' && t_pass "baseline snapshot exists" || t_warn "no baseline snapshot found (or needs sudo)"
  fi
  if skip dwl; then t_skip "dwl rebuild hook (dwl phase skipped)"
  elif [[ -f /etc/pacman.d/hooks/dwl-rebuild.hook ]]; then t_pass "dwl rebuild pacman hook installed"
  else t_fail "dwl rebuild hook missing"; fi
  local pc; pc="$(grep -oE 'wlroots-[0-9]+\.[0-9]+' "${DWL_SRC}/config.mk" 2>/dev/null | head -1)"
  [[ -n "$pc" ]] && { pkg-config --exists "$pc" && t_pass "dwl's wlroots dependency ($pc) is installed" || t_fail "dwl needs $pc but it is missing"; }
}

verify_health() {
  t_head "System health (disk, memory, failed units, clock)"
  local avail_gb mem_gb failed
  avail_gb="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"; avail_gb="${avail_gb:-0}"
  if (( avail_gb < 2 )); then t_fail "only ${avail_gb}G free on / - AUR builds and snapshots need room"
  elif (( avail_gb < 10 )); then t_warn "only ${avail_gb}G free on / - tight for AUR builds + snapshots"
  else t_pass "disk: ${avail_gb}G free on /"; fi
  mem_gb="$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')"; mem_gb="${mem_gb:-0}"
  if (( mem_gb < 2 )); then t_warn "only ${mem_gb}G RAM - browsers/games will struggle"
  else t_pass "memory: ${mem_gb}G RAM"; fi
  failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
  if [[ -z "$failed" ]]; then t_pass "no failed system units"
  else t_fail "failed units: $(tr '\n' ' ' <<<"$failed")"; fi
  if systemctl --user show-environment >/dev/null 2>&1; then
    failed="$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
    [[ -z "$failed" ]] && t_pass "no failed user units" || t_warn "failed user units: $(tr '\n' ' ' <<<"$failed")"
  else t_skip "user units check (no user session bus here)"; fi
  if command -v timedatectl >/dev/null; then
    [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]] \
      && t_pass "clock synced (NTP)" || t_warn "clock not NTP-synced - TLS/cert errors will follow (enable systemd-timesyncd)"
  fi
  info "load: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null), uptime: $(uptime -p 2>/dev/null)"
}

verify_all() {
  log "Verification suite  ($(date '+%F %R'))"
  sudo -v 2>/dev/null || true
  verify_packages; verify_binaries; verify_files; verify_services; verify_health
  verify_gpu; verify_codecs; verify_fonts_shell; verify_dwl_smoke; verify_office; verify_images
  verify_torrent; verify_gaming; verify_theme; verify_hardware; verify_ai; verify_monitor; verify_extras
  printf '\n\033[1mResult:\033[0m  %d passed, %d failed, %d warnings, %d skipped\n' "$T_PASS" "$T_FAIL" "$T_WARN" "$T_SKIP"
  if ((T_FAIL)); then printf '\033[31mFailures:\033[0m\n'; printf '  - %s\n' "${VERIFY_FAILS[@]}"; fi
  info "WARN = needs a reboot, a graphical session, or an optional item. FAIL = something is genuinely broken."
  ((T_FAIL == 0))
}

phase_verify() { verify_all || warn "Verification found ${T_FAIL} failure(s) - see the list above."; }

# ----------------------------------------------------------- 14. session -----
phase_session() {
  log "Session wiring (start-dwl, autostart, greetd)"
  inst "${P_SESSION[@]}"

  # Session-wide environment must be set BEFORE dwl starts (per dwl's README) -> wrapper script.
  sed -e "s|@KB_LAYOUT@|$KB_LAYOUT|" -e "s|@KB_OPTIONS@|$KB_OPTIONS|" <<'EOF' | write_root_exec /usr/local/bin/start-dwl
#!/bin/sh
# Launched by greetd. Anything exported here is inherited by every app in the session.
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=dwl
export XDG_CURRENT_DESKTOP=wlroots
export XKB_DEFAULT_LAYOUT="@KB_LAYOUT@"
export XKB_DEFAULT_OPTIONS="@KB_OPTIONS@"
export QT_QPA_PLATFORM="wayland;xcb"
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export GDK_BACKEND="wayland,x11"
export GTK_USE_PORTAL=1
export MOZ_ENABLE_WAYLAND=1
export ELECTRON_OZONE_PLATFORM_HINT=auto
export EDITOR=nvim
export TERMINAL=foot
export PATH="$HOME/.local/bin:$PATH"
[ -r "$HOME/.config/dwl/env" ] && . "$HOME/.config/dwl/env"
mkdir -p "$HOME/.cache"
exec dwl -s "$HOME/.config/dwl/autostart.sh <&-" >"$HOME/.cache/dwl.log" 2>&1
EOF

  write_user_if_absent "$HOME/.config/dwl/autostart.sh" 755 <<'EOF'
#!/usr/bin/env bash
# Started by `dwl -s` (replaces the autostart patch). Yours to edit.
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP 2>/dev/null

start() { command -v "$1" >/dev/null 2>&1 && "$@" & }

systemctl --user start hyprpolkitagent.service 2>/dev/null || start /usr/lib/hyprpolkitagent/hyprpolkitagent
start foot --server
start mako
start swayosd-server
start waybar
start udiskie
start nm-applet
start wl-paste --type text  --watch cliphist store
start wl-paste --type image --watch cliphist store
start swayidle -w timeout 600 'swaylock -f' before-sleep 'swaylock -f'
if command -v awww-daemon >/dev/null 2>&1; then
  start awww-daemon
  sleep 1
  [ -f "$HOME/.config/dwl/wallpaper.png" ] && awww img "$HOME/.config/dwl/wallpaper.png" &
elif command -v swww-daemon >/dev/null 2>&1; then
  start swww-daemon
  sleep 1
  [ -f "$HOME/.config/dwl/wallpaper.png" ] && swww img "$HOME/.config/dwl/wallpaper.png" &
fi

wait   # keep the startup command alive while the session runs
EOF

  write_root /usr/share/wayland-sessions/dwl.desktop <<'EOF'
[Desktop Entry]
Name=dwl
Comment=dwm for Wayland
Exec=/usr/local/bin/start-dwl
Type=Application
DesktopNames=wlroots
EOF

  sudo cp -n /etc/greetd/config.toml /etc/greetd/config.toml.bak-dwlsetup 2>/dev/null || true
  # tuigreet --remember needs a cache dir owned by the greeter user.
  sudo install -dm755 -o greeter -g greeter /var/cache/tuigreet 2>/dev/null \
    || warn "could not prepare /var/cache/tuigreet (username memory may not work)"
  # Minimal greeter: username + password only (no clock, no extra widgets). Theme colors
  # come from /etc/tuigreet/config.toml (written by the theme phase).
  write_root /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --asterisks --window-padding 2 --cmd /usr/local/bin/start-dwl"
user = "greeter"
EOF
}

phase_services() {
  log "Enabling greetd (takes effect at next boot; your current session is not touched)"
  local cur; cur="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
  [[ -n "$cur" && "$cur" != *greetd* ]] && warn "Replacing existing display manager: $cur"
  sudo systemctl enable -f greetd.service || warn "Could not enable greetd.service"
}

# --------------------------------------------------------- 15. snapshots -----
phase_snapshots() {
  log "Btrfs snapshots (Timeshift)"
  if [[ "$(findmnt -no FSTYPE /)" != "btrfs" ]]; then
    warn "Root is not Btrfs: snapshot phase skipped."; return 0
  fi
  if ! findmnt -no OPTIONS / | grep -q 'subvol=/@\(,\|$\)'; then
    warn "Root subvolume is not '@'. Timeshift's Btrfs mode requires the @ / @home layout - skipped (consider snapper + snap-pac)."
    return 0
  fi
  inst "${P_SNAP[@]}"
  sudo systemctl enable --now cronie.service
  inst_groups "${A_SNAP[@]}"
  if [[ -f /etc/default/grub ]]; then
    inst grub-btrfs
    sudo install -Dm644 /dev/stdin /etc/systemd/system/grub-btrfsd.service.d/timeshift.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable grub-btrfsd.service
    NEEDS_GRUB_REGEN=1
  else
    warn "Not using GRUB: skipped grub-btrfs (snapshots won't appear in the boot menu)."
  fi
  local dev; dev="$(findmnt -no SOURCE / | sed 's/\[.*//')"
  sudo timeshift --btrfs --snapshot-device "$dev" --create --comments "baseline after arch-dwl-setup" --tags D \
    || warn "Could not create the baseline snapshot; open Timeshift once to configure it."
  info "timeshift-autosnap hooks EVERY pacman transaction (not just paru -Syu)."
  mountpoint -q /boot && ! findmnt -no FSTYPE /boot | grep -q btrfs \
    && warn "/boot is a separate non-Btrfs partition: snapshots will NOT roll back your kernels. Mount the ESP at /efi instead, or add a kernel-backup hook."
}

# ---------------------------------------------------------------- summary ----
summary() {
  if [[ $NEEDS_GRUB_REGEN -eq 1 ]] && command -v grub-mkconfig >/dev/null; then
    log "Regenerating GRUB config"
    sudo grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed - run it manually."
  fi
  log "Done"
  if ((${#APPLIED[@]})); then info "dwl patches applied: ${APPLIED[*]}"; else info "dwl patches applied: none (vanilla dwl)"; fi
  if ((${#FAILED[@]})); then
    printf '\n\033[1;31mPackages that did NOT install:\033[0m\n'; printf '  - %s\n' "${FAILED[@]}"
  fi
  if ((${#WARNINGS[@]})); then
    printf '\n\033[1;33mWarnings worth reading:\033[0m\n'; printf '  - %s\n' "${WARNINGS[@]}"
  fi
  cat <<EOF

Next steps
  1. Reboot (new kernel/firmware, kernel parameters, greetd, NetworkManager), then run: ./arch-dwl-setup.sh --verify
     (the post-install check ran before the reboot, so reboot-dependent items showed as WARN).
  2. Log in via the minimal greeter -> dwl. If it bounces back: ~/.cache/dwl.log
  3. Keys: Super+Return = terminal, Super+P = rofi launcher (icons only), Super+X = quick settings,
     Super+/ = searchable help menu (every shortcut + action), Super+Up/Down = volume,
     Super+Left/Right = brightness, Super+Shift+S = region screenshot,
     Super+W = wallpaper menu, Super+Shift+W = next wallpaper, Super+Shift+Q = quit.
     Edit $DWL_SRC/config.h, then run: dwl-rebuild
  4. Waybar's dwl/tags needs the 'ipc' patch to have applied (see above).
  5. Connect wifi: nm-applet tray icon or 'nmtui'. Spotify TUI needs Premium.
  6. Torrents: Prowlarr at http://localhost:9696 -> add public indexers -> search without torrent sites.
     Open your client's listen port: sudo ufw allow <port>
  7. Wallpapers: dwl-wallpaper --fetch (wallhaven top-30, needs --set-apikey once), --add, --remove, --next.
  8. AI: export ANTHROPIC_API_KEY (and ANTHROPIC_BASE_URL for DeepSeek), 'claude' in any terminal,
     or <leader>aa inside nvim (LazyVim avante).
  9. Gaming: Steam -> Proton (GE) -> add 'gamemoderun %command%'; MANGOHUD=1 for the overlay.
EOF
}

main() {
  case "${1:-}" in
    -h|--help)         awk 'NR>1{print} NR>1 && /^# =+$/{c++} c==2{exit}' "$0"; exit 0 ;;
    --check-packages)  check_packages; exit $? ;;
    --verify)          verify_all; exit $? ;;
  esac
  preflight
  run_phase pacman    phase_pacman
  run_phase paru      phase_paru
  run_phase security  phase_security
  run_phase amd       phase_amd
  run_phase base      phase_base
  run_phase codecs    phase_codecs
  run_phase dwl       phase_dwl
  run_phase visual    phase_visual
  run_phase qol       phase_qol
  run_phase fonts     phase_fonts
  run_phase office    phase_office
  run_phase apps      phase_apps
  run_phase gaming    phase_gaming
  run_phase torrent   phase_torrent
  run_phase docker    phase_docker
  run_phase theme     phase_theme
  run_phase lazyvim   phase_lazyvim
  run_phase ai        phase_ai
  run_phase session   phase_session
  run_phase services  phase_services
  run_phase snapshots phase_snapshots
  run_phase verify    phase_verify
  summary
}
main "$@"
