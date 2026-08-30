import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI

/// Which "All" list a section header opens.
enum HomeListKind: Identifiable {
    case tasks
    case suggestions
    case location
    case other
    case updates
    /// The merged Suggestions + Updates deck (one Home list since).
    case forYou

    var id: Self {
        self
    }
}

/// The small "All ›" glass pill next to a section header.
struct SectionListButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.08)
                ZStack {
                    Circle().fill(Color(light: 0xFFFFFF, dark: 0x3A3A3C, lightOpacity: 0.46, darkOpacity: 0.60)).frame(width: 17, height: 17)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .offset(x: 0.5)
                }
            }
            .foregroundStyle(DS.Palette.ink.opacity(0.56))
            .padding(.leading, 11)
            .padding(.trailing, 5)
            .frame(height: 28)
            // Solid white pill + soft hairline, matching the card plates (was
            // clear glass — nothing to refract over the flat canvas).
            .background(Capsule(style: .continuous).fill(DS.Palette.card))
            .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
            .shadow(color: .black.opacity(0.025), radius: 7, x: 0, y: 3)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show all")
    }
}

// MARK: - Sheet

/// Handlers for the REAL UniversalCards the Open sections render — the same
/// closures HomeScreen wires into its inline deck. The Home sheet passes its
/// undo-window handlers verbatim; the menu page (no undo rail in reach)
/// wires direct commits.
struct SuggestionCardHandlers {
    var onDelete: (Suggestion) -> Void = { _ in }
    var onRunAction: (Suggestion, SuggestionActionItem, String?) -> Void = { _, _, _ in }
    var onGeneratedAction: (Suggestion, GeneratedAction, String?) async -> HomeStore.GeneratedActionOutcome = { _, _, _ in .failed("") }
    var onRunOrder: (Suggestion, CardReplyOrder) -> Void = { _, _ in }
    var onMarkRead: (Suggestion) -> Void = { _ in }
}

struct HomeListSheet: View {
    let kind: HomeListKind
    let tasks: [ActiveTask]
    let suggestions: [Suggestion]
    var location: [Suggestion] = []
    var other: [Suggestion] = []
    var updates: [Suggestion] = []
    var onTask: (ActiveTask) -> Void = { _ in }
    var onDeleteTask: (ActiveTask) -> Void = { _ in }
    var cardHandlers = SuggestionCardHandlers()

    @Environment(\.dismiss) private var dismiss
    /// The task row currently showing its Stop Task menu (one at a time).
    @State private var revealedDeleteTaskId: AnyHashable?

    private var title: String {
        switch kind {
        case .tasks: "Agent History"
        // "Updates" everywhere the user sees this list (menu row, page,
        // sheet) — the .updates kind is a separate legacy section.
        case .suggestions: "Updates"
        case .location: "Location & context"
        case .other: "Other"
        case .updates: "Updates"
        case .forYou: "For you"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.30)
                    .foregroundStyle(DS.Palette.ink)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(DS.Palette.card.opacity(0.35), in: Circle())
                .personaGlass(in: Circle(), interactive: true)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.top, 20)
            .padding(.horizontal, 22)

            ScrollView(showsIndicators: false) {
                HomeListSections(
                    kind: kind,
                    tasks: tasks,
                    suggestions: suggestions,
                    location: location,
                    other: other,
                    updates: updates,
                    onTask: { task in
                        dismiss()
                        onTask(task)
                    },
                    onDeleteTask: onDeleteTask,
                    cardHandlers: cardHandlers,
                    revealedDeleteTaskId: $revealedDeleteTaskId
                )
                .padding(.top, 8)
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A scroll dismisses any open Stop Task menu.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, revealedDeleteTaskId != nil {
                    withAnimation(.smooth(duration: 0.25, extraBounce: 0)) { revealedDeleteTaskId = nil }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sheetBackground.ignoresSafeArea())
        // Presents the task rows' long-press Stop Task layer (dim + capsule)
        // over the whole sheet.
        .taskStopMenuHost()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .dsAppearance()
    }

