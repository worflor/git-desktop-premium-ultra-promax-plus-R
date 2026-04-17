import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart'
    show extractPatchFromModelOutputForTesting;

void main() {
  group('extractPatchFromModelOutputForTesting', () {
    test('drops trailing prose after a valid patch body', () {
      const raw = '''Here is the patch:

```diff
diff --git a/lib/foo.dart b/lib/foo.dart
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,2 +1,2 @@
-oldValue
+newValue
 keep
```

This updates the file safely.
''';

      final patch = extractPatchFromModelOutputForTesting(raw);

      expect(patch, contains('diff --git a/lib/foo.dart b/lib/foo.dart'));
      expect(patch, contains('+newValue'));
      expect(patch, isNot(contains('This updates the file safely.')));
    });
  });
}
