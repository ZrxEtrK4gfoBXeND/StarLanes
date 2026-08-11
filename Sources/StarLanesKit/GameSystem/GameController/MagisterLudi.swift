//
//  MagisterLudi.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

/// The heart of the game engine. Also known as a view model.
/// Magister Ludi is responsible for running the game and series.
public class MagisterLudi {
    /// Version of the game, presented on the title card. Update this when the game changes.
    private let starlanesVersion = "1.2"
    /// Version of the persisted state file format.
    /// Only update this when that format changes, because a session written by any other
    /// version is discarded, taking the series and its leaderboard with it.
    private let persistedStateVersion = "1.1"
    /// Front end implementation.
    private let frontEnd: FrontEnd
    /// Current state.
    private var state: MagisterLudiState
    /// All players correlated with input implmentations.
    private var playerAgents: [PlayerAgent]
    /// Current series container (persistable)
    private var series: Series!
    /// Current game information container (persistable)
    private var game: Game!
    /// Move-by-move record of the current game (persistable, separate from the session).
    private var gameLog: GameLog!
    /// The last few games played, holding `gameLog` at its front.
    private var gameLogArchive = GameLogArchive()

    /// Basic initializer
    /// - parameter frontEnd: Front end implementation
    public init(frontEnd: FrontEnd) {
        self.frontEnd = frontEnd
        state = .displayTitle
        playerAgents = [PlayerAgent]()
    }

    /// Host calls this to know when Magister Ludi is finished.
    /// The name is nostalgic to the point of being a little imprecise: this really represents
    /// that a game has finished and the player doesn't want to play another game in the series right now.
    public var isGameOver: Bool {
        return state == .gameOver
    }

