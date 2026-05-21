import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _kLastCloneParent = 'last_clone_parent_dir';

Future<String?> lastCloneParentDir() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLastCloneParent);
}

Future<void> saveCloneParentDir(String targetPath) async {
  final parent = p.dirname(targetPath);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastCloneParent, parent);
}
