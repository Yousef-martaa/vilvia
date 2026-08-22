import 'package:flutter/material.dart';

import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, required this.apiClient});

  final CommunityApiClient apiClient;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const _categories = <String, String>{
    'experiences': 'Experiences',
    'qa': 'Questions & advice',
    'child_development': 'Child development',
    'family_life': 'Family life',
    'local_recommendations': 'Local recommendations',
    'meetups': 'Meetups',
  };

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _category = _categories.keys.first;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || title.length > 200) {
      setState(() => _error = 'Please enter a title (1-200 characters).');
      return;
    }
    if (body.isEmpty || body.length > 5000) {
      setState(() => _error = 'Please enter a post (1-5000 characters).');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.apiClient.createPost(
        title: title,
        body: body,
        category: _category,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New Post')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  maxLength: 200,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _category = value);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  decoration: const InputDecoration(labelText: 'Post'),
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 5000,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: VilviaColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Publish Post'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
