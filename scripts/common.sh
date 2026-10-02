#!/bin/bash
# ==============================================================================
# File: scripts/common.sh
# Thư viện tiện ích dùng chung: màu sắc, stage tracker, checkpoint/resume, error handling
# ==============================================================================

# Thiết lập bash an toàn
set -o pipefail

# Luôn bổ sung path brew và standard paths nếu có trên macOS
if [ -d "/opt/homebrew/bin" ]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi
if [ -d "/usr/local/bin" ]; then
    export PATH="/usr/local/bin:$PATH"
fi

# --- Môi trường Cross-Compile (Environment Sanitization) ---
# Tẩy sạch các cờ và biến của hệ điều hành Host (Homebrew, .zshrc, .bashrc)
# để ngăn ngừa trình biên dịch nhặt nhầm thư viện/header của macOS khi cross-compile Android/iOS
sanitize_build_env() {
    export PKG_CONFIG_PATH=""
    export PKG_CONFIG_LIBDIR="/dev/null"
    unset LDFLAGS
    unset CPPFLAGS
    unset CFLAGS
    unset CXXFLAGS
}

# Tự động làm sạch môi trường ngay khi nạp common.sh
sanitize_build_env

# Màu sắc terminal
if [ -t 1 ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_MAGENTA='\033[0;35m'
    C_CYAN='\033[0;36m'
    C_WHITE='\033[1;37m'
    C_BG_RED='\033[41m'
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_MAGENTA=''
    C_CYAN=''
    C_WHITE=''
    C_BG_RED=''
fi

# Định nghĩa các thư mục cốt lõi
SCRIPT_DIR_COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR_COMMON}/.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/.build_state"
LOGS_DIR="${PROJECT_ROOT}/logs"

mkdir -p "${STATE_DIR}" "${LOGS_DIR}"

# Biến theo dõi trạng thái hiện tại
CURRENT_STAGE_PLATFORM=""
CURRENT_STAGE_ID=""
CURRENT_STAGE_DISPLAY=""
CURRENT_STAGE_LOG=""
CURRENT_STAGE_START_TIME=0

# --- Logging Functions ---
log_info() {
    echo -e "${C_BLUE}ℹ  ${C_RESET}$*"
}

log_success() {
    echo -e "${C_GREEN}✔  ${C_BOLD}$*${C_RESET}"
}

log_warn() {
    echo -e "${C_YELLOW}⚠  ${C_BOLD}$*${C_RESET}"
}

log_error() {
    echo -e "${C_RED}✖  ${C_BOLD}$*${C_RESET}"
}

log_header() {
    echo -e "\n${C_CYAN}${C_BOLD}======================================================================${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}  $*${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}======================================================================${C_RESET}\n"
}

log_stage() {
    echo -e "\n${C_MAGENTA}${C_BOLD}▶▶ [$CURRENT_STAGE_PLATFORM] $1${C_RESET}"
}

# --- Checkpoint / Resume Management ---
get_checkpoint_file() {
    local platform="$1"
    local stage_id="$2"
    echo "${STATE_DIR}/${platform}/${stage_id}.done"
}

is_stage_done() {
    local platform="$1"
    local stage_id="$2"
    local cp_file
    cp_file="$(get_checkpoint_file "$platform" "$stage_id")"
    [ -f "$cp_file" ]
}

mark_stage_done() {
    local platform="$1"
    local stage_id="$2"
    local cp_file
    cp_file="$(get_checkpoint_file "$platform" "$stage_id")"
    mkdir -p "$(dirname "$cp_file")"
    date "+%Y-%m-%d %H:%M:%S" > "$cp_file"
}

clear_stage() {
    local platform="$1"
    local stage_id="$2"
    local cp_file
    cp_file="$(get_checkpoint_file "$platform" "$stage_id")"
    rm -f "$cp_file"
}

clear_platform_stages() {
    local platform="$1"
    if [ -d "${STATE_DIR}/${platform}" ]; then
        rm -rf "${STATE_DIR:?}/${platform}"
        log_info "Đã xóa toàn bộ checkpoint của ${platform}."
    fi
}

