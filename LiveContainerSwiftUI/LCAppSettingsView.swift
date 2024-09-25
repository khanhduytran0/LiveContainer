//
//  LCAppSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/9/16.
//

import Foundation
import SwiftUI

struct LCAppSettingsView : View{
    
    private var appInfo : LCAppInfo
    
    @ObservedObject private var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    

    @State private var uiPickerDataFolder : String?
    @State private var uiPickerTweakFolder : String?
    
    @StateObject private var renameFolderInput = InputHelper()
    @StateObject private var moveToAppGroupAlert = YesNoHelper()
    @StateObject private var moveToPrivateDocAlert = YesNoHelper()
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(model: LCAppModel, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        self.appInfo = model.appInfo
        self._model = ObservedObject(wrappedValue: model)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self._uiPickerDataFolder = State(initialValue: model.uiDataFolder)
        self._uiPickerTweakFolder = State(initialValue: model.uiTweakFolder)
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("lc.appSettings.bundleId".loc)
                    Spacer()
                    Text(appInfo.relativeBundlePath)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                }
                if !model.uiIsShared {
                    Menu {
                        Button {
                            Task{ await createFolder() }
                        } label: {
                            Label("lc.appSettings.newDataFolder".loc, systemImage: "plus")
                        }
                        if model.uiDataFolder != nil {
                            Button {
                                Task{ await renameDataFolder() }
                            } label: {
                                Label("lc.appSettings.renameDataFolder".loc, systemImage: "pencil")
                            }
                        }

                        Picker(selection: $uiPickerDataFolder , label: Text("")) {
                            ForEach(appDataFolders, id:\.self) { folderName in
                                Button(folderName) {
                                    setDataFolder(folderName: folderName)
                                }.tag(Optional(folderName))
                            }
                        }
                    } label: {
                        HStack {
                            Text("lc.appSettings.dataFolder".loc)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(model.uiDataFolder == nil ? "lc.appSettings.noDataFolder".loc : model.uiDataFolder!)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .onChange(of: uiPickerDataFolder, perform: { newValue in
                        if newValue != model.uiDataFolder {
                            setDataFolder(folderName: newValue)
                        }
                    })
                    
                    Menu {
                        Picker(selection: $uiPickerTweakFolder , label: Text("")) {
                            Label("lc.common.none".loc, systemImage: "nosign").tag(Optional<String>(nil))
                            ForEach(tweakFolders, id:\.self) { folderName in
                                Text(folderName).tag(Optional(folderName))
                            }
                        }
                    } label: {
                        HStack {
                            Text("lc.appSettings.tweakFolder".loc)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(model.uiTweakFolder == nil ? "None" : model.uiTweakFolder!)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .onChange(of: uiPickerTweakFolder, perform: { newValue in
                        if newValue != model.uiTweakFolder {
                            setTweakFolder(folderName: newValue)
                        }
                    })
                    
                    
                } else {
                    HStack {
                        Text("lc.appSettings.dataFolder".loc)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiDataFolder == nil ? "lc.appSettings.noDataFolder".loc : model.uiDataFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("lc.appSettings.tweakFolder".loc)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiTweakFolder == nil ? "lc.common.none".loc : model.uiTweakFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if !model.uiIsShared {
                    Button("lc.appSettings.toSharedApp".loc) {
                        Task { await moveToAppGroup()}
                    }
                    
                } else if sharedModel.multiLCStatus != 2 {
                    Button("lc.appSettings.toPrivateApp".loc) {
                        Task { await movePrivateDoc() }
                    }
                }
            } header: {
                Text("lc.common.data".loc)
            }
            
            
            Section {
                Toggle(isOn: $model.uiIsJITNeeded) {
                    Text("lc.appSettings.launchWithJit".loc)
                }
                .onChange(of: model.uiIsJITNeeded, perform: { newValue in
                    Task { await setJITNeeded(newValue) }
                })
            } footer: {
                Text("lc.appSettings.launchWithJitDesc".loc)
            }

            Section {
                Toggle(isOn: $model.uiIsLocked) {
                    Text("lc.appSettings.lockApp".loc)
                }
                .onChange(of: model.uiIsLocked, perform: { newValue in
                    Task {
                        if !newValue {
                            do {
                                let result = try await LCUtils.authenticateUser()
                                if !result {
                                    model.uiIsLocked = true
                                    return
                                }
                            } catch {
                                return
                            }
                        }

                        await model.toggleLock()
                    }
                })

                if model.uiIsLocked {
                    Toggle(isOn: $model.uiIsHidden) {
                        Text("lc.appSettings.hideApp".loc)
                    }
                    .onChange(of: model.uiIsHidden, perform: { _ in
                        Task { await toggleHidden() }
                    })
                    .transition(.opacity.combined(with: .slide)) 
                }
            } footer: {
                if model.uiIsLocked {
                    Text("lc.appSettings.hideAppDesc".loc)
                        .transition(.opacity.combined(with: .slide))
                }
            }

            
            Section {
                Toggle(isOn: $model.uiDoSymlinkInbox) {
                    Text("lc.appSettings.fixFilePicker".loc)
                }
                .onChange(of: model.uiDoSymlinkInbox, perform: { newValue in
                    Task { await setSimlinkInbox(newValue) }
                })
            } header: {
                Text("lc.appSettings.fixes".loc)
            } footer: {
                Text("lc.appSettings.fixFilePickerDesc".loc)
            }
            
            Section {
                Toggle(isOn: $model.uiBypassAssertBarrierOnQueue) {
                    Text("lc.appSettings.bypassAssert".loc)
                }
                .onChange(of: model.uiBypassAssertBarrierOnQueue, perform: { newValue in
                    Task { await setBypassAssertBarrierOnQueue(newValue) }
                })
            
            } footer: {
                Text("lc.appSettings.bypassAssertDesc".loc)
            }
            
            
            Section {
                Button("lc.appSettings.forceSign".loc) {
                    Task { await forceResign() }
                }
                .disabled(model.isAppRunning)
            } footer: {
                Text("lc.appSettings.forceSignDesc".loc)
            }

        }
        .navigationTitle(appInfo.displayName())
        
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        
        .textFieldAlert(
            isPresented: $renameFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $renameFolderInput.initVal,
            placeholder: "",
            action: { newText in
                renameFolderInput.close(result: newText!)
            },
            actionCancel: {_ in
                renameFolderInput.close(result: "")
            }
        )
        .alert("lc.appSettings.toSharedApp".loc, isPresented: $moveToAppGroupAlert.show) {
            Button {
                self.moveToAppGroupAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToAppGroupAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toSharedAppDesc".loc)
        }
        .alert("lc.appSettings.toPrivateApp".loc, isPresented: $moveToPrivateDocAlert.show) {
            Button {
                self.moveToPrivateDocAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToPrivateDocAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toPrivateAppDesc".loc)
        }
    }
    
    func setDataFolder(folderName: String?) {
        self.appInfo.setDataUUID(folderName!)
        self.model.uiDataFolder = folderName
        self.uiPickerDataFolder = folderName
    }
    
    func createFolder() async {
        guard let newName = await renameFolderInput.open(initVal: NSUUID().uuidString), newName != "" else {
            return
        }
        let fm = FileManager()
        let dest = LCPath.dataPath.appendingPathComponent(newName)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        self.appDataFolders.append(newName)
        self.setDataFolder(folderName: newName)
        
    }
    
    func renameDataFolder() async {
        if self.appInfo.getDataUUIDNoAssign() == nil {
            return
        }
        
        let initVal = self.model.uiDataFolder == nil ? "" : self.model.uiDataFolder!
        guard let newName = await renameFolderInput.open(initVal: initVal), newName != "" else {
            return
        }
        let fm = FileManager()
        let orig = LCPath.dataPath.appendingPathComponent(appInfo.getDataUUIDNoAssign())
        let dest = LCPath.dataPath.appendingPathComponent(newName)
        do {
            try fm.moveItem(at: orig, to: dest)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        let i = self.appDataFolders.firstIndex(of: self.appInfo.getDataUUIDNoAssign())
        guard let i = i else {
            return
        }
        
        self.appDataFolders[i] = newName
        self.setDataFolder(folderName: newName)
        
    }
    
    func setTweakFolder(folderName: String?) {
        self.appInfo.setTweakFolder(folderName)
        self.model.uiTweakFolder = folderName
        self.uiPickerTweakFolder = folderName
    }
    
    func moveToAppGroup() async {
        guard let result = await moveToAppGroupAlert.open(), result else {
            return
        }
        
        do {
            try LCPath.ensureAppGroupPaths()
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            if let dataFolder = appInfo.getDataUUIDNoAssign(), dataFolder.count > 0 {
                try fm.moveItem(at: LCPath.dataPath.appendingPathComponent(dataFolder),
                                to: LCPath.lcGroupDataPath.appendingPathComponent(dataFolder))
                appDataFolders.removeAll(where: { s in
                    return s == dataFolder
                })
            }
            if let tweakFolder = appInfo.tweakFolder(), tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.tweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.removeAll(where: { s in
                    return s == tweakFolder
                })
            }
            appInfo.setBundlePath(LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = true
            model.uiIsShared = true
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func movePrivateDoc() async {
        let runningLC = LCUtils.getAppRunningLCScheme(bundleId: appInfo.relativeBundlePath!)
        if runningLC != nil {
            errorInfo = "lc.appSettings.appOpenInOtherLc %@ %@".localizeWithFormat(runningLC!, runningLC!)
            errorShow = true
            return
        }
        
        guard let result = await moveToPrivateDocAlert.open(), result else {
            return
        }
        
        do {
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            if let dataFolder = appInfo.getDataUUIDNoAssign(), dataFolder.count > 0 {
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(dataFolder),
                                to: LCPath.dataPath.appendingPathComponent(dataFolder))
                appDataFolders.append(dataFolder)
                model.uiDataFolder = dataFolder
            }
            if let tweakFolder = appInfo.tweakFolder(), tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.tweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.append(tweakFolder)
                model.uiTweakFolder = tweakFolder
            }
            appInfo.setBundlePath(LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = false
            model.uiIsShared = false
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
        }
        
    }
    
    func setJITNeeded(_ JITNeeded: Bool) async {
        appInfo.isJITNeeded = JITNeeded
        model.uiIsJITNeeded = JITNeeded

    }
    
    func setSimlinkInbox(_ simlinkInbox : Bool) async {
        appInfo.doSymlinkInbox = simlinkInbox
        model.uiDoSymlinkInbox = simlinkInbox

    }
    
    func setBypassAssertBarrierOnQueue(_ enabled : Bool) async {
            appInfo.bypassAssertBarrierOnQueue = enabled
            model.uiBypassAssertBarrierOnQueue = enabled
    }
    func toggleHidden() async {
        await model.toggleHidden()
    }
    
    func forceResign() async {
        do {
            try await model.forceResign()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}
