import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  test('interactive rebase todo preserves actions and appends newline', () {
    final todo = interactiveRebaseTodoForTesting(const [
      RebaseTodoEntry(
        action: 'pick',
        commitHash: 'abc123',
        subject: 'first commit',
      ),
      RebaseTodoEntry(
        action: 'drop',
        commitHash: 'def456',
        subject: 'remove me',
      ),
    ]);

    expect(todo, 'pick abc123 first commit\ndrop def456 remove me\n');
  });

  test('windows sequence editor batch copies prepared todo to git todo arg',
      () {
    final script = windowsSequenceEditorScriptForTesting(
      r'C:\Users\me\Temp 100% ^ caret\todo.txt',
    );

    expect(
      script,
      contains(
        r'copy /y "C:\Users\me\Temp 100%% ^^ caret\todo.txt" "%~1" >NUL',
      ),
    );
    expect(script, contains('exit /b %ERRORLEVEL%'));
  });

  test('windows sequence editor command invokes cmd with autorun disabled', () {
    final command = windowsSequenceEditorCommandForTesting(
      r'C:\Users\me\Temp 100% ^ caret\sequence-editor.cmd',
    );

    expect(
      command,
      r'cmd.exe /d /c call "C:\Users\me\Temp 100^% ^^ caret\sequence-editor.cmd"',
    );
  });

  test('unix sequence editor quotes paths for shell execution', () {
    final script =
        unixSequenceEditorScriptForTesting("/tmp/rebase isn't easy/todo");
    final command =
        unixSequenceEditorCommandForTesting("/tmp/rebase isn't easy/editor.sh");

    expect(
        script, '#!/bin/sh\ncp \'/tmp/rebase isn\'\\\'\'t easy/todo\' "\$1"\n');
    expect(command, 'sh \'/tmp/rebase isn\'\\\'\'t easy/editor.sh\'');
  });
}
