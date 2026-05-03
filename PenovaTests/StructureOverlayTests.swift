//
//  StructureOverlayTests.swift
//  PenovaTests
//
//  Pins the StructureOverlay + StructureMapper contracts.
//

import Testing
import Foundation
@testable import PenovaKit

@Suite struct StructureOverlayTests {

    // MARK: - Beat counts (mockup pill labels)

    @Test func penovaHasSixBeats() {
        #expect(StructureOverlay.penova.beats.count == 6)
        #expect(StructureOverlay.penova.beatCountLabel == "6")
    }

    @Test func fieldHasThreeBeats() {
        #expect(StructureOverlay.fieldThreeAct.beats.count == 3)
    }

    @Test func saveTheCatHasFifteenBeats() {
        #expect(StructureOverlay.saveTheCat.beats.count == 15)
    }

    @Test func herosJourneyHasTwelveBeats() {
        #expect(StructureOverlay.herosJourney.beats.count == 12)
    }

    @Test func everyOverlayHasUniqueBeatIDs() {
        for overlay in StructureOverlay.allCases {
            let ids = overlay.beats.map(\.id)
            #expect(Set(ids).count == ids.count, "Duplicate ids in \(overlay)")
        }
    }

    @Test func everyOverlayHasExactlyOneMidpointAnchor() {
        for overlay in StructureOverlay.allCases {
            let midpoints = overlay.beats.filter(\.isMidpointAnchor)
            #expect(midpoints.count == 1, "Expected one midpoint in \(overlay)")
        }
    }

    // MARK: - Page anchors

    @Test func suggestedPagesAreClampedToValidRange() {
        for overlay in StructureOverlay.allCases {
            for beat in overlay.beats {
                #expect(beat.suggestedPageStart >= 0)
                #expect(beat.suggestedPageStart <= 1)
                #expect(beat.suggestedPageEnd >= 0)
                #expect(beat.suggestedPageEnd <= 1)
                #expect(beat.suggestedPageStart <= beat.suggestedPageEnd)
            }
        }
    }

    @Test func suggestedPageMapsToOneBased() {
        let midpoint = StructureOverlay.penova.beats
            .first(where: { $0.id == "midpoint" })!
        // 0.50 of 100 pages → 50.
        #expect(midpoint.suggestedStartPage(in: 100) == 50)
        // 0.50 of 110 pages → 55.
        #expect(midpoint.suggestedStartPage(in: 110) == 55)
    }

    @Test func suggestedPageClampsToOneOnEmptyScript() {
        let setup = StructureOverlay.penova.beats[0]
        #expect(setup.suggestedStartPage(in: 0) == 1)
        #expect(setup.suggestedEndPage(in: 0) == 1)
    }

    @Test func suggestedPageClampsToTotal() {
        // Final beats with 1.0 anchor on a 90-page script → 90.
        let resolution = StructureOverlay.penova.beats
            .first(where: { $0.id == "resolution" })!
        #expect(resolution.suggestedEndPage(in: 90) == 90)
    }

    // MARK: - Mapper — Penova → other overlays

    @Test func mapperPenovaToPenovaIsIdentity() {
        for beat in BeatType.allCases {
            #expect(
                StructureMapper.equivalent(beat, in: .penova) == beat.rawValue
            )
        }
    }

    @Test func mapperPenovaToFieldGroupsCorrectly() {
        // Setup + inciting → act 1
        // Turn + midpoint + climax → act 2
        // Resolution → act 3
        #expect(StructureMapper.equivalent(.setup, in: .fieldThreeAct) == "field-act-1")
        #expect(StructureMapper.equivalent(.inciting, in: .fieldThreeAct) == "field-act-1")
        #expect(StructureMapper.equivalent(.turn, in: .fieldThreeAct) == "field-act-2")
        #expect(StructureMapper.equivalent(.midpoint, in: .fieldThreeAct) == "field-act-2")
        #expect(StructureMapper.equivalent(.climax, in: .fieldThreeAct) == "field-act-2")
        #expect(StructureMapper.equivalent(.resolution, in: .fieldThreeAct) == "field-act-3")
    }

    @Test func mapperPenovaToSaveTheCatHandlesAllSix() {
        for beat in BeatType.allCases {
            #expect(
                StructureMapper.equivalent(beat, in: .saveTheCat) != nil,
                "BeatType .\(beat.rawValue) has no Save the Cat mapping"
            )
        }
    }

    @Test func mapperPenovaToHerosJourneyHandlesAllSix() {
        for beat in BeatType.allCases {
            #expect(
                StructureMapper.equivalent(beat, in: .herosJourney) != nil,
                "BeatType .\(beat.rawValue) has no Hero's Journey mapping"
            )
        }
    }

    @Test func mapperReturnsValidBeatIDs() {
        // Every mapped id should exist in the overlay's beats.
        for overlay in StructureOverlay.allCases {
            let validIDs = Set(overlay.beats.map(\.id))
            for beat in BeatType.allCases {
                if let mapped = StructureMapper.equivalent(beat, in: overlay) {
                    #expect(
                        validIDs.contains(mapped),
                        "Mapped id \(mapped) not found in \(overlay) beats"
                    )
                }
            }
        }
    }

    // MARK: - Coverage

    @Test func coverageEmptyAssignmentsZeroPercent() {
        let cov = StructureMapper.coverage(
            assignedBeats: [],
            overlay: .penova
        )
        #expect(cov.coveragePercent == 0.0)
        #expect(cov.coveredBeatIDs.isEmpty)
        #expect(cov.missingBeatIDs.count == 6)
    }

    @Test func coverageFullAssignmentsHundredPercent() {
        let cov = StructureMapper.coverage(
            assignedBeats: Set(BeatType.allCases),
            overlay: .penova
        )
        #expect(cov.coveragePercent == 1.0)
        #expect(cov.missingBeatIDs.isEmpty)
        #expect(cov.coveredBeatIDs.count == 6)
    }

    @Test func coverageHalfAssignmentsHalfPercent() {
        let cov = StructureMapper.coverage(
            assignedBeats: [.setup, .midpoint, .resolution],
            overlay: .penova
        )
        #expect(cov.coveragePercent == 0.5)
        #expect(cov.coveredBeatIDs.count == 3)
        #expect(cov.missingBeatIDs.count == 3)
    }

    @Test func coverageOnFieldOverlayCollapsesPenovaBeats() {
        // setup + midpoint covers field-act-1 and field-act-2 only.
        // field-act-3 (resolution) stays missing.
        let cov = StructureMapper.coverage(
            assignedBeats: [.setup, .midpoint],
            overlay: .fieldThreeAct
        )
        #expect(cov.coveredBeatIDs == ["field-act-1", "field-act-2"])
        #expect(cov.missingBeatIDs == ["field-act-3"])
    }

    // MARK: - Display labels

    @Test func displayLabels() {
        #expect(StructureOverlay.penova.display == "Penova")
        #expect(StructureOverlay.fieldThreeAct.display == "Field 3-Act")
        #expect(StructureOverlay.saveTheCat.display == "Save the Cat")
        #expect(StructureOverlay.herosJourney.display == "Hero's Journey")
    }

    @Test func midpointBeatExistsWithCorrectAnchor() {
        // Penova "midpoint" is at exactly 0.50.
        let mid = StructureOverlay.penova.beats.first { $0.isMidpointAnchor }!
        #expect(mid.id == "midpoint")
        #expect(mid.suggestedPageStart == 0.50)
    }
}
