//
//  GameLog.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// Final standing of one player, recorded when a game ends.
struct GameLogRanking: Codable {
    /// Player display name.
    let name: String
    /// Player net worth at the end of the game.
    let netWorth: Int
}

/// A record of one player's turn: the coordinate played, what it caused, and the resulting standings.
struct GameLogEntry: Codable {
    /// Sequential turn number across the whole game, starting at 1.
    let turnNumber: Int
    /// Round number, starting at 1. All players take one turn per round.
    let roundNumber: Int
    /// Player display name.
    let playerName: String
    /// Coordinate played, e.g. "8A". Empty when the player had no playable coordinate.
    var coordinate: String
    /// What playing the coordinate caused, e.g. "FOUNDED ALTAIR STARWAYS".
    var events: [String]
    /// Dividends paid to the player this turn.
    var dividends: Int
    /// Shares bought this turn, e.g. "10 x BETELGEUSE, LTD.".
    var purchases: [String]
    /// Net worth of every player at the end of this turn, indexed by player.
    var netWorths: [Int]
    /// Token count of every company at the end of this turn, indexed by company.
    var companySizes: [Int]
    /// Complete game state at the end of this turn.
    /// Restoring this into a persisted session resumes play from this point, which is what
    /// makes rewinding to a chosen turn possible.
    var snapshot: Game?
}

/// An append-only record of the most recently played game.
/// Starting a new game replaces the log, so this always describes the last game played.
struct GameLog: Codable {
    /// StarLanes version that produced the log.
    let version: String
    /// Series configuration. Retained so a rewound turn can be restored into a full session.
    let series: Series
    /// Player display names, in player-definition order.
    let playerNames: [String]
    /// One entry per turn taken.
    private(set) var entries: [GameLogEntry]
    /// Why the game ended. Nil while the game is still in progress.
    var endOfGameDescription: String?
    /// Final standings, highest net worth first. Empty while the game is still in progress.
    var finalRanking: [GameLogRanking]

    /// Basic initializer. Creates an empty log for a new game.
    /// - parameter version: StarLanes version.
    /// - parameter series: Series the game belongs to.
    init(version: String, series: Series) {
        self.version = version
        self.series = series
        self.playerNames = series.playerDefs.map { $0.name }
        self.entries = [GameLogEntry]()
        self.finalRanking = [GameLogRanking]()
    }
}

extension GameLog {

    /// Opens an entry for a player's turn. Later calls in the turn fill it in.
    /// - parameter playerName: Name of the player taking the turn.
    mutating func beginTurn(playerName: String) {
        let turnNumber = entries.count + 1
        let roundNumber = playerNames.isEmpty ? 1 : ((turnNumber - 1) / playerNames.count) + 1
        entries.append(
            GameLogEntry(
                turnNumber: turnNumber,
                roundNumber: roundNumber,
                playerName: playerName,
                coordinate: "",
                events: [String](),
                dividends: 0,
                purchases: [String](),
                netWorths: [Int](),
                companySizes: [Int](),
                snapshot: nil
            )
        )
    }

    /// Records the coordinate played and its consequences.
    /// - parameter coordinate: Coordinate played, e.g. "8A".
    /// - parameter events: Descriptions of what playing the coordinate caused.
    mutating func recordMove(coordinate: String, events: [String]) {
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].coordinate = coordinate
        entries[entries.count - 1].events += events
    }

    /// Records the dividends paid to the player this turn.
    /// - parameter amount: Dividend amount in dollars.
    mutating func recordDividends(_ amount: Int) {
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].dividends = amount
    }

    /// Records the shares bought by the player this turn.
    /// - parameter purchases: Descriptions of shares bought.
    mutating func recordPurchases(_ purchases: [String]) {
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].purchases = purchases
    }

    /// Closes the entry for the turn, capturing standings and a resumable snapshot.
    /// - parameter game: Game state at the end of the turn.
    mutating func endTurn(game: Game) {
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].netWorths = game.model.netWorths
        entries[entries.count - 1].companySizes = game.model.companies.map { $0.tokenCount }
        entries[entries.count - 1].snapshot = game
    }

    /// Drops a turn that was opened but never played out.
    /// This happens when a player ends the game instead of taking their turn, by calling it or
    /// conceding, which leaves an entry with no move, no standings and nothing to rewind to.
    mutating func discardIncompleteTurn() {
        if let lastEntry = entries.last, lastEntry.snapshot == nil {
            entries.removeLast()
        }
    }

    /// Records why the game ended and the final standings.
    /// - parameter description: Reason the game ended.
    /// - parameter ranking: Final standings, highest net worth first.
    mutating func finish(description: String, ranking: [GameLogRanking]) {
        endOfGameDescription = description
        finalRanking = ranking
    }

    /// Returns the entry for a turn number, or nil when no such turn was played.
    /// - parameter turnNumber: Turn number, starting at 1.
    func entry(turnNumber: Int) -> GameLogEntry? {
        return entries.first { $0.turnNumber == turnNumber }
    }

    /// Discards every turn after the given one, and any end-of-game record.
    /// Rewinding to a turn abandons the turns that followed it, so dropping them keeps the
    /// log a single consistent timeline and lets play resume at the next turn number.
    /// - parameter turnNumber: Last turn to keep.
    mutating func discardTurns(after turnNumber: Int) {
        entries = entries.filter { $0.turnNumber <= turnNumber }
        endOfGameDescription = nil
        finalRanking = [GameLogRanking]()
    }
}

extension GameLog {

    /// Re-populates a log from a blob previously created by `data`.
    /// - parameter data: Blob of data.
    init?(data: Data) {
        if let gameLog = try? JSONDecoder().decode(GameLog.self, from: data) {
            self = gameLog
        } else {
            return nil
        }
    }

    /// Creates a blob of data from this log.
    var data: Data? {
        return try? JSONEncoder().encode(self)
    }
}
