#!/bin/bash
# ==============================================================================
# File: config.default.sh
# Cấu hình mặc định cho hệ thống build PJSIP (Android & iOS)
# Bạn có thể ghi đè các cấu hình này bằng cách tạo file config.local.sh
# hoặc truyền các cờ tương ứng khi chạy ./build.sh
# ==============================================================================

# --- Phiên bản thư viện ---
PJSIP_VERSION="${PJSIP_VERSION:-2.16}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.4.2}"
OBOE_VERSION="${OBOE_VERSION:-1.10.0}"

# --- Tính năng chung ---
ENABLE_SSL="${ENABLE_SSL:-yes}"        # yes / no
ENABLE_VIDEO="${ENABLE_VIDEO:-yes}"     # yes / no (Bật mặc định để hỗ trợ Video Call / pjsua_vid)

# --- Cấu hình Android ---
ENABLE_OBOE="${ENABLE_OBOE:-yes}"      # yes / no (Hỗ trợ audio low-latency Oboe trên Android)
ANDROID_APP_PLATFORM="${ANDROID_APP_PLATFORM:-24}"
NDK_VERSION="${NDK_VERSION:-r28b}"     # Phiên bản NDK 28 mặc định tự động tải nếu thiếu
# Danh sách ABIs mặc định (có thể chọn: arm64-v8a armeabi-v7a x86_64 x86)
ANDROID_ABIS="${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64 x86}"

# ANDROID_NDK_ROOT: Sẽ được tự động giải quyết theo thứ tự ưu tiên:
# 1. Thư mục build (cùng cấp với openssl, oboe: android-build/android-ndk-*)
# 2. NDK có sẵn trên máy host
# 3. Tự động tải NDK r28b từ Google về thư mục build nếu không tìm thấy
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-}"

# Auto-detect JAVA_HOME nếu chưa được set (ưu tiên Java 17)
if [ -z "${JAVA_HOME}" ]; then
    if [ -d "/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home" ]; then
        JAVA_HOME="/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home"
    elif [ -x "/usr/libexec/java_home" ]; then
        JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home 2>/dev/null || echo "")
    fi
fi

# --- Cấu hình iOS / Apple Platforms ---
IOS_MIN_VERSION="${IOS_MIN_VERSION:-13.0}"
# Các targets mặc định cho Apple: device, simulator, catalyst, macos (đầy đủ cả 4 kiến trúc)
IOS_TARGETS="${IOS_TARGETS:-device simulator catalyst macos}"

# Thư mục Output
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"

# Load config.local.sh nếu tồn tại (để người dùng ghi đè máy local)
if [ -f "$(dirname "${BASH_SOURCE[0]}")/config.local.sh" ]; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/config.local.sh"
fi
