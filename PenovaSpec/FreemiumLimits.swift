//
//  FreemiumLimits.swift
//  Penova
//
//  Freemium gatekeeping — section D of the Build Guide.
//  All limits live here so product can tune without code changes.
//
//  UX principle — NEVER SURPRISE A FREE USER.
//  S22 "Limit Reached" is the *third* visible cue the user has already seen,
//  not the first:
//   1. Settings usage meter shows N/15 scenes, N/1 projects.
//   2. Scripts list shows "15/15 scenes" label at cap.
//   3. Editor shows subtle banner at (max - 1).
//
//  FAIL-CLOSED DEFAULTS.
//  If subscription state is uncertain, default to .free. Never default to .pro.
//

import Foundation

// MARK: - Limits table

public struct Limits {
    public let maxProjects: Int                // .max = unlimited
    public let maxScenesPerProject: Int
    public let exportFormats: Set<ExportFormat>
    public let characterProfiles: Bool
    public let offlineEditing: Bool
    public let voiceCapture: Bool
}

public enum ExportFormat: String, CaseIterable {
    case pdf, fdx
}

public enum FreemiumLimitsTable {
    public static func limits(for plan: Subscription.Plan) -> Limits {
        switch plan {
        case .free:
            return Limits(
                maxProjects: 1,
                maxScenesPerProject: 15,
                exportFormats: [.pdf],
                characterProfiles: true,
                offlineEditing: true,
                voiceCapture: true
            )
        case .pro:
            return Limits(
                maxProjects: .max,
                maxScenesPerProject: .max,
                exportFormats: [.pdf, .fdx],
                characterProfiles: true,
                offlineEditing: true,
                voiceCapture: true
            )
        }
    }
}

// MARK: - Check result + reasons

public enum FreemiumReason: String {
    case maxProjects = "max_projects"
    case maxScenes   = "max_scenes"
    case exportFdx   = "export_fdx"       // feature gate (direct to paywall)
    case settings                         // generic upgrade entrypoint
}

public enum FreemiumCheckResult {
    case allowed
    case denied(reason: FreemiumReason, limit: Int)
}

// MARK: - Gatekeeper

/// All create/edit actions go through this. Call BEFORE mutating state;
/// on `.denied`, route to S22 Limit Reached (for quantitative limits) or
/// directly to S14 Paywall (for feature gates like .fdx).
public struct FreemiumCheck {
    public let plan: Subscription.Plan
    public let projects: [Project]

    public init(plan: Subscription.Plan, projects: [Project]) {
        self.plan = plan
        self.projects = projects
    }

    public var limits: Limits { FreemiumLimitsTable.limits(for: plan) }

    public func canCreateProject() -> FreemiumCheckResult {
        if projects.filter({ $0.status == .active }).count >= limits.maxProjects {
            return .denied(reason: .maxProjects, limit: limits.maxProjects)
        }
        return .allowed
    }

    public func canAddScene(sceneCount: Int) -> FreemiumCheckResult {
        if sceneCount >= limits.maxScenesPerProject {
            return .denied(reason: .maxScenes, limit: limits.maxScenesPerProject)
        }
        return .allowed
    }

    public func canExport(_ format: ExportFormat) -> FreemiumCheckResult {
        if !limits.exportFormats.contains(format) {
            return .denied(reason: .exportFdx, limit: 0)
        }
        return .allowed
    }
}

// MARK: - Paywall trigger → hero copy routing

public enum PaywallSource: String {
    case sceneLimit   = "scene_limit"
    case projectLimit = "project_limit"
    case exportFdx    = "export_fdx"
    case settings

    /// Hero title shown at the top of S14 Paywall. Comparison table + price
    /// stay identical across sources.
    public var heroTitleKey: String {
        switch self {
        case .sceneLimit:   return "paywall.titleSceneLimit"
        case .projectLimit: return "paywall.titleProjectLimit"
        case .exportFdx:    return "paywall.titleExportFdx"
        case .settings:     return "paywall.titleDefault"
        }
    }
}
