import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/community/data/admin_report.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({
    super.key,
    required this.apiClient,
    required this.authService,
    required this.adminUserId,
  });

  final CommunityApiClient apiClient;
  final AuthService authService;
  final String adminUserId;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<AdminReport>? _reports;
  final Set<String> _updatingIds = {};
  final Set<String> _moderatingIds = {};
  bool _isLoading = true;
  bool _accessRevoked = false;
  int _authGeneration = 0;
  int _loadGeneration = 0;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    try {
      _authSubscription = widget.authService.onAuthStateChange.listen(
        _handleAuthState,
      );
    } catch (_) {
      _accessRevoked = true;
      _isLoading = false;
      return;
    }
    _loadReports();
  }

  void _handleAuthState(AuthState state) {
    if (state.session?.user.id != widget.adminUserId) _revokeAccess();
  }

  void _revokeAccess() {
    if (_accessRevoked) return;
    _accessRevoked = true;
    _authGeneration++;
    if (mounted) {
      setState(() {
        _reports = null;
        _updatingIds.clear();
        _moderatingIds.clear();
        _isLoading = false;
        _error = null;
      });
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadReports() async {
    if (_accessRevoked) return;
    final authGeneration = _authGeneration;
    final loadGeneration = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final reports = await widget.apiClient.getAdminReports();
      if (!mounted ||
          _accessRevoked ||
          authGeneration != _authGeneration ||
          loadGeneration != _loadGeneration) {
        return;
      }
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          _accessRevoked ||
          authGeneration != _authGeneration ||
          loadGeneration != _loadGeneration) {
        return;
      }
      setState(() {
        _error = 'Failed to load reports.';
        _isLoading = false;
      });
    }
  }

  Future<void> _update(AdminReport report, ReportStatus status) async {
    if (_accessRevoked ||
        _updatingIds.contains(report.id) ||
        _moderatingIds.contains(report.id)) {
      return;
    }
    final authGeneration = _authGeneration;
    setState(() => _updatingIds.add(report.id));
    try {
      final updated = await widget.apiClient.updateAdminReportStatus(
        reportId: report.id,
        status: status,
      );
      if (!mounted || _accessRevoked || authGeneration != _authGeneration) {
        return;
      }
      setState(() {
        _reports = _reports
            ?.map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (_) {
      if (!mounted || _accessRevoked || authGeneration != _authGeneration) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update report.')));
    } finally {
      if (mounted && !_accessRevoked && authGeneration == _authGeneration) {
        setState(() => _updatingIds.remove(report.id));
      }
    }
  }

  Future<void> _updateVisibility(AdminReport report) async {
    if (_accessRevoked ||
        _updatingIds.contains(report.id) ||
        _moderatingIds.contains(report.id)) {
      return;
    }
    final authGeneration = _authGeneration;
    setState(() => _moderatingIds.add(report.id));
    try {
      final updated = await widget.apiClient.updateAdminReportTargetVisibility(
        reportId: report.id,
        isHidden: !report.targetIsHidden,
      );
      if (!mounted || _accessRevoked || authGeneration != _authGeneration) {
        return;
      }
      setState(() {
        _reports = _reports?.map((item) {
          if (item.id == updated.id) return updated;
          if (item.targetKind == updated.targetKind &&
              item.targetId == updated.targetId) {
            return item.withTargetVisibility(updated.targetIsHidden);
          }
          return item;
        }).toList();
      });
    } catch (_) {
      if (!mounted || _accessRevoked || authGeneration != _authGeneration) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update content visibility.')),
      );
    } finally {
      if (mounted && !_accessRevoked && authGeneration == _authGeneration) {
        setState(() => _moderatingIds.remove(report.id));
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_accessRevoked) return const SizedBox.shrink();
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadReports, child: const Text('Retry')),
          ],
        ),
      );
    }
    final reports = _reports ?? [];
    if (reports.isEmpty) {
      return const Center(child: Text('No pending reports.'));
    }
    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _ReportCard(
          report: reports[index],
          isUpdating: _updatingIds.contains(reports[index].id),
          isModerating: _moderatingIds.contains(reports[index].id),
          onReviewed: () => _update(reports[index], ReportStatus.reviewed),
          onDismissed: () => _update(reports[index], ReportStatus.dismissed),
          onVisibilityChanged: () => _updateVisibility(reports[index]),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.isUpdating,
    required this.isModerating,
    required this.onReviewed,
    required this.onDismissed,
    required this.onVisibilityChanged,
  });

  final AdminReport report;
  final bool isUpdating;
  final bool isModerating;
  final VoidCallback onReviewed;
  final VoidCallback onDismissed;
  final VoidCallback onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final post = report.post;
    final comment = report.comment;
    final title = switch (report.targetKind) {
      ReportTargetKind.post => post?.title ?? 'Unavailable report context',
      ReportTargetKind.comment =>
        comment == null
            ? 'Unavailable report context'
            : 'Comment on ${comment.postTitle}',
    };
    final body = switch (report.targetKind) {
      ReportTargetKind.post => post?.body ?? '',
      ReportTargetKind.comment => comment?.body ?? '',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body),
            const SizedBox(height: 12),
            Text(
              'Reason: ${report.reason}',
              style: const TextStyle(color: VilviaColors.gray),
            ),
            const SizedBox(height: 8),
            Text(report.targetIsHidden ? 'Hidden' : 'Visible'),
            Align(
              alignment: Alignment.centerRight,
              child: isModerating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    )
                  : OutlinedButton(
                      onPressed: isUpdating ? null : onVisibilityChanged,
                      child: Text(report.targetIsHidden ? 'Restore' : 'Hide'),
                    ),
            ),
            const SizedBox(height: 12),
            if (isUpdating)
              const Center(child: CircularProgressIndicator())
            else if (report.status == ReportStatus.pending)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: isModerating ? null : onDismissed,
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isModerating ? null : onReviewed,
                    child: const Text('Review'),
                  ),
                ],
              )
            else
              Text('Status: ${report.status.name}'),
          ],
        ),
      ),
    );
  }
}
