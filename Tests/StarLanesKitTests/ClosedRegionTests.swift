//
//  ClosedRegionTests.swift
//
import XCTest
@testable import StarLanesKit

/// Tests for the optional closed-region feature: parts of the map held back from dealing until opened.
class ClosedRegionTests: XCTestCase {

    private let config = GameConfig.basic

    private var allCoordinates: [Coordinate] {
        return (0 ..< (config.mapColumnCount * config.mapRowCount)).map {
            Coordinate(row: $0 / config.mapColumnCount, column: $0 % config.mapColumnCount)
        }
    }

    /// Coordinates in columns `columns` (whole rows of the map).
    private func columns(_ columns: CountableRange<Int>) -> [Coordinate] {
        return allCoordinates.filter { columns.contains($0.column) }
    }

    private func makeModel(closed: [Coordinate]) -> GameModel {
        return GameModel(gameConfig: config, houseRules: .default, playerCount: 3, isComputer: [false, true, true],
                         fixedCoordinateStack: allCoordinates, closedCoordinates: closed)
    }

    /// Deals and plays each player's first option in turn, returning every coordinate played.
    private func playRounds(_ model: inout GameModel, rounds: Int) -> [Coordinate] {
        var played = [Coordinate]()
        for _ in 0 ..< rounds {
            for index in model.players.indices {
                model.select(playerIndex: index)
                guard let coordinate = model.playerCoordinateOptions().first else { continue }
                _ = model.play(coordinate: coordinate)
                played.append(coordinate)
            }
        }
        return played
    }

    func testDefaultGameHasNoClosedCoordinatesAndEncodesAsBefore() throws {
        let model = GameModel(gameConfig: config, houseRules: .default, playerCount: 2, isComputer: [false, false],
                              fixedCoordinateStack: allCoordinates)
        XCTAssertTrue(model.closedCoordinates.isEmpty)
        let json = String(data: try JSONEncoder().encode(model), encoding: .utf8)!
        XCTAssertFalse(json.contains("closedCoordinates"), "save format must not change when the feature is unused")
    }

    func testClosedCoordinatesAreNeverDealt() {
        let closed = columns(6 ..< 12)
        var model = makeModel(closed: closed)
        let closedSet = Set(closed)
        XCTAssertTrue(model.players.allSatisfy { $0.coordinateOptions.allSatisfy { !closedSet.contains($0) } },
                      "initial options must exclude closed regions")
        let played = playRounds(&model, rounds: 40)
        XCTAssertFalse(played.isEmpty)
        XCTAssertTrue(played.allSatisfy { !closedSet.contains($0) })
        XCTAssertTrue(model.players.allSatisfy { $0.coordinateOptions.allSatisfy { !closedSet.contains($0) } })
    }

    func testClosedRegionIsExhaustedThenOpened() {
        let closed = columns(6 ..< 12)
        var model = makeModel(closed: closed)
        _ = playRounds(&model, rounds: 60)
        XCTAssertFalse(model.hasPlayableTiles(), "the open region should run out")
        XCTAssertFalse(model.closedCoordinates.isEmpty)

        let opening = columns(6 ..< 9)
        model.open(coordinates: opening)
        XCTAssertEqual(Set(model.closedCoordinates), Set(columns(9 ..< 12)).intersection(Set(closed)))
        model.select(playerIndex: 0)
        let options = model.playerCoordinateOptions()
        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(options.allSatisfy { (6 ..< 9).contains($0.column) })
    }

    func testOpenIgnoresCoordinatesThatAreNotClosed() {
        let closed = columns(8 ..< 12)
        var model = makeModel(closed: closed)
        _ = playRounds(&model, rounds: 60)
        let a = model.closedCoordinates[0], b = model.closedCoordinates[1]
        let neverClosed = Coordinate(row: 0, column: 0)
        XCTAssertFalse(model.closedCoordinates.contains(neverClosed))
        model.open(coordinates: [a, neverClosed, b, a])
        model.select(playerIndex: 1)
        let options = model.playerCoordinateOptions()
        // The never-closed coordinate is ignored; the duplicate is dealt once.
        XCTAssertEqual(Set(options), Set([a, b]))
        XCTAssertEqual(options.count, 2)
        XCTAssertFalse(model.closedCoordinates.contains(a))
        XCTAssertFalse(model.closedCoordinates.contains(b))
    }

    func testClosedCoordinatesSurviveCodableRoundTrip() throws {
        var model = makeModel(closed: columns(6 ..< 12))
        _ = playRounds(&model, rounds: 5)
        model.open(coordinates: columns(6 ..< 9))
        let decoded = try JSONDecoder().decode(GameModel.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(decoded.closedCoordinates, model.closedCoordinates)
        var a = model.clone(), b = decoded.clone()
        a.select(playerIndex: 2)
        b.select(playerIndex: 2)
        XCTAssertEqual(a.playerCoordinateOptions(), b.playerCoordinateOptions())
    }

    func testStarsAreStillDealtAcrossTheWholeMap() {
        let withRegions = makeModel(closed: columns(6 ..< 12))
        let without = GameModel(gameConfig: config, houseRules: .default, playerCount: 3, isComputer: [false, true, true],
                                fixedCoordinateStack: allCoordinates)
        let stars: (GameModel) -> [Coordinate] = { model in self.allCoordinates.filter { model.galaxyMap[$0] == .star } }
        XCTAssertEqual(stars(withRegions), stars(without))
    }
}
