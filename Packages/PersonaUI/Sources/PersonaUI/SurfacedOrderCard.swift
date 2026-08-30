import PersonaCore
import PersonaDesign
import SwiftUI

/// A running DoorDash order, in Home's surfaced slot directly under Up Next —
/// the same position a live sign-in code takes, for the same reason: it is the
/// thing that is useful *right now* and worthless twenty minutes later.
///
/// The bar is driven by the server's `progress` (0…1), never re-ranked here, so
/// a status DoorDash adds tomorrow cannot silently render at 0%. The ladder of
/// dots is decoration over that one number, not a second source of truth.
struct SurfacedOrderCard: View {
    let suggestion: Suggestion
    /// The slot heartbeat — drives the travelling sheen without a second timer.
    let now: Date

    private var order: OrderProgressItem? { suggestion.orderProgress }

    var body: some View {
        if let order {
            Group {
                // The deck draws a running order as T2: brand lockup, status,
                // store, and a staged track instead of this card's continuous
                // bar. It wears the shared card plate rather than this slot's
                // hairline box, because under the grammar a tracker is a card
                // like any other, just one you cannot act on.
                if CardGrammar.isOn, case let .t2(model)? = suggestion.grammarDrawing(isUnread: false) {
                    GrammarT2Tracker(model: model)
                } else {
                    content(order)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(DS.Palette.surface)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(DS.Palette.hairlineSoft, lineWidth: 1)
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(order))
            .accessibilityIdentifier("surfaced-order-card")
        }
    }

    private func content(_ order: OrderProgressItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                glyph(order)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.storeName ?? "Your order")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                    Text(suggestion.message)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(order.isPickup ? "Pickup" : "Delivery")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(DS.Palette.surfaceAlt))
            }
            progressBar(order)
        }
    }

    /// A settled order swaps the animated mark for a plain check: motion on a
    /// finished thing reads as "still working", which is the one thing it isn't.
    private func glyph(_ order: OrderProgressItem) -> some View {
        ZStack {
            Circle()
                .fill(order.done ? DS.Palette.success.opacity(0.14) : DS.Palette.accent.opacity(0.14))
            Image(systemName: order.done ? "checkmark" : (order.isPickup ? "bag.fill" : "bicycle"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(order.done ? DS.Palette.success : DS.Palette.accent)
        }
        .frame(width: 38, height: 38)
    }

    private func progressBar(_ order: OrderProgressItem) -> some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width)
            let filled = width * order.progress
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.track)
                Capsule()
                    .fill(order.done ? DS.Palette.success : DS.Palette.accent)
                    .frame(width: filled)
                    .overlay(alignment: .leading) {
                        // A slow sheen travelling the filled span: the only
                        // signal that this is LIVE rather than a static
                        // snapshot. It stops the moment the order settles.
                        if !order.done, filled > 8 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, DS.Palette.onInk.opacity(0.45), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 46)
                                .offset(x: sheenOffset(in: filled))
                                .blendMode(.plusLighter)
                        }
                    }
                    .animation(.smooth(duration: 0.6, extraBounce: 0), value: order.progress)
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }

    /// Sweeps left→right across the filled span once every 1.8s, derived from
    /// the slot's existing tick so this view owns no timer of its own.
    private func sheenOffset(in filled: CGFloat) -> CGFloat {
        let period = 1.8
        let phase = now.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
        return (filled + 46) * phase - 46
    }

    private func accessibilityText(_ order: OrderProgressItem) -> String {
        let where_ = order.storeName.map { " from \($0)" } ?? ""
        return "\(suggestion.message)\(where_). \(Int(order.progress * 100)) percent."
    }
}
