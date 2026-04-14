import 'package:ekyc_app/screens/review_screen.dart';
import 'package:ekyc_app/services/ekyc_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = EkycSession.instance;

  setUp(() {
    session.clearAll();
    session.setOcrData(
      cccd: '001234567890',
      fullName: 'NGUYEN VAN A',
      dateOfBirth: '01/01/1990',
      cccdHash:
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
    );
  });

  tearDown(() {
    session.clearAll();
  });

  testWidgets('review screen shows consistent step and user actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReviewScreen()));

    expect(find.text('Bước 2/4'), findsOneWidget);
    expect(find.text('Kiểm tra thông tin'), findsOneWidget);
    expect(find.text('Xem lại'), findsOneWidget);
    expect(find.text('Thông tin đã đúng'), findsOneWidget);
    expect(find.text('Chụp lại giấy tờ'), findsOneWidget);
  });
}
