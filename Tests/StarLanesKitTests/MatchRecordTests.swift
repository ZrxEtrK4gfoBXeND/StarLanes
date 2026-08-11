//
//  MatchRecordTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Tests for the running record of a recurring line-up of players.
///
/// The record has to survive everything the series leaderboard does not: new series, abandoned
/// series, and quitting between games. These pin that behavior.
class MatchRecordTests: XCTestCase {

    private let playerDefs = [
        VmoPlayerDef(name: "MB", isComputer: false),
        VmoPlayerDef(name: "CLAUDE", isComputer: true)
    ]

    private func ranking(_ standings: [(String, Int)]) -> [GameLogRanking] {
        return standings.map { GameLogRanking(name: $0.0, netWorth: $0.1) }
    }

    private func record(games: [[(String, Int)]]) -> MatchRecord {
        var matchRecord = MatchRecord()
        for game in games {
            matchRecord.recordGame(
                playerDefs: playerDefs,
                gameConfig: .deluxe,
                houseRules: .default,
                ranking: ranking(game)
            )
        }
        return matchRecord
    }

    func testFirstGameCreatesTheMatchup() {
        let matchRecord = record(games: [[("MB", 100), ("CLAUDE", 50)]])

        guard let matchup = matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"]) else {
            return XCTFail("the matchup was not created")
        }
        XCTAssertEqual(matchup.gamesPlayed, 1)
        XCTAssertEqual(matchup.winsByPlayerName["MB"], 1)
        XCTAssertNil(matchup.winsByPlayerName["CLAUDE"], "a player with no wins has no entry")
    }

    func testWinsAccumulateAcrossGames() {
        let matchRecord = record(games: [
            [("MB", 100), ("CLAUDE", 50)],
            [("CLAUDE", 90), ("MB", 40)],
            [("CLAUDE", 80), ("MB", 70)]
        ])

        let matchup = matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"])!
        XCTAssertEqual(matchup.gamesPlayed, 3)
        XCTAssertEqual(matchup.winsByPlayerName["CLAUDE"], 2)
        XCTAssertEqual(matchup.winsByPlayerName["MB"], 1)
        XCTAssertEqual(matchup.leadingPlayerNames, ["CLAUDE"])
    }

    func testTheMatchupIsFoundWhateverOrderThePlayersAreNamedIn() {
        let matchRecord = record(games: [[("MB", 100), ("CLAUDE", 50)]])

        XCTAssertNotNil(matchRecord.matchup(forPlayerNames: ["CLAUDE", "MB"]))
        XCTAssertNotNil(matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"]))
    }

    func testDifferentPlayersKeepSeparateRecords() {
        var matchRecord = record(games: [[("MB", 100), ("CLAUDE", 50)]])
        matchRecord.recordGame(
            playerDefs: [VmoPlayerDef(name: "MB", isComputer: false), VmoPlayerDef(name: "HAL", isComputer: true)],
            gameConfig: .basic,
            houseRules: .default,
            ranking: ranking([("HAL", 10), ("MB", 5)])
        )

        XCTAssertEqual(matchRecord.matchups.count, 2)
        XCTAssertEqual(matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"])?.gamesPlayed, 1)
        XCTAssertEqual(matchRecord.matchup(forPlayerNames: ["MB", "HAL"])?.gamesPlayed, 1)
    }

    func testBestGameKeepsTheHighestNetWorthEverReached() {
        let matchRecord = record(games: [
            [("MB", 500), ("CLAUDE", 100)],
            [("CLAUDE", 900), ("MB", 200)],
            [("MB", 300), ("CLAUDE", 250)]
        ])

        let matchup = matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"])!
        XCTAssertEqual(matchup.bestNetWorthByPlayerName["MB"], 500, "a losing game can still be a personal best")
        XCTAssertEqual(matchup.bestNetWorthByPlayerName["CLAUDE"], 900)
    }

    func testALevelMatchHasNoLeader() {
        let matchRecord = record(games: [
            [("MB", 100), ("CLAUDE", 50)],
            [("CLAUDE", 90), ("MB", 40)]
        ])

        let vmo = VmoMatchRecord(matchup: matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"])!)
        XCTAssertFalse(vmo.standings.contains { $0.isLeading }, "nobody leads a tied match")
    }

    func testStandingsAreOrderedByGamesWon() {
        let matchRecord = record(games: [
            [("CLAUDE", 90), ("MB", 40)],
            [("CLAUDE", 80), ("MB", 70)],
            [("MB", 100), ("CLAUDE", 50)]
        ])

        let vmo = VmoMatchRecord(matchup: matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"])!)
        XCTAssertEqual(vmo.standings.map { $0.name }, ["CLAUDE", "MB"])
        XCTAssertEqual(vmo.standings.map { $0.gamesWon }, [2, 1])
        XCTAssertTrue(vmo.standings[0].isLeading)
        XCTAssertFalse(vmo.standings[1].isLeading)
        XCTAssertEqual(vmo.gamesPlayed, 3)
    }

    func testTheMostRecentMatchupIsTheOneOfferedToContinue() {
        var matchRecord = MatchRecord()
        let earlier = Date(timeIntervalSinceReferenceDate: 1000)
        let later = Date(timeIntervalSinceReferenceDate: 2000)

        matchRecord.recordGame(playerDefs: [VmoPlayerDef(name: "MB", isComputer: false), VmoPlayerDef(name: "HAL", isComputer: true)],
                               gameConfig: .basic, houseRules: .default,
                               ranking: ranking([("HAL", 10), ("MB", 5)]), date: earlier)
        matchRecord.recordGame(playerDefs: playerDefs, gameConfig: .deluxe, houseRules: .default,
                               ranking: ranking([("MB", 100), ("CLAUDE", 50)]), date: later)

        XCTAssertEqual(matchRecord.mostRecentMatchup?.playerNames, ["CLAUDE", "MB"])
    }

    func testTheMatchupRemembersTheSetUpToStartAgain() {
        let matchRecord = record(games: [[("MB", 100), ("CLAUDE", 50)]])
        let matchup = matchRecord.matchup(forPlayerNames: ["MB", "CLAUDE"])!

        XCTAssertEqual(matchup.gameConfig, GameConfig.deluxe, "continuing a match replays the same map")
        XCTAssertEqual(matchup.houseRules, HouseRules.default)
        XCTAssertEqual(matchup.playerDefs.map { $0.name }, ["MB", "CLAUDE"])
        XCTAssertEqual(matchup.playerDefs.map { $0.isComputer }, [false, true], "the computer stays the computer")
    }

    func testRecordSurvivesEncodingAndDecoding() {
        let matchRecord = record(games: [
            [("MB", 76_588_227), ("CLAUDE", 55_843_934)],
            [("CLAUDE", 900), ("MB", 200)]
        ])

        guard let data = matchRecord.data, let decoded = MatchRecord(data: data) else {
            return XCTFail("the match record did not encode and decode")
        }

        let matchup = decoded.matchup(forPlayerNames: ["MB", "CLAUDE"])!
        XCTAssertEqual(matchup.gamesPlayed, 2)
        XCTAssertEqual(matchup.winsByPlayerName["MB"], 1)
        XCTAssertEqual(matchup.winsByPlayerName["CLAUDE"], 1)
        XCTAssertEqual(matchup.bestNetWorthByPlayerName["MB"], 76_588_227)
    }

    func testAnEmptyRankingIsIgnored() {
        var matchRecord = MatchRecord()
        matchRecord.recordGame(playerDefs: playerDefs, gameConfig: .basic, houseRules: .default, ranking: [])

        XCTAssertTrue(matchRecord.matchups.isEmpty)
    }

    // MARK: Through a played game

    func testFinishingAGameRecordsItAgainstTheMatchup() {
        let playerDefs = [VmoPlayerDef(name: "ONE", isComputer: false), VmoPlayerDef(name: "TWO", isComputer: true)]
        let frontEnd = TestFrontEnd(
            gameConfig: .basic,
            houseRules: .default,
            playerDefs: playerDefs,
            input: FirstOptionInput(),
            fixedCoordinateStack: TestFrontEnd.coordinateStack(gameConfig: .basic, seed: 0),
            fixedPlayerOrder: [0, 1]
        )
        StarLanes.play(frontEnd: frontEnd)

        guard let data = frontEnd.persistedMatchRecord, let matchRecord = MatchRecord(data: data) else {
            return XCTFail("finishing a game must write the match record")
        }
        let matchup = matchRecord.matchup(forPlayerNames: ["ONE", "TWO"])!
        XCTAssertEqual(matchup.gamesPlayed, 1)
        XCTAssertEqual(matchup.winsByPlayerName[frontEnd.finalRanking!.first!.name], 1)
        XCTAssertNotNil(frontEnd.presentedMatchRecord, "the record is shown when the game ends")
        XCTAssertEqual(frontEnd.presentedMatchRecord?.gamesPlayed, 1)
    }

    func testASecondGameAddsToTheExistingRecordRatherThanReplacingIt() {
        let playerDefs = [VmoPlayerDef(name: "ONE", isComputer: false), VmoPlayerDef(name: "TWO", isComputer: true)]

        // Carry the record forward between two separate sessions, as the file on disk would.
        var carriedRecord: Data?
        for seed in 0 ..< 2 {
            let frontEnd = TestFrontEnd(
                gameConfig: .basic,
                houseRules: .default,
                playerDefs: playerDefs,
                input: FirstOptionInput(),
                fixedCoordinateStack: TestFrontEnd.coordinateStack(gameConfig: .basic, seed: seed),
                fixedPlayerOrder: [0, 1]
            )
            frontEnd.persistedMatchRecord = carriedRecord
            StarLanes.play(frontEnd: frontEnd)
            carriedRecord = frontEnd.persistedMatchRecord
        }

        guard let data = carriedRecord, let matchRecord = MatchRecord(data: data) else {
            return XCTFail("no record carried between sessions")
        }
        let matchup = matchRecord.matchup(forPlayerNames: ["ONE", "TWO"])!
        XCTAssertEqual(matchup.gamesPlayed, 2, "the tally must survive a new series")
        XCTAssertEqual(matchup.winsByPlayerName.values.reduce(0, +), 2)
        XCTAssertEqual(matchRecord.matchups.count, 1, "the same players share one record")
    }
}
