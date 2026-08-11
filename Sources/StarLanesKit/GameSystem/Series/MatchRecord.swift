//
//  MatchRecord.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// The running record of one recurring line-up of players.
/// Identified by the set of player names, so the same opponents always find their own record.
struct Matchup: Codable {
    /// Player names, sorted. This identifies the matchup.
    let playerNames: [String]
    /// The players as they were defined, so the same line-up can be started again.
    var playerDefs: [VmoPlayerDef]
    /// Game configuration last used by these players.
    var gameConfig: GameConfig
    /// House rules last used by these players.
    var houseRules: HouseRules
    /// Total games these players have finished together.
    var gamesPlayed: Int
    /// Games won, by player name.
    var winsByPlayerName: [String: Int]
    /// Highest net worth each player has ever finished a game with.
    var bestNetWorthByPlayerName: [String: Int]
    /// When these players last finished a game.
    var lastPlayed: Date
}

extension Matchup {
    /// Names of the players who have won the most games. More than one when the match is level.
    var leadingPlayerNames: [String] {
        let mostWins = winsByPlayerName.values.max() ?? 0
        return winsByPlayerName.filter { $0.value == mostWins }.map { $0.key }.sorted()
    }

    /// Player names ordered by games won, then alphabetically.
    var playerNamesByWins: [String] {
        return playerNames.sorted {
            let (first, second) = (winsByPlayerName[$0] ?? 0, winsByPlayerName[$1] ?? 0)
            return first == second ? $0 < $1 : first > second
        }
    }
}

/// Every matchup the player has taken part in, kept apart from the saved game so that
/// starting a new series, or abandoning one, never loses the running tally.
struct MatchRecord: Codable {
    /// One entry per line-up of players.
    private(set) var matchups: [Matchup]

    /// Basic initializer. Creates an empty record.
    init() {
        matchups = [Matchup]()
    }
}

extension MatchRecord {

    /// Identifies a matchup independently of the order the players were entered in.
    /// - parameter playerNames: Names of the players.
    /// - returns: The sorted names, used as the matchup identity.
    static func key(playerNames: [String]) -> [String] {
        return playerNames.sorted()
    }

    /// The record for a line-up of players.
    /// - parameter playerNames: Names of the players, in any order.
    /// - returns: The matchup, or nil when these players have not finished a game together.
    func matchup(forPlayerNames playerNames: [String]) -> Matchup? {
        let key = MatchRecord.key(playerNames: playerNames)
        return matchups.first { $0.playerNames == key }
    }

    /// The matchup played most recently, which is the one worth offering to continue.
    var mostRecentMatchup: Matchup? {
        return matchups.sorted { $0.lastPlayed > $1.lastPlayed }.first
    }

    /// Adds a finished game to the record, creating the matchup if these players are new to each other.
    /// - parameter playerDefs: Players in the game.
    /// - parameter gameConfig: Configuration the game was played with.
    /// - parameter houseRules: House rules the game was played with.
    /// - parameter ranking: Final standings, highest net worth first.
    /// - parameter date: When the game finished.
    mutating func recordGame(playerDefs: [VmoPlayerDef],
                             gameConfig: GameConfig,
                             houseRules: HouseRules,
                             ranking: [GameLogRanking],
                             date: Date = Date()) {
        guard let winner = ranking.first else { return }

        let playerNames = playerDefs.map { $0.name }
        let key = MatchRecord.key(playerNames: playerNames)
        let index = matchups.enumerated().first { $0.element.playerNames == key }?.offset

        var matchup = index.map { matchups[$0] } ?? Matchup(
            playerNames: key,
            playerDefs: playerDefs,
            gameConfig: gameConfig,
            houseRules: houseRules,
            gamesPlayed: 0,
            winsByPlayerName: [String: Int](),
            bestNetWorthByPlayerName: [String: Int](),
            lastPlayed: date
        )

        matchup.gamesPlayed += 1
        matchup.winsByPlayerName[winner.name] = (matchup.winsByPlayerName[winner.name] ?? 0) + 1
        for standing in ranking {
            let best = matchup.bestNetWorthByPlayerName[standing.name] ?? Int.min
            if standing.netWorth > best {
                matchup.bestNetWorthByPlayerName[standing.name] = standing.netWorth
            }
        }
        // Keep the most recent set-up, so continuing the match starts the game last played.
        matchup.playerDefs = playerDefs
        matchup.gameConfig = gameConfig
        matchup.houseRules = houseRules
        matchup.lastPlayed = date

        if let index = index {
            matchups[index] = matchup
        } else {
            matchups.append(matchup)
        }
    }
}

extension MatchRecord {

    /// Re-populates a record from a blob previously created by `data`.
    /// - parameter data: Blob of data.
    init?(data: Data) {
        if let matchRecord = try? JSONDecoder().decode(MatchRecord.self, from: data) {
            self = matchRecord
        } else {
            return nil
        }
    }

    /// Creates a blob of data from this record.
    var data: Data? {
        return try? JSONEncoder().encode(self)
    }
}
