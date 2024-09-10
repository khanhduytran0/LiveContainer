//
//  LCSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCSettingsView: View {
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    @Binding var apps: [LCAppInfo]
    @Binding var appDataFolderNames: [String]
    
    @State private var confirmAppFolderRemovalShow = false
    @State private var confirmAppFolderRemoval = false
    @State private var appFolderRemovalContinuation : CheckedContinuation<Void, Never>? = nil
    @State private var folderRemoveCount = 0
    
    @State private var confirmKeyChainRemovalShow = false
    @State private var confirmKeyChainRemoval = false
    @State private var confirmKeyChainContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State var isJitLessEnabled = false
    
    @State var isAltCertIgnored = false
    @State var frameShortIcon = false
    @State var silentSwitchApp = false
    @State var injectToLCItelf = false
    
    @State var sideJITServerAddress : String
    @State var deviceUDID: String
    
    init(apps: Binding<[LCAppInfo]>, appDataFolderNames: Binding<[String]>) {
        _isJitLessEnabled = State(initialValue: LCUtils.certificatePassword() != nil)
        _isAltCertIgnored = State(initialValue: UserDefaults.standard.bool(forKey: "LCIgnoreALTCertificate"))
        _frameShortIcon = State(initialValue: UserDefaults.standard.bool(forKey: "LCFrameShortcutIcons"))
        _silentSwitchApp = State(initialValue: UserDefaults.standard.bool(forKey: "LCSwitchAppWithoutAsking"))
        _injectToLCItelf = State(initialValue: UserDefaults.standard.bool(forKey: "LCLoadTweaksToSelf"))
        
        _apps = apps
        _appDataFolderNames = appDataFolderNames
        
        if let configSideJITServerAddress = LCUtils.appGroupUserDefault.string(forKey: "LCSideJITServerAddress") {
            _sideJITServerAddress = State(initialValue: configSideJITServerAddress)
        } else {
            _sideJITServerAddress = State(initialValue: "")
        }
        
        if let configDeviceUDID = LCUtils.appGroupUserDefault.string(forKey: "LCDeviceUDID") {
            _deviceUDID = State(initialValue: configDeviceUDID)
        } else {
            _deviceUDID = State(initialValue: "")
        }

    }
    
    var body: some View {
        NavigationView {
            Form {
                if LCUtils.multiLCStatus != 2 {
                    Section{
                        Button {
                            setupJitLess()
                        } label: {
                            if isJitLessEnabled {
                                Text("Renew JIT-less certificate")
                            } else {
                                Text("Setup JIT-less certificate")
                            }
                        }
                    } header: {
                        Text("JIT-Less")
                    } footer: {
                        Text("JIT-less allows you to use LiveContainer without having to enable JIT. Requires AltStore or SideStore.")
                    }
                }

                Section{
                    Button {
                        installAnotherLC()
                    } label: {
                        if LCUtils.multiLCStatus == 0 {
                            Text("Install another LiveContainer")
                        } else if LCUtils.multiLCStatus == 1 {
                            Text("Reinstall another LiveContainer")
                        } else if LCUtils.multiLCStatus == 2 {
                            Text("This is the second LiveContainer")
                        }

                    }
                    .disabled(LCUtils.multiLCStatus == 2)
                } header: {
                    Text("Multiple LiveContainers")
                } footer: {
                    Text("By installing multiple LiveContainers, and converting apps to Shared Apps, you can open one app between all LiveContainers with most of its data and settings.")
                }
                
                
                Section {
                    Toggle(isOn: $isAltCertIgnored) {
                        Text("Ignore ALTCertificate.p12")
                    }
                } footer: {
                    Text("If you see frequent re-sign, enable this option.")
                }
                
//                Section{
//                    Toggle(isOn: $frameShortIcon) {
//                        Text("Frame Short Icon")
//                    }
//                } header: {
//                    Text("Miscellaneous")
//                } footer: {
//                    Text("Frame shortcut icons with LiveContainer icon.")
//                }
                Section {
                    HStack {
                        Text("Address")
                        Spacer()
                        TextField("http://x.x.x.x:8080", text: $sideJITServerAddress)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("UDID")
                        Spacer()
                        TextField("", text: $deviceUDID)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("JIT")
                } footer: {
                    Text("Set up your SideJITServer/JITStreamer server. Local Network permission is required.")
                }
                
                Section {
                    Toggle(isOn: $silentSwitchApp) {
                        Text("Switch App Without Asking")
                    }
                } footer: {
                    Text("By default, LiveContainer asks you before switching app. Enable this to switch app immediately. Any unsaved data will be lost.")
                }
                
                Section {
                    Toggle(isOn: $injectToLCItelf) {
                        Text("Load Tweaks to LiveContainer Itself")
                    }
                } footer: {
                    Text("Place your tweaks into the global “Tweaks” folder and LiveContainer will pick them up.")
                }
                
                Section {
                    Button {
                        Task { await moveDanglingFolders() }
                    } label: {
                        Text("Move Dangling Folders Out of App Group")
                    }
                    Button(role:.destructive) {
                        Task { await cleanUpUnusedFolders() }
                    } label: {
                        Text("Clean Unused Data Folders")
                    }
                    Button(role:.destructive) {
                        Task { await removeKeyChain() }
                    } label: {
                        Text("Clean Up Keychain")
                    }
                }
                
                VStack{
                    Text(LCUtils.getVersionInfo())
                        .foregroundStyle(.gray)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(UIColor.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
            }
            .navigationBarTitle("Settings")
            .alert(isPresented: $errorShow){
                Alert(title: Text("Error"), message: Text(errorInfo))
            }
            .alert(isPresented: $successShow){
                Alert(title: Text("Success"), message: Text(successInfo))
            }
            .alert("Data Folder Clean Up", isPresented: $confirmAppFolderRemovalShow) {
                if folderRemoveCount > 0 {
                    Button(role: .destructive) {
                        self.confirmAppFolderRemoval = true
                        self.appFolderRemovalContinuation?.resume()
                    } label: {
                        Text("Delete")
                    }
                }

                Button("Cancel", role: .cancel) {
                    self.confirmAppFolderRemoval = false
                    self.appFolderRemovalContinuation?.resume()
                }
            } message: {
                if folderRemoveCount > 0 {
                    Text("Do you want to delete \(folderRemoveCount) unused data folder(s)?")
                } else {
                    Text("No data folder to remove. All data folders are in use.")
                }

            }
            .alert("Keychain Clean Up", isPresented: $confirmKeyChainRemovalShow) {
                Button(role: .destructive) {
                    self.confirmKeyChainRemoval = true
                    self.confirmKeyChainContinuation?.resume()
                } label: {
                    Text("Delete")
                }

                Button("Cancel", role: .cancel) {
                    self.confirmKeyChainRemoval = false
                    self.confirmKeyChainContinuation?.resume()
                }
            } message: {
                Text("If some app's account can not be synced between LiveContainers, it's may because it is still stored in current LiveContainer's private keychain. Cleaning up keychain may solve this issue, but it may sign you out of some of your accounts. Continue?")
            }
            .onChange(of: isAltCertIgnored) { newValue in
                saveItem(key: "LCIgnoreALTCertificate", val: newValue)
            }
            .onChange(of: silentSwitchApp) { newValue in
                saveItem(key: "LCSwitchAppWithoutAsking", val: newValue)
            }
            .onChange(of: frameShortIcon) { newValue in
                saveItem(key: "LCFrameShortcutIcons", val: newValue)
            }
            .onChange(of: injectToLCItelf) { newValue in
                saveItem(key: "LCLoadTweaksToSelf", val: newValue)
            }
            .onChange(of: deviceUDID) { newValue in
                saveAppGroupItem(key: "LCDeviceUDID", val: newValue)
            }
            .onChange(of: sideJITServerAddress) { newValue in
                saveAppGroupItem(key: "LCSideJITServerAddress", val: newValue)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        
    }
    
    func saveItem(key: String, val: Any) {
        UserDefaults.standard.setValue(val, forKey: key)
    }
    
    func saveAppGroupItem(key: String, val: Any) {
        LCUtils.appGroupUserDefault.setValue(val, forKey: key)
    }
    
    func setupJitLess() {
        if !LCUtils.isAppGroupAltStoreLike() {
            errorInfo = "Unsupported installation method. Please use AltStore or SideStore to setup this feature."
            errorShow = true
            return;
        }
        do {
            let packedIpaUrl = try LCUtils.archiveIPA(withSetupMode: true)
            let storeInstallUrl = String(format: LCUtils.storeInstallURLScheme(), packedIpaUrl.absoluteString)
            UIApplication.shared.open(URL(string: storeInstallUrl)!)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    
    }
    
    func installAnotherLC() {
        if !LCUtils.isAppGroupAltStoreLike() {
            errorInfo = "Unsupported installation method. Please use AltStore or SideStore to setup this feature."
            errorShow = true
            return;
        }
        let password = LCUtils.certificatePassword()
        let lcDomain = UserDefaults.init(suiteName: LCUtils.appGroupID())
        lcDomain?.setValue(password, forKey: "LCCertificatePassword")
        
        
        do {
            let packedIpaUrl = try LCUtils.archiveIPA(withBundleName: "LiveContainer2")
            let storeInstallUrl = String(format: LCUtils.storeInstallURLScheme(), packedIpaUrl.absoluteString)
            UIApplication.shared.open(URL(string: storeInstallUrl)!)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func cleanUpUnusedFolders() async {
        
        var folderNameToAppDict : [String:LCAppInfo] = [:]
        for app in apps {
            guard let folderName = app.getDataUUIDNoAssign() else {
                continue
            }
            folderNameToAppDict[folderName] = app
        }
        
        var foldersToDelete : [String]  = []
        for appDataFolderName in appDataFolderNames {
            if folderNameToAppDict[appDataFolderName] == nil {
                foldersToDelete.append(appDataFolderName)
            }
        }
        folderRemoveCount = foldersToDelete.count
        await withCheckedContinuation { c in
            self.appFolderRemovalContinuation = c
            DispatchQueue.main.async {
                confirmAppFolderRemovalShow = true
            }
        }
        if !confirmAppFolderRemoval {
            return
        }
        do {
            let fm = FileManager()
            for folder in foldersToDelete {
                try fm.removeItem(at: LCPath.dataPath.appendingPathComponent(folder))
                self.appDataFolderNames.removeAll(where: { s in
                    return s == folder
                })
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func removeKeyChain() async {
        await withCheckedContinuation { c in
            self.confirmKeyChainContinuation = c
            DispatchQueue.main.async {
                confirmKeyChainRemovalShow = true
            }
        }
        if !confirmKeyChainRemoval {
            return
        }
        
        [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity].forEach {
          let status = SecItemDelete([
            kSecClass: $0,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
          ] as CFDictionary)
          if status != errSecSuccess && status != errSecItemNotFound {
              //Error while removing class $0
              errorInfo = status.description
              errorShow = true
          }
        }
    }
    
    func moveDanglingFolders() async {
        let fm = FileManager()
        do {
            var appDataFoldersInUse : Set<String> = Set();
            var tweakFoldersInUse : Set<String> = Set();
            for app in apps {
                if !app.isShared {
                    continue
                }
                if let folder = app.getDataUUIDNoAssign() {
                    appDataFoldersInUse.update(with: folder);
                }
                if let folder = app.tweakFolder() {
                    tweakFoldersInUse.update(with: folder);
                }

            }
            
            var movedDataFolderCount = 0
            let sharedDataFolders = try fm.contentsOfDirectory(atPath: LCPath.lcGroupDataPath.path)
            for sharedDataFolder in sharedDataFolders {
                if appDataFoldersInUse.contains(sharedDataFolder) {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(sharedDataFolder), to: LCPath.dataPath.appendingPathComponent(sharedDataFolder))
                movedDataFolderCount += 1
            }
            
            var movedTweakFolderCount = 0
            let sharedTweakFolders = try fm.contentsOfDirectory(atPath: LCPath.lcGroupTweakPath.path)
            for tweakFolderInUse in sharedTweakFolders {
                if tweakFoldersInUse.contains(tweakFolderInUse) || tweakFolderInUse == "TweakLoader.dylib" {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolderInUse), to: LCPath.tweakPath.appendingPathComponent(tweakFolderInUse))
                movedTweakFolderCount += 1
            }
            successInfo = "Moved \(movedDataFolderCount) data folder(s) and \(movedTweakFolderCount) tweak folders."
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

}
