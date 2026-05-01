//
//  Copy.swift
//  Penova
//
//  Centralized user-facing strings. Section G of the Build Guide.
//  DO NOT write strings inline in Views — put them here, reference by key.
//  Eventually back this with Localizable.strings for i18n.
//
//  Voice rules (applied to every string):
//   1. Direct, not clever. "Delete project", not "Yeet the draft".
//   2. Respectful. The user is serious about their craft.
//   3. No exclamations. Ever. jade colour is the celebration.
//   4. No "Oops!" / "Whoops!". State the problem: "Couldn't save. Retrying."
//   5. Second-person singular ("you", "your"). No "I"/"me".
//   6. British/Indian spelling OK; prefer "organize" over "organise" for Swift
//      consistency. Sentence case for buttons (not Title Case).
//   7. No emoji in UI strings.
//
//  Error strings MUST end with a next-action: "— Retrying…" or "— Tap to retry".
//  Never leave an error as a dead-end statement.
//

import Foundation

public enum Copy {
    // MARK: Common
    public enum common {
        public static let done      = "Done"
        public static let cancel    = "Cancel"
        public static let save      = "Save"
        public static let delete    = "Delete"
        public static let keep      = "Keep"
        public static let retry     = "Retry"
        public static let back      = "Back"
        public static let next      = "Next"
        public static let skip      = "Skip"
        public static let close     = "Close"
        public static let edit      = "Edit"
        public static let seeAll    = "See all"
        public static let loading   = "Loading"
        public static let saved     = "Saved"
        public static let undo      = "Undo"
    }

    // MARK: Splash
    public enum splash {
        public static let tagline = "Write your story. Anywhere."
    }

    // MARK: Onboarding
    public enum onboarding {
        public static let step1Title = "Write like a professional."
        public static let step1Body  = "Industry-standard screenplay formatting. Scene headings, dialogue, action — formatted as you type."
        public static let step2Title = "Know your characters deeply."
        public static let step2Body  = "Build full profiles. Track their arc, dialogue, traits, and relationships — all in one place."
        public static let start      = "Start writing"
    }

    // MARK: Home
    public enum home {
        public static let greetingMorning   = "Good morning."
        public static let greetingAfternoon = "Good afternoon."
        public static let greetingEvening   = "Good evening."
        public static let greetingNight     = "Still writing."
        public static let heroLine          = "Write the\nnext scene."
        public static let quickCaptureTitle    = "Quick scene capture"
        public static let quickCaptureSubtitle = "Tap to write a new scene instantly"
        public static let activeProjectsLabel  = "Active projects"

        /// Hour → greeting. 5-11 morning, 12-16 afternoon, 17-21 evening, 22-4 night.
        public static func greeting(forHour hour: Int) -> String {
            switch hour {
            case 5...11:  return greetingMorning
            case 12...16: return greetingAfternoon
            case 17...21: return greetingEvening
            default:      return greetingNight
            }
        }
    }

    // MARK: Scripts
    public enum scripts {
        public static func episodesLabel(_ count: Int) -> String { "Episodes · \(count)" }
        public static let logline = "Logline"
        public static func progressLabel(_ pct: Int) -> String { "\(pct)% complete" }
        public static let editedToday     = "Edited today"
        public static let editedYesterday = "Edited yesterday"
        public static func editedDaysAgo(_ n: Int) -> String { "Edited \(n) days ago" }
        public static let notStarted      = "Not started"
        // Onboarding existing material — accepts PDF, FDX, Fountain.
        public static let importMenuLabel    = "Import script…"
        public static let importEmptyState   = "Already have a script?"
        public static let importEmptyCta     = "Import PDF, FDX, or Fountain"
        public static let importMenuSubtitle = "PDF · FDX · Fountain"
    }

    // MARK: Editor
    public enum editor {
        public static let saveIndicator   = "Saved"
        public static let savingIndicator = "Saving…"
        public static let formatScene         = "Scene heading"
        public static let formatAction        = "Action"
        public static let formatCharacter     = "Character"
        public static let formatDialogue      = "Dialogue"
        public static let formatParenthetical = "Parenthetical"
        public static let formatTransition    = "Transition"
    }

