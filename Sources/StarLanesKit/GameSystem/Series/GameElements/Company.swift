//
//  Company.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

import Foundation

/// GameModel representation of a Company
/// - SeeAlso: VmoCompany, the view model of this object which contains presentation fields such as `name`.
public struct Company: Codable {
    /// A count of occupied coordinates of this company.
    public var tokenCount         = 0
    /// Current share value of company.
    /// Calculated from:
    ///   ````
    ///   `tokenCount` * `houseRules.shareValueAdjacentToken` + adjacent (unique) star count * `houseRules.shareValueAdjacentStar`
    ///   ````
    public var shareValue         = 0
    /// Record of whether the company is safe from mergers.
    /// Evaluated from `tokenCount` >= `gameConfig.safeTokenCount`
    public var isSafe             = false
    /// Total shares purchased from all players.
    public var outstandingShares  = 0

    /// Index into gameModels' company array.
    /// Also used as company identifier: 0 = Altair, 1 = Betelgeuse, etc.
    public let index: Int
    /// Index converted into first letter of company name.
    public let monogram: String

    /// Initialize a company.
    /// - parameter index: The index of this company in gameModel's company array.
    public init(index: Int) {
        self.index = index
        let letterA = UInt8(65)
        monogram = String(UnicodeScalar(letterA + UInt8(index)))
    }

    /// Reports whether the company exists on the galaxy map.
    /// - Returns: boolean. If false, this structs values of `tokenCount`, `shareValue`, `isSafe` and `outstandingShares` are zero or false.
    public var isActive: Bool {
        return tokenCount > 0
    }
}
