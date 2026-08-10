//
//  TokenTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Tests for the single character encoding used to draw and to persist the galaxy map.
/// A token that does not survive the trip through its own text form corrupts a saved game,
/// so every case is checked in both directions.
class TokenTests: XCTestCase {

    func testFixedTokensRoundTrip() {
        for token in [Token.star, .blackHole, .destroyed, .outpost] {
            let text = String(describing: token)
            XCTAssertEqual(text.count, 1, "a map cell is one character")
            XCTAssertEqual(Token(text), token, "\(token) did not survive the round trip through \"\(text)\"")
        }
    }

    func testCompanyTokensRoundTripForEveryCompany() {
        // Deluxe games have ten companies; the encoding allows more.
        for companyID in 0 ..< 10 {
            let token = Token.company(companyID)
            let text = String(describing: token)
            XCTAssertEqual(text.count, 1)
            XCTAssertEqual(Token(text), token, "company \(companyID) encoded as \"\(text)\" and did not survive")
        }
    }

    func testCompanyTokensUseTheExpectedLetters() {
        XCTAssertEqual(String(describing: Token.company(0)), "A")
        XCTAssertEqual(String(describing: Token.company(9)), "J")
    }

    func testMarkerTokensRoundTripForEveryCoordinateOption() {
        // Markers are numbered from one, up to the largest allowed coordinate option count.
        for marker in 1 ... HouseRules.max.playerCoordinateOptionCount {
            let token = Token.marker(marker)
            let text = String(describing: token)
            XCTAssertEqual(text.count, 1, "marker \(marker) must encode to one character")
            XCTAssertEqual(Token(text), token, "marker \(marker) encoded as \"\(text)\" and did not survive")
        }
    }

    func testFirstMarkerIsDrawnAsOne() {
        // The player is offered options numbered from 1, so the map must agree.
        XCTAssertEqual(String(describing: Token.marker(1)), "1")
        XCTAssertEqual(String(describing: Token.marker(9)), "9")
    }

    func testInvalidTextIsRejected() {
        for text in ["", "AB", ".", "?", ":"] {
            XCTAssertNil(Token(text), "\"\(text)\" is not a token")
        }
    }

    func testMarkedUpMapNumbersOptionsFromOne() {
        let galaxyMap = GalaxyMap(columnCount: 12, rowCount: 9)
        let options = [Coordinate(row: 0, column: 0), Coordinate(row: 1, column: 1)]
        let markedUp = galaxyMap.markedUp(coordinateOptions: options)

        XCTAssertEqual(markedUp[options[0]], .marker(1))
        XCTAssertEqual(markedUp[options[1]], .marker(2))
        XCTAssertEqual(VmoGalaxyMap(galaxyMap: markedUp).map[0][0], "1", "the first option is shown as 1")
    }

    func testGalaxyMapSurvivesEncodingAndDecoding() {
        let galaxyMap = GalaxyMap(columnCount: 12, rowCount: 9)
        galaxyMap[Coordinate(row: 0, column: 0)] = .star
        galaxyMap[Coordinate(row: 1, column: 2)] = .outpost
        galaxyMap[Coordinate(row: 2, column: 3)] = .company(4)
        galaxyMap[Coordinate(row: 3, column: 4)] = .blackHole
        galaxyMap[Coordinate(row: 4, column: 5)] = .destroyed

        guard let data = try? JSONEncoder().encode(galaxyMap),
              let decoded = try? JSONDecoder().decode(GalaxyMap.self, from: data) else {
            return XCTFail("galaxy map did not encode and decode")
        }

        XCTAssertEqual(decoded.columnCount, 12)
        XCTAssertEqual(decoded.rowCount, 9)
        XCTAssertEqual(decoded[Coordinate(row: 0, column: 0)], .star)
        XCTAssertEqual(decoded[Coordinate(row: 1, column: 2)], .outpost)
        XCTAssertEqual(decoded[Coordinate(row: 2, column: 3)], .company(4))
        XCTAssertEqual(decoded[Coordinate(row: 3, column: 4)], .blackHole)
        XCTAssertEqual(decoded[Coordinate(row: 4, column: 5)], .destroyed)
    }

    func testCoordinateRoundTripsThroughItsLabel() {
        for row in 0 ..< 9 {
            for column in 0 ..< 20 {
                let coordinate = Coordinate(row: row, column: column)
                let text = coordinate.description
                XCTAssertEqual(text.count, 2, "\(text) should be a row digit and a column letter")
                XCTAssertEqual(Coordinate(text), coordinate, "\(text) did not survive the round trip")
            }
        }
    }

    func testCoordinateLabelsMatchTheDisplayedGrid() {
        // Row 1 column A is the top left of the map as drawn.
        XCTAssertEqual(Coordinate(row: 0, column: 0).description, "1A")
        XCTAssertEqual(Coordinate(row: 8, column: 19).description, "9T")
    }
}
