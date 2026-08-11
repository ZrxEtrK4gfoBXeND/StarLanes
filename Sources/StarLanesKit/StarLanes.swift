//
//  StarLanes.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

/// Entry points for the game.
///
/// The engine, the view models and the console front end all stay internal to this library.
/// This type is the whole public surface, which keeps the executable to a single line and lets
/// the test suite drive the engine directly with `@testable import`.
public enum StarLanes {

    /// Runs the game, or the command line action named by the arguments.
    /// - parameter arguments: Command line arguments, excluding the name of the executable.
    public static func run(arguments: [String]) {
        let frontEnd = ConsoleFrontEnd()

        switch arguments.first {
        case "--history"?:
            // Reviewing only reads the log, so a saved game is left untouched.
            frontEnd.displayGameHistory()

        case "--rewind"?:
            if let turnNumber = Int(arguments.dropFirst().first ?? "") {
                frontEnd.rewind(toTurnNumber: turnNumber)
            } else {
                frontEnd.output.write()
                frontEnd.output.write("USAGE: starlanes --rewind <TURN>")
                frontEnd.output.write("RUN starlanes --history TO SEE THE TURNS THAT CAN BE REPLAYED.", terminator: "\n\n")
            }

        case "--record"?:
            frontEnd.displayMatchRecords()

        case "--help"?, "-h"?:
            frontEnd.output.write()
            frontEnd.output.write("STAR LANES", terminator: "\n\n")
            frontEnd.output.write("  starlanes                 PLAY THE GAME")
            frontEnd.output.write("  starlanes --record        SHOW THE RUNNING RECORD OF EVERY MATCHUP")
            frontEnd.output.write("  starlanes --history       REVIEW THE LAST GAME PLAYED")
            frontEnd.output.write("  starlanes --rewind <N>    RESUME THE LAST GAME FROM TURN N", terminator: "\n\n")

        default:
            play(frontEnd: frontEnd)
        }
    }

    /// Runs the game loop to completion against a front end.
    /// - parameter frontEnd: Front end to play through. The console front end is used by the game;
    ///   the test suite supplies a scripted one.
    static func play(frontEnd: FrontEnd) {
        let magisterLudi = MagisterLudi(frontEnd: frontEnd)

        while !magisterLudi.isGameOver {
            magisterLudi.gameLoopIteration()
        }
    }
}
