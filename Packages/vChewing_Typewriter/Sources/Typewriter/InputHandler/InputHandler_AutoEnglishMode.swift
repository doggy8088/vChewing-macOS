// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation

// MARK: - 連續誤鍵自動切換的「英數暫存輸入模式」

/// 中文打字進度快照：記錄連續誤鍵觸發英數暫存模式之前的中文組字進度，供切回中文時還原。
public struct ChineseTypingSnapshot {
  // MARK: Lifecycle

  public init(
    composer: Tekkon.Composer, inFlightComposerKeys: [String], assemblerSnapshot: Homa.Assembler?
  ) {
    self.composer = composer
    self.inFlightComposerKeys = inFlightComposerKeys
    self.assemblerSnapshot = assemblerSnapshot
  }

  // MARK: Public

  /// 快照當下的注拼槽內容（含尚未拼裝完成的讀音）。
  public let composer: Tekkon.Composer
  /// 與注拼槽內容對應的原始鍵入字元序列。
  public let inFlightComposerKeys: [String]
  /// 組字器深拷貝快照。nil 表示快照當時組字器為空。
  public let assemblerSnapshot: Homa.Assembler?
}

/// 連續誤鍵自動切換後的英數暫存輸入模式狀態。
///
/// 該模式全程不離開唯音、亦不切換系統輸入法：英數鍵入內容先暫存在組字區
/// （不立即遞交），直到使用者以熱鍵切回中文（並還原中文輸入進度）、
/// 閒置超過指定秒數自動遞交並返回中文、或以 Enter / Tab 主動遞交為止。
public struct AutoEnglishModeState {
  // MARK: Lifecycle

  public init(
    buffer: String,
    chinesePrefix: String = "",
    lastActivityDate: Date,
    chineseSnapshot: ChineseTypingSnapshot,
    idleTask: Task<Void, Never>? = nil
  ) {
    self.buffer = buffer
    self.chinesePrefix = chinesePrefix
    self.lastActivityDate = lastActivityDate
    self.chineseSnapshot = chineseSnapshot
    self.idleTask = idleTask
  }

  // MARK: Public

  /// 英數暫存內容（對應組字區顯示、尚未遞交給客體應用）。
  public var buffer: String
  /// 進入本模式之前就已存在於組字區、且尚未遞交的內容（中文字詞、Shift+字母鍵塞入的大寫字母等）。
  ///
  /// 該內容的鍵入時間早於英數暫存內容，故無論顯示或遞交都必須排在 `buffer` 之前，
  /// 否則會出現「鍵入 `Claude` 卻得到 `laudeC`」這類順序顛倒的結果。
  public var chinesePrefix: String
  /// 最近一次鍵入活動時間（閒置判定基準）。
  public var lastActivityDate: Date
  /// 觸發自動切換時的中文打字進度快照。
  public var chineseSnapshot: ChineseTypingSnapshot
  /// 閒置自動返回中文的排程任務（僅生產環境使用；單元測試以事件驅動的懶惰閒置檢查為準）。
  public var idleTask: Task<Void, Never>?

  /// 組字區應顯示（並於遞交時輸出）的完整內容：先前的組字區內容 + 英數暫存內容。
  public var displayText: String { chinesePrefix + buffer }
}

// MARK: - 模式進出與鍵入處理

extension InputHandlerProtocol {
  /// 當前是否處於連續誤鍵觸發的英數暫存輸入模式。
  public var isAutoEnglishModeActive: Bool { autoEnglishMode != nil }

  /// 退出熱鍵的人類可讀名稱（用於通知與工具提示）。
  public var autoEnglishExitHotkeyLabel: String {
    switch prefs.autoSwitchedEnglishModeExitHotkey {
    case 1: "⌃Space"
    case 2: "⌥Enter"
    case 3: "⌃Enter"
    default: "Esc"
    }
  }

  /// 英數暫存模式的說明文字（供通知與組字區工具提示使用）。
  public var autoEnglishModeDescriptionMessage: String {
    var lines = ["i18n:InfoMessage.AutoSwitchedEnglishModeEntered".i18n]
    lines.append(
      String(format: "i18n:InfoMessage.AutoSwitchedEnglishModeReturnHint".i18n, autoEnglishExitHotkeyLabel)
    )
    let idleTimeout = max(0, prefs.autoSwitchedEnglishModeIdleTimeout)
    if idleTimeout > 0 {
      lines.append(
        String(format: "i18n:InfoMessage.AutoSwitchedEnglishModeIdleHint".i18n, "\(idleTimeout)")
      )
    }
    return lines.joined(separator: "\n")
  }

