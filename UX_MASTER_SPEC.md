# UX_MASTER_SPEC.md

## 1. Mục đích

Tài liệu này là nguồn tham chiếu duy nhất cho UI/UX flow eKYC trên Android.

Từ thời điểm này:
- prompt cũ chỉ là tài liệu khám phá
- mockup cũ chỉ là phương án đã thử
- chỉ các màn được đánh dấu trong tài liệu này mới là chuẩn để handoff cho dev/designer/AI coding agent

## 2. Phạm vi flow

Flow eKYC hiện tại gồm các màn chính:

1. Welcome
2. Camera permission pre-ask
3. Camera permission denied / mở cài đặt
4. OCR capture
5. Review extracted info
6. Live face scan
7. Processing
8. Success
9. Review needed (retryable)
10. Reject / could not verify
11. Cooldown / wait-before-retry
12. Manual review in progress

## 3. Trạng thái quyết định

Chỉ dùng 3 trạng thái:

- Approved: chốt, không generate lại bằng Stitch
- Approved with minor cleanup: không cần redesign, dev/designer chỉnh nhẹ theo note
- Needs redesign: chưa đạt, mới được phép prompt lại

## 4. Quy tắc chung của flow

### 4.1. Quy tắc bắt buộc
- Không dùng placeholder branding như “The Guided Guardian”
- Không có bottom navigation trong flow eKYC
- Không hiện chi tiết kỹ thuật nội bộ cho user:
  - correlation id
  - hash
  - HTTP status
  - decision nội bộ
  - retry policy nội bộ
  - trust/integrity detail
- Tất cả copy user-facing dùng tiếng Việt, ngắn, rõ, không kỹ thuật
- Mỗi màn chỉ phục vụ một logic chính
- Mỗi màn phải có next step rõ ràng

### 4.2. Progress model chuẩn
Dùng thống nhất:

- Bước 1/4: Chụp giấy tờ
- Bước 2/4: Kiểm tra thông tin
- Bước 3/4: Xác minh khuôn mặt
- Bước 4/4: Kết quả

### 4.3. Tone of voice
Giọng điệu phải:
- ngắn
- rõ
- lịch sự
- trấn an
- action-oriented

Tránh:
- từ kỹ thuật
- từ quá máy móc
- từ nghe như phán xét

---

## 5. Decision log theo từng màn

### 5.1. Welcome
**Trạng thái:** Approved

**Mục tiêu màn:**
- giải thích nhanh flow
- cho user biết mất bao lâu
- cho user biết cần chuẩn bị gì
- tạo trust ban đầu

**Nội dung chuẩn:**
- Title: `Xác minh danh tính`
- Subtitle: `Chỉ mất khoảng 2 phút để xác minh và bảo vệ tài khoản của bạn.`
- 3 prep items:
  - `Chuẩn bị CCCD — Dùng CCCD bản gốc, còn hạn`
  - `Đứng ở nơi đủ sáng — Tránh lóa hoặc quá tối khi quét`
  - `Quét khuôn mặt trong vài giây — Giữ khuôn mặt rõ và nhìn thẳng vào màn hình`
- Flow hint:
  - `Gồm 4 bước ngắn: giấy tờ · thông tin · khuôn mặt · kết quả`
- CTA:
  - `Bắt đầu xác minh`
- Privacy note:
  - `Thông tin chỉ được dùng để xác minh tài khoản`

**Quyết định:**
- Không dùng hero image lớn kiểu ổ khóa
- Không dùng branding template
- Không nói thuật ngữ kỹ thuật

---

### 5.2. Camera permission pre-ask
**Trạng thái:** Approved

**Mục tiêu màn:**
- xin quyền camera lần đầu
- giải thích ngắn gọn vì sao cần camera

**Nội dung chuẩn:**
- Title: `Cho phép dùng camera`
- Body: `Camera được dùng để chụp giấy tờ và xác minh khuôn mặt của bạn.`
- Primary CTA: `Cho phép camera`
- Secondary: `Để sau`
- Helper line:
  - `Bạn có thể cấp quyền ngay bây giờ để tiếp tục xác minh.`

**Quyết định:**
- Đây là state riêng
- Không được trộn với state mở cài đặt
- Không có hướng dẫn settings ở màn này

---

### 5.3. Camera permission denied / mở cài đặt
**Trạng thái:** Approved with minor cleanup

**Mục tiêu màn:**
- hướng user mở cài đặt khi camera đã bị từ chối hoặc permanently denied

**Nội dung chuẩn:**
- Title: `Bật quyền camera để tiếp tục`
- Body: `Hãy mở cài đặt và cho phép ứng dụng sử dụng camera.`
- Steps:
  - `1. Mở cài đặt`
  - `2. Chọn Quyền truy cập`
  - `3. Bật Camera`
- Primary CTA: `Mở cài đặt`
- Secondary: `Quay lại`

**Cleanup cần làm:**
- bỏ hình hướng dẫn hệ thống nếu còn
- bỏ mọi footer kiểu version/build info

---

### 5.4. OCR capture
**Trạng thái:** Approved

