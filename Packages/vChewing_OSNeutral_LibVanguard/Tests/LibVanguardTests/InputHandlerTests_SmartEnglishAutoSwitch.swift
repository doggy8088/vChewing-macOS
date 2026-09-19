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
    // 相對路徑情境：`./con` ＋ Tab。`./` 兩鍵即已自動轉英（見 SES050），
    // 故 Tab 此時只負責放行給客體（自動完成），輸出仍為 `./con`。
    ["."].forEach { _ = triageKey($0) }
    _ = triageKey("/")
    ["c", "o", "n"].forEach { _ = triageKey($0) }
    let consumed = triageKey(
      KBEvent.SpecialKey.tab.unicodeScalar.description,
      keyCode: KeyCode.kTab.rawValue
    )
    #expect(!consumed)
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.joined() == "./con")
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
    // 上一層相對路徑情境：`../pro` ＋ Tab（`..` 兩鍵即已自動轉英）。
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
    #expect(testSession.recentCommissions.joined() == "../pro")
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
    // 路徑後接空格（`./con `）：`./` 兩鍵即轉英，之後的空格屬英數暫存模式的內容。
    _ = triageKey(".")
    _ = triageKey("/")
    ["c", "o", "n"].forEach { _ = triageKey($0) }
    #expect(triageKey(" "))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.joined() == "./con ")
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

  // MARK: - URL 情境（重複韻母鍵視為誤鍵）

  @Test
  func test_SES040_RepeatedSlashCountsAsTypingError() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `/` ＝ ㄥ：連按兩次即槽位內容不變的死鍵，應計為誤鍵。
    let single = SmartEnglishTrailAnalyzer.analyze(keyTrail: [":", "/"], parser: .ofDachen)
    let doubled = SmartEnglishTrailAnalyzer.analyze(keyTrail: [":", "/", "/"], parser: .ofDachen)
    #expect(doubled.violationCount == single.violationCount + 1)
    // 實機（handler）流程亦同：連按第二個相同的韻母鍵使計次增加一次。
    // （此處用 `l` ＝ ㄠ，避免與 §5.1.C 的路徑前綴規則（`//`）互相干涉。）
    _ = triageKey("c")
    _ = triageKey("l")
    let errorsBeforeRepeat = testHandler.smartEnglishConsecutiveTypingErrors
    _ = triageKey("l")
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == errorsBeforeRepeat + 1)
  }

  @Test
  func test_SES041_HTTPSURLWithDefaultThresholdConvertsEnglish() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `https://` 一氣呵成：預設門檻 5，於最後一個 `/` 達標並整段轉英。
    // 註：此情境的 `:` 因注拼槽非空而未併入組字器（維持既有蜂鳴語義），故其半形字元
    // 由輸入鍵序列承擔；若 `:` 確已併入組字器，則由 `trailOwnedPunctuations` 改寫為半形
    // （見 SES045），兩條路徑的輸出同為半形的 `https://`。
    #expect(testHandler.smartEnglishErrorThreshold == 5)
    ["h", "t", "t", "p", "s", ":", "/"].forEach { _ = triageKey($0) }
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 4)
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(triageKey("/"))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "https://")
  }

  @Test
  func test_SES043_FullWidthColonIsNotDuplicatedInEnglishOutput() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 中文模式下 `:` 會被轉成全形 `：` 併入組字器；轉英時必須只輸出半形的原按鍵序列。
    // （`//` 兩鍵即觸發 §5.1.C 的路徑前綴規則；不論走哪條觸發路徑，輸出皆須為半形的 `:`。）
    _ = triageKey(":")
    _ = triageKey("/")
    #expect(testHandler.committableDisplayText(sansReading: true).contains("："))
    _ = triageKey("/")
    #expect(triageKey(" "))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.joined() == ":// ")
  }

  @Test
  func test_SES044_ChinesePrefixSanitizerDropsOnlyTrailOwnedPunctuation() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 出自同一批按鍵的全形標點：由序列承擔輸出 → 自前綴移除。
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("：", trail: [":", "/"]) == "")
    #expect(
      testHandler.sanitizedChinesePrefixForSmartEnglish("話，", trail: ["<", "u", "/"]) == "話，"
    )
    // 序列中沒有對應的半形字元時，一律保留（例如先前正常輸入的中文標點）。
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("：", trail: ["c", "d"]) == "：")
  }

  @Test
  func test_SES042_RepeatedPunctuationQuickPhraseDoesNotSwitch() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 快速標點（`,,,,`）不得因重複鍵新規則而誤觸自動轉英。
    typeSentence(",,,,")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(testHandler.smartEnglishConsecutiveTypingErrors < testHandler.smartEnglishErrorThreshold)
  }

  // MARK: - 標點情境（標點是正常輸入，永不計為誤鍵）

  @Test
  func test_SES048_PunctuationViaAliasKeyIsNotATypingError() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 實機案例：以 `<` 鍵輸入「，」（該鍵不是注音鍵），原本被計為無效鍵，
    // 導致接著打「終於」（終 ＝ ㄓㄨㄥ）再按空白鍵（一聲）即誤轉英文。
    let originalValue = testHandler.prefs.smartEnglishAutoSwitchErrorThreshold
    defer { testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = originalValue }
    testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = 3
    _ = triageKey("<")
    #expect(testHandler.committableDisplayText(sansReading: true).contains("，"))
    // 標點按鍵既已由組字器承擔輸出，就不該留在輸入鍵序列中、也不該計為誤鍵。
    #expect(testHandler.smartEnglishKeyTrail.isEmpty, "trail=\(testHandler.smartEnglishKeyTrail)")
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 0)
    ["5", "j", "/"].forEach { _ = triageKey($0) }
    _ = triageKey(" ")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(
      !testSession.recentCommissions.contains { $0.contains("<") },
      "commissions=\(testSession.recentCommissions)"
    )
  }

  // MARK: - 路徑／URL 前綴（不需斷點鍵即轉英）

  @Test
  func test_SES050_PathPrefixConvertsWithoutBreakKey() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `./` 只有兩鍵：注音讀作 `.` ＝ ㄡ、`/` ＝ ㄥ（後者覆寫前者，先前的鍵白打），
    // 明顯不是中文輸入順序，故不等誤鍵門檻（預設 5）即整段轉英。
    #expect(testHandler.smartEnglishErrorThreshold == 5)
    _ = triageKey(".")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(triageKey("/"))
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "./")
    // 之後的字元一律走英數暫存模式。
    _ = triageKey("b")
    #expect(testSession.recentCommissions.last == "b")
  }

  @Test
  func test_SES051_OtherPathPrefixesConvertImmediately() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `..`（相對路徑的上一層）與 `//` 同樣只有兩鍵即轉英。
    for keys in [[".", "."], ["/", "/"]] {
      resetSmartEnglishTestState()
      keys.forEach { _ = triageKey($0) }
      #expect(testHandler.isSmartEnglishModeActive, "keys=\(keys)")
      #expect(
        testSession.recentCommissions.contains(keys.joined()),
        "keys=\(keys) commissions=\(testSession.recentCommissions)"
      )
    }
  }

  @Test
  func test_SES052_PlausibleChineseIsNotHijackedByPathPrefixRule() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // `c l k` ＝ ㄏㄠ → ㄏㄜ（改韻母的中文修正行為）：不得因此轉英。
    ["c", "l", "k"].forEach { _ = triageKey($0) }
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(testHandler.smartEnglishConsecutiveTypingErrors == 0)
    // `.` 之後接聲調鍵（`. 3` ＝ 偶）：屬正常中文輸入，不得轉英。
    resetSmartEnglishTestState()
    _ = triageKey(".")
    _ = triageKey("3")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(!testSession.recentCommissions.contains("./"))
  }

  @Test
  func test_SES049_TrailRecordsNoPunctuationKeysAtAll() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 全形標點與其別名鍵（`<`、`[`、`'`……）皆屬正常輸入，逐一驗證不計誤鍵。
    for key in ["<", ">", "[", "]", "'", "\\"] {
      resetSmartEnglishTestState()
      _ = triageKey(key)
      #expect(testHandler.smartEnglishKeyTrail.isEmpty, "key=\(key) trail=\(testHandler.smartEnglishKeyTrail)")
      #expect(
        testHandler.smartEnglishConsecutiveTypingErrors == 0,
        "key=\(key) errors=\(testHandler.smartEnglishConsecutiveTypingErrors)"
      )
      #expect(!testHandler.isSmartEnglishModeActive, "key=\(key)")
    }
  }

  // MARK: - URL 情境（半形輸出保證）

  @Test
  func test_SES045_ColonIsNotResurrectedAfterPunctuationKeyRemoval() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 實機（Ghostty）案例：`:` 已併入組字器為全形 `：`、且已自輸入鍵序列移除，
    // 轉英時仍必須輸出半形的 `://ww`（不得殘留全形、也不得漏掉該冒號）。
    let originalValue = testHandler.prefs.smartEnglishAutoSwitchErrorThreshold
    defer { testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = originalValue }
    testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = 3
    _ = triageKey(":")
    #expect(testHandler.committableDisplayText(sansReading: true).contains("："))
    #expect(testHandler.smartEnglishContext.trailOwnedPunctuations == ["："])
    ["/", "/", "w", "w"].forEach { _ = triageKey($0) }
    #expect(testHandler.isSmartEnglishModeActive)
    // 觸發時遞交的內容與後續英數暫存模式的逐字遞交，接起來必須是半形的 `://ww`。
    let commissions = testSession.recentCommissions.joined()
    #expect(commissions.contains("://ww"), "commissions=\(testSession.recentCommissions)")
    #expect(!commissions.contains("："), "commissions=\(testSession.recentCommissions)")
  }

  @Test
  func test_SES047_IdleExitKeyIsRecordedAsFreshChineseInput() throws {
    resetSmartEnglishTestState()
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 實機（Ghostty）案例：`https` 觸發轉英後閒置逾時（> 500 ms），接著敲下的 `:` 會結束
    // 英數暫存模式；該按鍵必須以「中文模式的新按鍵」續審，否則併入組字器的全形 `：`
    // 不會被視為同一批按鍵、轉英時便會殘留全形。
    let originalValue = testHandler.prefs.smartEnglishAutoSwitchErrorThreshold
    defer { testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = originalValue }
    testHandler.prefs.smartEnglishAutoSwitchErrorThreshold = 3
    ["h", "t", "t", "p", "s"].forEach { _ = triageKey($0) }
    #expect(testHandler.isSmartEnglishModeActive)
    #expect(testSession.recentCommissions.last == "https")
    testHandler.smartEnglishContext.mode?.lastActivityDate = Date(timeIntervalSinceNow: -10)
    _ = triageKey(":")
    #expect(!testHandler.isSmartEnglishModeActive)
    #expect(testHandler.committableDisplayText(sansReading: true).contains("："))
    ["/", "/", "w", "w"].forEach { _ = triageKey($0) }
    let commissions = testSession.recentCommissions.joined()
    #expect(commissions.contains("://ww"), "commissions=\(testSession.recentCommissions)")
    #expect(!commissions.contains("："), "commissions=\(testSession.recentCommissions)")
  }

  @Test
  func test_SES046_ChinesePrefixSanitizerConvertsOnlyTrailOwnedPunctuation() throws {
    resetSmartEnglishTestState()
    guard let testHandler else {
      Issue.record("Test handler or session is nil.")
      return
    }
    // 序列已失去該鍵（已由組字器承擔）、且該標點確為序列所產生：改寫為半形，不重複、也不殘留全形。
    testHandler.smartEnglishContext.trailOwnedPunctuations = ["："]
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("：", trail: ["/", "/"]) == ":")
    // 序列自產標點的連續串（例如「（，」）依序改寫為半形。
    testHandler.smartEnglishContext.trailOwnedPunctuations = ["（", "，"]
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("（，", trail: ["w"]) == "(,")
    // 序列同時保有半形字元時，該自產標點整段剔除（避免重複輸出）。
    testHandler.smartEnglishContext.trailOwnedPunctuations = ["："]
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("：", trail: [":", "/"]) == "")
    // 非序列所產生的中文標點（例如使用者自行輸入的 `，`）一律保留原樣。
    testHandler.smartEnglishContext.trailOwnedPunctuations = []
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("話，", trail: ["w", "w"]) == "話，")
    #expect(testHandler.sanitizedChinesePrefixForSmartEnglish("：", trail: ["c", "d"]) == "：")
  }
}
