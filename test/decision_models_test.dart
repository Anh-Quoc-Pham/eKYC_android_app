import 'package:ekyc_app/models/decision_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DecisionOutcome.fromBackendPayload', () {
    test('parses explicit PASS payload', () {
      final payload = <String, dynamic>{
        'verified': true,
        'decision_status': 'PASS',
        'reason_codes': <String>[],
        'user_message_key': 'decision.pass',
        'retry_allowed': false,
        'retry_reason': 'none',
        'retry_policy': 'NO_RETRY',
        'correlation_id': 'cid-pass-001',
        'risk_signals': <String, dynamic>{
          'face': {'match_score': 0.98},
        },
      };

      final outcome = DecisionOutcome.fromBackendPayload(
        payload,
        fallbackStatusCode: 200,
        fallbackMessage: 'ok',
      );

      expect(outcome.status, DecisionStatus.pass);
      expect(outcome.retryPolicy, RetryPolicy.noRetry);
      expect(outcome.retryAllowed, isFalse);
      expect(outcome.reasonCodes, isEmpty);
      expect(outcome.correlationId, 'cid-pass-001');
      expect(outcome.isPass, isTrue);
    });

    test('maps rate_limited response to retry-limit reason', () {
      final payload = <String, dynamic>{
        'verified': false,
        'decision_status': 'REJECT',
        'reason': 'rate_limited',
        'retry_allowed': false,
        'retry_policy': 'NO_RETRY',
      };

      final outcome = DecisionOutcome.fromBackendPayload(
        payload,
        fallbackStatusCode: 429,
        fallbackMessage: 'rate_limited',
      );

      expect(outcome.status, DecisionStatus.reject);
      expect(outcome.reasonCodes, contains(ReasonCodes.sessionRetryLimit));
      expect(outcome.retryAllowed, isFalse);
      expect(outcome.retryPolicy, RetryPolicy.noRetry);
    });

    test('falls back to REVIEW when verify failed without status', () {
      final payload = <String, dynamic>{'verified': false, 'reason': 'unknown'};

      final outcome = DecisionOutcome.fromBackendPayload(
        payload,
        fallbackStatusCode: 400,
        fallbackMessage: 'request_failed',
      );

      expect(outcome.status, DecisionStatus.review);
      expect(
        outcome.reasonCodes,
        contains(ReasonCodes.unknownErrorSafeFallback),
      );
      expect(outcome.retryAllowed, isTrue);
    });
  });

  group('DecisionOutcome.networkInterrupted', () {
    test('creates retryable review outcome', () {
      final outcome = DecisionOutcome.networkInterrupted(
        correlationId: 'cid-network-001',
      );

      expect(outcome.status, DecisionStatus.review);
      expect(outcome.retryPolicy, RetryPolicy.immediate);
      expect(outcome.retryAllowed, isTrue);
      expect(
        outcome.reasonCodes,
        equals(const [ReasonCodes.networkInterrupted]),
      );
      expect(outcome.correlationId, 'cid-network-001');
    });
  });
}
