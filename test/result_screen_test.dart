import 'package:ekyc_app/app_routes.dart';
import 'package:ekyc_app/models/decision_models.dart';
import 'package:ekyc_app/screens/result_screen.dart';
import 'package:ekyc_app/services/ekyc_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DecisionOutcome _decision({
  required DecisionStatus status,
  required RetryPolicy retryPolicy,
  required bool retryAllowed,
  required String userMessageKey,
  required List<String> reasonCodes,
}) {
  return DecisionOutcome(
    status: status,
    reasonCodes: reasonCodes,
    userMessageKey: userMessageKey,
    retryAllowed: retryAllowed,
    retryReason: retryAllowed ? 'retry_recommended' : 'no_retry',
    retryPolicy: retryPolicy,
    correlationId: 'cid-ui-test-001',
    riskSignals: const <String, dynamic>{},
    verified: status == DecisionStatus.pass,
  );
}

Widget _buildResultHost() {
  return MaterialApp(
    home: const ResultScreen(),
    routes: {
      AppRoutes.face: (_) => const Scaffold(body: Text('face-route')),
      AppRoutes.review: (_) => const Scaffold(body: Text('review-route')),
      AppRoutes.welcome: (_) => const Scaffold(body: Text('welcome-route')),
    },
  );
}

void main() {
  final session = EkycSession.instance;

  setUp(() {
    session.clearAll();
  });

  tearDown(() {
    session.clearAll();
  });

  group('ResultScreen decision mapping', () {
    testWidgets('PASS shows success headline and no retry actions', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: true,
        statusCode: 200,
        message: 'ok',
        payload: const <String, dynamic>{},
        decision: _decision(
          status: DecisionStatus.pass,
          retryPolicy: RetryPolicy.noRetry,
          retryAllowed: false,
          userMessageKey: 'decision.pass',
          reasonCodes: const <String>[],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Đã xác thực thành công'), findsOneWidget);
      expect(find.text('Thử lại xác minh khuôn mặt'), findsNothing);
      expect(find.text('Sửa OCR và thử lại'), findsNothing);
    });

    testWidgets('REVIEW with user-correction shows OCR retry action', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: false,
        statusCode: 200,
        message: 'review',
        payload: const <String, dynamic>{},
        decision: _decision(
          status: DecisionStatus.review,
          retryPolicy: RetryPolicy.userCorrection,
          retryAllowed: true,
          userMessageKey: 'decision.review.document_quality',
          reasonCodes: const <String>[ReasonCodes.ocrFieldMismatch],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Cần rà soát thêm'), findsOneWidget);
      expect(find.text('Sửa OCR và thử lại'), findsOneWidget);
      expect(find.text('Thử lại xác minh khuôn mặt'), findsNothing);
    });

    testWidgets('REVIEW immediate retry shows face retry action', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: false,
        statusCode: 0,
        message: 'network_error',
        payload: const <String, dynamic>{},
        decision: _decision(
          status: DecisionStatus.review,
          retryPolicy: RetryPolicy.immediate,
          retryAllowed: true,
          userMessageKey: 'decision.review.network_retry',
          reasonCodes: const <String>[ReasonCodes.networkInterrupted],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Cần rà soát thêm'), findsOneWidget);
      expect(find.text('Thử lại xác minh khuôn mặt'), findsOneWidget);
      expect(find.text('Sửa OCR và thử lại'), findsNothing);
    });

    testWidgets('REJECT shows reject headline and no retry actions', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: false,
        statusCode: 429,
        message: 'rate_limited',
        payload: const <String, dynamic>{},
        decision: _decision(
          status: DecisionStatus.reject,
          retryPolicy: RetryPolicy.noRetry,
          retryAllowed: false,
          userMessageKey: 'decision.reject.retry_limit',
          reasonCodes: const <String>[ReasonCodes.sessionRetryLimit],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Từ chối xác thực'), findsOneWidget);
      expect(find.text('Thử lại xác minh khuôn mặt'), findsNothing);
      expect(find.text('Sửa OCR và thử lại'), findsNothing);
    });
  });
}
