// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import AppKit

extension SettingsPanesCocoa {
  /// 「智慧輸入」設定窗格：收納智慧中英混打（連續誤鍵自動切換為英數輸入）的相關設定。
  public final class SmartTyping: NSViewController {
    // MARK: Public

    override public func loadView() {
      view = body ?? .init()
      (view as? NSStackView)?.alignment = .centerX
      view.makeSimpleConstraint(.width, relation: .equal, value: windowWidth)
    }

    // MARK: Internal

    var windowWidth: CGFloat { SettingsPanesCocoa.windowWidth }
    var contentWidth: CGFloat { SettingsPanesCocoa.contentWidth }
    var innerContentWidth: CGFloat { SettingsPanesCocoa.innerContentWidth }
    var tabContainerWidth: CGFloat { SettingsPanesCocoa.tabContainerWidth }
    var contentHalfWidth: CGFloat { SettingsPanesCocoa.contentHalfWidth }

    var body: NSView? {
      NSStackView.build(.vertical, insets: .new(all: 14)) {
        NSStackView.buildSection(width: contentWidth) {
          UserDef.kAutoSwitchToAlphanumericalOnConsecutiveErrors.renderCocoa(
            fixWidth: contentWidth,
            prefUITab: .tabSmartTyping
          )
          UserDef.kConsecutiveTypingErrorsThreshold.renderCocoa(
            fixWidth: contentWidth,
            prefUITab: .tabSmartTyping
          )
          UserDef.kAutoSwitchedEnglishModeIdleTimeout.renderCocoa(
            fixWidth: contentWidth,
            prefUITab: .tabSmartTyping
          )
          UserDef.kAutoSwitchedEnglishModeExitHotkey.renderCocoa(
            fixWidth: contentWidth,
            prefUITab: .tabSmartTyping
          )
        }?.boxed()
        NSView().makeSimpleConstraint(.height, relation: .equal, value: NSFont.systemFontSize)
      }
    }
  }
}

@available(macOS 14.0, *)
#Preview(traits: .fixedLayout(width: 600, height: 768)) {
  SettingsPanesCocoa.SmartTyping()
}
