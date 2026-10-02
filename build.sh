#!/bin/bash
# ==============================================================================
# Script: build.sh
# Trình điều khiển build PJSIP toàn diện cho iOS và Android
# Hỗ trợ: Build đồng thời cả hai hoặc từng phần, tùy biến phiên bản & tính năng,
#         chia giai đoạn rõ ràng, báo lỗi chi tiết và tự động resume.
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nạp thư viện dùng chung & cấu hình mặc định
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/scripts/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config.default.sh"

# Thiết lập giá trị mặc định cho phiên làm việc
ACTION=""
CUSTOM_PJSIP_VER=""
CUSTOM_OPENSSL_VER=""
CUSTOM_OBOE_VER=""
CUSTOM_OBOE=""
CUSTOM_VIDEO=""
CUSTOM_SSL=""
CUSTOM_ABIS=""
CUSTOM_TARGETS=""
CUSTOM_NDK=""
CUSTOM_JAVA=""
CUSTOM_RESUME=1 # Mặc định bật chế độ resume thông minh
FORCE_REBUILD=0

# Hiển thị Banner
show_banner() {
    echo -e "${C_CYAN}${C_BOLD}"
    cat << "EOF"
  ____        _ _     _   ____       _     _
 | __ ) _   _(_) | __| | |  _ \     | |___(_)_ __
 |  _ \| | | | | |/ _` | | |_) | _  | / __| | '_ \
 | |_) | |_| | | | (_| | |  __/ | |_| \__ \ | |_) |
 |____/ \__,_|_|_|\__,_| |_|     \___/|___/_| .__/
                                            |_|
   Hệ thống build PJSIP chuyên nghiệp cho Android & iOS
EOF
    echo -e "${C_RESET}"
}

# Hiển thị Hướng dẫn sử dụng
show_help() {
    show_banner
    echo -e "${C_WHITE}${C_BOLD}CÁCH SỬ DỤNG:${C_RESET}"
    echo -e "  ./build.sh <lệnh> [tùy chọn...]\n"

    echo -e "${C_WHITE}${C_BOLD}LỆNH CHÍNH (COMMAND):${C_RESET}"
    echo -e "  ${C_GREEN}all${C_RESET}                 Biên dịch cả Android và iOS"
    echo -e "  ${C_GREEN}android${C_RESET}             Chỉ biên dịch thư viện cho Android"
    echo -e "  ${C_GREEN}ios${C_RESET}                 Chỉ biên dịch thư viện cho iOS / Apple Platforms"
    echo -e "  ${C_GREEN}clean${C_RESET}               Dọn dẹp bản build, cache và checkpoints"
    echo -e "  ${C_GREEN}status${C_RESET}              Kiểm tra tiến độ và các giai đoạn đã hoàn thành\n"

    echo -e "${C_WHITE}${C_BOLD}TÙY CHỌN PHIÊN BẢN & TÍNH NĂNG:${C_RESET}"
    echo -e "  --pjsip-version <v>     Phiên bản PJSIP git tag/branch (Mặc định: 2.16)"
    echo -e "  --openssl-version <v>   Phiên bản OpenSSL (Mặc định: 3.4.2)"
    echo -e "  --oboe-version <v>      Phiên bản Oboe cho Android (1.10.0 hoặc 1.9.3)"
    echo -e "  --with-oboe             Bật hỗ trợ Oboe audio low-latency (Android)"
    echo -e "  --without-oboe          Tắt hỗ trợ Oboe"
    echo -e "  --with-video            Bật hỗ trợ Video (VideoToolbox / Media) (Mặc định: BẬT)"
    echo -e "  --without-video         Tắt hỗ trợ Video"
    echo -e "  --with-ssl              Bật hỗ trợ SSL/TLS (Mặc định: bật)"
    echo -e "  --without-ssl           Tắt hỗ trợ SSL/TLS\n"

    echo -e "${C_WHITE}${C_BOLD}TÙY CHỌN KIẾN TRÚC & MỤC TIÊU:${C_RESET}"
    echo -e "  --abi <list>            Chỉ định Android ABI cần build, ngăn cách bởi dấu phẩy hoặc khoảng trắng"
    echo -e "                          (Ví dụ: --abi arm64-v8a hoặc --abi arm64-v8a,armeabi-v7a)"
    echo -e "                          Hỗ trợ: arm64-v8a, armeabi-v7a, x86_64, x86"
    echo -e "  --target <list>         Chỉ định iOS/Apple Targets cần build, ngăn cách bởi dấu phẩy hoặc khoảng trắng"
    echo -e "                          (Ví dụ: --target device hoặc --target device,simulator)"
    echo -e "                          Hỗ trợ: device, simulator, catalyst, macos, all"
    echo -e "                          (Mặc định: đầy đủ 4 kiến trúc: ios-arm64, ios-arm64_x86_64-simulator,"
    echo -e "                           ios-arm64_x86_64-maccatalyst, macos-arm64_x86_64)"
    echo -e "  --android-api <level>   Android API Level / Min SDK (Mặc định: 24)"
    echo -e "  --ndk-version <v>       Phiên bản Android NDK (Mặc định: r28b)"
    echo -e "  --ios-min-version <v>   iOS Deployment Target tối thiểu (Mặc định: 13.0)\n"

    echo -e "${C_WHITE}${C_BOLD}CƠ CHẾ RESUME & DỌN DẸP:${C_RESET}"
    echo -e "  --resume                Tự động tiếp tục từ bước bị gián đoạn/sửa lỗi (Mặc định: BẬT)"
    echo -e "  --rebuild, --no-resume  Xóa checkpoint và biên dịch lại từ đầu"
    echo -e "  --ndk <path>            Đường dẫn tới thư mục Android NDK"
    echo -e "  --java-home <path>      Đường dẫn tới JAVA_HOME"
    echo -e "  -h, --help              Hiển thị hướng dẫn này\n"

    echo -e "${C_WHITE}${C_BOLD}VÍ DỤ:${C_RESET}"
    echo -e "  ${C_CYAN}# 1. Build cả Android và iOS với cấu hình mặc định:${C_RESET}"
    echo -e "     ./build.sh all\n"
    echo -e "  ${C_CYAN}# 2. Chỉ build Android cho thiết bị thật (arm64-v8a) và tắt Oboe:${C_RESET}"
    echo -e "     ./build.sh android --abi arm64-v8a --without-oboe\n"
    echo -e "  ${C_CYAN}# 3. Chỉ build iOS cho cả thiết bị thật và máy ảo, có bật Video:${C_RESET}"
    echo -e "     ./build.sh ios --target device,simulator --with-video\n"
    echo -e "  ${C_CYAN}# 4. Khi gặp lỗi và đã sửa xong, tiếp tục build mà không mất thời gian:${C_RESET}"
    echo -e "     ./build.sh android --resume\n"
}

# Hiển thị trạng thái tiến độ các giai đoạn
show_status() {
    log_header "TRẠNG THÁI TIẾN ĐỘ CÁC GIAI ĐOẠN HIỆN TẠI"
    if [ ! -d "${STATE_DIR}" ] || [ -z "$(ls -A "${STATE_DIR}" 2>/dev/null)" ]; then
        log_info "Chưa có giai đoạn nào hoàn thành. Dự án đang ở trạng thái sạch."
        return 0
    fi

    for platform_dir in "${STATE_DIR}"/*; do
        if [ -d "$platform_dir" ]; then
            local plat
            plat=$(basename "$platform_dir")
            echo -e "${C_CYAN}${C_BOLD}Nền tảng: ${plat}${C_RESET}"
            for cp_file in "$platform_dir"/*.done; do
                if [ -f "$cp_file" ]; then
                    local stage_id
                    stage_id=$(basename "$cp_file" .done)
                    local time_str
                    time_str=$(cat "$cp_file")
                    echo -e "  ${C_GREEN}✔${C_RESET} [${stage_id}] - Hoàn thành: ${time_str}"
                fi
            done
        fi
    done
    echo ""
}

# Parse Command Line Arguments
while [ $# -gt 0 ]; do
    case "$1" in
        all|android|ios|clean|status)
            ACTION="$1"
            shift
            ;;
        --pjsip-version)
            CUSTOM_PJSIP_VER="$2"
            shift 2
            ;;
        --openssl-version)
            CUSTOM_OPENSSL_VER="$2"
            shift 2
            ;;
        --oboe-version)
            CUSTOM_OBOE_VER="$2"
            shift 2
            ;;
        --with-oboe)
            CUSTOM_OBOE="yes"
            shift
            ;;
        --without-oboe)
            CUSTOM_OBOE="no"
            shift
            ;;
        --with-video)
            CUSTOM_VIDEO="yes"
            shift
            ;;
        --without-video)
            CUSTOM_VIDEO="no"
            shift
            ;;
        --with-ssl)
            CUSTOM_SSL="yes"
            shift
            ;;
        --without-ssl)
            CUSTOM_SSL="no"
            shift
            ;;
        --abi)
            CUSTOM_ABIS="${2//,/ }"
            shift 2
            ;;
        --target)
            CUSTOM_TARGETS="${2//,/ }"
            if [ "$CUSTOM_TARGETS" = "all" ]; then
                CUSTOM_TARGETS="device simulator catalyst macos"
            fi
            shift 2
            ;;
        --ndk)
            CUSTOM_NDK="$2"
            shift 2
            ;;
        --ndk-version)
            CUSTOM_NDK_VERSION="$2"
            shift 2
            ;;
        --android-api|--api-level|--target-sdk)
            CUSTOM_ANDROID_API="$2"
            shift 2
            ;;
        --ios-min-version)
            CUSTOM_IOS_MIN_VERSION="$2"
            shift 2
            ;;
        --java-home)
            CUSTOM_JAVA="$2"
            shift 2
            ;;
        --resume)
            CUSTOM_RESUME=1
            shift
            ;;
        --rebuild|--no-resume)
            CUSTOM_RESUME=0
            FORCE_REBUILD=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Tùy chọn không hợp lệ: $1"
            echo "Chạy './build.sh --help' để xem hướng dẫn sử dụng."
            exit 1
            ;;
    esac
done

# Áp dụng các giá trị ghi đè nếu người dùng truyền
[ -n "$CUSTOM_PJSIP_VER" ]       && PJSIP_VERSION="$CUSTOM_PJSIP_VER"
[ -n "$CUSTOM_OPENSSL_VER" ]     && OPENSSL_VERSION="$CUSTOM_OPENSSL_VER"
[ -n "$CUSTOM_OBOE_VER" ]        && OBOE_VERSION="$CUSTOM_OBOE_VER"
[ -n "$CUSTOM_OBOE" ]            && ENABLE_OBOE="$CUSTOM_OBOE"
[ -n "$CUSTOM_VIDEO" ]           && ENABLE_VIDEO="$CUSTOM_VIDEO"
[ -n "$CUSTOM_SSL" ]             && ENABLE_SSL="$CUSTOM_SSL"
[ -n "$CUSTOM_ABIS" ]            && ANDROID_ABIS="$CUSTOM_ABIS"
[ -n "$CUSTOM_TARGETS" ]         && IOS_TARGETS="$CUSTOM_TARGETS"
[ -n "$CUSTOM_NDK" ]             && ANDROID_NDK_ROOT="$CUSTOM_NDK"
[ -n "$CUSTOM_NDK_VERSION" ]     && NDK_VERSION="$CUSTOM_NDK_VERSION"
[ -n "$CUSTOM_ANDROID_API" ]     && ANDROID_APP_PLATFORM="$CUSTOM_ANDROID_API"
[ -n "$CUSTOM_IOS_MIN_VERSION" ] && IOS_MIN_VERSION="$CUSTOM_IOS_MIN_VERSION"
[ -n "$CUSTOM_JAVA" ]            && JAVA_HOME="$CUSTOM_JAVA"

export PJSIP_VERSION
export OPENSSL_VERSION
export OBOE_VERSION
export ENABLE_OBOE
export ENABLE_VIDEO
export ENABLE_SSL
export ANDROID_ABIS
export IOS_TARGETS
export ANDROID_NDK_ROOT
export NDK_VERSION
export ANDROID_APP_PLATFORM
export IOS_MIN_VERSION
export JAVA_HOME
export OUTPUT_DIR
export RESUME_MODE="$CUSTOM_RESUME"

# Nếu người dùng chọn clean hoặc status
if [ "$ACTION" = "status" ]; then
    show_status
    exit 0
fi

if [ "$ACTION" = "clean" ]; then
    show_banner
    "${SCRIPT_DIR}/scripts/clean.sh" all
    exit 0
fi

# Nếu chưa chọn action
if [ -z "$ACTION" ]; then
    show_help
    exit 0
fi

show_banner

# Nếu yêu cầu force rebuild thì dọn dẹp checkpoint của action tương ứng trước
if [ "$FORCE_REBUILD" -eq 1 ]; then
    log_warn "Chế độ Rebuild được kích hoạt: Xóa bỏ các checkpoint cũ của [$ACTION]..."
    if [ "$ACTION" = "all" ]; then
        clear_all_stages
    else
        clear_platform_stages "$ACTION"
    fi
fi

# Thực thi lệnh tương ứng
case "$ACTION" in
    android)
        log_header "BẮT ĐẦU QUY TRÌNH BIÊN DỊCH CHO ANDROID"
        "${SCRIPT_DIR}/scripts/build_android.sh"
        ;;
    ios)
        log_header "BẮT ĐẦU QUY TRÌNH BIÊN DỊCH CHO IOS / APPLE PLATFORMS"
        "${SCRIPT_DIR}/scripts/build_ios.sh"
        ;;
    all)
        log_header "BẮT ĐẦU QUY TRÌNH BIÊN DỊCH CẢ ANDROID VÀ IOS"
        "${SCRIPT_DIR}/scripts/build_android.sh"
        "${SCRIPT_DIR}/scripts/build_ios.sh"
        log_header "🎉 CHÚC MỪNG! TOÀN BỘ QUY TRÌNH BIÊN DỊCH ĐÃ HOÀN TẤT THÀNH CÔNG!"
        log_success "Tất cả file artifacts đã được xuất tại: ${OUTPUT_DIR:-${SCRIPT_DIR}/output}"
        ;;
esac
