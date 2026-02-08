import Foundation

/// Applies a Tapback (reaction) to the most recent message in a Messages.app conversation.
///
/// Implementation note:
/// - AppleScript's Messages dictionary does not expose reacting/tapbacks.
/// - This uses UI scripting via `System Events` (Accessibility). It is inherently best-effort.
/// - Requires: System Settings → Privacy & Security → Accessibility → enable for the calling host app
///   (Terminal / iTerm / the process running `imsg`).
public struct TapbackSender: Sendable {
  public enum TapbackError: LocalizedError, Sendable {
    case uiScriptingFailure(String)

    public var errorDescription: String? {
      switch self {
      case .uiScriptingFailure(let message):
        return """
        \(message)

        ⚠️  Tapback failed (UI scripting)

        This command uses macOS Accessibility UI scripting to drive Messages.app.

        To fix:
        1) Open System Settings → Privacy & Security → Accessibility
        2) Enable Accessibility for the app running `imsg` (Terminal/iTerm/etc)
        3) Also check System Settings → Privacy & Security → Automation and allow control of “System Events” / “Messages” if prompted

        Notes:
        - Messages must be able to open the conversation for the recipient.
        - UI scripting is best-effort and may break across macOS versions/languages.
        """
      }
    }
  }

  public init() {}

  /// Tapback the most recent message in the conversation with `recipient`.
  public func tapbackMostRecentMessage(
    recipient: String,
    type: ReactionType,
    verbose: Bool = false
  ) throws {
    // We only support standard tapbacks via the UI (custom emoji is not reliable via UI scripting).
    guard !type.isCustom else {
      throw TapbackError.uiScriptingFailure(
        "Custom emoji tapbacks are not supported by UI scripting in this build. Use one of: like|love|laugh|emphasis|question|dislike."
      )
    }

    let script = makeScript(recipient: recipient, type: type, verbose: verbose)

    // Use /usr/bin/osascript so we can access UI scripting.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "AppleScript", "-"]

    let stdinPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardError = stderrPipe

    try process.run()
    if let data = script.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(data)
    }
    stdinPipe.fileHandleForWriting.closeFile()

    process.waitUntilExit()
    if process.terminationStatus != 0 {
      let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "Unknown osascript error"
      throw TapbackError.uiScriptingFailure(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private func makeScript(recipient: String, type: ReactionType, verbose: Bool) -> String {
    // We open the conversation via `open location "sms:..."` which is the most reliable way
    // to get Messages into the right chat without needing to find sidebar rows.
    let tapbackMenuItem = tapbackMenuLabel(for: type)

    // This script:
    // 1) Activates Messages
    // 2) Opens the conversation using sms: URL
    // 3) Tries to context-click the last message bubble in the transcript scroll area
    // 4) Clicks the Tapback menu item from the context menu
    //
    // Caveat: UI structure varies.
    let safeRecipient = recipient.replacingOccurrences(of: "\"", with: "\\\"")
    let safeMenuItem = tapbackMenuItem.replacingOccurrences(of: "\"", with: "\\\"")

    return """
    on logv(msg)
      if \(verbose ? "true" : "false") then
        log msg
      end if
    end logv

    set theRecipient to "\(safeRecipient)"
    set theMenuItem to "\(safeMenuItem)"

    my logv("Opening conversation for: " & theRecipient)

    tell application "Messages" to activate
    delay 0.3

    -- Open conversation (works for both iMessage/SMS depending on account)
    try
      tell application "Finder" to open location "sms:" & theRecipient
    on error errMsg
      my logv("open location failed: " & errMsg)
    end try

    delay 0.8

    tell application "System Events"
      if not (UI elements enabled) then
        error "UI scripting is not enabled. (System Events: UI elements not enabled)"
      end if

      tell process "Messages"
        set frontmost to true
        delay 0.2

        set theWindow to window 1
        set targetEl to missing value

        -- Attempt: grab last group inside scroll area(s)
        try
          set sa to scroll area 1 of theWindow
          try
            set sa to scroll area 1 of sa
          end try

          if (count of groups of sa) > 0 then
            set targetEl to item -1 of (groups of sa)
          end if
        end try

        if targetEl is missing value then
          error "Could not locate transcript UI element to apply tapback."
        end if

        my logv("Showing context menu...")
        try
          perform action "AXShowMenu" of targetEl
        on error errMsg
          try
            click targetEl
            delay 0.1
            perform action "AXShowMenu" of targetEl
          on error errMsg2
            error "Unable to open context menu on last message: " & errMsg2
          end try
        end try

        delay 0.2

        my logv("Clicking tapback menu item: " & theMenuItem)
        try
          click menu item theMenuItem of menu 1
        on error errMsg
          error "Could not find tapback menu item '" & theMenuItem & "'. " & errMsg
        end try
      end tell
    end tell
    """
  }

  private func tapbackMenuLabel(for type: ReactionType) -> String {
    // Context menu labels in Messages vary; these are the common English labels.
    // If your system language differs, UI scripting may fail.
    switch type {
    case .like: return "Thumbs Up"
    case .love: return "Heart"
    case .laugh: return "Ha Ha"
    case .emphasis: return "Emphasize"
    case .question: return "Question Mark"
    case .dislike: return "Thumbs Down"
    case .custom: return ""
    }
  }
}
