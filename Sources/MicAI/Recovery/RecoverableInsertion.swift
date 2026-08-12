import Foundation
import MicAICore

struct RecoverableInsertion: Identifiable, Equatable {
  let id: UUID
  let text: String
  let failure: MicAIError
}

struct RecoverableInsertionContext {
  let result: RecoverableInsertion
  let intent: InsertionIntent
  let target: TargetIdentity
  let mode: MicAIMode
}
