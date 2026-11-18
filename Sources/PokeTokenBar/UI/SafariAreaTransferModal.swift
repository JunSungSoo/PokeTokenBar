import SwiftUI

/// Cancellable picker over every other Safari area, each shown with its representative Pokémon.
@MainActor
struct SafariAreaTransferModal: View {
    let options: [SafariArea]
    let catalog: SafariCatalog?
    let language: AppLanguage
    let warnsAboutFleeing: Bool
    let confirm: (SafariArea) -> Void
    let cancel: () -> Void
    @State private var selected: SafariArea?
    private var l: L { L(language) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 12) {
                Text(l.safariTravelTitle).font(.headline)
                Text(l.safariTravelChooseMessage).multilineTextAlignment(.center)
                if warnsAboutFleeing { Text(l.safariTravelFleeNote).font(.caption).foregroundStyle(.orange) }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(options, id: \.self) { area in
                        VStack(spacing: 4) {
                            if let representative = catalog?.representative(in: area) {
                                SpriteView(speciesID: representative.id, size: 52, animated: true)
                                Text(BattleTextCatalog.shared.speciesName(representative.id, language: language))
                                    .font(.caption2).lineLimit(1)
                            }
                            // Long area names wrap here; the native button keeps a short label so cards never overlap.
                            Text(l.safariArea(area)).font(.callout.weight(.semibold)).multilineTextAlignment(.center)
                                .lineLimit(2).minimumScaleFactor(0.75).frame(maxWidth: .infinity, minHeight: 34)
                            SafariFinishButton(title: (selected == area ? "✓ " : "") + l.safariTravelSelect, enabled: true,
                                identifier: "safari-travel-option-" + area.rawValue) { selected = area }.fixedSize()
                        }
                        .padding(6).frame(maxWidth: .infinity)
                        .background(selected == area ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == area ? Color.accentColor : Color.clear, lineWidth: 2))
                    }
                }
                HStack(spacing: 12) {
                    SafariFinishButton(title: l.cancel, enabled: true, identifier: "safari-travel-cancel", action: cancel).fixedSize()
                    SafariFinishButton(title: l.safariTravelButton, enabled: selected != nil, identifier: "safari-travel-confirm") {
                        if let selected { confirm(selected) }
                    }.fixedSize()
                }
            }
            .padding(20).frame(width: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("safari-area-transfer")
        }
    }
}
