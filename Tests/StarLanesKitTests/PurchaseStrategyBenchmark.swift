//
//  PurchaseStrategyBenchmark.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Plays computer players against each other to measure a share buying strategy.
///
/// Every game is fully determined by its seed, so a result is repeatable and a change in the
/// strategy is the only thing that can move the number. Each seed is played twice with the
/// players swapped, because moving first is worth something and the benchmark should not
/// reward it.
class PurchaseStrategyBenchmark: XCTestCase {

    /// Result of a head to head run.
    private struct Result {
        var winsByStrategy = [PurchaseStrategy: Int]()
        var netWorthByStrategy = [PurchaseStrategy: Int]()
        var gamesPlayed = 0
        var unfinishedGames = 0
    }

    /// Plays one game between two computer players and reports who won.
    /// - parameter first: Strategy of the player who moves first.
    /// - parameter second: Strategy of the player who moves second.
    /// - parameter seed: Fixes the map and the deal.
    /// - parameter gameConfig: Game configuration to play.
    /// - returns: The winning strategy and both final net worths, or nil when the game did not finish.
    private func play(first: PurchaseStrategy,
                      second: PurchaseStrategy,
                      seed: Int,
                      gameConfig: GameConfig) -> (winner: PurchaseStrategy, netWorths: [PurchaseStrategy: Int])? {
        let playerDefs = [
            VmoPlayerDef(name: "FIRST", isComputer: true, purchaseStrategy: first),
            VmoPlayerDef(name: "SECOND", isComputer: true, purchaseStrategy: second)
        ]
        let frontEnd = TestFrontEnd(
            gameConfig: gameConfig,
            houseRules: .default,
            playerDefs: playerDefs,
            input: FirstOptionInput(),
            fixedCoordinateStack: TestFrontEnd.coordinateStack(gameConfig: gameConfig, seed: seed),
            fixedPlayerOrder: [0, 1]
        )
        frontEnd.playersDecideForThemselves = true
        StarLanes.play(frontEnd: frontEnd)

        guard let ranking = frontEnd.finalRanking, ranking.count == 2 else {
            return nil
        }
        let strategyByName = ["FIRST": first, "SECOND": second]
        var netWorths = [PurchaseStrategy: Int]()
        for player in ranking {
            // With both players on the same strategy the totals collapse into one entry, which is
            // fine: that run is only used to check the harness is not biased.
            netWorths[strategyByName[player.name]!] = player.netWorth
        }
        return (strategyByName[ranking[0].name]!, netWorths)
    }

    /// Plays a set of seeds both ways round.
    private func runHeadToHead(_ challenger: PurchaseStrategy,
                               versus incumbent: PurchaseStrategy,
                               seeds: CountableRange<Int>,
                               gameConfig: GameConfig = .basic) -> Result {
        var result = Result()
        for seed in seeds {
            for (first, second) in [(challenger, incumbent), (incumbent, challenger)] {
                guard let game = play(first: first, second: second, seed: seed, gameConfig: gameConfig) else {
                    result.unfinishedGames += 1
                    continue
                }
                result.gamesPlayed += 1
                result.winsByStrategy[game.winner] = (result.winsByStrategy[game.winner] ?? 0) + 1
                for (strategy, netWorth) in game.netWorths {
                    result.netWorthByStrategy[strategy] = (result.netWorthByStrategy[strategy] ?? 0) + netWorth
                }
            }
        }
        return result
    }

    private func report(_ title: String, _ result: Result, _ strategies: [PurchaseStrategy]) {
        print("")
        print("=== \(title) ===")
        print("games: \(result.gamesPlayed)\(result.unfinishedGames > 0 ? ", unfinished: \(result.unfinishedGames)" : "")")
        for strategy in strategies {
            let wins = result.winsByStrategy[strategy] ?? 0
            let share = result.gamesPlayed > 0 ? 100 * Double(wins) / Double(result.gamesPlayed) : 0
            let total = result.netWorthByStrategy[strategy] ?? 0
            print(String(format: "  %-12@ %2d wins (%5.1f%%)  total net worth %d", strategy.rawValue as NSString, wins, share, total))
        }
    }

