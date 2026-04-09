import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../services/ekyc_session.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = EkycSession.instance;
    final success = session.verificationSucceeded;
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Kết quả xác thực')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              success ? const Color(0xFFEAF7F1) : const Color(0xFFFFF2F2),
              AppColors.canvas,
            ],
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
                              success ? Icons.verified : Icons.error_outline,
                              size: compact ? 40 : 44,
                              color: success
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          );
                        },
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      Text(
                        success ? 'Success' : 'Failure',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: success ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        session.verificationMessage.isEmpty
                            ? 'Không có thông điệp trả về từ server.'
                            : session.verificationMessage,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 10 : 12),
                _InfoRow(
                  label: 'Trạng thái HTTP',
                  value: '${session.verificationStatusCode}',
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
                SizedBox(height: compact ? 18 : 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pushReplacementNamed(AppRoutes.face);
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('Quét mặt lại'),
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pushReplacementNamed(AppRoutes.review);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Chỉnh thông tin OCR'),
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
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
