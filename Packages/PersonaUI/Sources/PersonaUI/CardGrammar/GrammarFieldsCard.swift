import PersonaDesign
import SwiftUI

// The inline fields plate (flow-invite.css `.ev-msg` + `.ev-fields`): the
// plate that renders FIELDS OF AN OBJECT rather than a question — the account
// review's Cancelling / Because / Keeping, with the decision pill underneath.

struct GrammarFieldsCardModel {
    var rows: [(key: String, value: String)]
    var pill: GrammarPill?
}

struct GrammarFieldsCard: View {
    let model: GrammarFieldsCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.key)
                        .foregroundStyle(DS.Palette.placeholder)
                        .frame(width: 74, alignment: .leading)
                    Text(row.value)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 14.5))
                .grammarLeading(size: 14.5, weight: .regular, lineHeight: 1.35)
                .padding(.vertical, 6)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
                    }
                }
            }
            if let pill = model.pill {
                // `.ev-decide`: the sheet's own answer to the card's button.
                GrammarPillRow(pills: [pill])
                    .padding(.top, 16)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 18, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
                .fill(DS.Palette.card)
                .dsShadow(DS.Shadow.contact)
        }
    }
}
