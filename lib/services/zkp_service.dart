import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/decision_models.dart';

class ZkpKeyPair {
  const ZkpKeyPair({required this.privateKey, required this.publicKey});

  final BigInt privateKey;
  final BigInt publicKey;

  Map<String, String> toStorageMap() {
    return {
      'private_key': privateKey.toString(),
      'public_key': publicKey.toString(),
    };
  }
}

class SchnorrProof {
  const SchnorrProof({
    required this.commitment,
    required this.challenge,
    required this.response,
    required this.sessionNonce,
  });

  final BigInt commitment;
  final BigInt challenge;
  final BigInt response;
  final String sessionNonce;

  Map<String, dynamic> toJson() {
    return {
      'commitment': commitment.toString(),
      'challenge': challenge.toString(),
      'response': response.toString(),
      'session_nonce': sessionNonce,
    };
  }
}

class ZkpBackendResult {
  const ZkpBackendResult({
    required this.ok,
    required this.statusCode,
    required this.message,
    required this.payload,
    required this.decision,
  });

  final bool ok;
  final int statusCode;
  final String message;
  final Map<String, dynamic> payload;
  final DecisionOutcome decision;
}

class ZkpService {
  ZkpService({
    required this.baseUrl,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    String? apiKey,
    String? bearerToken,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _httpClient = httpClient ?? http.Client(),
       _apiKey = apiKey ?? AppConfig.apiClientApiKey,
       _bearerToken = bearerToken ?? AppConfig.apiClientBearerToken;

  static final BigInt _p = BigInt.parse(_pHex, radix: 16);
  static final BigInt _q = (_p - BigInt.one) >> 1;
  static final BigInt _g = BigInt.from(4);

  static const String _privateKeyStorageKey = 'ekyc.zkp.private_key';
  static const String _publicKeyStorageKey = 'ekyc.zkp.public_key';
  static const String _piiKeyVersionStorageKey = 'ekyc.pii_key.active_version';
  static const String _piiKeyStoragePrefix = 'ekyc.pii_key.v';
  static const int _maxRetainedPiiKeys = 5;

  final String baseUrl;
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  final String? _apiKey;
  final String? _bearerToken;
  final Random _secureRandom = Random.secure();
  final AesGcm _aesGcm = AesGcm.with256bits();

  String createClientCorrelationId() => _generateCorrelationId();

  String buildIntegrityRequestHash({
    required String idHash,
    required String correlationId,
    required int attemptCount,
  }) {
    final payload =
        'ekyc_integrity_v1|${_normalizeIdHash(idHash)}|$attemptCount|$correlationId';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<ZkpKeyPair> ensureKeyPair() async {
    final privateRaw = await _secureStorage.read(key: _privateKeyStorageKey);
    final publicRaw = await _secureStorage.read(key: _publicKeyStorageKey);

    if (privateRaw != null && publicRaw != null) {
      return ZkpKeyPair(
        privateKey: BigInt.parse(privateRaw),
        publicKey: BigInt.parse(publicRaw),
      );
    }

    final keyPair = generateKeyPair();
    await _secureStorage.write(
      key: _privateKeyStorageKey,
      value: keyPair.privateKey.toString(),
    );
    await _secureStorage.write(
      key: _publicKeyStorageKey,
      value: keyPair.publicKey.toString(),
    );
    return keyPair;
  }

  ZkpKeyPair generateKeyPair() {
    final privateKey = _randomScalar();
    final publicKey = _g.modPow(privateKey, _p);
    return ZkpKeyPair(privateKey: privateKey, publicKey: publicKey);
  }

  SchnorrProof createProof({
    required String idHash,
    required BigInt privateKey,
    String? sessionNonce,
  }) {
    final normalizedIdHash = _normalizeIdHash(idHash);
    final nonce = sessionNonce ?? _generateSessionNonce();
    final randomNonce = _randomScalar();

    final commitment = _g.modPow(randomNonce, _p);
    final challenge = _hashToScalar(
      '$normalizedIdHash|$nonce|${commitment.toString()}',
    );
    final response = (randomNonce + (challenge * privateKey)) % _q;

    return SchnorrProof(
      commitment: commitment,
      challenge: challenge,
      response: response,
      sessionNonce: nonce,
    );
  }

  Future<String> encryptPii({
    required Map<String, dynamic> pii,
    required String idHash,
    bool rotateKey = true,
  }) async {
    final normalizedIdHash = _normalizeIdHash(idHash);
    final keyMaterial = await _resolvePiiKey(rotateKey: rotateKey);

    final plainBytes = Uint8List.fromList(utf8.encode(jsonEncode(pii)));
    final nonceBytes = _randomBytes(12);

    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: keyMaterial.secretKey,
      nonce: nonceBytes,
      aad: Uint8List.fromList(utf8.encode(normalizedIdHash)),
    );

    return jsonEncode({
      'alg': 'AES-256-GCM',
      'key_version': keyMaterial.version,
      'iv': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'tag': base64Encode(secretBox.mac.bytes),
      'aad_hash': normalizedIdHash,
    });
  }

  Future<ZkpBackendResult> enroll({
    required String idHash,
    required String encryptedPii,
    required BigInt publicKey,
    VerificationRiskContext? riskContext,
    String? correlationId,
  }) {
    return _postJson(
      endpoint: '/enroll',
      body: {
        'id_hash': _normalizeIdHash(idHash),
        'encrypted_pii': encryptedPii,
        'public_key': publicKey.toString(),
        if (riskContext != null) 'risk_context': riskContext.toJson(),
      },
      correlationId: correlationId,
    );
  }

  Future<ZkpBackendResult> verify({
    required String idHash,
    required String encryptedPii,
    required BigInt publicKey,
    required SchnorrProof proof,
    VerificationRiskContext? riskContext,
    String? correlationId,
  }) {
    return _postJson(
      endpoint: '/verify',
      body: {
        'id_hash': _normalizeIdHash(idHash),
        'encrypted_pii': encryptedPii,
        'public_key': publicKey.toString(),
        'proof': proof.toJson(),
        if (riskContext != null) 'risk_context': riskContext.toJson(),
      },
      correlationId: correlationId,
    );
  }

  Future<ZkpBackendResult> submitPhase3({
    required String idHash,
    required Map<String, dynamic> pii,
    VerificationRiskContext? riskContext,
    String? correlationId,
    bool enrollIfNeeded = true,
    bool rotatePiiKey = true,
  }) async {
    final requestCorrelationId = correlationId ?? _generateCorrelationId();
    final keyPair = await ensureKeyPair();
    final encryptedPii = await encryptPii(
      pii: pii,
      idHash: idHash,
      rotateKey: rotatePiiKey,
    );

    if (enrollIfNeeded) {
      final enrollResult = await enroll(
        idHash: idHash,
        encryptedPii: encryptedPii,
        publicKey: keyPair.publicKey,
        riskContext: riskContext,
        correlationId: requestCorrelationId,
      );

      if (!enrollResult.ok) {
        return enrollResult;
      }
    }

    final proof = createProof(idHash: idHash, privateKey: keyPair.privateKey);

    return verify(
      idHash: idHash,
      encryptedPii: encryptedPii,
      publicKey: keyPair.publicKey,
      proof: proof,
      riskContext: riskContext,
      correlationId: requestCorrelationId,
    );
  }

  Future<ZkpBackendResult> _postJson({
    required String endpoint,
    required Map<String, dynamic> body,
    String? correlationId,
  }) async {
    final requestCorrelationId = correlationId ?? _generateCorrelationId();
    final requestBody = <String, dynamic>{
      ...body,
      if (!body.containsKey('correlation_id'))
        'correlation_id': requestCorrelationId,
    };

    final uri = Uri.parse(
      '${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}$endpoint',
    );

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'X-Correlation-ID': requestCorrelationId,
      };

      if ((_apiKey ?? '').isNotEmpty) {
        headers['X-EKYC-API-Key'] = _apiKey!;
      }

      if ((_bearerToken ?? '').isNotEmpty) {
        headers['Authorization'] = 'Bearer ${_bearerToken!}';
      }

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      final decodedBody = _decodeJsonMap(response.body);
      final ok = response.statusCode >= 200 && response.statusCode < 300;

      final message =
          decodedBody['reason']?.toString() ??
          decodedBody['detail']?.toString() ??
          (ok ? 'ok' : 'request_failed');

      final decision = DecisionOutcome.fromBackendPayload(
        decodedBody,
        fallbackStatusCode: response.statusCode,
        fallbackMessage: message,
        fallbackCorrelationId: requestCorrelationId,
      );

      return ZkpBackendResult(
        ok: ok && decision.isPass,
        statusCode: response.statusCode,
        message: message,
        payload: decodedBody,
        decision: decision,
      );
    } catch (error) {
      final decision = DecisionOutcome.networkInterrupted(
        correlationId: requestCorrelationId,
      );
      return ZkpBackendResult(
        ok: false,
        statusCode: 0,
        message: 'network_error: $error',
        payload: {
          'decision_status': 'REVIEW',
          'reason_codes': const [ReasonCodes.networkInterrupted],
          'retry_allowed': true,
          'retry_reason': 'network_interrupted',
          'retry_policy': 'IMMEDIATE',
          'correlation_id': requestCorrelationId,
        },
        decision: decision,
      );
    }
  }

