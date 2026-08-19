import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// Admin-only Event creation form (Issue #75). Reachable only from
/// [EventsScreen]'s admin-gated "New Event" button -- this screen itself
/// does no role checking of its own; the real, only enforcement is
/// backend `require_admin` on `POST /events`, which will reject a
/// non-admin caller regardless of how this screen was reached.
///
/// Creates a **draft**: `is_published` is always `false` server-side and
/// is never sent from here (there is no field for it), so a created
/// Event never appears in the public Events list. This screen makes that
/// explicit in its success message rather than implying "done" the same
/// way a normal, immediately-visible creation flow would.
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key, this.apiClient});

  final EventsApiClient? apiClient;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  late final EventsApiClient _apiClient;
  late final bool _ownsClient;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  DateTime? _startsAt;
  DateTime? _endsAt;

  bool _isSubmitting = false;
  String? _error;
  bool _createdSuccessfully = false;

  static final _dateTimeFormat = DateFormat('EEE, d MMM y - HH:mm');

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? EventsApiClient();
  }

  @override
  void dispose() {
    if (_ownsClient) _apiClient.close();
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: initial != null
          ? TimeOfDay.fromDateTime(initial)
          : TimeOfDay.fromDateTime(now),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStartsAt() async {
    final picked = await _pickDateTime(_startsAt);
    if (picked == null) return;
    setState(() => _startsAt = picked);
  }

  Future<void> _pickEndsAt() async {
    final picked = await _pickDateTime(_endsAt ?? _startsAt);
    if (picked == null) return;
    setState(() => _endsAt = picked);
  }

  void _clearEndsAt() => setState(() => _endsAt = null);

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();
    final startsAt = _startsAt;
    final endsAt = _endsAt;

    if (title.isEmpty || title.length > 200) {
      setState(() => _error = 'Please enter a title (1-200 characters).');
      return;
    }
    if (location.isEmpty || location.length > 200) {
      setState(() => _error = 'Please enter a location (1-200 characters).');
      return;
    }
    if (description.isEmpty) {
      setState(() => _error = 'Please enter a description.');
      return;
    }
    if (startsAt == null) {
      setState(() => _error = 'Please choose a start date and time.');
      return;
    }
    if (endsAt != null && !endsAt.isAfter(startsAt)) {
      setState(() => _error = 'End time must be after the start time.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _apiClient.createEvent(
        title: title,
        description: description,
        location: location,
        startsAt: startsAt,
        endsAt: endsAt,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _createdSuccessfully = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString();
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: VilviaColors.charcoal),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 8),
                  Text('New Event', style: textTheme.headlineMedium),
                  const SizedBox(height: 20),
                  if (_createdSuccessfully)
                    _buildSuccess(textTheme)
                  else
                    _buildForm(textTheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: VilviaColors.charcoal, size: 40),
        const SizedBox(height: 12),
        Text('Event created as a draft', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'This event will not appear in the public Events list yet. It '
          'still needs to be reviewed and published.',
          style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: 'Location'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          minLines: 3,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: 16),
        Text('Starts', style: textTheme.bodyMedium),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: _pickStartsAt,
          child: Text(
            _startsAt == null
                ? 'Choose start date & time'
                : _dateTimeFormat.format(_startsAt!),
          ),
        ),
        const SizedBox(height: 16),
        Text('Ends (optional)', style: textTheme.bodyMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickEndsAt,
                child: Text(
                  _endsAt == null
                      ? 'Choose end date & time'
                      : _dateTimeFormat.format(_endsAt!),
                ),
              ),
            ),
            if (_endsAt != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear end time',
                onPressed: _clearEndsAt,
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: textTheme.bodyMedium?.copyWith(color: VilviaColors.error),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VilviaColors.surface,
                    ),
                  )
                : const Text('Create Draft Event'),
          ),
        ),
      ],
    );
  }
}
