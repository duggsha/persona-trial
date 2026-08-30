import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI

/// Opened when a suggestion card is tapped: the full context plus the backend
/// actions as real buttons (send the drafted reply, open a link, …).
struct SuggestionDetailSheet: View {
    let suggestion: Suggestion

    @Environment(HomeStore.self) private var home
    // Optional: preview rigs may present this sheet without ProfileStore.
    @Environment(ProfileStore.self) private var profile: ProfileStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var runningType: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    badge
                    Text(suggestion.message)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.34)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !suggestion.detail.isEmpty {
                        irisBlock
                    }

                    actionButtons
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sheetBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .dsAppearance()
    }

    private var header: some View {
        HStack {
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
        }
        .padding(.top, 20)
        .padding(.horizontal, 22)
    }

    private var badge: some View {
        HStack(spacing: 8) {
            Image(systemName: suggestion.systemIcon ?? "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HomeIconTint.color(forKind: suggestion.kind, symbol: suggestion.systemIcon ?? "sparkles"))
                .frame(width: 34, height: 34)
                .background(DS.Palette.card, in: Circle())
                .overlay { Circle().stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
            Text(suggestion.badge)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.inkMuted)
        }
    }

    private var irisBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                BrandMark(size: 16)
                Text("\(profile?.assistantName ?? ProfileStore.defaultAssistantName) suggests")
                    .font(DS.Typography.micro)
                    .tracking(-0.10)
                    .foregroundStyle(DS.Palette.inkMuted)
            }
            Text(suggestion.detail)
                .font(.system(size: 15, weight: .regular))
                .tracking(-0.18)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidListPlate(fill: DS.Palette.surfaceAlt.opacity(0.80))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            ForEach(Array(suggestion.actions.enumerated()), id: \.element.id) { index, action in
                actionButton(action, prominent: index == 0)
            }
            if suggestion.actions.isEmpty {
                actionButton(SuggestionActionItem(type: "acknowledge", label: "Got it"), prominent: true)
            }
        }
    }

    private func actionButton(_ action: SuggestionActionItem, prominent: Bool) -> some View {
        Button {
            run(action)
        } label: {
            HStack(spacing: 8) {
                if runningType == action.type {
                    ProgressView().tint(prominent ? .white : DS.Palette.ink)
                }
                Text(action.label)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.2)
            }
            .foregroundStyle(prominent ? .white : DS.Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                if prominent {
                    DSPrimaryActionSurface(shape: Capsule(style: .continuous))
                } else {
                    Capsule(style: .continuous).fill(DS.Palette.card)
                }
            }
            .overlay {
                if !prominent {
                    Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(runningType != nil)
    }

    private func run(_ action: SuggestionActionItem) {
        guard runningType == nil else { return }
        runningType = action.type
        DSHaptics.tap()
        Task {
            let outcome = await home.performAction(suggestion, action)
            runningType = nil
            switch outcome {
            case let .openLink(url):
                openURL(url)
            case let .taskStarted(taskId):
                // Surface the new task on Home at once (this sheet just closes).
                home.noteTaskStarted(taskId: taskId, goal: suggestion.message)
                dismiss()
            case .sent, .acknowledged:
                dismiss()
            case let .permissionRequested(scope):
                // Raise the native dialog (or the Settings hand-off) as the
                // sheet closes — the dialog is the feedback.
                if await home.requestPermission(scope: scope) == .openSettings,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                dismiss()
            case .introCallPlaced:
                dismiss()
            case .failed:
                // Leave the sheet open so the user can retry; the error surfaces
                // on Home via HomeStore.errorText.
                break
            }
        }
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
