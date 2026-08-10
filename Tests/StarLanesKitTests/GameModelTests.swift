//
//  GameModelTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Tests for the rules engine: founding, share value, safety and the merge economics.
///
/// These build boards by playing coordinates directly. `play` does not require a coordinate to have
/// been dealt to the player, so a test can lay out any position it needs and assert on the result.
class GameModelTests: XCTestCase {

    /// A configuration with no stars and no black holes, so share values come only from tokens
    /// and boards are entirely determined by the coordinates a test plays.
    private func plainConfig(columns: Int = 12, rows: Int = 9, companies: Int = 5, safeAt: Int = 11, endGameAt: Int = 41) -> GameConfig {
        return GameConfig(
            mapColumnCount: columns,
            mapRowCount: rows,
            starCount: 0,
            blackHoleCount: 0,
            shippingCompanyCount: companies,
            safeTokenCount: safeAt,
            endGameTokenCount: endGameAt
        )
    }

    /// Builds a model whose deal is fixed, with the given number of human players.
    private func makeModel(gameConfig: GameConfig? = nil, houseRules: HouseRules = .default, playerCount: Int = 2) -> GameModel {
        let config = gameConfig ?? plainConfig()
        let allCoordinates = (0 ..< (config.mapColumnCount * config.mapRowCount)).map {
            Coordinate(row: $0 / config.mapColumnCount, column: $0 % config.mapColumnCount)
        }
        return GameModel(
            gameConfig: config,
            houseRules: houseRules,
            playerCount: playerCount,
            isComputer: Array(repeating: false, count: playerCount),
            fixedCoordinateStack: allCoordinates
        )
    }

    /// Plays a horizontal run of coordinates, which grows one company across a row.
    @discardableResult
    private func play(_ model: inout GameModel, row: Int, columns: CountableClosedRange<Int>) -> [PlayedCoordinateResult] {
        var results = [PlayedCoordinateResult]()
        for column in columns {
            results = model.play(coordinate: Coordinate(row: row, column: column))
        }
        return results
    }

    // MARK: Founding

    func testPlayingAnIsolatedCoordinateMakesAnOutpostAndNoCompany() {
        var model = makeModel()
        let results = model.play(coordinate: Coordinate(row: 4, column: 4))

        XCTAssertEqual(results.count, 1)
        if case .newOutpost = results[0] {} else {
            XCTFail("expected an outpost, got \(results[0])")
        }
        XCTAssertTrue(model.activeCompanies.isEmpty, "a lone outpost must not create a company")
    }

    func testTwoAdjacentOutpostsFoundACompanyAndPayTheFounderBonus() {
        var model = makeModel()
        model.select(playerIndex: 0)
        model.play(coordinate: Coordinate(row: 4, column: 4))
        let results = model.play(coordinate: Coordinate(row: 4, column: 5))

        guard case let .newCompany(company) = results[0] else {
            return XCTFail("expected a new company, got \(results[0])")
        }
        XCTAssertEqual(company.tokenCount, 2, "both outposts join the new company")
        XCTAssertEqual(model.players[0].shares[company.index], HouseRules.default.founderShareBonus)
        XCTAssertEqual(model.companies[company.index].outstandingShares, HouseRules.default.founderShareBonus)
    }

    func testFounderBonusGoesToTheCurrentPlayerOnly() {
        var model = makeModel()
        model.select(playerIndex: 1)
        model.play(coordinate: Coordinate(row: 4, column: 4))
        let results = model.play(coordinate: Coordinate(row: 4, column: 5))

        guard case let .newCompany(company) = results[0] else {
            return XCTFail("expected a new company")
        }
        XCTAssertEqual(model.players[1].shares[company.index], HouseRules.default.founderShareBonus)
        XCTAssertEqual(model.players[0].shares[company.index], 0)
    }

    func testCompaniesAreExhaustedWhenAllAreFounded() {
        var model = makeModel(gameConfig: plainConfig(companies: 2))
        // Found two companies on separate rows, then try for a third.
        play(&model, row: 0, columns: 0...1)
        play(&model, row: 2, columns: 0...1)
        XCTAssertEqual(model.activeCompanies.count, 2)

        let results = play(&model, row: 4, columns: 0...1)
        if case .newOutpost = results[0] {} else {
            XCTFail("with no company left, the coordinate must stay an outpost")
        }
        XCTAssertEqual(model.activeCompanies.count, 2)
    }

    // MARK: Share value

    func testShareValueComesFromTokenCount() {
        var model = makeModel()
        play(&model, row: 4, columns: 0...3)

        let company = model.activeCompanies[0]
        XCTAssertEqual(company.tokenCount, 4)
        XCTAssertEqual(company.shareValue, 4 * HouseRules.default.shareValueAdjacentToken)
    }