    // MARK: Characters
    public enum characters {
        public static let title = "Characters"
        public static let roleProtagonist = "Protagonist"
        public static let roleLead        = "Lead"
        public static let roleAntagonist  = "Antagonist"
        public static let roleSupporting  = "Supporting"
        public static let roleMinor       = "Minor"
        public static func linesCount(_ n: Int) -> String {
            n == 1 ? "1 line" : "\(n) lines"
        }
        public static func filterAll(_ n: Int) -> String { "All · \(n)" }
        public static let autoHint            = "Write a character in ALL CAPS — they'll appear here."
        public static let sampleDialogueLabel = "Sample dialogue"
        public static let viewInScript        = "View in script"
    }

    // MARK: Scenes
    public enum scenes {
        public static let tabList  = "List"
        public static let tabBoard = "Board"
        public static let tabActs  = "Acts"
        public static let beatSetup      = "Setup"
        public static let beatInciting   = "Inciting"
        public static let beatTurn       = "Turn"
        public static let beatMidpoint   = "Midpoint"
        public static let beatClimax     = "Climax"
        public static let beatResolution = "Resolution"
        public static let actOne   = "Act I"
        public static let actTwo   = "Act II"
        public static let actThree = "Act III"
    }

    // MARK: Quick Capture
    public enum quickCapture {
        public static let title         = "Quick capture"
        public static let subtitle      = "A beat, a line, a thought. Polish later."
        public static let saveButton    = "Save to Scripts"
        public static let discardPrompt = "Discard this capture?"
        public static let listening     = "Listening…"
        public static let tapToStart    = "Tap the mic to start."
        public static let permissionDenied =
            "Microphone or speech access denied. Enable in Settings to dictate."
        public static let localeLabel   = "Language"
        public static let onDeviceLabel = "Offline only"
        public static let onDeviceHint  = "Transcribe on-device. No audio leaves your phone."
        public static let onDeviceUnavailable =
            "On-device recognition isn't available for this language."
        public static let clearCta      = "Clear"
        public static let saveCta       = "Save"
        public static let closeCta      = "Close"
    }

    // MARK: Settings
    public enum settings {
        public static let title             = "Settings"
        public static let accountLabel      = "Account"
        public static let emailLabel        = "Email"
        public static let signOut           = "Sign out"

        public static let writingLabel     = "Writing"
        public static let fontSizeLabel    = "Font size"
        public static let fontSizeSmall    = "Small (13pt)"
        public static let fontSizeMedium   = "Medium (15pt)"
        public static let fontSizeLarge    = "Large (17pt)"
        public static let lineHeightLabel  = "Line height"
        public static let lineHeightComfortable = "Comfortable"
        public static let lineHeightCompact     = "Compact"
        public static let themeLabel       = "Theme"
        public static let themeDark        = "Dark"

        public static let exportLabel             = "Export"
        public static let defaultFormatLabel      = "Default format"
        public static let defaultRecipientLabel   = "Default recipient"
        public static let defaultRecipientEmpty   = "—"

        public static let aboutLabel         = "About"
        public static let versionLabel       = "Version"
        public static let privacyPolicy      = "Privacy Policy"
        public static let termsOfService     = "Terms of Service"
        public static let deleteAccount      = "Delete account"
        public static let deleteAccountConfirm = "Type your email to confirm"
    }

    // MARK: Export
    public enum export {
        public static let title = "Export"
        public static func metaLine(pages: Int, words: Int) -> String {
            "\(pages) pages  ·  ~\(words.formatted(.number.locale(Locale(identifier: "en_IN")))) words"
        }
        public static let formatLabel    = "Format"
        public static let pdfTitle       = "PDF"
        public static let pdfDescription = "Industry-standard A4, Courier 12pt"
        public static let fdxTitle       = ".fdx"
        public static let fdxDescription = "Final Draft · opens in FD mobile & desktop"
        public static let fdxProBadge    = "PRO"
        public static let scopeLabel     = "Scope"
        public static let scopeFull      = "Full script"
        public static func scopeSelected(_ n: Int) -> String { "Selected scenes (\(n))" }
        public static let ctaExport      = "Export & Share"
    }

