import AppKit
import SwiftUI

/// A standalone window survives dismissal of the transient menu-bar popover.
@MainActor
final class RedMapleWindowController: NSObject, NSWindowDelegate {
    static let shared=RedMapleWindowController()
    private var window:NSWindow?
    func show(store:CompanionStore) {
        if let window { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);return }
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:560),
            styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title=store.l.itemName(.redMaple)
        window.isReleasedWhenClosed=false
        window.delegate=self
        window.contentViewController=NSHostingController(rootView:RedMapleSelectionView(store:store))
        self.window=window
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification:Notification) { window=nil }
}

@MainActor
struct RedMapleSelectionView:View {
    let store:CompanionStore
    @State private var selectedID:String?
    @State private var applied=false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                ItemIconView(kind:.redMaple)
                VStack(alignment:.leading,spacing:4) {
                    Text(store.l.redMapleChoose).font(.headline)
                    Text(store.l.redMapleHint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("×\(store.itemCount(.redMaple))").monospacedDigit()
            }
            ScrollView {
                LazyVStack(spacing:8) {
                    if store.redMapleTargets.isEmpty { Text(store.l.redMapleEmpty).padding() }
                    ForEach(store.redMapleTargets) { entry in
                        Button {
                            selectedID=entry.id;applied=false
                        } label: {
                            HStack(spacing:10) {
                                SpriteView(speciesID:entry.finalID,size:52,animated:true,shiny:entry.isShiny,form:entry.form)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(BattleTextCatalog.shared.speciesName(entry.finalID,language:store.language)).font(.headline)
                                    if let profile=entry.profile {
                                        Text(PokemonStatCalculator.order.map { stat in
                                            store.l.statLabel(stat)+" "+PokemonStatGrade.label(iv:profile.ivs[stat])
                                        }.joined(separator:" · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal:false,vertical:true)
                                    }
                                }
                                Spacer(minLength:0)
                                Image(systemName:selectedID == entry.id ? "checkmark.circle.fill":"circle")
                                    .foregroundStyle(selectedID == entry.id ? Color.accentColor:Color.secondary)
                            }
                            .padding(10).frame(maxWidth:.infinity,alignment:.leading)
                            .background(selectedID == entry.id ? Color.accentColor.opacity(0.14):Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain).accessibilityIdentifier("red-maple-target-"+entry.id)
                    }
                }
            }
            Divider()
            HStack {
                if applied { Text(store.l.redMapleApplied).font(.caption).foregroundStyle(.green) }
                Spacer()
                Button(store.l.useItem) {
                    if let selectedID { applied=store.useRedMaple(entryID:selectedID) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canUseRedMaple || !store.redMapleTargets.contains(where:{$0.id == selectedID}))
                .accessibilityIdentifier("red-maple-apply")
            }
        }.padding(16).frame(minWidth:500,minHeight:560)
    }
}
