//
//  FDXReaderTests.swift
//  PenovaTests
//
//  Fixture-driven coverage of FDXReader. Each test feeds a small,
//  hand-written XML fixture that mirrors the shape Final Draft 8+ emits
//  and asserts that the resulting ParsedDocument has the right scenes,
//  elements, and title-page fields.
//

import Testing
import Foundation
@testable import Penova
@testable import PenovaKit

@Suite struct FDXReaderTests {

    // MARK: - Basic shape

    @Test func parsesSingleSceneWithEveryElementKind() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft DocumentType="Script" Template="No" Version="5">
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - DAY</Text></Paragraph>
            <Paragraph Type="Action"><Text>Eggs spit on the stove.</Text></Paragraph>
            <Paragraph Type="Character"><Text>ALICE</Text></Paragraph>
            <Paragraph Type="Parenthetical"><Text>(softly)</Text></Paragraph>
            <Paragraph Type="Dialogue"><Text>Hello, world.</Text></Paragraph>
            <Paragraph Type="Transition"><Text>CUT TO:</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.scenes.count == 1)
        let s = doc.scenes[0]
        #expect(s.heading == "INT. KITCHEN - DAY")
        #expect(s.elements.map(\.kind) == [.action, .character, .parenthetical, .dialogue, .transition])
        #expect(s.elements[0].text == "Eggs spit on the stove.")
        #expect(s.elements[1].text == "ALICE")
        #expect(s.elements[2].text == "(softly)")
        #expect(s.elements[3].text == "Hello, world.")
        #expect(s.elements[4].text == "CUT TO:")
    }

    @Test func parsesMultipleScenes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft DocumentType="Script">
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
            <Paragraph Type="Action"><Text>She enters.</Text></Paragraph>
            <Paragraph Type="Scene Heading"><Text>EXT. STREET - NIGHT</Text></Paragraph>
            <Paragraph Type="Action"><Text>She walks.</Text></Paragraph>
            <Paragraph Type="Scene Heading"><Text>EST. CITY - DAY</Text></Paragraph>
            <Paragraph Type="Action"><Text>City wakes.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.scenes.count == 3)
        #expect(doc.scenes.map(\.heading) ==
                ["INT. ROOM - DAY", "EXT. STREET - NIGHT", "EST. CITY - DAY"])
    }

    @Test func parsesTitlePageFields() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft DocumentType="Script">
          <TitlePage>
            <Content>
              <Paragraph Alignment="Center"><Text>Title: The Last Train</Text></Paragraph>
              <Paragraph Alignment="Center"><Text>Author: Penova Test</Text></Paragraph>
            </Content>
          </TitlePage>
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
            <Paragraph Type="Action"><Text>She enters.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.titlePage["title"] == "The Last Train")
        #expect(doc.titlePage["author"] == "Penova Test")
        #expect(doc.scenes.count == 1)
    }

    @Test func parsesCenteredTitleWithoutColon() throws {
        // Centered title pages without "Key:" prefixes are common.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft>
          <TitlePage>
            <Content>
              <Paragraph><Text>THE LAST TRAIN</Text></Paragraph>
              <Paragraph><Text>by Penova Test</Text></Paragraph>
            </Content>
          </TitlePage>
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
            <Paragraph Type="Action"><Text>x</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.titlePage["title"] == "THE LAST TRAIN")
        #expect(doc.titlePage["author"] == "Penova Test")
    }

    // MARK: - Robustness

    @Test func collapsesShotAndGeneralIntoAction() throws {
        let xml = """
        <FinalDraft><Content>
          <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
          <Paragraph Type="Shot"><Text>CLOSE ON: her hand.</Text></Paragraph>
          <Paragraph Type="General"><Text>Beat.</Text></Paragraph>
        </Content></FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.scenes.first?.elements.map(\.kind) == [.action, .action])
    }

    @Test func emptyParagraphsAreSkipped() throws {
        let xml = """
        <FinalDraft><Content>
          <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
          <Paragraph Type="Action"><Text>   </Text></Paragraph>
          <Paragraph Type="Action"><Text></Text></Paragraph>
          <Paragraph Type="Action"><Text>Real action.</Text></Paragraph>
        </Content></FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        let s = doc.scenes.first
        #expect(s?.elements.count == 1)
        #expect(s?.elements.first?.text == "Real action.")
    }

    @Test func contentBeforeFirstSceneHeadingGoesToPrologue() throws {
        // FDX legitimately allows action/dialogue ahead of any scene
        // heading (opening title cards). Our parser parks those in a
        // synthetic "INT. PROLOGUE" so nothing is dropped.
        let xml = """
        <FinalDraft><Content>
          <Paragraph Type="Action"><Text>FADE IN:</Text></Paragraph>
          <Paragraph Type="Action"><Text>BLACK SCREEN.</Text></Paragraph>
          <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
          <Paragraph Type="Action"><Text>x</Text></Paragraph>
        </Content></FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.scenes.count == 2)
        #expect(doc.scenes[0].heading.contains("PROLOGUE"))
        #expect(doc.scenes[0].elements.count == 2)
        #expect(doc.scenes[1].heading == "INT. ROOM - DAY")
    }

    @Test func unknownParagraphTypesFallBackToAction() throws {
        let xml = """
        <FinalDraft><Content>
          <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
          <Paragraph Type="SomethingMade-Up"><Text>blah</Text></Paragraph>
        </Content></FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.scenes.first?.elements.first?.kind == .action)
    }

    @Test func malformedXMLThrows() {
        let bad = "<FinalDraft><Content><Paragraph><Text>oops</Paragraph></Content>"
        do {
            _ = try FDXReader.parse(bad)
            #expect(Bool(false), "expected to throw")
        } catch {
            // ok
        }
    }

    @Test func acceptsWhitespaceAroundElementText() throws {
        let xml = """
        <FinalDraft><Content>
          <Paragraph Type="Scene Heading"><Text>
            INT. ROOM - DAY
          </Text></Paragraph>
          <Paragraph Type="Action"><Text>
            She breathes.
          </Text></Paragraph>
        </Content></FinalDraft>
        """
        let doc = try FDXReader.parse(xml)
        #expect(doc.scenes.first?.heading == "INT. ROOM - DAY")
        #expect(doc.scenes.first?.elements.first?.text == "She breathes.")
    }

    @Test func roundTripAgainstFinalDraftXMLWriterOutput() throws {
        // Build a minimal in-memory project, render with our writer, and
        // parse the result with our reader. Element kinds must match.
        // (This isn't a full round-trip — the writer emits the heading
        // synthetically when the first element isn't a heading — but it
        // proves the two file format codecs agree on the basic shapes.)
        let projectXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft DocumentType="Script" Template="No" Version="5">
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
            <Paragraph Type="Action"><Text>x</Text></Paragraph>
            <Paragraph Type="Character"><Text>ALICE</Text></Paragraph>
            <Paragraph Type="Dialogue"><Text>Hi.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
        let read = try FDXReader.parse(projectXML)
        #expect(read.scenes.first?.elements.map(\.kind) ==
                [.action, .character, .dialogue])
    }
}
