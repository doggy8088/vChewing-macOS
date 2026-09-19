// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation

// MARK: - 智慧中英輸入自動切換（Smart ZH-EN Auto-Switch）

/// 該檔案實作「智慧中英輸入自動切換」：使用者常態停留於唯音的中文模式，
/// 唯音自行辨識「這串按鍵其實是英文」並就地轉為英文輸出，不必切換到 ABC。
///
/// 觸發條件（僅在 `.ofEmpty` / `.ofInputting` 狀態、注音鍵盤語境下生效）：
/// - Tab：無條件把當前輸入鍵序列轉為英文並將 Tab 放行給客體（自動完成）。
/// - Space：輸入鍵序列被判定為「不合理的中文輸入順序」時，轉為英文並附帶半形空格。
/// - 路徑／URL 前綴：序列開頭兩鍵皆為 `.`,`/`,`~`,`\` 時（`./`、`../`、`~/`……）立即轉英。
/// - 連續誤鍵：逐鍵累計的誤鍵數達門檻時立即轉英（不必等待 Space／Tab 斷點）。
///
/// 進入「英數暫存模式」後不離開唯音：
/// - 可列印 ASCII 一律原樣遞交（含大寫與空格）。
/// - BackSpace 放行給客體刪除；連續 3 次則取消模式並還原觸發前的注音組字進度。
/// - Enter / Esc 結束模式；閒置逾時自動回到中文模式；其餘按鍵放行、維持模式。
extension InputHandlerProtocol {
  // MARK: - 常數

  /// 連續 BackSpace 觸發「取消英數暫存模式」所需的次數。
  public static var smartEnglishBackspaceCancellationCount: Int { 3 }

  // MARK: - 狀態查詢

  /// 當前是否處於英數暫存模式。
  public var isSmartEnglishModeActive: Bool { smartEnglishContext.mode != nil }

  /// 當前輸入鍵序列。
  public var smartEnglishKeyTrail: [String] { smartEnglishContext.keyTrail }

  /// 連續誤鍵次數。
  public var smartEnglishConsecutiveTypingErrors: Int { smartEnglishContext.consecutiveTypingErrorCount }

  /// 觸發自動轉英所需的連續誤鍵次數（偏好設定值夾限於 3...8）。
  public var smartEnglishErrorThreshold: Int {
    Swift.min(8, Swift.max(3, prefs.smartEnglishAutoSwitchErrorThreshold))
  }

  /// 閒置逾時秒數（由偏好設定之毫秒值換算；下限 50 ms 以防設定值失效）。
  public var smartEnglishIdleTimeoutSeconds: Double {
    Swift.max(0.05, Double(prefs.smartEnglishAutoSwitchIdleTimeoutMS) / 1000)
  }

  /// 智慧中英自動切換是否適用於當前語境。
  ///
  /// MVP 僅涵蓋注音鍵盤（`vChewingFactory` ＋ 非拼音、非磁帶、非中英混打、非英數模式）。
  /// 拼音鍵盤與狂拼另有自身機制，磁帶與中英混打亦不在本功能語義內。
  public var isSmartEnglishAutoSwitchApplicable: Bool {
    guard prefs.smartEnglishAutoSwitchEnabled, let session else { return false }
    guard currentTypingMethod == .vChewingFactory else { return false }
    guard !prefs.mixedAlphanumericalEnabled, !prefs.cassetteEnabled else { return false }
    guard !isPinyinFamilyTypingMode else { return false }
    guard !session.isASCIIMode else { return false }
    return true
  }

  // MARK: - 狀態重設

  /// 清空輸入鍵序列（組字內容被遞交時呼叫）並歸零連續誤鍵計次與標點歸屬。
  public func resetSmartEnglishKeyTrail() {
    smartEnglishContext.keyTrail.removeAll()
    smartEnglishContext.lastKnownComposerWasNonEmpty = false
    smartEnglishContext.consecutiveTypingErrorCount = 0
    smartEnglishContext.analyzedViolationCount = 0
    smartEnglishContext.trailOwnedPunctuations.removeAll()
  }

  /// 重設智慧中英自動切換的所有暫態（含進行中的英數暫存模式）。
  public func resetSmartEnglishAutoSwitchState() {
    smartEnglishContext.mode = nil
    resetSmartEnglishKeyTrail()
  }

  // MARK: - 分診入口