**Mục tiêu màn:**
- chụp CCCD theo logic auto-capture
- giảm mơ hồ
- hướng dẫn user theo tín hiệu chất lượng ảnh

**Nội dung chuẩn:**
- Top context: `Xác minh tài khoản`
- Step chip: `Bước 1/4`
- Section label: `Chụp giấy tờ`
- Main instruction:
  - `Đưa mặt trước CCCD vào khung`
- Support text:
  - `Hệ thống sẽ tự động chụp khi ảnh rõ và nằm đúng khung.`
- Dynamic helper ví dụ:
  - `Tránh bị lóa`
  - `Giữ điện thoại thẳng`
  - `Đưa lại gần hơn một chút`
  - `Giữ yên trong giây lát`
- Secondary status:
  - `Đang nhận diện...`
- Tip card:
  - `Mẹo chụp nhanh`
  - `Đảm bảo giấy tờ nằm trọn trong khung và không bị lóa.`

**Quyết định:**
- Đây là auto-capture thật sự về mặt UX
- Không có shutter button lớn
- Camera preview là phần chính
- Torch ở vị trí tự nhiên trong preview
- Helper và status là 2 lớp khác nhau

**Note cho dev:**
- Mockup chỉ là placeholder, build thật phải dùng camera feed
- Không thêm manual capture nếu chưa đổi logic sản phẩm

---

### 5.5. Review extracted info
**Trạng thái:** Approved with minor cleanup

**Mục tiêu màn:**
- cho user kiểm tra và sửa dữ liệu OCR

**Nội dung chuẩn:**
- Step chip: `Bước 2/4`
- Title: `Kiểm tra thông tin`
- Subtitle: `Hãy kiểm tra và chỉnh sửa nếu có sai sót`
- Fields:
  - Họ và tên
  - Số CCCD
  - Ngày sinh
- Document preview action:
  - `Xem lại`
- Primary CTA:
  - `Thông tin đã đúng`
- Secondary:
  - `Chụp lại giấy tờ`

**Cleanup cần làm:**
- polish nhẹ label/form spacing nếu cần
- giữ thumbnail giấy tờ đủ rõ để đối chiếu
- không hiện hash hoặc ID nội bộ

---

### 5.6. Live face scan
**Trạng thái:** Approved

**Mục tiêu màn:**
- quét khuôn mặt với cảm giác bình tĩnh, không quá tải

**Nội dung chuẩn:**
- Top context: `Xác minh tài khoản`
- Step chip: `Bước 3/4`
- Main title:
  - `Nhìn thẳng vào màn hình`
- Helper chip:
  - `Đưa máy ngang tầm mắt`
- Warning chip khi cần:
  - `Khuôn mặt chưa đủ sáng`
- Secondary status:
  - `Đang nhận diện`
- Primary CTA:
  - `Tiếp tục quét`
- Support link:
  - `Tôi gặp khó khăn ở bước này`

**Quyết định:**
- Không có bottom nav
- Không có decorative lens/demo art
- Không có metadata người dùng trên preview
- Warning dùng tone cam dịu, không đỏ gắt
- Preview thật khi build phải là camera feed

---

### 5.7. Processing
**Trạng thái:** Approved

**Mục tiêu màn:**
- trấn an user rằng app đang xử lý

**Nội dung chuẩn:**
- Title: `Đang xác minh`
- Body:
  - `Quá trình này thường chỉ mất vài giây. Vui lòng không đóng ứng dụng hoặc quay lại.`
- Progress rows:
  - `Kiểm tra giấy tờ`
  - `Đối chiếu thông tin`
  - `Xác minh khuôn mặt`

**Quyết định:**
- không có quote card
- không có footer mã hóa
- không có chi tiết kỹ thuật nội bộ

---

### 5.8. Success
**Trạng thái:** Approved

**Mục tiêu màn:**
- thông báo thành công ngắn gọn, rõ

**Nội dung chuẩn:**
- Context: `Bước 4/4`
- Title: `Xác minh thành công`
- Body:
  - `Thông tin của bạn đã được xác minh.`
- Primary CTA:
  - `Tiếp tục`

**Quyết định:**
- bỏ các card marketing/phụ trợ không cần thiết
- không kéo dài màn bằng ảnh trang trí

---

### 5.9. Review needed (retryable)
**Trạng thái:** Approved

**Mục tiêu màn:**
- user chưa qua ngay, nhưng có thể retry một bước cụ thể

**Nội dung chuẩn:**
- Title: `Cần kiểm tra thêm`
- Body:
  - `Hệ thống chưa thể xác minh ngay lúc này. Bạn có thể thử lại theo hướng dẫn bên dưới.`
- Guidance card:
  - `Hướng dẫn khắc phục`
  - `Ảnh giấy tờ chưa đủ rõ`
  - `- Thử lại ở nơi đủ sáng`
  - `- Giữ giấy tờ nằm trọn trong khung`
- Primary CTA:
  - `Thử lại ảnh giấy tờ`
- Secondary:
  - `Quay lại sau`
