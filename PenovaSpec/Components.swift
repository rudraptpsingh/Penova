//
//  Components.swift
//  Penova
//
//  Reusable UI primitives. Every screen composes these — no raw Views
//  that duplicate padding, colours, or radii. If a new combination is
//  needed twice, promote it here.
//

import SwiftUI

// MARK: - Buttons

public struct PenovaButton: View {
    public enum Variant { case primary, secondary, ghost, destructive }
    public enum Size { case regular, compact }

    let title: String
    var icon: PenovaIcon? = nil
    var variant: Variant = .primary
    var size: Size = .regular
    var isLoading: Bool = false
    let action: () -> Void

    public init(
        title: String,
        icon: PenovaIcon? = nil,
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
            HStack(spacing: PenovaSpace.s) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let icon {
                    PenovaIconView(icon, size: size == .compact ? 16 : 18, color: foreground)
                }
                Text(title)
                    .font(size == .compact ? PenovaFont.bodyMedium : PenovaFont.bodyLarge)
            }
            .frame(maxWidth: .infinity, minHeight: size == .compact ? 40 : 48)
            .padding(.horizontal, PenovaSpace.m)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.full))
            .overlay(
                RoundedRectangle(cornerRadius: PenovaRadius.full)
                    .stroke(strokeColor, lineWidth: variant == .ghost ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .sensoryFeedback(.selection, trigger: isLoading)
    }

    private var foreground: Color {
        switch variant {
        case .primary:     return PenovaColor.ink0
        case .secondary:   return PenovaColor.snow
        case .ghost:       return PenovaColor.snow
        case .destructive: return PenovaColor.snow
        }
    }

    private var background: Color {
        switch variant {
        case .primary:     return PenovaColor.amber
        case .secondary:   return PenovaColor.ink2
        case .ghost:       return .clear
        case .destructive: return PenovaColor.ember
        }
    }

    private var strokeColor: Color {
        variant == .ghost ? PenovaColor.ink4 : .clear
    }
}

// MARK: - Tags & Chips

public struct PenovaTag: View {
    let text: String
    var tint: Color = PenovaColor.ink3
    var fg: Color = PenovaColor.snow3

    public init(text: String, tint: Color = PenovaColor.ink3, fg: Color = PenovaColor.snow3) {
        self.text = text
        self.tint = tint
        self.fg = fg
    }

    public var body: some View {
        Text(text)
            .font(PenovaFont.labelTiny)
            .textCase(.uppercase)
            .tracking(PenovaTracking.labelTiny)
            .foregroundStyle(fg)
            .padding(.horizontal, PenovaSpace.s)
            .padding(.vertical, PenovaSpace.xs)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
    }
}

public struct PenovaChip: View {
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
                .font(PenovaFont.bodySmall)
                .foregroundStyle(isSelected ? PenovaColor.ink0 : PenovaColor.snow)
                .padding(.horizontal, PenovaSpace.sm)
                .padding(.vertical, PenovaSpace.s)
                .background(isSelected ? PenovaColor.amber : PenovaColor.ink3)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(PenovaMotion.easingFast, value: isSelected)
    }
}

// MARK: - Section Header

public struct PenovaSectionHeader: View {
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
                .font(PenovaFont.labelCaps)
                .textCase(.uppercase)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.amber)
            }
        }
        .padding(.vertical, PenovaSpace.s)
    }
}

// MARK: - Text Field

public struct PenovaTextField: View {
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
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(label)
                .font(PenovaFont.labelCaps)
                .textCase(.uppercase)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            TextField(placeholder, text: $text)
                .font(PenovaFont.bodyLarge)
                .foregroundStyle(PenovaColor.snow)
                .padding(PenovaSpace.sm)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: PenovaRadius.sm)
                        .stroke(error != nil ? PenovaColor.ember : PenovaColor.ink4, lineWidth: 1)
                )
            if let error {
                Text(error)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.ember)
            }
        }
    }
}

// MARK: - Cards

public struct ProjectCard: View {
    let project: Project
    public init(project: Project) { self.project = project }

    public var body: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.sm) {
            HStack {
                if let firstGenre = project.genre.first {
                    PenovaTag(text: firstGenre.display)
                }
                Spacer()
                Text(Copy.scripts.episodesLabel(project.episodes.count))
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
            }
            Text(project.title)
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
                .lineLimit(2)
            if !project.logline.isEmpty {
                Text(project.logline)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow3)
                    .lineLimit(2)
            }
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }
}

public struct SceneItem: View {
    let scene: ScriptScene
    public init(scene: ScriptScene) { self.scene = scene }

    public var body: some View {
        HStack(spacing: PenovaSpace.sm) {
            VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                HStack(spacing: PenovaSpace.xs) {
                    PenovaTag(text: scene.location.rawValue)
                    PenovaTag(text: scene.time.rawValue)
                    if let beat = scene.beatType {
                        PenovaTag(
                            text: beat.rawValue.uppercased(),
                            tint: PenovaColor.slate.opacity(0.2),
                            fg: PenovaColor.slate
                        )
                    }
                }
                Text(scene.heading)
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.snow)
                    .lineLimit(1)
                if let desc = scene.sceneDescription, !desc.isEmpty {
                    Text(desc)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                        .lineLimit(2)
                }
            }
            Spacer()
            PenovaIconView(.back, size: 16, color: PenovaColor.snow3)
                .rotationEffect(.degrees(180))
        }
        .padding(PenovaSpace.m)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }
}

public struct CharacterCard: View {
    let character: ScriptCharacter
    public init(character: ScriptCharacter) { self.character = character }

    public var body: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Circle()
                .fill(PenovaColor.slate.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(character.name.prefix(1)))
                        .font(PenovaFont.title)
                        .foregroundStyle(PenovaColor.snow)
                )
            Text(character.name)
                .font(PenovaFont.bodyLarge)
                .foregroundStyle(PenovaColor.snow)
                .lineLimit(1)
            PenovaTag(text: character.role.display)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }
}

// MARK: - Empty State

public struct EmptyState: View {
    let icon: PenovaIcon
    let title: String
    let message: String
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil

    public init(
        icon: PenovaIcon,
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
        VStack(spacing: PenovaSpace.m) {
            PenovaIconView(icon, size: 32, color: PenovaColor.snow4)
            Text(title)
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
                .multilineTextAlignment(.center)
            Text(message)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
                .multilineTextAlignment(.center)
            if let ctaTitle, let ctaAction {
                PenovaButton(title: ctaTitle, variant: .primary, size: .compact, action: ctaAction)
                    .frame(maxWidth: 260)
                    .padding(.top, PenovaSpace.s)
            }
        }
        .padding(PenovaSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FAB

public struct PenovaFAB: View {
    let action: () -> Void
    var icon: PenovaIcon
    @State private var tapCount: Int = 0

    public init(icon: PenovaIcon = .plus, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button {
            tapCount &+= 1
            action()
        } label: {
            PenovaIconView(icon, size: 24, color: PenovaColor.ink0)
                .frame(width: 56, height: 56)
                .background(PenovaColor.amber)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}