    /// The harness itself: the same strategy on both sides should not favour a seat.
    func testHarnessDoesNotFavourEitherSeat() {
        var firstSeatWins = 0
        var games = 0
        for seed in 0 ..< 12 {
            let playerDefs = [
                VmoPlayerDef(name: "FIRST", isComputer: true, purchaseStrategy: .classic),
                VmoPlayerDef(name: "SECOND", isComputer: true, purchaseStrategy: .classic)
            ]
            let frontEnd = TestFrontEnd(
                gameConfig: .basic,
                houseRules: .default,
                playerDefs: playerDefs,
                input: FirstOptionInput(),
                fixedCoordinateStack: TestFrontEnd.coordinateStack(gameConfig: .basic, seed: seed),
                fixedPlayerOrder: [0, 1]
            )
            frontEnd.playersDecideForThemselves = true
            StarLanes.play(frontEnd: frontEnd)
            guard let ranking = frontEnd.finalRanking else { continue }
            games += 1
            if ranking[0].name == "FIRST" {
                firstSeatWins += 1
            }
        }
        print("")
        print("=== seat bias, classic against itself ===")
        print("  first seat won \(firstSeatWins) of \(games)")
        XCTAssertGreaterThan(games, 0, "no game finished, so the benchmark measures nothing")
    }

    /// Measures the strategies against each other and reports the result.
    ///
    /// This deliberately does not assert that one strategy beats the other. Three formulations
    /// have been measured here, and none has beaten the original:
    ///
    ///     scoring companies by expected return    53% of 46 games, inside the margin of chance
    ///     weighting that by a merger's likelihood 38% of 100 games, clearly worse
    ///     refusing companies with nowhere to go   50% of 100 games, identical play
    ///
    /// Asserting a win here would either be a lie or a test that fails on an honest result. What
    /// the assertion protects instead is the benchmark itself: games have to finish, or the
    /// numbers above describe nothing.
    func testMeasureMergeAwareAgainstClassic() {
        // Fifty seeds a side, played both ways round. At a hundred games a coin flip lands
        // within about seven points of even, so a result outside that range means something.
        let result = runHeadToHead(.mergeAware, versus: .classic, seeds: 0 ..< 50)
        report("merge aware against classic, basic map", result, [.mergeAware, .classic])

        XCTAssertGreaterThan(result.gamesPlayed, 0, "no game finished, so the benchmark measures nothing")
        XCTAssertEqual(result.unfinishedGames, 0, "every game should reach an end")
    }

    func testMeasureMergeAwareAgainstClassicOnTheDeluxeMap() {
        let result = runHeadToHead(.mergeAware, versus: .classic, seeds: 0 ..< 8, gameConfig: .deluxe)
        report("merge aware against classic, deluxe map", result, [.mergeAware, .classic])

        XCTAssertGreaterThan(result.gamesPlayed, 0, "no game finished, so the benchmark measures nothing")
        XCTAssertEqual(result.unfinishedGames, 0, "every game should reach an end")
    }

    /// The trap that lost the last game: a cornered company that is both cheapest and most owned.
    func testMergeAwarePrefersACompanyThatCanMergeOverACorneredOne() {
        // A big company along a row, and a small one that can still be joined to it.
        var model = GameModel(
            gameConfig: GameConfig(mapColumnCount: 12, mapRowCount: 9, starCount: 0, blackHoleCount: 0,
                                   shippingCompanyCount: 5, safeTokenCount: 99, endGameTokenCount: 99),
            houseRules: .default,
            playerCount: 2,
            isComputer: [true, true],
            fixedCoordinateStack: (0 ..< 108).map { Coordinate(row: $0 / 12, column: $0 % 12) }
        )
        model.select(playerIndex: 0)
        for column in 0 ... 5 {
            model.play(coordinate: Coordinate(row: 2, column: column))     // the big company
        }
        for column in 7 ... 8 {
            model.play(coordinate: Coordinate(row: 2, column: column))     // small, one gap away
        }
        // A cornered company: hemmed in against the edge by the big one.
        model.play(coordinate: Coordinate(row: 0, column: 11))
        model.play(coordinate: Coordinate(row: 1, column: 11))

        let ranking = PurchaseScoring.rank(gameModel: model)
        let byIndex = Dictionary(uniqueKeysWithValues: ranking.map { ($0.companyIndex, $0.score) })
        let small = model.activeCompanies.first { $0.tokenCount == 2 && $0.index != 2 }!
        let cornered = model.activeCompanies.first { $0.index == 2 }!

        print("")
        print("=== scores ===")
        for scoring in ranking {
            print("  company \(scoring.companyIndex) size \(model.companies[scoring.companyIndex].tokenCount) score \(String(format: "%.2f", scoring.score))")
        }
        XCTAssertGreaterThan(
            byIndex[small.index]!, byIndex[cornered.index]!,
            "a company that can be absorbed by a larger one is worth more than one with nowhere to go"
        )
    }
}
