// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Homa
import LangModelAssembly
import Shared
import Tekkon
import Testing
@testable import Typewriter

// MARK: - AutoSwitchOnConsecutiveErrors Tests
// 註：自 2026-09 起，連續誤鍵觸發的行為改為「英數暫存輸入模式」：
// 不再遞交文字、也不再切換至系統 ABC 輸入法，全程留在唯音內。

extension InputHandlerTests {
  // MARK: - 基本觸發

  @Test
  func test_AutoSwitchOnConsecutiveErrors_BasicEnterEnglishBufferMode() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // Dachen: g=ㄕ, r=ㄐ, e=ㄍ, a=ㄇ, t=ㄔ (5 consonants -> 5 consecutive errors)
    typeSentence("great")

    // 觸發後進入英數暫存模式：不遞交、不離開唯音，英數內容暫存於組字區。
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "great")
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testSession.isASCIIMode == false)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.data.displayedText == "great")
    #expect(testHandler.composer.isEmpty)
    #expect(testHandler.assembler.isEmpty)
    #expect(testHandler.consecutiveTypingErrors.isEmpty)
    #expect(testHandler.autoEnglishChineseStash == nil)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_EnteringModeNotifiesUser() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    var notifications = [String]()
    testHandler.notificationCallback = { notifications.append($0) }
    defer { testHandler.notificationCallback = nil }

    typeSentence("great")
    #expect(notifications.count == 1)
    #expect(notifications.first?.contains("AutoSwitchedEnglishModeEntered") == true)
  }

  // MARK: - 模式期間的鍵入緩衝

  @Test
  func test_AutoSwitchOnConsecutiveErrors_SubsequentKeysAppendToBuffer() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // "cd .." 剛好滿 5 個鍵觸發切換；第 6 鍵 "/" 不再被當成注音（大千 "ㄥ"），
    // 而是計入英數暫存緩衝區。
    typeSentence("cd ..")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "cd ..")

    let slashHandled = testHandler.triageInput(event: KBEvent.KeyEventData(chars: "/").asEvent)
    #expect(slashHandled)
    #expect(testHandler.autoEnglishMode?.buffer == "cd ../")
    #expect(testSession.recentCommissions.isEmpty)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_GitLogBufferAccumulates() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // "git l" 滿 5 鍵觸發；隨後的 "og" 持續計入英數暫存緩衝區。
    typeSentence("git log")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "git log")
    #expect(testSession.recentCommissions.isEmpty)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_UpperCaseAndSpacesPreserved() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("mkdir")
    #expect(testHandler.isAutoEnglishModeActive)

    // Shift+字母鍵 = 大寫字母，應原樣計入英數暫存緩衝區。
    let capitalEvent = KBEvent.KeyEventData(
      flags: [.shift],
      chars: "X",
      charsSansModifiers: "x",
      keyCode: mapKeyCodesANSIForTests["x"]
    ).asEvent
    let handled = testHandler.triageInput(event: capitalEvent)
    #expect(handled)
    #expect(testHandler.autoEnglishMode?.buffer == "mkdirX")
  }

  // MARK: - 退出：熱鍵與還原

  @Test
  func test_AutoSwitchOnConsecutiveErrors_EscExitRestoresChineseTyping() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // "su"（ㄋㄧ，拼到一半）+ "ddd"（誤鍵）→ 觸發英數暫存模式。
    typeSentence("su")
    typeSentence("ddd")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "suddd")

    // Esc：棄置英數暫存內容、還原注拼槽（ㄋㄧ）。
    let escHandled = testHandler.triageInput(
      event: KBEvent.KeyEventData(chars: "\u{1b}", keyCode: KeyCode.kEscape.rawValue).asEvent
    )
    #expect(escHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.composer.consonant.value == "ㄋ")
    #expect(testHandler.composer.semivowel.value == "ㄧ")
    #expect(testHandler.inFlightComposerKeys == ["s", "u"])

    // 還原後繼續輸入 "3"（ㄋㄧˇ）→ 組出「你」。
    typeSentence("3")
    #expect(testHandler.assembler.assembledSentence.values.joined() == "你")
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_CustomHotkeysExitAndRestore() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    let hotkeyEvents: [(Int, KBEvent)] = [
      (
        1,
        KBEvent.KeyEventData(
          flags: [.control], chars: " ", keyCode: KeyCode.kSpace.rawValue
        ).asEvent
      ),
      (
        2,
        KBEvent.KeyEventData(
          flags: [.option],
          chars: KBEvent.SpecialKey.carriageReturn.unicodeScalar.description,
          keyCode: KeyCode.kCarriageReturn.rawValue
        ).asEvent
      ),
      (
        3,
        KBEvent.KeyEventData(
          flags: [.control],
          chars: KBEvent.SpecialKey.carriageReturn.unicodeScalar.description,
          keyCode: KeyCode.kCarriageReturn.rawValue
        ).asEvent
      ),
    ]

    for (hotkeyOption, event) in hotkeyEvents {
      testHandler.prefs.autoSwitchedEnglishModeExitHotkey = hotkeyOption
      testSession.state = .ofEmpty()
      testSession.recentCommissions.removeAll()
      testHandler.autoEnglishMode = nil
      testHandler.autoEnglishChineseStash = nil
      testSession.resetInputHandler(forceComposerCleanup: true)

      typeSentence("great")
      #expect(testHandler.isAutoEnglishModeActive)

      let handled = testHandler.triageInput(event: event)
      #expect(handled)
      #expect(!testHandler.isAutoEnglishModeActive)
      #expect(testSession.recentCommissions.isEmpty)
    }
    testHandler.prefs.autoSwitchedEnglishModeExitHotkey = 0
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_HotkeyDoesNotFireWithWrongModifiers() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testHandler.prefs.autoSwitchedEnglishModeExitHotkey = 1 // ⌃Space
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)
    defer { testHandler.prefs.autoSwitchedEnglishModeExitHotkey = 0 }

    typeSentence("great")
    #expect(testHandler.isAutoEnglishModeActive)

    // ⌥Space 不是 ⌃Space，不應觸發退出，而是計入英數暫存緩衝區。
    let altSpaceEvent = KBEvent.KeyEventData(
      flags: [.option], chars: " ", keyCode: KeyCode.kSpace.rawValue
    ).asEvent
    let handled = testHandler.triageInput(event: altSpaceEvent)
    #expect(handled)
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "great ")
  }

  // MARK: - 退出：Enter / Tab 遞交

  @Test
  func test_AutoSwitchOnConsecutiveErrors_EnterCommitsBufferAndReturnsToChinese() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(testHandler.isAutoEnglishModeActive)

    let enterHandled = testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent)
    #expect(enterHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions == ["great"])

    // 返回中文模式後可立即輸入中文。
    typeSentence("su3")
    #expect(testHandler.assembler.assembledSentence.values.joined() == "你")
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_TabCommitsBufferAndReturnsToChinese() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("mkdir")
    #expect(testHandler.isAutoEnglishModeActive)

    let tabHandled = testHandler.triageInput(event: KBEvent.KeyEventData.dataTab.asEvent)
    #expect(tabHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions == ["mkdir"])
  }

  // MARK: - 退出：BackSpace 逐字刪除

  @Test
  func test_AutoSwitchOnConsecutiveErrors_BackSpaceEditsBufferAndExitsAtEmpty() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(testHandler.isAutoEnglishModeActive)

    for _ in 1 ... 4 {
      let handled = testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent)
      #expect(handled)
      #expect(testHandler.isAutoEnglishModeActive)
    }
    #expect(testHandler.autoEnglishMode?.buffer == "g")

    // 刪到清空時自動返回中文模式、還原中文輸入進度。
    let finalHandled = testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent)
    #expect(finalHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions.isEmpty)

    // "great" 的誤鍵序列在 'r' 處打斷了 ㄕ（'g'），退出時應還原 ㄕ。
    #expect(testHandler.composer.consonant.value == "ㄕ")
    #expect(testHandler.inFlightComposerKeys == ["g"])
  }

  // MARK: - 退出：閒置逾時

  @Test
  func test_AutoSwitchOnConsecutiveErrors_IdleTimeoutCommitsAndReturnsToChinese() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testHandler.prefs.autoSwitchedEnglishModeIdleTimeout = 2
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(testHandler.isAutoEnglishModeActive)

    // 模擬閒置超過 2 秒後的下一個按鍵。
    testHandler.autoEnglishMode?.lastActivityDate = Date(timeIntervalSinceNow: -10)
    typeSentence("s")

    // 英數暫存內容自動遞交、"s" 以中文模式重新分診（ㄋ）。
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions == ["great"])
    #expect(testHandler.composer.consonant.value == "ㄋ")
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_DisabledIdleTimeoutKeepsBuffering() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testHandler.prefs.autoSwitchedEnglishModeIdleTimeout = 0
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)
    defer { testHandler.prefs.autoSwitchedEnglishModeIdleTimeout = 2 }

    typeSentence("great")
    #expect(testHandler.isAutoEnglishModeActive)

    // 逾時停用時，即使閒置再久，下一個按鍵仍計入英數暫存緩衝區。
    testHandler.autoEnglishMode?.lastActivityDate = Date(timeIntervalSinceNow: -3600)
    typeSentence("s")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "greats")
    #expect(testSession.recentCommissions.isEmpty)
  }

  // MARK: - 中文進度快照與還原

  @Test
  func test_AutoSwitchOnConsecutiveErrors_PriorAssemblerContentPreservedAndRestored() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // 先組出「你」（未遞交），再以 "suddd" 觸發（誤鍵前的 ㄋㄧ 進入 stash）。
    typeSentence("su3")
    typeSentence("su")
    typeSentence("ddd")
    #expect(testHandler.isAutoEnglishModeActive)

    // Esc 退出：組字器內容（你）與注拼槽（ㄋㄧ）一併還原、且全程沒有遞交過任何內容。
    let escHandled = testHandler.triageInput(
      event: KBEvent.KeyEventData(chars: "\u{1b}", keyCode: KeyCode.kEscape.rawValue).asEvent
    )
    #expect(escHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "你")
    #expect(testHandler.composer.consonant.value == "ㄋ")
    #expect(testHandler.composer.semivowel.value == "ㄧ")

    // 還原後續接 "3"（ㄋㄧˇ）→ 組字區顯示「你你」。
    typeSentence("3")
    #expect(testHandler.assembler.assembledSentence.values.joined() == "你你")
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_IdleExitCommitsAssemblerBeforeEnglishBuffer() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // 先組出「你」，再以 "suddd" 觸發（誤鍵前的 ㄋㄧ 進入 stash）。
    typeSentence("su3")
    typeSentence("su")
    typeSentence("ddd")
    #expect(testHandler.isAutoEnglishModeActive)

    // 進入模式時，組字區顯示「先前的組字內容 + 英數暫存內容」，與鍵入順序一致。
    #expect(testSession.state.data.displayedText == "你suddd")

    // 閒置退出：組字器內容（你）先於英數暫存內容（suddd）一併遞交（順序須與鍵入順序一致，
    // 不可變成「suddd你」）、注拼槽 stash（ㄋㄧ）不還原（避免誤鍵殘留干擾），
    // 本次按鍵 "c"（ㄏ）以中文模式重新分診。
    testHandler.autoEnglishMode?.lastActivityDate = Date(timeIntervalSinceNow: -10)
    typeSentence("c")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions == ["你suddd"])
    #expect(testHandler.assembler.isEmpty)
    #expect(testHandler.composer.consonant.value == "ㄏ")
    #expect(testHandler.composer.semivowel.isEmpty)
  }

  // MARK: - 門檻未滿前不得干擾中文注拼流程（純觀測）

  @Test
  func test_AutoSwitchOnConsecutiveErrors_OutOfOrderPhonabetsStillReachComposer() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // 先誤鍵 "j"（ㄨ）再鍵入 "n"（ㄙ）：注拼槽會自動校正為 ㄙㄨ，屬合法音節，
    // 不得判定為誤鍵、更不得吞掉按鍵或清空注拼槽。
    typeSentence("jn")
    #expect(testHandler.composer.consonant.value == "ㄙ")
    #expect(testHandler.composer.semivowel.value == "ㄨ")
    #expect(testHandler.consecutiveTypingErrors.count < 2)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.data.displayedText == "ㄙㄨ")

    // 續鍵 "."（ㄡ）：ㄙㄨㄡ 非合法音節，屬誤鍵；但門檻未滿，按鍵仍應照常流入注拼槽，
    // 組字區所見即注拼槽實際內容（不得殘留過時顯示）。
    typeSentence(".")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(!testHandler.composer.isEmpty)
    #expect(testSession.state.data.displayedText == testHandler.composer.getComposition())
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_BackSpaceAfterTypoResetsAndAllowsRetry() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // 使用者情境：想打「搜」（n. ），卻先誤鍵了 "j"（ㄨ）。
    typeSentence("jn. ")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.assembler.isEmpty)

    // BackSpace：一律重置誤鍵計數（不得計入連續誤鍵門檻）、並照常刪除注拼槽內容。
    _ = testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent)
    #expect(testHandler.consecutiveTypingErrors.isEmpty)
    #expect(testHandler.inFlightComposerKeys.isEmpty)
    #expect(testHandler.autoEnglishChineseStash == nil)
    while !testHandler.composer.isEmpty {
      _ = testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent)
    }

    // 重打 "n. " → 「搜」。
    typeSentence("n. ")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "搜")
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_RetryAfterFailedCompositionIsNotPunished() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // "jn. " 組不出讀音（注拼槽依偏好預設值自動清空）後，使用者未按 BackSpace 直接重打 "n. "：
    // 重打的每一鍵都是合法的注音續鍵，不得因先前殘留的誤鍵計數而被推入英數暫存模式。
    typeSentence("jn. ")
    #expect(!testHandler.isAutoEnglishModeActive)
    typeSentence("n. ")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "搜")
  }

  // MARK: - 正常輸入不觸發

  @Test
  func test_AutoSwitchOnConsecutiveErrors_NormalChineseTypingUntouched() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // 正常輸入注音："su3" -> "你" (3聲)
    typeSentence("su3")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(!testSession.isASCIIMode)
    #expect(testHandler.consecutiveTypingErrors.isEmpty)
    #expect(testHandler.inFlightComposerKeys.isEmpty)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "你")
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_LeftBracketInputsFullWidthBracket() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    let leftBracketEvent = KBEvent.KeyEventData(chars: "[", keyCode: 33).asEvent
    let leftHandled = testHandler.triageInput(event: leftBracketEvent)
    #expect(leftHandled == true)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "「")

    let rightBracketEvent = KBEvent.KeyEventData(chars: "]", keyCode: 30).asEvent
    let rightHandled = testHandler.triageInput(event: rightBracketEvent)
    #expect(rightHandled == true)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "「」")
    #expect(!testHandler.isAutoEnglishModeActive)
  }

  // MARK: - 誤鍵暫存重置

  @Test
  func test_AutoSwitchOnConsecutiveErrors_BackSpaceClearsErrorBuffer() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // Type 4 consecutive errors: "grea"
    typeSentence("grea")
    #expect(testHandler.consecutiveTypingErrors.count == 4)
    #expect(!testHandler.isAutoEnglishModeActive)

    // Press BackSpace
    _ = testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent)
    #expect(testHandler.consecutiveTypingErrors.isEmpty)

    // Type 2 more errors: "ts"
    typeSentence("ts")
    #expect(testHandler.consecutiveTypingErrors.count == 2)
    #expect(!testHandler.isAutoEnglishModeActive)
  }

  // MARK: - 偏好開關與模式排除

  @Test
  func test_AutoSwitchOnConsecutiveErrors_DisabledPreference() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = false
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.isASCIIMode == false)
    #expect(testSession.recentCommissions.isEmpty)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_SimplifiedChineseModeIgnored() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHS
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.isASCIIMode == false)
    #expect(testSession.recentCommissions.isEmpty)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_PinyinModeIgnored() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.composer.ensureParser(arrange: .ofHanyuPinyin)

    typeSentence("great")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.isASCIIMode == false)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_MixedAlphanumericalIgnored() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.isASCIIMode == false)
  }

  // MARK: - 自訂門檻

  @Test
  func test_AutoSwitchOnConsecutiveErrors_CustomThreshold() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testHandler.prefs.consecutiveTypingErrorsThreshold = 3
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)
    defer { testHandler.prefs.consecutiveTypingErrorsThreshold = 5 }

    // "git" with threshold = 3 should trigger switch on 3 keys
    typeSentence("git")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "git")
    #expect(testSession.recentCommissions.isEmpty)
  }

  // MARK: - IMK 強制遞交場景（commitComposition 等）

  @Test
  func test_AutoSwitchOnConsecutiveErrors_CommittableTextIncludesEnglishBuffer() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    typeSentence("great")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.committableDisplayText() == "great")

    // 模擬 IMK 強制遞交（如客體失焦）：英數暫存內容一併遞交、模式結束。
    testSession.resetInputHandler(forceComposerCleanup: true)
    #expect(testSession.recentCommissions == ["great"])
    #expect(!testHandler.isAutoEnglishModeActive)
  }

  // MARK: - 遞交順序：先前的中文組字內容必須排在英數暫存內容之前

  @Test
  func test_AutoSwitchOnConsecutiveErrors_LeadingUpperCaseLetterKeepsTypingOrder() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    // 「Claude」：Shift+C 依 upperCaseLetterKeyBehavior 預設值直接塞入組字區，
    // 其後的 "laude" 滿門檻觸發英數暫存模式。組字區顯示與遞交結果都必須是「Claude」，
    // 而非把先鍵入的 "C" 排到後面的「laudeC」。
    let capitalC = KBEvent.KeyEventData(
      flags: [.shift],
      chars: "C",
      charsSansModifiers: "c",
      keyCode: mapKeyCodesANSIForTests["c"]
    ).asEvent
    _ = testHandler.triageInput(event: capitalC)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "C")

    typeSentence("laude")
    #expect(testHandler.isAutoEnglishModeActive)
    #expect(testHandler.autoEnglishMode?.buffer == "laude")
    #expect(testSession.state.data.displayedText == "Claude")
    #expect(testHandler.committableDisplayText() == "Claude")

    // Enter 遞交：一次性遞交「Claude」，且組字器不得殘留先前的 "C"。
    let enterHandled = testHandler.triageInput(
      event: KBEvent.KeyEventData(chars: "\u{0D}", keyCode: KeyCode.kCarriageReturn.rawValue).asEvent
    )
    #expect(enterHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions == ["Claude"])
    #expect(testHandler.assembler.isEmpty)
  }

  @Test
  func test_AutoSwitchOnConsecutiveErrors_EscExitRestoresLeadingUpperCaseLetter() throws {
    guard let testHandler, let testSession else {
      Issue.record("Test handler or session is nil.")
      return
    }
    testHandler.prefs.autoSwitchToAlphanumericalOnConsecutiveErrors = true
    testSession.inputMode = .imeModeCHT
    testSession.isASCIIMode = false
    testSession.recentCommissions.removeAll()
    testHandler.autoEnglishMode = nil
    testHandler.autoEnglishChineseStash = nil
    testSession.resetInputHandler(forceComposerCleanup: true)

    let capitalC = KBEvent.KeyEventData(
      flags: [.shift],
      chars: "C",
      charsSansModifiers: "c",
      keyCode: mapKeyCodesANSIForTests["c"]
    ).asEvent
    _ = testHandler.triageInput(event: capitalC)
    typeSentence("laude")
    #expect(testHandler.isAutoEnglishModeActive)

    // Esc 棄置英數暫存內容：先前塞入組字區的 "C" 必須原樣還原、且全程未遞交。
    let escHandled = testHandler.triageInput(
      event: KBEvent.KeyEventData(chars: "\u{1b}", keyCode: KeyCode.kEscape.rawValue).asEvent
    )
    #expect(escHandled)
    #expect(!testHandler.isAutoEnglishModeActive)
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.assembler.assembledSentence.values.joined() == "C")
  }
}