    // MARK: Delete Confirm (S20)
    public enum deleteConfirm {
        public static func projectTitle(_ name: String) -> String { "Delete \"\(name)\"?" }
        public static func projectImpact(eps: Int, scenes: Int, chars: Int) -> String {
            let s = { (n: Int, noun: String) in "\(n) \(noun)\(n == 1 ? "" : "s")" }
            return "\(s(eps, "episode"))  ·  \(s(scenes, "scene"))  ·  \(s(chars, "character"))"
        }
        public static let projectBody       = "This will move the project to Trash for 14 days. After that, it is permanently erased. Your characters and beats will be lost."
        public static let deleteProjectCta  = "Delete project"
        public static let keepCta           = "Keep"
        public static let trashedToast      = "Moved to Trash"
    }

    // MARK: Errors
    public enum errors {
        public static let offlineBanner   = "You're offline. Penova is saving locally — will sync when you reconnect."
        public static let saveFailedToast = "Couldn't save. Retrying…"
        public static let retryNow        = "Retry now"
        public static let syncConflictTitle = "Two versions of this scene"
        public static let syncConflictBody  = "You edited this scene on two devices while offline. Keep both, or pick one."
        public static let keepBoth          = "Keep both"
        public static let usePicked         = "Use selected"
        public static let purchaseFailed    = "Purchase failed — try again"
        public static let restoreFailed     = "Couldn't restore purchases"
        public static let welcomeToPro      = "Welcome to Pro"
    }

    // MARK: Habit
    public enum habit {
        public static let title           = "Writing habit"
        public static let settingsRow     = "Writing habit"
        public static let settingsRowSubtitle = "Streak, daily goal, last 49 days"
        public static let todayLabel      = "Today"
        public static let goalLabel       = "Daily goal"
        public static let streakLabel     = "Streak"
        public static let bestStreakLabel = "Best"
        public static let lastFortyNine   = "Last 49 days"
        public static let editGoalCta     = "Edit goal"
        public static let goalSheetTitle  = "Daily goal"
        public static let goalSheetBody   = "Words per day. The streak counts any day you cross this line."
        public static let saveGoalCta     = "Save goal"
        public static let resetCta        = "Reset history"
        public static let resetPrompt     = "Reset writing history?"
        public static let resetBody       = "Erases every recorded day. Your scripts are not touched."
        public static let emptyTitle      = "Open a scene to start the streak."
        public static let emptyBody       = "Penova counts the words you add each day. Hit your daily goal to keep the streak alive."
        public static func wordsLabel(_ n: Int) -> String {
            n == 1 ? "1 word" : "\(n) words"
        }
        public static func wordsOfGoal(words: Int, goal: Int) -> String {
            "\(words) / \(goal)"
        }
        public static func streakDaysLabel(_ n: Int) -> String {
            n == 1 ? "1 day" : "\(n) days"
        }
        public static func goalHitToday(_ hit: Bool) -> String {
            hit ? "Goal hit" : "Keep going"
        }
    }

    // MARK: Empty States
    public enum emptyStates {
        public static let homeTitle = "Your first story starts here."
        public static let homeBody  = "Create a project. Penova will keep the formatting out of your way."
        public static let homeCta   = "Start your first project"
        public static let homeHint  = "Or tap any of the sample stories to learn the format"

        public static let scriptsTitle = "Write your first scene."
        public static let scriptsBody  = "Start typing. Scene headings in ALL CAPS. Press tab to jump between action, character, and dialogue."
        public static let scriptsCta   = "Start writing"
        public static let scriptsHint  = "You'll see scene chips light up as you write"

        public static let charactersTitle = "Your cast will gather here."
        public static let charactersBody  = "Characters auto-populate as you write. Or add one manually now to build their profile first."
        public static let charactersHint  = "Write a character in ALL CAPS — they'll appear here."
    }
}
