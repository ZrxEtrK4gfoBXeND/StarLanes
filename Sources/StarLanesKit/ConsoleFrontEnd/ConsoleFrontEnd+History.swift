//
//  ConsoleFrontEnd+History.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// Presentation of the log of the last game played, and restoration of a turn from it.
/// These are invoked from the command line rather than from the Magister Ludi state machine,
/// so reviewing a game never disturbs a game in progress.
extension ConsoleFrontEnd {

    /// Reads the archive of recent games.
    /// - returns: The archive, or nil when no game has been logged yet.
    private func retrieveGameLogArchive() -> GameLogArchive? {
        guard let data = try? Data(contentsOf: gameLogFileURL) else {
            return nil
        }
        return GameLogArchive(data: data)
    }

    /// Reports that no log is available, which is expected before any game has been played to a turn.
    private func displayNoGameLog() {
        output.write()
        output.write("NO GAME HISTORY FOUND.")
        output.write("PLAY A GAME AND THE MOVES WILL BE RECORDED HERE.", terminator: "\n\n")
    }

    /// Presents the running record of every matchup, most recently played first.
    func displayMatchRecords() {
        guard let matchRecord = matchRecord, !matchRecord.matchups.isEmpty else {
            output.write()
            output.write("NO MATCHES ON RECORD.")
            output.write("FINISH A GAME AND THE RESULT WILL BE RECORDED HERE.", terminator: "\n\n")
            return
        }

        output.write()
        for matchup in matchRecord.matchups.sorted(by: { $0.lastPlayed > $1.lastPlayed }) {
            display(matchRecord: VmoMatchRecord(matchup: matchup))
        }
    }

    /// Presents the move-by-move history of a recent game.
    /// - parameter gameNumber: 1 for the most recent game, 2 for the one before it, and so on.
    func displayGameHistory(gameNumber: Int = 1) {
        guard let archive = retrieveGameLogArchive(), !archive.games.isEmpty else {
            displayNoGameLog()
            return
        }

        guard let gameLog = archive.game(number: gameNumber) else {
            output.write()
            output.write("GAME \(gameNumber) IS NOT KEPT. \(archive.games.count) GAME\(archive.games.count == 1 ? " IS" : "S ARE") ON RECORD.", terminator: "\n\n")
            return
        }

        let gameConfig = gameLog.series.gameConfig!
        let companyNames = (0 ..< gameConfig.shippingCompanyCount).map { VmoCompany(company: Company(index: $0)).name }

        output.write()
        output.write("* * * \(gameNumber == 1 ? "HISTORY OF LAST GAME" : "HISTORY OF GAME \(gameNumber) OF \(archive.games.count)") * * *", terminator: "\n\n")
        output.write("MAP: \(gameConfig.mapColumnCount) X \(gameConfig.mapRowCount), COMPANIES: \(gameConfig.shippingCompanyCount), SAFE AT: \(gameConfig.safeTokenCount), END GAME AT: \(gameConfig.endGameTokenCount)")
        output.write("PLAYERS: " + gameLog.series.playerDefs.map { "\($0.name)\($0.isComputer ? " (COMPUTER)" : "")" }.joined(separator: ", "), terminator: "\n\n")

        if gameLog.entries.isEmpty {
            output.write("NO TURNS WERE RECORDED.", terminator: "\n\n")
            return
        }

        output.write("TURN  RND  PLAYER      MOVE  BIGGEST   DIVIDEND    NET WORTH  EVENT")
        output.write("----  ---  ----------  ----  --------  ----------  ---------  -----------------------------")

        for entry in gameLog.entries {
            // Largest company after the turn, shown as progress toward ending the game.
            var biggest = ""
            if let largestSize = entry.companySizes.max(), largestSize > 0 {
                let largestIndex = entry.companySizes.enumerated().first { $0.element == largestSize }?.offset ?? 0
                let monogram = largestIndex < companyNames.count ? String(companyNames[largestIndex].prefix(1)) : "?"
                biggest = "\(monogram) \(largestSize)/\(gameConfig.endGameTokenCount)"
            }

            // Net worth of the player who took this turn.
            var netWorth = ""
            let playerIndex = gameLog.playerNames.enumerated().first { $0.element == entry.playerName }?.offset
            if let playerIndex = playerIndex, playerIndex < entry.netWorths.count {
                netWorth = String(money: entry.netWorths[playerIndex])
            }

            let events = entry.events.isEmpty ? "" : entry.events.joined(separator: "; ")
            output.write("\(String("\(entry.turnNumber)", pad: 6))\(String("\(entry.roundNumber)", pad: 5))\(String(entry.playerName, pad: 12))\(String(entry.coordinate.isEmpty ? "-" : entry.coordinate, pad: 6))\(String(biggest, pad: 10))\(String(String(money: entry.dividends), pad: 12))\(String(netWorth, pad: 11))\(events)")

            for purchase in entry.purchases {
                output.write("\(String("", pad: 24))BOUGHT \(purchase)")
            }
        }
        output.write()

        if let endOfGameDescription = gameLog.endOfGameDescription {
            output.write("GAME ENDED: \(endOfGameDescription)")
            for (rank, ranking) in zip(gameLog.finalRanking.indices, gameLog.finalRanking) {
                output.write("  #\(rank+1) \(String(ranking.name, pad: 12))\(String(money: ranking.netWorth))")
            }
        } else {
            output.write("GAME DID NOT FINISH. THE LAST RECORDED TURN IS \(gameLog.entries.count).")
        }
        output.write()

        let rewindableTurns = gameLog.entries.filter { $0.snapshot != nil }.count
        if rewindableTurns > 0 {
            output.write("\(rewindableTurns) TURNS CAN BE REPLAYED. TO RESUME FROM A TURN:", terminator: "\n\n")
            output.write("    starlanes --rewind <TURN>", terminator: "\n\n")
        } else {
            output.write("THIS GAME IS KEPT FOR REVIEW ONLY. ONLY THE LAST GAME CAN BE REPLAYED.", terminator: "\n\n")
        }

        // Point the way to the other games kept, so they are not invisible.
        if archive.games.count > 1 {
            output.write("GAMES ON RECORD:")
            for (index, game) in zip(archive.games.indices, archive.games) {
                let outcome = game.endOfGameDescription ?? "UNFINISHED, \(game.entries.count) TURNS"
                output.write("  \(index + 1)) \(String(game.playerNames.joined(separator: " VS "), pad: 20))\(outcome)\(index + 1 == gameNumber ? "   <- SHOWN ABOVE" : "")")
            }
            output.write()
            output.write("    starlanes --history <GAME>", terminator: "\n\n")
        }
    }