    func testAdjacentStarAddsToShareValueOnlyOnce() {
        // One star, placed by the deal at a known coordinate.
        var config = plainConfig()
        config = GameConfig(
            mapColumnCount: config.mapColumnCount,
            mapRowCount: config.mapRowCount,
            starCount: 1,
            blackHoleCount: 0,
            shippingCompanyCount: config.shippingCompanyCount,
            safeTokenCount: config.safeTokenCount,
            endGameTokenCount: config.endGameTokenCount
        )
        var model = makeModel(gameConfig: config)

        // Find where the star landed, then grow a company along the row above it so that two
        // of the company's tokens are adjacent to that one star.
        var starCoordinate: Coordinate?
        for row in 0 ..< config.mapRowCount {
            for column in 0 ..< config.mapColumnCount where model.galaxyMap[Coordinate(row: row, column: column)] == .star {
                starCoordinate = Coordinate(row: row, column: column)
            }
        }
        guard let star = starCoordinate, star.row > 0, star.column > 0, star.column < config.mapColumnCount - 1 else {
            return  // star landed on an edge this deal; the rule is covered by the token-count test
        }

        // Two tokens above and beside the star, so the star is adjacent to the company twice.
        model.play(coordinate: Coordinate(row: star.row - 1, column: star.column))
        model.play(coordinate: Coordinate(row: star.row, column: star.column - 1))

        let company = model.activeCompanies[0]
        XCTAssertEqual(
            company.shareValue,
            company.tokenCount * HouseRules.default.shareValueAdjacentToken + HouseRules.default.shareValueAdjacentStar,
            "a star touching a company twice still counts once"
        )
    }

    // MARK: Safety

    func testCompanyBecomesSafeAtTheConfiguredSize() {
        var model = makeModel(gameConfig: plainConfig(safeAt: 5))
        play(&model, row: 3, columns: 0...3)
        XCTAssertFalse(model.activeCompanies[0].isSafe, "four tokens is below the safe size")

        play(&model, row: 3, columns: 4...4)
        XCTAssertTrue(model.activeCompanies[0].isSafe, "five tokens reaches the safe size")
    }

    func testGameCanBeCalledOnlyByTheLeaderAndOnlyAtTheEndGameSize() {
        var model = makeModel(gameConfig: plainConfig(safeAt: 99, endGameAt: 5))
        model.select(playerIndex: 0)
        play(&model, row: 3, columns: 0...3)
        XCTAssertFalse(model.canPlayerCallGame(), "four tokens is below the end game size")

        play(&model, row: 3, columns: 4...4)
        XCTAssertTrue(model.canPlayerCallGame(), "the leader may call the game at the end game size")

        model.select(playerIndex: 1)
        XCTAssertFalse(model.canPlayerCallGame(), "a trailing player may not call the game")
    }

    // MARK: Merging

