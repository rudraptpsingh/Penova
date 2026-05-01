//
//  Icons.swift
//  Penova
//
//  24 icons exported from Figma page "02 · Icons".
//  All icons are 24×24, 1.5pt stroke, stroke colour `PenovaColor.snow`.
//
//  STRATEGY FOR APPLE-NATIVE FEEL:
//   - When an icon has a close SF Symbols equivalent, use SF Symbols first.
//     SF Symbols are rendered at point size, respect Dynamic Type, support
//     `.hierarchical` / `.palette` modes, and feel native out of the box.
//   - When the semantic is app-specific (custom parens, focus target,
//     dialogue balloon with specific mouth), bundle the Figma SVG
//     as a Symbol Image (.symbolRenderingMode(.monochrome)) or Asset.
//
//  Implementation plan:
//    1. For "easy" icons, use SF Symbols at 20-24 pt, weight .regular.
//    2. For custom icons, export the Figma SVG as a multicolor Asset image or
//       convert to an SF Symbols custom symbol (.svg → .symbolimage), and drop
//       into the Assets.xcassets "Symbols" folder so we can still use `Image(systemName:)`
//       with our custom glyph.
//

import SwiftUI

public enum PenovaIcon: CaseIterable {
    case home, scripts, characters, scenes
    case plus, search, back, more
    case close, check, voice
    case progress, action, dialogue, transition
    case parens, edit, clock, bookmark
    case focus, export, settings, complete

    /// Preferred SF Symbols name; `nil` means use the bundled custom asset.
    public var sfSymbol: String? {
        switch self {
        case .home:       return "house"
        case .scripts:    return "doc.text"
        case .characters: return "person.2"
        case .scenes:     return "rectangle.stack"
        case .plus:       return "plus"
        case .search:     return "magnifyingglass"
        case .back:       return "chevron.left"
        case .more:       return "ellipsis"
        case .close:      return "xmark"
        case .check:      return "checkmark"
        case .voice:      return "mic"
        case .progress:   return "chart.line.uptrend.xyaxis"
        case .action:     return "text.alignleft"
        case .dialogue:   return "bubble.left"
        case .transition: return "arrow.right.to.line"
        case .parens:     return nil                         // custom: ( )
        case .edit:       return "pencil"
        case .clock:      return "clock"
        case .bookmark:   return "bookmark"
        case .focus:      return nil                         // custom: target w/ rays
        case .export:     return "square.and.arrow.up"
        case .settings:   return "gearshape"
        case .complete:   return "checkmark"
        }
    }

    /// Asset name for the fallback / custom SVG (see Assets.xcassets/Icons).
    public var assetName: String {
        switch self {
        case .home:       return "Icon/Home"
        case .scripts:    return "Icon/Scripts"
        case .characters: return "Icon/Characters"
        case .scenes:     return "Icon/Scenes"
        case .plus:       return "Icon/Plus"
        case .search:     return "Icon/Search"
        case .back:       return "Icon/Back"
        case .more:       return "Icon/More"
        case .close:      return "Icon/Close"
        case .check:      return "Icon/Check"
        case .voice:      return "Icon/Voice"
        case .progress:   return "Icon/Progress"
        case .action:     return "Icon/Action"
        case .dialogue:   return "Icon/Dialogue"
        case .transition: return "Icon/Transition"
        case .parens:     return "Icon/Parens"
        case .edit:       return "Icon/Edit"
        case .clock:      return "Icon/Clock"
        case .bookmark:   return "Icon/Bookmark"
        case .focus:      return "Icon/Focus"
        case .export:     return "Icon/Export"
        case .settings:   return "Icon/Settings"
        case .complete:   return "Icon/Complete"
        }
    }
}

public struct PenovaIconView: View {
    public let icon: PenovaIcon
    public var size: CGFloat = 24
    public var color: Color = PenovaColor.snow
    public var weight: Font.Weight = .regular     // SF Symbols weight

    public init(_ icon: PenovaIcon,
                size: CGFloat = 24,
                color: Color = PenovaColor.snow,
                weight: Font.Weight = .regular) {
        self.icon = icon
        self.size = size
        self.color = color
        self.weight = weight
    }

    public var body: some View {
        Group {
            if let name = icon.sfSymbol {
                Image(systemName: name)
                    .font(.system(size: size * 0.95, weight: weight))
                    .symbolRenderingMode(.monochrome)
            } else {
                Image(icon.assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size, alignment: .center)
    }
}
