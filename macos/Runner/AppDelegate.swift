import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    Self.preloadSoloudNativeAsset()
  }

  /// flutter_soloud 5.3.0 的 macOS 插件通过 `-undefined dynamic_lookup` 引用
  /// native asset (`flutter_soloud_plugin.framework`) 中的生命周期符号。
  /// 若用户未触发语音播放就退出应用，`applicationWillTerminate:` 调用
  /// `soloud_vst3HostUnloadAll()` 会因该动态库尚未加载而空指针崩溃（SIGSEGV 0x0）。
  /// 在启动时以 `RTLD_GLOBAL` 预加载该 framework，确保退出及生命周期回调均安全绑定。
  private static func preloadSoloudNativeAsset() {
    guard let frameworksPath = Bundle.main.privateFrameworksPath else { return }
    let dylibPath = (frameworksPath as NSString).appendingPathComponent(
      "flutter_soloud_plugin.framework/Versions/A/flutter_soloud_plugin"
    )
    if FileManager.default.fileExists(atPath: dylibPath) {
      _ = dlopen(dylibPath, RTLD_LAZY | RTLD_GLOBAL)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
