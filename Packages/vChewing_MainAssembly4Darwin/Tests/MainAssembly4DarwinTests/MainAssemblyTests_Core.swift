// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Testing

@testable import MainAssembly4Darwin

// MARK: - MainAssemblyTests

/// 唯音輸入法 Darwin 宿主（MainAssembly4Darwin）的單元測試基座。
///
/// 本基座只負責 Darwin 宿主專屬的全域設定：單元測試專用的 `UserDefaults`、
/// `LMMgr` 的沙箱環境與路徑失效警示的 KVO 觀察器，以及兩處 UI 宿主接線。
///
/// 跨平台（Session／InputHandler）行為的測試位於 `vChewing_Typewriter` 套件的
/// `TypewriterTests`；此處僅保留必須在 Darwin 宿主上進行的測試。
@Suite(.serialized)
@MainActor
final class MainAssemblyTests {
  init() {
    UserDefaults.unitTests = .init(suiteName: "org.atelierInmu.vChewing.MainAssembly.UnitTests")
    UserDefaults.pendingUnitTests = true
    UserDef.resetAll()
    SettingsUIHost.wireUp()
    SessionHost.wireUp()
    // 生產路徑的 LMMgr.shared 已改由 phraseEditorDelegateProvider 延遲實體化；
    // 測試需要其 KVO 觀察器在場以錄製路徑失效警示，故在此顯式武裝。
    _ = LMMgr.shared
    LMMgr.prepareForUnitTests()
    LMMgr.resetRecordedPathInvalidityAlerts()
    LMMgr.syncLMPrefs()
  }

  deinit {
    mainSync {
      LMMgr.resetAfterUnitTests()
      LMMgr.resetRecordedPathInvalidityAlerts()
    }
    UserDefaults.unitTests?.removeSuite(named: "org.atelierInmu.vChewing.MainAssembly.UnitTests")
    UserDefaults.pendingUnitTests = false
  }
}
