// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation

// MARK: - 智慧中英輸入自動切換（Smart ZH-EN Auto-Switch）

/// 英數暫存模式的執行期狀態。
public struct SmartEnglishModeState {
  /// 觸發當下的中文組字進度快照，供「連續 BackSpace 取消」時還原。
  public struct ChineseCompositionSnapshot {
    /// 觸發當下的注拼槽內容。
    public var composer: Tekkon.Composer
    /// 觸發當下的輸入鍵序列。
    public var keyTrail: [String]
  }

  /// 最近一次鍵入活動時間（閒置判定基準）。
  public var lastActivityDate: Date
  /// 連續 BackSpace 計數（鍵入其它按鍵時歸零）。
  public var consecutiveBackSpaceCount: Int
  /// 觸發前的中文組字進度快照。
  public var restoreSnapshot: ChineseCompositionSnapshot
}

/// 智慧中英自動切換的執行期上下文。
public struct SmartEnglishTypingContext {
  /// 自上次組字內容被固化／遞交之後、使用者依序敲下的原始鍵。
  public var keyTrail: [String] = []
  /// 上次分診時，注拼槽內是否有內容（用來偵測注拼槽被別處清空的時機）。
  public var lastKnownComposerWasNonEmpty: Bool = false
  /// 英數暫存模式的執行期狀態；`nil` 表示目前不在該模式內。
  public var mode: SmartEnglishModeState?
}

/// 輸入鍵序列的中文合理性分析結果。
public struct SmartEnglishTrailAnalysis {
  /// 序列中是否至少有一個當前注音排列可吃的注音鍵。
  public var containsZhuyinKey: Bool = false
  /// 序列是否出現「不合理的中文輸入順序」。
  public var containsViolation: Bool = false
}

// MARK: - 輸入鍵序列的中文合理性分析

/// 以注音語法模擬輸入鍵序列，判斷其是否為「合理的中文輸入順序」。
///
/// 判定為不合理的情形（任一成立即算）：
/// 1. 無效鍵：該鍵不是當前注音排列可吃的鍵。
/// 2. 破壞性覆寫：聲母槽已被佔用時又鍵入聲母（`cd` ＝ `ㄏ` 尚未成音節就被 `ㄎ` 覆寫）。
/// 3. 順序倒錯：新鍵的槽位次序早於目前音節已填的最後一個槽位（`ls` ＝ 先韻母 `ㄠ` 再聲母 `ㄋ`）。
/// 4. 無解音節：尚未收束的音節（聲介韻）既非合法國語音節、亦非任何合法音節的前綴（`vi` ＝ `ㄒㄛ`）。
///
/// 註一：介母與韻母的同槽覆寫（例如打錯韻母後直接改按正確韻母）屬常見的中文修正行為，
/// 刻意不視為違規，以免誤判。
/// 註二：聲調鍵視為一個音節的收束點；其後的鍵開始新音節。
enum SmartEnglishTrailAnalyzer {
  static func analyze(
    keyTrail: [String],
    parser: Tekkon.MandarinParser
  )
    -> SmartEnglishTrailAnalysis {
    var result = SmartEnglishTrailAnalysis()
    guard !keyTrail.isEmpty else { return result }
    let allPossibleReadings: Set<String> = parser.allPossibleReadings
    var consonant = ""
    var semivowel = ""
    var vowel = ""
    var highestFilledSlot = 0 // 聲＝1、介＝2、韻＝3、調＝4。

    func currentStem() -> String { consonant + semivowel + vowel }

    /// 尚未收束的音節是否可能繼續合法延伸。
    func isStemSane() -> Bool {
      let stem = currentStem()
      guard !stem.isEmpty else { return true }
      if allPossibleReadings.contains(stem) { return true }
      return allPossibleReadings.contains { $0.hasPrefix(stem) }
    }

    /// 收束當前音節（聲調鍵到來時呼叫）。
    func flushSyllable() {
      if !isStemSane() { result.containsViolation = true }
      consonant = ""
      semivowel = ""
      vowel = ""
      highestFilledSlot = 0
    }

    for key in keyTrail {
      guard key.unicodeScalars.count == 1 else {
        result.containsViolation = true
        continue
      }
      var probe = Tekkon.Composer("", arrange: parser)
      _ = probe.receiveKey(fromString: key)
      guard !probe.isEmpty else {
        // 該鍵不是當前注音排列可吃的鍵（含大小寫不合者）。
        result.containsViolation = true
        continue
      }
      result.containsZhuyinKey = true
      if !probe.intonation.isEmpty {
        flushSyllable()
      } else if !probe.vowel.isEmpty {
        vowel = probe.vowel.value
        highestFilledSlot = max(highestFilledSlot, 3)
      } else if !probe.semivowel.isEmpty {
        if highestFilledSlot > 2 { result.containsViolation = true }
        semivowel = probe.semivowel.value
        highestFilledSlot = max(highestFilledSlot, 2)
      } else {
        if highestFilledSlot >= 1 { result.containsViolation = true }
        consonant = probe.consonant.value
        highestFilledSlot = max(highestFilledSlot, 1)
      }
    }
    // 收尾：序列最後仍未收束的音節。
    if !isStemSane() { result.containsViolation = true }
    return result
  }
}
