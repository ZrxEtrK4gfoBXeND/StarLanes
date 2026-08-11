//
//  GameLogArchive.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// The last few games played, most recent first.
///
/// Only the game in progress keeps its turn by turn snapshots, because those are what make the
/// file large and only the most recent game can be rewound into. Older games keep their moves,
/// mergers and standings, which is what reviewing them needs.
struct GameLogArchive: Codable {
    /// How many games are kept before the oldest is dropped.
    static let maximumGameCount = 3

    /// Games kept, most recent first. The first is the game in progress, or the last one finished.
    private(set) var games: [GameLog]

    /// Basic initializer. Creates an empty archive.
    init() {
        games = [GameLog]()
    }
}

extension GameLogArchive {

    /// The game in progress, or the most recently finished one.
    var currentGame: GameLog? {
        return games.first
    }

    /// Adds a new game to the front, dropping the oldest once the archive is full.
    /// - parameter gameLog: Log of the game just started.
    mutating func beginGame(_ gameLog: GameLog) {
        // The games now behind us keep their moves for review, but give up their snapshots.
        for index in games.indices {
            games[index].discardSnapshots()
        }
        games.insert(gameLog, at: 0)
        if games.count > GameLogArchive.maximumGameCount {
            games.removeLast(games.count - GameLogArchive.maximumGameCount)
        }
    }

    /// Replaces the game in progress with its latest state.
    /// - parameter gameLog: Log of the game in progress.
    mutating func updateCurrentGame(_ gameLog: GameLog) {
        if games.isEmpty {
            games = [gameLog]
        } else {
            games[0] = gameLog
        }
    }

    /// A game by position, counting from the most recent.
    /// - parameter number: 1 for the most recent game.
    /// - returns: The game, or nil when the archive does not hold that many.
    func game(number: Int) -> GameLog? {
        let index = number - 1
        return index >= 0 && index < games.count ? games[index] : nil
    }
}

extension GameLogArchive {

    /// Re-populates an archive from a blob previously created by `data`.
    ///
    /// A file written before games were archived holds a single game, and is read as an archive
    /// of one so that an existing history is not thrown away.
    /// - parameter data: Blob of data.
    init?(data: Data) {
        if let archive = try? JSONDecoder().decode(GameLogArchive.self, from: data) {
            self = archive
        } else if let singleGame = GameLog(data: data) {
            self.init()
            games = [singleGame]
        } else {
            return nil
        }
    }

    /// Creates a blob of data from this archive.
    var data: Data? {
        return try? JSONEncoder().encode(self)
    }
}
