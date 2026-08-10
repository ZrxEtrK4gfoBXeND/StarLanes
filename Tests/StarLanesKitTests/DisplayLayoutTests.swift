//
//  DisplayLayoutTests.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//
import XCTest
@testable import StarLanesKit

/// Tests that the console tables line up, with and without color.
///
/// Column drift is invisible in a diff and easy to introduce, and coloring a cell before padding it
/// silently breaks alignment because escape sequences are counted as width. Both are checked here.
class DisplayLayoutTests: XCTestCase {

    /// Collects what the front end presents so a test can measure it.
    private func render(_ body: (ConsoleFrontEnd, SilentOutput) -> Void) -> [String] {
        let output = SilentOutput()
        let frontEnd = ConsoleFrontEnd(input: FirstOptionInput(), output: output)
        body(frontEnd, output)
        return output.lines
    }

    private func makeRanking(companyCount: Int, safeCompanyIndices: Set<Int> = []) -> VmoPlayerRanking {
        let companies = (0 ..< companyCount).map { index -> VmoCompany in
            var company = Company(index: index)
            company.tokenCount = (index + 1) * 3
            company.shareValue = (index + 1) * 600
            company.outstandingShares = 10
            company.isSafe = safeCompanyIndices.contains(index)
            return VmoCompany(company: company)
        }
        let players = [
            VmoPlayer(name: "LONGNAME10", netWorth: 123_456_789, activeCompanyShares: Array(repeating: 9999, count: companyCount)),
            VmoPlayer(name: "AB", netWorth: 0, activeCompanyShares: Array(repeating: 0, count: companyCount))
        ]
        return VmoPlayerRanking(activeCompanies: companies, rankedPlayers: players, endGameTokenCount: 55)
    }

    // MARK: Column width helper

    func testColumnPadsToTheRequestedVisibleWidth() {
        for width in [4, 8, 20] {
            for text in ["", "A", "AB*", "ALTAIR STARWAYS"] {
                let plain = Ansi.column(text, pad: width, code: "")
                XCTAssertEqual(Ansi.visibleText(plain).count, width, "\"\(text)\" padded to \(width)")
            }
        }
    }

    func testColoringDoesNotChangeVisibleWidth() {
        // The whole point of laying out before styling: escape sequences must not count as width.
        for width in [4, 8, 20] {
            for text in ["A", "B*", "DENEBOLA SHIPPERS"] {
                let plain = Ansi.column(text, pad: width, code: "")
                let colored = Ansi.column(text, pad: width, code: Ansi.companyColor(monogram: "A"))
                XCTAssertEqual(
                    Ansi.visibleText(colored).count,
                    Ansi.visibleText(plain).count,
                    "coloring \"\(text)\" changed its column width"
                )
            }
        }
    }

    func testColumnTruncatesTextLongerThanTheColumn() {
        let cell = Ansi.column("ALTAIR STARWAYS", pad: 6, code: "")
        XCTAssertEqual(Ansi.visibleText(cell), "ALTAIR")
    }

    func testEachCompanyHasItsOwnColorAndNoneIsYellow() {
        var seen = Set<String>()
        for index in 0 ..< 10 {
            let monogram = String(UnicodeScalar(UInt8(65) + UInt8(index)))
            let code = Ansi.companyColor(monogram: monogram)
            XCTAssertFalse(code.isEmpty, "company \(monogram) has no color")
            XCTAssertNotEqual(code, Ansi.yellow, "yellow is reserved for outposts")
            seen.insert(code)
        }
        XCTAssertEqual(seen.count, 10, "every company needs a distinct color")
    }

    // MARK: Ranking table

    func testRankingTableRowsAreAllTheSameWidth() {
        for companyCount in [0, 1, 5, 10] {
            let lines = render { frontEnd, _ in
                frontEnd.display(playerRanking: self.makeRanking(companyCount: companyCount))
            }
            let widths = lines
                .filter { !$0.isEmpty && $0 != "* = safe" }
                .map { Ansi.visibleText($0).count }
            XCTAssertEqual(Set(widths).count, 1, "rows differ in width with \(companyCount) companies: \(Set(widths).sorted())")
        }
    }

