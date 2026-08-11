//
//  GameLogArchiveTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Tests for the archive of recent games.
///
/// The archive has to keep several games without letting the file grow without bound, and it has
/// to read a file written before archiving existed. Both are pinned here.
class GameLogArchiveTests: XCTestCase {

    private func makeSeries(playerNames: [String] = ["MB", "CLAUDE"]) -> Series {
        let playerDefs = playerNames.map { VmoPlayerDef(name: $0, isComputer: $0 == "CLAUDE") }
        return Series(
            gameConfig: .basic,
            houseRules: .default,
            playerDefs: playerDefs,
            leaderboard: Leaderboard(playerDefs: playerDefs)
        )
    }

    private func makeGame() -> Game {
        let isComputer = [false, true]
        return Game(
            model: GameModel(gameConfig: .basic, houseRules: .default, playerCount: 2, isComputer: isComputer, fixedCoordinateStack: nil),
            laggardMonitor: LaggardMonitor(gameConfig: .basic, isComputer: isComputer),
            companiesDeclaredSafe: Array(repeating: false, count: GameConfig.basic.shippingCompanyCount),
            playerIndex: 0,
            playerOrder: [0, 1]
        )
    }

    /// A finished game with a handful of turns, each carrying a snapshot.
    private func makePlayedGame(description: String, turnCount: Int = 3) -> GameLog {
        var gameLog = GameLog(version: "1.1", series: makeSeries())
        for index in 0 ..< turnCount {
            gameLog.beginTurn(playerName: index % 2 == 0 ? "MB" : "CLAUDE")
            gameLog.recordMove(coordinate: "1A", events: ["NEW OUTPOST"])
            gameLog.endTurn(game: makeGame())
        }
        gameLog.finish(description: description, ranking: [GameLogRanking(name: "MB", netWorth: 100)])
        return gameLog
    }

    func testTheNewestGameIsFirst() {
        var archive = GameLogArchive()
        archive.beginGame(makePlayedGame(description: "FIRST"))
        archive.beginGame(makePlayedGame(description: "SECOND"))

        XCTAssertEqual(archive.games.count, 2)
        XCTAssertEqual(archive.currentGame?.endOfGameDescription, "SECOND")
        XCTAssertEqual(archive.game(number: 2)?.endOfGameDescription, "FIRST")
    }

    func testOnlyThreeGamesAreKept() {
        var archive = GameLogArchive()
        for index in 1 ... 5 {
            archive.beginGame(makePlayedGame(description: "GAME \(index)"))
        }

        XCTAssertEqual(archive.games.count, GameLogArchive.maximumGameCount)
        XCTAssertEqual(archive.games.map { $0.endOfGameDescription ?? "" }, ["GAME 5", "GAME 4", "GAME 3"])
    }

    func testOnlyTheCurrentGameKeepsItsSnapshots() {
        // Snapshots are the bulk of the file, and only the newest game can be rewound into.
        var archive = GameLogArchive()
        archive.beginGame(makePlayedGame(description: "OLDER"))
        XCTAssertTrue(archive.currentGame!.isRewindable)

        archive.beginGame(makePlayedGame(description: "NEWER"))

        XCTAssertTrue(archive.game(number: 1)!.isRewindable, "the newest game can still be replayed")
        XCTAssertFalse(archive.game(number: 2)!.isRewindable, "an older game gives up its snapshots")
        XCTAssertEqual(archive.game(number: 2)!.entries.count, 3, "but keeps its moves for review")
        XCTAssertEqual(archive.game(number: 2)!.finalRanking.count, 1, "and its result")
    }

    func testDroppingSnapshotsShrinksTheStoredArchive() {
        var withSnapshots = GameLogArchive()
        withSnapshots.beginGame(makePlayedGame(description: "ONE", turnCount: 20))

        var archived = withSnapshots
        archived.beginGame(makePlayedGame(description: "TWO", turnCount: 1))

        guard let bigger = withSnapshots.data, let smaller = archived.data else {
            return XCTFail("archives did not encode")
        }
        XCTAssertLessThan(smaller.count, bigger.count, "an archived game should not cost what a live one does")
    }

