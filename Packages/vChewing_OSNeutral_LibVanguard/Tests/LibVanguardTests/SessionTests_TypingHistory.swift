// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import Shared
@testable import LibVanguard
import Testing

// MARK: - 打字履歷（Typing History）× 真實會話管線

extension LibVanguardTestsRoot.InputHandlerTests.Session {
  /// 產生一份專供本次測試使用的打字履歷暫存檔 URL。
  private func makeTypingHistoryTempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("vChewing_typing-history-\(UUID().uuidString).jsonl")
  }

  private func tearDownTypingHistory(from url: URL) {
    testHandler.prefs.recordTypingHistory = false
    SessionHost.shared.typingHistoryDataURL = { nil }
    try? FileManager.default.removeItem(at: url)
  }

  @Test
  func test_TH01_TypingHistoryRecordsCommittedComposition() throws {
    let tempURL = makeTypingHistoryTempURL()
    defer { tearDownTypingHistory(from: tempURL) }

    resetToAbortionAndClear()
    prepareBasicComposition(sequence: "dk ru4") // 科技
    #expect(testSession.state.displayedText == "科技")

    testHandler.prefs.spaceKeyBehaviorAgainstICB = 0 // 空格鍵用於遞交。
    testHandler.prefs.recordTypingHistory = true
    SessionHost.shared.typingHistoryDataURL = { tempURL }

    testClientProxy.clear()
    press(.spaceEvent)
    #expect(testClientProxy.committedText.hasPrefix("科技"))

    let content = try String(contentsOf: tempURL, encoding: .utf8)
    let lines = content.split(whereSeparator: \.isNewline).map(String.init)
    #expect(lines.count == 1, "實際內容：\(content)")
    let line = try #require(lines.first)
    let lineData = try #require(line.data(using: .utf8))
    let entry = try JSONDecoder().decode(TypingHistoryLogger.Entry.self, from: lineData)
    #expect(entry.text == "科技")
    #expect(entry.reading == "ㄎㄜ-ㄐㄧˋ")
    #expect(entry.mode == "cht")
    #expect(entry.timestamp > 0)
  }

  @Test
  func test_TH02_TypingHistoryIsOffByDefault() throws {
    let tempURL = makeTypingHistoryTempURL()
    defer { tearDownTypingHistory(from: tempURL) }

    resetToAbortionAndClear()
    prepareBasicComposition(sequence: "dk ru4") // 科技
    #expect(testSession.state.displayedText == "科技")

    testHandler.prefs.spaceKeyBehaviorAgainstICB = 0
    testHandler.prefs.recordTypingHistory = false
    SessionHost.shared.typingHistoryDataURL = { tempURL }

    testClientProxy.clear()
    press(.spaceEvent)
    #expect(testClientProxy.committedText.hasPrefix("科技"))
    #expect(!FileManager.default.fileExists(atPath: tempURL.path))
  }
}
