eKYC Simulator (Privacy-First)
1. Tổng quan dự án
eKYC Simulator (Privacy-First) là ứng dụng mô phỏng quy trình định danh điện tử theo hướng bảo vệ quyền riêng tư ngay từ lớp kiến trúc. Sản phẩm tập trung vào khả năng quét giấy tờ tùy thân, trích xuất dữ liệu, xác minh thông tin và chuẩn bị cho các cơ chế chứng thực nâng cao trong các phiên bản sau.
Mục tiêu dài hạn là xây dựng một nền tảng eKYC hiện đại, minh bạch, dễ mở rộng và giảm thiểu tối đa rủi ro rò rỉ dữ liệu nhạy cảm.

2. Tầm nhìn và triết lý
Tầm nhìn
Xây dựng một bộ khung eKYC mô phỏng có thể tiến hóa thành hệ thống production-ready, trong đó dữ liệu định danh được xử lý ưu tiên trên thiết bị người dùng, giúp tăng tính riêng tư và giảm bề mặt tấn công.

Triết lý cốt lõi
On-device OCR & Hashing, không lưu ảnh thô lên server.

Nguyên tắc kiến trúc Privacy-First
Data Minimization: chỉ thu thập dữ liệu cần thiết cho từng bước xác minh.
On-Device First: ưu tiên xử lý trên thiết bị trước khi cân nhắc xử lý phía server.
No Raw Image Persistence: không lưu trữ dài hạn hoặc truyền tải ảnh gốc theo mặc định.
Cryptographic Integrity: dùng băm SHA-256 để tạo dấu vết toàn vẹn cho dữ liệu quan trọng.
Secure-by-Default: dữ liệu nhạy cảm được lưu cục bộ bằng cơ chế bảo mật hệ điều hành.
Auditability: mọi quyết định kỹ thuật quan trọng đều có lý do và khả năng truy vết.
3. Mục tiêu sản phẩm
Cung cấp trải nghiệm quét CCCD nhanh, ổn định, có bước kiểm tra dữ liệu trước khi xác nhận.
Bảo vệ dữ liệu cá nhân bằng cách không phụ thuộc vào lưu ảnh thô trên hạ tầng server.
Mở rộng tuần tự sang xác minh sinh trắc học và liveness mà vẫn giữ triết lý Privacy-First.
Chuẩn bị nền tảng cho mô hình xác thực nâng cao với Zero-Knowledge Proof (ZKP).
4. Techstack
Thành phần cốt lõi
Flutter
Vai trò: nền tảng phát triển ứng dụng đa nền tảng, đồng nhất codebase và tối ưu tốc độ triển khai.

Google ML Kit (OCR)
Vai trò: nhận diện ký tự trên ảnh giấy tờ tùy thân trực tiếp trên thiết bị.

SHA-256 (Hashing)
Vai trò: tạo fingerprint toàn vẹn cho dữ liệu định danh, hạn chế phụ thuộc vào dữ liệu gốc.

Flutter Secure Storage
Vai trò: lưu trữ dữ liệu nhạy cảm cục bộ bằng Keychain/Keystore theo chuẩn bảo mật nền tảng.

Thành phần mở rộng theo lộ trình
MediaPipe
Dùng cho đối sánh khuôn mặt và active liveness ở V2.

FastAPI
Dùng cho backend tích hợp giao thức chứng minh/kiểm chứng ở V3.

