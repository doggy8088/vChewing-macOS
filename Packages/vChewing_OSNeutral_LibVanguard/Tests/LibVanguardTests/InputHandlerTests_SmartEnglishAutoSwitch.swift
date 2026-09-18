// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import LexiconAssembly
@testable import LibVanguard
import Shared
import Tekkon
import Testing

// MARK: - 智慧中英輸入自動切換（Smart ZH-EN Auto-Switch）相關測試

extension LibVanguardTestsRoot.InputHandlerTests {
  // MARK: - 工具函式

  /// 分診單一按鍵（僅 keyDown，InputHandler 不處理 keyUp）。
  /// - Returns: `triageInput` 的回傳值：true 表示按鍵已被輸入法攔截。
  @discardableResult
  func triageKey(
    _ chars: String,
    keyCode: UInt16? = nil,
    flags: KBEvent.ModifierFlags = []
  )
    -> Bool {
    guard let testHandler else { return false }
    let data = KBEvent.KeyEventData(flags: flags, chars: chars, keyCode: keyCode)
    return testHandler.triageInput(event: data.asEvent)
  }

  /// 清除測試之間可能殘留的智慧中英自動切換狀態與遞交紀錄。
  func resetSmartEnglishTestState() {
    testHandler?.resetSmartEnglishAutoSwitchState()
    testSession?.recentCommissions.removeAll()
    testSession?.switchState(.ofEmpty())
  }

  // MARK: - 序列合理性分析

  @Test
  func test_SES001_TrailAnalysisViolations() throws {
    let parser = Tekkon.MandarinParser.ofDachen
    // `cd` → ㄏ 被 ㄎ 覆寫：破壞性覆寫。
    #expect(SmartEnglishTrailAnalyzer.analyze(keyTrail: ["c", "d"], parser: parser).containsViolation)
    // `ls` → 先韻母 ㄠ 再聲母 ㄋ：順序倒錯。
    #expect(SmartEnglishTrailAnalyzer.analyze(keyTrail: ["l", "s"], parser: parser).containsViolation)
    // `vi` → ㄒㄛ 不是合法音節、亦非任何合法音節的前綴。
    #expect(SmartEnglishTrailAnalyzer.analyze(keyTrail: ["v", "i"], parser: parser).containsViolation)
    // 合理的中文輸入順序不應被判定為違規。
    #expect(!SmartEnglishTrailAnalyzer.analyze(keyTrail: ["s", "u", "3"], parser: parser).containsViolation)
    #expect(!SmartEnglishTrailAnalyzer.analyze(keyTrail: ["c", "l"], parser: parser).containsViolation)
    #expect(!SmartEnglishTrailAnalyzer.analyze(keyTrail: ["s"], parser: parser).containsViolation)
    // 純標點不具任何注音鍵。
    let punctuationOnly = SmartEnglishTrailAnalyzer.analyze(keyTrail: ["'"], parser: parser)
    #expect(!punctuationOnly.containsZhuyinKey)
  }

  // MARK: - Space 觸發