    /// Restores the game state saved at a turn, so play can continue from that point.
    /// The saved session is replaced, so the player is asked to confirm first.
    /// - parameter turnNumber: Turn number to resume from, as listed by `--history`.
    func rewind(toTurnNumber turnNumber: Int) {
        // Only the most recent game keeps the states needed to resume from a turn.
        guard let archive = retrieveGameLogArchive(), let gameLog = archive.currentGame else {
            displayNoGameLog()
            return
        }

        guard let entry = gameLog.entry(turnNumber: turnNumber) else {
            output.write()
            output.write("TURN \(turnNumber) IS NOT IN THE HISTORY. RECORDED TURNS ARE 1 TO \(gameLog.entries.count).", terminator: "\n\n")
            return
        }

        guard let snapshot = entry.snapshot else {
            output.write()
            output.write("TURN \(turnNumber) HAS NO SAVED STATE AND CANNOT BE REPLAYED.", terminator: "\n\n")
            return
        }

        output.write()
        output.write("REWIND TO TURN \(turnNumber): \(entry.playerName) PLAYED \(entry.coordinate.isEmpty ? "NOTHING" : entry.coordinate)")
        if !entry.events.isEmpty {
            output.write("  \(entry.events.joined(separator: "; "))")
        }
        let discardedTurnCount = gameLog.entries.count - turnNumber
        output.write()
        output.write("THIS REPLACES YOUR SAVED GAME.")
        if discardedTurnCount > 0 {
            output.write("THE \(discardedTurnCount) TURNS AFTER TURN \(turnNumber) WILL BE DROPPED FROM THE HISTORY,")
            output.write("BECAUSE PLAY FROM HERE REPLACES THEM.")
        }
        output.write("PROCEED (Y/N) ", terminator: "")

        if ConsoleInput().readYorN(output: output) != "Y" {
            output.write()
            output.write("REWIND CANCELLED. YOUR SAVED GAME AND HISTORY ARE UNCHANGED.", terminator: "\n\n")
            return
        }

        let persistedSessionContainer = PersistedSessionContainer(version: gameLog.version, series: gameLog.series, game: snapshot)
        output.write()
        if let data = persistedSessionContainer.data, ConsoleFrontEnd.writeSession(data: data) {
            // Drop the abandoned turns so the resumed game continues one consistent timeline.
            // Only the current game changes; the games kept behind it are untouched.
            var rewoundArchive = archive
            var rewoundGameLog = gameLog
            rewoundGameLog.discardTurns(after: turnNumber)
            rewoundArchive.updateCurrentGame(rewoundGameLog)
            if let logData = rewoundArchive.data {
                persistGameLog(data: logData)
            }
            output.write("DONE. RUN starlanes AND RESUME THE GAME TO CONTINUE FROM TURN \(turnNumber + 1).", terminator: "\n\n")
        } else {
            output.write("COULD NOT WRITE THE SAVED GAME. YOUR SAVED GAME AND HISTORY ARE UNCHANGED.", terminator: "\n\n")
        }
    }
}