clear_all_stages() {
    rm -rf "${STATE_DIR:?}"/*
    log_info "Đã xóa toàn bộ checkpoint của dự án."
}

# --- Error Trapping & Reporting ---
format_elapsed_time() {
    local start=$1
    local end=$2
    local elapsed=$((end - start))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    printf "%02dm %02ds" "$minutes" "$seconds"
}

report_stage_failure() {
    local exit_code=$1
    local end_time
    end_time=$(date +%s)
    local duration
    duration=$(format_elapsed_time "$CURRENT_STAGE_START_TIME" "$end_time")

    echo -e "\n${C_RED}${C_BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_RED}${C_BOLD}║ ✖ BUILD FAILED: GIAI ĐOẠN GẶP LỖI                                             ║${C_RESET}"
    echo -e "${C_RED}${C_BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_WHITE}${C_BOLD}  Nền tảng    :${C_RESET} ${CURRENT_STAGE_PLATFORM}"
    echo -e "${C_WHITE}${C_BOLD}  Giai đoạn   :${C_RESET} ${CURRENT_STAGE_DISPLAY} (ID: ${CURRENT_STAGE_ID})"
    echo -e "${C_WHITE}${C_BOLD}  Thời gian   :${C_RESET} ${duration}"
    echo -e "${C_WHITE}${C_BOLD}  Exit Code   :${C_RESET} ${exit_code}"
    echo -e "${C_WHITE}${C_BOLD}  File Log    :${C_RESET} ${CURRENT_STAGE_LOG}"
    echo -e "${C_RED}${C_BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}  15 DÒNG LOG CUỐI CÙNG TRƯỚC KHI THẤT BẠI:${C_RESET}"
    echo -e "${C_RED}--------------------------------------------------------------------------------${C_RESET}"
    if [ -f "$CURRENT_STAGE_LOG" ]; then
        tail -n 15 "$CURRENT_STAGE_LOG" | sed 's/^/  /'
    else
        echo "  (Không tìm thấy file log)"
    fi
    echo -e "${C_RED}--------------------------------------------------------------------------------${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}  💡 CÁCH TIẾP TỤC (RESUME):${C_RESET}"
    echo -e "  Sau khi kiểm tra nguyên nhân và sửa lỗi, bạn chỉ cần chạy lại lệnh cũ:"
    if [ "$CURRENT_STAGE_PLATFORM" = "android" ]; then
        echo -e "  ${C_GREEN}${C_BOLD}./build.sh android --resume${C_RESET}"
    elif [ "$CURRENT_STAGE_PLATFORM" = "ios" ]; then
        echo -e "  ${C_GREEN}${C_BOLD}./build.sh ios --resume${C_RESET}"
    else
        echo -e "  ${C_GREEN}${C_BOLD}./build.sh all --resume${C_RESET}"
    fi
    echo -e "  Hệ thống sẽ ${C_BOLD}tự động bỏ qua các bước đã hoàn thành${C_RESET} và tiếp tục từ bước này!"
    echo -e "${C_RED}${C_BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}\n"
}

# Wrapper thực thi một stage với khả năng resume và log độc lập
# Cách dùng: run_stage <platform> <stage_id> <display_name> <command...>
run_stage() {
    local platform="$1"
    local stage_id="$2"
    local display_name="$3"
    shift 3

    CURRENT_STAGE_PLATFORM="$platform"
    CURRENT_STAGE_ID="$stage_id"
    CURRENT_STAGE_DISPLAY="$display_name"
    CURRENT_STAGE_LOG="${LOGS_DIR}/${platform}_${stage_id}.log"
    CURRENT_STAGE_START_TIME=$(date +%s)

    mkdir -p "$(dirname "$CURRENT_STAGE_LOG")"

    # Kiểm tra nếu stage đã hoàn tất
    if [ "${RESUME_MODE:-1}" = "1" ] && is_stage_done "$platform" "$stage_id"; then
        local done_time
        done_time=$(cat "$(get_checkpoint_file "$platform" "$stage_id")" 2>/dev/null || echo "Trước đó")
        echo -e "${C_YELLOW}⏩ [SKIPPED] ${display_name}${C_RESET} (Đã xong lúc: ${done_time})"
        return 0
    fi

    log_stage "${display_name}..."
    echo -e "   ${C_BLUE}Ghi log tại:${C_RESET} ${CURRENT_STAGE_LOG}"

    # Bắt đầu ghi log
    {
        echo "================================================================================"
        echo "STAGE: [${platform}] ${display_name} (${stage_id})"
        echo "TIME : $(date "+%Y-%m-%d %H:%M:%S")"
        echo "CMD  : $*"
        echo "================================================================================"
    } > "$CURRENT_STAGE_LOG"

    # Thực thi lệnh trong background và chuyển toàn bộ output vào file log
    local exit_code=0
    "$@" >> "$CURRENT_STAGE_LOG" 2>&1 &
    local cmd_pid=$!

    # Bắt tín hiệu ngắt (Ctrl+C / SIGTERM) để tránh zombie process và dọn dẹp màn hình
    local last_rendered_lines=0
    trap '
        if [ -n "$cmd_pid" ] && kill -0 "$cmd_pid" 2>/dev/null; then
            kill "$cmd_pid" 2>/dev/null
        fi
        if [ "$last_rendered_lines" -gt 0 ]; then
            for ((k=0; k<last_rendered_lines; k++)); do
                printf "\033[1A\033[2K\r"
            done
        fi
        exit 130
    ' INT TERM

    # Nếu đang chạy trên interactive terminal (TTY)
    if [ -t 1 ]; then
        local max_lines=10
        local cols
        cols=$(tput cols 2>/dev/null || echo 100)
        [ "$cols" -lt 40 ] && cols=80
        local max_width=$((cols - 8))

        # Hiển thị live 10 dòng log mới nhất trong suốt quá trình chạy
        while kill -0 "$cmd_pid" 2>/dev/null; do
            if [ -s "$CURRENT_STAGE_LOG" ]; then
                # Xóa các dòng log đã in ở lần render trước
                if [ "$last_rendered_lines" -gt 0 ]; then
                    for ((k=0; k<last_rendered_lines; k++)); do
                        printf "\033[1A\033[2K\r"
                    done
                fi

                # Đọc tối đa 10 dòng log cuối cùng
                local lines=()
                while IFS= read -r line; do
                    lines+=("$line")
                done < <(tail -n "$max_lines" "$CURRENT_STAGE_LOG" 2>/dev/null)

                last_rendered_lines=${#lines[@]}
                for l in "${lines[@]}"; do
                    local trunc_line="${l:0:$max_width}"
                    printf "   ${C_CYAN}│${C_RESET} \033[90m%s${C_RESET}\n" "$trunc_line"
                done
            fi
            sleep 0.3
        done

        wait "$cmd_pid" || exit_code=$?

        # Khi giai đoạn đã hoàn tất: LOẠI BỎ TOÀN BỘ CÁC DÒNG LOG LIVE
        if [ "$last_rendered_lines" -gt 0 ]; then
            for ((k=0; k<last_rendered_lines; k++)); do
                printf "\033[1A\033[2K\r"
            done
        fi
    else
        # Khi chạy không có TTY (pipe, background, non-interactive)
        wait "$cmd_pid" || exit_code=$?
    fi

    # Huỷ trap tùy chỉnh sau khi lệnh đã xong
    trap - INT TERM

    local end_time
    end_time=$(date +%s)
    local duration
    duration=$(format_elapsed_time "$CURRENT_STAGE_START_TIME" "$end_time")

    if [ $exit_code -eq 0 ]; then
        mark_stage_done "$platform" "$stage_id"
        log_success "${display_name} hoàn tất! (${duration})"

        # Tự động vô hiệu hóa stage đóng gói cuối nếu có bước biên dịch mới chạy
        if [ "$platform" = "ios" ] && [ "$stage_id" != "create_xcframework" ]; then
            clear_stage "ios" "create_xcframework"
        fi
        if [ "$platform" = "android" ] && [ "$stage_id" != "export_java_headers" ]; then
            clear_stage "android" "export_java_headers"
        fi

        return 0
    else
        report_stage_failure "$exit_code"
        return $exit_code
    fi
}

# --- Utility Functions ---
version_ge() {
    # So sánh phiên bản dạng X.Y hoặc X.Y.Z: trả về 0 nếu $1 >= $2
    awk -v v1="$1" -v v2="$2" 'BEGIN {
        split(v1, a, ".");
        split(v2, b, ".");
        for (i = 1; i <= 3; i++) {
            a[i] = a[i] + 0;
            b[i] = b[i] + 0;
            if (a[i] > b[i]) exit 0;
            if (a[i] < b[i]) exit 1;
        }
        exit 0;
    }'
}

# --- Toolchain & Environment Verification ---
check_system_tools() {
    # Bổ sung path brew nếu có trên macOS
    if [ -d "/opt/homebrew/bin" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    fi
    if [ -d "/usr/local/bin" ]; then
        export PATH="/usr/local/bin:$PATH"
    fi

    local missing=()
    for tool in git make curl swig unzip tar; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Thiếu các công cụ hệ thống bắt buộc: ${missing[*]}"
        return 1
    fi
    return 0
}

get_ndk_version() {
    local ndk_path="$1"
    if [ -f "${ndk_path}/source.properties" ]; then
        grep "Pkg.Revision" "${ndk_path}/source.properties" | cut -d '=' -f 2 | tr -d ' \r\n'
    fi
}

# ==============================================================================
# TÌM KIẾM HOẶC TỰ ĐỘNG TẢI ANDROID NDK
# Thứ tự ưu tiên:
# 1. Thư mục xử lý / build (cùng cấp với openssl và oboe: ví dụ android-build/)
# 2. Trên máy host (biến ANDROID_NDK_ROOT hoặc các đường dẫn SDK phổ biến)
# 3. Tự động tải Android NDK r28b từ Google và giải nén vào thư mục build
# ==============================================================================
resolve_android_ndk() {
    local build_dir="$1"
    local required_version="27"
    local default_ndk_tag="${NDK_VERSION:-r28b}"

    # 1. Kiểm tra trong thư mục xử lý / build trước (cùng cấp openssl, oboe)
    if [ -n "$build_dir" ] && [ -d "$build_dir" ]; then
        log_info "Kiểm tra Android NDK trong thư mục xử lý: ${build_dir}..."

        local local_candidates=()
        [ -d "${build_dir}/android-ndk-${default_ndk_tag}" ] && local_candidates+=("${build_dir}/android-ndk-${default_ndk_tag}")
        while IFS= read -r dir; do
            [ -n "$dir" ] && local_candidates+=("$dir")
        done < <(find "${build_dir}" -maxdepth 1 -type d -name "android-ndk-*" 2>/dev/null)

        for candidate in "${local_candidates[@]}"; do
            if [ -f "${candidate}/source.properties" ]; then
                local ver
                ver=$(get_ndk_version "$candidate")
                if [ -n "$ver" ] && version_ge "$ver" "$required_version"; then
                    log_success "Tìm thấy Android NDK tại thư mục build: ${candidate} (v${ver})"
                    export ANDROID_NDK_ROOT="$candidate"
                    return 0
                fi
            fi
        done
    fi

    # 2. Nếu không có ở thư mục build, tìm kiếm trên máy host
    log_info "Không tìm thấy NDK trong thư mục build, đang tìm kiếm NDK trên máy..."

    # Nếu người dùng đã chỉ định qua biến môi trường hoặc cờ --ndk
    if [ -n "${ANDROID_NDK_ROOT:-}" ] && [ -d "${ANDROID_NDK_ROOT}" ]; then
        local ver
        ver=$(get_ndk_version "${ANDROID_NDK_ROOT}")
        if [ -n "$ver" ] && version_ge "$ver" "$required_version"; then
            log_success "Sử dụng Android NDK trên máy: ${ANDROID_NDK_ROOT} (v${ver})"
            return 0
        fi
    fi

    # Quét các đường dẫn NDK phổ biến trên hệ thống macOS / Linux
    local system_candidates=(
        "$HOME/Library/Android/sdk/ndk/28."*
        "$HOME/Library/Android/sdk/ndk/27."*
        "$ANDROID_HOME/ndk/28."*
        "$ANDROID_HOME/ndk/27."*
        "$HOME/Library/Android/sdk/ndk"/*
        "$ANDROID_HOME/ndk"/*
        "$ANDROID_HOME/ndk-bundle"
        "/usr/local/share/android-ndk"
        "/opt/android-ndk"
    )

    for candidate in "${system_candidates[@]}"; do
        if [ -d "$candidate" ] && [ -f "${candidate}/source.properties" ]; then
            local ver
            ver=$(get_ndk_version "$candidate")
            if [ -n "$ver" ] && version_ge "$ver" "$required_version"; then
                log_success "Tìm thấy Android NDK phù hợp trên hệ thống: ${candidate} (v${ver})"
                export ANDROID_NDK_ROOT="$candidate"
                return 0
            fi
        fi
    done

    # 3. Nếu không tìm thấy NDK phù hợp trên máy -> Tự động tải NDK 28 về thư mục build
    log_warn "Không tìm thấy NDK (>= ${required_version}) trong thư mục build hoặc trên máy!"
    log_info "Tiến hành tự động tải Android NDK ${default_ndk_tag} từ Google về thư mục build: ${build_dir}..."

    mkdir -p "${build_dir}"

    local os_tag="darwin"
    if [[ "$(uname -s)" == "Linux" ]]; then
        os_tag="linux"
    fi

    local ndk_archive_name="android-ndk-${default_ndk_tag}-${os_tag}.zip"
    local ndk_url="https://dl.google.com/android/repository/${ndk_archive_name}"
    local ndk_zip="${build_dir}/${ndk_archive_name}"

    log_info "Đang tải: ${ndk_url}..."
    if ! curl -# -fSL "${ndk_url}" -o "${ndk_zip}"; then
        log_error "Tải Android NDK thất bại từ: ${ndk_url}"
        rm -f "${ndk_zip}"
        return 1
    fi

    log_info "Giải nén Android NDK vào ${build_dir} (khoảng 1-2 phút)..."
    if ! unzip -q -o "${ndk_zip}" -d "${build_dir}"; then
        log_error "Giải nén Android NDK thất bại!"
        rm -f "${ndk_zip}"
        return 1
    fi
    rm -f "${ndk_zip}"

    local downloaded_ndk="${build_dir}/android-ndk-${default_ndk_tag}"
    if [ -d "${downloaded_ndk}" ] && [ -f "${downloaded_ndk}/source.properties" ]; then
        local ver
        ver=$(get_ndk_version "${downloaded_ndk}")
        log_success "Đã cài đặt thành công Android NDK tại: ${downloaded_ndk} (v${ver})"
        export ANDROID_NDK_ROOT="${downloaded_ndk}"
        return 0
    else
        log_error "Không tìm thấy thư mục NDK hợp lệ sau khi giải nén!"
        return 1
    fi
}

check_android_env() {
    log_info "Kiểm tra môi trường Android..."

    if [ -z "${ANDROID_NDK_ROOT}" ] || [ ! -d "${ANDROID_NDK_ROOT}" ]; then
        log_error "Không tìm thấy ANDROID_NDK_ROOT!"
        log_error "Vui lòng chỉ định bằng cờ: ./build.sh android --ndk /path/to/ndk"
        log_error "Hoặc cài đặt NDK trong Android SDK."
        return 1
    fi

    # Kiểm tra toolchain LLVM bên trong NDK
    local llvm_bin=""
    if [ -d "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin" ]; then
        llvm_bin="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    elif [ -d "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-arm64/bin" ]; then
        llvm_bin="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-arm64/bin"
    elif [ -d "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin" ]; then
        llvm_bin="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    fi

    if [ -z "$llvm_bin" ]; then
        log_error "Không tìm thấy thư mục llvm toolchain bin trong: ${ANDROID_NDK_ROOT}"
        return 1
    fi

    export PATH="${llvm_bin}:${PATH}"

    # Kiểm tra phiên bản NDK
    local ndk_rev=""
    if [ -f "${ANDROID_NDK_ROOT}/source.properties" ]; then
        ndk_rev=$(grep "Pkg.Revision" "${ANDROID_NDK_ROOT}/source.properties" | cut -d '=' -f 2 | tr -d ' ')
    fi
    local ndk_major=""
    if [ -n "$ndk_rev" ]; then
        ndk_major=$(echo "$ndk_rev" | cut -d '.' -f 1)
    fi

    # Ràng buộc: NDK >= 27 cho các phiên bản PJSIP mới (>= 2.15 hoặc master/main)
    local current_pjsip="${PJSIP_VERSION:-2.17}"
    local require_ndk_27=0
    if [[ "$current_pjsip" =~ ^(master|main|trunk)$ ]]; then
        require_ndk_27=1
    elif version_ge "$current_pjsip" "2.15"; then
        require_ndk_27=1
    fi

    if [ $require_ndk_27 -eq 1 ]; then
        if [ -n "$ndk_major" ] && [ "$ndk_major" -lt 27 ]; then
            log_error "RÀNG BUỘC PHIÊN BẢN NDK THẤT BẠI:"
            log_error "  PJSIP v${current_pjsip} yêu cầu Android NDK phiên bản r27 trở lên!"
            log_error "  Phiên bản NDK hiện tại phát hiện: r${ndk_major} (chi tiết: ${ndk_rev})"
            log_error "  Đường dẫn NDK hiện tại: ${ANDROID_NDK_ROOT}"
            log_error "  Vui lòng nâng cấp Android NDK lên >= 27 hoặc chỉ định qua: ./build.sh android --ndk /path/to/ndk-27+"
            return 1
        fi
    fi

    log_success "Android NDK: ${ANDROID_NDK_ROOT} (r${ndk_major:-unknown}, ${ndk_rev})"

    # Kiểm tra Java
    if [ -z "${JAVA_HOME}" ] || [ ! -d "${JAVA_HOME}" ]; then
        log_warn "Chưa đặt JAVA_HOME. Thử tự động nhận diện..."
        if [ -x "/usr/libexec/java_home" ]; then
            JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || echo "")
        fi
    fi

    if [ -n "${JAVA_HOME}" ] && [ -d "${JAVA_HOME}" ]; then
        export JAVA_HOME
        export PATH="${JAVA_HOME}/bin:${PATH}"
        log_success "Java Home  : ${JAVA_HOME}"
    else
        log_warn "Không tìm thấy JAVA_HOME hợp lệ. Việc biên dịch SWIG Java có thể bị ảnh hưởng nếu javac không có trong PATH."
    fi

    return 0
}

check_ios_env() {
    log_info "Kiểm tra môi trường Apple / iOS..."

    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "Biên dịch iOS yêu cầu hệ điều hành macOS (Darwin)."
        return 1
    fi

    if ! xcode-select -p >/dev/null 2>&1; then
        log_error "Xcode Command Line Tools chưa được cài đặt (chạy: xcode-select --install)."
        return 1
    fi

    if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
        log_error "Không tìm thấy iPhoneOS SDK trong Xcode. Hãy đảm bảo bạn đã cài đặt Xcode đầy đủ từ App Store."
        return 1
    fi

    log_success "Xcode SDK Path: $(xcrun --sdk iphoneos --show-sdk-path)"
    return 0
}