  /// 智慧中英自動切換的分診入口（由 `triageInput(event:)` 於 `.ofEmpty` / `.ofInputting` 狀態呼叫）。
  /// - Parameter input: 輸入按鍵訊號。
  /// - Returns: `nil`：不攔截、續走既有分診；`true`：本拍按鍵已被本功能消費；
  ///   `false`：本拍按鍵放行給客體應用、不再分診。
  public func handleSmartEnglishAutoSwitch(input: some InputSignalProtocol) -> Bool? {
    guard isSmartEnglishAutoSwitchApplicable else { return nil }

    // 英數暫存模式中：由模式專屬分診接管。該分診若回傳 `nil`（含因閒置逾時而結束模式），
    // 本拍按鍵即等同中文模式下的新按鍵——必須照常記入輸入鍵序列，否則該鍵不會被視為
    // 「同一批按鍵」（實機案例：`https` → 閒置逾時 → `:` 併成全形 `：` 卻無紀錄）。
    if smartEnglishContext.mode != nil {
      guard let modeResult = handleSmartEnglishModeInput(input: input) else {
        return handleSmartEnglishChineseModeInput(input: input)
      }
      return modeResult
    }

    return handleSmartEnglishChineseModeInput(input: input)
  }

  /// 中文模式下的鍵入分診（含各種自動轉英觸發判定）。
  /// - Parameter input: 輸入按鍵訊號。
  /// - Returns: `nil`：不攔截、續走既有分診；`true`：本拍按鍵已被本功能消費；
  ///   `false`：本拍按鍵放行給客體應用、不再分診。
  func handleSmartEnglishChineseModeInput(input: some InputSignalProtocol) -> Bool? {
    // 對帳：注拼槽若已在別處被固化／清空，序列即失效。
    reconcileSmartEnglishKeyTrail()

    // Tab：無條件把輸入鍵序列轉為英文，並將 Tab 放行給客體（自動完成）。
    if input.isTab, !input.isHoldingAny([.command, .control, .option]) {
      guard !smartEnglishContext.keyTrail.isEmpty else { return nil }
      vCLog("SmartEnglish: Tab trigger; trail=\(smartEnglishContext.keyTrail.joined())")
      triggerSmartEnglishMode(appendingSpace: false)
      return false
    }

    // Space：輸入鍵序列不合理時轉為英文並附帶半形空格。
    if input.isSpace, !input.isHoldingAny([.command, .control, .option]) {
      let analysis = analyzeSmartEnglishKeyTrail()
      // 序列中連一個注音鍵都沒有時（例如單引號類標點）不視為英文，維持既有標點行為。
      if analysis.containsZhuyinKey, analysis.containsViolation {
        let trailJoined = smartEnglishContext.keyTrail.joined()
        vCLog("SmartEnglish: Space trigger; trail=\(trailJoined)")
        triggerSmartEnglishMode(appendingSpace: true)
        return true
      }
    }

    // BackSpace：尚未輸出英文前的退格＝使用者想打中文、只是打錯鍵，連續誤鍵計次歸零
    // （序列本身的既有違規量維持對帳基準，避免退格後重複計入先前的違規）。
    if input.isBackSpace {
      smartEnglishContext.consecutiveTypingErrorCount = 0
      recordSmartEnglishKeyTrailKey(input: input)
      smartEnglishContext.analyzedViolationCount = analyzeSmartEnglishKeyTrail().violationCount
      return nil
    }

    recordSmartEnglishKeyTrailKey(input: input)

    // 路徑／URL 前綴：序列開頭兩鍵皆為路徑特徵字元（`.`, `/`, `~`, `\`）時，明顯不是中文
    // 輸入順序（例：`./`、`../`、`~/`、`//`），不必等待誤鍵門檻即整段轉英。
    if isSmartEnglishObviousPathPrefix {
      let trailJoined = smartEnglishContext.keyTrail.joined()
      vCLog("SmartEnglish: path prefix trigger; trail=\(trailJoined)")
      triggerSmartEnglishMode(appendingSpace: false)
      return true
    }

    // 連續誤鍵達門檻時自動轉英（適用於「所有輸入鍵都是合理按鍵、但輸入順序不合理」的情形）。
    if accountSmartEnglishTypingErrors() { return true }

    return nil
  }

  /// 路徑／URL 特徵字元：中文輸入幾乎不可能以這些字元連打作為序列開頭。
  ///
  /// 僅收 `.`（ㄡ）與 `/`（ㄥ）兩個鍵：前者是相對路徑的起手式，後者是絕對路徑與 URL 的標記。
  /// 註：`~` 在唯音既有語義中是標點別名鍵（會就地併成 `～` 並自序列移除），故不列於此。
  static var smartEnglishPathMarkerKeys: Set<String> { [".", "/"] }

