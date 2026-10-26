import Foundation

@MainActor
final class BattleEngineProcess {
    nonisolated static let revision = "ptb-bw2-owned-stats-v1/showdown-0.11.11/move-details-v1/species-clause-v1/effects-v2/stats-stages-v1/move-targets-v1/final-team-v1/six-hidden-order-v1/field-state-v1/event-notices-v1/field-timers-v1/move-accuracy-v1/bring-six-pick-three-four-v1/public-roster-preview-v1/locked-roster-v1/action-scenes-v1/held-items-mega-v1/item-clause-v1"
    var onFrames: (([BattleFrame]) -> Void)?
    var onFailure: ((String) -> Void)?
    var onExit: ((String) -> Void)?
    private var errorOutput: FileHandle?
    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var expectedStop = false

    static var sourceRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("BattleEngine")
    }
    static var resourceDirectory: URL {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BattleEngine")
        return FileManager.default.fileExists(atPath: bundled.appendingPathComponent("node").path) ? bundled : sourceRoot
    }
    static var runtimeURL: URL { resourceDirectory.appendingPathComponent(resourceDirectory == sourceRoot ? "runtime/node" : "node") }

    static func validate(mode: BattleMode, team: [BattlePokemon]) async throws -> [String] {
        let node = runtimeURL, script = resourceDirectory.appendingPathComponent("engine.cjs")
        guard FileManager.default.isExecutableFile(atPath: node.path) else { throw BattleFailure.unavailableEngine }
        return try await Task.detached {
            struct Validation: Encodable { let kind = "validate"; let mode: BattleMode; let team: [BattlePokemon] }
            struct Reply: Decodable { let validated: Bool?; let abilities: [String]?; let error: String? }
            let child = Process(), input = Pipe(), output = Pipe()
            child.executableURL = node; child.arguments = [script.path]
            child.standardInput = input; child.standardOutput = output
            child.standardError = FileHandle.nullDevice
            child.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
            try child.run()
            var data = try JSONEncoder().encode(Validation(mode: mode, team: team)); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
            try input.fileHandleForWriting.close()
            let response = output.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            let reply = try JSONDecoder().decode(Reply.self, from: response)
            guard child.terminationStatus == 0, reply.validated == true, let abilities = reply.abilities else {
                throw BattleFailure.invalidTeam(reply.error ?? "Battle team validation failed.")
            }
            return abilities
        }.value
    }

    func start(mode: BattleMode, teams: [[BattlePokemon]]) throws {
        stop()
        expectedStop = false
        let node = Self.runtimeURL
        let script = Self.resourceDirectory.appendingPathComponent("engine.cjs")
        guard FileManager.default.isExecutableFile(atPath: node.path), FileManager.default.fileExists(atPath: script.path) else { throw BattleFailure.unavailableEngine }
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = node; child.arguments = [script.path]
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        child.currentDirectoryURL = script.deletingLastPathComponent()
        // Do not inherit NODE_OPTIONS or module injection from the launching shell.
        child.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        errorOutput = stderr.fileHandleForReading
        errorOutput?.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor [weak self] in
                guard let self, self.process === child, !self.expectedStop else { return }
                self.onExit?("Battle engine exited (\(child.terminationStatus)).")
            }
        }
        try child.run()
        process = child; input = stdin.fileHandleForWriting
        let output = stdout.fileHandleForReading
        // One serial reader preserves complete-line order and bounds an incomplete engine response.
        reader = Task.detached { [weak self] in
            var buffer = Data()
            do {
                while !Task.isCancelled {
                    let chunk = output.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    guard buffer.count <= 2_097_152 else { throw BattleFailure.invalidMessage }
                    while let end = buffer.firstIndex(of: 10) {
                        let line = buffer.subdata(in: buffer.startIndex..<end)
                        buffer.removeSubrange(buffer.startIndex...end)
                        await self?.receive(line)
                    }
                }
            } catch { await self?.fail(error.localizedDescription) }
        }
        try send(StartCommand(kind: "start", mode: mode, teams: teams))
    }
    private struct StartCommand: Encodable { let kind: String; let mode: BattleMode; let teams: [[BattlePokemon]] }
    private struct ChoiceCommand: Encodable { let kind = "choose"; let player: Int; let decisionID: String; let actions: [BattleAction]; let order: [Int] }
    private struct SurrenderCommand: Encodable { let kind = "surrender"; let player: Int }
    private struct Reply: Decodable { let frames: [BattleFrame]?; let error: String? }
    func choose(player: Int, decision: BattleDecision) throws {
        try send(ChoiceCommand(player: player, decisionID: decision.decisionID, actions: decision.actions, order: decision.order))
    }
    func surrender(player: Int) throws { try send(SurrenderCommand(player: player)) }
    private func send<T: Encodable>(_ command: T) throws {
        guard let input, process?.isRunning == true else { throw BattleFailure.unavailableEngine }
        var data = try JSONEncoder().encode(command); data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ line: Data) {
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: line)
            if let error = reply.error { onFailure?(error) }
            else if let frames = reply.frames, frames.count == 2 { onFrames?(frames) }
        } catch { onExit?(error.localizedDescription) }
    }
    private func fail(_ reason: String) { if !expectedStop { onFailure?(reason) } }
    func stop() {
        expectedStop = true
        onFrames = nil; onFailure = nil; onExit = nil
        errorOutput?.readabilityHandler = nil; errorOutput = nil
        reader?.cancel(); reader = nil
        try? input?.close(); input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}
