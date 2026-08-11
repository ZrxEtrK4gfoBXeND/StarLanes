//
//  FullGameTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Plays whole games through the Magister Ludi state machine with a fixed map and turn order.
///
/// These are the tests the engine was built for: `configureGame` can supply a fixed coordinate
/// stack and player order, which removes every source of randomness and makes a game repeatable.
class FullGameTests: XCTestCase {

    private func playGame(seed: Int,
                          gameConfig: GameConfig = .basic,
                          playerDefs: [VmoPlayerDef] = [VmoPlayerDef(name: "ONE", isComputer: false),
                                                        VmoPlayerDef(name: "TWO", isComputer: true)],
                          callsGame: Bool = true) -> TestFrontEnd {
        let frontEnd = TestFrontEnd(
            gameConfig: gameConfig,
            houseRules: .default,
            playerDefs: playerDefs,
            input: FirstOptionInput(),
            fixedCoordinateStack: TestFrontEnd.coordinateStack(gameConfig: gameConfig, seed: seed),
            fixedPlayerOrder: Array(playerDefs.indices),
            callsGame: callsGame
        )
        StarLanes.play(frontEnd: frontEnd)
        return frontEnd
    }

    /// The log of the game just played, read back the way the game stores it.
    /// Games are kept in an archive, and the one just played is at its front.
    private func playedGameLog(_ frontEnd: TestFrontEnd) -> GameLog? {
        guard let data = frontEnd.persistedGameLog, let archive = GameLogArchive(data: data) else {
            return nil
        }
        return archive.currentGame
    }

    func testAGameFinishes() {
        let frontEnd = playGame(seed: 0)

        XCTAssertNotNil(frontEnd.endOfGameReason, "the game must reach an end")
        XCTAssertNotNil(frontEnd.finalRanking)
        XCTAssertEqual(frontEnd.finalRanking?.count, 2)
    }

    func testEveryConfigurationFinishes() {
        // A game that cannot end leaves the player stuck, so each shipped configuration is played out.
        for (name, config) in [("basic", GameConfig.basic), ("deluxe", GameConfig.deluxe)] {
            let frontEnd = playGame(seed: 1, gameConfig: config)
            XCTAssertNotNil(frontEnd.endOfGameReason, "the \(name) game did not finish")
        }
    }

    func testAGameWithFourPlayersFinishes() {
        let playerDefs = [
            VmoPlayerDef(name: "ONE", isComputer: false),
            VmoPlayerDef(name: "TWO", isComputer: true),
            VmoPlayerDef(name: "THREE", isComputer: true),
            VmoPlayerDef(name: "FOUR", isComputer: true)
        ]
        let frontEnd = playGame(seed: 2, playerDefs: playerDefs)

        XCTAssertNotNil(frontEnd.endOfGameReason)
        XCTAssertEqual(frontEnd.finalRanking?.count, 4)
    }

    func testTheSameGameIsPlayedTheSameWayEveryTime() {
        // Without this, none of the other full game assertions mean anything.
        let first = playGame(seed: 3)
        let second = playGame(seed: 3)

        XCTAssertEqual(
            first.finalRanking?.map { $0.netWorth },
            second.finalRanking?.map { $0.netWorth },
            "a fixed map and turn order must produce the same result"
        )
        XCTAssertEqual(first.endOfGameReason, second.endOfGameReason)
    }

    func testDifferentMapsProduceDifferentGames() {
        // Guards against the fixed stack being ignored, which would make the tests above vacuous.
        let first = playGame(seed: 0)
        let second = playGame(seed: 4)

        XCTAssertNotEqual(
            first.finalRanking?.map { $0.netWorth },
            second.finalRanking?.map { $0.netWorth },
            "different maps should not produce identical results"
        )
    }

    func testRankingIsOrderedByNetWorth() {
        let frontEnd = playGame(seed: 0)
        guard let ranking = frontEnd.finalRanking else {
            return XCTFail("no final ranking")
        }

        XCTAssertEqual(ranking.map { $0.netWorth }, ranking.map { $0.netWorth }.sorted(by: >))
    }

    func testTheSessionAndTheLogAreBothWritten() {
        let frontEnd = playGame(seed: 0)

        XCTAssertNotNil(frontEnd.persistedSession, "the session must be saved")
        guard let log = playedGameLog(frontEnd) else {
            return XCTFail("the game log must be written and readable")
        }
        XCTAssertFalse(log.entries.isEmpty)
        XCTAssertNotNil(log.endOfGameDescription, "a finished game records why it ended")
        XCTAssertEqual(log.finalRanking.count, 2)
    }

