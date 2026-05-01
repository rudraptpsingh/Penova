// swift-tools-version: 5.10
//
//  PenovaKit — shared platform-agnostic core for Penova (iOS) and Penova-mac.
//
//  What's in here:
//  - SwiftData @Model classes (Project, Episode, ScriptScene, SceneElement, ScriptCharacter)
//  - Design tokens (PenovaColor, PenovaFont, PenovaSpace, PenovaRadius, PenovaMotion)
//  - Reusable SwiftUI components (PenovaButton, PenovaCard, PenovaTag, …)
//  - Screenwriting business logic: EditorLogic, SceneHeadingParser
//  - Format pipelines: FountainParser, FountainExporter, FinalDraftXMLWriter
//
//  What's NOT in here:
//  - Per-platform PDF rendering (UIGraphicsPDFRenderer / CGDataConsumer adapters live in apps)
//  - Per-platform UI shell (NavigationStack on iOS, NavigationSplitView on Mac)
//

import PackageDescription

let package = Package(
    name: "PenovaKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PenovaKit", targets: ["PenovaKit"]),
    ],
    targets: [
        .target(
            name: "PenovaKit",
            path: "Sources/PenovaKit"
        ),
    ]
)
