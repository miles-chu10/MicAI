import MicAICore
import Testing

@Suite
struct OperationCoordinatorTests {
  private let target = TargetIdentity(
    processIdentifier: 42,
    bundleIdentifier: "com.example.Editor",
    applicationName: "Editor"
  )

  @Test
  func dictationMovesThroughLegalTransitions() async throws {
    let coordinator = OperationCoordinator()
    let operationID = try await coordinator.begin(mode: .dictation, target: target)

    var snapshot = await coordinator.snapshot()
    #expect(snapshot.phase == .recording)

    await coordinator.stopRecording(operationID: operationID)
    snapshot = await coordinator.snapshot()
    #expect(snapshot.phase == .transcribing)
    #expect(await coordinator.markInserting(operationID: operationID))
    snapshot = await coordinator.snapshot()
    #expect(snapshot.phase == .inserting)
    #expect(await coordinator.complete(operationID: operationID))
    snapshot = await coordinator.snapshot()
    #expect(snapshot.phase == .idle)
  }

  @Test
  func commandMovesThroughLLMTransition() async throws {
    let coordinator = OperationCoordinator()
    let operationID = try await coordinator.begin(mode: .command, target: target)

    await coordinator.stopRecording(operationID: operationID)
    #expect(await coordinator.markAwaitingLLM(operationID: operationID))
    #expect(await coordinator.markInserting(operationID: operationID))
    #expect(await coordinator.complete(operationID: operationID))
  }

  @Test
  func rejectsConcurrentOperation() async throws {
    let coordinator = OperationCoordinator()
    _ = try await coordinator.begin(mode: .dictation, target: target)

    do {
      _ = try await coordinator.begin(mode: .command, target: target)
      Issue.record("Expected a concurrent operation to be rejected")
    } catch {
      #expect(error as? MicAIError == .operationAlreadyActive)
    }
  }

  @Test
  func rejectsIllegalTransition() async throws {
    let coordinator = OperationCoordinator()
    let operationID = try await coordinator.begin(mode: .dictation, target: target)

    #expect(!(await coordinator.markInserting(operationID: operationID)))
    let snapshot = await coordinator.snapshot()
    #expect(snapshot.phase == .recording)
  }

  @Test
  func cancellationReturnsToIdleAndSuppressesLateResult() async throws {
    let coordinator = OperationCoordinator()
    let operationID = try await coordinator.begin(mode: .command, target: target)
    let task = Task<Void, Never> {
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        return
      }
    }
    #expect(
      await coordinator.registerCancellationTask(task, operationID: operationID)
    )

    await coordinator.stopRecording(operationID: operationID)
    await coordinator.cancel(operationID: operationID)

    #expect(task.isCancelled)
    let snapshot = await coordinator.snapshot()
    #expect(snapshot.phase == .idle)
    #expect(!(await coordinator.isCurrent(operationID: operationID)))
    #expect(!(await coordinator.markAwaitingLLM(operationID: operationID)))
    #expect(!(await coordinator.markInserting(operationID: operationID)))
    #expect(!(await coordinator.complete(operationID: operationID)))
  }

  @Test
  func staleOperationCannotMutateNewOperation() async throws {
    let coordinator = OperationCoordinator()
    let staleID = try await coordinator.begin(mode: .dictation, target: target)
    await coordinator.cancel(operationID: staleID)

    let currentID = try await coordinator.begin(mode: .command, target: target)
    await coordinator.stopRecording(operationID: staleID)

    let snapshot = await coordinator.snapshot()
    #expect(snapshot.operationID == currentID)
    #expect(snapshot.mode == .command)
    #expect(snapshot.phase == .recording)
  }
}