  @Test
  func test_SES002_CDSpaceTriggersEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    triageKey("c")
    triageKey("d")
    #expect(!testHandler.isSmartEnglishModeActive)
    let consumed = triageKey(" ")
    #expect(consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "cd ")
    #expect(testHandler.composer.isEmpty)
  }

  @Test
  func test_SES003_LSSpaceTriggersEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    triageKey("l")
    triageKey("s")
    #expect(triageKey(" "))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "ls ")
  }

  @Test
  func test_SES004_VISpaceTriggersEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    triageKey("v")
    triageKey("i")
    #expect(triageKey(" "))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "vi ")
  }

  @Test
  func test_SES005_PlausibleChineseSequenceIsUnaffected() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `cl` ＝ ㄏㄠ：合理的中文輸入前綴，不應轉為英文。
    triageKey("c")
    triageKey("l")
    #expect(!testHandler.smartEnglishKeyTrail.isEmpty)
    _ = triageKey(" ")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(!testSession.recentCommissions.contains("cl "))
  }

  @Test
  func test_SES006_CompletedChineseSyllableIsUnaffected() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("su3")
    // 完整音節既已固化，序列在下一次分診時即失效（不得把注音鍵誤轉為英文）。
    _ = triageKey(" ")
    #expect(testHandler.smartEnglishKeyTrail.isEmpty)
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(!testSession.recentCommissions.contains { $0.contains("su3") })
  }

  // MARK: - Tab 觸發

  @Test
  func test_SES007_TabConvertsTrailAndPassesTabThrough() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    triageKey("g")
    triageKey("i")
    triageKey("t")
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    // Tab 必須放行給客體（自動完成），故 triageInput 應回報 false。
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.contains("git"))
  }

  // MARK: - 英數暫存模式的鍵入

  @Test
  func test_SES008_EnglishModeKeepsTypingAndFinishesWithEnter() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("cd ")
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(triageKey("."))
    #expect(triageKey("."))
    #expect(triageKey("/"))
    #expect(testSession.recentCommissions.suffix(3) == [".", ".", "/"])
    let enterConsumed = triageKey(
      KBEvent.SpecialKey.carriageReturn.unicodeScalar.description,
      keyCode: KeyCode.kLineFeed.rawValue
    )
    #expect(!enterConsumed)
    #expect(!testHandler.isSmartEnglishModeActive)
    // 離開英數暫存模式之後，注音輸入照常運作。
    #expect(triageKey("c"))
    #expect(testHandler.composer.consonant.value == "ㄏ")
  }

  @Test
  func test_SES009_EnglishModeConsumesSpace() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("ls ")
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testHandler.assembler.isEmpty)
  }

  // MARK: - 閒置逾時

  @Test
  func test_SES010_IdleTimeoutReturnsToChineseMode() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("cd ")
    #expect(testHandler.isSmartEnglishModeActive)
    let countBefore = testSession.recentCommissions.count
    // 模擬閒置逾時。
    testHandler.smartEnglishContext.mode?.lastActivityDate = Date().addingTimeInterval(-10)
    #expect(triageKey("c"))
    #expect(!testHandler.isSmartEnglishModeActive)
    // 本拍按鍵改以中文流程處理：不得再遞交任何英文字元。
    #expect(testSession.recentCommissions.count == countBefore)
    #expect(testHandler.composer.consonant.value == "ㄏ")
  }

  // MARK: - BackSpace 行為

  @Test
  func test_SES011_SingleBackspaceKeepsEnglishMode() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("cd ")
    #expect(testHandler.isSmartEnglishModeActive)
    let countBefore = testSession.recentCommissions.count
    let consumed = triageKey(
      KBEvent.SpecialKey.backspace.unicodeScalar.description,
      keyCode: KeyCode.kBackSpace.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testHandler.smartEnglishContext.mode?.consecutiveBackSpaceCount == 1)
    #expect(testSession.recentCommissions.count == countBefore)
  }

  @Test
  func test_SES012_ThreeBackspacesCancelEnglishModeAndRestoreComposition() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("ls ")
    #expect(testHandler.isSmartEnglishModeActive)
    let backspace = KBEvent.SpecialKey.backspace.unicodeScalar.description
    for _ in 0 ..< 2 {
      triageKey(backspace, keyCode: KeyCode.kBackSpace.rawValue)
    }
    #expect(testHandler.isSmartEnglishModeActive)
    triageKey(backspace, keyCode: KeyCode.kBackSpace.rawValue)
    #expect(!testHandler.isSmartEnglishModeActive)
    // 還原觸發前的注音組字進度：ㄋㄠ。
    #expect(testHandler.composer.consonant.value == "ㄋ")
    #expect(testHandler.composer.vowel.value == "ㄠ")
    #expect(testHandler.smartEnglishKeyTrail == ["l", "s"])
  }

  // MARK: - 偏好設定與邊界

  @Test
  func test_SES013_DisabledPreferenceKeepsLegacyBehavior() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    let originalValue = testHandler.prefs.smartEnglishAutoSwitchEnabled
    testHandler.prefs.smartEnglishAutoSwitchEnabled = false
    defer { testHandler.prefs.smartEnglishAutoSwitchEnabled = originalValue }
    triageKey("c")
    triageKey("d")
    _ = triageKey(" ")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(!testSession.recentCommissions.contains("cd "))
  }

  @Test
  func test_SES014_PunctuationOnlyTrailIsNotConverted() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    triageKey("'")
    _ = triageKey(" ")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(!testSession.recentCommissions.contains { $0.contains("'") })
  }

  @Test
  func test_SES015_TabWithoutTrailKeepsLegacyBehavior() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("su3")
    _ = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!testHandler.isSmartEnglishModeActive)
    // 序列已隨固化失效，Tab 不得把已固化的注音鍵轉為英文。
    #expect(testHandler.smartEnglishKeyTrail.isEmpty)
  }

  @Test
  func test_SES016_ChinesePrefixIsCommittedBeforeEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("su3")
    let chinesePrefix = testHandler.assembler.assembledSentence.values.joined()
    triageKey("c")
    triageKey("d")
    #expect(triageKey(" "))
    // 先鍵入的中文內容必須排在英文內容之前。
    #expect(testSession.recentCommissions.last == chinesePrefix + "cd ")
  }

  @Test
  func test_SES017_ModifierCombosPassThroughInEnglishMode() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    typeSentence("cd ")
    #expect(testHandler.isSmartEnglishModeActive)
    // Cmd / Control 組合鍵一律放行給客體快捷鍵、且不結束英數暫存模式。
    #expect(!triageKey("c", flags: [.command]))
    #expect(!triageKey("c", flags: [.control]))
    #expect(testHandler.isSmartEnglishModeActive)
  }

  @Test
  func test_SES018_IdleTimeoutPreferenceIsRespected() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    let originalValue = testHandler.prefs.smartEnglishAutoSwitchIdleTimeoutMS
    defer { testHandler.prefs.smartEnglishAutoSwitchIdleTimeoutMS = originalValue }
    testHandler.prefs.smartEnglishAutoSwitchIdleTimeoutMS = 1_500
    #expect(testHandler.smartEnglishIdleTimeoutSeconds == 1.5)
  }

  @Test
  func test_SES019_TabConvertsEvenPlausibleTrail() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `cl` ＝ ㄏㄠ 屬合理的中文輸入前綴；但 Tab 依規格為無條件轉英。
    triageKey("c")
    triageKey("l")
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.contains("cl"))
  }

  @Test
  func test_SES020_RelativePathWithTabIsConverted() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 相對路徑情境：`./con` ＋ Tab（`.` 與 `/` 亦必須計入輸入鍵序列）。
    ["."].forEach { _ = triageKey($0) }
    _ = triageKey("/")
    ["c", "o", "n"].forEach { _ = triageKey($0) }
    #expect(testHandler.smartEnglishKeyTrail == [".", "/", "c", "o", "n"])
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.contains("./con"))
  }

  @Test
  func test_SES021_FileNamePrefixWithTabIsConverted() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 檔名前綴情境：`conf` ＋ Tab。
    ["c", "o", "n", "f"].forEach { _ = triageKey($0) }
    #expect(testHandler.smartEnglishKeyTrail == ["c", "o", "n", "f"])
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.contains("conf"))
  }

  @Test
  func test_SES022_ParentRelativePathWithTabIsConverted() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 上一層相對路徑情境：`../pro` ＋ Tab。
    ["."].forEach { _ = triageKey($0) }
    _ = triageKey(".")
    _ = triageKey("/")
    ["p", "r", "o"].forEach { _ = triageKey($0) }
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.contains("../pro"))
  }

  @Test
  func test_SES023_TabInsideEnglishModeStaysInEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 英數暫存模式中的 Tab（例如 `cd ` 之後的自動完成）純放行、不遞交任何內容、亦不結束模式。
    typeSentence("cd ")
    #expect(testHandler.isSmartEnglishModeActive)
    let countBefore = testSession.recentCommissions.count
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.count == countBefore)
    // Tab 鍵不得被當成 Tab 字元遞交。
    #expect(!testSession.recentCommissions.joined().contains("\t"))
  }

  @Test
  func test_SES024_RelativePathFollowedBySpaceIsConverted() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 路徑後接空格（`./con `）亦屬不合理的注音順序，比照 `cd ` 轉為英文。
    _ = triageKey(".")
    _ = triageKey("/")
    ["c", "o", "n"].forEach { _ = triageKey($0) }
    #expect(triageKey(" "))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "./con ")
  }

  @Test
  func test_SES025_UpperCasePathSegmentWithTab() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 含大寫字母的路徑片段（`./Doc`）＋ Tab。
    _ = triageKey(".")
    _ = triageKey("/")
    _ = triageKey("D", flags: [.shift])
    ["o", "c"].forEach { _ = triageKey($0) }
    _ = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(testSession.recentCommissions.joined() == "./Doc")
  }

  @Test
  func test_SES026_TabIsPassedThroughAsAKeyNotAsACharacter() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    let tab = KBEvent.SpecialKey.tab.unicodeScalar.description
    let tabKeyCode = KeyCode.kTab.rawValue

    // `<Tab>` 的語義：把「真實的 Tab 按鍵」放行給客體（終端機因而觸發自動完成），
    // 而不是把 Tab 字元（`\t`）當成文字遞交。
    ["g", "i", "t"].forEach { _ = triageKey($0) }
    #expect(!triageKey(tab, keyCode: tabKeyCode))
    #expect(testSession.recentCommissions == ["git"])
    #expect(!testSession.recentCommissions.joined().contains("\t"))

    // 英數暫存模式內再按 Tab：同樣只放行、不遞交。
    #expect(!triageKey(tab, keyCode: tabKeyCode))
    #expect(testSession.recentCommissions == ["git"])
    #expect(!testHandler.smartEnglishContext.keyTrail.contains(where: { $0 == "\t" }))

    // Shift+Tab（反向自動完成）：比照辦理。
    testHandler.resetSmartEnglishAutoSwitchState()
    testSession.recentCommissions.removeAll()
    ["p", "r", "o"].forEach { _ = triageKey($0) }
    #expect(!triageKey(tab, keyCode: tabKeyCode, flags: [.shift]))
    #expect(testSession.recentCommissions == ["pro"])
    #expect(!testSession.recentCommissions.joined().contains("\t"))
  }

  // MARK: - 連續誤鍵自動轉英

  @Test
  func test_SES030_ConsecutiveTypingErrorsTriggerEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 預設門檻 5：`cdcdcd` 每個聲母重複鍵各計一次誤鍵（共 6 次）。
    #expect(testHandler.smartEnglishErrorThreshold == 5)
    ["c", "d", "c", "d", "c"].forEach { _ = triageKey($0) }
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 4)
    // 第六鍵達門檻：自動轉英、本拍按鍵被消費、不附加空格。
    #expect(triageKey("d"))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "cdcdcd")
  }

  @Test
  func test_SES031_BackspaceResetsConsecutiveTypingErrors() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    ["c", "d", "c"].forEach { _ = triageKey($0) }
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 2)
    // 尚未輸出英文前的 BackSpace＝使用者想打中文、只是打錯鍵：計次歸零。
    _ = triageKey(
      KBEvent.SpecialKey.backspace.unicodeScalar.description,
      keyCode: KeyCode.kBackSpace.rawValue
    )
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 0)
    #expect(!testHandler.isSmartEnglishModeActive)
    // 退格後序列一併失效、重新累計：`cdcd` 累積 3 次誤鍵，尚未達門檻 5。
    ["c", "d", "c", "d"].forEach { _ = triageKey($0) }
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 3)
    #expect(!testHandler.isSmartEnglishModeActive)
    _ = triageKey("c")
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 4)
    #expect(triageKey("d"))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "cdcdcd")
  }

  @Test
  func test_SES032_ErrorThresholdPreferenceIsRespected() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    let originalValue = testHandler.prefs.smartEnglishAutoSwitchErrorThreshold
    defer { testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = originalValue }
    testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = 3
    #expect(testHandler.smartEnglishErrorThreshold == 3)
    ["c", "d", "c"].forEach { _ = triageKey($0) }
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(triageKey("d"))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "cdcd")
  }

  @Test
  func test_SES033_CompositionCommitResetsConsecutiveTypingErrors() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    ["c", "d"].forEach { _ = triageKey($0) }
    #expect(testHandler.smartEnglishConsecutiveTypingErrors >= 1)
    #expect(!testHandler.isSmartEnglishModeActive)
    // 成功組字成文（`2u,6` ＝ ㄉㄧㄝˊ）之後，下一拍對帳即歸零。
    typeSentence("2u,6")
    _ = triageKey("c")
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 0)
    #expect(testHandler.smartEnglishKeyTrail == ["c"])
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(!testSession.recentCommissions.contains { $0.contains("cd") })
  }
}
