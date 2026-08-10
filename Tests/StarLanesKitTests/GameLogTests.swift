//
//  GameLogTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Tests for the record of the last game played, and for rewinding to a turn in it.
class GameLogTests: XCTestCase {

    private func makeSeries(playerNames: [String] = ["ONE", "TWO"]) -> Series {
        let playerDefs = playerNames.map { VmoPlayerDef(name: $0, isComputer: false) }
        return Series(
            gameConfig: .basic,
            houseRules: .default,
            playerDefs: playerDefs,
            leaderboard: Leaderboard(playerDefs: playerDefs)
        )
    }

    private func makeLog(playerNames: [String] = ["ONE", "TWO"]) -> GameLog {
        return GameLog(version: "1.1", series: makeSeries(playerNames: playerNames))
    }

    /// A game in its opening position, for tests that need something to snapshot.
    private func makeGame(playerCount: Int = 2) -> Game {
        let isComputer = Array(repeating: false, count: playerCount)
        return Game(
            model: GameModel(
                gameConfig: .basic,
                houseRules: .default,
                playerCount: playerCount,
                isComputer: isComputer,
                fixedCoordinateStack: nil
            ),
            laggardMonitor: LaggardMonitor(gameConfig: .basic, isComputer: isComputer),
            companiesDeclaredSafe: Array(repeating: false, count: GameConfig.basic.shippingCompanyCount),
            playerIndex: 0,
            playerOrder: Array(0 ..< playerCount)
        )
    }

    func testTurnsAreNumberedFromOne() {
        var log = makeLog()
        log.beginTurn(playerName: "ONE")
        log.beginTurn(playerName: "TWO")

        XCTAssertEqual(log.entries.map { $0.turnNumber }, [1, 2])
    }