  /// 進入英數暫存輸入模式：不遞交、不切換系統輸入法，英數內容先暫存於組字區，
  /// 同時快照中文輸入進度供之後還原。
  /// - Parameter session: 委任會話。
  /// - Returns: 恒為 true（該觸發鍵已被本模式消費）。
  @discardableResult
  public func enterAutoEnglishMode(session: Session) -> Bool {
    let textToBuffer = consecutiveTypingErrors.joined()
    let assemblerSnapshot = assembler.isEmpty ? nil : assembler.copy
    // 先於清空組字器之前擷取「既有組字區內容」的可遞交文字。該內容鍵入時間早於英數暫存內容，
    // 之後無論顯示或遞交都得排在英數暫存內容前面。
    // （注拼槽的未完成讀音已在誤鍵折入時計入 consecutiveTypingErrors，故此處 sansReading。）
    let chinesePrefix = assembler.isEmpty ? "" : committableDisplayText(sansReading: true)
    let stash = autoEnglishChineseStash
    autoEnglishChineseStash = nil
    consecutiveTypingErrors.removeAll()
    inFlightComposerKeys.removeAll()
    composer.clear()
    calligrapher.removeAll()
    assembler.clear()
    // 中文進度快照：注拼槽部分取自誤鍵序列打斷注拼時的暫存（stash）；
    // 組字器部分則於觸發當下深拷貝（誤鍵累積期間組字器處於凍結狀態，觸發時快照即為最新）。
    let chineseSnapshot: ChineseTypingSnapshot
    if let stash {
      chineseSnapshot = .init(
        composer: stash.composer,
        inFlightComposerKeys: stash.inFlightComposerKeys,
        assemblerSnapshot: assemblerSnapshot
      )
    } else {
      chineseSnapshot = .init(
        composer: composer,
        inFlightComposerKeys: [],
        assemblerSnapshot: assemblerSnapshot
      )
    }
    autoEnglishMode = .init(
      buffer: textToBuffer,
      chinesePrefix: chinesePrefix,
      lastActivityDate: .init(),
      chineseSnapshot: chineseSnapshot
    )
    scheduleAutoEnglishIdleReturn()
    var displayState = generateStateOfInputting(guarded: true)
    displayState.tooltip = autoEnglishModeDescriptionMessage
    displayState.tooltipDuration = 2.0
    session.switchState(displayState)
    notificationCallback?(autoEnglishModeDescriptionMessage)
    return true
  }

  /// 退出英數暫存輸入模式。
  /// - Parameters:
  ///   - commitEnglishBuffer: 是否將英數暫存內容遞交給客體應用（false = 棄置）。
  ///     遞交時會連同進入本模式之前既有的組字區內容一併遞交（且排在前面），
  ///     故該組字區內容不再另行還原；棄置時則反過來還原該組字區內容。
  ///   - restoreComposerStash: 是否還原注拼槽與對應鍵入序列快照（拼到一半的讀音）。
  public func exitAutoEnglishMode(
    commitEnglishBuffer: Bool,
    restoreComposerStash: Bool
  ) {
    guard let mode = autoEnglishMode else { return }
    autoEnglishMode?.idleTask?.cancel()
    autoEnglishMode = nil
    let snapshot = mode.chineseSnapshot
    if commitEnglishBuffer {
      // 遞交順序必須與鍵入順序一致：先前的組字區內容在前、英數暫存內容在後。
      // 若改成「先遞交英數內容、再還原組字器」的話，先鍵入的內容反而會後遞交
      // （例如鍵入 `Claude` 卻得到 `laudeC`）。
      let textToCommit = mode.displayText
      if !textToCommit.isEmpty, let session {
        session.switchState(State.ofCommitting(textToCommit: textToCommit))
      }
    } else if let restoredAssembler = snapshot.assemblerSnapshot {
      // switchState(.ofCommitting) 會觸發 clear() 清空組字器等暫存，
      // 故快照內容一律在該 switchState 之後還原。
      assembler = restoredAssembler
    }
    if restoreComposerStash {
      composer = snapshot.composer
      inFlightComposerKeys = snapshot.inFlightComposerKeys
    }
    if let session {
      // generateStateOfInputting() 在無可顯示內容時會自行回報 ofAbortion()。
      session.switchState(generateStateOfInputting())
    }
  }

