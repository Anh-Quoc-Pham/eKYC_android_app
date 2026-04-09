import 'package:flutter_test/flutter_test.dart';

import 'package:ekyc_app/main.dart';

void main() {
  testWidgets('renders unsupported-platform fallback UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const EkycApp(cameras: [], isOcrSupportedPlatform: false),
    );

    expect(
      find.text('OCR realtime hiện chỉ hỗ trợ Android và iOS.'),
      findsOneWidget,
    );
  });

  testWidgets('renders fallback UI when no camera is available', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const EkycApp(cameras: []));

    expect(
      find.text('Không tìm thấy camera khả dụng trên thiết bị này.'),
      findsOneWidget,
    );
  });
}
