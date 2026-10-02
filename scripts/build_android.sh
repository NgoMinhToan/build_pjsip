#!/bin/bash
# ==============================================================================
# File: scripts/build_android.sh
# Script biên dịch PJSIP cho Android (OpenSSL, Oboe, PJSIP, SWIG Java)
# Hỗ trợ checkpoint, resume từng giai đoạn cho từng ABI
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Nạp thư viện chung và cấu hình
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/config.default.sh"

# Nhận các biến môi trường hoặc override
PJSIP_VERSION="${PJSIP_VERSION:-2.17}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.4.2}"
ENABLE_SSL="${ENABLE_SSL:-yes}"
ENABLE_VIDEO="${ENABLE_VIDEO:-yes}"
ENABLE_OBOE="${ENABLE_OBOE:-yes}"
OBOE_VERSION="${OBOE_VERSION:-1.10.0}"
ANDROID_APP_PLATFORM="${ANDROID_APP_PLATFORM:-24}"
ANDROID_ABIS="${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64 x86}"
RESUME_MODE="${RESUME_MODE:-1}"
NUM_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Thư mục làm việc
ANDROID_DIR="${PROJECT_ROOT}/android-build"
PJPROJECT_DIR="${ANDROID_DIR}/pjproject"
OPENSSL_SRC_DIR="${ANDROID_DIR}/openssl-${OPENSSL_VERSION}"
OBOE_DIR="${ANDROID_DIR}/oboe-${OBOE_VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/output}/android"
JNILIBS_DEST="${OUTPUT_DIR}/src/main/jniLibs"
HEADERS_DEST="${OUTPUT_DIR}/src/main/java"

# Tóm tắt cấu hình Android trước khi chạy
print_android_summary() {
    echo -e "\n${C_CYAN}${C_BOLD}--- CẤU HÌNH BUILD ANDROID ---${C_RESET}"
    echo -e "  PJSIP Version      : ${C_WHITE}${PJSIP_VERSION}${C_RESET}"
    echo -e "  OpenSSL Version    : ${C_WHITE}${OPENSSL_VERSION} (SSL: ${ENABLE_SSL})${C_RESET}"
    echo -e "  Oboe Support       : ${C_WHITE}${ENABLE_OBOE} (v${OBOE_VERSION})${C_RESET}"
    echo -e "  Video Support      : ${C_WHITE}${ENABLE_VIDEO}${C_RESET}"
    echo -e "  Android ABIs       : ${C_WHITE}${ANDROID_ABIS}${C_RESET}"
    echo -e "  Android API Level  : ${C_WHITE}${ANDROID_APP_PLATFORM}${C_RESET}"
    echo -e "  Android NDK        : ${C_WHITE}${ANDROID_NDK_ROOT}${C_RESET}"
    echo -e "  Java Home          : ${C_WHITE}${JAVA_HOME}${C_RESET}"
    echo -e "  Output Directory   : ${C_WHITE}${OUTPUT_DIR}${C_RESET}"
    echo -e "  Chế độ Resume      : ${C_WHITE}$([ "$RESUME_MODE" = "1" ] && echo "BẬT (Bỏ qua các bước đã hoàn tất)" || echo "TẮT")${C_RESET}"
    echo -e "--------------------------------------------------\n"
}

