//
//  ScreenshotMode.swift
//  Penova
//
//  Debug-only launch-arg router for App Store screenshot automation.
//  Pass `-screenshot <route>` at launch to skip splash/onboarding and land
//  directly on a seeded screen. Not used in release builds.
//

import Foundation

enum ScreenshotRoute: String {
    case home
    case scripts
    case characters
    case scenes
    case project       // Scripts → first project detail
    case scene         // Scripts → project → first episode → first scene
}

enum ScreenshotMode {
    static var route: ScreenshotRoute? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-screenshot"),
              idx + 1 < args.count,
              let route = ScreenshotRoute(rawValue: args[idx + 1])
        else { return nil }
        return route
    }

    static var isActive: Bool { route != nil }
}
