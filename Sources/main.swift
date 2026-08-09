//
//  main.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import Foundation

let consoleFrontEnd = ConsoleFrontEnd()
let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "--history"?:
    // Review the last game played. This only reads the log, so a saved game is untouched.
    consoleFrontEnd.displayGameHistory()

case "--rewind"?:
    // Restore the state saved at a turn of the last game, so play can continue from there.
    if let turnNumber = Int(arguments.dropFirst().first ?? "") {
        consoleFrontEnd.rewind(toTurnNumber: turnNumber)
    } else {
        print()
        print("USAGE: starlanes --rewind <TURN>")
        print("RUN starlanes --history TO SEE THE TURNS THAT CAN BE REPLAYED.")
        print()
    }

case "--help"?, "-h"?:
    print()
    print("STAR LANES")
    print()
    print("  starlanes                 PLAY THE GAME")
    print("  starlanes --history       REVIEW THE LAST GAME PLAYED")
    print("  starlanes --rewind <N>    RESUME THE LAST GAME FROM TURN N")
    print()

default:
    let magisterLudi = MagisterLudi(frontEnd: consoleFrontEnd)

    while !magisterLudi.isGameOver {
        magisterLudi.gameLoopIteration()
    }
}
