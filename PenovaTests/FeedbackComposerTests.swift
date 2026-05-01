//
//  FeedbackComposerTests.swift
//  PenovaTests
//
//  Validates the in-app "Send Feedback…" mailto + clipboard fallback
//  builders. These never touch the network — every assertion is on
//  pure string composition. We pin the recipient (per founder
//  preference: rudra.ptp.singh@gmail.com), the diagnostic-block
//  shape, and the URL escaping.
//

import Testing
import Foundation
@testable import PenovaKit

@Suite struct FeedbackComposerTests {

    @Test("mailto URL points at the recipient on file")
    func recipientPinned() throws {
        let url = try #require(FeedbackComposer.mailtoURL())
        let s = url.absoluteString
        #expect(s.hasPrefix("mailto:rudra.ptp.singh@gmail.com?"))
        #expect(FeedbackComposer.recipient == "rudra.ptp.singh@gmail.com")
    }

    @Test("subject contains the version + build")
    func subjectIncludesVersion() {
        let subject = FeedbackComposer.subjectLine()
        #expect(subject.hasPrefix("Penova feedback —"))
        // Should contain a parenthesised build number even when build = "0"
        #expect(subject.contains("("))
        #expect(subject.contains(")"))
    }

    @Test("diagnostic block contains the four documented fields")
    func diagnosticBlockHasAllFields() {
        let now = Date(timeIntervalSince1970: 1_716_200_000)
        let block = FeedbackComposer.diagnosticBlock(now: now)
        #expect(block.contains("App:"))
        #expect(block.contains("Platform:"))
        #expect(block.contains("Locale:"))
        #expect(block.contains("Date:"))
        // Diagnostic block should explicitly tell the user not to delete it.
        #expect(block.contains("(please keep)"))
    }

    @Test("date renders in UTC")
    func utcTimestamp() {
        // 2024-05-20 11:33:20 UTC
        let date = Date(timeIntervalSince1970: 1_716_204_800)
        let formatted = FeedbackComposer.utcTimestamp(date)
        #expect(formatted.hasSuffix("UTC"))
        #expect(formatted.contains("2024-05-20"))
    }

    @Test("clipboard fallback contains the same diagnostic block")
    func clipboardFallbackParity() {
        let now = Date(timeIntervalSince1970: 1_716_200_000)
        let fallback = FeedbackComposer.clipboardFallback(now: now)
        let block = FeedbackComposer.diagnosticBlock(now: now)
        #expect(fallback.contains(block))
        #expect(fallback.contains(FeedbackComposer.subjectLine()))
        #expect(fallback.contains("[Please describe your feedback above this line]"))
    }

    @Test("mailto URL escapes whitespace + brackets")
    func mailtoEscaping() throws {
        let url = try #require(FeedbackComposer.mailtoURL())
        let raw = url.absoluteString
        // Spaces in the body must be percent-encoded; literal spaces would
        // break Mail.app's URL handler on some macOS versions.
        #expect(!raw.contains(" "))
        // "(please keep)" appears in the body — verify we got an
        // encoded form (parens are legal in URLs but spaces inside aren't).
        #expect(raw.contains("please%20keep") || raw.contains("please+keep"))
    }

    @Test("platform string identifies the host OS")
    func platformDescriptionHasOS() {
        let p = FeedbackComposer.platformDescription()
        #if os(macOS)
        #expect(p.hasPrefix("macOS"))
        #elseif os(iOS)
        #expect(p.contains("iOS"))
        #endif
    }
}
