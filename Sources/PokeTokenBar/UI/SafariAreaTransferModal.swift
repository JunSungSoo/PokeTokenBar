import SwiftUI

@MainActor
struct SafariAreaTransferModal: View {
    let options: [SafariArea]
    let catalog: SafariCatalog?
    let language: AppLanguage
    let confirm: (SafariArea) -> Void
    @State private var selected: SafariArea?
    private var l:L { L(language) }
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing:16) {
                Text(l.safariTravelTitle).font(.headline)
                Text(l.safariTravelChooseMessage).multilineTextAlignment(.center)
                HStack(alignment:.top,spacing:8) {
                    ForEach(options,id:\.self) { area in
                        VStack(spacing:8) {
                            if let representative = catalog?.representative(in:area) {
                                SpriteView(speciesID:representative.id,size:72,animated:true)
                                Text(BattleTextCatalog.shared.speciesName(representative.id,language:language))
                                    .font(.caption.weight(.semibold)).lineLimit(1)
                                Text(l.safariRepresentative).font(.caption2).foregroundStyle(.secondary)
                            }
                            SafariFinishButton(title:l.safariArea(area) + (selected == area ? " ✓":""),enabled:true,
                                identifier:"safari-travel-option-" + area.rawValue) { selected = area }.fixedSize()
                        }
                        .padding(8).frame(maxWidth:.infinity)
                        .background(selected == area ? Color.accentColor.opacity(0.18):Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8).stroke(selected == area ? Color.accentColor:Color.clear,lineWidth:2))
                    }
                }
                SafariFinishButton(title:l.battleConfirm,enabled:selected != nil,identifier:"safari-travel-confirm") {
                    if let selected { confirm(selected) }
                }.fixedSize()
            }
            .padding(24).frame(width:580)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
            .shadow(radius:16)
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("safari-area-transfer")
        }
    }
}
