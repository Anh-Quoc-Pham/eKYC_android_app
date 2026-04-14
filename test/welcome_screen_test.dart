import 'package:ekyc_app/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Welcome screen shows UX master copy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(find.text('Xác minh tài khoản'), findsOneWidget);
    expect(find.text('Xác minh danh tính'), findsOneWidget);
    expect(
      find.text(
        'Chỉ mất khoảng 2 phút để xác minh và bảo vệ tài khoản của bạn.',
      ),
      findsOneWidget,
    );
    expect(find.text('Chuẩn bị CCCD'), findsOneWidget);
    expect(find.text('Đứng ở nơi đủ sáng'), findsOneWidget);
    expect(find.text('Quét khuôn mặt trong vài giây'), findsOneWidget);
    expect(find.text('Bắt đầu xác minh'), findsOneWidget);
    expect(
      find.text('Thông tin chỉ được dùng để xác minh tài khoản'),
      findsOneWidget,
    );
  });
}
