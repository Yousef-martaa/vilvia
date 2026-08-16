import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vilvia/features/information/data/information_api_client.dart';
import 'package:vilvia/features/information/data/resource_detail.dart';
import 'package:vilvia/features/information/presentation/resource_labels.dart';
import 'package:vilvia/theme/vilvia_colors.dart';
import 'package:vilvia/widgets/tag_chip.dart';
import 'package:vilvia/widgets/tinted_icon_badge.dart';

/// The Resource Details screen (Issue #61): fetches one resource's full
/// content from Vilvia's own API (never MedlinePlus or any other external
/// source directly -- Flutter only ever talks to the Vilvia backend) and
/// shows its title, category/stage, full body, and source attribution.
class ResourceDetailsScreen extends StatefulWidget {
  const ResourceDetailsScreen({
    super.key,
    required this.resourceId,
    this.apiClient,
    this.onLaunchUrl,
  });

  final String resourceId;
  final InformationApiClient? apiClient;

  /// Overridable for tests. Defaults to the real `url_launcher` call.
  final Future<void> Function(Uri url)? onLaunchUrl;

  @override
  State<ResourceDetailsScreen> createState() => _ResourceDetailsScreenState();
}

class _ResourceDetailsScreenState extends State<ResourceDetailsScreen> {
  late final InformationApiClient _apiClient;
  late final bool _ownsClient;
  ResourceDetail? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? InformationApiClient();
    _loadResource();
  }

  @override
  void dispose() {
    if (_ownsClient) _apiClient.close();
    super.dispose();
  }

  Future<void> _loadResource() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final detail = await _apiClient.getResource(widget.resourceId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openSource(String url) {
    final launch = widget.onLaunchUrl ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    return launch(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: VilviaColors.charcoal),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load resource.',
              style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadResource,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final detail = _detail!;
    final resource = detail.resource;
    final style = categoryStyle(resource.category);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        TintedIconBadge(icon: style.icon, color: style.color, size: 48),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TagChip(
              label: categoryLabel(resource.category),
              color: style.color,
            ),
            TagChip(
              label: stageLabel(resource.stage),
              color: VilviaColors.gray,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(resource.title, style: textTheme.headlineMedium),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VilviaColors.sageGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Source',
                style:
                    textTheme.labelSmall?.copyWith(color: VilviaColors.gray),
              ),
              const SizedBox(height: 4),
              Text(resource.sourceName, style: textTheme.titleLarge),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openSource(resource.sourceUrl),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VilviaColors.sageGreen,
                  side: const BorderSide(color: VilviaColors.sageGreen),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('View original source'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SelectableText(detail.body, style: textTheme.bodyLarge),
      ],
    );
  }
}
