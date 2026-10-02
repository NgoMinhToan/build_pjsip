# PJSIP Build Toolchain (iOS & Android)

Bộ công cụ tự động hóa biên dịch [PJSIP](https://www.pjsip.org/) hỗ trợ đầy đủ cho cả hai nền tảng **Android** và **iOS / Apple Platforms**.

---

## 🌟 Điểm nổi bật

1. **CLI Thống nhất (`./build.sh`)**:
   - Dùng 1 lệnh duy nhất để build cả hai nền tảng cùng lúc hoặc từng nền tảng riêng biệt.
   - Hỗ trợ chọn lọc từng kiến trúc Android (`--abi arm64-v8a`) hoặc từng target iOS (`--target device`).
2. **Tùy biến Linh hoạt**:
   - Điều chỉnh phiên bản PJSIP, OpenSSL, Oboe dễ dàng.
   - Bật/tắt Oboe (audio độ trễ thấp trên Android) qua `--with-oboe` / `--without-oboe`.
   - Bật/tắt Video (VideoToolbox / Media) qua `--with-video` / `--without-video`.
   - Bật/tắt SSL qua `--with-ssl` / `--without-ssl`.
3. **Phân đoạn Rõ ràng (Stage Tracking) & Live Log Terminal**:
   - Quy trình build được chia thành từng giai đoạn cụ thể.
   - Trong lúc build, terminal hiển thị động **10 dòng log mới nhất** theo thời gian thực và tự động dọn sạch khi giai đoạn hoàn tất để giữ màn hình terminal luôn gọn gàng.
   - Mỗi giai đoạn lưu log độc lập trong thư mục `logs/` để dễ dàng tra cứu lại.
4. **Báo lỗi Trực quan & Chi tiết**:
   - Khi có lỗi ở bất kỳ bước nào, script dừng ngay lập tức, hiển thị bảng thông báo màu đỏ, trích xuất 15 dòng log lỗi cuối cùng và chỉ rõ file log đầy đủ để kiểm tra.
5. **Cơ chế Checkpoint & Resume Thông minh**:
   - Build PJSIP rất tốn thời gian (30-60 phút). Hệ thống tự động ghi nhớ các giai đoạn đã hoàn thành vào thư mục `.build_state/`.
   - Khi bị gián đoạn hoặc gặp lỗi, sau khi sửa xong bạn chỉ cần chạy lại kèm `--resume`, hệ thống sẽ **bỏ qua toàn bộ các bước đã thành công trước đó** và tiếp tục ngay từ bước bị gián đoạn.
6. **Làm Sạch Môi Trường Cross-Compile (Environment Sanitization)**:
   - Tự động làm sạch các biến môi trường của macOS host (`PKG_CONFIG_PATH`, `PKG_CONFIG_LIBDIR=/dev/null`, `CFLAGS`, `CPPFLAGS`, `LDFLAGS`, `CXXFLAGS`) để triệt tiêu tình trạng dính thư viện Homebrew host khi biên dịch chéo cho Android hoặc iOS.

---

## 🚀 Hướng dẫn Sử dụng Nhanh

### 1. Build cả 2 nền tảng cùng lúc:
```bash
./build.sh all
```

### 2. Chỉ build Android:
```bash
# Build tất cả các kiến trúc mặc định (arm64-v8a, armeabi-v7a, x86_64, x86):
./build.sh android

# Chỉ build cho thiết bị thật 64-bit (tiết kiệm thời gian khi phát triển):
./build.sh android --abi arm64-v8a

# Build Android không dùng Oboe:
./build.sh android --without-oboe

# Build Android kèm hỗ trợ Video:
./build.sh android --with-video
```

### 3. Chỉ build iOS / Apple Platforms:
```bash
# Build đầy đủ cả 4 kiến trúc Apple vào 1 XCFramework (Device, Simulator, Catalyst, macOS):
./build.sh ios

# Chỉ build cho thiết bị thật:
./build.sh ios --target device

# Chỉ build cho máy ảo Simulator:
./build.sh ios --target simulator

# Chỉ định nhiều target tùy ý:
./build.sh ios --target device,simulator
# hoặc
./build.sh ios --target "device simulator catalyst macos"

# Build kèm hỗ trợ Video (VideoToolbox):
./build.sh ios --with-video
```

### 4. Cơ chế Checkpoint & Tiếp tục build (Resume):
- **Nếu chạy `--resume` khi chưa có checkpoint**: Hệ thống sẽ tự động chạy từ giai đoạn đầu tiên, đồng thời tự động lưu checkpoint sau mỗi giai đoạn thành công.
- **Nếu chạy lệnh thường khi đã có checkpoint**: Hệ thống mặc định **bảo lưu các checkpoint** và tiếp tục các giai đoạn chưa làm (tránh mất 30-60 phút build lại từ đầu).
- **Khi muốn xóa sạch và build lại từ đầu**: Thêm cờ `--rebuild` (hoặc `--no-resume`):
  ```bash
  ./build.sh android --rebuild
  # hoặc
  ./build.sh clean state && ./build.sh android
  ```

---

## 🛡️ Tự Động Giải Quyết & Tải Dependencies

1. **Cơ chế Tìm kiếm & Tự Động Tải Android NDK 28**:
   - Khi build Android, hệ thống tự động tìm kiếm NDK theo thứ tự ưu tiên 3 bước:
     1. **Tìm trong thư mục xử lý / build (`android-build/android-ndk-*`)**: Cùng cấp với OpenSSL và Oboe.
     2. **Tìm trên máy host**: Kiểm tra biến `ANDROID_NDK_ROOT` hoặc các đường dẫn SDK phổ biến (`$HOME/Library/Android/sdk/ndk/28.*`, `27.*`, v.v.).
     3. **Tự động tải về nếu thiếu**: Nếu máy chưa có NDK >= 27, script tự động tải bản **Android NDK r28b** chính thức từ Google, giải nén và lưu trữ cục bộ ngay tại `android-build/android-ndk-r28b` để tái sử dụng lâu dài mà không cần can thiệp thủ công.
2. **Tự động tải Oboe từ GitHub Releases**:
   - Nếu bật `--with-oboe` mà chưa có thư viện Oboe cục bộ trong `android-build/`, hệ thống sẽ tự động tải `oboe-${OBOE_VERSION}.aar` từ [Google Oboe Releases](https://github.com/google/oboe/releases) và giải nén đúng cấu trúc Prefab mà PJSIP yêu cầu.
3. **Tự động tải OpenSSL từ GitHub Releases**:
   - Nếu bật `--with-ssl` mà chưa có thư mục mã nguồn OpenSSL cục bộ trong `android-build/`, hệ thống sẽ tự động tải `openssl-${OPENSSL_VERSION}.tar.gz` từ [OpenSSL Releases](https://github.com/openssl/openssl/releases) và giải nén sẵn sàng để cấu hình.

---

## 📁 Cấu trúc Dự Án Clean

```
build_pjsip/
├── build.sh                   # [CLI chính] Entrypoint duy nhất điều khiển toàn bộ hệ thống
├── config.default.sh          # [Config] Thiết lập mặc định (PJSIP 2.17, OpenSSL 3.4.2, NDK r28b...)
├── scripts/                   # [Modules]
│   ├── common.sh              # Quản lý logging, ANSI live-tail, checkpoint/resume, NDK detection
│   ├── build_android.sh       # Engine build Android (OpenSSL, Oboe, PJSIP, SWIG Java)
│   ├── build_ios.sh           # Engine build iOS / Apple 4 slices (Device, Simulator, Catalyst, macOS)
│   └── clean.sh               # Tiện ích dọn dẹp build cache, checkpoint, logs
├── old_build/                 # [Lưu trữ] Thư mục chứa toàn bộ script và file của repo cũ
│   ├── android-build/         # Script và mã nguồn cũ của Android
│   └── pjproject-apple-platforms/ # Script và mã nguồn cũ của iOS
├── README.md                  # Tài liệu hướng dẫn sử dụng
└── .gitignore                 # Đã loại trừ tất cả các thư mục phát sinh lúc build (android-build, ios-build, output, logs, .build_state...)
```

---

## 📁 Cấu trúc Thư mục Sau khi Build

```
output/
├── android/
│   ├── src/main/jniLibs/
│   │   ├── arm64-v8a/      (libpjsua2.so, libcrypto.so, libssl.so, liboboe.so)
│   │   ├── armeabi-v7a/
│   │   ├── x86/
│   │   └── x86_64/
│   └── src/main/java/      (Các file Java bindings sinh từ SWIG)
└── ios/
    ├── libpjproject.xcframework (Đầy đủ 4 slices kiến trúc):
    │   ├── ios-arm64                       (iOS Device)
    │   ├── ios-arm64_x86_64-simulator      (iOS Simulator Universal)
    │   ├── ios-arm64_x86_64-maccatalyst    (Mac Catalyst Universal)
    │   └── macos-arm64_x86_64              (macOS Universal)
    ├── include/                 (Header files của PJSIP)
    └── pkgconfig/               (libpjproject.pc)
```

---

## 🛠️ File Cấu hình Riêng cho Máy Cá Nhân

Bạn có thể tạo một file `config.local.sh` ở thư mục gốc (đã được cấu hình trong `.gitignore`) để cố định đường dẫn NDK hoặc cấu hình mặc định trên máy của mình:

```bash
# config.local.sh
ANDROID_NDK_ROOT="/Users/your_name/Library/Android/sdk/ndk/28.2.13676358"
ENABLE_OBOE="yes"
ENABLE_VIDEO="no"
```
