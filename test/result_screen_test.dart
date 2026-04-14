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
      AppRoutes.ocr: (_) => const Scaffold(body: Text('ocr-route')),
      AppRoutes.welcome: (_) => const Scaffold(body: Text('welcome-route')),
      AppRoutes.review: (_) => const Scaffold(body: Text('review-route')),
      AppRoutes.face: (_) => const Scaffold(body: Text('face-route')),
      AppRoutes.result: (_) => const Scaffold(body: Text('result-route')),
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

  group('ResultScreen UX state mapping', () {
    testWidgets('PASS shows success content and step 4/4', (
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

      expect(find.text('Bước 4/4'), findsOneWidget);
      expect(find.text('Xác minh thành công'), findsOneWidget);
      expect(find.text('Tiếp tục'), findsOneWidget);
    });

    testWidgets('retryable review does not show manual review wording', (
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
          reasonCodes: const <String>[ReasonCodes.documentBlur],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Cần kiểm tra thêm'), findsOneWidget);
      expect(find.text('Thử lại ảnh giấy tờ'), findsOneWidget);
      expect(find.text('Hồ sơ đang được kiểm tra'), findsNothing);
    });

    testWidgets('manual review state does not show retry CTA', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: false,
        statusCode: 200,
        message: 'manual_review',
        payload: const <String, dynamic>{},
        decision: _decision(
          status: DecisionStatus.review,
          retryPolicy: RetryPolicy.manualReview,
          retryAllowed: false,
          userMessageKey: 'decision.review.internal_required',
          reasonCodes: const <String>[ReasonCodes.internalReviewRequired],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ đang được kiểm tra'), findsOneWidget);
      expect(find.text('Đã hiểu'), findsOneWidget);
      expect(find.text('Thử lại ảnh giấy tờ'), findsNothing);
      expect(find.text('Thử lại từ đầu'), findsNothing);
    });

    testWidgets('reject state hides technical diagnostics', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: false,
        statusCode: 429,
        message: 'rate_limited',
        payload: const <String, dynamic>{'correlation_id': 'cid-x'},
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

      expect(find.text('Chưa thể xác minh'), findsOneWidget);
      expect(find.textContaining('HTTP'), findsNothing);
      expect(find.textContaining('Correlation ID'), findsNothing);
      expect(find.textContaining('Retry Policy'), findsNothing);
    });

    testWidgets('wait-before-retry maps to cooldown screen', (
      WidgetTester tester,
    ) async {
      session.setVerificationResult(
        succeeded: false,
        statusCode: 200,
        message: 'cooldown',
        payload: const <String, dynamic>{'retry_after_seconds': 180},
        decision: _decision(
          status: DecisionStatus.review,
          retryPolicy: RetryPolicy.waitBeforeRetry,
          retryAllowed: true,
          userMessageKey: 'decision.review.device_trust_pending',
          reasonCodes: const <String>[ReasonCodes.deviceTrustUnavailable],
        ),
      );

      await tester.pumpWidget(_buildResultHost());
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng thử lại sau ít phút'), findsOneWidget);
      expect(find.text('Quay lại trang chính'), findsOneWidget);
    });
  });
}