  /// 輸入鍵序列的開頭兩鍵是否皆為路徑特徵字元（`./`、`../`、`//` 等）。
  ///
  /// 判定只看序列**開頭**：這類前綴一旦出現即無疑是英文（相對路徑、URL 等），
  /// 而注音語境下兩者互相覆寫（`.`,`/` ＝ ㄡ、ㄥ）也只會使先前的按鍵白打，故直接轉英並無損失。
  /// 註：不採「結尾兩鍵」判定，因為那會誤傷正常中文（例如 `ㄓㄨㄥ` 之後改韻母）。
  var isSmartEnglishObviousPathPrefix: Bool {
    let trail = smartEnglishContext.keyTrail
    guard trail.count >= 2 else { return false }
    return trail.prefix(2).allSatisfy(Self.smartEnglishPathMarkerKeys.contains)
  }

  /// 逐鍵累計「連續誤鍵」次數；達門檻時直接轉為英文輸出。
  /// - Returns: 是否已因而進入英數暫存模式（是的話呼叫端應消費本拍按鍵）。
  func accountSmartEnglishTypingErrors() -> Bool {
    let analysis = analyzeSmartEnglishKeyTrail()
    let delta = analysis.violationCount - smartEnglishContext.analyzedViolationCount
    if delta > 0 { smartEnglishContext.consecutiveTypingErrorCount += delta }
    smartEnglishContext.analyzedViolationCount = analysis.violationCount
    let threshold = smartEnglishErrorThreshold
    guard smartEnglishContext.consecutiveTypingErrorCount >= threshold,
          !smartEnglishContext.keyTrail.isEmpty else { return false }
    let trailJoined = smartEnglishContext.keyTrail.joined()
    vCLog("SmartEnglish: consecutive typing errors reached \(threshold); trail=\(trailJoined)")
    triggerSmartEnglishMode(appendingSpace: false)
    return true
  }

  /// 分析當前輸入鍵序列是否為合理的中文輸入順序。
  func analyzeSmartEnglishKeyTrail() -> SmartEnglishTrailAnalysis {
    SmartEnglishTrailAnalyzer.analyze(
      keyTrail: smartEnglishContext.keyTrail,
      parser: composer.parser
    )
  }
}

// MARK: - 英數暫存模式

extension InputHandlerProtocol {
  /// 英數暫存模式期間的鍵入分診。
  /// - Parameter input: 輸入按鍵訊號。
  /// - Returns: 告知 IMK「該按鍵是否已經被輸入法攔截處理」。
  func handleSmartEnglishModeInput(input: some InputSignalProtocol) -> Bool? {
    guard let session, var mode = smartEnglishContext.mode else {
      smartEnglishContext.mode = nil
      return nil
    }
    let now = Date()

    /// 刷新活動時間（預設同時歸零連續 BackSpace 計數），寫回模式狀態之後回傳給定結果。
    func touchAndReturn(_ result: Bool?, resetBackSpaces: Bool = true) -> Bool? {
      mode.lastActivityDate = now
      if resetBackSpaces { mode.consecutiveBackSpaceCount = 0 }
      smartEnglishContext.mode = mode
      return result
    }

    // 閒置逾時：結束模式，並讓本拍按鍵改以中文流程續審。
    if now.timeIntervalSince(mode.lastActivityDate) >= smartEnglishIdleTimeoutSeconds {
      exitSmartEnglishMode(restoreChineseComposition: false)
      return nil
    }

    // Enter / Esc：結束本段英數輸入（按鍵放行給客體）。
    if input.isEnter || input.isEsc {
      exitSmartEnglishMode(restoreChineseComposition: false)
      return false
    }

    // BackSpace：放行給客體刪除；連續 3 次則取消模式並還原中文組字進度。
    // （逾時檢查已在上方處理，故此處可安心累計連續次數。）
    if input.isBackSpace {
      mode.consecutiveBackSpaceCount += 1
      mode.lastActivityDate = now
      smartEnglishContext.mode = mode
      if mode.consecutiveBackSpaceCount >= Self.smartEnglishBackspaceCancellationCount {
        vCLog("SmartEnglish: three consecutive backspaces; cancel English mode.")
        exitSmartEnglishMode(restoreChineseComposition: true)
      }
      return false
    }

    // Command / Control / Option 組合鍵：一律放行給客體快捷鍵、維持模式。
    if input.isHoldingAny([.command, .control, .option]) {
      return touchAndReturn(false)
    }

    // Tab：放行給客體（自動完成）、維持模式。
    if input.isTab {
      return touchAndReturn(false)
    }

    // 可列印 ASCII：原樣遞交（含大寫與空格），維持模式。
    if input.charCode.isPrintableASCII, !input.text.isEmpty {
      _ = touchAndReturn(nil)
      session.switchState(State.ofCommitting(textToCommit: input.text))
      return true
    }

    // 其餘（方向鍵、翻頁鍵、功能鍵等）：維持模式，續走既有分診。
    return touchAndReturn(nil)
  }

