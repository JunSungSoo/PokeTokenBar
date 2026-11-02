import AppKit
import SwiftUI

@MainActor final class ChallengeWindowController:NSObject,NSWindowDelegate {
    private static var current:ChallengeWindowController?
    let model:ChallengeUIModel
    let battle:ChallengeBattleAdapter
    let audioSettings:BattleAudioSettings
    let auxiliary=BattleAuxiliaryState()
    let activity:ChallengeActivity
    private(set) var window:BattleViewportWindow?
    private(set) var fieldWindow:NSWindow?
    private(set) var statsWindow:NSWindow?
    private(set) var contentMeasurement:BattleContentMeasurement?
    private let allowsAudio:Bool
    private var player:BattleMusicPlayer?
    private var confirming=false
    private var visiblePresentation=true
    init(model:ChallengeUIModel,identity:BattleIdentity,allowsAudio:Bool=true,
         audioSettings:BattleAudioSettings = BattleAudioSettings(defaults:.standard),activity:ChallengeActivity = .shared) {
        self.model=model;self.battle=ChallengeBattleAdapter(model:model,identity:identity)
        self.allowsAudio=allowsAudio;self.audioSettings=audioSettings;self.activity=activity
        super.init()
        audioSettings.onVolumeChange={ [weak self] volume in self?.player?.volume=volume }
    }
    static func open(store:CompanionStore,identity:BattleIdentity)throws {
        if let current {current.show();return}
        let save=ChallengeRunStore(url:ChallengeTestMode.enabled ? AppStatePaths.directory().appendingPathComponent("challenge-test-run-v1.json"):nil),session=try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load())
        let controller=ChallengeWindowController(model:ChallengeUIModel(store:store,session:session),identity:identity)
        current=controller;controller.show()
    }
    func show(present:Bool=true) {
        visiblePresentation=present;model.isOpen=true;activity.isOpen=true
        if window==nil {
            let width=BattleWindowLayout.preferredWidth(for:.singles)
            let window=BattleViewportWindow(contentRect:NSRect(x:present ? 0:-10000,y:present ? 0:-10000,width:width,height:720),
                styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.minimumBattleWidth=width;window.minSize=NSSize(width:width,height:440)
            window.isReleasedWhenClosed=false;window.delegate=self
            let root=ChallengeRootView(model:model,battle:battle,audioSettings:audioSettings,auxiliary:auxiliary,allowsAudio:allowsAudio,
                onClose:{ [weak self] in self?.window?.performClose(nil) },
                onSurrender:{ [weak self] in self?.confirmSurrender() },
                onMusic:{ [weak self] in guard let self else{return};self.model.musicEnabled.toggle();self.refreshMusic() },
                onShowField:{ [weak self] in self?.showAuxiliary(.field) },onShowStats:{ [weak self] in self?.showAuxiliary(.stats) },
                onLayout:{ [weak self] measurement in Task{@MainActor [weak self] in self?.fit(measurement)} },
                onState:{ [weak self] in Task{@MainActor [weak self] in self?.sync()} })
            let host=NSHostingController(rootView:root);host.sizingOptions=[]
            window.contentViewController=host;self.window=window
            if present,let screen=NSScreen.main {window.setFrame(BattleWindowLayout(screen:screen.visibleFrame,mode:.singles).main,display:false)}
        }
        window?.title="PokeTokenBar · "+model.store.l.challengeTitle
        if present {NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)}
        else {window?.orderFront(nil)}
        sync()
    }
    private func fit(_ measurement:BattleContentMeasurement) {
        guard model.screen == .battle,let window else{return}
        contentMeasurement=measurement
        let title=window.frame.height-window.contentRect(forFrameRect:window.frame).height
        let visible=(window.screen ?? NSScreen.main)?.visibleFrame
        let height=min(ceil(measurement.content.height)+title,visible?.height ?? .greatestFiniteMagnitude)
        window.minSize=NSSize(width:660,height:height)
        if abs(window.frame.height-height)>0.5 {
            var rect=window.frame;rect.origin.y=max(visible?.minY ?? rect.minY,rect.maxY-height);rect.size.height=height
            window.setFrame(rect,display:true)
        }
    }
    private func sync() {
        guard let window,model.isOpen else{return}
        window.title="PokeTokenBar · "+model.store.l.challengeTitle
        model.synchronizeChampionAward()
        refreshMusic()
        if model.screen == .battle,visiblePresentation {
            if auxiliary.fieldVisible {showAuxiliary(.field)}
            if auxiliary.statsVisible {showAuxiliary(.stats)}
        } else {
            fieldWindow?.orderOut(nil);statsWindow?.orderOut(nil)
            if model.screen != .battle {
                let title=window.frame.height-window.contentRect(forFrameRect:window.frame).height
                let height=min(742.0,((window.screen ?? NSScreen.main)?.visibleFrame.height ?? 770)-title)
                window.minSize=NSSize(width:660,height:440)
                if abs(window.contentRect(forFrameRect:window.frame).height-height)>1 {window.setContentSize(NSSize(width:max(660,window.contentRect(forFrameRect:window.frame).width),height:height))}
            }
        }
    }
    func showAuxiliary(_ kind:BattleAuxiliaryKind) {
        guard let window,model.screen == .battle else{return}
        var panel=kind == .field ? fieldWindow:statsWindow
        if panel==nil {
            let created=NSPanel(contentRect:.zero,styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
            created.isReleasedWhenClosed=false;created.hidesOnDeactivate=false;created.delegate=self;created.minSize=NSSize(width:200,height:200)
            created.contentViewController=NSHostingController(rootView:BattleAuxiliaryView(kind:kind,battle:battle,store:model.store))
            if kind == .field{fieldWindow=created}else{statsWindow=created};panel=created
        }
        if kind == .field{auxiliary.fieldVisible=true}else{auxiliary.statsVisible=true}
        panel?.title=kind == .field ? model.store.l.battleFieldWindow:model.store.l.battleStatsWindow
        let layout=BattleWindowLayout(screen:(window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame,mode:.singles,main:window.frame)
        panel?.setFrame(kind == .field ? layout.field:layout.stats,display:true)
        if let panel {if panel.parent==nil {window.addChildWindow(panel,ordered:.above)};panel.orderFront(nil)}
    }
    func windowDidMove(_ notification:Notification){if notification.object as? NSWindow === window {syncAuxiliaryPositions()}}
    func windowDidResize(_ notification:Notification){if notification.object as? NSWindow === window {syncAuxiliaryPositions()}}
    private func syncAuxiliaryPositions(){
        guard let window else{return}
        let layout=BattleWindowLayout(screen:(window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame,mode:.singles,main:window.frame)
        if let fieldWindow,fieldWindow.isVisible{fieldWindow.setFrame(layout.field,display:true)}
        if let statsWindow,statsWindow.isVisible{statsWindow.setFrame(layout.stats,display:true)}
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {
        if sender===fieldWindow {auxiliary.fieldVisible=false;return true}
        if sender===statsWindow {auxiliary.statsVisible=false;return true}
        if model.run?.phase == .cleared,model.run?.championReward?.claimed != true,model.screen != .championReward {
            do{try model.offerChampionReward();sync()}catch{model.report(error)}
            return false
        }
        if model.running && model.run?.phase == .battling {confirmSurrender();return false}
        return true
    }
    private func confirmSurrender() {
        guard let window,model.run?.phase == .battling,!confirming else{return}
        confirming=true
        let alert=NSAlert();alert.messageText=model.store.l.battleConfirmClose;alert.informativeText=model.store.l.challengeLost
        alert.addButton(withTitle:model.store.l.cancel);alert.addButton(withTitle:model.store.l.battleSurrender)
        alert.beginSheetModal(for:window){ [weak self] response in Task{@MainActor [weak self] in
            guard let self else{return};self.confirming=false
            if response == .alertSecondButtonReturn {
                do {try self.model.session.surrender();self.model.runningDidEnd();self.sync()}
                catch {self.model.report(error)}
            }
        }}
    }
    func windowWillClose(_ notification:Notification) {
        guard notification.object as? NSWindow === window else{return}
        model.close();activity.isOpen=false;stopMusic()
        for panel in [fieldWindow,statsWindow].compactMap({$0}){panel.orderOut(nil);panel.contentViewController=nil;if let parent=panel.parent{parent.removeChildWindow(panel)}}
        fieldWindow=nil;statsWindow=nil
        window?.contentViewController=nil;window=nil
    }
    var musicCue:BattleMusicCue? {player?.cue}
    var resolvedMusicCue:BattleMusicCue? {
        if model.screen == .championReward{return nil}
        let encounterMusic:BattleMusicCue=model.encounter?.id=="red" ? .championBattle:.battle
        if model.run?.phase == .cleared{return model.sceneSettled || !model.running ? .championVictory:encounterMusic}
        let cue=BattleMusicCue.resolve(phase:battle.phase,outcome:battle.outcome,pending:battle.presentation.pending)
        return cue == .battle ? encounterMusic:cue
    }
    private func refreshMusic() {
        guard model.isOpen,(model.running || model.run?.phase == .cleared),allowsAudio,model.musicEnabled,
              let cue=resolvedMusicCue else{stopMusic();return}
        if player?.cue==cue && (player?.isPlaying==true || !cue.repeats){return}
        stopMusic()
        do {player=try BattleMusicPlayer(directory:BattleEngineProcess.resourceDirectory,volume:audioSettings.volume,cue:cue);try player?.play()}
        catch {AppLog.write("challenge BGM unavailable: \(error)")}
    }
    private func stopMusic(){player?.stop();player=nil}
}

@MainActor struct BattleTabView:View {
    let store:CompanionStore
    let battle:BattleCoordinator
    let tradeActive:Bool
    @State private var failed=false
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            BattleLobbyView(store:store,battle:battle,tradeActive:tradeActive).disabled(ChallengeActivity.shared.isOpen)
            Divider()
            Button {
                do {try ChallengeWindowController.open(store:store,identity:battle.identity)}
                catch {AppLog.write("challenge launch failed: \(error)");failed=true}
            } label:{Label(store.l.challengeEntry,systemImage:"flag.checkered")}
                .buttonStyle(.borderedProminent).disabled(tradeActive || battle.isActive || ![.idle,.ended].contains(battle.phase))
                .accessibilityIdentifier("challenge-open")
            Text(store.l.challengeRules).font(.caption).foregroundStyle(.secondary)
        }.alert(store.l.challengeProblem,isPresented:$failed){Button(store.l.quit,role:.cancel){}}
    }
}
