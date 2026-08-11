//
//  VmoMatchRecord.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// One player's standing in the running record of a matchup.
public struct VmoMatchRecordStanding {
    /// Display name
    public let name: String
    /// Games this player has won against this line-up.
    public let gamesWon: Int
    /// Highest net worth this player has ever finished one of these games with.
    public let bestNetWorth: Int
    /// True when no other player has won more games.
    public let isLeading: Bool
}

/// View model object of the running record of a matchup, presented between games.
public struct VmoMatchRecord {
    /// Names of the players, in the order they were defined.
    public let playerNames: [String]
    /// Games these players have finished together.
    public let gamesPlayed: Int
    /// Standings, most games won first.
    public let standings: [VmoMatchRecordStanding]
}

extension VmoMatchRecord {
    /// VmoMatchRecord initializer.
    /// - parameter matchup: Matchup model to transform into this view model.
    init(matchup: Matchup) {
        let leaders = matchup.leadingPlayerNames
        playerNames = matchup.playerDefs.map { $0.name }
        gamesPlayed = matchup.gamesPlayed
        standings = matchup.playerNamesByWins.map {
            VmoMatchRecordStanding(
                name: $0,
                gamesWon: matchup.winsByPlayerName[$0] ?? 0,
                bestNetWorth: matchup.bestNetWorthByPlayerName[$0] ?? 0,
                // With every player level, nobody is presented as leading.
                isLeading: leaders.contains($0) && leaders.count < matchup.playerNames.count
            )
        }
    }
}
