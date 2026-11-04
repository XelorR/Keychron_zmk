#!/bin/bash
# Build Keychron B1 Pro firmware: board `keychron` + shield `keychron_b1_us`.
# Commands taken from the space-fn branch README ("how to build").
#
# Matrix revision (SKU):
#   B1P-K11 (2023) -> original matrix wiring (default)
#   B1P-K13 (2025) -> 2025 revision matrix wiring
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"
KEYBOARD_ID="blue"
MATRIX_REV="B1P-K11"

ACTION=""
ASSUME_YES=0
SKIP_DEPS_CHECK=0
DRY_RUN=0
FORCE_REINSTALL=0
REMOVE_HAD_ERRORS=0

ZEPHYR_SDK_VERSION="${ZEPHYR_SDK_VERSION:-0.17.4}"
ZEPHYR_SDK_DIR="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/.opt/zephyr-sdk-$ZEPHYR_SDK_VERSION}"
SDK_PLATFORM=""
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keychron_zmk"

DISTRO=""
PKG_MANAGER=""
SYSTEM_COMMANDS=(wget cmake ninja git python3 pipx xz)
SYSTEM_PACKAGE_NAMES=()
MISSING_SYSTEM_PKGS=()
MISSING_WEST=0
MISSING_PYELFTOOLS=0
MISSING_SDK=0

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    YELLOW=$'\033[33m'
    RESET=$'\033[0m'
else
    BOLD=""
    GREEN=""
    RED=""
    YELLOW=""
    RESET=""
fi

usage() {
    cat >&2 <<EOF
Usage: $0 [build options] [dependency options]

Build options:
  --id/-i ID           keyboard ID (default: blue)
  --matrix/-m/--rev SKU
                       matrix SKU: B1P-K11 (2023, default) or B1P-K13 (2025)
                       years 2023 and 2025 are also accepted
  --new-matrix         shorthand for --matrix B1P-K13
  --skip-deps-check    do not check/install build dependencies before build

Dependency options:
  --install-deps       install missing build dependencies and exit
  --remove-deps        remove build dependencies installed by this script and exit
  --reinstall-deps     reinstall all build dependencies and exit
  --yes/-y             answer yes to all confirmation prompts
  --dry-run            show dependency commands without executing them

  --help/-h            show this help

Supported distributions: Arch Linux, CachyOS, Ubuntu, Debian, Fedora.

Output: ~/Downloads/b1_<branch>_<SKU>_<ID>.uf2
Example: $0 --id red --matrix B1P-K13
EOF
}

set_action() {
    if [[ -n "$ACTION" && "$ACTION" != "$1" ]]; then
        echo "Conflicting dependency actions: --${ACTION}-deps and --$1-deps" >&2
        exit 2
    fi
    ACTION="$1"
}

while (($# > 0)); do
    case "$1" in
        --id|-i)
            if (($# < 2)); then
                usage
                exit 2
            fi
            KEYBOARD_ID="$2"
            shift 2
            ;;
        --id=*)
            KEYBOARD_ID="${1#*=}"
            shift
            ;;
        --matrix|-m|--rev)
            if (($# < 2)); then
                usage
                exit 2
            fi
            MATRIX_REV="$2"
            shift 2
            ;;
        --matrix=*|--rev=*)
            MATRIX_REV="${1#*=}"
            shift
            ;;
        --new-matrix)
            MATRIX_REV="B1P-K13"
            shift
            ;;
        --install-deps|--deps-install)
            set_action install
            shift
            ;;
        --remove-deps|--deps-remove)
            set_action remove
            shift
            ;;
        --reinstall-deps|--deps-reinstall)
            set_action reinstall
            shift
            ;;
        --skip-deps-check)
            SKIP_DEPS_CHECK=1
            shift
            ;;
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ ! "$KEYBOARD_ID" =~ ^[[:alnum:]_-]+$ ]]; then
    echo "Invalid keyboard ID: '$KEYBOARD_ID'" >&2
    echo "Use only letters, numbers, '_' and '-'." >&2
    exit 2
fi

case "${MATRIX_REV^^}" in
    B1P-K11|2023)
        MATRIX_REV="2023"
        MATRIX_SKU="B1P-K11"
        ;;
    B1P-K13|2025)
        MATRIX_REV="2025"
        MATRIX_SKU="B1P-K13"
        ;;
    *)
        echo "Invalid matrix revision/SKU: '$MATRIX_REV'" >&2
        echo "Allowed values: B1P-K11 (2023), B1P-K13 (2025), 2023, 2025" >&2
        exit 2
        ;;
esac

# ---------------------------------------------------------------------------
# Dependency detection
# ---------------------------------------------------------------------------

detect_distro() {
    local os_release="${OS_RELEASE_FILE:-/etc/os-release}"
    local id=""
    local id_like=""

    if [[ -r "$os_release" ]]; then
        id="$(set +u; . "$os_release" >/dev/null 2>&1; printf '%s' "${ID:-}")"
        id_like="$(set +u; . "$os_release" >/dev/null 2>&1; printf '%s' "${ID_LIKE:-}")"
    fi

    local keys=" ${id,,} ${id_like,,} "
    case "$keys" in
        *" cachyos "*|*" arch "*)
            echo "arch"
            ;;
        *" ubuntu "*|*" debian "*)
            echo "debian"
            ;;
        *" fedora "*)
            echo "fedora"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