  /// 英數暫存輸入模式期間的鍵入分診。僅處理 keyDown 事件
  /// （flagsChanged 事件在會話層即已放行、不會抵達此函式）。
  /// - Parameter input: 輸入訊號。
  /// - Returns: 告知 IMK「該按鍵是否已經被輸入法攔截處理」。
  public func handleAutoEnglishModeInput(input: some InputSignalProtocol) -> Bool {
    guard let session else { return false }

    // 閒置檢查：逾時未鍵入時，先自動遞交英數暫存內容並返回中文模式，
    // 再將本次按鍵交給中文模式重新分診（英數鍵入視為已告一段落）。
    let idleTimeout = max(0, prefs.autoSwitchedEnglishModeIdleTimeout)
    if idleTimeout > 0, let lastActivityDate = autoEnglishMode?.lastActivityDate,
       Date().timeIntervalSince(lastActivityDate) >= Double(idleTimeout) {
      exitAutoEnglishMode(commitEnglishBuffer: true, restoreComposerStash: false)
      return triageInput(event: input)
    }

    // 帶有意義修飾鍵（Shift / Command / Control / Option）的按鍵，除自訂熱鍵外
    // 一律不觸發模式內的特殊按鍵行為（避免攔截客體應用快捷鍵，如 ⌘⏎）。
    let isPlainKey =
      input.keyModifierFlags.intersection([.shift, .command, .control, .option]).isEmpty

    // Esc 恒為退出熱鍵：棄置英數暫存內容、還原中文輸入進度。
    if isPlainKey, input.isEsc {
      exitAutoEnglishMode(commitEnglishBuffer: false, restoreComposerStash: true)
      return true
    }

    // 自訂退出熱鍵（⌃Space / ⌥Enter / ⌃Enter）：行為同 Esc。
    if isAutoEnglishExitHotkey(input) {
      exitAutoEnglishMode(commitEnglishBuffer: false, restoreComposerStash: true)
      return true
    }

    // Enter / Tab：遞交英數暫存內容並返回中文模式。
    // 按鍵由唯音消費、不代客體遞交換行，與既有 Enter 鍵行為一致。
    if isPlainKey, input.isEnter || input.isTab {
      exitAutoEnglishMode(commitEnglishBuffer: true, restoreComposerStash: false)
      return true
    }

    // BackSpace：逐字刪除英數暫存內容；刪到清空時直接返回中文模式並還原中文進度。
    if isPlainKey, input.isBackSpace {
      if var mode = autoEnglishMode, !mode.buffer.isEmpty {
        mode.buffer = String(mode.buffer.dropLast())
        mode.lastActivityDate = .init()
        autoEnglishMode = mode
        if mode.buffer.isEmpty {
          exitAutoEnglishMode(commitEnglishBuffer: false, restoreComposerStash: true)
        } else {
          scheduleAutoEnglishIdleReturn()
          session.switchState(generateStateOfInputting(guarded: true))
        }
        return true
      }
      exitAutoEnglishMode(commitEnglishBuffer: false, restoreComposerStash: true)
      return true
    }

    // 摁住 Command 的組合鍵視為客體應用快捷鍵，直接放行。
    if input.isCommandHeld {
      autoEnglishMode?.lastActivityDate = .init()
      return false
    }

    // 可列印字元：計入英數暫存緩衝區（顯示於組字區、不立即遞交）。
    if !input.text.isEmpty, input.text.count == 1, input.charCode.isPrintableUniChar {
      autoEnglishMode?.buffer += input.text
      autoEnglishMode?.lastActivityDate = .init()
      scheduleAutoEnglishIdleReturn()
      session.switchState(generateStateOfInputting(guarded: true))
      return true
    }

    // 其餘按鍵（方向鍵、翻頁鍵、Ctrl / Option 組合鍵、功能鍵等）一律放行，交由客體應用處理。
    autoEnglishMode?.lastActivityDate = .init()
    return false
  }

  /// 判定輸入訊號是否符合自訂退出熱鍵。
  func isAutoEnglishExitHotkey(_ input: some InputSignalProtocol) -> Bool {
    guard !input.isCommandHeld, !input.isShiftHeld else { return false }
    switch prefs.autoSwitchedEnglishModeExitHotkey {
    case 1: return input.isControlHeld && input.isSpace && !input.isOptionHeld
    case 2: return input.isOptionHeld && input.isEnter && !input.isControlHeld
    case 3: return input.isControlHeld && input.isEnter && !input.isOptionHeld
    default: return false
    }
  }

  /// 排程（或重排程）閒置自動返回中文的任務。
  /// 單元測試環境不排程非同步任務，僅以事件驅動的懶惰閒置檢查為準，確保測試確定性。
  func scheduleAutoEnglishIdleReturn() {
    autoEnglishMode?.idleTask?.cancel()
    let idleTimeout = max(0, prefs.autoSwitchedEnglishModeIdleTimeout)
    guard idleTimeout > 0, autoEnglishMode != nil else { return }
    guard !UserDefaults.pendingUnitTests else { return }
    let seconds = Double(idleTimeout)
    autoEnglishMode?.idleTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      guard !Task.isCancelled else { return }
      guard let self, self.isAutoEnglishModeActive else { return }
      self.exitAutoEnglishMode(commitEnglishBuffer: true, restoreComposerStash: false)
    }
  }
}