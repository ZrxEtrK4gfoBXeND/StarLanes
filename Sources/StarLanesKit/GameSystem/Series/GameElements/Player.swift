//
//  Player.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

import Foundation

/// Player model during the game.
public struct Player: Codable {
    /// Index that correlates players to the player array.
    public let index: Int
    /// Player's current cash
    public var cash: Int
    /// Player's current playable coordinate options.
    public var coordinateOptions: [Coordinate]
    /// List of share quantites. Array size correlates to all companies, active or not.
    public var shares: [Int]

    /// Player initializer.
    /// - parameter index: Index in correlated array of player definitions. Invariant throughout game.
    /// - parameter cash: Player's initial cash.
    /// - parameter shippingCompanyCount: Used to create array of share counts.
    /// - parameter coordinateOptions: Initial playable coordinate options.
    public init(index: Int, cash: Int, shippingCompanyCount: Int, coordinateOptions: [Coordinate]) {
        self.index = index
        self.cash = cash
        self.coordinateOptions = coordinateOptions
        shares = Array(repeating: 0, count: shippingCompanyCount)
    }
}