  Map<String, dynamic> _decodeJsonMap(String source) {
    if (source.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'raw': decoded};
  }

  String _generateSessionNonce() {
    return base64UrlEncode(_randomBytes(16)).replaceAll('=', '');
  }

  String _generateCorrelationId() {
    final bytes = _randomBytes(16);
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  BigInt _randomScalar() {
    while (true) {
      final bytes = _randomBytes(64);
      final candidate = _bytesToBigInt(bytes) % _q;
      if (candidate > BigInt.one) {
        return candidate;
      }
    }
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _secureRandom.nextInt(256)),
    );
  }

  BigInt _hashToScalar(String payload) {
    final digest = sha256.convert(utf8.encode(payload)).bytes;
    final scalar =
        _bytesToBigInt(Uint8List.fromList(digest)) % (_q - BigInt.one);
    return scalar + BigInt.one;
  }

  Future<_PiiKeyMaterial> _resolvePiiKey({required bool rotateKey}) async {
    if (rotateKey) {
      return _rotatePiiKey();
    }

    final activeVersionRaw = await _secureStorage.read(
      key: _piiKeyVersionStorageKey,
    );
    final activeVersion = int.tryParse(activeVersionRaw ?? '');
    if (activeVersion == null || activeVersion <= 0) {
      return _rotatePiiKey();
    }

    final encodedKey = await _secureStorage.read(
      key: '$_piiKeyStoragePrefix$activeVersion',
    );
    if (encodedKey == null || encodedKey.isEmpty) {
      return _rotatePiiKey();
    }

    final keyBytes = base64Decode(encodedKey);
    return _PiiKeyMaterial(
      version: activeVersion,
      secretKey: SecretKey(keyBytes),
    );
  }

  Future<_PiiKeyMaterial> _rotatePiiKey() async {
    final currentVersionRaw = await _secureStorage.read(
      key: _piiKeyVersionStorageKey,
    );
    final currentVersion = int.tryParse(currentVersionRaw ?? '0') ?? 0;
    final nextVersion = currentVersion + 1;

    final secretKey = await _aesGcm.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final encodedKey = base64Encode(keyBytes);

    await _secureStorage.write(
      key: '$_piiKeyStoragePrefix$nextVersion',
      value: encodedKey,
    );
    await _secureStorage.write(
      key: _piiKeyVersionStorageKey,
      value: nextVersion.toString(),
    );

    await _pruneOldPiiKeys(activeVersion: nextVersion);

    return _PiiKeyMaterial(
      version: nextVersion,
      secretKey: SecretKey(keyBytes),
    );
  }

  Future<void> _pruneOldPiiKeys({required int activeVersion}) async {
    final allItems = await _secureStorage.readAll();

    final versions = <int>[];
    for (final key in allItems.keys) {
      if (!key.startsWith(_piiKeyStoragePrefix)) {
        continue;
      }

      final suffix = key.substring(_piiKeyStoragePrefix.length);
      final version = int.tryParse(suffix);
      if (version != null && version > 0 && version != activeVersion) {
        versions.add(version);
      }
    }

    versions.sort();
    final deletableCount = versions.length - (_maxRetainedPiiKeys - 1);
    if (deletableCount <= 0) {
      return;
    }

    for (var i = 0; i < deletableCount; i++) {
      final version = versions[i];
      await _secureStorage.delete(key: '$_piiKeyStoragePrefix$version');
    }
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  String _normalizeIdHash(String value) {
    final normalized = value.trim().toLowerCase();
    final regex = RegExp(r'^[0-9a-f]{64}$');
    if (!regex.hasMatch(normalized)) {
      throw FormatException('idHash phải là SHA-256 hex 64 ký tự.');
    }
    return normalized;
  }

  void dispose() {
    _httpClient.close();
  }
}

const String _pHex =
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E08'
    '8A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD'
    '3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E'
    '7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899F'
    'A5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05'
    '98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C'
    '62F356208552BB9ED529077096966D670C354E4ABC9804F174'
    '6C08CA18217C32905E462E36CE3BE39E772C180E86039B2783'
    'A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497C'
    'EA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF';

class _PiiKeyMaterial {
  const _PiiKeyMaterial({required this.version, required this.secretKey});

  final int version;
  final SecretKey secretKey;
}
