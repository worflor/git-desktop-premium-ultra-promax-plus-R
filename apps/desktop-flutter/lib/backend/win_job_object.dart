import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows Job Object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE.
/// Assigning a process to this job guarantees the entire subprocess
/// tree is killed when the handle closes — even across cmd.exe
/// wrappers and re-parented children.
///
/// No-op on non-Windows platforms.
class WinJobObject {
  WinJobObject._();

  static final _kernel32 = Platform.isWindows
      ? DynamicLibrary.open('kernel32.dll')
      : null;

  // Intentionally never closed — the handle closing IS the kill signal.
  // Windows reclaims it on process exit, which triggers KILL_ON_JOB_CLOSE.
  static int? _jobHandle;

  static final _openProcess = _kernel32?.lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)>('OpenProcess');

  static final _assignToJob = _kernel32?.lookupFunction<
      Int32 Function(IntPtr, IntPtr),
      int Function(int, int)>('AssignProcessToJobObject');

  static final _closeHandle = _kernel32?.lookupFunction<
      Int32 Function(IntPtr),
      int Function(int)>('CloseHandle');

  static void assignProcess(int pid) {
    try {
      if (_openProcess == null || _assignToJob == null || _closeHandle == null) {
        return;
      }
      _jobHandle ??= _createJob();
      if (_jobHandle == null || _jobHandle == 0) return;

      final hProcess = _openProcess!(0x0101, 0, pid);
      if (hProcess == 0) return;
      _assignToJob!(_jobHandle!, hProcess);
      _closeHandle!(hProcess);
    } catch (_) {}
  }

  static int? _createJob() {
    final create = _kernel32!.lookupFunction<
        IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)>('CreateJobObjectW');
    final handle = create(nullptr, nullptr);
    if (handle == 0) return null;

    final setInfo = _kernel32!.lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)>(
        'SetInformationJobObject');

    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION layout:
    //   BASIC (x64=64, x86=48*) + IO_COUNTERS (48) + 4×SIZE_T
    //   * x86 BASIC is 44 but padded to 48 for IO_COUNTERS alignment
    //   x64: 64+48+32 = 144, x86: 48+48+16 = 112
    // LimitFlags at offset 16 on both (after two LARGE_INTEGERs).
    // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000.
    // JobObjectExtendedLimitInformation = 9.
    final infoSize = sizeOf<IntPtr>() == 8 ? 144 : 112;
    final info = calloc<Uint8>(infoSize);
    info.elementAt(16).cast<Uint32>().value = 0x2000;
    setInfo(handle, 9, info.cast(), infoSize);
    calloc.free(info);
    return handle;
  }
}
