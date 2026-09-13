//
//  SellSharesTests.swift
//
import XCTest
@testable import StarLanesKit

/// Tests for the optional share sale: the mirror of `purchaseShares`, at the current share value.
class SellSharesTests: XCTestCase {

    /// No stars and no black holes, so share values come only from tokens; nothing is safe from mergers.
    private let config = GameConfig(mapColumnCount: 12, mapRowCount: 9, starCount: 0, blackHoleCount: 0,
                                    shippingCompanyCount: 5, safeTokenCount: 99, endGameTokenCount: 41)

    private func makeModel() -> GameModel {
        let allCoordinates = (0 ..< (config.mapColumnCount * config.mapRowCount)).map {
            Coordinate(row: $0 / config.mapColumnCount, column: $0 % config.mapColumnCount)
        }
        return GameModel(gameConfig: config, houseRules: .default, playerCount: 2, isComputer: [false, false],
                         fixedCoordinateStack: allCoordinates)
    }

    /// Plays a horizontal run of coordinates, which grows one company across a row.
    private func play(_ model: inout GameModel, row: Int, columns: CountableClosedRange<Int>) {
        for column in columns {
            model.play(coordinate: Coordinate(row: row, column: column))
        }
    }

    /// One active company (id 0), founded by player 0, who then buys ten more shares.
    private func modelWithOneCompany() -> GameModel {
        var model = makeModel()
        model.select(playerIndex: 0)
        play(&model, row: 4, columns: 2...4)
        model.purchaseShares(purchaseOrder: [10])
        return model
    }

    func testSellingPaysShareValueAndReducesHoldings() {
        var model = modelWithOneCompany()
        let company = model.activeCompanies[0]
        let cashBefore = model.players[0].cash
        let sharesBefore = model.players[0].shares[company.index]
        let outstandingBefore = model.companies[company.index].outstandingShares
        XCTAssertGreaterThan(company.shareValue, 0)
        XCTAssertEqual(sharesBefore, HouseRules.default.founderShareBonus + 10)

        model.sellShares(saleOrder: [7])

        XCTAssertEqual(model.players[0].cash, cashBefore + 7 * company.shareValue)
        XCTAssertEqual(model.players[0].shares[company.index], sharesBefore - 7)
        XCTAssertEqual(model.companies[company.index].outstandingShares, outstandingBefore - 7)
    }

    func testAnAllZeroSaleOrderIsANoOp() throws {
        var model = modelWithOneCompany()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]   // key order is otherwise unspecified
        let before = try encoder.encode(model)
        model.sellShares(saleOrder: [0])
        XCTAssertEqual(try encoder.encode(model), before)
    }

    func testSaleOrderCorrelatesToActiveCompaniesNotCompanyIndex() {
        var model = makeModel()
        model.select(playerIndex: 0)
        // Found companies 0, 1, 2 and 3 (founding takes the lowest inactive index), then merge 0 into 1 and 2 into 3.
        play(&model, row: 0, columns: 0...1)     // company 0, two tokens
        play(&model, row: 0, columns: 3...5)     // company 1, three tokens
        play(&model, row: 4, columns: 0...1)     // company 2, two tokens
        play(&model, row: 4, columns: 3...5)     // company 3, three tokens
        XCTAssertEqual(model.activeCompanies.map { $0.index }, [0, 1, 2, 3])
        model.play(coordinate: Coordinate(row: 0, column: 2))
        model.play(coordinate: Coordinate(row: 4, column: 2))
        XCTAssertEqual(model.activeCompanies.map { $0.index }, [1, 3], "companies 0 and 2 were absorbed")

        let company3 = model.companies[3]
        let cashBefore = model.players[0].cash
        let heldIn1 = model.players[0].shares[1], heldIn3 = model.players[0].shares[3]
        XCTAssertGreaterThanOrEqual(heldIn3, 2)

        // Element 1 of the order is the second ACTIVE company, id 3 — not company id 1.
        model.sellShares(saleOrder: [0, 2])

        XCTAssertEqual(model.players[0].shares[3], heldIn3 - 2)
        XCTAssertEqual(model.players[0].shares[1], heldIn1, "company id 1 is untouched")
        XCTAssertEqual(model.players[0].cash, cashBefore + 2 * company3.shareValue)
        XCTAssertEqual(model.companies[3].outstandingShares, company3.outstandingShares - 2)
    }

    func testShareValuesDoNotMoveOnASale() {
        var model = modelWithOneCompany()
        let valuesBefore = model.companies.map { $0.shareValue }
        let netWorthOfOthersBefore = model.netWorths[1]
        let netWorthBefore = model.netWorths[0]

        model.sellShares(saleOrder: [12])

        XCTAssertEqual(model.companies.map { $0.shareValue }, valuesBefore)
        XCTAssertEqual(model.netWorths[0], netWorthBefore, "a sale at share value converts holdings to cash one for one")
        XCTAssertEqual(model.netWorths[1], netWorthOfOthersBefore)
    }
}
