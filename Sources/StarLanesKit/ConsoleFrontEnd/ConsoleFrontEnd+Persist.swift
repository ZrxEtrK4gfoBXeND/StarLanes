//
//  ConsoleFrontEnd+Persist.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

import Foundation

/// File is stored in users home directory.
private let fileURL = URL(fileURLWithPath: NSString(string: "~/.starlanes").expandingTildeInPath)

/// Log of the most recently played game, stored alongside the session file.
let gameLogFileURL = URL(fileURLWithPath: NSString(string: "~/.starlanes-log").expandingTildeInPath)

/// Running record of every matchup, stored alongside the session file.
let matchRecordFileURL = URL(fileURLWithPath: NSString(string: "~/.starlanes-record").expandingTildeInPath)

/// Front end delegate to store and retrieve a persisted game series.
/// The blob of data is never interpreted by the delegate.
extension ConsoleFrontEnd: FrontEndPersist {

    /// Delegation to retrieve a previously persisted game/series.
    /// - parameter completionHandler: The delegate calls this with the blob of data used to persist the game/series.
    func retrievePersistedSession(completionHandler: (Data?) -> Void) {
        completionHandler(try? Data(contentsOf: fileURL))
    }

    /// Delegation to store a game/series.
    /// - parameter data: Blob of data containing the game/series.
    func persistSession(data: Data) {
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Delegation to store the log of the game being played.
    /// - parameter data: Blob of data containing the game log.
    func persistGameLog(data: Data) {
        try? data.write(to: gameLogFileURL, options: .atomic)
    }

    /// Delegation to retrieve the log of the last game played.
    /// - parameter completionHandler: The delegate calls this with the blob of data used to persist the log.
    func retrieveGameLog(completionHandler: (Data?) -> Void) {
        completionHandler(try? Data(contentsOf: gameLogFileURL))
    }

    /// Delegation to store the running record of every matchup.
    /// - parameter data: Blob of data containing the match record.
    func persistMatchRecord(data: Data) {
        try? data.write(to: matchRecordFileURL, options: .atomic)
    }

    /// Delegation to retrieve the running record of every matchup.
    /// - parameter completionHandler: The delegate calls this with the blob of data used to persist the record.
    func retrieveMatchRecord(completionHandler: (Data?) -> Void) {
        completionHandler(try? Data(contentsOf: matchRecordFileURL))
    }

    /// The running record of every matchup, read directly.
    /// Used when configuring a series, where the front end needs the record before the
    /// Magister Ludi has any part in the decision.
    var matchRecord: MatchRecord? {
        guard let data = try? Data(contentsOf: matchRecordFileURL) else {
            return nil
        }
        return MatchRecord(data: data)
    }

    /// Writes a session directly, used to restore a turn rewound from the game log.
    /// - parameter data: Blob of data containing the game/series.
    static func writeSession(data: Data) -> Bool {
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
