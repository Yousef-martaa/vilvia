import 'package:flutter/material.dart';

Future<bool> showReportDialog({
  required BuildContext context,
  required Future<void> Function(String reason) onSubmit,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReportDialog(onSubmit: onSubmit),
    ) ??
    false;

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.onSubmit});

  final Future<void> Function(String reason) onSubmit;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  bool get _isValid {
    final reason = _reasonController.text.trim();
    return reason.isNotEmpty && reason.length <= 500;
  }

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(_reasonChanged);
  }

  void _reasonChanged() => setState(() => _error = null);

  @override
  void dispose() {
    _reasonController
      ..removeListener(_reasonChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_reasonController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Could not submit report. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isSubmitting,
    child: AlertDialog(
      title: const Text('Report content'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Briefly tell us why this content should be reviewed.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            enabled: !_isSubmitting,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isValid && !_isSubmitting ? _submit : null,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    ),
  );
}
