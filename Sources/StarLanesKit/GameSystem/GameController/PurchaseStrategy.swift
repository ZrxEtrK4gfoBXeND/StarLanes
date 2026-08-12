//
//  PurchaseStrategy.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// How a computer player decides which shares to buy.
public enum PurchaseStrategy: String, Codable {
    /// The original heuristic: buy the cheapest company when it is well under the price of the
    /// company the player owns most of, otherwise buy more of that company.
    case classic
    /// Buys where a merger is about to pay, judged from the map.
    case mergeAware
}

/// Scores each company by what a dollar spent on it is expected to return.
///
/// The scores come from the merge rules rather than from taste:
///
/// - A company that goes defunct pays every holder a bonus of `mergeBonusShareValueMultiple`
///   times the defunct share value, split by ownership. A holder of `k` of `o` outstanding shares
///   receives `k * v * multiple / o`, having paid `k * v`, so the bonus returns `multiple / o`
///   per dollar. Companies with few outstanding shares therefore pay the most, whatever the price.
/// - Defunct shares convert into the survivor two for one, turning `k * v` of stock into
///   `k / 2 * survivorValue`, which returns `survivorValue / (2 * v)` per dollar. This is the
///   "buy low, merge high" of the instructions: it profits whenever the surviving share price is
///   more than twice the defunct one.
/// - A company that simply grows gains `shareValueAdjacentToken` per new token, so room to expand
///   is worth something even with no merger in sight.
///
/// A company that can neither be absorbed nor grow returns only its dividends. That is the trap
/// the original heuristic could fall into, buying the same cornered company every turn because it
/// was both the cheapest on the board and the one it owned most of.
struct PurchaseScoring {
    /// The company being scored.
    let companyIndex: Int
    /// Expected return per dollar spent. 1.0 is a company that merely holds its value.
    let score: Double
    /// False when the company can neither grow nor be absorbed at a profit, so a dollar put into
    /// it is expected to stay exactly where it is. This is the cornered company that the original
    /// heuristic could buy every turn until its money was gone.
    let hasFuture: Bool
}

extension PurchaseScoring {

    /// Scores every active company for a player.
    /// - parameter gameModel: Current state of the game.
    /// - returns: A score per active company, best first.
    static func rank(gameModel: GameModel) -> [PurchaseScoring] {
        let galaxyMap = gameModel.galaxyMap
        let companies = gameModel.companies

        /// Coordinates that are still empty, where play can happen.
        var emptyCoordinates = [Coordinate]()
        for row in 0 ..< galaxyMap.rowCount {
            for column in 0 ..< galaxyMap.columnCount {
                let coordinate = Coordinate(row: row, column: column)
                if galaxyMap[coordinate] == nil {
                    emptyCoordinates.append(coordinate)
                }
            }
        }

        // Room to grow, and which companies could be joined to which, judged from the empty
        // coordinates: playing one joins every company it touches.
        var growthRoom = [Int: Int]()
        var touchingCompanies = [Int: Set<Int>]()
        // How many places could join this company to a bigger one. More places means the merger
        // is likelier to happen, and sooner.
        var mergePlaces = [Int: Int]()
        for coordinate in emptyCoordinates {
            let adjacent = Set(coordinate.adjacentCoordinates.compactMap { galaxyMap[$0]?.companyID })
            for companyID in adjacent {
                growthRoom[companyID] = (growthRoom[companyID] ?? 0) + 1
                let others = adjacent.subtracting([companyID])
                touchingCompanies[companyID] = (touchingCompanies[companyID] ?? Set<Int>()).union(others)
                if others.contains(where: { companies[$0].tokenCount > companies[companyID].tokenCount }) {
                    mergePlaces[companyID] = (mergePlaces[companyID] ?? 0) + 1
                }
            }
        }

        return gameModel.activeCompanies.map { company -> PurchaseScoring in
            let shareValue = Double(company.shareValue)
            guard shareValue > 0 else {
                return PurchaseScoring(companyIndex: company.index, score: 0, hasFuture: false)
            }

            // What a dollar is worth if the company is left to grow: it holds its value, and
            // gains as the company expands into the space around it. Damped, and capped at a
            // doubling, because a company never captures every empty square beside it.
            let room = Double(growthRoom[company.index] ?? 0)
            let growth = min(room / Double(max(company.tokenCount, 1)), 1.0)
            let valueIfHeld = 1.0 + 0.5 * growth

            // What a dollar is worth if the company is absorbed.
            var valueIfMerged = 0.0
            var chanceOfMerging = 0.0
            if !company.isSafe {
                let largerNeighbours = (touchingCompanies[company.index] ?? Set<Int>())
                    .map { companies[$0] }
                    .filter { $0.tokenCount > company.tokenCount }
                if let bestSurvivor = largerNeighbours.max(by: { $0.shareValue < $1.shareValue }) {
                    // Bonus per dollar is the multiple divided by the shares outstanding.
                    // The multiple is a house rule the model keeps to itself, so the default is
                    // assumed; being wrong about it only scales every candidate equally.
                    let outstandingShares = Double(max(company.outstandingShares, 1))
                    let bonus = Double(HouseRules.default.mergeBonusShareValueMultiple) / outstandingShares
                    // Two for one conversion into the surviving company.
                    let conversion = Double(bestSurvivor.shareValue) / (2.0 * shareValue)
                    valueIfMerged = bonus + conversion

                    // The more places the two companies could be joined, the sooner it happens.
                    chanceOfMerging = min(Double(mergePlaces[company.index] ?? 0) / 3.0, 1.0)
                }
            }

            let score = chanceOfMerging * valueIfMerged + (1.0 - chanceOfMerging) * valueIfHeld

            // Somewhere for the money to go: room to expand, or a merger that pays more than it
            // costs. Being absorbed into a company worth less than twice this one loses half the
            // stake, so that does not count as a future.
            let hasFuture = room > 0 || (chanceOfMerging > 0 && valueIfMerged > 1.0)

            return PurchaseScoring(companyIndex: company.index, score: score, hasFuture: hasFuture)
        }
        .sorted { $0.score > $1.score }
    }
}
