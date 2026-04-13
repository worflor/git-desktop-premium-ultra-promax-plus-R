import 'package:file_picker/file_picker.dart' as fp;

/// Shared native directory picker. Returns the picked path or null if the
/// user cancels. Kept behind a thin wrapper so onboarding and the sidebar
/// rail share one call site for the OS dialog.
Future<String?> pickDirectory(String title) {
  return fp.FilePicker.platform.getDirectoryPath(dialogTitle: title);
}
