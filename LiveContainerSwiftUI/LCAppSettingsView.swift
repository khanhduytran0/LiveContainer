//
//  LCAppSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/9/16.
//

import Foundation
import SwiftUI

protocol LCAppSettingDelegate {
    func forceResign() async
    func toggleHidden() async
}

class LCAppModel: ObservableObject {
    @Published var appInfo : LCAppInfo
    
    @Published var isAppRunning = false
    
    @Published var uiIsJITNeeded : Bool
    @Published var uiIsHidden : Bool
    @Published var uiIsShared : Bool
    @Published var uiDataFolder : String?
    @Published var uiTweakFolder : String?
    @Published var uiDoSymlinkInbox : Bool
    @Published var uiBypassAssertBarrierOnQueue : Bool
    
    init(appInfo : LCAppInfo) {
        self.appInfo = appInfo
        
        self.uiIsJITNeeded = appInfo.isJITNeeded
        self.uiIsHidden = appInfo.isHidden
        self.uiIsShared = appInfo.isShared
        self.uiDataFolder = appInfo.getDataUUIDNoAssign()
        self.uiTweakFolder = appInfo.tweakFolder()
        self.uiDoSymlinkInbox = appInfo.doSymlinkInbox
        self.uiBypassAssertBarrierOnQueue = appInfo.bypassAssertBarrierOnQueue
    }
}


struct LCAppSettingsView : View{
    
    private var appInfo : LCAppInfo
    
    @ObservedObject private var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    

    @State private var uiPickerDataFolder : String?
    @State private var uiPickerTweakFolder : String?
    
    @State private var renameFolderShow = false
    @State private var renameFolderContent = ""
    @State private var renameFolerContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var confirmMoveToAppGroupShow = false
    @State private var confirmMoveToAppGroup = false
    @State private var confirmMoveToAppGroupContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var confirmMoveToPrivateDocShow = false
    @State private var confirmMoveToPrivateDoc = false
    @State private var confirmMoveToPrivateDocContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    private let delegate : LCAppSettingDelegate
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(model: LCAppModel, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>, delegate: LCAppSettingDelegate) {
        self.appInfo = model.appInfo
        self._model = ObservedObject(wrappedValue: model)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self.delegate = delegate
        self._uiPickerDataFolder = State(initialValue: model.uiDataFolder)
        self._uiPickerTweakFolder = State(initialValue: model.uiTweakFolder)
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Bundle Identifier")
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
                            Label("New data folder", systemImage: "plus")
                        }
                        if model.uiDataFolder != nil {
                            Button {
                                Task{ await renameDataFolder() }
                            } label: {
                                Label("Rename data folder", systemImage: "pencil")
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
                            Text("Data Folder")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(model.uiDataFolder == nil ? "Not created yet" : model.uiDataFolder!)
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
                            Label("None", systemImage: "nosign").tag(Optional<String>(nil))
                            ForEach(tweakFolders, id:\.self) { folderName in
                                Text(folderName).tag(Optional(folderName))
                            }
                        }
                    } label: {
                        HStack {
                            Text("Tweak Folder")
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
                        Text("Data Folder")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiDataFolder == nil ? "Data folder not created yet" : model.uiDataFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Tweak Folder")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiTweakFolder == nil ? "None" : model.uiTweakFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if !model.uiIsShared {
                    Button("Convert to Shared App") {
                        Task { await moveToAppGroup()}
                    }
                    
                } else if LCUtils.multiLCStatus != 2 {
                    Button("Convert to Private App") {
                        Task { await movePrivateDoc() }
                    }
                }
            } header: {
                Text("Data")
            }
            
            
            Section {
                Toggle(isOn: $model.uiIsJITNeeded) {
                    Text("Launch with JIT")
                }
                .onChange(of: model.uiIsJITNeeded, perform: { newValue in
                    Task { await setJITNeeded(newValue) }
                })
            } footer: {
                Text("LiveContainer will try to acquire JIT permission before launching the app.")
            }
            
            if sharedModel.isHiddenAppUnlocked {
                Section {
                    Toggle(isOn: $model.uiIsHidden) {
                        Text("Hide App")
                    }
                    .onChange(of: model.uiIsHidden, perform: { newValue in
                        Task { await toggleHidden() }
                    })
                } footer: {
                    Text("To completely hide apps, enable Strict Hiding mode in settings.")
                }

            }
            
            Section {
                Toggle(isOn: $model.uiDoSymlinkInbox) {
                    Text("Fix File Picker")
                }
                .onChange(of: model.uiDoSymlinkInbox, perform: { newValue in
                    Task { await setSimlinkInbox(newValue) }
                })
            } header: {
                Text("Fixes")
            } footer: {
                Text("Fix file picker not responding when hitting 'open' by forcing this app to copy selected files to its inbox. You may view imported files in the 'Inbox' folder in app's data folder.")
            }
            