# 1. Hàm kiểm tra và tự động tải các dependencies (OpenSSL, Oboe) nếu thiếu
stage_prep_dependencies() {
    mkdir -p "${ANDROID_DIR}"

    # 1.1 Kiểm tra và tự động tải OpenSSL
    if [ "$ENABLE_SSL" = "yes" ]; then
        if [ ! -f "${OPENSSL_SRC_DIR}/Configure" ]; then
            log_warn "Không tìm thấy mã nguồn OpenSSL v${OPENSSL_VERSION} tại: ${OPENSSL_SRC_DIR}"
            log_info "Tiến hành tự động tải OpenSSL từ GitHub releases..."
            local openssl_tar="/tmp/openssl-${OPENSSL_VERSION}-$$.tar.gz"
            local openssl_url="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"

            log_info "Đang tải: ${openssl_url}..."
            if ! curl -fSL "${openssl_url}" -o "${openssl_tar}"; then
                local fallback_url="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
                log_warn "Tải từ GitHub thất bại, thử URL dự phòng: ${fallback_url}..."
                if ! curl -fSL "${fallback_url}" -o "${openssl_tar}"; then
                    log_error "Tải OpenSSL v${OPENSSL_VERSION} thất bại từ cả 2 nguồn!"
                    rm -f "${openssl_tar}"
                    return 1
                fi
            fi

            log_info "Giải nén OpenSSL vào ${ANDROID_DIR}..."
            tar -xzf "${openssl_tar}" -C "${ANDROID_DIR}" || {
                log_error "Giải nén OpenSSL thất bại!"
                rm -f "${openssl_tar}"
                return 1
            }
            rm -f "${openssl_tar}"

            if [ -f "${OPENSSL_SRC_DIR}/Configure" ]; then
                log_success "Đã tải và giải nén OpenSSL v${OPENSSL_VERSION} thành công!"
            else
                log_error "Không tìm thấy file Configure trong ${OPENSSL_SRC_DIR} sau khi giải nén!"
                return 1
            fi
        else
            log_info "OpenSSL v${OPENSSL_VERSION} đã sẵn sàng tại: ${OPENSSL_SRC_DIR}"
        fi
    fi

    # 1.2 Kiểm tra và tự động tải Oboe
    if [ "$ENABLE_OBOE" = "yes" ]; then
        if [ ! -d "${OBOE_DIR}/prefab" ]; then
            log_warn "Không tìm thấy thư viện Oboe v${OBOE_VERSION} tại: ${OBOE_DIR}"
            log_info "Tiến hành tự động tải Oboe AAR từ GitHub releases..."
            local oboe_aar="/tmp/oboe-${OBOE_VERSION}-$$.aar"
            local oboe_url="https://github.com/google/oboe/releases/download/${OBOE_VERSION}/oboe-${OBOE_VERSION}.aar"

            log_info "Đang tải: ${oboe_url}..."
            if ! curl -fSL "${oboe_url}" -o "${oboe_aar}"; then
                log_error "Không thể tải Oboe từ: ${oboe_url}"
                log_error "Vui lòng kiểm tra kết nối mạng hoặc xem danh sách phiên bản tại https://github.com/google/oboe/releases"
                rm -f "${oboe_aar}"
                return 1
            fi

            log_info "Giải nén Oboe AAR vào ${OBOE_DIR}..."
            mkdir -p "${OBOE_DIR}"
            unzip -q -o "${oboe_aar}" -d "${OBOE_DIR}" || {
                log_error "Giải nén Oboe AAR thất bại!"
                rm -f "${oboe_aar}"
                return 1
            }
            rm -f "${oboe_aar}"

            if [ -d "${OBOE_DIR}/prefab" ]; then
                log_success "Đã tải và giải nén Oboe v${OBOE_VERSION} thành công!"
            else
                log_error "Thư mục Oboe giải nén không đúng cấu trúc prefab chuẩn!"
                return 1
            fi
        else
            log_info "Oboe v${OBOE_VERSION} đã sẵn sàng tại: ${OBOE_DIR}"
        fi
    fi
    return 0
}

# 2. Hàm chuẩn bị Source PJSIP
stage_prep_pjsip() {
    mkdir -p "${ANDROID_DIR}"
    cd "${ANDROID_DIR}" || return 1

    if [ -d "pjproject" ]; then
        log_info "Cập nhật pjproject sang branch/tag: ${PJSIP_VERSION}..."
        pushd pjproject >/dev/null || return 1
        git fetch --tags 2>/dev/null || true
        git reset --hard "${PJSIP_VERSION}"
        popd >/dev/null || return 1
    else
        log_info "Clone pjproject (${PJSIP_VERSION})..."
        git -c advice.detachedHead=false clone --depth 1 --branch "${PJSIP_VERSION}" https://github.com/pjsip/pjproject
    fi

    # Tạo config_site.h
    log_info "Cấu hình pjlib/include/pj/config_site.h..."
    local video_val=0
    if [ "$ENABLE_VIDEO" = "yes" ]; then
        video_val=1
    fi

    cat << EOF > "${PJPROJECT_DIR}/pjlib/include/pj/config_site.h"
#define PJ_CONFIG_ANDROID 1
#define PJMEDIA_HAS_VIDEO ${video_val}
#include <pj/config_site_sample.h>
EOF
}

