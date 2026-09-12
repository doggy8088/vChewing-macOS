// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import SwiftUI

// MARK: - VwrSettingsPaneSmartTyping

/// 「智慧輸入」設定窗格：收納智慧中英混打（連續誤鍵自動切換為英數輸入）的相關設定。
@available(macOS 14, *)
public struct VwrSettingsPaneSmartTyping: View {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public var body: some View {
    Form {
      // MARK: (header: Text("Smart Chinese/English Mixed Typing:"))

      Section {
        UserDef.kAutoSwitchToAlphanumericalOnConsecutiveErrors.renderUI()
        UserDef.kConsecutiveTypingErrorsThreshold.renderUI()
        UserDef.kAutoSwitchedEnglishModeIdleTimeout.renderUI()
        UserDef.kAutoSwitchedEnglishModeExitHotkey.renderUI()
      }
    }.formStyled()
      .frame(
        minWidth: CtlSettingsUI.formWidth,
        maxHeight: CtlSettingsUI.contentMaxHeight
      )
  }
}

// MARK: - VwrSettingsPaneSmartTyping_Previews

@available(macOS 14, *)
struct VwrSettingsPaneSmartTyping_Previews: PreviewProvider {
  static var previews: some View {
    VwrSettingsPaneSmartTyping()
  }
}
