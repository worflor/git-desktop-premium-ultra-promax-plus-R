class GitResult<T> {
  final T? data;
  final String? error;

  bool get ok => error == null;

  const GitResult.ok(T this.data) : error = null;

  const GitResult.err(String this.error) : data = null;
}