# 3. Hàm build OpenSSL cho từng ABI
stage_build_openssl_abi() {
    local target_abi="$1"
    local arch="$2"

    # Làm sạch cờ môi trường host để tránh lỗi link nhầm thư viện Mac
    sanitize_build_env

    if [ "$ENABLE_SSL" != "yes" ]; then
        log_info "Bỏ qua build OpenSSL vì SSL bị tắt."
        return 0
    fi

    if [ ! -d "${OPENSSL_SRC_DIR}" ]; then
        log_error "Không tìm thấy thư mục OpenSSL: ${OPENSSL_SRC_DIR}"
        return 1
    fi

    cd "${OPENSSL_SRC_DIR}" || return 1

    log_info "Cấu hình OpenSSL cho ${arch} (ABI: ${target_abi})..."
    make clean >/dev/null 2>&1 || true

    if [ "$arch" = "android-arm" ]; then
        # armeabi-v7a cần cờ no-asm
        ./Configure "$arch" -D__ANDROID_API__="${ANDROID_APP_PLATFORM}" no-asm
    else
        ./Configure "$arch" -D__ANDROID_API__="${ANDROID_APP_PLATFORM}"
    fi

    log_info "Biên dịch OpenSSL ${target_abi}..."
    make -j"${NUM_JOBS}"

    # Lưu lại artifact riêng cho ABI này
    local abi_lib_dir="${OPENSSL_SRC_DIR}/lib-${target_abi}"
    mkdir -p "${abi_lib_dir}"
    rm -rf "${abi_lib_dir:?}"/*
    cp -f lib*.so "${abi_lib_dir}/" 2>/dev/null || true
    cp -f lib*.a "${abi_lib_dir}/" 2>/dev/null || true

    # Chuẩn bị thư mục lib mặc định cho pjsip configure
    mkdir -p "${OPENSSL_SRC_DIR}/lib"
    cp -f "${abi_lib_dir}"/* "${OPENSSL_SRC_DIR}/lib/"
}

# 4. Hàm build PJSIP cho từng ABI
stage_build_pjsip_abi() {
    local target_abi="$1"
    export TARGET_ABI="$target_abi"

    # Làm sạch cờ môi trường host
    sanitize_build_env

    # Đảm bảo thư viện OpenSSL đúng của ABI này nằm trong lib/
    if [ "$ENABLE_SSL" = "yes" ] && [ -d "${OPENSSL_SRC_DIR}/lib-${target_abi}" ]; then
        mkdir -p "${OPENSSL_SRC_DIR}/lib"
        cp -f "${OPENSSL_SRC_DIR}/lib-${target_abi}"/* "${OPENSSL_SRC_DIR}/lib/"
    fi

    cd "${PJPROJECT_DIR}" || return 1

    log_info "Dọn dẹp bản build cũ..."
    make distclean >/dev/null 2>&1 || true

    local config_args=("--use-ndk-cflags")

    if [ "$ENABLE_SSL" = "yes" ]; then
        config_args+=("-with-ssl=${OPENSSL_SRC_DIR}")
    fi

    if [ "$ENABLE_OBOE" = "yes" ]; then
        if [ -d "${OBOE_DIR}" ]; then
            config_args+=("--with-oboe=${OBOE_DIR}")
        else
            log_warn "Không tìm thấy thư mục Oboe: ${OBOE_DIR}. Bỏ qua cờ --with-oboe."
        fi
    fi

    log_info "Configure PJSIP với các tham số: ${config_args[*]}..."
    ./configure-android "${config_args[@]}"

    log_info "Make dep & make PJSIP (${target_abi})..."
    make dep
    make clean
    make -j"${NUM_JOBS}"
}

# 4. Hàm build SWIG Java bindings
stage_build_swig_abi() {
    local target_abi="$1"
    export TARGET_ABI="$target_abi"

    local sample_dir="${PJPROJECT_DIR}/pjsip-apps/src/swig/java/android"
    mkdir -p "${sample_dir}/pjsua2/src/main/jniLibs/${target_abi}"
    rm -rf "${sample_dir}/pjsua2/src/main/jniLibs/${target_abi:?}"/*

    cd "${PJPROJECT_DIR}/pjsip-apps/src/swig/java" || return 1
    log_info "Biên dịch SWIG Java cho ${target_abi}..."
    make clean
    make
}

# 5. Hàm đóng gói JNI Libs cho từng ABI
stage_package_abi() {
    local target_abi="$1"
    local sample_dir="${PJPROJECT_DIR}/pjsip-apps/src/swig/java/android"
    local jni_out="${JNILIBS_DEST}/${target_abi}"
    mkdir -p "${jni_out}"

    # 1. Copy thư viện JNI của PJSIP
    log_info "Sao chép libpjsua2.so..."
    cp -v "${sample_dir}/pjsua2/src/main/jniLibs/${target_abi}"/*.so "${jni_out}/" 2>/dev/null || true

    # 2. Copy thư viện OpenSSL
    if [ "$ENABLE_SSL" = "yes" ] && [ -d "${OPENSSL_SRC_DIR}/lib-${target_abi}" ]; then
        log_info "Sao chép OpenSSL libraries..."
        cp -v "${OPENSSL_SRC_DIR}/lib-${target_abi}"/*.so "${jni_out}/" 2>/dev/null || true
    fi

    # 3. Copy thư viện Oboe
    if [ "$ENABLE_OBOE" = "yes" ] && [ -d "${OBOE_DIR}" ]; then
        local oboe_lib_path="${OBOE_DIR}/prefab/modules/oboe/libs/android.${target_abi}"
        if [ -d "${oboe_lib_path}" ]; then
            log_info "Sao chép Oboe libraries từ ${oboe_lib_path}..."
            cp -v "${oboe_lib_path}"/*.so "${jni_out}/" 2>/dev/null || true
        fi
    fi

    log_success "Đã đóng gói jniLibs cho ${target_abi} vào: ${jni_out}"
}

# 6. Hàm xuất Header / Java code
stage_export_headers() {
    local src_java="${PJPROJECT_DIR}/pjsip-apps/src/swig/java/android/pjsua2/src/main/java"
    mkdir -p "${HEADERS_DEST}"
    rm -rf "${HEADERS_DEST:?}"/*

    if [ -d "${src_java}" ]; then
        log_info "Sao chép mã nguồn Java bindings sang: ${HEADERS_DEST}..."
        cp -Rv "${src_java}"/* "${HEADERS_DEST}/"
        log_success "Mã nguồn Java bindings đã sẵn sàng!"
    else
        log_error "Không tìm thấy thư mục Java bindings: ${src_java}"
        return 1
    fi
}

# --- Entrypoint Build Android ---
build_android_main() {
    export APP_PLATFORM="${ANDROID_APP_PLATFORM}"
    export JAVA_HOME

    check_system_tools || exit 1

    # Tự động giải quyết NDK theo thứ tự:
    # 1. Thư mục xử lý/build (android-build)
    # 2. Máy host
    # 3. Tự động tải NDK r28b về thư mục build
    resolve_android_ndk "${ANDROID_DIR}" || exit 1
    check_android_env || exit 1

    print_android_summary

    # Bước 1: Chuẩn bị thư viện phụ thuộc (OpenSSL, Oboe) nếu chưa có
    run_stage "android" "prepare_dependencies" "Chuẩn bị dependencies (OpenSSL, Oboe)" stage_prep_dependencies || exit 1

    # Bước 2: Chuẩn bị mã nguồn PJSIP
    run_stage "android" "prepare_pjsip" "Chuẩn bị mã nguồn PJSIP v${PJSIP_VERSION}" stage_prep_pjsip || exit 1

    # Bước 3: Vòng lặp từng ABI
    for target_abi in ${ANDROID_ABIS}; do
        local arch=""
        case "$target_abi" in
            "arm64-v8a")   arch="android-arm64" ;;
            "armeabi-v7a") arch="android-arm" ;;
            "x86_64")      arch="android-x86_64" ;;
            "x86")         arch="android-x86" ;;
            *)
                log_error "ABI không được hỗ trợ: $target_abi"
                exit 1
                ;;
        esac

        log_header "BIÊN DỊCH ANDROID ABI: ${target_abi} (${arch})"

        # 2.1: OpenSSL
        if [ "$ENABLE_SSL" = "yes" ]; then
            run_stage "android" "openssl_${target_abi}" "Biên dịch OpenSSL [${target_abi}]" stage_build_openssl_abi "$target_abi" "$arch" || exit 1
        fi

        # 2.2: PJSIP
        run_stage "android" "pjsip_${target_abi}" "Biên dịch PJSIP core [${target_abi}]" stage_build_pjsip_abi "$target_abi" || exit 1

        # 2.3: SWIG Java bindings
        run_stage "android" "swig_${target_abi}" "Biên dịch SWIG Java bindings [${target_abi}]" stage_build_swig_abi "$target_abi" || exit 1

        # 2.4: Đóng gói jniLibs
        run_stage "android" "package_${target_abi}" "Đóng gói jniLibs [${target_abi}]" stage_package_abi "$target_abi" || exit 1
    done

    # Bước 3: Xuất Java headers
    run_stage "android" "export_java_headers" "Xuất mã nguồn Java sang output" stage_export_headers || exit 1

    log_header "HOÀN TẤT BIÊN DỊCH ANDROID"
    log_success "Kết quả đã được xuất ra thư mục: ${OUTPUT_DIR}"
    log_info "   ├─ jniLibs: ${JNILIBS_DEST}"
    log_info "   └─ java   : ${HEADERS_DEST}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_android_main "$@"
fi