  /// 觸發英數暫存模式：遞交既有中文內容與輸入鍵序列（可附加半形空格），再進入模式。
  /// - Parameter appendingSpace: 是否在遞交的英文內容之後附加一個半形空格。
  func triggerSmartEnglishMode(appendingSpace: Bool) {
    guard let session else { return }
    let rawChineseText = committableDisplayText(sansReading: true)
    let chineseText = sanitizedChinesePrefixForSmartEnglish(
      rawChineseText,
      trail: smartEnglishContext.keyTrail
    )
    let englishText = smartEnglishContext.keyTrail.joined()
    let snapshot = SmartEnglishModeState.ChineseCompositionSnapshot(
      composer: composer,
      keyTrail: smartEnglishContext.keyTrail
    )
    composer.clear()
    calligrapher.removeAll()
    assembler.clear()
    smartEnglishContext.keyTrail.removeAll()
    smartEnglishContext.lastKnownComposerWasNonEmpty = false
    smartEnglishContext.consecutiveTypingErrorCount = 0
    smartEnglishContext.analyzedViolationCount = 0
    smartEnglishContext.trailOwnedPunctuations.removeAll()
    smartEnglishContext.mode = .init(
      lastActivityDate: .init(),
      consecutiveBackSpaceCount: 0,
      restoreSnapshot: snapshot
    )
    let textToCommit = chineseText + englishText + (appendingSpace ? " " : "")
    guard !textToCommit.isEmpty else { return }
    vCLog("SmartEnglish: commit \(textToCommit.debugDescription) and enter English mode.")
    session.switchState(State.ofCommitting(textToCommit: textToCommit))
  }

  /// 退出英數暫存模式。
  /// - Parameter restoreChineseComposition: 是否還原觸發前的注音組字進度（供連續 BackSpace 取消使用）。
  public func exitSmartEnglishMode(restoreChineseComposition: Bool) {
    guard let mode = smartEnglishContext.mode else { return }
    smartEnglishContext.mode = nil
    // 組字器已於觸發時清空（且觸發時的標點已隨中文前綴遞交），故標點歸屬一併失效。
    smartEnglishContext.trailOwnedPunctuations.removeAll()
    vCLog("SmartEnglish: exit English mode; restore=\(restoreChineseComposition).")
    guard restoreChineseComposition, let session else { return }
    composer = mode.restoreSnapshot.composer
    smartEnglishContext.keyTrail = mode.restoreSnapshot.keyTrail
    smartEnglishContext.lastKnownComposerWasNonEmpty = !composer.isEmpty
    guard !isComposerOrCalligrapherEmpty else { return }
    session.switchState(generateStateOfInputting(guarded: true))
  }

  /// 觸發轉英時，自中文前綴尾端處理「其實出自同一批按鍵」的標點。
  ///
  /// 兩道判定：
  /// 1. 前綴尾端若為 `trailOwnedPunctuations` 的連續串（先前由序列中的按鍵產生、且已自序列移除，
  ///    例如 `:` 於併成全形 `：` 時）→ 整段改以半形保留（不殘留全形）；該半形字元若已由序列
  ///    承擔輸出，則整段剔除（不重複）。
  /// 2. 其餘「半形對應字元仍在輸入鍵序列中」的尾端全形字元 → 自前綴剔除（由序列輸出半形）。
  ///
  /// 註：僅在「該字元確實是序列自身產生」、或「其半形對應字元存在於序列中」時才處理，
  /// 故不影響先前正常輸入的中文標點。
  func sanitizedChinesePrefixForSmartEnglish(_ prefix: String, trail: [String]) -> String {
    let trailJoined = trail.joined()
    var result = prefix
    // 判定 1：序列自產標點者，自前綴尾端整段取出後改寫為半形（或整段剔除）。
    var trailOwnedRun: [String] = []
    for owned in smartEnglishContext.trailOwnedPunctuations.reversed() {
      guard result.hasSuffix(owned) else { break }
      trailOwnedRun.insert(owned, at: 0)
      result.removeLast(owned.count)
    }
    for owned in trailOwnedRun {
      guard let halfWidthOwned = owned.halfWidthFormIfConvertible else {
        result += owned
        continue
      }
      result += trailJoined.contains(halfWidthOwned) ? "" : halfWidthOwned
    }
    // 判定 2：序列自身已承擔輸出者，自前綴剔除。
    while let lastCharacter = result.last {
      let lastString = String(lastCharacter)
      guard let halfWidthForm = lastString.halfWidthFormIfConvertible,
            trailJoined.contains(halfWidthForm) else { break }
      result.removeLast()
    }
    return result
  }