5. Luồng dữ liệu chuẩn Privacy-First
Người dùng chụp hoặc quét CCCD bằng camera trong ứng dụng.
OCR chạy trên thiết bị để trích xuất dữ liệu chữ.
Dữ liệu được chuẩn hóa và kiểm tra định dạng.
Trường dữ liệu trọng yếu được băm SHA-256 để phục vụ đối chiếu toàn vẹn.
Dữ liệu cần thiết được lưu cục bộ bằng secure storage.
Ảnh thô không được upload lên server theo mặc định.
Nếu có backend, chỉ truyền dữ liệu tối giản, ưu tiên dữ liệu đã bảo vệ.
6. Phạm vi dự án
In scope
Quét CCCD và trích xuất dữ liệu bằng OCR.
Màn hình review để người dùng xác nhận/chỉnh sửa trước khi lưu.
Lưu dữ liệu nhạy cảm cục bộ an toàn.
Mở rộng có kiểm soát sang sinh trắc học, liveness, ZKP.
Out of scope giai đoạn đầu
Lưu ảnh thô giấy tờ lên server.
Chia sẻ dữ liệu định danh thô cho bên thứ ba.
Huấn luyện mô hình OCR tùy biến từ đầu.
Tự động phê duyệt hoàn toàn không có bước xác nhận người dùng.
7. Lộ trình phát triển
V1: OCR Core (Quét CCCD) + Review Screen + Local Secure Storage
Mục tiêu
Hoàn thiện luồng eKYC nền tảng theo nguyên tắc Privacy-First.
Đảm bảo dữ liệu OCR được người dùng kiểm tra trước khi xác nhận.
Hạng mục chính
Camera capture tối ưu cho giấy tờ CCCD.
OCR pipeline on-device bằng ML Kit.
Chuẩn hóa và ánh xạ trường dữ liệu định danh.
Review screen thể hiện mức tin cậy dữ liệu theo từng trường.
Hashing SHA-256 cho dữ liệu trọng yếu.
Lưu dữ liệu cục bộ bằng Flutter Secure Storage.
Cơ chế xóa dữ liệu và reset phiên làm việc.
Tiêu chí hoàn thành
Luồng quét → OCR → review → lưu chạy end-to-end ổn định.
Không upload ảnh thô trong luồng mặc định.
Dữ liệu nhạy cảm được lưu cục bộ an toàn.
Log kỹ thuật không chứa dữ liệu định danh thô.
Rủi ro và giảm thiểu
OCR sai do ảnh mờ/lóa/nghiêng
Giảm thiểu: hướng dẫn chụp tốt, tiền xử lý ảnh, hậu kiểm định dạng.
Dữ liệu không đồng nhất định dạng
Giảm thiểu: quy tắc chuẩn hóa và validate theo trường.
UX review phức tạp
Giảm thiểu: giao diện rõ ràng, ưu tiên thao tác ngắn gọn.
V2: Face Matching & Active Liveness (MediaPipe)
Mục tiêu
Bổ sung lớp xác minh sinh trắc học để giảm gian lận danh tính.
Xác nhận người dùng là người thật đang hiện diện tại thời điểm xác thực.
Hạng mục chính
Trích xuất đặc trưng khuôn mặt và đối sánh giấy tờ với selfie.
Active liveness theo cơ chế challenge-response.
Chấm điểm rủi ro và ngưỡng chấp nhận.
Quản lý dữ liệu sinh trắc học theo nguyên tắc tối thiểu.
Cơ chế fallback khi thiết bị hoặc môi trường không đạt điều kiện.
Tiêu chí hoàn thành
Phát hiện hiệu quả các kịch bản spoof cơ bản.
Đảm bảo cân bằng giữa bảo mật và trải nghiệm người dùng.
Duy trì tốc độ xử lý phù hợp trên thiết bị phổ thông.
Rủi ro và giảm thiểu
Sai số sinh trắc học do điều kiện môi trường
Giảm thiểu: tăng cường chất lượng đầu vào, đo lường liên tục chỉ số sai lệch.
Tăng tải xử lý trên thiết bị
Giảm thiểu: tối ưu pipeline, giảm tác vụ không cần thiết.
UX bị gián đoạn vì challenge khó
Giảm thiểu: thiết kế challenge ngắn, hướng dẫn rõ, có retry hợp lý.
V3: ZKP Integration (Schnorr Protocol) & Backend (FastAPI)
Mục tiêu
Nâng cấp sang mô hình xác thực bảo toàn quyền riêng tư ở cấp giao thức.
Cho phép chứng minh thuộc tính định danh mà không lộ dữ liệu gốc.
Hạng mục chính
Tích hợp Schnorr Protocol cho luồng chứng minh và kiểm chứng.
Xây backend FastAPI để điều phối challenge và kết quả xác minh.
Thiết kế API phục vụ proof generation/submission/verification.
Bảo vệ kênh truyền và kiểm soát truy cập API.
Thiết lập logging, monitoring theo nguyên tắc không lộ dữ liệu nhạy cảm.
Tiêu chí hoàn thành
Luồng proof-verification chạy ổn định trong môi trường mô phỏng.
API backend rõ ràng, dễ tích hợp và mở rộng.
Dữ liệu truyền tải tuân thủ nguyên tắc tối thiểu hóa.
Rủi ro và giảm thiểu
Độ phức tạp triển khai mật mã
Giảm thiểu: tách module rõ ràng, kiểm thử chặt chẽ, review bảo mật.
Vận hành backend tăng chi phí và rủi ro cấu hình
Giảm thiểu: chuẩn hóa quy trình triển khai và kiểm soát cấu hình.
Sai lệch giữa mô hình mô phỏng và production
Giảm thiểu: xác định rõ giả định và kế hoạch hardening theo từng giai đoạn.
8. Yêu cầu phi chức năng
Bảo mật: không rò rỉ dữ liệu định danh qua log, cache, hoặc telemetry.
Hiệu năng: thời gian xử lý OCR và phản hồi UI phù hợp cho thiết bị tầm trung.
Độ tin cậy: có xử lý lỗi rõ ràng cho camera, OCR, liveness và lưu trữ.
Khả dụng: luồng người dùng mạch lạc, hướng dẫn đầy đủ, dễ retry.
Khả năng mở rộng: kiến trúc module hóa để thêm tính năng mà không phá vỡ lõi.
9. Quản trị dữ liệu và tuân thủ nội bộ
Chỉ lưu dữ liệu cần cho mục đích xác minh.
Ưu tiên lưu hash/metadata thay cho dữ liệu gốc khi có thể.
Có cơ chế xóa dữ liệu cục bộ theo yêu cầu người dùng.
Phân tách dữ liệu nghiệp vụ và dữ liệu debug.
Định kỳ rà soát chính sách dữ liệu theo từng phiên bản.
10. Chỉ số theo dõi thành công
Độ chính xác OCR theo từng trường thông tin.
Thời gian hoàn tất một phiên eKYC.
Tỷ lệ phiên thất bại theo nguyên nhân.
Tỷ lệ người dùng hoàn thành toàn bộ quy trình.
Số sự cố liên quan đến quyền riêng tư hoặc xử lý dữ liệu ngoài phạm vi.
11. Kết luận định hướng
eKYC Simulator (Privacy-First) theo đuổi chiến lược phát triển có kiểm soát: xây chắc phần lõi ở V1, tăng cường xác minh sinh trắc học ở V2, và mở rộng sang mô hình xác thực mật mã ở V3.
Mọi quyết định kỹ thuật xuyên suốt dự án phải bám trụ vào nguyên tắc trung tâm: xử lý tại thiết bị, tối thiểu hóa dữ liệu, và không lưu ảnh thô lên server theo mặc định.