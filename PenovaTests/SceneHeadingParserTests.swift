//
//  SceneHeadingParserTests.swift
//  PenovaTests
//
//  Covers the free-form slug-line parser. Focus is on making sure garbage
//  input still returns a usable result instead of crashing (the parser is
//  called from the save path, so a throw would block the user).
//

import Testing
import PenovaKit
@testable import Penova

@Suite struct SceneHeadingParserTests {

    @Test func parsesCanonicalInteriorHeading() {
        let r = SceneHeadingParser.parse("INT. DINER - NIGHT")
        #expect(r.location == .interior)
        #expect(r.locationName == "DINER")
        #expect(r.time == .night)
    }

    @Test func parsesExteriorWithoutTime() {
        let r = SceneHeadingParser.parse("EXT. CITY")
        #expect(r.location == .exterior)
        #expect(r.locationName == "CITY")
        #expect(r.time == nil)
    }

    @Test func parsesIntExtHeading() {
        let r = SceneHeadingParser.parse("INT./EXT. CAR - DAY")
        #expect(r.location == .both)
        #expect(r.locationName == "CAR")
        #expect(r.time == .day)
    }

    @Test func parsesCaseInsensitively() {
        let r = SceneHeadingParser.parse("int. diner - night")
        #expect(r.location == .interior)
        #expect(r.locationName == "DINER")
        #expect(r.time == .night)
    }

    @Test func gibberishDoesNotCrashAndStashesLocation() {
        let r = SceneHeadingParser.parse("lol what is this even")
        #expect(r.location == nil)
        #expect(r.locationName == "LOL WHAT IS THIS EVEN")
        #expect(r.time == nil)
    }

    @Test func emptyInputIsSafe() {
        let r = SceneHeadingParser.parse("   ")
        #expect(r.locationName == "")
        #expect(r.location == nil)
        #expect(r.time == nil)
    }

    @Test func unknownTimeOfDayIsIgnored() {
        // "GOLDEN HOUR" isn't in SceneTimeOfDay — we keep the location but
        // decline to guess the time.
        let r = SceneHeadingParser.parse("EXT. BEACH - GOLDEN HOUR")
        #expect(r.location == .exterior)
        #expect(r.locationName == "BEACH")
        #expect(r.time == nil)
    }
}
