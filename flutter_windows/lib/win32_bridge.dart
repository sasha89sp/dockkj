import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// ============================================================================
// Pure Dart 32-bit RGBA -> PNG encoder (uses dart:io ZLibCodec, <1ms per icon)
// ============================================================================

final List<int> _crc32Table = () {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[n] = c & 0xFFFFFFFF;
  }
  return table;
}();

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crc32Table[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void _writeBe32(BytesBuilder out, int value) {
  out.add([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}

void _writePngChunk(BytesBuilder out, String type, List<int> data) {
  _writeBe32(out, data.length);
  final typeBytes = type.codeUnits;
  final crcInput = BytesBuilder(copy: false)
    ..add(typeBytes)
    ..add(data);
  out.add(typeBytes);
  out.add(data);
  _writeBe32(out, _crc32(crcInput.toBytes()));
}

Uint8List encodeRgbaToPng(Uint8List rgba, int width, int height) {
  final out = BytesBuilder(copy: false);
  out.add(const [137, 80, 78, 71, 13, 10, 26, 10]);

  final ihdr = BytesBuilder(copy: false);
  _writeBe32(ihdr, width);
  _writeBe32(ihdr, height);
  ihdr.add(const [8, 6, 0, 0, 0]); // 8-bit RGBA
  _writePngChunk(out, 'IHDR', ihdr.toBytes());

  final rowBytes = width * 4;
  final raw = Uint8List(height * (rowBytes + 1));
  for (var y = 0; y < height; y++) {
    final dstRow = y * (rowBytes + 1);
    raw[dstRow] = 0; // Filter type: None
    final srcRow = y * rowBytes;
    raw.setRange(dstRow + 1, dstRow + 1 + rowBytes, rgba, srcRow);
  }

  final compressed = ZLibCodec(level: 2).encode(raw);
  _writePngChunk(out, 'IDAT', compressed);
  _writePngChunk(out, 'IEND', const []);
  return out.toBytes();
}

// ============================================================================
// Win32 Native Structs
// ============================================================================

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;
  @Uint8()
  external int batteryFlag;
  @Uint8()
  external int batteryLifePercent;
  @Uint8()
  external int systemStatusFlag;
  @Uint32()
  external int batteryLifeTime;
  @Uint32()
  external int batteryFullLifeTime;
}

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

final class _FileTime extends Struct {
  @Uint32()
  external int dwLowDateTime;
  @Uint32()
  external int dwHighDateTime;

  int get asUint64 => (dwHighDateTime << 32) | dwLowDateTime;
}

final class _ShQueryRbInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int _pad;
  @Int64()
  external int i64Size;
  @Int64()
  external int i64NumItems;
}

final class _ShFileOpStructW extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int wFunc;
  external Pointer<Utf16> pFrom;
  external Pointer<Utf16> pTo;
  @Uint16()
  external int fFlags;
  @Int32()
  external int fAnyOperationsAborted;
  @IntPtr()
  external int hNameMappings;
  external Pointer<Utf16> lpszProgressTitle;
}

final class _ShFileInfoW extends Struct {
  @IntPtr()
  external int hIcon;
  @Int32()
  external int iIcon;
  @Uint32()
  external int dwAttributes;
  @Array(260)
  external Array<Uint16> szDisplayName;
  @Array(80)
  external Array<Uint16> szTypeName;
}

final class _IconInfo extends Struct {
  @Int32()
  external int fIcon;
  @Uint32()
  external int xHotspot;
  @Uint32()
  external int yHotspot;
  @IntPtr()
  external int hbmMask;
  @IntPtr()
  external int hbmColor;
}

final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

final class _Bitmap extends Struct {
  @Int32()
  external int bmType;
  @Int32()
  external int bmWidth;
  @Int32()
  external int bmHeight;
  @Int32()
  external int bmWidthBytes;
  @Uint16()
  external int bmPlanes;
  @Uint16()
  external int bmBitsPixel;
  @IntPtr()
  external int bmBits;
}

// ============================================================================
// Data Models Returned by Win32Bridge
// ============================================================================

class Win32WindowInfo {
  final int hwnd;
  final int pid;
  final String title;
  final String exePath;
  final String processName;
  final bool isMinimized;
  final bool isVisible;

  const Win32WindowInfo({
    required this.hwnd,
    required this.pid,
    required this.title,
    required this.exePath,
    required this.processName,
    required this.isMinimized,
    required this.isVisible,
  });
}

class BatteryInfo {
  final int percent;
  final bool acOnline;
  final bool charging;
  final bool hasBattery;

  const BatteryInfo({
    required this.percent,
    required this.acOnline,
    required this.charging,
    required this.hasBattery,
  });

  @override
  bool operator ==(Object other) =>
      other is BatteryInfo &&
      percent == other.percent &&
      acOnline == other.acOnline &&
      charging == other.charging &&
      hasBattery == other.hasBattery;

  @override
  int get hashCode => Object.hash(percent, acOnline, charging, hasBattery);
}

class SysStatsInfo {
  final int cpuPercent;
  final int ramPercent;
  final double usedGb;
  final double totalGb;

  const SysStatsInfo({
    required this.cpuPercent,
    required this.ramPercent,
    required this.usedGb,
    required this.totalGb,
  });

  @override
  bool operator ==(Object other) =>
      other is SysStatsInfo &&
      cpuPercent == other.cpuPercent &&
      ramPercent == other.ramPercent;

  @override
  int get hashCode => Object.hash(cpuPercent, ramPercent);
}

class RecycleBinInfo {
  final int itemCount;
  final int sizeBytes;

  const RecycleBinInfo({required this.itemCount, required this.sizeBytes});

