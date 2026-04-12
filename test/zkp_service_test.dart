import 'dart:convert';

import 'package:ekyc_app/models/decision_models.dart';
import 'package:ekyc_app/services/zkp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.statusCode, required this.responseBody});

  final int statusCode;
  final Map<String, dynamic> responseBody;

  Map<String, String>? lastHeaders;
  Map<String, dynamic>? lastJsonBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastHeaders = request.headers;
      lastJsonBody = jsonDecode(request.body) as Map<String, dynamic>;
    }

    final bytes = utf8.encode(jsonEncode(responseBody));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('simulated_network_failure');
  }
}

void main() {
  group('ZkpService contract safety', () {
    test('propagates correlation_id in header and body', () async {
      const correlationId = 'cid-app-propagation-001';
      final client = _RecordingClient(
        statusCode: 200,
        responseBody: {
          'verified': true,
          'reason': 'ok',
          'score': 1.0,
          'decision_status': 'PASS',
          'reason_codes': <String>[],
          'user_message_key': 'decision.pass',
          'retry_allowed': false,
          'retry_reason': 'none',
          'retry_policy': 'NO_RETRY',
          'correlation_id': correlationId,
          'risk_signals': <String, dynamic>{},
        },
      );

      final service = ZkpService(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      final result = await service.enroll(
        idHash: 'a' * 64,
        encryptedPii: 'ciphertext_payload',
        publicKey: BigInt.from(5),
        correlationId: correlationId,
      );

      expect(client.lastHeaders?['X-Correlation-ID'], correlationId);
      expect(client.lastJsonBody?['correlation_id'], correlationId);
      expect(result.decision.correlationId, correlationId);
      expect(result.decision.status, DecisionStatus.pass);
    });

    test('returns retryable review decision on network failure', () async {
      const correlationId = 'cid-network-fallback-001';
      final service = ZkpService(
        baseUrl: 'http://localhost:8000',
        httpClient: _ThrowingClient(),
      );

      final result = await service.verify(
        idHash: 'b' * 64,
        encryptedPii: 'ciphertext_payload',
        publicKey: BigInt.from(7),
        proof: SchnorrProof(
          commitment: BigInt.one,
          challenge: BigInt.one,
          response: BigInt.one,
          sessionNonce: 'nonce-network-fallback',
        ),
        correlationId: correlationId,
      );

      expect(result.ok, isFalse);
      expect(result.statusCode, 0);
      expect(result.decision.status, DecisionStatus.review);
      expect(result.decision.retryAllowed, isTrue);
      expect(result.decision.retryPolicy, RetryPolicy.immediate);
      expect(
        result.decision.reasonCodes,
        contains(ReasonCodes.networkInterrupted),
      );
      expect(result.payload['correlation_id'], correlationId);
    });
  });
}
