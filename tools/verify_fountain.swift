// verify_fountain.swift — standalone CLI that runs Penova's FountainParser
// against fountain fixtures and reports scene / cue / dialogue counts.
//
// Build & run:
//   swiftc -O -o /tmp/verify_fountain tools/verify_fountain.swift \
//       <(sed -e 's/^import SwiftData//' Penova/Features/Import/FountainParser.swift) \
//       <(sed -n '/^public enum SceneLocation/,/^}/p; /^public enum SceneTimeOfDay/,/^}/p; /^public enum SceneElementKind/,/^}/p' PenovaSpec/Models.swift)
//   /tmp/verify_fountain <files...>

import Foundation

let args = CommandLine.arguments.dropFirst()
if args.isEmpty {
    FileHandle.standardError.write(Data("usage: verify_fountain <file.fountain> ...\n".utf8))
    exit(2)
}

var failures: [String] = []
var totalFiles = 0
var totalScenes = 0
var totalCues = 0
var totalDialogue = 0

for path in args {
    totalFiles += 1
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    else {
        let msg = "\(path): cannot read"
        failures.append(msg)
        print("  ❌ \(msg)")
        continue
    }
    let doc = FountainParser.parse(raw)
    let cues = doc.scenes.flatMap { $0.elements.filter { $0.kind == .character } }.count
    let dialogue = doc.scenes.flatMap { $0.elements.filter { $0.kind == .dialogue } }.count
    let parens = doc.scenes.flatMap { $0.elements.filter { $0.kind == .parenthetical } }.count
    let transitions = doc.scenes.flatMap { $0.elements.filter { $0.kind == .transition } }.count
    let actions = doc.scenes.flatMap { $0.elements.filter { $0.kind == .action } }.count
    let titleKey = doc.titlePage["title"] ?? doc.titlePage["Title"] ?? "—"

    totalScenes += doc.scenes.count
    totalCues += cues
    totalDialogue += dialogue

    let basename = (path as NSString).lastPathComponent
    let ok = doc.scenes.count >= 1
    let mark = ok ? "✅" : "❌"
    print("  \(mark) \(basename): scenes=\(doc.scenes.count) cues=\(cues) dialogue=\(dialogue) parens=\(parens) transitions=\(transitions) action=\(actions) title=\"\(titleKey)\"")
    if !ok { failures.append("\(basename): zero scenes") }
}

print("")
print("totals: \(totalFiles) files, \(totalScenes) scenes, \(totalCues) cues, \(totalDialogue) dialogue")

if !failures.isEmpty {
    print("FAIL: \(failures.count) failure(s)")
    for f in failures { print("  - \(f)") }
    exit(1)
}
print("PASS")