    func testUpdatingTheCurrentGameLeavesOlderGamesAlone() {
        var archive = GameLogArchive()
        archive.beginGame(makePlayedGame(description: "OLDER"))
        archive.beginGame(makePlayedGame(description: "IN PROGRESS"))

        var current = archive.currentGame!
        current.beginTurn(playerName: "MB")
        archive.updateCurrentGame(current)

        XCTAssertEqual(archive.currentGame?.entries.count, 4)
        XCTAssertEqual(archive.game(number: 2)?.endOfGameDescription, "OLDER")
        XCTAssertEqual(archive.games.count, 2)
    }

    func testUpdatingAnEmptyArchiveStartsIt() {
        var archive = GameLogArchive()
        archive.updateCurrentGame(makePlayedGame(description: "ONLY"))

        XCTAssertEqual(archive.games.count, 1)
    }

    func testAskingForAGameThatIsNotKept() {
        var archive = GameLogArchive()
        archive.beginGame(makePlayedGame(description: "ONLY"))

        XCTAssertNil(archive.game(number: 0))
        XCTAssertNil(archive.game(number: 2))
        XCTAssertNotNil(archive.game(number: 1))
    }

    func testArchiveSurvivesEncodingAndDecoding() {
        var archive = GameLogArchive()
        archive.beginGame(makePlayedGame(description: "FIRST"))
        archive.beginGame(makePlayedGame(description: "SECOND"))

        guard let data = archive.data, let decoded = GameLogArchive(data: data) else {
            return XCTFail("the archive did not encode and decode")
        }

        XCTAssertEqual(decoded.games.count, 2)
        XCTAssertEqual(decoded.currentGame?.endOfGameDescription, "SECOND")
        XCTAssertEqual(decoded.game(number: 2)?.endOfGameDescription, "FIRST")
    }

    func testAFileWrittenBeforeArchivingIsStillReadable() {
        // Earlier versions stored a single game. That history should not be thrown away.
        let singleGame = makePlayedGame(description: "WRITTEN BY AN EARLIER VERSION")
        guard let data = singleGame.data else {
            return XCTFail("could not encode a single game")
        }

        guard let archive = GameLogArchive(data: data) else {
            return XCTFail("an old single game log was not readable as an archive")
        }
        XCTAssertEqual(archive.games.count, 1)
        XCTAssertEqual(archive.currentGame?.endOfGameDescription, "WRITTEN BY AN EARLIER VERSION")
        XCTAssertTrue(archive.currentGame!.isRewindable, "an old log keeps its snapshots")
    }

    func testNonsenseIsRejected() {
        XCTAssertNil(GameLogArchive(data: Data("not a log".utf8)))
    }

    // MARK: Through played games

    func testConsecutiveGamesAccumulateInTheArchive() {
        let playerDefs = [VmoPlayerDef(name: "ONE", isComputer: false), VmoPlayerDef(name: "TWO", isComputer: true)]
        var carriedLog: Data?

        for seed in 0 ..< 4 {
            let frontEnd = TestFrontEnd(
                gameConfig: .basic,
                houseRules: .default,
                playerDefs: playerDefs,
                input: FirstOptionInput(),
                fixedCoordinateStack: TestFrontEnd.coordinateStack(gameConfig: .basic, seed: seed),
                fixedPlayerOrder: [0, 1]
            )
            frontEnd.persistedGameLog = carriedLog
            StarLanes.play(frontEnd: frontEnd)
            carriedLog = frontEnd.persistedGameLog
        }

        guard let data = carriedLog, let archive = GameLogArchive(data: data) else {
            return XCTFail("no archive carried between games")
        }
        XCTAssertEqual(archive.games.count, GameLogArchive.maximumGameCount, "four games played, three kept")
        XCTAssertFalse(archive.games.contains { $0.endOfGameDescription == nil }, "every kept game finished")
        XCTAssertTrue(archive.game(number: 1)!.isRewindable)
        XCTAssertFalse(archive.game(number: 2)!.isRewindable)
    }
}
