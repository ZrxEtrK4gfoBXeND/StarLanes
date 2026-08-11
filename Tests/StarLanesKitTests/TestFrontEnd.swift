//
//  TestFrontEnd.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation
@testable import StarLanesKit

/// Captures what the front end presents, assembling lines the way a terminal would.
///
/// Rows are written a cell at a time with an empty terminator, so a line is only complete when a
/// newline arrives. Treating each write as its own line would make every column look like a row.
final class SilentOutput: Output {
    /// Completed lines, in the order they were presented.
    private(set) var lines = [String]()
    /// The line being assembled, not yet terminated by a newline.
    private var partialLine = ""

    func write() {
        write("", terminator: "\n")
    }

    func write(_ string: String) {
        write(string, terminator: "\n")
    }

    func write(_ string: String, terminator: String) {
        partialLine += string + terminator
        // Everything before a newline is a finished line; whatever follows the last one is not.
        var pieces = partialLine.components(separatedBy: "\n")
        partialLine = pieces.removeLast()
        lines += pieces
    }
}

/// Supplies scripted answers instead of reading a keyboard.
/// Running out of answers is a test failure rather than a hang, which is what the real
/// console input used to do before end of input was handled.
final class ScriptedInput: Input {
    /// Queued answers to yes/no questions.
    private var yesOrNoAnswers: [String]
    /// Queued answers to quantity questions.
    private var intAnswers: [Int]
    /// Set when the script runs dry, so a test can tell an exhausted script from a finished game.
    private(set) var ranOutOfAnswers = false

    /// Basic initializer.
    /// - parameter yesOrNo: Answers to yes/no questions, in the order they will be asked.
    /// - parameter ints: Answers to quantity questions, in the order they will be asked.
    init(yesOrNo: [String] = [], ints: [Int] = []) {
        self.yesOrNoAnswers = yesOrNo
        self.intAnswers = ints
    }

    func readYorN(output: Output) -> String {
        guard !yesOrNoAnswers.isEmpty else {
            ranOutOfAnswers = true
            return "N"
        }
        return yesOrNoAnswers.removeFirst()
    }

    func readInt(output: Output, min: Int, max: Int, defaultValue: Int?) -> Int {
        guard !intAnswers.isEmpty else {
            ranOutOfAnswers = true
            return min
        }
        let answer = intAnswers.removeFirst()
        return answer < min ? min : (answer > max ? max : answer)
    }
}

/// Always takes the first coordinate offered and never buys shares.
/// Predictable on purpose: a test asserting on the outcome of a game needs the human to play
/// the same way every run.
final class FirstOptionInput: Input {
    func readYorN(output: Output) -> String {
        return "N"
    }

    func readInt(output: Output, min: Int, max: Int, defaultValue: Int?) -> Int {
        return min == 0 ? 0 : 1
    }
}

/// A front end that plays a fully determined game with no console and no files.
///
/// The map, the deal and the player order are all fixed, so the same configuration produces
/// the same game every run. Persistence is held in memory, which keeps the suite from touching
/// the player's real saved game.
final class TestFrontEnd: FrontEnd {
    let input: Input
    /// Everything the game presented, for tests that assert on output.
    let recordedOutput = SilentOutput()
    /// Game configuration handed to the Magister Ludi.
    private let gameConfig: GameConfig
    /// House rules handed to the Magister Ludi.
    private let houseRules: HouseRules
    /// Players in the series.
    private let playerDefs: [VmoPlayerDef]
    /// Fixed coordinate order, which fixes the map and every deal.
    private let fixedCoordinateStack: [Coordinate]
    /// Fixed player order, which removes the turn order shuffle.
    private let fixedPlayerOrder: [Int]
    /// Answer given when asked to call the game.
    private let callsGame: Bool
    /// Answer given when asked to play another game in the series.
    private let playsAnotherGame: Bool

    /// Session blob, held in memory instead of in the player's home directory.
    private(set) var persistedSession: Data?
    /// Game log blob, held in memory instead of in the player's home directory.
    /// Seeded by a test that needs games already on record.
    var persistedGameLog: Data?
    /// Match record blob, held in memory. Seeded by a test that needs a match already in progress.
    var persistedMatchRecord: Data?
    /// Reason the game ended, captured when it is presented.
    private(set) var endOfGameReason: EndOfGameReason?
    /// Final standings, captured when they are presented.
    private(set) var finalRanking: [VmoPlayer]?
    /// Match record, captured when it is presented at the end of a game.
    private(set) var presentedMatchRecord: VmoMatchRecord?

    /// Basic initializer.
    /// - parameter gameConfig: Game configuration for the series.
    /// - parameter houseRules: House rules for the series.
    /// - parameter playerDefs: Players in the series.
    /// - parameter input: Input supplying the human answers.
    /// - parameter fixedCoordinateStack: Coordinate order, which fixes the map and the deals.
    /// - parameter fixedPlayerOrder: Turn order.
    /// - parameter callsGame: Answer given when offered the chance to end the game.
    /// - parameter playsAnotherGame: Answer given when offered another game in the series.
    init(gameConfig: GameConfig,
         houseRules: HouseRules,
         playerDefs: [VmoPlayerDef],
         input: Input,
         fixedCoordinateStack: [Coordinate],
         fixedPlayerOrder: [Int],
         callsGame: Bool = true,
         playsAnotherGame: Bool = false) {
        self.gameConfig = gameConfig
        self.houseRules = houseRules
        self.playerDefs = playerDefs
        self.input = input
        self.fixedCoordinateStack = fixedCoordinateStack
        self.fixedPlayerOrder = fixedPlayerOrder
        self.callsGame = callsGame
        self.playsAnotherGame = playsAnotherGame
    }

