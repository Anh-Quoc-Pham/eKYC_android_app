import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../models/decision_models.dart';
import '../services/ekyc_session.dart';

enum ResultUiState { success, reviewRetryable, reject, cooldown, manualReview }

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = EkycSession.instance;
    final decision = session.decisionOutcome;
    final uiState = _resolveUiState(session, decision);
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Xác minh tài khoản')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_backgroundTone(uiState), AppColors.canvas],
          ),
        ),
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(pagePadding),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Bước 4/4',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(height: compact ? 10 : 12),
              _ResultCard(
                icon: _iconForState(uiState),
                iconColor: _iconColor(uiState),
                title: _titleForState(uiState),
                body: _bodyForState(uiState),
              ),
              SizedBox(height: compact ? 10 : 12),
              ..._detailsForState(uiState, session),
              SizedBox(height: compact ? 18 : 24),
              ..._actionsForState(context, uiState, session),
            ],
          ),
        ),
      ),
    );
  }

  static ResultUiState _resolveUiState(
    EkycSession session,
    DecisionOutcome? decision,
  ) {
    if (decision == null) {
      return session.verificationSucceeded
          ? ResultUiState.success
          : ResultUiState.reviewRetryable;
    }

    if (decision.status == DecisionStatus.pass) {
      return ResultUiState.success;
    }

    if (decision.status == DecisionStatus.review) {
      if (decision.retryPolicy == RetryPolicy.manualReview ||
          !decision.retryAllowed) {
        return ResultUiState.manualReview;
      }
      if (decision.retryPolicy == RetryPolicy.waitBeforeRetry) {
        return ResultUiState.cooldown;
      }
      return ResultUiState.reviewRetryable;
    }

    if (decision.retryPolicy == RetryPolicy.waitBeforeRetry) {
      return ResultUiState.cooldown;
    }

    return ResultUiState.reject;
  }

  static Color _backgroundTone(ResultUiState uiState) {
    switch (uiState) {
      case ResultUiState.success:
        return const Color(0xFFEAF7F1);
      case ResultUiState.reviewRetryable:
        return const Color(0xFFFFF8E8);
      case ResultUiState.reject:
        return const Color(0xFFFFF2F2);
      case ResultUiState.cooldown:
        return const Color(0xFFF5F1FF);
      case ResultUiState.manualReview:
        return const Color(0xFFEFF4FF);
    }
  }

  static IconData _iconForState(ResultUiState uiState) {
    switch (uiState) {
      case ResultUiState.success:
        return Icons.verified;
      case ResultUiState.reviewRetryable:
        return Icons.rule_folder_outlined;
      case ResultUiState.reject:
        return Icons.highlight_off_rounded;
      case ResultUiState.cooldown:
        return Icons.schedule;
      case ResultUiState.manualReview:
        return Icons.pending_actions_outlined;
    }
  }

  static Color _iconColor(ResultUiState uiState) {
    switch (uiState) {
      case ResultUiState.success:
        return AppColors.success;
      case ResultUiState.reviewRetryable:
        return const Color(0xFFE38A1D);
      case ResultUiState.reject:
        return AppColors.danger;
      case ResultUiState.cooldown:
        return const Color(0xFF6D4EC5);
      case ResultUiState.manualReview:
        return const Color(0xFF3666D8);
    }
  }

  static String _titleForState(ResultUiState uiState) {
    switch (uiState) {
      case ResultUiState.success:
        return 'Xác minh thành công';
      case ResultUiState.reviewRetryable:
        return 'Cần kiểm tra thêm';
      case ResultUiState.reject:
        return 'Chưa thể xác minh';
      case ResultUiState.cooldown:
        return 'Vui lòng thử lại sau ít phút';
      case ResultUiState.manualReview:
        return 'Hồ sơ đang được kiểm tra';
    }
  }

  static String _bodyForState(ResultUiState uiState) {
    switch (uiState) {
      case ResultUiState.success:
        return 'Thông tin của bạn đã được xác minh.';
      case ResultUiState.reviewRetryable:
        return 'Hệ thống chưa thể xác minh ngay lúc này. Bạn có thể thử lại theo hướng dẫn bên dưới.';
      case ResultUiState.reject:
        return 'Chúng tôi chưa thể xác minh lần này. Bạn có thể thử lại với giấy tờ rõ hơn và ở nơi đủ sáng.';
      case ResultUiState.cooldown:
        return 'Hệ thống cần một chút thời gian nghỉ ngơi trước khi bạn thử lại. Cảm ơn sự kiên nhẫn của bạn.';
      case ResultUiState.manualReview:
        return 'Chúng tôi cần thêm thời gian để xác minh. Bạn sẽ được thông báo khi có kết quả.';
    }
  }

  static List<Widget> _detailsForState(
    ResultUiState uiState,
    EkycSession session,
  ) {
    switch (uiState) {
      case ResultUiState.success:
        return const <Widget>[];
      case ResultUiState.reviewRetryable:
        return const <Widget>[
          _InfoCard(
            title: 'Hướng dẫn khắc phục',
            lines: <String>[
              'Ảnh giấy tờ chưa đủ rõ',
              'Thử lại ở nơi đủ sáng',
              'Giữ giấy tờ nằm trọn trong khung',
            ],
          ),
        ];
      case ResultUiState.reject:
        return const <Widget>[
          _InfoCard(
            title: 'Gợi ý thực hiện lại',
            lines: <String>['Đứng ở nơi đủ sáng', 'Giữ giấy tờ rõ nét'],
          ),
        ];
      case ResultUiState.cooldown:
        return <Widget>[
          _InfoCard(
            title: 'Thời gian chờ còn lại',
            lines: <String>[_cooldownText(session)],
          ),
        ];
      case ResultUiState.manualReview:
        return const <Widget>[
          _InfoCard(
            title: 'Thời gian xử lý',
            lines: <String>['24-48 giờ làm việc'],
          ),
          SizedBox(height: 8),
          _InfoCard(
            title: 'Thông báo',
            lines: <String>[
              'Kết quả sẽ được gửi qua ứng dụng hoặc email đã đăng ký.',
            ],
          ),
        ];
    }
  }

  static String _cooldownText(EkycSession session) {
    final payload = session.verificationPayload;
    final seconds = payload['retry_after_seconds'];
    final minutes = payload['retry_after_minutes'];

    if (seconds is int && seconds > 0) {
      final roundedMinutes = (seconds / 60).ceil();
      return '$roundedMinutes phút';
    }
    if (minutes is int && minutes > 0) {
      return '$minutes phút';
    }
    return 'Khoảng vài phút';
  }

  static List<Widget> _actionsForState(
    BuildContext context,
    ResultUiState uiState,
    EkycSession session,
  ) {
    switch (uiState) {
      case ResultUiState.success:
        return <Widget>[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                session.clearAll();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
              },
              child: const Text('Tiếp tục'),
            ),
          ),
        ];
      case ResultUiState.reviewRetryable:
        return <Widget>[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacementNamed(AppRoutes.ocr);
              },
              child: const Text('Thử lại ảnh giấy tờ'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                session.clearAll();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
              },
              child: const Text('Quay lại sau'),
            ),
          ),
          const SizedBox(height: 10),
          _SupportRow(
            onTap: () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng liên hệ bộ phận hỗ trợ.'),
                  ),
                );
            },
          ),
        ];
      case ResultUiState.reject:
        return <Widget>[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                session.clearAll();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.ocr, (route) => false);
              },
              child: const Text('Thử lại từ đầu'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng liên hệ bộ phận hỗ trợ.'),
                    ),
                  );
              },
              child: const Text('Liên hệ hỗ trợ'),
            ),
          ),
        ];
      case ResultUiState.cooldown:
        return <Widget>[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                session.clearAll();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
              },
              child: const Text('Quay lại trang chính'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng liên hệ bộ phận hỗ trợ.'),
                    ),
                  );
              },
              child: const Text('Liên hệ trợ giúp'),
            ),
          ),
        ];
      case ResultUiState.manualReview:
        return <Widget>[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                session.clearAll();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
              },
              child: const Text('Đã hiểu'),
            ),
          ),
        ];
    }
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 44),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Text('Bạn gặp khó khăn khi xác minh?')),
        TextButton(onPressed: onTap, child: const Text('Liên hệ hỗ trợ')),
      ],
    );
  }
}
