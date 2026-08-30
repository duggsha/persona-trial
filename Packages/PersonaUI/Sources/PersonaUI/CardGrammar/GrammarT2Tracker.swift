import PersonaDesign
import SwiftUI

// T2 · the live tracker: brand-lockup · trailing fact · status · detail ·
// stage track. No mic and no action row — a view over a poll, not a
// suggestion. DoorDash and Lyft, and the same slots filled the same way; the
// only differences left are the stop count and the words.

enum GrammarBrandLockup: Hashable {
    /// Mark + name set beside it at the lockup's proportions (DoorDash — its
    /// wordmark is not the artwork we ship, so the name is typed).
    case doorDash
    /// The artwork IS the wordmark (Lyft).
    case lyft

    @ViewBuilder
    var view: some View {
        switch self {
        case .doorDash:
            HStack(spacing: 6) {
                PersonaAsset.image("LogoDoorDashMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 21.1, height: 12)
                Text("DoorDash")
                    .font(.system(size: 12.5, weight: .bold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(GrammarPalette.brandDoorDash)
            }
        case .lyft:
            PersonaAsset.image("LogoLyft")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24.9, height: 17)
        }
    }
}

struct GrammarT2Model: Hashable {
    var lockup: GrammarBrandLockup
    /// The live socket ETA. Omitted until the frame capture lands (T5.4a).
    var trailingFact: String?
    var status: String
    var detail: String
    var stops: [String]
    var currentStop: Int
    /// DoorDash tints the run that happened its own red — the one element the
    /// brand's own product tints. The ride's track stays ink.
    var brandTint: Color?
}

struct GrammarT2Tracker: View {
    let model: GrammarT2Model

    var body: some View {
        content.grammarCardPlate()
    }

    /// The drawing WITHOUT its plate — same split as GrammarT1Card, and for
    /// the same reason: the live feed already owns a plate that tints on a
    /// reject swipe, so a second one inside it doubles the shadow.
    @ViewBuilder
    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                model.lockup.view
                Spacer(minLength: 0)
                if let fact = model.trailingFact {
                    Text(fact)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.Palette.placeholder)
                }
            }
            Text(model.status)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, 10)
            Text(model.detail)
                .font(.system(size: 13.5))
                .foregroundStyle(DS.Palette.placeholder)
                .grammarLeading(size: 13.5, weight: .regular, lineHeight: 1.35)
                // `.b-sub` wraps; it never truncates.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            track
                .padding(.top, 15)
            labels
                .padding(.top, 7)
        }
    }

    private var doneTint: Color { model.brandTint ?? DS.Palette.ink }

    /// `.progress-track`: dot · rule · dot · … — dots up to the current stop
    /// are filled, rules before it are done, stops ahead stay hollow.
    private var track: some View {
        HStack(spacing: 6) {
            ForEach(model.stops.indices, id: \.self) { index in
                if index > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index <= model.currentStop ? doneTint : DS.Palette.track)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
                if index <= model.currentStop {
                    Circle().fill(doneTint).frame(width: 9, height: 9)
                } else {
                    Circle()
                        .strokeBorder(DS.Palette.hairline, lineWidth: 2)
                        .frame(width: 9, height: 9)
                }
            }
        }
    }

    /// `.pt-labels`: each label under its own dot at any stop count. The dots
    /// run evenly from x=4.5 to x=W−4.5, so interior labels centre on their
    /// dot and the outer pair pins to the card's edges.
    private var labels: some View {
        GrammarTrackLabels {
            ForEach(model.stops.indices, id: \.self) { index in
                let isCurrent = index == model.currentStop
                // 10.5, not the deck's 11.5. Five stops
                // at 11.5 spend 233 of 337pt on ink, and because the outer
                // pair pins to the card's edges the slack lands unevenly —
                // three gaps of 22–38pt and a last one of 9.7, which reads as
                // `On the way` touching `Delivered`. A point of type buys
                // ~20pt back and the row's rhythm with it.
                Text(model.stops[index])
                    .font(.system(size: 10.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? DS.Palette.ink : DS.Palette.placeholder)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Places one label per stop: outer pair pinned to the edges, interior
/// labels centred on their dots — then nudged apart wherever two would
/// collide, so "On the way" never touches "Delivered". Dot-centring is the
/// preference; the minimum gap is the rule.
private struct GrammarTrackLabels: Layout {
    var dotInset: CGFloat = 4.5
    /// The floor, not the target. 8 was still legible as a collision beside
    /// this row's other gaps; 14 is the smallest step that reads as deliberate
    /// space between two words rather than as a pair that ran out of room.
    var minGap: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let step = (bounds.width - dotInset * 2) / CGFloat(max(count - 1, 1))
        var minXs = (0 ..< count).map { index -> CGFloat in
            if index == 0 { return 0 }
            if index == count - 1 { return bounds.width - widths[index] }
            return dotInset + step * CGFloat(index) - widths[index] / 2
        }
        // Resolve collisions: push right off the left neighbour, then pull
        // left off the right one — the edges stay pinned, the middle gives.
        for index in 1 ..< count {
            minXs[index] = max(minXs[index], minXs[index - 1] + widths[index - 1] + minGap)
        }
        for index in stride(from: count - 2, through: 0, by: -1) {
            minXs[index] = min(minXs[index], minXs[index + 1] - minGap - widths[index])
        }
        for index in 0 ..< count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + minXs[index], y: bounds.minY),
                proposal: .unspecified
            )
        }
    }
}
