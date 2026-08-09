//
//  ConsoleInput.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Ends the game when the input stream is exhausted, which happens when the player presses Ctrl-D
/// or when stdin is redirected from a file or pipe that runs dry.
/// The prompt loops that call this would otherwise spin forever on a nil `readLine()`, writing
/// prompts at full speed. The session is persisted at the end of every turn, so at most the
/// current turn is lost.
func exitOnEndOfInput() -> Never {
    print()
    print("END OF INPUT. GOODBYE.")
    exit(0)
}

/// Console front end implementation of Input protocol
struct ConsoleInput: Input {

    /// Queries a player for a yes or no response. For invalid responses, the user is prompted again.
    /// - parameter output: Output stream to present prompt.
    /// - returns: "Y" or "N"
    func readYorN(output: Output) -> String {
        while true {
            output.write("? ", terminator: "")
            guard let str = readLine() else {
                exitOnEndOfInput()
            }
            if str == "Y" || str == "y" {
                return "Y"
            } else if str == "N" || str == "n" {
                return "N"
            }
        }
    }

    /// Queries a player for an integer value. For invalid responses, the user is prompted again.
    /// - parameter output: Output stream to present prompt.
    /// - parameter min: Minimum acceptable input value.
    /// - parameter max: Maximum acceptable input value.
    func readInt(output: Output, min: Int, max: Int, defaultValue: Int?) -> Int {
         while true {
            output.write("? ", terminator: "")
            guard let str = readLine() else {
                exitOnEndOfInput()
            }
            if defaultValue != nil && str.isEmpty {
                output.write(" \(defaultValue!)")
                return defaultValue!
            }
            if let int = Int(str) {
               if int >= min && int <= max {
                   return int
               }
            }
        }
    }
}