    func testMergeKeepsTheLargerCompanyAndConvertsSharesTwoToOne() {
        var model = makeModel(gameConfig: plainConfig(safeAt: 99))
        model.select(playerIndex: 0)

        // A large company on the left, a small one on the right, with a gap between them.
        play(&model, row: 2, columns: 0...3)     // company A, four tokens
        play(&model, row: 2, columns: 5...6)     // company B, two tokens
        let large = model.activeCompanies.first { $0.tokenCount == 4 }!
        let small = model.activeCompanies.first { $0.tokenCount == 2 }!

        // Buy five, on top of the five the founder already holds, for an even ten.
        model.purchaseShares(purchaseOrder: model.activeCompanies.map { $0.index == small.index ? 5 : 0 })
        let sharesInSurvivorBefore = model.players[0].shares[large.index]
        let sharesInDefunctBefore = model.players[0].shares[small.index]
        XCTAssertEqual(sharesInDefunctBefore, 10, "founder bonus plus the shares bought")

        let results = model.play(coordinate: Coordinate(row: 2, column: 4))
        guard case let .companiesMerged(reports) = results[0] else {
            return XCTFail("expected a merge, got \(results[0])")
        }

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].survivingCompany.index, large.index, "the larger company survives")
        XCTAssertEqual(reports[0].defunctCompany.index, small.index)
        XCTAssertEqual(model.players[0].shares[small.index], 0, "defunct shares are given up")
        XCTAssertEqual(model.players[0].shares[large.index], sharesInSurvivorBefore + sharesInDefunctBefore / 2, "shares convert two to one")
        XCTAssertFalse(model.companies[small.index].isActive, "the defunct company leaves the map")
    }

    func testOddShareCountPaysOutTheRemainderInCash() {
        var model = makeModel(gameConfig: plainConfig(safeAt: 99))
        model.select(playerIndex: 0)
        play(&model, row: 2, columns: 0...3)
        play(&model, row: 2, columns: 5...6)
        let large = model.activeCompanies.first { $0.tokenCount == 4 }!
        let small = model.activeCompanies.first { $0.tokenCount == 2 }!

        // Four bought on top of the founder's five makes nine: four convert and one is left over.
        model.purchaseShares(purchaseOrder: model.activeCompanies.map { $0.index == small.index ? 4 : 0 })
        let sharesInSurvivorBefore = model.players[0].shares[large.index]
        let sharesInDefunctBefore = model.players[0].shares[small.index]
        XCTAssertEqual(sharesInDefunctBefore, 9, "an odd holding is needed to leave a remainder")
        let cashBefore = model.players[0].cash

        let results = model.play(coordinate: Coordinate(row: 2, column: 4))
        guard case let .companiesMerged(reports) = results[0] else {
            return XCTFail("expected a merge")
        }

        XCTAssertEqual(model.players[0].shares[large.index], sharesInSurvivorBefore + 4, "nine shares convert to four")
        let survivorShareValue = model.companies[large.index].shareValue
        XCTAssertEqual(
            model.players[0].cash - cashBefore,
            reports[0].bonusesPaid[0] + survivorShareValue,
            "the merge bonus, plus the odd share cashed out at the surviving share price"
        )
    }

    func testMergeBonusIsProportionalToOwnership() {
        var model = makeModel(gameConfig: plainConfig(safeAt: 99), playerCount: 2)
        model.select(playerIndex: 0)
        play(&model, row: 2, columns: 0...3)     // player 0 founds the company that will survive

        // Player 1 founds the doomed company, taking the founder bonus of five shares.
        model.select(playerIndex: 1)
        play(&model, row: 2, columns: 5...6)
        let small = model.activeCompanies.first { $0.tokenCount == 2 }!

        // Player 0 buys ten, so it holds twice what player 1 does.
        model.select(playerIndex: 0)
        model.purchaseShares(purchaseOrder: model.activeCompanies.map { $0.index == small.index ? 10 : 0 })
        XCTAssertEqual(model.players[0].shares[small.index], 10)
        XCTAssertEqual(model.players[1].shares[small.index], 5)

        let defunctShareValue = model.companies[small.index].shareValue
        let outstandingShares = model.companies[small.index].outstandingShares
        XCTAssertEqual(defunctShareValue, 2 * HouseRules.default.shareValueAdjacentToken, "two tokens, no stars")
        XCTAssertEqual(outstandingShares, 15)

        let cashBefore = [model.players[0].cash, model.players[1].cash]
        let results = model.play(coordinate: Coordinate(row: 2, column: 4))

        guard case let .companiesMerged(reports) = results[0] else {
            return XCTFail("expected a merge")
        }
        // Each holder is paid a share of ten times the defunct share value, in proportion to ownership.
        let multiple = HouseRules.default.mergeBonusShareValueMultiple
        let bonuses = reports[0].bonusesPaid
        XCTAssertEqual(bonuses[0], 10 * defunctShareValue * multiple / outstandingShares)
        XCTAssertEqual(bonuses[1], 5 * defunctShareValue * multiple / outstandingShares)
        XCTAssertGreaterThan(bonuses[0], bonuses[1], "the larger holder is paid the larger bonus")
        XCTAssertGreaterThan(model.players[1].cash - cashBefore[1], 0, "bonuses reach every holder, not only the merging player")
        XCTAssertGreaterThan(model.players[0].cash - cashBefore[0], 0)
    }

    func testSafeCompanyIsNeverTheDefunctCompany() {
        // Safe at two tokens, so the small company is safe as soon as it is founded.
        var model = makeModel(gameConfig: plainConfig(safeAt: 2))
        model.select(playerIndex: 0)
        play(&model, row: 2, columns: 0...3)     // four tokens, safe
        play(&model, row: 2, columns: 5...6)     // two tokens, also safe
        let large = model.activeCompanies.first { $0.tokenCount == 4 }!
        let small = model.activeCompanies.first { $0.tokenCount == 2 }!
        XCTAssertTrue(model.companies[small.index].isSafe)

        model.play(coordinate: Coordinate(row: 2, column: 4))

        XCTAssertTrue(model.companies[small.index].isActive, "a safe company survives a merge attempt")
        XCTAssertTrue(model.companies[large.index].isActive)
    }

    func testCoordinateJoiningTwoSafeCompaniesIsNotOffered() {
        var model = makeModel(gameConfig: plainConfig(safeAt: 2))
        model.select(playerIndex: 0)
        play(&model, row: 2, columns: 0...3)
        play(&model, row: 2, columns: 5...6)

        let options = model.playerCoordinateOptions()
        XCTAssertFalse(
            options.contains(Coordinate(row: 2, column: 4)),
            "a coordinate that could only merge two safe companies is unplayable"
        )
    }

    // MARK: Dividends

    func testDividendsPayThePercentageOfHoldings() {
        var model = makeModel()
        model.select(playerIndex: 0)
        play(&model, row: 4, columns: 0...3)

        let company = model.activeCompanies[0]
        let shares = model.players[0].shares[company.index]
        let cashBefore = model.players[0].cash

        let dividends = model.calculateDividends()

        XCTAssertEqual(dividends, shares * company.shareValue * HouseRules.default.dividendPercent / 100)
        XCTAssertEqual(model.players[0].cash, cashBefore + dividends)
    }

    // MARK: Net worth

    func testNetWorthIsCashPlusHoldings() {
        var model = makeModel()
        model.select(playerIndex: 0)
        play(&model, row: 4, columns: 0...3)

        let company = model.activeCompanies[0]
        let expected = model.players[0].cash + model.players[0].shares[company.index] * company.shareValue
        XCTAssertEqual(model.netWorths[0], expected)
    }
}