    private var sheetBackground: some View {
        ZStack {
            DS.Palette.surface.opacity(0.92)
            LinearGradient(
                colors: [
                    Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: 0.86, darkOpacity: 0.86),
                    Color(light: 0xDFF2FF, dark: 0x1D3A50, lightOpacity: 0.32, darkOpacity: 0.20),
                    Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: 0.68, darkOpacity: 0.68),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

}

// MARK: - Shared sections + full-page variant

/// The grouped section list itself — shared verbatim by the Home "All" sheet
/// and the full-page variant the Iris menu's "Others" dropdown opens, so the
/// two surfaces can never drift.
private struct HomeListSections: View {
    let kind: HomeListKind
    let tasks: [ActiveTask]
    let suggestions: [Suggestion]
    let location: [Suggestion]
    let other: [Suggestion]
    let updates: [Suggestion]
    let onTask: (ActiveTask) -> Void
    let onDeleteTask: (ActiveTask) -> Void
    let cardHandlers: SuggestionCardHandlers
    var revealedDeleteTaskId: Binding<AnyHashable?>

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            switch kind {
            case .tasks:
                ForEach(taskSections) { section in
                    TaskHistorySectionView(
                        section: section,
                        onTask: onTask,
                        onDelete: onDeleteTask,
                        revealedDeleteId: revealedDeleteTaskId
                    )
                }
            case .suggestions:
                ForEach(suggestionSections(suggestions)) { section in
                    SuggestionSheetSectionView(section: section, handlers: cardHandlers)
                }
            case .location:
                ForEach(suggestionSections(location)) { section in
                    SuggestionSheetSectionView(section: section, handlers: cardHandlers)
                }
            case .other:
                ForEach(suggestionSections(other)) { section in
                    SuggestionSheetSectionView(section: section, handlers: cardHandlers)
                }
            case .updates:
                ForEach(suggestionSections(updates)) { section in
                    SuggestionSheetSectionView(section: section, handlers: cardHandlers)
                }
            case .forYou:
                // The merged deck's history: both kinds, one Open/Closed split,
                // newest first within each — same order as the Home list.
                ForEach(suggestionSections((suggestions + updates).sorted { $0.createdAt > $1.createdAt })) { section in
                    SuggestionSheetSectionView(section: section, handlers: cardHandlers)
                }
            }
        }
    }

    // MARK: Grouping

    private var taskSections: [TaskHistorySection] {
        var sections: [TaskHistorySection] = []
        let active = tasks.filter(\.isActive)
        if !active.isEmpty { sections.append(TaskHistorySection(title: "Active", tasks: active)) }

        let completed = tasks.filter { !$0.isActive }
        let preferred = ["Today", "Yesterday"]
        let available = completed.map { $0.historySection ?? "Earlier" }
        var titles = preferred.filter { available.contains($0) }
        for title in available where !titles.contains(title) {
            titles.append(title)
        }
        for title in titles {
            let group = completed.filter { ($0.historySection ?? "Earlier") == title }
            if !group.isEmpty { sections.append(TaskHistorySection(title: title, tasks: group)) }
        }
        return sections
    }

    private func suggestionSections(_ all: [Suggestion]) -> [SuggestionSheetSection] {
        ["Open", "Closed"].compactMap { title in
            let group = all.filter { ($0.isOpen ? "Open" : "Closed") == title }
            return group.isEmpty ? nil : SuggestionSheetSection(title: title, suggestions: group)
        }
    }
}

/// The FULL-PAGE variant of the "All" lists — the same sections as the sheet,
/// presented as a trailing slide-in page (PersonDeepDiveScreen's scaffold:
/// shared wash, floating back chevron, header backdrop). Opened from the Iris
/// menu's "Others" dropdown, where a half-height sheet would read as a detour.
struct HomeListPage: View {
    let kind: HomeListKind
    let tasks: [ActiveTask]
    let suggestions: [Suggestion]
    var location: [Suggestion] = []
    var other: [Suggestion] = []
    var updates: [Suggestion] = []
    var onTask: (ActiveTask) -> Void = { _ in }
    var onDeleteTask: (ActiveTask) -> Void = { _ in }
    var cardHandlers = SuggestionCardHandlers()
    let onClose: () -> Void

    /// The task row currently showing its Stop Task menu (one at a time).
    @State private var revealedDeleteTaskId: AnyHashable?

    private var title: String {
        switch kind {
        case .tasks: String(localized: "Agents")
        // Matches the ledger menu row that opens this page ("Updates").
        case .suggestions: String(localized: "Updates")
        case .location: String(localized: "Location & context")
        case .other: String(localized: "Other")
        case .updates: String(localized: "Updates")
        case .forYou: String(localized: "For you")
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SharedAppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.24)
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, 8)
                    HomeListSections(
                        kind: kind,
                        tasks: tasks,
                        suggestions: suggestions,
                        location: location,
                        other: other,
                        updates: updates,
                        onTask: onTask,
                        onDeleteTask: onDeleteTask,
                        cardHandlers: cardHandlers,
                        revealedDeleteTaskId: $revealedDeleteTaskId
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 64)
                .padding(.bottom, 96)
            }
            .topScrollFade()
            // A scroll dismisses any open Stop Task menu.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, revealedDeleteTaskId != nil {
                    withAnimation(.smooth(duration: 0.25, extraBounce: 0)) { revealedDeleteTaskId = nil }
                }
            }

            TopHeaderBackdrop()
                .frame(height: 150)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            backButton
                .padding(.leading, DS.Spacing.gutter)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Presents the task rows' long-press Stop Task layer over the page.
        .taskStopMenuHost()
        .dsAppearance()
    }

    private var backButton: some View {
        Button {
            DSHaptics.tap(.light)
            onClose()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .smallGlassCircle()
    }
}

