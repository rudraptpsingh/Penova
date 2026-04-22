//
//  SceneHeadingParser.swift
//  Penova
//
//  Parses free-form screenplay slug lines into the structured
//  (location, locationName, time) triplet that ScriptScene expects.
//
//  Grammar we try to match (case-insensitive, whitespace-tolerant):
//
//      <prefix> <locationName> [ - <time> ]
//
//      prefix ::= INT. | EXT. | INT./EXT. | EST.
//
//  Anything that doesn't match still yields a usable result: the full raw
//  trimmed string goes into `locationName`, `location` and `time` come back
//  nil, and the caller falls back to its defaults. Parsing a slug line must
//  never throw or block the user — a crooked heading is still a heading.
//

import Foundation

struct ParsedSceneHeading {
    let location: SceneLocation?
    let locationName: String
    let time: SceneTimeOfDay?
}

enum SceneHeadingParser {

    // Regex: ^(INT\.|EXT\.|INT\./EXT\.|EST\.)\s+(.+?)(?:\s+-\s+(.+))?$
    // NSRegularExpression needs double-escaped backslashes in the source
    // string, and we run it case-insensitively so "int. diner - night" works
    // the same as the canonical uppercase form.
    private static let pattern = #"^(INT\./EXT\.|INT\.|EXT\.|EST\.)\s+(.+?)(?:\s+-\s+(.+))?$"#

    static func parse(_ raw: String) -> ParsedSceneHeading {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedSceneHeading(location: nil, locationName: "", time: nil)
        }

        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let regex,
              let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 3,
              let prefixRange = Range(match.range(at: 1), in: trimmed),
              let nameRange = Range(match.range(at: 2), in: trimmed)
        else {
            // Gracefully degrade: stash the full string as the location name.
            return ParsedSceneHeading(
                location: nil,
                locationName: trimmed.uppercased(),
                time: nil
            )
        }

        let prefix = trimmed[prefixRange].uppercased()
        let name = trimmed[nameRange]
            .trimmingCharacters(in: .whitespaces)
            .uppercased()

        let location: SceneLocation = {
            switch prefix {
            case "INT.":       return .interior
            case "EXT.":       return .exterior
            case "INT./EXT.":  return .both
            case "EST.":       return .exterior   // closest analogue we have today
            default:           return .interior
            }
        }()

        var time: SceneTimeOfDay?
        if match.numberOfRanges >= 4,
           let timeRange = Range(match.range(at: 3), in: trimmed) {
            let timeText = trimmed[timeRange]
                .trimmingCharacters(in: .whitespaces)
                .uppercased()
            time = SceneTimeOfDay.allCases.first { $0.rawValue == timeText }
        }

        return ParsedSceneHeading(
            location: location,
            locationName: name,
            time: time
        )
    }
}
