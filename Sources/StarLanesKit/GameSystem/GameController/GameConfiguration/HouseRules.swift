//
//  HouseRules.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

import Foundation

/// House rules values. Invariant during series.
public struct HouseRules: Codable, Equatable {
    /// The cash each human player is given at the start of every game in the series.
    public let humanInitialCash: Int
    /// The cash each computer player is given at the start of every game in the series.
    public let computerInitialCash: Int
    /// Number of coordinates dealt to each player at the start of the game.
    public let playerCoordinateOptionCount: Int
    /// Number of shares given to the founder as a bonus when creating a company.
    public let founderShareBonus: Int
    /// Value of adjacent star to share price. Stars are only calculated once for multiple adjacencies.
    public let shareValueAdjacentStar: Int
    /// Value of adjacent token to share price.
    public let shareValueAdjacentToken: Int
    /// Each round, each player gets paid a dividend. The dividend is calculated as: all shares * share values * dividend percent.
    public let dividendPercent: Int
    /// Upon merger, this many multiples of defunct company share value is split proportionaly amongst outstanding share holders
    public let mergeBonusShareValueMultiple: Int
    /// Determines whether the player order is random or fixed for every game in the series.
    public let isPlayerOrderRandom: Bool

    /// Explicit memberwise initializer, so it can be public.
    public init(humanInitialCash: Int, computerInitialCash: Int, playerCoordinateOptionCount: Int,
                founderShareBonus: Int, shareValueAdjacentStar: Int, shareValueAdjacentToken: Int,
                dividendPercent: Int, mergeBonusShareValueMultiple: Int, isPlayerOrderRandom: Bool) {
        self.humanInitialCash = humanInitialCash
        self.computerInitialCash = computerInitialCash
        self.playerCoordinateOptionCount = playerCoordinateOptionCount
        self.founderShareBonus = founderShareBonus
        self.shareValueAdjacentStar = shareValueAdjacentStar
        self.shareValueAdjacentToken = shareValueAdjacentToken
        self.dividendPercent = dividendPercent
        self.mergeBonusShareValueMultiple = mergeBonusShareValueMultiple
        self.isPlayerOrderRandom = isPlayerOrderRandom
    }
}

extension HouseRules {

    // Default house rules.
    public static var `default`:HouseRules {
        return HouseRules(
                humanInitialCash: 6000,
                computerInitialCash: 6000,
                playerCoordinateOptionCount: 5,
                founderShareBonus: 5,
                shareValueAdjacentStar: 500,
                shareValueAdjacentToken: 100,
                dividendPercent: 5,
                mergeBonusShareValueMultiple: 10,
                isPlayerOrderRandom: true
            )
    }

    /// Minimum house rules values, integer values used as limits during game configuration.
    static var min: HouseRules {
        return HouseRules(
                humanInitialCash: 3000,
                computerInitialCash: 3000,
                playerCoordinateOptionCount: 3,
                founderShareBonus: 0,
                shareValueAdjacentStar: 200,
                shareValueAdjacentToken: 10,
                dividendPercent: 5,
                mergeBonusShareValueMultiple: 1,
                isPlayerOrderRandom: true
            )
    }

    /// Maximum house rules values, integer values used as limits during game configuration.
    static var max: HouseRules {
        return HouseRules(
                humanInitialCash: 10_000,
                computerInitialCash: 10_000,
                playerCoordinateOptionCount: 9,
                founderShareBonus: 10,
                shareValueAdjacentStar: 1000,
                shareValueAdjacentToken: 200,
                dividendPercent: 10,
                mergeBonusShareValueMultiple: 20,
                isPlayerOrderRandom: true
            )
    }
}