init_distro() {
    DISTRO="$(detect_distro)"
    case "$DISTRO" in
        arch)
            PKG_MANAGER="pacman"
            SYSTEM_PACKAGE_NAMES=(wget cmake ninja git python python-pipx xz)
            ;;
        debian)
            PKG_MANAGER="apt"
            SYSTEM_PACKAGE_NAMES=(wget cmake ninja-build git python3 python3-pip pipx xz-utils)
            ;;
        fedora)
            PKG_MANAGER="dnf"
            SYSTEM_PACKAGE_NAMES=(wget cmake ninja-build git python3 python3-pip pipx xz)
            ;;
        *)
            PKG_MANAGER=""
            SYSTEM_PACKAGE_NAMES=()
            ;;
    esac
}

init_sdk_platform() {
    case "$(uname -m)" in
        x86_64|amd64)
            SDK_PLATFORM="linux-x86_64"
            ;;
        aarch64|arm64)
            SDK_PLATFORM="linux-aarch64"
            ;;
        *)
            SDK_PLATFORM=""
            ;;
    esac
}

package_for_command() {
    local cmd="$1"
    case "$DISTRO:$cmd" in
        arch:python3) echo "python" ;;
        arch:pipx) echo "python-pipx" ;;
        debian:ninja|fedora:ninja) echo "ninja-build" ;;
        debian:xz) echo "xz-utils" ;;
        *) echo "$cmd" ;;
    esac
}

package_is_installed() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pacman)
            pacman -Qq "$pkg" >/dev/null 2>&1
            ;;
        apt)
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
            ;;
        dnf)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

sdk_is_ready() {
    [[ -x "$ZEPHYR_SDK_DIR/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc" ]] &&
        [[ -f "$ZEPHYR_SDK_DIR/sdk_version" ]] &&
        [[ -d "$ZEPHYR_SDK_DIR/sysroots" ]]
}