    func testRankingTableColumnsLineUpAcrossHeaderRuleAndData() {
        // The rule under the header used to start its company columns one character early.
        let lines = render { frontEnd, _ in
            frontEnd.display(playerRanking: self.makeRanking(companyCount: 5, safeCompanyIndices: [1, 3]))
        }
        guard let headerIndex = lines.index(where: { $0.hasPrefix("RANK") }) else {
            return XCTFail("no header row")
        }
        let header = Ansi.visibleText(lines[headerIndex])
        let rule = Ansi.visibleText(lines[headerIndex + 1])
        let firstPlayerRow = Ansi.visibleText(lines[headerIndex + 2])
        let sizeRow = Ansi.visibleText(lines.first { $0.hasPrefix("SIZE / ") } ?? "")

        // Company columns start at 30 and repeat every 8 characters.
        for column in stride(from: 30, to: 30 + 8 * 5, by: 8) {
            XCTAssertNotEqual(header[column], " ", "header company column at \(column) is empty")
            XCTAssertEqual(rule[column], "-", "rule does not start a company column at \(column)")
            XCTAssertNotEqual(firstPlayerRow[column], " ", "data company column at \(column) is empty")
            XCTAssertNotEqual(sizeRow[column], " ", "size company column at \(column) is empty")
        }
    }

    func testRankingTableShowsSizeAsProgressTowardEndingTheGame() {
        let lines = render { frontEnd, _ in
            frontEnd.display(playerRanking: self.makeRanking(companyCount: 3))
        }
        guard let sizeRow = lines.first(where: { $0.hasPrefix("SIZE / ") }) else {
            return XCTFail("no size row, so a player cannot see how close the game is to ending")
        }
        let visible = Ansi.visibleText(sizeRow)
        XCTAssertTrue(visible.hasPrefix("SIZE / 55"))
        XCTAssertTrue(visible.contains("3/55"), "first company has three tokens")
        XCTAssertTrue(visible.contains("9/55"), "third company has nine tokens")
    }

    func testSafeCompaniesAreMarkedAndFootnoted() {
        let lines = render { frontEnd, _ in
            frontEnd.display(playerRanking: self.makeRanking(companyCount: 3, safeCompanyIndices: [1]))
        }
        XCTAssertTrue(lines.contains { Ansi.visibleText($0).contains("B*") }, "a safe company is marked")
        XCTAssertTrue(lines.contains("* = safe"))
    }

    func testRankingTableOmitsTheSizeRowWhenNoCompaniesExist() {
        let lines = render { frontEnd, _ in
            frontEnd.display(playerRanking: self.makeRanking(companyCount: 0))
        }
        XCTAssertFalse(lines.contains { $0.hasPrefix("SIZE / ") })
    }

    // MARK: Company table

    func testCompanyTableRowsLineUpWithTheHeader() {
        let companies = (0 ..< 4).map { index -> VmoCompany in
            var company = Company(index: index)
            company.tokenCount = index * 18
            company.shareValue = (index + 1) * 4600
            return VmoCompany(company: company)
        }
        let lines = render { frontEnd, _ in
            frontEnd.display(activeCompanies: companies, endGameTokenCount: 55)
        }
        guard let headerIndex = lines.index(where: { $0.hasPrefix("COMPANY") }) else {
            return XCTFail("no company table header")
        }
        let header = Ansi.visibleText(lines[headerIndex])
        let rule = Ansi.visibleText(lines[headerIndex + 1])
        let row = Ansi.visibleText(lines[headerIndex + 2])

        // Name at 0, price at 20, size at 34, progress bar at 44.
        for column in [0, 20, 34, 44] {
            XCTAssertNotEqual(header[column], " ", "header column at \(column) is empty")
            XCTAssertEqual(rule[column], "-", "rule does not start a column at \(column)")
            XCTAssertNotEqual(row[column], " ", "data column at \(column) is empty")
        }
    }

    func testProgressBarFillsInProportionToSize() {
        func bar(forSize size: Int) -> String {
            var company = Company(index: 0)
            company.tokenCount = size
            company.shareValue = 100
            let lines = render { frontEnd, _ in
                frontEnd.display(activeCompanies: [VmoCompany(company: company)], endGameTokenCount: 40)
            }
            let row = Ansi.visibleText(lines.first { $0.hasPrefix("ALTAIR") } ?? "")
            return String(row[row.index(row.startIndex, offsetBy: 44)...])
        }

        XCTAssertEqual(bar(forSize: 0), "[" + String(repeating: "-", count: 20) + "]")
        XCTAssertEqual(bar(forSize: 20), "[" + String(repeating: "=", count: 10) + String(repeating: "-", count: 10) + "]")
        XCTAssertEqual(bar(forSize: 40), "[" + String(repeating: "=", count: 20) + "]")
        XCTAssertEqual(bar(forSize: 99), "[" + String(repeating: "=", count: 20) + "]", "the bar never overflows")
    }
}

/// Reading a character at an offset, which keeps the column assertions above readable.
private extension String {
    subscript(offset: Int) -> Character {
        guard offset < count else { return " " }
        return self[index(startIndex, offsetBy: offset)]
    }
}
