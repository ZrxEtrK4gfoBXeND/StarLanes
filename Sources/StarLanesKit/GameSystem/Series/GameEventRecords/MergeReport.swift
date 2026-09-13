//
//  MergeReport.swift
//
//  Copyright © 2018 Michael McMahon. All rights reserved worldwide.
//  http://github.com/mmpub/starlanes
//

/// A merge report model used in creating merger announcements. When more than two companies are merged at once, multiple merge reports are generated.
public struct MergeReport {
    /// Player who triggered the merge.
    public let mergePlayerIndex: Int
    /// Company that survived.
    public let survivingCompany: Company
    /// Company that is gone.
    public let defunctCompany: Company
    /// Array of bonuses paid used to inform players in announcement.
    public let bonusesPaid: [Int]
}
