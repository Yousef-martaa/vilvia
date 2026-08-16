import 'package:flutter/material.dart';

import 'package:vilvia/features/information/data/information_api_client.dart';
import 'package:vilvia/features/information/data/resource.dart';
import 'package:vilvia/features/information/presentation/screens/resource_details_screen.dart';
import 'package:vilvia/features/information/presentation/widgets/resource_card.dart';
import 'package:vilvia/features/information/presentation/widgets/stage_filter_chips.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

class ResourcesScreen extends StatefulWidget {
  final InformationApiClient? apiClient;

  const ResourcesScreen({super.key, this.apiClient});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  late final InformationApiClient _apiClient;
  late final bool _ownsClient;
  List<Resource>? _resources;
  bool _isLoading = true;
  String? _error;
  String? _selectedStage;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? InformationApiClient();
    _loadResources();
  }

  @override
  void dispose() {
    if (_ownsClient) _apiClient.close();
    super.dispose();
  }

  Future<void> _loadResources() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final resources = await _apiClient.getResources();
      if (!mounted) return;
      setState(() {
        _resources = resources;
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Resources', style: textTheme.headlineLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Explore helpful articles and guides for every '
                        'stage of your parenting journey.',
                        style: textTheme.bodyLarge
                            ?.copyWith(color: VilviaColors.gray),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(textTheme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load resources.',
              style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadResources,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final resources = _resources ?? [];
    if (resources.isEmpty) {
      return Center(
        child: Text(
          'No resources available.',
          style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
        ),
      );
    }

    final filtered = _selectedStage == null
        ? resources
        : resources.where((r) => r.stage == _selectedStage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: StageFilterChips(
            selectedStage: _selectedStage,
            onStageSelected: (stage) =>
                setState(() => _selectedStage = stage),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No resources available.',
                    style: textTheme.bodyLarge
                        ?.copyWith(color: VilviaColors.gray),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final resource = filtered[index];
                    return ResourceCard(
                      resource: resource,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ResourceDetailsScreen(resourceId: resource.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