- Support footer:
  - `Bạn gặp khó khăn khi xác minh?`
  - `Liên hệ hỗ trợ`

**Quyết định:**
- Đây là state retryable
- Không được nhắc manual review
- Không được nói đang chờ chuyên viên

---

### 5.10. Reject / could not verify
**Trạng thái:** Approved

**Mục tiêu màn:**
- nói rõ chưa xác minh được lần này
- cho user cách phục hồi

**Nội dung chuẩn:**
- Title: `Chưa thể xác minh`
- Body:
  - `Chúng tôi chưa thể xác minh lần này. Bạn có thể thử lại với giấy tờ rõ hơn và ở nơi đủ sáng.`
- Help cards:
  - `Đứng ở nơi đủ sáng`
  - `Giữ giấy tờ rõ nét`
- Primary CTA:
  - `Thử lại từ đầu`
- Secondary:
  - `Liên hệ hỗ trợ`

---

### 5.11. Cooldown / wait-before-retry
**Trạng thái:** Approved with minor cleanup

**Mục tiêu màn:**
- báo user phải chờ trước khi thử lại

**Nội dung chuẩn:**
- Title: `Vui lòng thử lại sau ít phút`
- Body:
  - `Hệ thống cần một chút thời gian nghỉ ngơi trước khi bạn thử lại. Cảm ơn sự kiên nhẫn của bạn.`
- Countdown card:
  - `Thời gian chờ còn lại`
- Primary CTA:
  - `Quay lại trang chính`
- Secondary:
  - `Liên hệ trợ giúp`

**Cleanup cần làm:**
- bỏ mọi footer/branding template nếu còn
- giữ màn gọn, không thêm card rác

---

### 5.12. Manual review in progress
**Trạng thái:** Approved with minor cleanup

**Mục tiêu màn:**
- báo hồ sơ đang ở nhánh kiểm tra thêm
- không khuyến khích retry ngay

**Nội dung chuẩn:**
- Title: `Hồ sơ đang được kiểm tra`
- Body:
  - `Chúng tôi cần thêm thời gian để xác minh. Bạn sẽ được thông báo khi có kết quả.`
- ETA card:
  - `Thời gian xử lý`
  - `24–48 giờ làm việc`
- Notification card:
  - `Thông báo`
  - `Kết quả sẽ được gửi qua ứng dụng hoặc email đã đăng ký.`
- Primary CTA:
  - `Đã hiểu`

**Quyết định:**
- Không có retry CTA ở màn này
- Đây là state riêng, không trộn với retryable review

---

## 6. Quy tắc logic bắt buộc

### Retryable review
- Có CTA retry
- Có hướng dẫn khắc phục
- Không nhắc manual review

### Manual review
- Không có retry CTA
- Có ETA
- Có thông báo kênh nhận kết quả

### Cooldown
- User phải chờ
- Có countdown hoặc thông tin thời gian chờ
- Không dùng ngôn ngữ máy móc

### Permission flow
- Pre-ask và denied là 2 state tách biệt hoàn toàn

### OCR flow
- Auto-capture là logic chính thức
- Không có shutter button lớn nếu chưa đổi quyết định sản phẩm

---

## 7. Danh sách ảnh chuẩn cần giữ

Thư mục đề xuất:

`ux_handoff/`

Tên file đề xuất:

- `welcome_approved.png`
- `permission_preask_approved.png`
- `permission_denied_approved.png`
- `ocr_capture_approved.png`
- `review_form_approved.png`
- `live_face_approved.png`
- `processing_approved.png`
- `success_approved.png`
- `review_needed_approved.png`
- `reject_approved.png`
- `cooldown_approved.png`
- `manual_review_approved.png`

## 8. Danh sách ảnh cũ cần archive

Thư mục đề xuất:

`ux_archive/`

Quy tắc:
- mọi ảnh exploration cũ phải chuyển vào archive
- không dùng ảnh archive cho dev handoff
- prompt cũ không còn là tài liệu chuẩn

---

## 9. Handoff rule cho dev/designer/agent

Chỉ được dùng:
- `UX_MASTER_SPEC.md`
- thư mục `ux_handoff/`

Không được dùng:
- prompt Stitch cũ
- ảnh cũ không được gắn nhãn approved
- bản exploration chưa chốt

---

## 10. Event tracking tối thiểu

Các event nên có:

- `welcome_viewed`
- `welcome_started`
- `permission_prompt_shown`
- `permission_granted`
- `permission_denied`
- `ocr_screen_viewed`
- `ocr_capture_success`
- `ocr_capture_failed_reason`
- `review_viewed`
- `review_confirmed`
- `face_scan_viewed`
- `face_scan_success`
- `face_scan_failed_reason`
- `processing_started`
- `result_success`
- `result_review_retryable`
- `result_reject`
- `result_cooldown`
- `result_manual_review`

---

## 11. Kết luận hiện tại

Flow đã đủ tốt để:
- dừng exploration bằng Stitch
- chuyển sang implementation trong Flutter
- handoff cho dev/designer/AI coding agent bằng spec