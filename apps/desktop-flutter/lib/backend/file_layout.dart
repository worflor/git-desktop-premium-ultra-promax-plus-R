/// Returns the final path component (filename) of [path], normalising
/// both forward- and back-slashes.
String pathBasename(String path) {
  final norm = path.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx < 0 ? norm : norm.substring(idx + 1);
}
