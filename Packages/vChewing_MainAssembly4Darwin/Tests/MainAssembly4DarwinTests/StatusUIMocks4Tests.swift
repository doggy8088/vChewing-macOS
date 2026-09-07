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

// MARK: - MockSessionUI4ModeDescriptionHint

/// SessionUIProtocol 替身：可控 Caps Lock 燈態＋可攔截 statusUI。
internal final class MockSessionUI4ModeDescriptionHint: SessionUIProtocol {
  // MARK: Lifecycle

  init(capsLockIsOn: Bool, pcb: (any PCBProtocol)? = nil) {
    self.capsLockToggler = MockCapsLockToggler4ModeDescriptionHint(isOn: capsLockIsOn)
    self.statusUI = MockStatusUI4ModeDescriptionHint()
    self.pcb = pcb
  }

  // MARK: Internal

  var currentSessionID: UUID = .init()
  var shiftKeyUpChecker: (any ShiftKeyUpCheckerProtocol)?
  var capsLockHitChecker: (any HitCheckerProtocol)?
  var capsLockToggler: (any CapsLockTogglerProtocol)?
  var pcb: (any PCBProtocol)?
  var tooltipUI: (any TooltipUIProtocol)?
  var statusUI: (any TooltipUIProtocol)?
  var candidateUI: (any CtlCandidateProtocol)?

  var statusUIMock: MockStatusUI4ModeDescriptionHint? {
    statusUI as? MockStatusUI4ModeDescriptionHint
  }
}

// MARK: - MockStatusUI4ModeDescriptionHint

/// TooltipUIProtocol 替身：記錄最後一次 show 的內容與次數。
internal final class MockStatusUI4ModeDescriptionHint: TooltipUIProtocol {
  var shownTooltip: String?
  var shownDuration: Double?
  var shownPoint: CGPoint?
  var showCount = 0
  var syncCount = 0
  var lastLocale: String?
  var isShown = false

  func sync(accent _: HSBA?, locale: String) {
    syncCount += 1
    lastLocale = locale
  }

  func show(
    tooltip: String,
    at point: CGPoint,
    bottomOutOfScreenAdjustmentHeight: Double,
    direction: UILayoutOrientation,
    duration: Double
  ) {
    shownTooltip = tooltip
    shownDuration = duration
    shownPoint = point
    showCount += 1
    isShown = true
  }

  func hide() {
    isShown = false
  }

  func setColor(state: TooltipColorState) {}
}

// MARK: - MockPCB4ModeDescriptionHint

/// PCBProtocol 替身：可控顯示狀態與視窗 frame。
internal final class MockPCB4ModeDescriptionHint: PCBProtocol {
  var isTypingDirectionVertical: Bool = false
  var isShown = false
  var frame: CGRect?
  var showCount = 0

  func show(state _: some IMEStateProtocol, at _: CGPoint) {
    showCount += 1
  }

  func hide() {}
  func sync(accent _: HSBA?, locale _: String) {}
}

// MARK: - MockCapsLockToggler4ModeDescriptionHint

/// CapsLockTogglerProtocol 替身。
internal final class MockCapsLockToggler4ModeDescriptionHint: CapsLockTogglerProtocol {
  // MARK: Lifecycle

  init(isOn: Bool) {
    self.isOn = isOn
  }

  // MARK: Internal

  var isOn: Bool
}