  /// 記錄「剛被併入組字器的標點其實出自輸入鍵序列」，並將該按鍵自輸入鍵序列移除。
  ///
  /// 標點輸入是正常的中文輸入、不是誤鍵：該按鍵的輸出既已由中文端（組字器）承擔，
  /// 就不該再計為誤鍵、也不該重複出現在英文輸出中。實機案例：以 `<` 鍵輸入「，」後
  /// 續打「終於」時，`<` 被視為無效鍵而累計誤鍵，導致按空白鍵（一聲）即誤轉英文。
  /// - Parameters:
  ///   - insertedKey: 併入組字器的鍵名（例如 `_punctuation_Standard_<`）。
  ///   - displayedPunctuation: 該標點在組字區的顯示字元（例如全形 `，`）。
  func noteSmartEnglishTrailOwnedPunctuation(insertedKey: String, displayedPunctuation: String?) {
    guard isSmartEnglishAutoSwitchApplicable else { return }
    guard let displayedPunctuation, !displayedPunctuation.isEmpty else { return }
    guard !smartEnglishContext.keyTrail.isEmpty else { return }
    smartEnglishContext.trailOwnedPunctuations.append(displayedPunctuation)
    // `_letter_` 開頭者為 Shift+字母的字母插入（其輸出屬「中英混打」語義），不在此列。
    guard !insertedKey.hasPrefix("_letter_") else { return }
    guard let lastKey = smartEnglishContext.keyTrail.last,
          insertedKey.hasSuffix(lastKey) else { return }
    let violationsBefore = analyzeSmartEnglishKeyTrail().violationCount
    smartEnglishContext.keyTrail.removeLast()
    let violationsAfter = analyzeSmartEnglishKeyTrail().violationCount
    // 該按鍵先前若曾貢獻誤鍵，一併自連續誤鍵計次中扣除（標點不是誤鍵）。
    let removedViolations = Swift.max(0, violationsBefore - violationsAfter)
    smartEnglishContext.consecutiveTypingErrorCount = Swift.max(
      0, smartEnglishContext.consecutiveTypingErrorCount - removedViolations
    )
    smartEnglishContext.analyzedViolationCount = violationsAfter
    vCLog(
      "SmartEnglish: punctuation \(displayedPunctuation) owned by trail; key \(insertedKey) removed."
    )
  }

  /// 對帳：注拼槽內容若已在別處被固化／清空，輸入鍵序列即失效、連續誤鍵計次一併歸零
  /// （組字內容成功成文＝確為中文打字）。
  func reconcileSmartEnglishKeyTrail() {
    if composer.isEmpty, smartEnglishContext.lastKnownComposerWasNonEmpty {
      vCLog("SmartEnglish: trail invalidated (composer flushed elsewhere); trail=\(smartEnglishContext.keyTrail.joined())")
      smartEnglishContext.keyTrail.removeAll()
      smartEnglishContext.consecutiveTypingErrorCount = 0
      smartEnglishContext.analyzedViolationCount = 0
    }
    smartEnglishContext.lastKnownComposerWasNonEmpty = !composer.isEmpty
  }

  /// 記錄輸入鍵序列（僅記錄無 Command/Control/Option 修飾的可列印 ASCII 鍵；
  /// BackSpace 則回退一格）。
  ///
  /// 註：空格鍵本身是觸發／斷句鍵、永不計入序列。
  func recordSmartEnglishKeyTrailKey(input: some InputSignalProtocol) {
    if input.isBackSpace {
      if !smartEnglishContext.keyTrail.isEmpty { smartEnglishContext.keyTrail.removeLast() }
      return
    }
    guard !input.isSpace else { return }
    guard !input.isHoldingAny([.command, .control, .option]) else { return }
    guard input.charCode.isPrintableASCII, !input.text.isEmpty else { return }
    smartEnglishContext.keyTrail.append(input.text)
  }
}

// MARK: - 內部輔助

private extension String {
  /// 該字串的半形對應形式；若該字串本身即無全形變化（例如漢字），則回傳 `nil`。
  var halfWidthFormIfConvertible: String? {
    let halfWidth = applyingTransformFW2HW(reverse: false)
    guard halfWidth != self, !halfWidth.isEmpty else { return nil }
    return halfWidth
  }
}