    func testTheLogNumbersEveryTurnWithoutGaps() {
        let frontEnd = playGame(seed: 0)
        guard let log = playedGameLog(frontEnd) else {
            return XCTFail("no log")
        }

        XCTAssertEqual(log.entries.map { $0.turnNumber }, Array(1 ... log.entries.count))
    }

    func testEveryLoggedTurnCanBeRewoundTo() {
        // Rewinding is only possible because each entry carries a complete game state.
        let frontEnd = playGame(seed: 0)
        guard let log = playedGameLog(frontEnd) else {
            return XCTFail("no log")
        }

        for entry in log.entries {
            XCTAssertNotNil(entry.snapshot, "turn \(entry.turnNumber) cannot be replayed")
            XCTAssertEqual(entry.netWorths.count, 2, "turn \(entry.turnNumber) has no standings")
        }
    }

    func testLoggedNetWorthMatchesTheFinalRanking() {
        let frontEnd = playGame(seed: 0)
        guard let log = playedGameLog(frontEnd),
              let lastEntry = log.entries.last, let ranking = frontEnd.finalRanking else {
            return XCTFail("no log or ranking")
        }

        for player in ranking {
            guard let index = log.playerNames.index(where: { $0 == player.name }) else {
                return XCTFail("\(player.name) is missing from the log")
            }
            XCTAssertEqual(lastEntry.netWorths[index], player.netWorth, "\(player.name) net worth disagrees with the log")
        }
    }

    func testTheWinnerIsRecordedOnTheLeaderboard() {
        let frontEnd = playGame(seed: 0)
        guard let sessionData = frontEnd.persistedSession,
              let session = PersistedSessionContainer(data: sessionData) else {
            return XCTFail("no session was saved")
        }

        XCTAssertNil(session.game, "a finished game is cleared from the session")
        let gamesWon = session.series.leaderboard.gamesWonByPlayerName
        XCTAssertEqual(gamesWon.values.reduce(0, +), 1, "exactly one win is recorded")
        XCTAssertEqual(gamesWon[frontEnd.finalRanking!.first!.name], 1, "the leader is credited with the win")
    }

    func testDecliningToCallTheGameStillEndsWhenCoordinatesRunOut() {
        // Nobody ever calls the game, so it can only end by exhausting the board.
        let frontEnd = playGame(seed: 0, callsGame: false)

        XCTAssertEqual(frontEnd.endOfGameReason, .noMorePlayableCoordinates)
    }

    func testNoPlayerEverHoldsNegativeCash() {
        // The engine trusts the front end to prevent overspending, so this pins that contract.
        let frontEnd = playGame(seed: 0)
        guard let log = playedGameLog(frontEnd) else {
            return XCTFail("no log")
        }

        for entry in log.entries {
            guard let snapshot = entry.snapshot else { continue }
            for player in snapshot.model.players {
                XCTAssertGreaterThanOrEqual(player.cash, 0, "player went into debt on turn \(entry.turnNumber)")
            }
        }
    }

    func testCompanyTokensOnTheMapMatchTheRecordedSizes() {
        // Company size drives share price, safety and the end of the game, so a drift between
        // the map and the company records would corrupt all three.
        let frontEnd = playGame(seed: 0)
        guard let log = playedGameLog(frontEnd),
              let snapshot = log.entries.last?.snapshot else {
            return XCTFail("no snapshot")
        }

        let model = snapshot.model
        for company in model.companies {
            var tokensOnMap = 0
            for row in 0 ..< model.galaxyMap.rowCount {
                for column in 0 ..< model.galaxyMap.columnCount
                    where model.galaxyMap[Coordinate(row: row, column: column)] == .company(company.index) {
                    tokensOnMap += 1
                }
            }
            XCTAssertEqual(company.tokenCount, tokensOnMap, "company \(company.monogram) size disagrees with the map")
        }
    }

    func testSafeCompaniesStaySafeForTheRestOfTheGame() {
        let frontEnd = playGame(seed: 0)
        guard let log = playedGameLog(frontEnd) else {
            return XCTFail("no log")
        }

        var everSafe = Set<Int>()
        for entry in log.entries {
            guard let snapshot = entry.snapshot else { continue }
            for company in snapshot.model.companies where company.isSafe {
                everSafe.insert(company.index)
            }
            for index in everSafe {
                let company = snapshot.model.companies[index]
                // A company destroyed by a black hole is removed from play entirely; otherwise
                // once safe, always safe.
                if company.isActive {
                    XCTAssertTrue(company.isSafe, "company \(company.monogram) stopped being safe on turn \(entry.turnNumber)")
                }
            }
        }
    }
}
