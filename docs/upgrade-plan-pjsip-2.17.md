# Kế hoạch Kỹ thuật: Nâng cấp PJSIP lên Phiên bản 2.17

Tài liệu này trình bày chi tiết nghiên cứu kỹ thuật, đánh giá mức độ tương thích, các bản vá bảo mật và lộ trình nâng cấp hệ thống build PJSIP từ phiên bản **`2.16`** lên phiên bản **`2.17`**.

---

## 1. Tổng quan Phiên bản PJSIP 2.17

* **Kho lưu trữ chính thức:** [pjsip/pjproject](https://github.com/pjsip/pjproject)
* **Phiên bản mới nhất:** `2.17` (Phát hành chính thức: ngày 22/04/2026)
* **Phiên bản trước đó:** `2.16` (Phát hành: ngày 26/11/2025)
* **Mục tiêu phiên bản:** 
  - Khắc phục toàn bộ 14 lỗ hổng bảo mật nghiêm trọng được phát hiện trong các bộ giải mã media và giao thức SIP/RTP.
  - Tối ưu hóa build SWIG Java cho nền tảng Android.
  - Cải tiến tính năng hội thoại đa phương tiện AI (AI Real-time Speech Connectivity) và xác thực SIP bất đồng bộ.

---

## 2. Chi tiết 14 Lỗ hổng Bảo mật được Khắc phục trong PJSIP 2.17

Phiên bản 2.17 giải quyết triệt để 14 lỗ hổng bảo mật có nguy cơ gây tràn bộ đệm (Buffer Overflow), tấn công từ chối dịch vụ (DoS) và thực thi mã tùy ý (RCE):

| Mã định danh (Advisory) | Thành phần ảnh hưởng | Mức độ & Tóm tắt sự cố |
| :--- | :--- | :--- |
| **GHSA-j29p-pvh2-pvqp** | ICE / STUN / TURN | Tràn bộ đệm (Buffer overflow) khi phân tích username có độ dài bất thường |
| **GHSA-p965-mf7j-gwv8** | H.264 Video Codec | Lỗi Use-after-free trong H.264 packetizer khi đóng gói NAL phân mảnh |
| **GHSA-x2hc-6969-g8v6** | H.264 Video Codec | Tràn bộ nhớ heap (Heap buffer overflow) trong H.264 unpacketizer |
| **GHSA-pqww-jrxr-457f** | pjmedia-codec framework | Tràn ngăn xếp (Stack buffer overflow) khi phân tích RTP payload |
| **GHSA-8fj4-fv9f-hjpc** | PJSIP Presence | Lỗi Heap use-after-free khi kết thúc presence subscription |
| **GHSA-g88q-c2hm-q7p7** | ICE Session | Tranh chấp luồng (Race conditions) gây lỗi Use-after-free trong phiên ICE |
| **GHSA-jr2p-p2w4-rr9q** | DNS Parser | Tràn bộ nhớ heap (Heap buffer overflow) khi phân tích gói tin DNS |
| **GHSA-x5pq-qrp4-fmrj** | SIP Parser | Đọc ngoài giới hạn bộ nhớ (Out-of-bounds read) khi xử lý SIP multipart |
| **GHSA-pqrm-53pc-wx28** | VPX Video Codec | Đọc ngoài giới hạn bộ nhớ heap (Heap OOB read) trong VPX unpacketizer |
| **GHSA-j59p-4xrr-fp8g** | Opus Audio Codec | Tràn bộ nhớ heap (Heap buffer overflow) khi giải mã gói tin âm thanh Opus |
| **GHSA-2wcg-w3c4-48r7** | pjsip_auth | Tràn ngăn xếp trong hàm `pjsip_auth_create_digest2()` |
| **GHSA-f33g-8hjq-62xr** | Media Stream | Tràn số nguyên (Integer overflow) trong luồng media asymmetric ptime |
| **GHSA-935m-fmf5-j4pm** | SIP Parser | Lỗi Underflow khi xử lý độ dài SIP Multipart CID URI |
| **GHSA-x2fv-6j6c-pxmx** | TLS Backend (GnuTLS) | Bỏ qua bước xác minh chuỗi chứng chỉ khi `verify_peer` là false |

---

## 3. Cải tiến Nền tảng (Platform Enhancements)

### 3.1. Cải tiến Android & SWIG Java (Commit `2965cffa2`)
* **Loại bỏ phụ thuộc `javac` trên máy Host:** 
  Trước phiên bản 2.17, Makefile của SWIG Java phụ thuộc vào việc tìm `javac` hệ thống để copy các file Java helper. Ở 2.17, quy trình sao chép các helper (`PjCamera*.java`, `PjAudioDevInfo.java`) được tách thành target độc lập `android_helpers`, giúp việc biên dịch bằng NDK sạch sẽ và không gặp lỗi thiếu JDK.
* **Xử lý hiển thị Video Preview (Z-Order):**
  Thêm cờ `setZOrderMediaOverlay(true)` cho SurfaceView của video preview, ngăn chặn hiện tượng video preview cục bộ bị che khuất hoặc nằm dưới video đầu xa.
* **Xử lý Xoay Màn hình (Orientation & Lifecycle):**
  Cải tiến hàm xử lý thay đổi góc nhìn thiết bị (`onConfigurationChanged`), lắng nghe sự kiện `OnGlobalLayoutListener` để cập nhật kích thước video stream chính xác, tránh lỗi crash do layout chưa render xong.

### 3.2. Cải tiến Apple Platforms (iOS, Simulator, macOS, Catalyst)
* Giữ nguyên hỗ trợ phần cứng **Apple VideoToolbox** (`vid_toolbox.m`) tối ưu cho H.264 và HEVC.
* Sửa lỗi race condition và crash `asan_poisoning` trên các luồng worker ARM64 của macOS (#4846).
* Tương thích tốt với các phiên bản Xcode và Clang SDKs mới nhất.

### 3.3. Các Tính năng Mới Khác
* **Xác thực SIP Client bất đồng bộ (#4816):** Hỗ trợ asynchronous digest authentication, ngăn ngừa hiện tượng nghẽn luồng xử lý chính khi thực hiện các cuộc gọi xác thực với tổng đài SIP.
* **AI Voice / Speech Connectivity (#4866, #4870):** Bổ sung module kết nối media thời gian thực phục vụ các dịch vụ trợ lý ảo AI và voice agent.

---

## 4. Đánh giá Tính Tương thích Ngược (Backward Compatibility)

Qua đối chiếu mã nguồn giữa thẻ `2.16` và `2.17` trên kho chính thức:

1. **Khả năng tương thích C API & Video Symbols:**
   * Các hàm điều khiển video cốt lõi bao gồm:
     - `pjsua_vid_dev_count()`
     - `pjsua_vid_dev_set_setting()`
     - `pjsua_vid_win_set_size()`
     - Các hàm `pjsua_call_*` và `pjsua_acc_*`
   * **Kết luận:** Giữ nguyên chữ ký hàm (signatures) và hành vi tương thích 100%. Không có bất kỳ thay đổi nào làm phá vỡ các ứng dụng di động khách (consumer apps) đang tích hợp thư viện này.

2. **Khả năng tương thích Toolchain:**
   * **Android NDK:** PJSIP 2.17 yêu cầu NDK >= r27. Hệ thống build hiện tại của chúng ta đã sử dụng **NDK r28b**, hoàn toàn đáp ứng tối ưu.
   * **OpenSSL:** Tương thích đầy đủ với OpenSSL 3.4.2 đang cấu hình.
   * **Oboe:** Tương thích đầy đủ với thư viện audio low-latency Oboe 1.10.0.

---

## 5. Lộ trình Triển khai Nâng cấp (5 Bước)

```
[Bước 1: Cập nhật Config] ──▶ [Bước 2: Test Build Cục bộ] ──▶ [Bước 3: Xác minh Symbols] ──▶ [Bước 4: CI/CD Build All] ──▶ [Bước 5: Phát hành Release]
```

### Bước 1: Cập nhật cấu hình phiên bản
Cập nhật biến phiên bản mặc định trong `config.default.sh`:
```bash
PJSIP_VERSION="${PJSIP_VERSION:-2.17}"
```
Đồng bộ giá trị fallback trong `scripts/build_android.sh` và `scripts/build_ios.sh`.

### Bước 2: Thử nghiệm biên dịch cục bộ (Kiểm tra nhanh)
Kiểm tra khả năng biên dịch Android cho kiến trúc chính:
```bash
./build.sh android --abi arm64-v8a --pjsip-version 2.17
```
Kiểm tra khả năng biên dịch iOS cho thiết bị thật:
```bash
./build.sh ios --target device --pjsip-version 2.17
```

### Bước 3: Xác minh các Symbol quan trọng
Kiểm tra file nhị phân sau khi build để đảm bảo các symbol video và core được xuất đầy đủ:
```bash
nm -gU output/ios/libpjproject.xcframework/ios-arm64/libpjproject.a | grep -E "_pjsua_vid_dev_count|_pjsua_vid_dev_set_setting|_pjsua_vid_win_set_size"
```

### Bước 4: Đẩy mã nguồn kích hoạt GitHub Actions
Đẩy các thay đổi cấu hình lên nhánh `main`:
```bash
git add config.default.sh scripts/build_android.sh scripts/build_ios.sh docs/upgrade-plan-pjsip-2.17.md
git commit -m "upgrade default PJSIP version to 2.17"
git push origin main
```

### Bước 5: Phát hành Phiên bản Release Mới
Workflow GitHub Actions sẽ tự động:
1. Biên dịch toàn bộ 4 ABIs Android (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`).
2. Biên dịch toàn bộ 4 lát cắt Apple (iOS Device, iOS Simulator Universal, Mac Catalyst, macOS Universal).
3. Tự động đóng gói và xuất bản bản phát hành `v2.17.x` công khai trên GitHub Releases kèm mã băm SHA-256 xác thực.

---

## 6. Kế hoạch Dự phòng (Rollback Plan)

Hệ thống build đã được thiết kế linh hoạt với kiến trúc tham số động. Trong trường hợp cần quay lại phiên bản 2.16 vì bất kỳ lý do gì:

1. **Khôi phục nhanh qua dòng lệnh (không cần sửa code):**
   ```bash
   ./build.sh all --pjsip-version 2.16 --rebuild
   ```
2. **Khôi phục cấu hình mặc định:**
   Sửa lại `PJSIP_VERSION="${PJSIP_VERSION:-2.16}"` trong `config.default.sh` và commit.