    // MARK: FrontEndConfig

    func configureSeries(minPlayerCount: Int, maxPlayerCount: Int, completionHandler: (GameConfig, HouseRules, [VmoPlayerDef]) -> Void) {
        completionHandler(gameConfig, houseRules, playerDefs)
    }

    func configureGame(gameConfig: GameConfig, houseRules: HouseRules, playerDefs: [VmoPlayerDef], completionHandler: ([Coordinate]?, [Int]?) -> Void) {
        completionHandler(fixedCoordinateStack, fixedPlayerOrder)
    }

    // MARK: FrontEndPersist

    func retrievePersistedSession(completionHandler: (Data?) -> Void) {
        // Always start fresh, so a test never inherits state from the machine it runs on.
        completionHandler(nil)
    }

    func persistSession(data: Data) {
        persistedSession = data
    }

    func persistGameLog(data: Data) {
        persistedGameLog = data
    }

    func retrieveGameLog(completionHandler: (Data?) -> Void) {
        completionHandler(persistedGameLog)
    }

    func persistMatchRecord(data: Data) {
        persistedMatchRecord = data
    }

    func retrieveMatchRecord(completionHandler: (Data?) -> Void) {
        completionHandler(persistedMatchRecord)
    }

    // MARK: FrontEndInput

    func inputCallGame(input: Input, endGameTokenCount: Int, completionHandler: (Bool) -> Void) {
        completionHandler(callsGame)
    }

    func inputConcedeGame(input: Input, playerDef: VmoPlayerDef, completionHandler: (Bool) -> Void) {
        completionHandler(false)
    }

    func inputPlayAnotherGame(input: Input, completionHandler: (Bool) -> Void) {
        completionHandler(playsAnotherGame)
    }

    func inputResumeSession(input: Input, isResumingGame: Bool, completionHandler: (Bool) -> Void) {
        completionHandler(false)
    }

    func inputCoordinate(input: Input, playerDef: VmoPlayerDef, coordinateOptions: [Coordinate], completionHandler: (Coordinate) -> Void) {
        let selection = input.readInt(output: recordedOutput, min: 1, max: coordinateOptions.count, defaultValue: nil)
        completionHandler(coordinateOptions[selection - 1])
    }

    func inputPurchaseOrder(input: Input, activeCompanies: [VmoCompany], availableCash: Int, completionHandler: ([Int]) -> Void) {
        // Mirrors the console front end: only affordable companies are offered, in order.
        var cash = availableCash
        var purchaseOrder = Array(repeating: 0, count: activeCompanies.count)
        for index in activeCompanies.indices where cash >= activeCompanies[index].shareValue {
            let maxAmount = cash / activeCompanies[index].shareValue
            purchaseOrder[index] = input.readInt(output: recordedOutput, min: 0, max: maxAmount, defaultValue: nil)
            cash -= purchaseOrder[index] * activeCompanies[index].shareValue
        }
        completionHandler(purchaseOrder)
    }

    // MARK: FrontEndDisplay

    func display(title vmoTitleCard: VmoTitleCard, completionHandler: () -> Void) {
        completionHandler()
    }

    func display(turnStart vmoPlayerDef: VmoPlayerDef) {}

    func display(galaxyMap vmoGalaxyMap: VmoGalaxyMap) {}

    func display(playerRanking vmoPlayerRanking: VmoPlayerRanking) {}

    func display(activeCompanies vmoCompanies: [VmoCompany], endGameTokenCount: Int) {}

    func display(error: MagisterLudiError) {
        recordedOutput.write("ERROR: \(error)")
    }

    func display(endOfGameReason: EndOfGameReason, vmoPlayerRanking: VmoPlayerRanking) {
        self.endOfGameReason = endOfGameReason
        self.finalRanking = vmoPlayerRanking.rankedPlayers
    }

    func display(leaderboard vmoLeaderboardEntries: [VmoLeaderboardEntry]) {}

    func display(matchRecord: VmoMatchRecord) {
        presentedMatchRecord = matchRecord
    }

    func display(announcements vmoAnnouncements: [VmoAnnouncement]) {}

    func display(gameConfig: GameConfig, houseRules: HouseRules) {}
}

extension TestFrontEnd {

    /// A coordinate order that is shuffled but repeatable, so games are varied yet identical run to run.
    ///
    /// The system shuffle cannot be used: it is seeded differently on every launch, which is exactly
    /// the randomness these tests exist to remove.
    /// - parameter gameConfig: Configuration supplying the map size.
    /// - parameter seed: Chooses which order is produced.
    /// - returns: Every coordinate on the map exactly once, in an order fixed by the seed.
    static func coordinateStack(gameConfig: GameConfig, seed: Int) -> [Coordinate] {
        var coordinates = (0 ..< (gameConfig.mapColumnCount * gameConfig.mapRowCount)).map {
            Coordinate(row: $0 / gameConfig.mapColumnCount, column: $0 % gameConfig.mapColumnCount)
        }

        // A small linear congruential generator, so the order depends only on the seed.
        var state = UInt64(seed &+ 1) &* 6364136223846793005 &+ 1442695040888963407
        func next(below limit: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(limit))
        }

        // Fisher-Yates, which visits every coordinate exactly once.
        for index in stride(from: coordinates.count - 1, to: 0, by: -1) {
            let target = next(below: index + 1)
            coordinates.swapAt(index, target)
        }
        return coordinates
    }
}
