import Commander
import Foundation
import IMsgCore

enum TapbackCommand {
  static let spec = CommandSpec(
    name: "tapback",
    abstract: "Apply a Tapback (reaction) to the most recent message in a conversation",
    discussion: "Best-effort: uses Accessibility UI scripting to drive Messages.app. Requires Accessibility permission.",
    signature: CommandSignatures.withRuntimeFlags(
      CommandSignature(
        options: CommandSignatures.baseOptions() + [
          .make(label: "to", names: [.long("to")], help: "phone number or email"),
          .make(
            label: "type",
            names: [.long("type")],
            help: "tapback type: like|love|laugh|emphasis|question|dislike"
          ),
        ],
        flags: []
      )
    ),
    usageExamples: [
      "imsg tapback --to +14155551212 --type like",
      "imsg tapback --to user@icloud.com --type love",
      "imsg tapback --to +14155551212 --type laugh --verbose",
    ]
  ) { values, runtime in
    guard let to = values.option("to"), !to.isEmpty else {
      throw ParsedValuesError.missingOption("to")
    }
    guard let typeString = values.option("type"), !typeString.isEmpty else {
      throw ParsedValuesError.missingOption("type")
    }

    guard let reactionType = ReactionType(cliValue: typeString) else {
      throw ParsedValuesError.invalidOption("type")
    }

    do {
      let sender = TapbackSender()
      try sender.tapbackMostRecentMessage(recipient: to, type: reactionType, verbose: runtime.verbose)
    } catch {
      // Provide a readable error message.
      throw error
    }

    if runtime.jsonOutput {
      try JSONLines.print(["status": "tapped"]) // minimal machine-readable output
      return
    }

    Swift.print("tapback applied (best-effort): to=\(to) type=\(reactionType.name)")
  }
}

extension ReactionType {
  /// Parse from CLI value.
  init?(cliValue: String) {
    switch cliValue.lowercased() {
    case "like", "thumbsup", "thumbs-up": self = .like
    case "love", "heart": self = .love
    case "laugh", "haha", "ha-ha": self = .laugh
    case "emphasize", "emphasis", "exclaim": self = .emphasis
    case "question", "qmark", "?": self = .question
    case "dislike", "thumbsdown", "thumbs-down": self = .dislike
    default: return nil
    }
  }
}
