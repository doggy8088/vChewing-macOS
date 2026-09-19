// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import Homa
import LexiconAssembly
@testable import LibVanguard
import Shared
import Tekkon
import Testing

// MARK: - 智慧中英自動切換 × 真實會話管線（SessionProtocol.handleEvent）

extension LibVanguardTestsRoot.InputHandlerTests.Session {
  /// 診斷用：印出當前管線狀態。
  func diagSmartEnglish(_ tag: String) {
    print(
      "[SES-DIAG][\(tag)] state=\(testSession.state.type.rawValue)"
        + " composer=\(testHandler.composer.value)"
        + " trail=\(testHandler.smartEnglishKeyTrail)"
        + " mode=\(testHandler.isSmartEnglishModeActive)"
        + " committed=\(testClientProxy.committedText.debugDescription)"
        + " isASCIIMode=\(testSession.isASCIIMode)"
    )
  }

  @Test
  func test_SESR01_RealSessionDotSlashBuildWithTab() throws {
    resetToAbortionAndClear()
    let keys: [KBEvent.KeyEventData] = [".", "/", "b", "u", "i", "l", "d"].map { KBEvent.KeyEventData(chars: $0) }
    keys.forEach { press($0) }
    diagSmartEnglish("after ./build")
    press(KBEvent.KeyEventData.dataTab, shouldHandle: false)
    diagSmartEnglish("after Tab")
    #expect(testClientProxy.committedText == "./build")
  }

  @Test
  func test_SESR02_RealSessionConsecutiveErrorThreshold() throws {
    resetToAbortionAndClear()
    // 全為合理按鍵、但輸入順序一路不合理：預設門檻 5 時第 6 鍵即自動轉英。
    let keys: [KBEvent.KeyEventData] = ["c", "d", "c", "d", "c", "d"].map { KBEvent.KeyEventData(chars: $0) }
    keys.forEach { press($0) }
    diagSmartEnglish("after cdcdcd")
    #expect(testClientProxy.committedText == "cdcdcd")
    #expect(testHandler.isSmartEnglishModeActive)
    // 進入英數暫存模式後，後續鍵入逐字遞交。
    press(KBEvent.KeyEventData(chars: "e"))
    #expect(testClientProxy.committedText == "cdcdcde")
  }

  @Test
  func test_SESR03_RealSessionBackspaceResetsErrorCount() throws {
    resetToAbortionAndClear()
    ["c", "d", "c"].forEach { press(KBEvent.KeyEventData(chars: $0)) }
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 2)
    press(KBEvent.KeyEventData.backspace, shouldHandle: true)
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 0)
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(testClientProxy.committedText.isEmpty)
  }

  @Test
  func test_SESR04_RealSessionPunctuationThenChineseStaysChinese() throws {
    resetToAbortionAndClear()
    // 使用者實機情境：以 `<` 鍵輸入「，」再打「終於」（終 ＝ ㄓㄨㄥ，空白鍵為一聲）。
    // 標點是正常的中文輸入，不得被計為誤鍵、也不得因此把後續的中文輸入轉成英文。
    ["<", "5", "j", "/", " "].forEach { press(KBEvent.KeyEventData(chars: $0)) }
    diagSmartEnglish("after ，終於")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 0)
    #expect(testClientProxy.committedText.isEmpty)
    #expect(!testHandler.smartEnglishKeyTrail.contains("<"))
    #expect(testSession.state.displayedText.contains("，"))
    #expect(!testSession.state.displayedText.contains("<"))
  }

  @Test
  func test_SESR05_RealSessionPathPrefixConvertsWithoutBreakKey() throws {
    resetToAbortionAndClear()
    // 使用者實機情境：只打 `./`（兩鍵）即應轉英，不必等誤鍵門檻或空格／Tab。
    [".", "/"].forEach { press(KBEvent.KeyEventData(chars: $0)) }
    diagSmartEnglish("after ./")
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testClientProxy.committedText == "./")
    // 續打 `build` 一路為英文。
    ["b", "u", "i", "l", "d"].forEach { press(KBEvent.KeyEventData(chars: $0)) }
    diagSmartEnglish("after ./build")
    #expect(testClientProxy.committedText == "./build")
  }
}
