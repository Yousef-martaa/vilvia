import 'package:flutter/material.dart';

import 'package:vilvia/features/information/data/information_api_client.dart';
import 'package:vilvia/features/information/data/resource.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Failed to load resources.'),
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
      return const Center(child: Text('No resources available.'));
    }

    return ListView.builder(
      itemCount: resources.length,
      itemBuilder: (context, index) {
        final resource = resources[index];
        return ListTile(
          title: Text(resource.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(resource.summary),
              Text('${resource.category} · ${resource.stage}'),
            ],
          ),
          isThreeLine: true,
        );
      },
    );
  }
}
