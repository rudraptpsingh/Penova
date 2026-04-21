//
//  Components.swift
//  Draftr
//
//  Reusable UI primitives. Every screen composes these — no raw Views
//  that duplicate padding, colours, or radii. If a new combination is
//  needed twice, promote it here.
//

import SwiftUI

// MARK: - Buttons

public struct DraftrButton: View {
    public enum Variant { case primary, secondary, ghost, destructive }
    public enum Size { case regular, compact }

    let title: String
    var icon: DraftrIcon? = nil
    var variant: Variant = .primary
    var size: Size = .regular
    var isLoading: Bool = false
    let action: () -> Void

    public init(
        title: String,
        icon: DraftrIcon? = nil,
        variant: Variant = .primary,
        size: Size = .regular,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DraftrSpace.s) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let icon {
                    DraftrIconView(icon, size: size == .compact ? 16 : 18, color: foreground)
                }
                Text(title)
                    .font(size == .compact ? DraftrFont.bodyMedium : DraftrFont.bodyLarge)
            }
            .frame(maxWidth: .infinity, minHeight: size == .compact ? 40 : 48)
            .padding(.horizontal, DraftrSpace.m)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.full))
            .overlay(
                RoundedRectangle(cornerRadius: DraftrRadius.full)
                    .stroke(strokeColor, lineWidth: variant == .ghost ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .sensoryFeedback(.selection, trigger: isLoading)
    }

    private var foreground: Color {
        switch variant {
        case .primary:     return DraftrColor.ink0
        case .secondary:   return DraftrColor.snow
        case .ghost:       return DraftrColor.snow
        case .destructive: return DraftrColor.snow
        }
    }

    private var background: Color {
        switch variant {
        case .primary:     return DraftrColor.amber
        case .secondary:   return DraftrColor.ink2
        case .ghost:       return .clear
        case .destructive: return DraftrColor.ember
        }
    }

    private var strokeColor: Color {
        variant == .ghost ? DraftrColor.ink4 : .clear
    }
}

// MARK: - Tags & Chips

public struct DraftrTag: View {
    let text: String
    var tint: Color = DraftrColor.ink3
    var fg: Color = DraftrColor.snow3

    public init(text: String, tint: Color = DraftrColor.ink3, fg: Color = DraftrColor.snow3) {
        self.text = text
        self.tint = tint
        self.fg = fg
    }

    public var body: some View {
        Text(text)
            .font(DraftrFont.labelTiny)
            .textCase(.uppercase)
            .tracking(DraftrTracking.labelTiny)
            .foregroundStyle(fg)
            .padding(.horizontal, DraftrSpace.s)
            .padding(.vertical, DraftrSpace.xs)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.sm))
    }
}

public struct DraftrChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    public init(text: String, isSelected: Bool, action: @escaping () -> Void) {
        self.text = text
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(DraftrFont.bodySmall)
                .foregroundStyle(isSelected ? DraftrColor.ink0 : DraftrColor.snow)
                .padding(.horizontal, DraftrSpace.sm)
                .padding(.vertical, DraftrSpace.s)
                .background(isSelected ? DraftrColor.amber : DraftrColor.ink3)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DraftrMotion.easingFast, value: isSelected)
    }
}

// MARK: - Section Header

public struct DraftrSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String = Copy.common.seeAll

    public init(title: String, actionTitle: String = Copy.common.seeAll, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
        self.actionTitle = actionTitle
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(DraftrFont.labelCaps)
                .textCase(.uppercase)
                .tracking(DraftrTracking.labelCaps)
                .foregroundStyle(DraftrColor.snow3)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .font(DraftrFont.bodySmall)
                    .foregroundStyle(DraftrColor.amber)
            }
        }
        .padding(.vertical, DraftrSpace.s)
    }
}

// MARK: - Text Field

public struct DraftrTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var error: String? = nil

    public init(label: String, text: Binding<String>, placeholder: String = "", error: String? = nil) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.xs) {
            Text(label)
                .font(DraftrFont.labelCaps)
                .textCase(.uppercase)
                .tracking(DraftrTracking.labelCaps)
                .foregroundStyle(DraftrColor.snow3)
            TextField(placeholder, text: $text)
                .font(DraftrFont.bodyLarge)
                .foregroundStyle(DraftrColor.snow)
                .padding(DraftrSpace.sm)
                .background(DraftrColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DraftrRadius.sm)
                        .stroke(error != nil ? DraftrColor.ember : DraftrColor.ink4, lineWidth: 1)
                )
            if let error {
                Text(error)
                    .font(DraftrFont.bodySmall)
                    .foregroundStyle(DraftrColor.ember)
            }
        }
    }
}