            Section {
                Toggle(isOn: $model.uiBypassAssertBarrierOnQueue) {
                    Text("Bypass AssertBarrierOnQueue")
                }
                .onChange(of: model.uiBypassAssertBarrierOnQueue, perform: { newValue in
                    Task { await setBypassAssertBarrierOnQueue(newValue) }
                })
            
            } footer: {
                Text("Might prevent some games from crashing, but may cause them to be unstable.")
            }
            
            
            Section {
                Button("Force Sign") {
                    Task { await forceResign() }
                }
                .disabled(model.isAppRunning)
            } footer: {
                Text("Try to sign again if this app failed to launch with error like 'Invalid Signature'. It this still don't work, renew JIT-Less certificate.")
            }

        }
        .navigationTitle(appInfo.displayName())
        
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
        }
        
        .textFieldAlert(
            isPresented: $renameFolderShow,
            title: "Enter the name of new folder",
            text: $renameFolderContent,
            placeholder: "",
            action: { newText in
                self.renameFolderContent = newText!
                renameFolerContinuation?.resume()
            },
            actionCancel: {_ in
                self.renameFolderContent = ""
                renameFolerContinuation?.resume()
            }
        )
        .alert("Move to App Group", isPresented: $confirmMoveToAppGroupShow) {
            Button {
                self.confirmMoveToAppGroup = true
                self.confirmMoveToAppGroupContinuation?.resume()
            } label: {
                Text("Move")
            }
            Button("Cancel", role: .cancel) {
                self.confirmMoveToAppGroup = false
                self.confirmMoveToAppGroupContinuation?.resume()
            }
        } message: {
            Text("Moving this app to App Group allows other LiveContainers to run this app with all its data and tweak preserved. If you want to access its data and tweak again from the file app, move it back.")
        }
        .alert("Move to Private Document Folder", isPresented: $confirmMoveToPrivateDocShow) {
            Button {
                self.confirmMoveToPrivateDoc = true
                self.confirmMoveToPrivateDocContinuation?.resume()
            } label: {
                Text("Move")
            }
            Button("Cancel", role: .cancel) {
                self.confirmMoveToPrivateDoc = false
                self.confirmMoveToPrivateDocContinuation?.resume()
            }
        } message: {
            Text("Moving this app to Private Document Folder allows you to access its data and tweaks in the Files app, but it can not be run by other LiveContainers.")
        }
    }
    
    func setDataFolder(folderName: String?) {
        self.appInfo.setDataUUID(folderName!)
        self.model.uiDataFolder = folderName
        self.uiPickerDataFolder = folderName
    }
    
    func createFolder() async {
        
        self.renameFolderContent = NSUUID().uuidString
        
        await withCheckedContinuation { c in
            self.renameFolerContinuation = c
            self.renameFolderShow = true
        }
        
        if self.renameFolderContent == "" {
            return
        }
        let fm = FileManager()
        let dest = LCPath.dataPath.appendingPathComponent(self.renameFolderContent)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        self.appDataFolders.append(self.renameFolderContent)
        self.setDataFolder(folderName: self.renameFolderContent)
        
    }
    
    func renameDataFolder() async {
        if self.appInfo.getDataUUIDNoAssign() == nil {
            return
        }
        
        self.renameFolderContent = self.model.uiDataFolder == nil ? "" : self.model.uiDataFolder!
        await withCheckedContinuation { c in
            self.renameFolerContinuation = c
            self.renameFolderShow = true
        }
        if self.renameFolderContent == "" {
            return
        }
        let fm = FileManager()
        let orig = LCPath.dataPath.appendingPathComponent(appInfo.getDataUUIDNoAssign())
        let dest = LCPath.dataPath.appendingPathComponent(self.renameFolderContent)
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
        
        self.appDataFolders[i] = self.renameFolderContent
        self.setDataFolder(folderName: self.renameFolderContent)
        
    }
    
    func setTweakFolder(folderName: String?) {
        self.appInfo.setTweakFolder(folderName)
        self.model.uiTweakFolder = folderName
        self.uiPickerTweakFolder = folderName
    }
    
    func moveToAppGroup() async {
        await withCheckedContinuation { c in
            confirmMoveToAppGroupContinuation = c
            confirmMoveToAppGroupShow = true
        }
        if !confirmMoveToAppGroup {
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
            errorInfo = "Data of this app is currently in \(runningLC!). Open \(runningLC!) and launch it to 'My Apps' screen and try again."
            errorShow = true
            return
        }
        
        await withCheckedContinuation { c in
            confirmMoveToPrivateDocContinuation = c
            confirmMoveToPrivateDocShow = true
        }
        if !confirmMoveToPrivateDoc {
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
        await delegate.toggleHidden()
    }
    
    func forceResign() async {
        await delegate.forceResign()
    }
}
