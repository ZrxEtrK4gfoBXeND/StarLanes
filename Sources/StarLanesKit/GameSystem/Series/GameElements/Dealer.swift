//
//  Dealer.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// A pseudo-entity that manages the unplayed coordinates, dealing out coordinates to play and filtering out unplayable coordinates.
struct Dealer: Codable {

    /// This is the single source of unplayed coordinates in the game model.
    private var unplayedCoordinateStack = [Coordinate]()

    /// Unplayed coordinates held back from dealing until opened (map regions). Optional feature:
    /// nil when unused, so it is omitted from encoded games and existing save files keep their format.
    private var closedCoordinates: [Coordinate]?

    /// Basic initializer.
    /// - parameter coordinateStack: Ordered (shuffled) array of coordinates.
    init(coordinateStack: [Coordinate]) {
        unplayedCoordinateStack = coordinateStack
    }

    /// Deal one playable coordinate.
    /// - returns: Coordinate, or nil if no playable coordinates exists.
    mutating func dealCoordinate() -> Coordinate? {
        return unplayedCoordinateStack.isEmpty ? nil : unplayedCoordinateStack.removeLast()
    }

    /// Deal several playable coordinates.
    /// - parameter count: number of playable coordinates to deal.
    /// - returns: array of playable coordinates; if fewer than `count` playable coordinates exist, all playable coordinates are returned, which could be zero.
    mutating func dealCoordinates(count: Int) -> [Coordinate] {
        return (0 ..< count).compactMap { _ in dealCoordinate() }
    }

    /// Removes playable coordinates from the unplayed stack.
    /// This occurs when a company becomes safe and coordinates that would merge it with another safe company are removed from play.
    /// - parameter using: filter predicate is supplied by game model with logic to protect safe companies.
    mutating func filterCoordinates(using predicate: (Coordinate) -> Bool) {
        unplayedCoordinateStack = unplayedCoordinateStack.filter(predicate)
    }

    // MARK: Closed regions (optional feature)

    /// Coordinates currently held back from dealing, in the order they were closed.
    var closed: [Coordinate] {
        return closedCoordinates ?? []
    }

    /// Holds back the given coordinates: any still in the unplayed stack are removed from it, and `returned`
    /// (coordinates already dealt out but handed back, e.g. from players' initial options) are added too.
    /// - parameter coordinates: Coordinates to close.
    /// - parameter returned: Dealt coordinates to take back into the closed set.
    mutating func close(_ coordinates: [Coordinate], returning returned: [Coordinate] = []) {
        let closing = Set(coordinates)
        let fromStack = unplayedCoordinateStack.filter { closing.contains($0) }
        unplayedCoordinateStack = unplayedCoordinateStack.filter { !closing.contains($0) }
        closedCoordinates = closed + fromStack + returned
    }

    /// Releases closed coordinates onto the top of the unplayed stack, so they are dealt next.
    /// Coordinates are dealt in the order given; any that are not closed are ignored.
    /// - parameter coordinates: Coordinates to open.
    mutating func open(_ coordinates: [Coordinate]) {
        let closedSet = Set(closed)
        var seen = Set<Coordinate>()
        let opening = coordinates.filter { closedSet.contains($0) && seen.insert($0).inserted }
        let openingSet = Set(opening)
        closedCoordinates = closed.filter { !openingSet.contains($0) }
        // dealCoordinate() takes from the end, so push in reverse to deal in the given order.
        unplayedCoordinateStack += opening.reversed()
    }

}
