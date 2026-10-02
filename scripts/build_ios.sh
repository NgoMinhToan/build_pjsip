#!/bin/bash
# ==============================================================================
# File: scripts/build_ios.sh
# Script biên dịch PJSIP cho iOS / Apple Platforms (Device, Simulator, XCFramework)
# Hỗ trợ checkpoint, resume từng giai đoạn cho từng target
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
PJSIP_VERSION="${PJSIP_VERSION:-2.16}"
ENABLE_SSL="${ENABLE_SSL:-yes}"
ENABLE_VIDEO="${ENABLE_VIDEO:-yes}"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-13.0}"
IOS_TARGETS="${IOS_TARGETS:-device simulator catalyst macos}"
RESUME_MODE="${RESUME_MODE:-1}"
NUM_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Thư mục làm việc
APPLE_DIR="${PROJECT_ROOT}/ios-build"
PJPROJECT_DIR="${APPLE_DIR}/pjproject"
BUILD_TEMP_DIR="${APPLE_DIR}/build_temp"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/output}/ios"
XCFRAMEWORK_OUT="${OUTPUT_DIR}/libpjproject.xcframework"

# Các prefix cài đặt tạm thời
PREFIX_DEVICE="${BUILD_TEMP_DIR}/ios-arm64"
PREFIX_SIM_ARM64="${BUILD_TEMP_DIR}/ios-arm64-simulator"
PREFIX_SIM_X86_64="${BUILD_TEMP_DIR}/ios-x86_64-simulator"
PREFIX_SIM_FAT="${BUILD_TEMP_DIR}/ios-simulator-universal"
PREFIX_CATALYST_ARM64="${BUILD_TEMP_DIR}/ios-arm64-maccatalyst"
PREFIX_CATALYST_X86_64="${BUILD_TEMP_DIR}/ios-x86_64-maccatalyst"
PREFIX_CATALYST_FAT="${BUILD_TEMP_DIR}/ios-catalyst-universal"
PREFIX_MACOS_ARM64="${BUILD_TEMP_DIR}/macos-arm64"
PREFIX_MACOS_X86_64="${BUILD_TEMP_DIR}/macos-x86_64"
PREFIX_MACOS_FAT="${BUILD_TEMP_DIR}/macos-universal"

print_ios_summary() {
    echo -e "\n${C_CYAN}${C_BOLD}--- CẤU HÌNH BUILD IOS / APPLE PLATFORMS ---${C_RESET}"
    echo -e "  PJSIP Version      : ${C_WHITE}${PJSIP_VERSION}${C_RESET}"
    echo -e "  SSL Support        : ${C_WHITE}${ENABLE_SSL} (Apple Network/Security)${C_RESET}"
    echo -e "  Video Support      : ${C_WHITE}${ENABLE_VIDEO}${C_RESET}"
    echo -e "  iOS Min Version    : ${C_WHITE}${IOS_MIN_VERSION}${C_RESET}"
    echo -e "  Apple Targets      : ${C_WHITE}${IOS_TARGETS}${C_RESET}"
    echo -e "  Xcode SDK          : ${C_WHITE}$(xcrun --sdk iphoneos --show-sdk-path)${C_RESET}"
    echo -e "  Output Directory   : ${C_WHITE}${OUTPUT_DIR}${C_RESET}"
    echo -e "  Chế độ Resume      : ${C_WHITE}$([ "$RESUME_MODE" = "1" ] && echo "BẬT (Bỏ qua các bước đã hoàn tất)" || echo "TẮT")${C_RESET}"
    echo -e "--------------------------------------------------------\n"
}

