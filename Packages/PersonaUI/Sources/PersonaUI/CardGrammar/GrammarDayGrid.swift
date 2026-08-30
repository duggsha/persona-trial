import PersonaDesign
import SwiftUI

// The embedded calendar selector (flow-daygrid.css `.dg-card`): the day drawn
// instead of described. One plate, two users — the time picker (question,
// extracted-constraint chips, day strip, grid, hint, disabled commit) and the
// invite (same fields, day tabs and hint switched off, Accept pair at the
// foot). Everything absolutely positioned in the column is model data, in
// points, exactly as the prototype inlines it.

/// `.ts-head`: attribution small, QUESTION as the title — the question is
/// what the grid below is an answer to.
struct GrammarQuestionHead: View {
    var initials: String
    var who: String
    var question: String

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(DS.Palette.accent.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(initials)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DS.Palette.accent)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(who)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DS.Palette.subtle)
                Text(question)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .grammarLeading(size: 17, weight: .semibold, lineHeight: 1.2)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}

/// `.dg-chip`: what the sender constrained. One variant carries the cast at
/// 18pt — a chip with a face pile is still 26pt tall.
enum GrammarConstraintChip: Hashable {
    case text(String)
    case cast([GrammarFace], String)
}

struct GrammarConstraintChips: View {
    var chips: [GrammarConstraintChip]

    var body: some View {
        FlowingChips(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                switch chip {
                case let .text(label):
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Palette.subtle)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(DS.TaskState.chipFill, in: Capsule())
                case let .cast(faces, label):
                    HStack(spacing: 8) {
                        HStack(spacing: -3) {
                            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                                Circle()
                                    .fill(face.fill)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Text(face.initials)
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(face.ink)
                                    }
                                    .background { Circle().fill(DS.Palette.card).frame(width: 22, height: 22) }
                            }
                        }
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .tracking(-0.1)
                            .foregroundStyle(DS.Palette.subtle)
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 10)
                    .frame(height: 26)
                    .background(DS.TaskState.chipFill, in: Capsule())
                }
            }
        }
        .padding(.top, 9)
    }
}

/// Wrapping chip row — CSS `flex-wrap`. Layout, so a fourth chip breaks to a
/// second line instead of squeezing the row (the thread picker's four).
struct FlowingChips: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - The week, as four days (`.dg-days`)

struct GrammarDayTab: Hashable {
    var name: String
    var number: String
    /// The capacity line — evidence, not a label. "full"/"out" closes the day.
    var free: String
    var state: State = .open

    enum State: Hashable {
        case open
        case selected
        case full
    }
}

struct GrammarDayStrip: View {
    var days: [GrammarDayTab]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 0) {
                    Text(day.name)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(titleInk(day))
                    Text(day.number)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(titleInk(day))
                    Text(day.free)
                        .font(.system(size: 11))
                        .tracking(-0.1)
                        .foregroundStyle(freeInk(day))
                        .padding(.top, 2)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background {
                    let shape = RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
                    if day.state == .selected {
                        shape.fill(DS.Palette.ink)
                    } else {
                        shape.fill(DS.Palette.card)
                            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1)
                    }
                }
                // 0.97, one notch shallower than a pill: 0.98 on a 78pt tile
                // is nearly invisible beside a full-width pill dipping the
                // same amount, and a tile that stays still reads as disabled.
                .grammarPressable(scale: 0.97)
            }
        }
        .padding(.top, 11)
        .padding(.horizontal, -2)
    }

    private func titleInk(_ day: GrammarDayTab) -> Color {
        switch day.state {
        case .selected: DS.Palette.onInk
        case .full: DS.Palette.placeholder
        case .open: DS.Palette.ink
        }
    }

    private func freeInk(_ day: GrammarDayTab) -> Color {
        switch day.state {
        case .selected: .white.opacity(0.6)
        case .full: Color(hex: 0xC08A86)
        case .open: DS.Palette.placeholder
        }
    }
}

// MARK: - The column (`.dg-grid`)

struct GrammarDayColumnModel: Hashable {
    /// Hour labels down the rail, one per line from the top, one hourStep apart.
    var hours: [String]
    /// Points per hour — 44 on the picker, 56 on the invite.
    var hourStep: CGFloat
    /// Hatched "outside the window she named" bands: (top, height, label?).
    var bands: [Band] = []
    var busy: [Busy] = []
    var ghosts: [Ghost] = []

    var height: CGFloat { hourStep * CGFloat(hours.count - 1) }

    struct Band: Hashable {
        var top: CGFloat
        var height: CGFloat
        var label: String?
        /// Label pinned to the band's bottom edge (top band) or top (bottom band).
        var labelAtBottom = true
    }

    /// The user's own events, quiet — the evidence, not the subject.
    struct Busy: Hashable {
        var top: CGFloat
        var height: CGFloat
        var title: String
        var when: String?
    }

    /// What Persona proposes: dashed, because a proposal is not yet an answer.
    struct Ghost: Hashable {
        var top: CGFloat
        var height: CGFloat
        var time: String
        /// Rank 1's mark — the time the card's primary would have sent.
        var starred = false
        /// Why, written directly above the thing it refers to.
        var why: String?
    }
}

