//
//  GameConfig.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

import Foundation

/// Game Configuration parameters. Invariant during series.
public struct GameConfig: Codable, Equatable {
    /// Number of columns in Galaxy Map for each game in the series.
    public let mapColumnCount: Int
    /// Number of rows in Galaxy Map for each game in the series.
    public let mapRowCount: Int
    /// Number of stars on the map for each game in the series.
    public let starCount: Int
    /// Number of black holes on the map for each game in the series.
    public let blackHoleCount: Int
    /// Number of shipping companies in the series.
    public let shippingCompanyCount: Int
    /// Number of company tokens on the map to declare a company "safe" from being merged into another company.
    public let safeTokenCount: Int
    /// Once a company has this many tokens on the map, the lead player can call the game.
    public let endGameTokenCount: Int

    /// Explicit memberwise initializer, so it can be public.
    public init(mapColumnCount: Int, mapRowCount: Int, starCount: Int, blackHoleCount: Int,
                shippingCompanyCount: Int, safeTokenCount: Int, endGameTokenCount: Int) {
        self.mapColumnCount = mapColumnCount
        self.mapRowCount = mapRowCount
        self.starCount = starCount
        self.blackHoleCount = blackHoleCount
        self.shippingCompanyCount = shippingCompanyCount
        self.safeTokenCount = safeTokenCount
        self.endGameTokenCount = endGameTokenCount
    }
}

extension GameConfig {

    /// Basic game configuration.
    public static var basic: GameConfig {
        return GameConfig(
                  mapColumnCount: 12,
                  mapRowCount: 9,
                  starCount: 8,
                  blackHoleCount: 0,
                  shippingCompanyCount: 5,
                  safeTokenCount: 11,
                  endGameTokenCount: 41
               )
    }

    /// Deluxe game configuration.
    public static var deluxe: GameConfig {
        return GameConfig(
                   mapColumnCount: 16,
                   mapRowCount: 9,
                   starCount: 12,
                   blackHoleCount: 0,
                   shippingCompanyCount: 10,
                   safeTokenCount: 15,
                   endGameTokenCount: 55
               )
    }

    /// Minimum game configuration values, used as limits during game configuration.
    static var min: GameConfig {
        return GameConfig(
                   mapColumnCount: 7,
                   mapRowCount: 5,
                   starCount: 0,
                   blackHoleCount: 0,
                   shippingCompanyCount: 5,
                   safeTokenCount: 5,
                   endGameTokenCount: 15
               )
    }

    /// Maximum game configuration values, used as limits during game configuration.
    static var max: GameConfig {
        return GameConfig(
                   mapColumnCount: 20,
                   mapRowCount: 9,
                   starCount: 15,
                   blackHoleCount: 4,
                   shippingCompanyCount: 10,
                   safeTokenCount: 65,
                   endGameTokenCount: 180
               )
    }
}