  @override
  bool operator ==(Object other) =>
      other is RecycleBinInfo && itemCount == other.itemCount;

  @override
  int get hashCode => itemCount.hashCode;
}

class VirtualScreenRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const VirtualScreenRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class FolderEntryInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final String? iconPngPath;

  const FolderEntryInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.iconPngPath,
  });
}

// ============================================================================
// Native Win32 Function Typedefs
// ============================================================================

typedef _EnumWindowsProcNative = Int32 Function(IntPtr hwnd, IntPtr lParam);

typedef _EnumWindowsNative = Int32 Function(
    Pointer<NativeFunction<_EnumWindowsProcNative>> lpEnumFunc, IntPtr lParam);
typedef _EnumWindowsDart = int Function(
    Pointer<NativeFunction<_EnumWindowsProcNative>> lpEnumFunc, int lParam);

typedef _IsWindowVisibleNative = Int32 Function(IntPtr hwnd);
typedef _IsWindowVisibleDart = int Function(int hwnd);

typedef _IsIconicNative = Int32 Function(IntPtr hwnd);
typedef _IsIconicDart = int Function(int hwnd);

typedef _IsWindowNative = Int32 Function(IntPtr hwnd);
typedef _IsWindowDart = int Function(int hwnd);

typedef _GetWindowTextLengthWNative = Int32 Function(IntPtr hwnd);
typedef _GetWindowTextLengthWDart = int Function(int hwnd);

typedef _GetWindowTextWNative = Int32 Function(
    IntPtr hwnd, Pointer<Utf16> lpString, Int32 nMaxCount);
typedef _GetWindowTextWDart = int Function(
    int hwnd, Pointer<Utf16> lpString, int nMaxCount);

typedef _GetClassNameWNative = Int32 Function(
    IntPtr hwnd, Pointer<Utf16> lpClassName, Int32 nMaxCount);
typedef _GetClassNameWDart = int Function(
    int hwnd, Pointer<Utf16> lpClassName, int nMaxCount);

typedef _GetWindowLongPtrWNative = IntPtr Function(IntPtr hwnd, Int32 nIndex);
typedef _GetWindowLongPtrWDart = int Function(int hwnd, int nIndex);