# Helper tạo thư viện tĩnh gộp libpjproject.a
create_fat_pjproject_lib() {
    local target_lib_dir="$1"
    pushd "${target_lib_dir}" >/dev/null || return 1
    log_info "Gộp các thư viện .a thành libpjproject.a tại: ${target_lib_dir}..."
    rm -f libpjproject.a
    local libs=(./*.a)
    libtool -static -o libpjproject.a "${libs[@]}"
    ranlib libpjproject.a
    popd >/dev/null || return 1
}

# 1. Chuẩn bị source code
stage_prep_ios_source() {
    mkdir -p "${APPLE_DIR}" "${BUILD_TEMP_DIR}" "${OUTPUT_DIR}"
    cd "${APPLE_DIR}" || return 1

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
}

# Cấu hình config_site.h cho từng loại target
prepare_config_site() {
    local is_iphone="$1"
    local has_video="$2"

    cd "${PJPROJECT_DIR}" || return 1
    git reset --hard HEAD >/dev/null 2>&1
    git clean -fxd >/dev/null 2>&1

    {
        if [ "$is_iphone" = "YES" ]; then
            echo "#define PJ_CONFIG_IPHONE 1"
        fi
        if [ "$has_video" = "YES" ]; then
            echo "#define PJMEDIA_HAS_VIDEO 1"
            echo "#define PJMEDIA_HAS_VID_TOOLBOX_CODEC 1"
        fi
        echo "#define PJ_HAS_SSL_SOCK 1"
        echo "#undef PJ_SSL_SOCK_IMP"
        echo "#define PJ_SSL_SOCK_IMP PJ_SSL_SOCK_IMP_APPLE"
        echo "#include <pj/config_site_sample.h>"
    } > pjlib/include/pj/config_site.h
}

# 2. Build iOS Device (arm64)
stage_build_ios_device() {
    rm -rf "${PREFIX_DEVICE}"
    prepare_config_site "YES" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1

    local sdkpath
    sdkpath=$(xcrun -sdk iphoneos --show-sdk-path)
    local arch="arm64"

    log_info "Configure cho iOS Device (arm64)..."
    CFLAGS="-isysroot $sdkpath -miphoneos-version-min=${IOS_MIN_VERSION} -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch" \
    LDFLAGS="-isysroot $sdkpath -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $arch" \
    ./aconfigure --prefix="${PREFIX_DEVICE}" --host="${arch}-apple-darwin_ios" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_DEVICE}/lib"
}

# 3. Build iOS Simulator arm64
stage_build_ios_sim_arm64() {
    rm -rf "${PREFIX_SIM_ARM64}"
    prepare_config_site "YES" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1

    local sdkpath
    sdkpath=$(xcrun -sdk iphonesimulator --show-sdk-path)
    local arch="arm64"

    log_info "Configure cho iOS Simulator (arm64)..."
    CFLAGS="-isysroot $sdkpath -miphonesimulator-version-min=${IOS_MIN_VERSION} -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch" \
    LDFLAGS="-isysroot $sdkpath -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $arch" \
    ./aconfigure --prefix="${PREFIX_SIM_ARM64}" --host="${arch}-apple-darwin_ios" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_SIM_ARM64}/lib"
}

# 4. Build iOS Simulator x86_64
stage_build_ios_sim_x86_64() {
    rm -rf "${PREFIX_SIM_X86_64}"
    prepare_config_site "YES" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1

    local sdkpath
    sdkpath=$(xcrun -sdk iphonesimulator --show-sdk-path)
    local arch="x86_64"

    log_info "Configure cho iOS Simulator (x86_64)..."
    CFLAGS="-isysroot $sdkpath -miphonesimulator-version-min=${IOS_MIN_VERSION} -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch" \
    LDFLAGS="-isysroot $sdkpath -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $arch" \
    ./aconfigure --prefix="${PREFIX_SIM_X86_64}" --host="${arch}-apple-darwin_ios" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_SIM_X86_64}/lib"
}

# 5. Gộp Lipo iOS Simulator (arm64 + x86_64)
stage_lipo_simulator() {
    mkdir -p "${PREFIX_SIM_FAT}/lib"
    cp -R "${PREFIX_SIM_ARM64}/include" "${PREFIX_SIM_FAT}/"

    log_info "Tạo universal binary cho iOS Simulator (arm64 + x86_64)..."
    lipo -create \
        "${PREFIX_SIM_ARM64}/lib/libpjproject.a" \
        "${PREFIX_SIM_X86_64}/lib/libpjproject.a" \
        -output "${PREFIX_SIM_FAT}/lib/libpjproject.a"
}

# 6. Build Catalyst arm64
stage_build_catalyst_arm64() {
    rm -rf "${PREFIX_CATALYST_ARM64}"
    prepare_config_site "YES" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1
    local sdkpath
    sdkpath=$(xcrun -sdk macosx --show-sdk-path)
    local arch="arm64"

    log_info "Configure cho Mac Catalyst (${arch})..."
    CFLAGS="-isysroot $sdkpath -isystem ${sdkpath}/System/iOSSupport/usr/include -iframework ${sdkpath}/System/iOSSupport/System/Library/Frameworks -miphoneos-version-min=13.1 -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch -target ${arch}-apple-ios-macabi" \
    LDFLAGS="-isysroot $sdkpath -isystem ${sdkpath}/System/iOSSupport/usr/include -iframework ${sdkpath}/System/iOSSupport/System/Library/Frameworks -framework Network -framework Security -framework Foundation -arch $arch -target ${arch}-apple-ios-macabi" \
    ./aconfigure --prefix="${PREFIX_CATALYST_ARM64}" --host="${arch}-apple-darwin_ios" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_CATALYST_ARM64}/lib"
}

# 7. Build Catalyst x86_64
stage_build_catalyst_x86_64() {
    rm -rf "${PREFIX_CATALYST_X86_64}"
    prepare_config_site "YES" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1
    local sdkpath
    sdkpath=$(xcrun -sdk macosx --show-sdk-path)
    local arch="x86_64"

    log_info "Configure cho Mac Catalyst (${arch})..."
    CFLAGS="-isysroot $sdkpath -isystem ${sdkpath}/System/iOSSupport/usr/include -iframework ${sdkpath}/System/iOSSupport/System/Library/Frameworks -miphoneos-version-min=13.1 -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch -target ${arch}-apple-ios-macabi" \
    LDFLAGS="-isysroot $sdkpath -isystem ${sdkpath}/System/iOSSupport/usr/include -iframework ${sdkpath}/System/iOSSupport/System/Library/Frameworks -framework Network -framework Security -framework Foundation -arch $arch -target ${arch}-apple-ios-macabi" \
    ./aconfigure --prefix="${PREFIX_CATALYST_X86_64}" --host="${arch}-apple-darwin_ios" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_CATALYST_X86_64}/lib"
}

# 8. Gộp Lipo Catalyst (arm64 + x86_64) -> ios-arm64_x86_64-maccatalyst
stage_lipo_catalyst() {
    mkdir -p "${PREFIX_CATALYST_FAT}/lib"
    cp -R "${PREFIX_CATALYST_ARM64}/include" "${PREFIX_CATALYST_FAT}/"

    log_info "Tạo universal binary cho Mac Catalyst (arm64 + x86_64)..."
    lipo -create \
        "${PREFIX_CATALYST_ARM64}/lib/libpjproject.a" \
        "${PREFIX_CATALYST_X86_64}/lib/libpjproject.a" \
        -output "${PREFIX_CATALYST_FAT}/lib/libpjproject.a"
}

# 9. Build macOS arm64
stage_build_macos_arm64() {
    rm -rf "${PREFIX_MACOS_ARM64}"
    prepare_config_site "NO" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1
    local sdkpath
    sdkpath=$(xcrun -sdk macosx --show-sdk-path)
    local arch="arm64"

    log_info "Configure cho macOS (${arch})..."
    CFLAGS="-isysroot $sdkpath -mmacosx-version-min=11 -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch" \
    LDFLAGS="-isysroot $sdkpath -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $arch" \
    ./aconfigure --prefix="${PREFIX_MACOS_ARM64}" --host="arm-apple-darwin" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_MACOS_ARM64}/lib"
}

# 10. Build macOS x86_64
stage_build_macos_x86_64() {
    rm -rf "${PREFIX_MACOS_X86_64}"
    prepare_config_site "NO" "$([ "$ENABLE_VIDEO" = "yes" ] && echo "YES" || echo "NO")"

    cd "${PJPROJECT_DIR}" || return 1
    local sdkpath
    sdkpath=$(xcrun -sdk macosx --show-sdk-path)
    local arch="x86_64"

    log_info "Configure cho macOS (${arch})..."
    CFLAGS="-isysroot $sdkpath -mmacosx-version-min=11 -DPJ_SDK_NAME=\"\\\"$(basename "$sdkpath")\\\"\" -arch $arch" \
    LDFLAGS="-isysroot $sdkpath -framework AudioToolbox -framework Foundation -framework Network -framework Security -arch $arch" \
    ./aconfigure --prefix="${PREFIX_MACOS_X86_64}" --host="x86_64-apple-darwin" --disable-sdl

    log_info "Biên dịch và cài đặt..."
    make dep && make clean
    make -j"${NUM_JOBS}"
    make install

    create_fat_pjproject_lib "${PREFIX_MACOS_X86_64}/lib"
}

# 11. Gộp Lipo macOS (arm64 + x86_64) -> macos-arm64_x86_64
stage_lipo_macos() {
    mkdir -p "${PREFIX_MACOS_FAT}/lib"
    cp -R "${PREFIX_MACOS_ARM64}/include" "${PREFIX_MACOS_FAT}/"

    log_info "Tạo universal binary cho macOS (arm64 + x86_64)..."
    lipo -create \
        "${PREFIX_MACOS_ARM64}/lib/libpjproject.a" \
        "${PREFIX_MACOS_X86_64}/lib/libpjproject.a" \
        -output "${PREFIX_MACOS_FAT}/lib/libpjproject.a"
}

# 12. Tạo XCFramework hoàn chỉnh chứa đầy đủ các kiến trúc
stage_create_xcframework() {
    mkdir -p "${OUTPUT_DIR}"
    rm -rf "${XCFRAMEWORK_OUT}"

    local xc_args=("-create-xcframework")
    local slice_count=0

    # 1. iOS Device (ios-arm64)
    if [ -f "${PREFIX_DEVICE}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_DEVICE}/lib/libpjproject.a" "-headers" "${PREFIX_DEVICE}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 1: iOS Device (ios-arm64)"
    fi

    # 2. iOS Simulator (ios-arm64_x86_64-simulator)
    if [ -f "${PREFIX_SIM_FAT}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_SIM_FAT}/lib/libpjproject.a" "-headers" "${PREFIX_SIM_FAT}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 2: iOS Simulator Universal (ios-arm64_x86_64-simulator)"
    elif [ -f "${PREFIX_SIM_ARM64}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_SIM_ARM64}/lib/libpjproject.a" "-headers" "${PREFIX_SIM_ARM64}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 2: iOS Simulator (ios-arm64)"
    fi

    # 3. Mac Catalyst (ios-arm64_x86_64-maccatalyst)
    if [ -f "${PREFIX_CATALYST_FAT}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_CATALYST_FAT}/lib/libpjproject.a" "-headers" "${PREFIX_CATALYST_FAT}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 3: Mac Catalyst Universal (ios-arm64_x86_64-maccatalyst)"
    elif [ -f "${PREFIX_CATALYST_ARM64}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_CATALYST_ARM64}/lib/libpjproject.a" "-headers" "${PREFIX_CATALYST_ARM64}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 3: Mac Catalyst (arm64)"
    fi

    # 4. macOS (macos-arm64_x86_64)
    if [ -f "${PREFIX_MACOS_FAT}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_MACOS_FAT}/lib/libpjproject.a" "-headers" "${PREFIX_MACOS_FAT}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 4: macOS Universal (macos-arm64_x86_64)"
    elif [ -f "${PREFIX_MACOS_ARM64}/lib/libpjproject.a" ]; then
        xc_args+=("-library" "${PREFIX_MACOS_ARM64}/lib/libpjproject.a" "-headers" "${PREFIX_MACOS_ARM64}/include")
        slice_count=$((slice_count + 1))
        log_info "  + Slice 4: macOS (arm64)"
    fi

    if [ $slice_count -eq 0 ]; then
        log_error "Không tìm thấy thư viện nào đã build để đóng gói XCFramework!"
        return 1
    fi

    xc_args+=("-output" "${XCFRAMEWORK_OUT}")

    log_info "Chạy xcodebuild để đóng gói XCFramework (${slice_count} nền tảng)..."
    xcodebuild "${xc_args[@]}"

    # Xuất file pkg-config
    local pc_dir="${OUTPUT_DIR}/pkgconfig"
    mkdir -p "${pc_dir}"
    local pc_file="${pc_dir}/libpjproject.pc"
    cat << EOF > "${pc_file}"
Name: libpjproject
Description: Multimedia communication library (Apple / iOS)
URL: http://www.pjsip.org
Version: ${PJSIP_VERSION}
Libs: -lpjproject -framework Security -framework Network -framework AudioToolbox -framework Foundation -framework VideoToolbox -framework CoreVideo -framework CoreMedia -framework AVFoundation
Cflags: -DPJ_AUTOCONF=1
EOF

    # Copy headers tổng sang output
    if [ -d "${PREFIX_DEVICE}/include" ]; then
        cp -R "${PREFIX_DEVICE}/include" "${OUTPUT_DIR}/include"
    elif [ -d "${PREFIX_MACOS_ARM64}/include" ]; then
        cp -R "${PREFIX_MACOS_ARM64}/include" "${OUTPUT_DIR}/include"
    fi

    log_success "XCFramework đã được tạo tại: ${XCFRAMEWORK_OUT}"
}

# --- Entrypoint Build iOS ---
build_ios_main() {
    # Làm sạch cờ môi trường host
    sanitize_build_env

    check_system_tools || exit 1
    check_ios_env || exit 1

    print_ios_summary

    # Bước 1: Chuẩn bị mã nguồn
    run_stage "ios" "prepare_source" "Chuẩn bị mã nguồn PJSIP v${PJSIP_VERSION}" stage_prep_ios_source || exit 1

    # 1. iOS Device (ios-arm64)
    if [[ " $IOS_TARGETS " =~ " device " ]] || [[ " $IOS_TARGETS " =~ " all " ]]; then
        run_stage "ios" "build_device" "Biên dịch iOS Device (arm64)" stage_build_ios_device || exit 1
    fi

    # 2. iOS Simulator Universal (ios-arm64_x86_64-simulator)
    if [[ " $IOS_TARGETS " =~ " simulator " ]] || [[ " $IOS_TARGETS " =~ " all " ]]; then
        run_stage "ios" "build_sim_arm64" "Biên dịch iOS Simulator (arm64)" stage_build_ios_sim_arm64 || exit 1
        run_stage "ios" "build_sim_x86_64" "Biên dịch iOS Simulator (x86_64)" stage_build_ios_sim_x86_64 || exit 1
        run_stage "ios" "lipo_simulator" "Gộp Universal Simulator (arm64 + x86_64)" stage_lipo_simulator || exit 1
    fi

    # 3. Mac Catalyst Universal (ios-arm64_x86_64-maccatalyst)
    if [[ " $IOS_TARGETS " =~ " catalyst " ]] || [[ " $IOS_TARGETS " =~ " all " ]]; then
        run_stage "ios" "build_catalyst_arm64" "Biên dịch Mac Catalyst (arm64)" stage_build_catalyst_arm64 || exit 1
        run_stage "ios" "build_catalyst_x86_64" "Biên dịch Mac Catalyst (x86_64)" stage_build_catalyst_x86_64 || exit 1
        run_stage "ios" "lipo_catalyst" "Gộp Universal Catalyst (arm64 + x86_64)" stage_lipo_catalyst || exit 1
    fi

    # 4. macOS Universal (macos-arm64_x86_64)
    if [[ " $IOS_TARGETS " =~ " macos " ]] || [[ " $IOS_TARGETS " =~ " all " ]]; then
        run_stage "ios" "build_macos_arm64" "Biên dịch macOS (arm64)" stage_build_macos_arm64 || exit 1
        run_stage "ios" "build_macos_x86_64" "Biên dịch macOS (x86_64)" stage_build_macos_x86_64 || exit 1
        run_stage "ios" "lipo_macos" "Gộp Universal macOS (arm64 + x86_64)" stage_lipo_macos || exit 1
    fi

    # Bước cuối: Tạo XCFramework
    run_stage "ios" "create_xcframework" "Đóng gói Apple XCFramework hoàn chỉnh" stage_create_xcframework || exit 1

    log_header "HOÀN TẤT BIÊN DỊCH IOS"
    log_success "Kết quả đã được xuất ra thư mục: ${OUTPUT_DIR}"
    log_info "   ├─ XCFramework: ${XCFRAMEWORK_OUT}"
    log_info "   └─ Headers    : ${OUTPUT_DIR}/include"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_ios_main "$@"
fi
