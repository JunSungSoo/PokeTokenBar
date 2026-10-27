import AppKit
import SwiftUI

/// A row click changes only the preview. Apply is the sole assignment/recency boundary.
@MainActor struct BattleItemPicker:View {
    let pokemon:DexEntry
    let current:String
    let assignments:[String:String]
    let language:AppLanguage
    let usage:BattleItemUsageStore
    let onApply:(String)->Bool
    let onCancel:()->Void
    var collectionDefault=false
    @State private var pending:String
    @State private var category:BattleItemCategory = .all
    private var l:L {L(language)}
    init(pokemon:DexEntry,current:String,assignments:[String:String],language:AppLanguage,usage:BattleItemUsageStore = .shared,collectionDefault:Bool=false,onApply:@escaping(String)->Bool,onCancel:@escaping()->Void) {
        self.pokemon=pokemon;self.current=current;self.assignments=assignments;self.language=language;self.usage=usage;self.onApply=onApply;self.onCancel=onCancel
        _pending=State(initialValue:current)
        self.collectionDefault=collectionDefault
    }
    private var inUse:Bool { !pending.isEmpty && assignments.contains{$0.key != pokemon.id && $0.value==pending} }
    private var choices:[PokemonLoadoutChoice] {
        [.init(id:"",title:l.battleNoItem,tooltip:l.battleHeldItemHint)] + usage.sorted(BattleHeldItems.choices(speciesID:pokemon.finalID,form:pokemon.form).filter{category.includes($0)},language:language).map { item in
            let used=assignments.contains{$0.key != pokemon.id && $0.value==item.id}
            return .init(id:item.id,title:item.name(language)+(used ? " · "+l.battleItemInUse:""),tooltip:item.tooltip(language))
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(l.battleChooseItem+" · "+BattleTextCatalog.shared.speciesName(pokemon.finalID,language:language)).font(.headline)
            Text(l.battleItemOrderHint).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal,showsIndicators:false) {
                Picker(l.battleChooseItem,selection:$category) {
                    ForEach(BattleItemCategory.allCases) { group in Text(group.title(language)).tag(group) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal:true,vertical:false)
                    .accessibilityIdentifier("battle-item-categories")
            }
            .onChange(of:category) { _,group in
                if let item=BattleHeldItems.item(pending),!group.includes(item){pending=""}
            }
            HStack(alignment:.top,spacing:16) {
                BattleItemList(choices:choices,selectedID:pending,onSelect:{pending=$0})
                    .frame(width:252,height:250).accessibilityIdentifier("battle-item-list")
                VStack(alignment:.leading,spacing:10) {
                    if let item=BattleHeldItems.item(pending) {
                        Text(item.name(language)).font(.title3.bold()).accessibilityIdentifier("battle-item-description-title")
                        ScrollView {Text(item.descriptions[language.rawValue]!).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}
                    } else {
                        Text(l.battleNoItem).font(.title3.bold())
                        Text(l.battleItemPreviewHint).foregroundStyle(.secondary)
                    }
                    if inUse {Text(l.battleItemInUse).font(.caption.bold()).foregroundStyle(.red)}
                    if pending==current {Text(l.battleItemEquipped).font(.caption).foregroundStyle(.secondary)}
                    Spacer(minLength:0)
                }.frame(maxWidth:.infinity,alignment:.leading).frame(height:250)
            }
            Divider()
            HStack {
                Text(collectionDefault ? l.collectionDefaultItemHint:l.battleDuplicateItem).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer()
                Button(l.cancel,action:onCancel).keyboardShortcut(.cancelAction)
                Button(l.battleApplyItem){_ = onApply(pending)}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(inUse || pending==current).accessibilityIdentifier("battle-item-apply")
            }
        }.padding(18).frame(width:640,height:414)
    }
}

/// Native selection/keyboard navigation and bounded scrolling for the full item list.
@MainActor struct BattleItemList:NSViewRepresentable {
    let choices:[PokemonLoadoutChoice]
    let selectedID:String
    let onSelect:(String)->Void
    func makeCoordinator()->Coordinator {Coordinator(onSelect:onSelect)}
    func makeNSView(context:Context)->NSScrollView {
        let table=NSTableView();table.headerView=nil;table.rowHeight=29;table.usesAlternatingRowBackgroundColors=true
        table.allowsEmptySelection=false;table.allowsMultipleSelection=false
        let column=NSTableColumn(identifier:.init("item"));column.resizingMask = .autoresizingMask;table.addTableColumn(column)
        table.delegate=context.coordinator;table.dataSource=context.coordinator;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;scroll.documentView=table
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let table=scroll.documentView as? NSTableView else{return}
        let coordinator=context.coordinator;coordinator.onSelect=onSelect;coordinator.updating=true
        coordinator.choices=choices;table.reloadData()
        if let index=choices.firstIndex(where:{$0.id==selectedID}){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false);table.scrollRowToVisible(index)} else {table.deselectAll(nil)}
        coordinator.updating=false
    }
    final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
        var choices:[PokemonLoadoutChoice]=[];var updating=false
        var onSelect:(String)->Void
        init(onSelect:@escaping(String)->Void){self.onSelect=onSelect}
        func numberOfRows(in tableView:NSTableView)->Int {choices.count}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            let cell=(tableView.makeView(withIdentifier:.init("held-item-cell"),owner:self) as? NSTableCellView) ?? Self.makeCell()
            cell.textField?.stringValue=choices[row].title;cell.textField?.toolTip=choices[row].tooltip
            return cell
        }
        static func makeCell()->NSTableCellView {
            let cell=NSTableCellView();cell.identifier = .init("held-item-cell")
            let text=NSTextField(labelWithString:"");text.font = .systemFont(ofSize:12)
            text.lineBreakMode = .byTruncatingTail;text.translatesAutoresizingMaskIntoConstraints=false
            cell.addSubview(text);cell.textField=text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:6),
                text.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-6),
                text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)
            ])
            return cell
        }
        func tableViewSelectionDidChange(_ notification:Notification) {
            guard !updating,let table=notification.object as? NSTableView,choices.indices.contains(table.selectedRow) else{return}
            onSelect(choices[table.selectedRow].id)
        }
    }
}
