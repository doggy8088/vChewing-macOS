// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import Shared

// MARK: - TypingHistoryLogger

/// 「打字履歷」記錄器。
///
/// 用途：把「中文模式下、使用者實際遞交給客體」的每一筆組字結果，以 JSON Lines
/// （每行一筆 JSON）追加寫入單一檔案，供離線詞頻統計與選字策略分析。
///
/// 設計要點：
/// - 由 `UserDef.kRecordTypingHistory` 把守（預設關閉）；呼叫端負責判斷，本類別不讀偏好。
/// - 檔案位置由 `SessionHost.typingHistoryDataURL` 注入；未設定時本類別不做任何事。
/// - 寫入失敗一律靜默（僅留 log），不得干擾打字流程。
/// - 內容不含客體 App 資訊；英數模式或其他無讀音的遞交也一律不記（由呼叫端把守）。
public final class TypingHistoryLogger {
  // MARK: Lifecycle

  private init() {}

  // MARK: Public

  /// 行程共用的記錄器。
  public static let shared = TypingHistoryLogger()

  /// 單筆打字履歷記錄。
  public struct Entry: Codable, Sendable {
    // MARK: Lifecycle

    public init(timestamp: Double, mode: String, reading: String, text: String) {
      self.timestamp = timestamp
      self.mode = mode
      self.reading = reading
      self.text = text
    }

    // MARK: Public

    /// Unix 時間戳（秒）。
    public let timestamp: Double
    /// 輸入模式：`chs` / `cht` / `null`。
    public let mode: String
    /// 讀音：該次組字結果各節點的讀音，以「-」相連。
    public let reading: String
    /// 實際遞交給客體的文字。
    public let text: String

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
      case timestamp = "ts"
      case mode, reading, text
    }
  }

  /// 記錄一筆打字履歷。
  /// - Parameters:
  ///   - mode: 當前輸入模式。
  ///   - reading: 該次組字結果的讀音。
  ///   - text: 實際遞交給客體的文字。
  ///   - fileURL: 目標檔案；為 nil 或內容不完整時不記錄。
  ///   - timestamp: 時間戳（秒）；預設為當下時間。
  public func record(
    mode: Shared.InputMode,
    reading: String,
    text: String,
    to fileURL: URL?,
    timestamp: Double = Date().timeIntervalSince1970
  ) {
    guard let fileURL, !reading.isEmpty, !text.isEmpty else { return }
    let entry = Entry(timestamp: timestamp, mode: Self.modeTag(for: mode), reading: reading, text: text)
    guard let line = Self.encode(entry) else { return }
    append(line: line, to: fileURL)
  }

  /// 將單筆記錄編碼成 JSON 行（不含換行字元）。
  public static func encode(_ entry: Entry) -> String? {
    guard let data = try? JSONEncoder().encode(entry) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// 輸入模式於記錄當中的標籤。
  public static func modeTag(for mode: Shared.InputMode) -> String {
    switch mode {
    case .imeModeCHS: return "chs"
    case .imeModeCHT: return "cht"
    case .imeModeNULL: return "null"
    }
  }

  // MARK: Private

  /// 以追加模式寫入單行記錄。任何失敗皆只留 log。
  private func append(line: String, to fileURL: URL) {
    guard let lineData = (line + "\n").data(using: .utf8) else { return }
    let fileManager = FileManager.default
    do {
      let folderURL = fileURL.deletingLastPathComponent()
      if !fileManager.fileExists(atPath: folderURL.path) {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
      }
      if !fileManager.fileExists(atPath: fileURL.path) {
        _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: fileURL)
      defer { try? handle.closeTheFile() }
      _ = try? handle.seekToEOF()
      try handle.writeData(lineData)
    } catch {
      vCLog("TypingHistory: Unable to append record. Details: \(error)")
    }
  }
}
