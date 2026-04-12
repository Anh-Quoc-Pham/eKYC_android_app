import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../models/decision_models.dart';
import '../services/ekyc_session.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = EkycSession.instance;
    final decision = session.decisionOutcome;
    final decisionStatus = _resolveDecisionStatus(session);
    final retryAllowed =
        decision?.retryAllowed ?? !session.verificationSucceeded;
    final retryPolicy =
        decision?.retryPolicy ??
        (retryAllowed ? RetryPolicy.immediate : RetryPolicy.noRetry);
    final canRetryFace =
        retryAllowed &&
        (retryPolicy == RetryPolicy.immediate ||
            retryPolicy == RetryPolicy.waitBeforeRetry);
    final canRetryReview =
        retryAllowed && retryPolicy == RetryPolicy.userCorrection;
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Kết quả xác thực')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_backgroundTone(decisionStatus), AppColors.canvas],
          ),
        ),
        child: SafeArea(
          child: TweenAnimationBuilder<double>(
            duration: AppMotion.slow,
            curve: AppMotion.emphasized,
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * (compact ? 14 : 20)),
                  child: child,
                ),
              );
            },
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(pagePadding),
              children: [
                AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: AppMotion.standard,
                  padding: EdgeInsets.all(compact ? 14 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        duration: AppMotion.medium,
                        curve: AppMotion.emphasized,
                        tween: Tween<double>(begin: 0.86, end: 1),
                        builder: (context, scale, _) {
                          return Transform.scale(
                            scale: scale,
                            child: Icon(
                              _statusIcon(decisionStatus),
                              size: compact ? 40 : 44,
                              color: _statusColor(decisionStatus),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      Text(
                        _headline(decisionStatus),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _statusColor(decisionStatus),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _userFacingMessage(
                          decision: decision,
                          fallbackMessage: session.verificationMessage,
                          retryPolicy: retryPolicy,
                          retryAllowed: retryAllowed,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 10 : 12),
                _InfoRow(
                  label: 'Decision',
                  value: decisionStatus.name.toUpperCase(),
                ),
                _InfoRow(
                  label: 'Trạng thái HTTP',
                  value: '${session.verificationStatusCode}',
                ),
                _InfoRow(
                  label: 'Retry Policy',
                  value: _retryPolicyLabel(retryPolicy),
                ),
                _InfoRow(
                  label: 'Liveness',
                  value: session.livenessPassed ? 'Đạt' : 'Chưa đạt',
                ),
                _InfoRow(
                  label: 'Face Match',
                  value:
                      '${(session.faceMatchScore * 100).toStringAsFixed(0)}% '
                      '(${session.faceMatchPassed ? 'Đạt' : 'Chưa đạt'})',
                ),
                if (session.cccdHash.isNotEmpty)
                  _InfoRow(
                    label: 'ID Hash',
                    value: _truncateHash(session.cccdHash),
                    monospace: true,
                  ),
                if ((decision?.correlationId ?? session.correlationId)
                    .isNotEmpty)
                  _InfoRow(
                    label: 'Correlation ID',
                    value: _truncateHash(
                      decision?.correlationId ?? session.correlationId,
                    ),
                    monospace: true,
                  ),
                SizedBox(height: compact ? 18 : 24),
                if (canRetryFace)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pushReplacementNamed(AppRoutes.face);
                      },
                      icon: const Icon(Icons.replay),
                      label: const Text('Thử lại xác minh khuôn mặt'),
                    ),
                  ),
                if (canRetryFace) SizedBox(height: compact ? 8 : 10),
                if (canRetryReview)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pushReplacementNamed(AppRoutes.review);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Sửa OCR và thử lại'),
                    ),
                  ),
                if (canRetryReview) SizedBox(height: compact ? 8 : 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      session.clearAll();
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.welcome,
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Về màn hình chào'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _truncateHash(String hash) {
    if (hash.length <= 20) {
      return hash;
    }
    return '${hash.substring(0, 10)}...${hash.substring(hash.length - 8)}';
  }

  static DecisionStatus _resolveDecisionStatus(EkycSession session) {
    final decision = session.decisionOutcome;
    if (decision != null) {
      return decision.status;
    }

    return session.verificationSucceeded
        ? DecisionStatus.pass
        : DecisionStatus.review;
  }

  static Color _backgroundTone(DecisionStatus status) {
    switch (status) {
      case DecisionStatus.pass:
        return const Color(0xFFEAF7F1);
      case DecisionStatus.review:
        return const Color(0xFFFFF8E8);
      case DecisionStatus.reject:
        return const Color(0xFFFFF2F2);
    }
  }

  static Color _statusColor(DecisionStatus status) {
    switch (status) {
      case DecisionStatus.pass:
        return AppColors.success;
      case DecisionStatus.review:
        return const Color(0xFFE38A1D);
      case DecisionStatus.reject:
        return AppColors.danger;
    }
  }

  static IconData _statusIcon(DecisionStatus status) {
    switch (status) {
      case DecisionStatus.pass:
        return Icons.verified;
      case DecisionStatus.review:
        return Icons.rule_folder_outlined;
      case DecisionStatus.reject:
        return Icons.block_outlined;
    }
  }

  static String _headline(DecisionStatus status) {
    switch (status) {
      case DecisionStatus.pass:
        return 'Đã xác thực thành công';
      case DecisionStatus.review:
        return 'Cần rà soát thêm';
      case DecisionStatus.reject:
        return 'Từ chối xác thực';
    }
  }

  static String _retryPolicyLabel(RetryPolicy retryPolicy) {
    switch (retryPolicy) {
      case RetryPolicy.immediate:
        return 'Retry ngay';
      case RetryPolicy.userCorrection:
        return 'Cần sửa thông tin';
      case RetryPolicy.waitBeforeRetry:
        return 'Đợi và thử lại';
      case RetryPolicy.manualReview:
        return 'Rà soát thủ công';
      case RetryPolicy.noRetry:
        return 'Không cho retry';
    }
  }

  static String _userFacingMessage({
    required DecisionOutcome? decision,
    required String fallbackMessage,
    required RetryPolicy retryPolicy,
    required bool retryAllowed,
  }) {
    if (decision == null) {
      return fallbackMessage.isEmpty
          ? 'Không có thông điệp trả về từ server.'
          : fallbackMessage;
    }

    switch (decision.userMessageKey) {
      case 'decision.pass':
        return 'Phiên eKYC đạt yêu cầu cho bước pilot.';
      case 'decision.review.document_quality':
        return 'Ảnh giấy tờ chưa đạt chất lượng. Vui lòng chỉnh lại góc chụp/ánh sáng và thử lại.';
      case 'decision.review.liveness_retry':
        return 'Độ tin cậy liveness chưa đủ. Vui lòng thực hiện lại thao tác khuôn mặt.';
      case 'decision.review.network_retry':
        return 'Kết nối mạng bị gián đoạn. Bạn có thể thử lại ngay.';
      case 'decision.review.device_trust_pending':
        return 'Thiết bị chưa cung cấp đủ tín hiệu integrity. Vui lòng thử lại sau.';
      case 'decision.review.internal_required':
        return 'Phiên xác minh cần chuyển bước rà soát nội bộ.';
      case 'decision.reject.retry_limit':
        return 'Bạn đã vượt quá giới hạn số lần thử trong phiên này.';
      case 'decision.reject.security_check_failed':
        return 'Phiên xác minh bị từ chối do tín hiệu an toàn không đạt yêu cầu.';
      default:
        if (retryAllowed && retryPolicy == RetryPolicy.userCorrection) {
          return 'Có thể thử lại sau khi điều chỉnh thông tin/điều kiện chụp.';
        }
        if (retryAllowed) {
          return 'Bạn có thể thử lại xác minh.';
        }
        return fallbackMessage.isEmpty
            ? 'Phiên xác minh chưa thể tự động phê duyệt.'
            : fallbackMessage;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontFamily: monospace ? 'monospace' : null),
            ),
          ),
        ],
      ),
    );
  }
}
