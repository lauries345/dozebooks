part of refactored_app;

class _Book {
  final String name;
  final Uri uri; // works for file:// & content://
  final Duration duration;
  final List<Duration> marks;
  const _Book({
    required this.name,
    required this.uri,
    required this.duration,
    required this.marks,
  });
}