// MARK: - Cards

public struct ProjectCard: View {
    let project: Project
    public init(project: Project) { self.project = project }

    public var body: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.sm) {
            HStack {
                if let firstGenre = project.genre.first {
                    DraftrTag(text: firstGenre.display)
                }
                Spacer()
                Text(Copy.scripts.episodesLabel(project.episodes.count))
                    .font(DraftrFont.bodySmall)
                    .foregroundStyle(DraftrColor.snow3)
            }
            Text(project.title)
                .font(DraftrFont.title)
                .foregroundStyle(DraftrColor.snow)
                .lineLimit(2)
            if !project.logline.isEmpty {
                Text(project.logline)
                    .font(DraftrFont.body)
                    .foregroundStyle(DraftrColor.snow3)
                    .lineLimit(2)
            }
        }
        .padding(DraftrSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DraftrColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }
}

public struct SceneItem: View {
    let scene: ScriptScene
    public init(scene: ScriptScene) { self.scene = scene }

    public var body: some View {
        HStack(spacing: DraftrSpace.sm) {
            VStack(alignment: .leading, spacing: DraftrSpace.xs) {
                HStack(spacing: DraftrSpace.xs) {
                    DraftrTag(text: scene.location.rawValue)
                    DraftrTag(text: scene.time.rawValue)
                    if let beat = scene.beatType {
                        DraftrTag(
                            text: beat.rawValue.uppercased(),
                            tint: DraftrColor.slate.opacity(0.2),
                            fg: DraftrColor.slate
                        )
                    }
                }
                Text(scene.heading)
                    .font(DraftrFont.monoScript)
                    .foregroundStyle(DraftrColor.snow)
                    .lineLimit(1)
                if let desc = scene.sceneDescription, !desc.isEmpty {
                    Text(desc)
                        .font(DraftrFont.bodySmall)
                        .foregroundStyle(DraftrColor.snow3)
                        .lineLimit(2)
                }
            }
            Spacer()
            DraftrIconView(.back, size: 16, color: DraftrColor.snow3)
                .rotationEffect(.degrees(180))
        }
        .padding(DraftrSpace.m)
        .background(DraftrColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }
}

public struct CharacterCard: View {
    let character: ScriptCharacter
    public init(character: ScriptCharacter) { self.character = character }

    public var body: some View {
        VStack(alignment: .leading, spacing: DraftrSpace.s) {
            Circle()
                .fill(DraftrColor.slate.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(character.name.prefix(1)))
                        .font(DraftrFont.title)
                        .foregroundStyle(DraftrColor.snow)
                )
            Text(character.name)
                .font(DraftrFont.bodyLarge)
                .foregroundStyle(DraftrColor.snow)
                .lineLimit(1)
            DraftrTag(text: character.role.display)
        }
        .padding(DraftrSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DraftrColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }
}

// MARK: - Empty State

public struct EmptyState: View {
    let icon: DraftrIcon
    let title: String
    let message: String
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil

    public init(
        icon: DraftrIcon,
        title: String,
        message: String,
        ctaTitle: String? = nil,
        ctaAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.ctaTitle = ctaTitle
        self.ctaAction = ctaAction
    }

    public var body: some View {
        VStack(spacing: DraftrSpace.m) {
            DraftrIconView(icon, size: 32, color: DraftrColor.snow4)
            Text(title)
                .font(DraftrFont.title)
                .foregroundStyle(DraftrColor.snow)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DraftrFont.body)
                .foregroundStyle(DraftrColor.snow3)
                .multilineTextAlignment(.center)
            if let ctaTitle, let ctaAction {
                DraftrButton(title: ctaTitle, variant: .primary, size: .compact, action: ctaAction)
                    .frame(maxWidth: 260)
                    .padding(.top, DraftrSpace.s)
            }
        }
        .padding(DraftrSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FAB

public struct DraftrFAB: View {
    let action: () -> Void
    var icon: DraftrIcon
    @State private var tapCount: Int = 0

    public init(icon: DraftrIcon = .plus, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button {
            tapCount &+= 1
            action()
        } label: {
            DraftrIconView(icon, size: 24, color: DraftrColor.ink0)
                .frame(width: 56, height: 56)
                .background(DraftrColor.amber)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}