// MARK: - Task rows

struct TaskHistorySection: Identifiable {
    let title: String
    let tasks: [ActiveTask]
    var id: String {
        title
    }
}

private struct TaskHistorySectionView: View {
    let section: TaskHistorySection
    let onTask: (ActiveTask) -> Void
    var onDelete: (ActiveTask) -> Void = { _ in }
    var revealedDeleteId: Binding<AnyHashable?> = .constant(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetSectionHeader(title: section.title)
            VStack(spacing: 8) {
                ForEach(section.tasks) { task in
                    // Same long-press Stop Task affordance as the Home cards.
                    TaskStopMenuContainer(
                        id: task.id,
                        revealedId: revealedDeleteId,
                        onTap: { onTask(task) },
                        onDelete: { onDelete(task) },
                        // TaskHistoryRow's surface radius, for the dim cutout.
                        menuCornerRadius: 26
                    ) {
                        TaskHistoryRow(task: task)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskHistoryRow: View {
    let task: ActiveTask
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rowIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold)).tracking(-0.14)
                    .foregroundStyle(DS.Palette.ink).lineLimit(1)
                Text(task.subtitle)
                    .font(.system(size: 12, weight: .medium)).tracking(-0.11)
                    .foregroundStyle(Color(light: 0x777777, dark: 0xAEAEB2)).lineLimit(1)
                Text(task.detail)
                    .font(.system(size: 10, weight: .medium)).tracking(-0.10)
                    .foregroundStyle(Color(light: 0xA0A0A0, dark: 0x8E8E93)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                TaskStatusPill(task: task)
                Spacer(minLength: 0)
                Text(task.historyDurationLabel)
                    .font(.system(size: 11, weight: .semibold)).tracking(-0.11)
                    .foregroundStyle(Color(light: 0x777777, dark: 0xAEAEB2))
                    .lineLimit(1).minimumScaleFactor(0.78)
                    .padding(.trailing, 10)
            }
            .frame(width: 92, height: 48, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: 0.85, darkOpacity: 0.85), in: shape)
        .overlay { shape.stroke(DS.Palette.card.opacity(0.64), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.055), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder private var rowIcon: some View {
        if task.appImage.isEmpty {
            HomeEntryAvatar(
                photoUrl: task.photoUrl,
                contactEmail: task.contactEmail,
                logoDomain: task.logoDomain,
                fallbackSymbol: task.displayIconSymbol,
                // Task icons stay in the app's ink family (Home card parity).
                monochromeFallback: true
            )
        } else {
            PersonaAsset.image(task.appImage)
                .resizable().interpolation(.high).scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

private struct TaskStatusPill: View {
    let task: ActiveTask

    /// Design parity: amber when parked on a question, green while active, grey
    /// once completed.
    private var dotColor: Color {
        if task.needsInput { return DS.TaskState.amber }
        return task.isActive ? Color(hex: 0x34C759) : Color(hex: 0x9D9D9D)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(task.status)
                .font(.system(size: 9, weight: .semibold)).tracking(-0.09)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.80)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(DS.Palette.card.opacity(0.82), in: Capsule(style: .continuous))
        .overlay { Capsule(style: .continuous).stroke(DS.Palette.ink.opacity(0.04), lineWidth: 0.6) }
    }
}

// MARK: - Suggestion rows

struct SuggestionSheetSection: Identifiable {
    let title: String
    let suggestions: [Suggestion]
    var id: String {
        title
    }
}

private struct SuggestionSheetSectionView: View {
    let section: SuggestionSheetSection
    let handlers: SuggestionCardHandlers

    /// Optional so store-less previews still render the receipt rows; the
    /// real hosts always provide it (UniversalCard requires it regardless).
    @Environment(HomeStore.self) private var home: HomeStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetSectionHeader(title: section.title)
            VStack(spacing: 8) {
                ForEach(section.suggestions) { suggestion in
                    row(suggestion)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Open cards ARE the Home cards: the same UniversalCard through the same
    /// gate, tap disclosing in place — the retired SuggestionChatSheet is gone
    /// from this surface. A live sign-in code keeps its
    /// tap-to-copy row, and a closed card is a receipt, not a button.
    @ViewBuilder
    private func row(_ suggestion: Suggestion) -> some View {
        if suggestion.isOpen, HomeScreen.usesUniversalCard(suggestion) {
            UniversalCard(
                suggestion: suggestion,
                isUnread: home?.isUpdateUnread(suggestion) ?? false,
                onDelete: handlers.onDelete,
                onRunAction: handlers.onRunAction,
                onGeneratedAction: handlers.onGeneratedAction,
                onMarkRead: { handlers.onMarkRead(suggestion) },
                onRunOrder: handlers.onRunOrder
            )
        } else if suggestion.isOpen, let code = suggestion.code, !code.isEmpty {
            CodeCopyListRow(suggestion: suggestion, code: code)
        } else {
            SuggestionListRow(suggestion: suggestion)
        }
    }
}

/// A sign-in-code row: tap copies the code (grouping spaces stripped, exactly
/// like the inline UpdateCard) and flips the row's chip to "Copied" — the list
/// must never be a surface where a code is visible but unreachable.
private struct CodeCopyListRow: View {
    let suggestion: Suggestion
    let code: String
    /// Optional: the sheet is presented from Home, so the store rides the
    /// environment — a copy here consumes the code out of the surfaced slot
    /// too (and marks its row seen). Nil-safe for previews without a store.
    @Environment(HomeStore.self) private var home: HomeStore?
    @State private var copied = false

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            UIPasteboard.general.string = code.replacingOccurrences(of: " ", with: "")
            DSHaptics.selection()
            home?.markUpdateSeen(suggestion)
            home?.markCodeConsumed(suggestion)
            withAnimation(.smooth(duration: 0.2, extraBounce: 0)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.smooth(duration: 0.3, extraBounce: 0)) { copied = false }
            }
        } label: {
            SuggestionListRow(suggestion: suggestion, codeCopied: copied)
        }
        .buttonStyle(.plain)
    }
}

private struct SuggestionListRow: View {
    let suggestion: Suggestion
    /// Sign-in-code rows only: the wrapping CodeCopyListRow's "just copied"
    /// flash, reflected in the code line's trailing glyph.
    var codeCopied: Bool = false
    private let shape = RoundedRectangle(cornerRadius: DS.Radius.card)

    /// Same title the inline card leads with — updates and suggestions each
    /// keep their own header line (UniversalCard.titleLine's rule).
    private var titleLine: String {
        suggestion.section == .updates ? suggestion.updateHeaderLine : suggestion.proposalLine
    }

    /// The card's own headline run: title + Iris's context flowed as one
    /// paragraph, dedup rules included — open and closed alike (the receipt
    /// line rides below the context on closed rows).
    private var headline: AttributedString {
        UniversalCard.headline(
            title: titleLine,
            context: UniversalCard.contextText(title: titleLine, raw: suggestion.contextLine)
        )
    }

    // Closed rows say HOW they closed: deleted by the user ("Dismissed", muted
    // ✕) vs consumed by an action (what was done, green ✓).
    private var statusText: String? {
        guard !suggestion.isOpen else { return nil }
        if suggestion.wasDismissed { return "Dismissed" }
        return suggestion.handledResult ?? "Handled"
    }

    private var statusIcon: String {
        suggestion.wasDismissed ? "xmark" : "checkmark"
    }

    private var statusTint: Color {
        suggestion.wasDismissed ? DS.Palette.placeholder : DS.Palette.success
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rowAvatar

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headline)
                        .lineSpacing(1.5)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    // When an open suggestion came in — relative age, riding
                    // the title's first baseline like the inline card.
                    if suggestion.isOpen, !suggestion.ageLabel.isEmpty {
                        Text(suggestion.ageLabel)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.placeholder)
                            .fixedSize()
                    }
                }

                // A live sign-in code renders its digits right in the row —
                // the "All" list must offer the same code the inline card does.
                if suggestion.isOpen, let code = suggestion.code, !code.isEmpty {
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(DS.Palette.ink)
                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(codeCopied ? DS.Palette.success : DS.Palette.placeholder)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(codeCopied ? Text("Code copied") : Text("Sign-in code \(code). Tap to copy."))
                }

                if let statusText {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(statusTint)
                        Text(statusText)
                            .font(.system(size: 12, weight: .regular)).tracking(-0.12)
                            .foregroundStyle(Color(light: 0x777777, dark: 0xAEAEB2))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The inline card's plate, verbatim (UniversalCard.cardPlate at rest):
        // solid card fill, 28pt radius, the shared solid-plate shadow pair —
        // the history rows ARE the cards, just resolved.
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(DS.Palette.card))
        .shadow(color: Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0), radius: 18, y: 8)
        .shadow(color: Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.05, darkOpacity: 0), radius: 3, y: 1.5)
    }

    private var rowAvatar: some View {
        SuggestionEntryAvatar(suggestion: suggestion)
    }
}

private struct SheetSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold)).tracking(-0.12)
                .foregroundStyle(DS.Palette.ink.opacity(0.58))
                .textCase(.uppercase)
            Rectangle().fill(DS.Palette.ink.opacity(0.06)).frame(height: 1)
        }
        .padding(.horizontal, 4)
    }
}