struct GrammarDayColumn: View {
    let model: GrammarDayColumnModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // The hour rail: labels at the LINE, not centred in the row.
            ZStack(alignment: .topTrailing) {
                Color.clear
                ForEach(Array(model.hours.enumerated()), id: \.offset) { index, hour in
                    Text(hour)
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Palette.placeholder)
                        .fixedSize()
                        .alignmentGuide(.top) { $0.height / 2 - model.hourStep * CGFloat(index) }
                }
            }
            .frame(width: 34, height: model.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Palette.card)
                    .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1)
                ForEach(1 ..< max(model.hours.count - 1, 1), id: \.self) { index in
                    Rectangle()
                        .fill(DS.Palette.hairlineSoft)
                        .frame(height: 1)
                        .offset(y: model.hourStep * CGFloat(index))
                }
                ForEach(Array(model.bands.enumerated()), id: \.offset) { _, band in
                    bandView(band)
                }
                ForEach(Array(model.busy.enumerated()), id: \.offset) { _, block in
                    busyView(block)
                }
                ForEach(Array(model.ghosts.enumerated()), id: \.offset) { _, ghost in
                    ghostView(ghost)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: model.height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .padding(.top, 12)
    }

    private func bandView(_ band: GrammarDayColumnModel.Band) -> some View {
        GrammarHatch()
            .background(DS.Palette.surfaceMuted)
            .overlay(alignment: band.labelAtBottom ? .bottomTrailing : .topTrailing) {
                if let label = band.label {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Palette.placeholder)
                        .padding(.trailing, 8)
                        .padding(.vertical, 5)
                }
            }
            .frame(height: band.height)
            .offset(y: band.top)
    }

    private func busyView(_ block: GrammarDayColumnModel.Busy) -> some View {
        Group {
            if let when = block.when {
                VStack(alignment: .leading, spacing: 0) {
                    Text(block.title)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Palette.subtle)
                        .lineLimit(1)
                    Text(when)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.placeholder)
                }
                .padding(.top, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // Under 26pt the title alone, centred, is the honest render.
                Text(block.title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(DS.Palette.subtle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                Rectangle().fill(DS.Palette.track).frame(width: 3)
                DS.Palette.surfaceMuted
            }
        }
        .frame(height: block.height)
        .offset(y: block.top)
    }

    private func ghostView(_ ghost: GrammarDayColumnModel.Ghost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if ghost.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.Palette.ink)
                }
                Text(ghost.time)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(DS.Palette.ink)
            }
            if let why = ghost.why {
                Text(why)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.subtle)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.Palette.ink.opacity(0.028))
                .strokeBorder(
                    DS.Palette.ink.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
        }
        .frame(height: ghost.height)
        .grammarPressable()
        .offset(y: ghost.top)
    }
}

/// The band's -45° hatch: 5pt ink-wash stripes on 5pt gaps.
struct GrammarHatch: View {
    var body: some View {
        Canvas { context, size in
            let stripe: CGFloat = 5
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(
                    path,
                    with: .color(DS.Palette.ink.opacity(0.028)),
                    style: StrokeStyle(lineWidth: stripe)
                )
                x += stripe * 2
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The whole plate

struct GrammarDayGridModel {
    var head: (initials: String, who: String, question: String)
    var chips: [GrammarConstraintChip]
    var days: [GrammarDayTab] = []
    var column: GrammarDayColumnModel?
    /// The grid's real cost, paid in one line — the empty state is an
    /// instruction (`.dg-hint`).
    var hint: String?
    var foot: Foot

    enum Foot {
        /// The picker's single commit, disabled until something is picked.
        case commit(String)
        /// The invite's equal-weight pair.
        case pair([GrammarPill])
        case none
    }
}

struct GrammarDayGridCard: View {
    let model: GrammarDayGridModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GrammarQuestionHead(initials: model.head.initials, who: model.head.who, question: model.head.question)
            GrammarConstraintChips(chips: model.chips)
            if !model.days.isEmpty {
                GrammarDayStrip(days: model.days)
            }
            if let column = model.column {
                GrammarDayColumn(model: column)
            }
            if let hint = model.hint {
                Text(hint)
                    .font(.system(size: 13))
                    .tracking(-0.1)
                    .grammarLeading(size: 13, weight: .regular, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.placeholder)
                    .fixedSize(horizontal: false, vertical: true)
                    // `.dg-foot` 13 above + the hint's own 9 / 3 / 2.
                    .padding(EdgeInsets(top: 22, leading: 2, bottom: 3, trailing: 2))
            }
            switch model.foot {
            case let .commit(label):
                GrammarPillView(pill: .init(label: label, fill: .commit, icon: nil))
                    .opacity(0.4)
                    .padding(.top, model.hint == nil ? 13 : 0)
            case let .pair(pills):
                GrammarPillRow(pills: pills)
                    .padding(.top, 16)
            case .none:
                EmptyView()
            }
        }
        .grammarCardPlate()
    }
}
