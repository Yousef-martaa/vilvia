import 'package:flutter/material.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/features/community/presentation/screens/create_post_screen.dart';
import 'package:vilvia/features/community/presentation/widgets/post_card.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, this.apiClient, this.authService});

  final CommunityApiClient? apiClient;
  final AuthService? authService;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late final CommunityApiClient _apiClient;
  late final bool _ownsClient;
  late final AuthService _authService;
  List<Post>? _posts;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _ownsClient = widget.apiClient == null;
    _apiClient =
        widget.apiClient ??
        CommunityApiClient(
          accessToken: () => _authService.currentSession?.accessToken,
        );
    _loadPosts();
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(apiClient: _apiClient),
      ),
    );
    if (created == true && mounted) await _loadPosts();
  }

  @override
  void dispose() {
    if (_ownsClient) _apiClient.close();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final posts = await _apiClient.getPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePost,
        icon: const Icon(Icons.add),
        label: const Text('New Post'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Community', style: textTheme.headlineLarge),
                            const SizedBox(height: 8),
                            Text(
                              'Stories, questions, and support from parents.',
                              style: textTheme.bodyLarge?.copyWith(
                                color: VilviaColors.gray,
                              ),
                            ),
                          ],
                        ),
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
              'Failed to load community posts.',
              style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPosts, child: const Text('Retry')),
          ],
        ),
      );
    }

    final posts = _posts ?? [];
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'No community posts yet.',
          style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) => PostCard(post: posts[index]),
    );
  }
}
