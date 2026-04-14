import 'package:ekyc_app/screens/ocr_camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('camera pre-ask and denied screens are distinct', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPermissionPreAskView(onAllowCamera: () {}, onLater: () {}),
      ),
    );

    expect(find.text('Cho phép dùng camera'), findsOneWidget);
    expect(
      find.text('Bạn có thể cấp quyền ngay bây giờ để tiếp tục xác minh.'),
      findsOneWidget,
    );
    expect(find.text('Mở cài đặt'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: CameraPermissionDeniedView(onOpenSettings: () {}, onBack: () {}),
      ),
    );

    expect(find.text('Bật quyền camera để tiếp tục'), findsOneWidget);
    expect(find.text('Mở cài đặt'), findsOneWidget);
    expect(find.text('1. Mở cài đặt'), findsOneWidget);
    expect(find.text('2. Chọn Quyền truy cập'), findsOneWidget);
    expect(find.text('3. Bật Camera'), findsOneWidget);
    expect(find.text('Cho phép dùng camera'), findsNothing);
  });
}