    /// Host calls this repeatedly until `isGameOver` returns true.
    /// This implements the Magister Ludi state machine.
    public func gameLoopIteration() {
        switch state {
        case .displayTitle:
            state = .awaitingInput
            frontEnd.display(title: VmoTitleCard(version: starlanesVersion)) {
                state = .retrievePersistedSession
            }

        case .retrievePersistedSession:
            state = .awaitingInput
            frontEnd.retrievePersistedSession { data in
                if  let data = data,
                    let persistedSession = PersistedSessionContainer(data: data), persistedSession.version == persistedStateVersion {
                    series = persistedSession.series
                    if let game = persistedSession.game {
                        self.game = game
                        state = .awaitingInput
                        frontEnd.display(galaxyMap: VmoGalaxyMap(galaxyMap: game.model.galaxyMap))
                        frontEnd.display(gameConfig: series.gameConfig, houseRules: series.houseRules)
                        frontEnd.display(playerRanking: VmoPlayerRanking(game: game, series: series))
                        frontEnd.inputResumeSession(input: frontEnd.input, isResumingGame: true) { resumeSession in
                            state = resumeSession ? (game.playerIndex == series.playerDefs.count ? .endRound :  .startTurn) : .configureSeries
                        }
                    } else {
                        state = .awaitingInput
                        frontEnd.display(gameConfig: series.gameConfig, houseRules: series.houseRules)
                        frontEnd.display(leaderboard: series.leaderboard.vmoLeaderboardEntries)
                        frontEnd.inputResumeSession(input: frontEnd.input, isResumingGame: false) { resumeSession in
                            state = resumeSession ? .startGame : .configureSeries
                        }
                    }

                    if state != .configureSeries {
                        playerAgents = series.playerDefs.map { PlayerAgent(name: $0.name, input: $0.isComputer  ? ComputerInput() : frontEnd.input) }
                        // Continue the existing log when it belongs to this same unfinished game,
                        // so resuming does not discard the turns already recorded.
                        frontEnd.retrieveGameLog { logData in
                            gameLogArchive = (logData.flatMap { GameLogArchive(data: $0) }) ?? GameLogArchive()
                            if  let persistedLog = gameLogArchive.currentGame,
                                persistedLog.endOfGameDescription == nil,
                                persistedLog.playerNames == series.playerDefs.map({ $0.name }) {
                                gameLog = persistedLog
                            } else {
                                gameLog = GameLog(version: persistedStateVersion, series: series)
                                gameLogArchive.beginGame(gameLog)
                            }
                        }
                    }
                } else {
                    state = .configureSeries
                }
            }

        case .configureSeries:
            // Game Constants
            let (minPlayerCount, maxPlayerCount) = (2, 4)

            state = .awaitingInput
            frontEnd.configureSeries(minPlayerCount: minPlayerCount, maxPlayerCount: maxPlayerCount) { (gameConfig, houseRules, playerDefs) in
                if playerDefs.count < minPlayerCount || playerDefs.count > maxPlayerCount {
                    state = .error(.invalidPlayerCount(min:minPlayerCount, max:maxPlayerCount, submitted:playerDefs.count))
                } else if Set(playerDefs.map { $0.name }).count != playerDefs.count {
                    state = .error(.nonuniquePlayerNames(submittedNames:playerDefs.map { $0.name }))
                } else {
                    series = Series(gameConfig: gameConfig, houseRules: houseRules, playerDefs: playerDefs, leaderboard: Leaderboard(playerDefs: playerDefs))
                    playerAgents = playerDefs.map { PlayerAgent(name: $0.name, input: $0.isComputer  ? ComputerInput() : frontEnd.input) }
                    state = .startGame
                }
            }

        case .startGame:
            state = .awaitingInput
            frontEnd.configureGame(gameConfig: series.gameConfig, houseRules: series.houseRules, playerDefs: series.playerDefs) { fixedCoordinateStack, fixedPlayerOrder in
                let gameModel = GameModel(
                                    gameConfig: series.gameConfig,
                                    houseRules: series.houseRules,
                                    playerCount: series.playerDefs.count,
                                    isComputer: series.playerDefs.map { $0.isComputer},
                                    fixedCoordinateStack: fixedCoordinateStack
                                )
                let playerOrder: [Int]
                if let fixedPlayerOrder = fixedPlayerOrder {
                    playerOrder = fixedPlayerOrder
                } else if series.houseRules.isPlayerOrderRandom {
                    playerOrder = series.playerDefs.indices.map { Int($0) }.shuffled()
                } else {
                    playerOrder = series.playerDefs.indices.map { Int($0) }
                }
                let laggardMonitor = LaggardMonitor(gameConfig: series.gameConfig, isComputer: series.playerDefs.map { $0.isComputer})
                let companiesDeclaredSafe = Array(repeating: false, count: series.gameConfig.shippingCompanyCount)
                game = Game(model: gameModel, laggardMonitor: laggardMonitor, companiesDeclaredSafe: companiesDeclaredSafe, playerIndex: 0, playerOrder: playerOrder)
                playerAgents.resetAnnouncements()
                gameLog = GameLog(version: persistedStateVersion, series: series)
                // Load the archive before adding to it, so games from earlier runs are kept.
                frontEnd.retrieveGameLog { logData in
                    gameLogArchive = (logData.flatMap { GameLogArchive(data: $0) }) ?? GameLogArchive()
                }
                gameLogArchive.beginGame(gameLog)
                state = .startRound
            }

        case .startRound:
            game.playerIndex = 0
            state = .startTurn

        case .startTurn:
            game.model.select(playerIndex: game.currentPlayerIndex)
            gameLog.beginTurn(playerName: series.playerDefs[game.currentPlayerIndex].name)
            frontEnd.display(turnStart: series.playerDefs[game.currentPlayerIndex])
            state = .checkEarlyGameEnd

        case .checkEarlyGameEnd:
            state = .awaitingInput
            if game.model.canPlayerCallGame() {
                frontEnd.inputCallGame(input: playerAgents[game.currentPlayerIndex].input, endGameTokenCount: series.gameConfig.endGameTokenCount) { playerCalledGame in
                    if playerCalledGame {
                        state = .endGame(.playerCalledGame(series.playerDefs[game.currentPlayerIndex].name))
                    } else {
                        state = .selectCoordinate
                    }
                }
            } else if game.laggardMonitor.isPlayerLagging(playerIndex: game.currentPlayerIndex) {
                frontEnd.inputConcedeGame(input: playerAgents[game.currentPlayerIndex].input, playerDef: series.playerDefs[game.currentPlayerIndex]) { playerConcededGame in
                    if playerConcededGame {
                        state = .endGame(.playerConcededGame(series.playerDefs[game.currentPlayerIndex].name))
                    } else {
                        state = .selectCoordinate
                    }
                }
            } else {
                state = .selectCoordinate
            }

        case .selectCoordinate:
            let coordinateOptions = game.model.playerCoordinateOptions()
            if !coordinateOptions.isEmpty {
                let input = playerAgents[game.currentPlayerIndex].input
                if let computerInput = input as? ComputerInput {
                    computerInput.decideCoordinateSelection(playerIndex: game.currentPlayerIndex, coordinateOptions: coordinateOptions, gameModel: game.model)
                }

                frontEnd.display(galaxyMap: VmoGalaxyMap(galaxyMap: game.model.galaxyMap.markedUp(coordinateOptions: coordinateOptions)))
                frontEnd.display(announcements: playerAgents[game.currentPlayerIndex].publishAnnouncements())
                frontEnd.display(playerRanking: VmoPlayerRanking(game: game, series: series))

                state = .awaitingInput
                frontEnd.inputCoordinate(input: input, playerDef: series.playerDefs[game.currentPlayerIndex], coordinateOptions: coordinateOptions) { coordinate in
                    var loggedEvents = [String]()
                    for playedCoordinateResult in game.model.play(coordinate: coordinate) {
                        switch playedCoordinateResult {
                        case .newOutpost:
                            loggedEvents.append("NEW OUTPOST")
                        case let .companyExpanded(company):
                            loggedEvents.append("EXPANDED \(VmoCompany(company: company).name)")
                        case let .newCompany(company):
                            loggedEvents.append("FOUNDED \(VmoCompany(company: company).name)")
                            playerAgents.announce(.newCompany(VmoCompany(company: company), founder:series.playerDefs[game.currentPlayerIndex].name))
                        case let .companiesMerged(mergeReports):
                            for mergeReport in mergeReports {
                                loggedEvents.append("MERGED \(VmoCompany(company: mergeReport.defunctCompany).name) INTO \(VmoCompany(company: mergeReport.survivingCompany).name)")
                                for index in series.playerDefs.indices {
                                    playerAgents[index].announce(.merger(
                                                                     byPlayer: series.playerDefs[mergeReport.mergePlayerIndex].name,
                                                                     survivingCompany: VmoCompany(company: mergeReport.survivingCompany),
                                                                     defunctCompany: VmoCompany(company: mergeReport.defunctCompany),
                                                                     bonus: mergeReport.bonusesPaid[index]
                                                                   )
                                                                 )
                                }
                            }
                        case let .companiesDestroyed(companyIDs):
                            for companyID in companyIDs {
                                loggedEvents.append("BLACK HOLE DESTROYED \(VmoCompany(company: Company(index: companyID)).name)")
                                playerAgents.announce(.destroyedCompany(VmoCompany(company: Company(index: companyID))))
                            }
                        }
                    }

                    for company in game.model.activeCompanies {
                        if company.isSafe && !game.companiesDeclaredSafe[company.index] {
                            loggedEvents.append("\(VmoCompany(company: company).name) IS NOW SAFE")
                            playerAgents.announce(.safeCompany(VmoCompany(company: company)))
                            game.companiesDeclaredSafe[company.index] = true
                        }
                    }

                    gameLog.recordMove(coordinate: "\(coordinate)", events: loggedEvents)

                    frontEnd.display(galaxyMap: VmoGalaxyMap(galaxyMap: game.model.galaxyMap))
                    frontEnd.display(announcements: playerAgents[game.currentPlayerIndex].publishAnnouncements())
                    frontEnd.display(playerRanking: VmoPlayerRanking(game: game, series: series))

                    state = .calculateDividends
                }
            } else {
                state = .calculateDividends
            }

        case .calculateDividends:
            let dividends = game.model.calculateDividends()
            gameLog.recordDividends(dividends)
            playerAgents[game.currentPlayerIndex].announce(.dividends(dividends))
            state = .purchaseShares

        case .purchaseShares:
            let input = playerAgents[game.currentPlayerIndex].input
            if let computerInput = input as? ComputerInput {
                computerInput.decideSharePurchase(playerIndex: game.currentPlayerIndex, gameModel: game.model)
            }
            let vmoActiveCompanies = game.model.activeCompanies.map { VmoCompany(company: $0) }
            frontEnd.display(announcements: playerAgents[game.currentPlayerIndex].publishAnnouncements())
            frontEnd.display(activeCompanies: vmoActiveCompanies, endGameTokenCount: series.gameConfig.endGameTokenCount)
            state = .awaitingInput
            frontEnd.inputPurchaseOrder(input: input, activeCompanies: vmoActiveCompanies, availableCash: game.model.players[game.currentPlayerIndex].cash) { purchaseOrder in
                game.model.purchaseShares(purchaseOrder: purchaseOrder)
                gameLog.recordPurchases(
                    zip(vmoActiveCompanies.indices, purchaseOrder)
                        .filter { $0.1 > 0 }
                        .map { "\($0.1) x \(vmoActiveCompanies[$0.0].name)" }
                )
                state = .endTurn
            }

        case .endTurn:
            game.playerIndex += 1
            state = game.playerIndex == series.playerDefs.count ? .endRound : .startTurn

            // Snapshot after the player index advances, so restoring this entry resumes with the
            // next player to act, matching the state the session file is saved in below.
            gameLog.endTurn(game: game)
            gameLogArchive.updateCurrentGame(gameLog)
            if let logData = gameLogArchive.data {
                frontEnd.persistGameLog(data: logData)
            }

            let persistedSessionContainer = PersistedSessionContainer(version: persistedStateVersion, series: series, game: game)
            if let data = persistedSessionContainer.data {
                frontEnd.persistSession(data: data)
            }

        case .endRound:
            game.laggardMonitor.endRound(gameModel: game.model)
            state = game.model.hasPlayableTiles() ? .startRound : .endGame(.noMorePlayableCoordinates)

        case let .endGame(reason):
            let vmoPlayerRanking = VmoPlayerRanking(game: game, series: series)
            frontEnd.display(endOfGameReason: reason, vmoPlayerRanking: vmoPlayerRanking)

            let endOfGameDescription: String
            switch reason {
            case let .playerCalledGame(name):
                endOfGameDescription = "\(name) CALLED THE GAME"
            case let .playerConcededGame(name):
                endOfGameDescription = "\(name) CONCEDED THE GAME"
            case .noMorePlayableCoordinates:
                endOfGameDescription = "NO MORE PLAYABLE COORDINATES"
            }
            // A player who ends the game does so instead of taking their turn, so the turn they
            // opened has nothing in it.
            gameLog.discardIncompleteTurn()
            gameLog.finish(
                description: endOfGameDescription,
                ranking: vmoPlayerRanking.rankedPlayers.map { GameLogRanking(name: $0.name, netWorth: $0.netWorth) }
            )
            gameLogArchive.updateCurrentGame(gameLog)
            if let logData = gameLogArchive.data {
                frontEnd.persistGameLog(data: logData)
            }

            series.leaderboard.gameEnded(winningPlayerName: vmoPlayerRanking.rankedPlayers.first!.name)
            frontEnd.display(leaderboard: series.leaderboard.vmoLeaderboardEntries)

            // The running record of this line-up, which outlives the series and the saved game.
            frontEnd.retrieveMatchRecord { data in
                var matchRecord = (data.flatMap { MatchRecord(data: $0) }) ?? MatchRecord()
                matchRecord.recordGame(
                    playerDefs: series.playerDefs,
                    gameConfig: series.gameConfig,
                    houseRules: series.houseRules,
                    ranking: vmoPlayerRanking.rankedPlayers.map { GameLogRanking(name: $0.name, netWorth: $0.netWorth) }
                )
                if let matchRecordData = matchRecord.data {
                    frontEnd.persistMatchRecord(data: matchRecordData)
                }
                if let matchup = matchRecord.matchup(forPlayerNames: series.playerDefs.map { $0.name }) {
                    frontEnd.display(matchRecord: VmoMatchRecord(matchup: matchup))
                }
            }

            let persistedSessionContainer = PersistedSessionContainer(version: persistedStateVersion, series: series, game: nil)
            if let data = persistedSessionContainer.data {
                frontEnd.persistSession(data: data)
            }

            state = .awaitingInput
            frontEnd.inputPlayAnotherGame(input: frontEnd.input) { playAnotherGame in
                state = playAnotherGame ? .startGame : .gameOver
            }

        case let .error(magisterLudiError):
            frontEnd.display(error: magisterLudiError)
            state = .gameOver

        case .awaitingInput, .gameOver:
            break
        }
    }
}