typedef _GetWindowThreadProcessIdNative = Uint32 Function(
    IntPtr hwnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(
    int hwnd, Pointer<Uint32> lpdwProcessId);

typedef _ShowWindowNative = Int32 Function(IntPtr hwnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hwnd, int nCmdShow);

typedef _SetForegroundWindowNative = Int32 Function(IntPtr hwnd);
typedef _SetForegroundWindowDart = int Function(int hwnd);

typedef _PostMessageWNative = Int32 Function(
    IntPtr hwnd, Uint32 msg, IntPtr wParam, IntPtr lParam);
typedef _PostMessageWDart = int Function(
    int hwnd, int msg, int wParam, int lParam);

typedef _SetWindowPosNative = Int32 Function(
    IntPtr hwnd,
    IntPtr hWndInsertAfter,
    Int32 x,
    Int32 y,
    Int32 cx,
    Int32 cy,
    Uint32 uFlags);
typedef _SetWindowPosDart = int Function(
    int hwnd, int hWndInsertAfter, int x, int y, int cx, int cy, int uFlags);

typedef _GetWindowRectNative = Int32 Function(IntPtr hwnd, Pointer<_Rect> lpRect);
typedef _GetWindowRectDart = int Function(int hwnd, Pointer<_Rect> lpRect);

typedef _GetCursorPosNative = Int32 Function(Pointer<_Point> lpPoint);
typedef _GetCursorPosDart = int Function(Pointer<_Point> lpPoint);

typedef _GetSystemMetricsNative = Int32 Function(Int32 nIndex);
typedef _GetSystemMetricsDart = int Function(int nIndex);

typedef _SystemParametersInfoWNative = Int32 Function(
    Uint32 uiAction, Uint32 uiParam, Pointer<Void> pvParam, Uint32 fWinIni);
typedef _SystemParametersInfoWDart = int Function(
    int uiAction, int uiParam, Pointer<Void> pvParam, int fWinIni);

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

typedef _GetDCNative = IntPtr Function(IntPtr hwnd);
typedef _GetDCDart = int Function(int hwnd);

typedef _ReleaseDCNative = Int32 Function(IntPtr hwnd, IntPtr hdc);
typedef _ReleaseDCDart = int Function(int hwnd, int hdc);

typedef _DestroyIconNative = Int32 Function(IntPtr hIcon);
typedef _DestroyIconDart = int Function(int hIcon);

typedef _GetIconInfoNative = Int32 Function(IntPtr hIcon, Pointer<_IconInfo> info);
typedef _GetIconInfoDart = int Function(int hIcon, Pointer<_IconInfo> info);

typedef _PrivateExtractIconsWNative = Uint32 Function(
    Pointer<Utf16> szFileName,
    Int32 nIconIndex,
    Int32 cxIcon,
    Int32 cyIcon,
    Pointer<IntPtr> phicon,
    Pointer<Uint32> piconid,
    Uint32 nIcons,
    Uint32 flags);
typedef _PrivateExtractIconsWDart = int Function(
    Pointer<Utf16> szFileName,
    int nIconIndex,
    int cxIcon,
    int cyIcon,
    Pointer<IntPtr> phicon,
    Pointer<Uint32> piconid,
    int nIcons,
    int flags);

typedef _DwmGetWindowAttributeNative = Int32 Function(
    IntPtr hwnd, Uint32 dwAttribute, Pointer<Void> pvAttribute, Uint32 cbAttribute);
typedef _DwmGetWindowAttributeDart = int Function(
    int hwnd, int dwAttribute, Pointer<Void> pvAttribute, int cbAttribute);

typedef _OpenProcessNative = IntPtr Function(
    Uint32 dwDesiredAccess, Int32 bInheritHandle, Uint32 dwProcessId);
typedef _OpenProcessDart = int Function(
    int dwDesiredAccess, int bInheritHandle, int dwProcessId);

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

typedef _QueryFullProcessImageNameWNative = Int32 Function(
    IntPtr hProcess, Uint32 dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize);
typedef _QueryFullProcessImageNameWDart = int Function(
    int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize);

typedef _GetCurrentProcessIdNative = Uint32 Function();
typedef _GetCurrentProcessIdDart = int Function();

typedef _GetSystemPowerStatusNative = Int32 Function(
    Pointer<_SystemPowerStatus> lpSystemPowerStatus);
typedef _GetSystemPowerStatusDart = int Function(
    Pointer<_SystemPowerStatus> lpSystemPowerStatus);

typedef _GlobalMemoryStatusExNative = Int32 Function(
    Pointer<_MemoryStatusEx> lpBuffer);
typedef _GlobalMemoryStatusExDart = int Function(
    Pointer<_MemoryStatusEx> lpBuffer);

typedef _GetSystemTimesNative = Int32 Function(
    Pointer<_FileTime> lpIdleTime,
    Pointer<_FileTime> lpKernelTime,
    Pointer<_FileTime> lpUserTime);
typedef _GetSystemTimesDart = int Function(
    Pointer<_FileTime> lpIdleTime,
    Pointer<_FileTime> lpKernelTime,
    Pointer<_FileTime> lpUserTime);

typedef _ShellExecuteWNative = IntPtr Function(
    IntPtr hwnd,
    Pointer<Utf16> lpOperation,
    Pointer<Utf16> lpFile,
    Pointer<Utf16> lpParameters,
    Pointer<Utf16> lpDirectory,
    Int32 nShowCmd);
typedef _ShellExecuteWDart = int Function(
    int hwnd,
    Pointer<Utf16> lpOperation,
    Pointer<Utf16> lpFile,
    Pointer<Utf16> lpParameters,
    Pointer<Utf16> lpDirectory,
    int nShowCmd);

typedef _ShQueryRecycleBinWNative = Int32 Function(
    Pointer<Utf16> pszRootPath, Pointer<_ShQueryRbInfo> pSHQueryRBInfo);
typedef _ShQueryRecycleBinWDart = int Function(
    Pointer<Utf16> pszRootPath, Pointer<_ShQueryRbInfo> pSHQueryRBInfo);

typedef _ShEmptyRecycleBinWNative = Int32 Function(
    IntPtr hwnd, Pointer<Utf16> pszRootPath, Uint32 dwFlags);
typedef _ShEmptyRecycleBinWDart = int Function(
    int hwnd, Pointer<Utf16> pszRootPath, int dwFlags);

typedef _ShFileOperationWNative = Int32 Function(
    Pointer<_ShFileOpStructW> lpFileOp);
typedef _ShFileOperationWDart = int Function(
    Pointer<_ShFileOpStructW> lpFileOp);

typedef _ShGetFileInfoWNative = IntPtr Function(
    Pointer<Utf16> pszPath,
    Uint32 dwFileAttributes,
    Pointer<_ShFileInfoW> psfi,
    Uint32 cbFileInfo,
    Uint32 uFlags);
typedef _ShGetFileInfoWDart = int Function(
    Pointer<Utf16> pszPath,
    int dwFileAttributes,
    Pointer<_ShFileInfoW> psfi,
    int cbFileInfo,
    int uFlags);

typedef _DeleteObjectNative = Int32 Function(IntPtr ho);
typedef _DeleteObjectDart = int Function(int ho);

typedef _GetObjectWNative = Int32 Function(
    IntPtr h, Int32 c, Pointer<Void> pv);
typedef _GetObjectWDart = int Function(int h, int c, Pointer<Void> pv);

typedef _GetDIBitsNative = Int32 Function(
    IntPtr hdc,
    IntPtr hbm,
    Uint32 start,
    Uint32 cLines,
    Pointer<Void> lpvBits,
    Pointer<_BitmapInfoHeader> lpbmi,
    Uint32 usage);
typedef _GetDIBitsDart = int Function(
    int hdc,
    int hbm,
    int start,
    int cLines,
    Pointer<Void> lpvBits,
    Pointer<_BitmapInfoHeader> lpbmi,
    int usage);

// ============================================================================
// Ultra-Fast Win32Bridge Implementation (<0.2ms per poll, HD 128px icons)
// ============================================================================

class Win32Bridge {
  Win32Bridge._();

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
  static final DynamicLibrary _gdi32 = DynamicLibrary.open('gdi32.dll');
  static final DynamicLibrary _dwmapi = DynamicLibrary.open('dwmapi.dll');

  static final _enumWindows =
      _user32.lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');
  static final _isWindowVisible =
      _user32.lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>('IsWindowVisible');
  static final _isIconic =
      _user32.lookupFunction<_IsIconicNative, _IsIconicDart>('IsIconic');
  static final _isWindow =
      _user32.lookupFunction<_IsWindowNative, _IsWindowDart>('IsWindow');
  static final _getWindowTextLengthW = _user32
      .lookupFunction<_GetWindowTextLengthWNative, _GetWindowTextLengthWDart>(
          'GetWindowTextLengthW');
  static final _getWindowTextW =
      _user32.lookupFunction<_GetWindowTextWNative, _GetWindowTextWDart>('GetWindowTextW');
  static final _getClassNameW =
      _user32.lookupFunction<_GetClassNameWNative, _GetClassNameWDart>('GetClassNameW');
  static final _getWindowLongPtrW = _user32
      .lookupFunction<_GetWindowLongPtrWNative, _GetWindowLongPtrWDart>(
          'GetWindowLongPtrW');
  static final _getWindowThreadProcessId = _user32.lookupFunction<
      _GetWindowThreadProcessIdNative,
      _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
  static final _showWindow =
      _user32.lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');
  static final _setForegroundWindow = _user32
      .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
          'SetForegroundWindow');
  static final _postMessageW =
      _user32.lookupFunction<_PostMessageWNative, _PostMessageWDart>('PostMessageW');
  static final _setWindowPos =
      _user32.lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');
  static final _getCursorPos =
      _user32.lookupFunction<_GetCursorPosNative, _GetCursorPosDart>('GetCursorPos');
  static final _getSystemMetrics = _user32
      .lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>('GetSystemMetrics');
  static final _systemParametersInfoW = _user32.lookupFunction<
      _SystemParametersInfoWNative,
      _SystemParametersInfoWDart>('SystemParametersInfoW');
  static final _getAsyncKeyState = _user32
      .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>('GetAsyncKeyState');
  static final _getDC = _user32.lookupFunction<_GetDCNative, _GetDCDart>('GetDC');
  static final _releaseDC =
      _user32.lookupFunction<_ReleaseDCNative, _ReleaseDCDart>('ReleaseDC');
  static final _destroyIcon =
      _user32.lookupFunction<_DestroyIconNative, _DestroyIconDart>('DestroyIcon');
  static final _getIconInfo =
      _user32.lookupFunction<_GetIconInfoNative, _GetIconInfoDart>('GetIconInfo');
  static final _privateExtractIconsW = _user32.lookupFunction<
      _PrivateExtractIconsWNative,
      _PrivateExtractIconsWDart>('PrivateExtractIconsW');

  static final _dwmGetWindowAttribute = _dwmapi.lookupFunction<
      _DwmGetWindowAttributeNative,
      _DwmGetWindowAttributeDart>('DwmGetWindowAttribute');

  static final _openProcess =
      _kernel32.lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
  static final _closeHandle =
      _kernel32.lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final _queryFullProcessImageNameW = _kernel32.lookupFunction<
      _QueryFullProcessImageNameWNative,
      _QueryFullProcessImageNameWDart>('QueryFullProcessImageNameW');
  static final _getCurrentProcessId = _kernel32
      .lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>(
          'GetCurrentProcessId');
  static final _getSystemPowerStatus = _kernel32
      .lookupFunction<_GetSystemPowerStatusNative, _GetSystemPowerStatusDart>(
          'GetSystemPowerStatus');
  static final _globalMemoryStatusEx = _kernel32
      .lookupFunction<_GlobalMemoryStatusExNative, _GlobalMemoryStatusExDart>(
          'GlobalMemoryStatusEx');
  static final _getSystemTimes =
      _kernel32.lookupFunction<_GetSystemTimesNative, _GetSystemTimesDart>('GetSystemTimes');

  static final _shellExecuteW =
      _shell32.lookupFunction<_ShellExecuteWNative, _ShellExecuteWDart>('ShellExecuteW');
  static final _shQueryRecycleBinW = _shell32
      .lookupFunction<_ShQueryRecycleBinWNative, _ShQueryRecycleBinWDart>(
          'SHQueryRecycleBinW');
  static final _shEmptyRecycleBinW = _shell32
      .lookupFunction<_ShEmptyRecycleBinWNative, _ShEmptyRecycleBinWDart>(
          'SHEmptyRecycleBinW');
  static final _shFileOperationW = _shell32
      .lookupFunction<_ShFileOperationWNative, _ShFileOperationWDart>('SHFileOperationW');
  static final _shGetFileInfoW =
      _shell32.lookupFunction<_ShGetFileInfoWNative, _ShGetFileInfoWDart>('SHGetFileInfoW');

  static final _deleteObject =
      _gdi32.lookupFunction<_DeleteObjectNative, _DeleteObjectDart>('DeleteObject');
  static final _getObjectW =
      _gdi32.lookupFunction<_GetObjectWNative, _GetObjectWDart>('GetObjectW');
  static final _getDIBits =
      _gdi32.lookupFunction<_GetDIBitsNative, _GetDIBitsDart>('GetDIBits');

  static int get currentPid => _getCurrentProcessId();

  // Cached PID -> (exePath, processName) so EnumWindows avoids OpenProcess every tick!
  static final Map<int, ({String exePath, String processName})> _pidCache = {};

  // CPU delta state
  static int _lastIdle = 0;
  static int _lastKernel = 0;
  static int _lastUser = 0;

  // Callback state for synchronous EnumWindows
  static final List<int> _enumBuffer = <int>[];
  static final Pointer<NativeFunction<_EnumWindowsProcNative>> _enumProcPtr =
      Pointer.fromFunction<_EnumWindowsProcNative>(_enumCallback, 0);

  static int _enumCallback(int hwnd, int lParam) {
    _enumBuffer.add(hwnd);
    return 1;
  }

  static const Set<String> _ignoredWindowClasses = {
    'Progman',
    'WorkerW',
    'Shell_TrayWnd',
    'Shell_SecondaryTrayWnd',
    'Windows.UI.Core.CoreWindow',
    'ApplicationFrameWindow',
    'NotifyIconOverflowWindow',
    'ForegroundStaging',
    'DummyDWMListenerWindow',
    'EdgeUiInputTopWndClass',
  };

  /// Ultra-fast (<0.2ms) native enumeration of real user windows (filtering out cloaked UWP shells).
  static List<Win32WindowInfo> enumerateWindows({Set<int> includeHiddenHwnds = const {}}) {
    final result = <Win32WindowInfo>[];
    if (!Platform.isWindows) return result;

    _enumBuffer.clear();
    _enumWindows(_enumProcPtr, 0);

    final selfPid = currentPid;
    final pidPtr = calloc<Uint32>();
    final cloakedPtr = calloc<Uint32>();
    final classBuf = calloc<Uint16>(96);
    final titleBuf = calloc<Uint16>(256);
    final exeBuf = calloc<Uint16>(512);
    final exeLenPtr = calloc<Uint32>();

    try {
      for (final hwnd in _enumBuffer) {
        final isTrackedHidden = includeHiddenHwnds.contains(hwnd);
        final visible = _isWindowVisible(hwnd) != 0;
        if (!visible && !isTrackedHidden) continue;

        // Filter out invisible cloaked Windows 10/11 UWP/virtual-desktop windows!
        if (!isTrackedHidden) {
          cloakedPtr.value = 0;
          if (_dwmGetWindowAttribute(hwnd, 14, cloakedPtr.cast(), 4) == 0 &&
              cloakedPtr.value != 0) {
            continue;
          }
        }

        _getWindowThreadProcessId(hwnd, pidPtr);
        final pid = pidPtr.value;
        if (pid == selfPid || pid == 0) continue;

        final exStyle = _getWindowLongPtrW(hwnd, -20); // GWL_EXSTYLE
        const wsExToolWindow = 0x00000080;
        const wsExAppWindow = 0x00040000;
        if (!isTrackedHidden &&
            (exStyle & wsExToolWindow) != 0 &&
            (exStyle & wsExAppWindow) == 0) {
          continue;
        }

        final titleLen = _getWindowTextLengthW(hwnd);
        if (titleLen <= 0) continue;

        _getClassNameW(hwnd, classBuf.cast<Utf16>(), 96);
        final cls = classBuf.cast<Utf16>().toDartString();
        if (_ignoredWindowClasses.contains(cls)) continue;

        _getWindowTextW(hwnd, titleBuf.cast<Utf16>(), 256);
        final title = titleBuf.cast<Utf16>().toDartString().trim();
        if (title.isEmpty) continue;

        var cached = _pidCache[pid];
        if (cached == null) {
          var exePath = '';
          var procName = '';
          final hProc = _openProcess(0x1000, 0, pid); // PROCESS_QUERY_LIMITED_INFORMATION
          if (hProc != 0) {
            exeLenPtr.value = 512;
            if (_queryFullProcessImageNameW(hProc, 0, exeBuf.cast<Utf16>(), exeLenPtr) != 0) {
              exePath = exeBuf.cast<Utf16>().toDartString();
              procName = p.basenameWithoutExtension(exePath).toLowerCase();
            }
            _closeHandle(hProc);
          }
          cached = (exePath: exePath, processName: procName);
          if (_pidCache.length > 200) _pidCache.clear();
          _pidCache[pid] = cached;
        }

        if (cached.processName == 'aerodock' ||
            cached.processName == 'textinputhost' ||
            cached.processName == 'searchhost' ||
            cached.processName == 'shellexperiencehost' ||
            cached.processName == 'applicationframehost') {
          continue;
        }

        final minimized = _isIconic(hwnd) != 0;
        result.add(
          Win32WindowInfo(
            hwnd: hwnd,
            pid: pid,
            title: title,
            exePath: cached.exePath,
            processName: cached.processName,
            isMinimized: minimized,
            isVisible: visible,
          ),
        );
      }
    } finally {
      calloc.free(pidPtr);
      calloc.free(cloakedPtr);
      calloc.free(classBuf);
      calloc.free(titleBuf);
      calloc.free(exeBuf);
      calloc.free(exeLenPtr);
    }

    return result;
  }

  static bool isWindowAlive(int hwnd) => Platform.isWindows && _isWindow(hwnd) != 0;

  static void restoreAndFocusWindow(int hwnd) {
    if (!Platform.isWindows || hwnd == 0) return;
    _showWindow(hwnd, 5); // SW_SHOW
    _showWindow(hwnd, 9); // SW_RESTORE
    _setForegroundWindow(hwnd);
  }

  static void hideWindowFromTaskbar(int hwnd) {
    if (!Platform.isWindows || hwnd == 0) return;
    _showWindow(hwnd, 0); // SW_HIDE
  }

  static void closeWindow(int hwnd) {
    if (!Platform.isWindows || hwnd == 0) return;
    _postMessageW(hwnd, 0x0010, 0, 0); // WM_CLOSE
  }

  static int findOwnWindowHandle() {
    if (!Platform.isWindows) return 0;
    _enumBuffer.clear();
    _enumWindows(_enumProcPtr, 0);
    final selfPid = currentPid;
    final pidPtr = calloc<Uint32>();
    try {
      for (final hwnd in _enumBuffer) {
        _getWindowThreadProcessId(hwnd, pidPtr);
        if (pidPtr.value == selfPid && _isWindowVisible(hwnd) != 0) {
          return hwnd;
        }
      }
    } finally {
      calloc.free(pidPtr);
    }
    return 0;
  }

  static void setWindowLayer(int hwnd, String layer) {
    if (!Platform.isWindows || hwnd == 0) return;
    const swpFlags = 0x0001 | 0x0002 | 0x0010;
    switch (layer) {
      case 'top':
        _setWindowPos(hwnd, -1, 0, 0, 0, 0, swpFlags);
        break;
      case 'bottom':
        _setWindowPos(hwnd, -2, 0, 0, 0, 0, swpFlags);
        _setWindowPos(hwnd, 1, 0, 0, 0, 0, swpFlags);
        break;
      case 'normal':
      default:
        _setWindowPos(hwnd, -2, 0, 0, 0, 0, swpFlags);
        break;
    }
  }

  /// Primary monitor desktop work area (cleanly excludes Windows Taskbar!).
  static VirtualScreenRect? getPrimaryWorkArea() {
    if (!Platform.isWindows) return null;
    final rect = calloc<_Rect>();
    try {
      // SPI_GETWORKAREA = 0x0030
      if (_systemParametersInfoW(0x0030, 0, rect.cast(), 0) != 0) {
        final w = (rect.ref.right - rect.ref.left).toDouble();
        final h = (rect.ref.bottom - rect.ref.top).toDouble();
        if (w > 200 && h > 200) {
          return VirtualScreenRect(
            left: rect.ref.left.toDouble(),
            top: rect.ref.top.toDouble(),
            width: w,
            height: h,
          );
        }
      }
      return null;
    } finally {
      calloc.free(rect);
    }
  }

  static VirtualScreenRect getVirtualScreenRect() {
    if (!Platform.isWindows) {
      return const VirtualScreenRect(left: 0, top: 0, width: 1920, height: 1080);
    }
    final x = _getSystemMetrics(76).toDouble();
    final y = _getSystemMetrics(77).toDouble();
    final w = _getSystemMetrics(78).toDouble();
    final h = _getSystemMetrics(79).toDouble();
    return VirtualScreenRect(
      left: x,
      top: y,
      width: w > 0 ? w : 1920,
      height: h > 0 ? h : 1080,
    );
  }

  static ({int x, int y}) getCursorPos() {
    if (!Platform.isWindows) return (x: 0, y: 0);
    final pt = calloc<_Point>();
    try {
      if (_getCursorPos(pt) != 0) {
        return (x: pt.ref.x, y: pt.ref.y);
      }
      return (x: 0, y: 0);
    } finally {
      calloc.free(pt);
    }
  }

  static bool isCtrlPressed() =>
      Platform.isWindows && (_getAsyncKeyState(0x11) & 0x8000) != 0;

  static bool isAltPressed() =>
      Platform.isWindows && (_getAsyncKeyState(0x12) & 0x8000) != 0;

  static bool isShiftPressed() =>
      Platform.isWindows && (_getAsyncKeyState(0x10) & 0x8000) != 0;

  static bool isCtrlAltShiftPressed() =>
      isCtrlPressed() && isAltPressed() && isShiftPressed();

  static BatteryInfo getBatteryStatus() {
    if (!Platform.isWindows) {
      return const BatteryInfo(percent: 100, acOnline: true, charging: false, hasBattery: false);
    }
    final ptr = calloc<_SystemPowerStatus>();
    try {
      if (_getSystemPowerStatus(ptr) != 0) {
        final s = ptr.ref;
        final noBattery = (s.batteryFlag & 128) != 0 || s.batteryLifePercent == 255;
        final charging = (s.batteryFlag & 8) != 0;
        final acOnline = s.acLineStatus == 1;
        return BatteryInfo(
          percent: noBattery ? 100 : s.batteryLifePercent.clamp(0, 100),
          acOnline: acOnline,
          charging: charging,
          hasBattery: !noBattery,
        );
      }
      return const BatteryInfo(percent: 100, acOnline: true, charging: false, hasBattery: false);
    } finally {
      calloc.free(ptr);
    }
  }

  static SysStatsInfo getCpuRamStats() {
    if (!Platform.isWindows) {
      return const SysStatsInfo(cpuPercent: 0, ramPercent: 0, usedGb: 0, totalGb: 0);
    }
    var cpuPct = 0;
    var ramPct = 0;
    var usedGb = 0.0;
    var totalGb = 0.0;

    final idlePtr = calloc<_FileTime>();
    final kernelPtr = calloc<_FileTime>();
    final userPtr = calloc<_FileTime>();
    final memPtr = calloc<_MemoryStatusEx>();

    try {
      if (_getSystemTimes(idlePtr, kernelPtr, userPtr) != 0) {
        final idle = idlePtr.ref.asUint64;
        final kernel = kernelPtr.ref.asUint64;
        final user = userPtr.ref.asUint64;
        if (_lastKernel != 0) {
          final idleDiff = idle - _lastIdle;
          final kernelDiff = kernel - _lastKernel;
          final userDiff = user - _lastUser;
          final total = kernelDiff + userDiff;
          if (total > 0) {
            cpuPct = (((total - idleDiff) * 100) / total).round().clamp(0, 100);
          }
        }
        _lastIdle = idle;
        _lastKernel = kernel;
        _lastUser = user;
      }

      memPtr.ref.dwLength = sizeOf<_MemoryStatusEx>();
      if (_globalMemoryStatusEx(memPtr) != 0) {
        ramPct = memPtr.ref.dwMemoryLoad.clamp(0, 100);
        const gb = 1024 * 1024 * 1024;
        totalGb = memPtr.ref.ullTotalPhys / gb;
        usedGb = (memPtr.ref.ullTotalPhys - memPtr.ref.ullAvailPhys) / gb;
      }
    } finally {
      calloc.free(idlePtr);
      calloc.free(kernelPtr);
      calloc.free(userPtr);
      calloc.free(memPtr);
    }

    return SysStatsInfo(
      cpuPercent: cpuPct,
      ramPercent: ramPct,
      usedGb: usedGb,
      totalGb: totalGb,
    );
  }

  static RecycleBinInfo queryRecycleBin() {
    if (!Platform.isWindows) {
      return const RecycleBinInfo(itemCount: 0, sizeBytes: 0);
    }
    final info = calloc<_ShQueryRbInfo>();
    try {
      info.ref.cbSize = sizeOf<_ShQueryRbInfo>();
      final hr = _shQueryRecycleBinW(nullptr, info);
      if (hr == 0) {
        return RecycleBinInfo(
          itemCount: info.ref.i64NumItems.clamp(0, 999999),
          sizeBytes: info.ref.i64Size,
        );
      }
      return const RecycleBinInfo(itemCount: 0, sizeBytes: 0);
    } finally {
      calloc.free(info);
    }
  }

  static void emptyRecycleBin({bool silent = false}) {
    if (!Platform.isWindows) return;
    _shEmptyRecycleBinW(0, nullptr, silent ? 7 : 0);
  }

  static bool sendFilesToRecycleBin(List<String> paths) {
    if (!Platform.isWindows || paths.isEmpty) return false;
    final doubleNull = '${paths.join('\x00')}\x00\x00';
    final fromPtr = doubleNull.toNativeUtf16();
    final op = calloc<_ShFileOpStructW>();
    try {
      op.ref.hwnd = 0;
      op.ref.wFunc = 3; // FO_DELETE
      op.ref.pFrom = fromPtr;
      op.ref.pTo = nullptr;
      op.ref.fFlags = 0x0040 | 0x0010 | 0x0004;
      return _shFileOperationW(op) == 0;
    } finally {
      calloc.free(fromPtr);
      calloc.free(op);
    }
  }

  static Future<int> copyFilesToFolder(List<String> sources, String destFolder) async {
    var copied = 0;
    final dest = Directory(destFolder);
    if (!await dest.exists()) return 0;

    for (final src in sources) {
      try {
        final name = p.basename(src);
        final targetPath = p.join(destFolder, name);
        if (await FileSystemEntity.isFile(src)) {
          await File(src).copy(targetPath);
          copied++;
        } else if (await FileSystemEntity.isDirectory(src)) {
          await _copyDirectoryRecursive(Directory(src), Directory(targetPath));
          copied++;
        }
      } catch (_) {}
    }
    return copied;
  }

  static Future<void> _copyDirectoryRecursive(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false, followLinks: false)) {
      final target = p.join(dst.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(target);
      } else if (entity is Directory) {
        await _copyDirectoryRecursive(entity, Directory(target));
      }
    }
  }

  static bool shellExecute({
    required String target,
    String args = '',
    String startIn = '',
    String runMode = 'normal',
  }) {
    if (!Platform.isWindows || target.trim().isEmpty) return false;
    final opPtr = 'open'.toNativeUtf16();
    final filePtr = target.trim().toNativeUtf16();
    final argsPtr = args.trim().isEmpty ? nullptr : args.trim().toNativeUtf16();
    final dirPtr = startIn.trim().isEmpty ? nullptr : startIn.trim().toNativeUtf16();

    final showCmd = switch (runMode) {
      'minimized' => 7,
      'maximized' => 3,
      _ => 1,
    };

    try {
      return _shellExecuteW(0, opPtr, filePtr, argsPtr, dirPtr, showCmd) > 32;
    } finally {
      calloc.free(opPtr);
      calloc.free(filePtr);
      if (argsPtr != nullptr) calloc.free(argsPtr);
      if (dirPtr != nullptr) calloc.free(dirPtr);
    }
  }

  /// Crisp 128x128 HD icon extraction using PrivateExtractIconsW (with SHGetFileInfoW fallback).
  /// Skips Windows UWP stub icons (calc.exe) so built-in crisp HD vector icons are used instead!
  static String? extractIconToPng(String targetPath, Directory iconsCacheDir) {
    if (!Platform.isWindows || targetPath.trim().isEmpty) return null;
    if (targetPath.startsWith('http://') || targetPath.startsWith('https://')) {
      return null;
    }
    // Skip ugly low-res UWP stub icons where our built-in Aero HD icons look far sharper
    final lowerBase = p.basename(targetPath).toLowerCase();
    if (lowerBase == 'calc.exe' || lowerBase == 'cmd.exe') {
      return null;
    }

    if (!iconsCacheDir.existsSync()) {
      iconsCacheDir.createSync(recursive: true);
    }

    final safeHash = targetPath.toLowerCase().codeUnits.fold<int>(
          2166136261,
          (h, c) => ((h ^ c) * 16777619) & 0x7FFFFFFF,
        );
    final outFile = File(p.join(iconsCacheDir.path, 'hd128_$safeHash.png'));
    if (outFile.existsSync() && outFile.lengthSync() > 120) {
      return outFile.path;
    }

    var resolved = targetPath;
    if (!resolved.contains('\\') && !resolved.contains('/')) {
      final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final sys32 = p.join(sysRoot, 'System32', resolved);
      if (File(sys32).existsSync()) {
        resolved = sys32;
      } else {
        final winDir = p.join(sysRoot, resolved);
        if (File(winDir).existsSync()) resolved = winDir;
      }
    }

    final pathPtr = resolved.toNativeUtf16();
    final hIconPtr = calloc<IntPtr>();
    final iconIdPtr = calloc<Uint32>();
    final shfi = calloc<_ShFileInfoW>();

    try {
      int hIcon = 0;

      // 1. Try crisp 128x128 HD icon directly from .exe / .dll / .ico
      final ext = p.extension(resolved).toLowerCase();
      if (ext == '.exe' || ext == '.dll' || ext == '.ico') {
        final count = _privateExtractIconsW(pathPtr, 0, 128, 128, hIconPtr, iconIdPtr, 1, 0);
        if (count > 0 && hIconPtr.value != 0) {
          hIcon = hIconPtr.value;
        }
      }

      // 2. Fallback to Shell icon for folders, .lnk shortcuts, documents
      if (hIcon == 0) {
        final res = _shGetFileInfoW(pathPtr, 0, shfi, sizeOf<_ShFileInfoW>(), 0x00000100);
        if (res != 0 && shfi.ref.hIcon != 0) {
          hIcon = shfi.ref.hIcon;
        }
      }

      if (hIcon == 0) return null;
      try {
        final pngBytes = _hIconToPng(hIcon);
        if (pngBytes == null) return null;
        outFile.writeAsBytesSync(pngBytes, flush: true);
        return outFile.path;
      } finally {
        _destroyIcon(hIcon);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(hIconPtr);
      calloc.free(iconIdPtr);
      calloc.free(shfi);
    }
  }

  static Uint8List? _hIconToPng(int hIcon) {
    final iconInfo = calloc<_IconInfo>();
    final bmpStruct = calloc<_Bitmap>();
    try {
      if (_getIconInfo(hIcon, iconInfo) == 0) return null;
      final hbmColor = iconInfo.ref.hbmColor;
      final hbmMask = iconInfo.ref.hbmMask;
      try {
        if (hbmColor == 0) return null;
        if (_getObjectW(hbmColor, sizeOf<_Bitmap>(), bmpStruct.cast()) == 0) {
          return null;
        }
        final w = bmpStruct.ref.bmWidth;
        final h = bmpStruct.ref.bmHeight.abs();
        if (w <= 0 || h <= 0 || w > 512 || h > 512) return null;

        final screenDc = _getDC(0);
        final bmi = calloc<_BitmapInfoHeader>();
        final colorBuf = calloc<Uint8>(w * h * 4);
        final maskBuf = calloc<Uint8>(w * h * 4);
        try {
          bmi.ref.biSize = sizeOf<_BitmapInfoHeader>();
          bmi.ref.biWidth = w;
          bmi.ref.biHeight = -h;
          bmi.ref.biPlanes = 1;
          bmi.ref.biBitCount = 32;
          bmi.ref.biCompression = 0;

          if (_getDIBits(screenDc, hbmColor, 0, h, colorBuf.cast(), bmi, 0) == 0) {
            return null;
          }

          final colorList = colorBuf.asTypedList(w * h * 4);
          var hasAlpha = false;
          for (var i = 3; i < colorList.length; i += 4) {
            if (colorList[i] != 0) {
              hasAlpha = true;
              break;
            }
          }

          Uint8List? maskList;
          if (!hasAlpha && hbmMask != 0) {
            if (_getDIBits(screenDc, hbmMask, 0, h, maskBuf.cast(), bmi, 0) != 0) {
              maskList = maskBuf.asTypedList(w * h * 4);
            }
          }

          final rgba = Uint8List(w * h * 4);
          for (var i = 0; i < w * h * 4; i += 4) {
            rgba[i] = colorList[i + 2];
            rgba[i + 1] = colorList[i + 1];
            rgba[i + 2] = colorList[i];
            if (hasAlpha) {
              rgba[i + 3] = colorList[i + 3];
            } else if (maskList != null) {
              rgba[i + 3] = maskList[i] == 0 ? 255 : 0;
            } else {
              rgba[i + 3] = 255;
            }
          }
          return encodeRgbaToPng(rgba, w, h);
        } finally {
          _releaseDC(0, screenDc);
          calloc.free(bmi);
          calloc.free(colorBuf);
          calloc.free(maskBuf);
        }
      } finally {
        if (hbmColor != 0) _deleteObject(hbmColor);
        if (hbmMask != 0) _deleteObject(hbmMask);
      }
    } finally {
      calloc.free(iconInfo);
      calloc.free(bmpStruct);
    }
  }

  static Future<List<FolderEntryInfo>> listDirectoryContents(
    String dirPath, {
    Directory? iconsCacheDir,
    int limit = 48,
  }) async {
    final result = <FolderEntryInfo>[];
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return result;
      final entities = await dir.list(followLinks: false).take(limit).toList();
      entities.sort((a, b) {
        final aDir = a is Directory ? 0 : 1;
        final bDir = b is Directory ? 0 : 1;
        if (aDir != bDir) return aDir.compareTo(bDir);
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.') || name.toLowerCase() == 'desktop.ini') continue;
        String? iconPng;
        if (iconsCacheDir != null) {
          iconPng = extractIconToPng(e.path, iconsCacheDir);
        }
        result.add(
          FolderEntryInfo(
            name: name,
            path: e.path,
            isDirectory: e is Directory,
            iconPngPath: iconPng,
          ),
        );
      }
    } catch (_) {}
    return result;
  }

  static File? _startupLauncherFile() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return File(p.join(
      appData,
      'Microsoft',
      'Windows',
      'Start Menu',
      'Programs',
      'Startup',
      'AeroDockPortable.vbs',
    ));
  }

  static bool isStartupEnabled() {
    final f = _startupLauncherFile();
    return f != null && f.existsSync();
  }

  static Future<bool> setStartupEnabled(bool enable) async {
    final f = _startupLauncherFile();
    if (f == null) return false;
    try {
      if (enable) {
        final exe = Platform.resolvedExecutable;
        final script = 'Set WshShell = CreateObject("WScript.Shell")\r\n'
            'WshShell.Run """$exe""", 1, False\r\n';
        await f.parent.create(recursive: true);
        await f.writeAsString(script, flush: true);
      } else if (await f.exists()) {
        await f.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