sdk_path_is_safe() {
    local path="$1"
    [[ -n "$path" && "$path" == /* && "$path" != "/" && "$path" == *"/zephyr-sdk-"* ]]
}

west_is_pipx_managed() {
    command -v pipx >/dev/null 2>&1 &&
        pipx list --short 2>/dev/null | awk '{print $1}' | grep -qxF "west"
}

west_has_pyelftools() {
    command -v west >/dev/null 2>&1 || return 1

    if west_is_pipx_managed; then
        pipx runpip west show pyelftools >/dev/null 2>&1
    else
        # west may be installed outside pipx; the system Python is the best
        # available guess in that case.
        python3 -c 'import elftools' >/dev/null 2>&1
    fi
}

check_dependencies() {
    MISSING_SYSTEM_PKGS=()
    MISSING_WEST=0
    MISSING_PYELFTOOLS=0
    MISSING_SDK=0

    local cmd
    local pkg
    for cmd in "${SYSTEM_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            pkg="$(package_for_command "$cmd")"
            MISSING_SYSTEM_PKGS+=("$pkg")
        fi
    done

    if ! command -v west >/dev/null 2>&1; then
        MISSING_WEST=1
    elif ! west_has_pyelftools; then
        MISSING_PYELFTOOLS=1
    fi

    if ! sdk_is_ready; then
        MISSING_SDK=1
    fi
}

dependencies_complete() {
    if ((${#MISSING_SYSTEM_PKGS[@]} > 0)); then
        return 1
    fi
    if ((MISSING_WEST != 0)); then
        return 1
    fi
    if ((MISSING_PYELFTOOLS != 0)); then
        return 1
    fi
    if ((MISSING_SDK != 0)); then
        return 1
    fi
    return 0
}

print_unsupported_distro() {
    echo "Unsupported distribution." >&2
    echo "Supported: Arch Linux, CachyOS, Ubuntu, Debian, Fedora." >&2
    local os_release="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ -r "$os_release" ]]; then
        local pretty=""
        pretty="$(set +u; . "$os_release" >/dev/null 2>&1; printf '%s' "${PRETTY_NAME:-unknown}")"
        echo "Detected: $pretty" >&2
    fi
}

print_missing_dependencies() {
    echo "Missing build dependencies:"
    if ((${#MISSING_SYSTEM_PKGS[@]} > 0)); then
        echo "  - system packages: ${MISSING_SYSTEM_PKGS[*]}"
    fi
    if ((MISSING_WEST != 0)); then
        echo "  - west (pipx package)"
    fi
    if ((MISSING_PYELFTOOLS != 0)); then
        echo "  - pyelftools (injected into west)"
    fi
    if ((MISSING_SDK != 0)); then
        echo "  - Zephyr SDK $ZEPHYR_SDK_VERSION ($ZEPHYR_SDK_DIR, about 1 GB download)"
    fi
}

prompt_yes() {
    local question="$1"

    if ((ASSUME_YES)); then
        echo "$question yes (--yes)"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "$question [y/N] (non-interactive shell; use --yes to confirm)" >&2
        return 1
    fi

    local answer=""
    read -r -p "$question [y/N] " answer || true
    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Managed dependency state (for safe removal)
# ---------------------------------------------------------------------------

state_file() {
    printf '%s/%s' "$STATE_DIR" "$1"
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

record_managed_packages() {
    (($# > 0)) || return 0
    ensure_state_dir
    local file
    file="$(state_file managed-packages)"
    touch "$file"
    printf '%s\n' "$@" >>"$file"
    sort -u -o "$file" "$file"
}

record_managed_component() {
    (($# > 0)) || return 0
    ensure_state_dir
    local file
    file="$(state_file managed-components)"
    touch "$file"
    printf '%s\n' "$@" >>"$file"
    sort -u -o "$file" "$file"
}

record_managed_sdk_path() {
    ensure_state_dir
    printf '%s\n' "$1" >"$(state_file managed-sdk-path)"
}

remove_managed_component() {
    local file
    file="$(state_file managed-components)"
    if [[ -f "$file" ]]; then
        sed -i "/^${1}$/d" "$file"
    fi
}

read_managed_sdk_path() {
    local file
    file="$(state_file managed-sdk-path)"
    if [[ -f "$file" ]]; then
        head -n 1 "$file"
    fi
}

# ---------------------------------------------------------------------------
# Progress / ETA
# ---------------------------------------------------------------------------

DEPS_STEP_LABELS=()
DEPS_STEP_FUNCS=()
DEPS_STEP_WEIGHTS=()
DEPS_STEP_BASE=()
DEPS_BASE_SUFFIX=()
DEPS_TOTAL_WEIGHT=0

deps_plan_reset() {
    DEPS_STEP_LABELS=()
    DEPS_STEP_FUNCS=()
    DEPS_STEP_WEIGHTS=()
    DEPS_STEP_BASE=()
    DEPS_BASE_SUFFIX=()
    DEPS_TOTAL_WEIGHT=0
}

deps_plan_add() {
    local weight="$1"
    local base_seconds="$2"
    local label="$3"
    local func="$4"

    DEPS_STEP_WEIGHTS+=("$weight")
    DEPS_STEP_BASE+=("$base_seconds")
    DEPS_STEP_LABELS+=("$label")
    DEPS_STEP_FUNCS+=("$func")
}

deps_plan_finalize() {
    DEPS_TOTAL_WEIGHT=0
    DEPS_BASE_SUFFIX=()

    local i
    local suffix=0
    local total=${#DEPS_STEP_FUNCS[@]}
    for ((i = total - 1; i >= 0; i--)); do
        suffix=$((suffix + DEPS_STEP_BASE[i]))
        DEPS_BASE_SUFFIX[i]=$suffix
        DEPS_TOTAL_WEIGHT=$((DEPS_TOTAL_WEIGHT + DEPS_STEP_WEIGHTS[i]))
    done
}

format_duration() {
    local total="${1:-0}"
    if ((total < 0)); then
        total=0
    fi

    local hours=$((total / 3600))
    local minutes=$(((total % 3600) / 60))
    local seconds=$((total % 60))
    if ((hours > 0)); then
        printf '%d:%02d:%02d' "$hours" "$minutes" "$seconds"
    else
        printf '%02d:%02d' "$minutes" "$seconds"
    fi
}

progress_bar() {
    local pct="$1"
    local width=24
    local filled=$((pct * width / 100))
    if ((filled > width)); then
        filled=$width
    fi
    if ((filled < 0)); then
        filled=0
    fi

    local bar=""
    local i
    for ((i = 0; i < width; i++)); do
        if ((i < filled)); then
            bar+="#"
        else
            bar+="-"
        fi
    done
    printf '%s' "$bar"
}

deps_run_plan() {
    deps_plan_finalize

    local total=${#DEPS_STEP_FUNCS[@]}
    if ((total == 0)); then
        echo "Nothing to do."
        return 0
    fi
    if ((DEPS_TOTAL_WEIGHT <= 0)); then
        echo "Internal error: empty dependency plan." >&2
        return 1
    fi

    local start=$SECONDS
    local done_weight=0
    local i
    local weight
    local label
    local elapsed
    local pct
    local eta

    for ((i = 0; i < total; i++)); do
        weight=${DEPS_STEP_WEIGHTS[i]}
        label=${DEPS_STEP_LABELS[i]}
        elapsed=$((SECONDS - start))
        pct=$((done_weight * 100 / DEPS_TOTAL_WEIGHT))

        if ((done_weight > 0)); then
            eta=$((elapsed * (DEPS_TOTAL_WEIGHT - done_weight) / done_weight))
        else
            eta=${DEPS_BASE_SUFFIX[i]}
        fi

        printf '\n%s[%d/%d] %s%s\n' "$BOLD" "$((i + 1))" "$total" "$label" "$RESET"
        printf '  [%s] %3d%%  elapsed %s  ETA ~%s\n' \
            "$(progress_bar "$pct")" "$pct" \
            "$(format_duration "$elapsed")" "$(format_duration "$eta")"

        if ! "${DEPS_STEP_FUNCS[$i]}"; then
            printf '\n%s[FAILED]%s %s\n' "$RED" "$RESET" "$label" >&2
            printf 'Dependency step failed after %s.\n' \
                "$(format_duration "$((SECONDS - start))")" >&2
            return 1
        fi

        done_weight=$((done_weight + weight))
        elapsed=$((SECONDS - start))
        pct=$((done_weight * 100 / DEPS_TOTAL_WEIGHT))
        if ((done_weight > 0)); then
            eta=$((elapsed * (DEPS_TOTAL_WEIGHT - done_weight) / done_weight))
        else
            eta=0
        fi
        printf '  [%s] %3d%%  elapsed %s  ETA ~%s (step done)\n' \
            "$(progress_bar "$pct")" "$pct" \
            "$(format_duration "$elapsed")" "$(format_duration "$eta")"
    done

    printf '\n%sAll dependency steps completed in %s.%s\n' \
        "$GREEN" "$(format_duration "$((SECONDS - start))")" "$RESET"
}

# ---------------------------------------------------------------------------
# Running commands
# ---------------------------------------------------------------------------

print_command() {
    printf '  %s[dry-run]%s' "$YELLOW" "$RESET"
    printf ' %q' "$@"
    printf '\n'
}

run_root() {
    if ((DRY_RUN)); then
        if ((EUID == 0)); then
            print_command "$@"
        else
            print_command sudo "$@"
        fi
        return 0
    fi

    if ((EUID == 0)); then
        "$@"
    else
        sudo "$@"
    fi
}

require_sudo() {
    if ((EUID != 0)) && ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is required to install/remove system packages." >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Package manager operations
# ---------------------------------------------------------------------------

pkg_update() {
    case "$PKG_MANAGER" in
        pacman)
            # A normal Arch/CachyOS installation already has a populated sync
            # database. A minimal container may not, so bootstrap it without
            # forcing a full system upgrade.
            if [[ ! -d /var/lib/pacman/sync ]] ||
                ! compgen -G "/var/lib/pacman/sync/*.db" >/dev/null; then
                run_root pacman -Sy --noconfirm
            fi
            ;;
        apt)
            run_root apt-get update
            ;;
        *)
            return 0
            ;;
    esac
}

pkg_install() {
    local packages=("$@")
    ((${#packages[@]} > 0)) || return 0

    case "$PKG_MANAGER" in
        pacman)
            run_root pacman -S --needed --noconfirm "${packages[@]}"
            ;;
        apt)
            run_root apt-get install -y "${packages[@]}"
            ;;
        dnf)
            run_root dnf install -y "${packages[@]}"
            ;;
        *)
            echo "Cannot install packages: unsupported package manager." >&2
            return 1
            ;;
    esac
}

pkg_reinstall() {
    local packages=("$@")
    ((${#packages[@]} > 0)) || return 0

    case "$PKG_MANAGER" in
        pacman)
            run_root pacman -S --noconfirm "${packages[@]}"
            ;;
        apt)
            run_root apt-get install -y --reinstall "${packages[@]}"
            ;;
        dnf)
            run_root dnf reinstall -y "${packages[@]}"
            ;;
        *)
            echo "Cannot reinstall packages: unsupported package manager." >&2
            return 1
            ;;
    esac
}

pkg_remove() {
    local packages=("$@")
    ((${#packages[@]} > 0)) || return 0

    case "$PKG_MANAGER" in
        pacman)
            run_root pacman -R --noconfirm "${packages[@]}"
            ;;
        apt)
            run_root apt-get remove -y "${packages[@]}"
            ;;
        dnf)
            run_root dnf remove -y "${packages[@]}"
            ;;
        *)
            echo "Cannot remove packages: unsupported package manager." >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Install / reinstall operations
# ---------------------------------------------------------------------------

install_system_packages() {
    local packages=("${MISSING_SYSTEM_PKGS[@]}")
    ((${#packages[@]} > 0)) || return 0

    require_sudo || return 1
    echo "Installing system packages: ${packages[*]}"
    pkg_update || return 1
    pkg_install "${packages[@]}" || return 1
    if ((!DRY_RUN)); then
        record_managed_packages "${packages[@]}"
    fi
}

install_west() {
    command -v pipx >/dev/null 2>&1 || {
        echo "pipx is not available; cannot install west." >&2
        return 1
    }

    if ((DRY_RUN)); then
        print_command pipx install west
    elif west_is_pipx_managed; then
        pipx reinstall west || return 1
    else
        pipx install west || return 1
    fi

    if ((!DRY_RUN)); then
        record_managed_component west
    fi
}

install_pyelftools() {
    command -v pipx >/dev/null 2>&1 || {
        echo "pipx is not available; cannot inject pyelftools." >&2
        return 1
    }

    if ((DRY_RUN)); then
        print_command pipx inject west pyelftools
    else
        if ! west_is_pipx_managed; then
            echo "west is not managed by pipx; installing a pipx-managed copy."
            pipx install --force west || return 1
        fi
        pipx inject west pyelftools || return 1
    fi

    if ((!DRY_RUN)); then
        record_managed_component pyelftools
    fi
}

reinstall_west() {
    command -v pipx >/dev/null 2>&1 || {
        echo "pipx is not available; cannot reinstall west." >&2
        return 1
    }

    if ((DRY_RUN)); then
        print_command pipx reinstall west
        return 0
    fi

    if west_is_pipx_managed; then
        pipx reinstall west || return 1
    else
        pipx install --force west || return 1
    fi
    record_managed_component west
}

reinstall_system_packages() {
    ((${#SYSTEM_PACKAGE_NAMES[@]} > 0)) || return 0

    require_sudo || return 1
    pkg_update || return 1

    local to_install=()
    local to_reinstall=()
    local pkg
    for pkg in "${SYSTEM_PACKAGE_NAMES[@]}"; do
        if package_is_installed "$pkg"; then
            to_reinstall+=("$pkg")
        else
            to_install+=("$pkg")
        fi
    done

    if ((${#to_install[@]} > 0)); then
        echo "Installing missing system packages: ${to_install[*]}"
        pkg_install "${to_install[@]}" || return 1
    fi
    if ((${#to_reinstall[@]} > 0)); then
        echo "Reinstalling system packages: ${to_reinstall[*]}"
        pkg_reinstall "${to_reinstall[@]}" || return 1
    fi

    if ((!DRY_RUN)) && ((${#to_install[@]} > 0)); then
        record_managed_packages "${to_install[@]}"
    fi
}

sdk_archive_path() {
    printf '%s/zephyr-sdk-%s_%s.tar.xz' \
        "$(dirname "$ZEPHYR_SDK_DIR")" "$ZEPHYR_SDK_VERSION" "$SDK_PLATFORM"
}

sdk_download_url() {
    printf 'https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v%s/zephyr-sdk-%s_%s.tar.xz' \
        "$ZEPHYR_SDK_VERSION" "$ZEPHYR_SDK_VERSION" "$SDK_PLATFORM"
}

download_sdk() {
    local archive=""
    archive="$(sdk_archive_path)"

    local need_extract=0
    if ((FORCE_REINSTALL)); then
        need_extract=1
    elif [[ ! -d "$ZEPHYR_SDK_DIR" || ! -f "$ZEPHYR_SDK_DIR/setup.sh" ]]; then
        need_extract=1
    fi

    if ((need_extract)) && [[ -e "$ZEPHYR_SDK_DIR" ]]; then
        if ! sdk_path_is_safe "$ZEPHYR_SDK_DIR"; then
            echo "Refusing to remove suspicious SDK path: '$ZEPHYR_SDK_DIR'" >&2
            return 1
        fi
        echo "Removing existing SDK directory: $ZEPHYR_SDK_DIR"
        if ((DRY_RUN)); then
            print_command rm -rf -- "$ZEPHYR_SDK_DIR"
        else
            rm -rf -- "$ZEPHYR_SDK_DIR" || return 1
        fi
    fi

    if [[ -s "$archive" ]]; then
        echo "Using cached SDK archive: $archive"
    else
        if [[ -z "$SDK_PLATFORM" ]]; then
            echo "Unsupported CPU architecture for automatic SDK install: $(uname -m)" >&2
            return 1
        fi

        local url=""
        url="$(sdk_download_url)"
        echo "Downloading Zephyr SDK $ZEPHYR_SDK_VERSION:"
        echo "  $url"
        echo "wget shows transfer progress and its own ETA."

        if ((DRY_RUN)); then
            print_command wget -c --progress=bar:force -O "$archive.part" "$url"
            print_command mv "$archive.part" "$archive"
        else
            mkdir -p "$(dirname "$archive")" || return 1
            if ! wget -c --progress=bar:force -O "$archive.part" "$url"; then
                echo "SDK download failed." >&2
                return 1
            fi
            mv "$archive.part" "$archive" || return 1
        fi
    fi

    if ((need_extract)); then
        echo "Extracting SDK archive..."
        local sdk_parent=""
        sdk_parent="$(dirname "$ZEPHYR_SDK_DIR")"
        local archive_root="$sdk_parent/zephyr-sdk-$ZEPHYR_SDK_VERSION"
        if ((DRY_RUN)); then
            print_command tar -C "$sdk_parent" -xf "$archive"
            if [[ "$archive_root" != "$ZEPHYR_SDK_DIR" ]]; then
                print_command rm -rf -- "$ZEPHYR_SDK_DIR"
                print_command mv "$archive_root" "$ZEPHYR_SDK_DIR"
            fi
        else
            tar -C "$sdk_parent" -xf "$archive" || return 1
            if [[ "$archive_root" != "$ZEPHYR_SDK_DIR" ]]; then
                rm -rf -- "$ZEPHYR_SDK_DIR" || return 1
                mv "$archive_root" "$ZEPHYR_SDK_DIR" || return 1
            fi
        fi
    fi
}

setup_sdk() {
    if [[ ! -x "$ZEPHYR_SDK_DIR/setup.sh" ]]; then
        echo "SDK setup script not found: $ZEPHYR_SDK_DIR/setup.sh" >&2
        return 1
    fi

    echo "Running Zephyr SDK setup (this can take a few minutes)..."
    if ((DRY_RUN)); then
        print_command bash -c "cd $(printf '%q' "$ZEPHYR_SDK_DIR") && ./setup.sh -t all -h -c"
        return 0
    fi

    (cd "$ZEPHYR_SDK_DIR" && ./setup.sh -t all -h -c) || return 1

    if ! sdk_is_ready; then
        echo "SDK setup completed, but $ZEPHYR_SDK_DIR does not look ready." >&2
        return 1
    fi

    record_managed_component sdk
    record_managed_sdk_path "$ZEPHYR_SDK_DIR"
}

install_dependencies() {
    local explicit="${1:-0}"
    local summary_printed="${2:-0}"

    init_distro
    check_dependencies

    if dependencies_complete; then
        echo "All build dependencies are already installed."
        return 0
    fi

    if ((!summary_printed)); then
        print_missing_dependencies
    fi

    if ((!explicit)); then
        if ! prompt_yes "Install missing build dependencies now?"; then
            echo "Build dependencies are required; not starting the build." >&2
            echo "Run '$0 --install-deps' to install them." >&2
            return 1
        fi
    fi

    if ((${#MISSING_SYSTEM_PKGS[@]} > 0)) && [[ -z "$PKG_MANAGER" ]]; then
        print_unsupported_distro
        return 1
    fi
    if ((MISSING_SDK != 0)) && [[ -z "$SDK_PLATFORM" ]]; then
        echo "Unsupported CPU architecture for automatic SDK install: $(uname -m)" >&2
        return 1
    fi

    build_install_plan 0
    deps_run_plan || return 1

    if ((DRY_RUN)); then
        echo "Dry-run complete; no changes were made."
        return 0
    fi

    check_dependencies
    if dependencies_complete; then
        echo "Build dependencies are ready."
        return 0
    fi

    echo "Some build dependencies are still missing after installation:" >&2
    print_missing_dependencies
    return 1
}

reinstall_dependencies() {
    init_distro

    if ! prompt_yes "Reinstall all build dependencies? The Zephyr SDK may be downloaded again."; then
        echo "Cancelled."
        return 0
    fi

    if [[ -z "$PKG_MANAGER" ]]; then
        print_unsupported_distro
        return 1
    fi
    if [[ -z "$SDK_PLATFORM" ]]; then
        echo "Unsupported CPU architecture for automatic SDK install: $(uname -m)" >&2
        return 1
    fi

    check_dependencies
    FORCE_REINSTALL=1
    build_install_plan 1
    deps_run_plan || {
        FORCE_REINSTALL=0
        return 1
    }
    FORCE_REINSTALL=0

    if ((!DRY_RUN)); then
        if ((${#MISSING_SYSTEM_PKGS[@]} > 0)); then
            record_managed_packages "${MISSING_SYSTEM_PKGS[@]}"
        fi
        record_managed_component west
        record_managed_component pyelftools
        record_managed_component sdk
        record_managed_sdk_path "$ZEPHYR_SDK_DIR"
    fi

    if ((DRY_RUN)); then
        echo "Dry-run complete; no changes were made."
        return 0
    fi

    check_dependencies
    if dependencies_complete; then
        echo "Build dependencies reinstalled."
        return 0
    fi

    echo "Some build dependencies are still missing after reinstall:" >&2
    print_missing_dependencies
    return 1
}

# ---------------------------------------------------------------------------
# Removal
# ---------------------------------------------------------------------------

remove_system_packages() {
    local packages=("${REMOVE_SYSTEM_PKGS[@]}")
    ((${#packages[@]} > 0)) || return 0

    local installed=()
    local pkg
    for pkg in "${packages[@]}"; do
        if package_is_installed "$pkg"; then
            installed+=("$pkg")
        fi
    done

    if ((${#installed[@]} == 0)); then
        echo "No installed system packages to remove."
        return 0
    fi
    if [[ -z "$PKG_MANAGER" ]]; then
        echo "Cannot remove system packages: unsupported distribution." >&2
        REMOVE_HAD_ERRORS=1
        return 0
    fi

    require_sudo || return 1
    echo "Removing system packages: ${installed[*]}"
    if ! pkg_remove "${installed[@]}"; then
        echo "Warning: system package removal failed; continuing with other components." >&2
        REMOVE_HAD_ERRORS=1
        return 0
    fi

    if ((!DRY_RUN)); then
        rm -f "$(state_file managed-packages)"
    fi
}

remove_west() {
    if ((DRY_RUN)); then
        print_command pipx uninstall west
        return 0
    fi

    if command -v pipx >/dev/null 2>&1 && west_is_pipx_managed; then
        if ! pipx uninstall west; then
            echo "Warning: failed to uninstall west." >&2
            REMOVE_HAD_ERRORS=1
            return 0
        fi
    else
        echo "west is not managed by pipx; leaving it in place." >&2
        REMOVE_HAD_ERRORS=1
        return 0
    fi

    remove_managed_component west
}

remove_pyelftools() {
    if ((DRY_RUN)); then
        print_command pipx uninject west pyelftools
        return 0
    fi

    if command -v pipx >/dev/null 2>&1 && west_is_pipx_managed; then
        if ! pipx uninject west pyelftools; then
            echo "Warning: failed to remove pyelftools from west." >&2
            REMOVE_HAD_ERRORS=1
            return 0
        fi
    fi

    remove_managed_component pyelftools
}

remove_sdk() {
    if ((DRY_RUN)); then
        local dry_path=""
        dry_path="$(read_managed_sdk_path)"
        if [[ -z "$dry_path" ]]; then
            dry_path="$ZEPHYR_SDK_DIR"
        fi
        print_command rm -rf -- "$dry_path"
        print_command rm -f -- "$(sdk_archive_path)"
        return 0
    fi

    local path=""
    path="$(read_managed_sdk_path)"
    if [[ -z "$path" ]]; then
        path="$ZEPHYR_SDK_DIR"
    fi

    local archive=""
    archive="$(sdk_archive_path)"

    if sdk_path_is_safe "$path"; then
        echo "Removing Zephyr SDK: $path"
        rm -rf -- "$path" || return 1
    else
        echo "Refusing to remove suspicious SDK path: '$path'" >&2
        REMOVE_HAD_ERRORS=1
        return 0
    fi

    if [[ -e "$archive" ]]; then
        echo "Removing SDK archive: $archive"
        rm -f -- "$archive" || return 1
    fi

    remove_managed_component sdk
    rm -f "$(state_file managed-sdk-path)"
}

remove_dependencies() {
    init_distro

    local managed_packages=()
    local managed_components=()
    local file=""

    file="$(state_file managed-packages)"
    if [[ -f "$file" ]]; then
        mapfile -t managed_packages <"$file"
    fi
    file="$(state_file managed-components)"
    if [[ -f "$file" ]]; then
        mapfile -t managed_components <"$file"
    fi

    local remove_all=0
    if ((${#managed_packages[@]} == 0 && ${#managed_components[@]} == 0)); then
        echo "No build dependencies are recorded as installed by this script."
        if ! prompt_yes "Remove all known build dependencies anyway? This may affect other software."; then
            echo "Nothing removed."
            return 0
        fi
        remove_all=1
    else
        if ! prompt_yes "Remove the build dependencies installed by this script?"; then
            echo "Nothing removed."
            return 0
        fi
    fi

    REMOVE_SYSTEM_PKGS=()
    if ((remove_all)); then
        local pkg
        for pkg in "${SYSTEM_PACKAGE_NAMES[@]}"; do
            if package_is_installed "$pkg"; then
                REMOVE_SYSTEM_PKGS+=("$pkg")
            fi
        done
        REMOVE_WEST=1
        REMOVE_PYELFTOOLS=1
        REMOVE_SDK=1
    else
        REMOVE_SYSTEM_PKGS=("${managed_packages[@]}")
        REMOVE_WEST=0
        REMOVE_PYELFTOOLS=0
        REMOVE_SDK=0
        local component
        for component in "${managed_components[@]}"; do
            case "$component" in
                west) REMOVE_WEST=1 ;;
                pyelftools) REMOVE_PYELFTOOLS=1 ;;
                sdk) REMOVE_SDK=1 ;;
            esac
        done
    fi

    build_remove_plan
    deps_run_plan || return 1

    if ((REMOVE_HAD_ERRORS)); then
        echo "Dependency removal finished with warnings." >&2
        return 1
    fi
    echo "Build dependencies removed."
}

# ---------------------------------------------------------------------------
# Dependency plans
# ---------------------------------------------------------------------------

build_install_plan() {
    local reinstall="${1:-0}"
    deps_plan_reset

    if ((reinstall)); then
        deps_plan_add 25 60 "Reinstall system packages" reinstall_system_packages
        deps_plan_add 10 20 "Reinstall west via pipx" reinstall_west
        deps_plan_add 5 10 "Inject pyelftools into west" install_pyelftools
        deps_plan_add 45 300 "Download Zephyr SDK $ZEPHYR_SDK_VERSION" download_sdk
        deps_plan_add 15 90 "Set up Zephyr SDK $ZEPHYR_SDK_VERSION" setup_sdk
        return 0
    fi

    if ((${#MISSING_SYSTEM_PKGS[@]} > 0)); then
        deps_plan_add 25 60 "Install system packages (${MISSING_SYSTEM_PKGS[*]})" install_system_packages
    fi
    if ((MISSING_WEST != 0)); then
        deps_plan_add 10 20 "Install west via pipx" install_west
    fi
    if ((MISSING_PYELFTOOLS != 0)); then
        deps_plan_add 5 10 "Inject pyelftools into west" install_pyelftools
    fi
    if ((MISSING_SDK != 0)); then
        deps_plan_add 45 300 "Download Zephyr SDK $ZEPHYR_SDK_VERSION" download_sdk
        deps_plan_add 15 90 "Set up Zephyr SDK $ZEPHYR_SDK_VERSION" setup_sdk
    fi
}

build_remove_plan() {
    deps_plan_reset

    if ((${#REMOVE_SYSTEM_PKGS[@]} > 0)); then
        deps_plan_add 20 30 "Remove system packages (${REMOVE_SYSTEM_PKGS[*]})" remove_system_packages
    fi
    if ((REMOVE_WEST != 0)); then
        deps_plan_add 5 5 "Remove west" remove_west
    fi
    if ((REMOVE_PYELFTOOLS != 0)); then
        deps_plan_add 5 5 "Remove pyelftools from west" remove_pyelftools
    fi
    if ((REMOVE_SDK != 0)); then
        deps_plan_add 20 10 "Remove Zephyr SDK" remove_sdk
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

init_sdk_platform

if ((DRY_RUN)) && [[ -z "$ACTION" ]]; then
    echo "--dry-run is only supported together with --install-deps, --remove-deps or --reinstall-deps." >&2
    exit 2
fi

case "$ACTION" in
    install)
        install_dependencies 1
        exit $?
        ;;
    remove)
        remove_dependencies
        exit $?
        ;;
    reinstall)
        reinstall_dependencies
        exit $?
        ;;
esac

if ((SKIP_DEPS_CHECK)); then
    echo "Skipping build dependency check (--skip-deps-check)."
else
    init_distro
    check_dependencies
    if ! dependencies_complete; then
        print_missing_dependencies
        if ! prompt_yes "Install missing build dependencies now?"; then
            echo "Build dependencies are required; not starting the build." >&2
            echo "Run '$0 --install-deps' to install them." >&2
            exit 1
        fi
        install_dependencies 1 1 || exit 1
    fi
fi

if ! (cd "$SCRIPT_DIR" && west topdir >/dev/null 2>&1); then
    echo "West workspace is not initialized in $SCRIPT_DIR." >&2
    echo "Prepare it first:" >&2
    echo "  cd $(printf '%q' "$SCRIPT_DIR")" >&2
    echo "  west init -l app/" >&2
    echo "  west update" >&2
    echo "  (cd zephyr && git am ../0001-esb-nrf-fix.patch)" >&2
    exit 1
fi

CONFIG_FILE="$SCRIPT_DIR/app/boards/shields/keychron/b1/us/keychron_b1_us.conf"
OVERLAY_FILE="$SCRIPT_DIR/app/boards/shields/keychron/b1/us/keychron_b1_us.overlay"
CONFIG_BACKUP="$(mktemp)"
OVERLAY_BACKUP="$(mktemp)"

restore_all() {
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    cp "$OVERLAY_BACKUP" "$OVERLAY_FILE"
    rm -f "$CONFIG_BACKUP"
    rm -f "$OVERLAY_BACKUP"
}

trap restore_all EXIT INT TERM HUP
cp "$CONFIG_FILE" "$CONFIG_BACKUP"
cp "$OVERLAY_FILE" "$OVERLAY_BACKUP"

if [[ "$KEYBOARD_ID" != "blue" ]]; then
    sed -E -i \
        -e "s|^(CONFIG_KEYCHRON_B1_COLOR=).*|\\1\"$KEYBOARD_ID\"|" \
        -e "s|^(CONFIG_USB_DEVICE_PRODUCT=)\"b1-[^\"]+-usb\"|\\1\"b1-$KEYBOARD_ID-usb\"|" \
        -e "s|^(CONFIG_BT_DIS_MODEL=)\"b1-[^\"]+\"|\\1\"b1-$KEYBOARD_ID\"|" \
        -e "s|^(CONFIG_ZMK_KEYBOARD_NAME=)\"b1-[^\"]+\"|\\1\"b1-$KEYBOARD_ID\"|" \
        "$CONFIG_FILE"
fi

if [[ "$MATRIX_REV" == "2025" ]]; then
    python3 - "$OVERLAY_FILE" <<'PY'
import re
import sys

path = sys.argv[1]
matrix_2025 = [
    (7, 5), (1, 2), (3, 4), (1, 14), (1, 4), (2, 2), (4, 2), (2, 5),
    (2, 6), (2, 7), (2, 10), (2, 8), (3, 7), (5, 8),
    (0, 17), (1, 0), (1, 15), (1, 1), (3, 6), (1, 12), (1, 13), (5, 5),
    (5, 6), (5, 7), (5, 10), (1, 6), (1, 7), (1, 8),
    (0, 5), (0, 10), (0, 8), (0, 9), (0, 13), (0, 14), (3, 5), (3, 1),
    (1, 3), (2, 4), (1, 11), (4, 6), (4, 7), (4, 10),
    (5, 17), (0, 4), (0, 6), (0, 7), (0, 2), (1, 17), (6, 8), (1, 10),
    (3, 2), (1, 9), (6, 5), (6, 7), (2, 1),
    (0, 16), (0, 0), (0, 15), (0, 1), (0, 12), (0, 11), (7, 6), (7, 11),
    (7, 10), (7, 8), (7, 9), (5, 15),
    (1, 5), (3, 10), (6, 17), (0, 3), (4, 0), (2, 9), (3, 17), (2, 17),
    (4, 17), (7, 17),
    (8, 0), (8, 1), (8, 2), (8, 3), (8, 4),
]

with open(path, encoding="utf-8") as f:
    text = f.read()

state = {"idx": 0}

def repl(match):
    idx = state["idx"]
    if idx >= len(matrix_2025):
        return match.group(0)
    row, col = matrix_2025[idx]
    state["idx"] += 1
    return "RC({}, {})".format(row, col)

patched = re.sub(r"RC\(\s*\d+\s*,\s*\d+\s*\)", repl, text, count=len(matrix_2025))
if state["idx"] != len(matrix_2025):
    raise SystemExit(
        "matrix 2025 patch failed: expected {} RC entries, patched {}"
        .format(len(matrix_2025), state["idx"])
    )

with open(path, "w", encoding="utf-8") as f:
    f.write(patched)
PY
fi

cd "$SCRIPT_DIR/app"
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR="$ZEPHYR_SDK_DIR"

west build -b keychron -p always -- -DSHIELD=keychron_b1_us

BRANCH_NAME="$(git branch --show-current)"
UF2_NAME="b1_${BRANCH_NAME}_${MATRIX_SKU}_${KEYBOARD_ID}.uf2"
cp ./build/zephyr/zmk.uf2 "$HOME/Downloads/$UF2_NAME"