    func testRoundAdvancesAfterEveryPlayerHasTakenATurn() {
        var log = makeLog(playerNames: ["ONE", "TWO"])
        for _ in 0 ..< 5 {
            log.beginTurn(playerName: "ONE")
            log.beginTurn(playerName: "TWO")
        }

        XCTAssertEqual(log.entries.map { $0.roundNumber }, [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
    }

    func testRoundAdvancesCorrectlyForThreePlayers() {
        var log = makeLog(playerNames: ["ONE", "TWO", "THREE"])
        for _ in 0 ..< 2 {
            log.beginTurn(playerName: "ONE")
            log.beginTurn(playerName: "TWO")
            log.beginTurn(playerName: "THREE")
        }

        XCTAssertEqual(log.entries.map { $0.roundNumber }, [1, 1, 1, 2, 2, 2])
    }

    func testATurnRecordsItsMoveDividendsAndPurchases() {
        var log = makeLog()
        log.beginTurn(playerName: "ONE")
        log.recordMove(coordinate: "5C", events: ["FOUNDED ALTAIR STARWAYS"])
        log.recordDividends(1250)
        log.recordPurchases(["10 x ALTAIR STARWAYS"])

        let entry = log.entries[0]
        XCTAssertEqual(entry.playerName, "ONE")
        XCTAssertEqual(entry.coordinate, "5C")
        XCTAssertEqual(entry.events, ["FOUNDED ALTAIR STARWAYS"])
        XCTAssertEqual(entry.dividends, 1250)
        XCTAssertEqual(entry.purchases, ["10 x ALTAIR STARWAYS"])
    }

    func testRecordingBeforeAnyTurnIsIgnoredRatherThanCrashing() {
        // A player with no playable coordinate skips straight past the move, so these
        // must tolerate being called with nothing open.
        var log = makeLog()
        log.recordMove(coordinate: "1A", events: ["NEW OUTPOST"])
        log.recordDividends(100)
        log.recordPurchases(["1 x ALTAIR STARWAYS"])

        XCTAssertTrue(log.entries.isEmpty)
    }

    func testEntryLookupFindsTheRequestedTurn() {
        var log = makeLog()
        log.beginTurn(playerName: "ONE")
        log.beginTurn(playerName: "TWO")

        XCTAssertEqual(log.entry(turnNumber: 2)?.playerName, "TWO")
        XCTAssertNil(log.entry(turnNumber: 3))
        XCTAssertNil(log.entry(turnNumber: 0))
    }

    // MARK: Rewinding

    func testRewindingDiscardsTheTurnsThatFollowed() {
        var log = makeLog()
        for index in 1 ... 10 {
            log.beginTurn(playerName: index % 2 == 1 ? "ONE" : "TWO")
        }
        log.finish(description: "ONE CALLED THE GAME", ranking: [GameLogRanking(name: "ONE", netWorth: 100)])

        log.discardTurns(after: 4)

        XCTAssertEqual(log.entries.count, 4)
        XCTAssertEqual(log.entries.last?.turnNumber, 4)
        XCTAssertNil(log.endOfGameDescription, "a rewound game is no longer finished")
        XCTAssertTrue(log.finalRanking.isEmpty)
    }

    func testPlayResumesAtTheNextTurnNumberAfterRewinding() {
        // The bug this guards against: turns from the abandoned timeline were kept, so the
        // next turn was numbered after them instead of after the rewind point.
        var log = makeLog()
        for index in 1 ... 10 {
            log.beginTurn(playerName: index % 2 == 1 ? "ONE" : "TWO")
        }

        log.discardTurns(after: 4)
        log.beginTurn(playerName: "ONE")

        XCTAssertEqual(log.entries.count, 5)
        XCTAssertEqual(log.entries.last?.turnNumber, 5, "play continues from the rewind point")
        XCTAssertEqual(log.entries.last?.roundNumber, 3)
    }

    func testAnUnplayedTurnIsDroppedWhenTheGameEnds() {
        // A player who calls the game never plays a move, leaving an entry with nothing in it
        // and no state to rewind to.
        var log = makeLog()
        log.beginTurn(playerName: "ONE")
        log.recordMove(coordinate: "1A", events: ["NEW OUTPOST"])
        log.endTurn(game: makeGame())
        log.beginTurn(playerName: "TWO")

        log.discardIncompleteTurn()

        XCTAssertEqual(log.entries.count, 1, "the unplayed turn is dropped")
        XCTAssertEqual(log.entries.last?.playerName, "ONE")
    }

    func testDiscardingAnIncompleteTurnKeepsCompletedOnes() {
        var log = makeLog()
        log.beginTurn(playerName: "ONE")
        log.endTurn(game: makeGame())

        log.discardIncompleteTurn()

        XCTAssertEqual(log.entries.count, 1, "a completed turn is never dropped")
    }

    func testDiscardingBeyondTheEndKeepsEverything() {
        var log = makeLog()
        for _ in 1 ... 3 {
            log.beginTurn(playerName: "ONE")
        }

        log.discardTurns(after: 99)

        XCTAssertEqual(log.entries.count, 3)
    }

    // MARK: Persistence

    func testLogSurvivesEncodingAndDecoding() {
        var log = makeLog()
        log.beginTurn(playerName: "ONE")
        log.recordMove(coordinate: "5C", events: ["FOUNDED ALTAIR STARWAYS"])
        log.recordDividends(1250)
        log.recordPurchases(["10 x ALTAIR STARWAYS"])
        log.finish(description: "ONE CALLED THE GAME", ranking: [GameLogRanking(name: "ONE", netWorth: 12345)])

        guard let data = log.data, let decoded = GameLog(data: data) else {
            return XCTFail("game log did not encode and decode")
        }

        XCTAssertEqual(decoded.version, "1.1")
        XCTAssertEqual(decoded.playerNames, ["ONE", "TWO"])
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].coordinate, "5C")
        XCTAssertEqual(decoded.entries[0].dividends, 1250)
        XCTAssertEqual(decoded.endOfGameDescription, "ONE CALLED THE GAME")
        XCTAssertEqual(decoded.finalRanking.first?.netWorth, 12345)
    }

    func testSnapshotRestoresAPlayableGame() {
        // The snapshot is what makes rewinding possible, so it must carry the whole game.
        let series = makeSeries()
        var log = GameLog(version: "1.1", series: series)
        let model = GameModel(
            gameConfig: .basic,
            houseRules: .default,
            playerCount: 2,
            isComputer: [false, false],
            fixedCoordinateStack: nil
        )
        let game = Game(
            model: model,
            laggardMonitor: LaggardMonitor(gameConfig: .basic, isComputer: [false, false]),
            companiesDeclaredSafe: Array(repeating: false, count: GameConfig.basic.shippingCompanyCount),
            playerIndex: 1,
            playerOrder: [1, 0]
        )
        log.beginTurn(playerName: "ONE")
        log.endTurn(game: game)

        guard let data = log.data, let decoded = GameLog(data: data),
              let snapshot = decoded.entries[0].snapshot else {
            return XCTFail("snapshot did not survive persistence")
        }

        XCTAssertEqual(snapshot.playerIndex, 1, "the snapshot resumes with the next player")
        XCTAssertEqual(snapshot.playerOrder, [1, 0])
        XCTAssertEqual(snapshot.model.players.count, 2)
        XCTAssertEqual(decoded.entries[0].netWorths.count, 2)
        XCTAssertEqual(decoded.entries[0].companySizes.count, GameConfig.basic.shippingCompanyCount)
    }
}
