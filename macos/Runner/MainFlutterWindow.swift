import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // iPhone SE (第2/3世代) の論理解像度に合わせてウィンドウを固定する。
  // 実機 iPhone のレイアウトをそのまま MacBook 上で再現する目的。
  private static let phoneSize = NSSize(width: 375, height: 667)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // コンテンツ領域を iPhone SE サイズに固定し、リサイズ・全画面化を禁止する。
    self.styleMask.remove(.resizable)
    self.setContentSize(MainFlutterWindow.phoneSize)
    self.contentMinSize = MainFlutterWindow.phoneSize
    self.contentMaxSize = MainFlutterWindow.phoneSize
    self.collectionBehavior.remove(.fullScreenPrimary)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
