import Testing
@testable import imsg
import IMsgCore

@Test func reactionTypeFromCLI() async throws {
  #expect(ReactionType(cliValue: "like") == .like)
  #expect(ReactionType(cliValue: "love") == .love)
  #expect(ReactionType(cliValue: "laugh") == .laugh)
  #expect(ReactionType(cliValue: "emphasis") == .emphasis)
  #expect(ReactionType(cliValue: "question") == .question)
  #expect(ReactionType(cliValue: "dislike") == .dislike)

  #expect(ReactionType(cliValue: "custom") == nil)
  #expect(ReactionType(cliValue: "") == nil)
}
