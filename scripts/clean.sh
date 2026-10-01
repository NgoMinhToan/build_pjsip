#!/bin/bash
# ==============================================================================
# File: scripts/clean.sh
# Script dọn dẹp cache, checkpoint, logs và artifacts
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

clean_target="${1:-all}"

clean_android() {
    log_info "Dọn dẹp Android build..."
    clear_platform_stages "android"

    # Dọn dẹp OpenSSL build
    find "${PROJECT_ROOT}/android-build" -maxdepth 2 -type d -name "lib-*" -exec rm -rf {} + 2>/dev/null || true
    for openssl_dir in "${PROJECT_ROOT}/android-build"/openssl-*; do
        if [ -d "$openssl_dir" ]; then
            pushd "$openssl_dir" >/dev/null
            make clean >/dev/null 2>&1 || true
            rm -rf lib/*
            popd >/dev/null
        fi
    done

    # Dọn dẹp PJSIP Android
    if [ -d "${PROJECT_ROOT}/android-build/pjproject" ]; then
        pushd "${PROJECT_ROOT}/android-build/pjproject" >/dev/null
        make distclean >/dev/null 2>&1 || true
        make clean >/dev/null 2>&1 || true
        popd >/dev/null
    fi

    rm -rf "${PROJECT_ROOT}/output/android"
    log_success "Đã dọn dẹp Android!"
}

clean_ios() {
    log_info "Dọn dẹp iOS build..."
    clear_platform_stages "ios"

    rm -rf "${PROJECT_ROOT}/ios-build/build_temp"
    if [ -d "${PROJECT_ROOT}/ios-build/pjproject" ]; then
        pushd "${PROJECT_ROOT}/ios-build/pjproject" >/dev/null
        make distclean >/dev/null 2>&1 || true
        make clean >/dev/null 2>&1 || true
        popd >/dev/null
    fi
    rm -rf "${PROJECT_ROOT}/ios-build"

    # Hỗ trợ dọn dẹp thư mục cũ nếu còn sót lại
    rm -rf "${PROJECT_ROOT}/pjproject-apple-platforms/build_temp"
    if [ -d "${PROJECT_ROOT}/pjproject-apple-platforms/pjproject" ]; then
        pushd "${PROJECT_ROOT}/pjproject-apple-platforms/pjproject" >/dev/null
        make distclean >/dev/null 2>&1 || true
        make clean >/dev/null 2>&1 || true
        popd >/dev/null
    fi

    rm -rf "${PROJECT_ROOT}/output/ios"
    log_success "Đã dọn dẹp iOS!"
}

clean_all() {
    log_info "Dọn dẹp toàn bộ hệ thống..."
    clear_all_stages
    clean_android
    clean_ios
    rm -rf "${PROJECT_ROOT}/logs"/*
    log_success "Đã dọn dẹp sạch sẽ toàn bộ project!"
}

case "$clean_target" in
    android) clean_android ;;
    ios)     clean_ios ;;
    all)     clean_all ;;
    state)   clear_all_stages ;;
    logs)    rm -rf "${PROJECT_ROOT}/logs"/*; log_success "Đã xóa toàn bộ logs!" ;;
    *)
        echo "Cách dùng: $0 [all|android|ios|state|logs]"
        exit 1
        ;;
esac
