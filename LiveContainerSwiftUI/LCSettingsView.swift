//
//  LCSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

enum PatchChoice {
    case cancel
    case autoPath
    case archiveOnly
}

enum JITEnablerType : Int {
    case SideJITServer = 0
    case JITStreamerEB = 1
}

struct LCSettingsView: View {
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    @Binding var appDataFolderNames: [String]
    
    @StateObject private var appFolderRemovalAlert = YesNoHelper()
    @State private var folderRemoveCount = 0
    
    @StateObject private var keyChainRemovalAlert = YesNoHelper()
    @StateObject private var patchAltStoreAlert = AlertHelper<PatchChoice>()
    @StateObject private var installLC2Alert = AlertHelper<PatchChoice>()
    @State private var isAltStorePatched = false
    
    @StateObject private var certificateImportAlert = YesNoHelper()
    @StateObject private var certificateRemoveAlert = YesNoHelper()
    @StateObject private var certificateImportFileAlert = AlertHelper<URL>()
    @StateObject private var certificateImportPasswordAlert = InputHelper()
    
    @State var isJitLessEnabled = false
    @State var defaultSigner = Signer.ZSign
    @State var isSignOnlyOnExpiration = true
    @State var frameShortIcon = false
    @State var silentSwitchApp = false
    @State var silentOpenWebPage = false
    @State var strictHiding = false
    @AppStorage("dynamicColors") var dynamicColors = true
    
    @State var sideJITServerAddress : String
    @State var deviceUDID: String
    @State var JITEnabler: JITEnablerType = .SideJITServer
    
    @State var isSideStore : Bool = true
    
    @State var injectToLCItelf = false
    @State var ignoreJITOnLaunch = false
    @State var doSaparateKeychainWhenCertImported = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    let storeName = LCUtils.getStoreName()
    
    init(appDataFolderNames: Binding<[String]>) {
        _isJitLessEnabled = State(initialValue: LCUtils.certificatePassword() != nil)
        
        if(LCUtils.appGroupUserDefault.object(forKey: "LCSignOnlyOnExpiration") == nil) {
            LCUtils.appGroupUserDefault.set(true, forKey: "LCSignOnlyOnExpiration")
        }
        
        _isSignOnlyOnExpiration = State(initialValue: LCUtils.appGroupUserDefault.bool(forKey: "LCSignOnlyOnExpiration"))
        _frameShortIcon = State(initialValue: UserDefaults.standard.bool(forKey: "LCFrameShortcutIcons"))
        _silentSwitchApp = State(initialValue: UserDefaults.standard.bool(forKey: "LCSwitchAppWithoutAsking"))
        _silentOpenWebPage = State(initialValue: UserDefaults.standard.bool(forKey: "LCOpenWebPageWithoutAsking"))
        _injectToLCItelf = State(initialValue: UserDefaults.standard.bool(forKey: "LCLoadTweaksToSelf"))
        _ignoreJITOnLaunch = State(initialValue: UserDefaults.standard.bool(forKey: "LCIgnoreJITOnLaunch"))
        _doSaparateKeychainWhenCertImported = State(initialValue: UserDefaults.standard.bool(forKey: "LCSaparateKeychainWhenCertImported"))
        
        _isSideStore = State(initialValue: LCUtils.store() == .SideStore)
        
        DataManager.shared.model.certificateImported = UserDefaults.standard.bool(forKey: "LCCertificateImported")
        if !DataManager.shared.model.certificateImported {
            // Only ZSign is available to ADP certs
            _defaultSigner = State(initialValue: Signer(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCDefaultSigner"))!)
        }
        
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
        _JITEnabler = State(initialValue: JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType"))!)
        
        _strictHiding = State(initialValue: LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding"))

    }
    
    var body: some View {
        NavigationView {
            Form {
                if sharedModel.multiLCStatus != 2 {
                    Section{
                        if !sharedModel.certificateImported {
                            Button {
                                Task { await patchAltStore() }
                            } label: {
                                if isAltStorePatched {
                                    Text("lc.settings.patchStoreAgain %@".localizeWithFormat(storeName))
                                } else {
                                    Text("lc.settings.patchStore %@".localizeWithFormat(storeName))
                                }
                            }
                            if !isAltStorePatched {
                                Button {
                                    Task{ await importCertificate() }
                                } label: {
                                    Text("lc.settings.importCertificate".loc)
                                }
                            }

                        } else {
                            Button {
                                Task{ await removeCertificate() }
                            } label: {
                                Text("lc.settings.removeCertificate".loc)
                            }
                        }
                        
                        NavigationLink {
                            LCJITLessDiagnoseView()
                        } label: {
                            Text("lc.settings.jitlessDiagnose".loc)
                        }
                        
                        if isAltStorePatched {
                            Toggle(isOn: $isSignOnlyOnExpiration) {
                                Text("lc.settings.signOnlyOnExpiration".loc)
                            }
                        }
                        
                        Picker(selection: $defaultSigner) {
                            if !sharedModel.certificateImported {
                                Text("AltSign").tag(Signer.AltSign)
                            }
                            Text("ZSign").tag(Signer.ZSign)
                        } label: {
                            Text("lc.settings.defaultSigner")
                        }

                    } header: {
                        Text("lc.settings.jitLess".loc)
                    } footer: {
                        Text("lc.settings.jitLessDesc".loc + "\n" + "lc.settings.signer.desc".loc)
                    }
                }

                Section{
                    Button {
                        Task { await installAnotherLC() }
                    } label: {
                        if sharedModel.multiLCStatus == 0 {
                            Text("lc.settings.multiLCInstall".loc)
                        } else if sharedModel.multiLCStatus == 1 {
                            Text("lc.settings.multiLCReinstall".loc)
                        } else if sharedModel.multiLCStatus == 2 {
                            Text("lc.settings.multiLCIsSecond".loc)
                        }

                    }
                    .disabled(sharedModel.multiLCStatus == 2)
                    
                    if(sharedModel.multiLCStatus == 2) {
                        NavigationLink {
                            LCJITLessDiagnoseView()
                        } label: {
                            Text("lc.settings.jitlessDiagnose".loc)
                        }
                    }
                } header: {
                    Text("lc.settings.multiLC".loc)
                } footer: {
                    Text("lc.settings.multiLCDesc".loc)
                }
                
                Section {
                    HStack {
                        Text("lc.settings.JitAddress".loc)
                        Spacer()
                        TextField(JITEnabler == .SideJITServer ? "http://x.x.x.x:8080" : "http://[fd00::]:9172", text: $sideJITServerAddress)
                            .multilineTextAlignment(.trailing)
                    }
                    if JITEnabler == .SideJITServer {
                        HStack {
                            Text("lc.settings.JitUDID".loc)
                            Spacer()
                            TextField("", text: $deviceUDID)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Picker(selection: $JITEnabler) {
                        Text("SideJITServer/JITStreamer 2.0").tag(JITEnablerType.SideJITServer)
                        Text("JitStreamer-EB").tag(JITEnablerType.JITStreamerEB)
                    } label: {
                        Text("lc.settings.jitEnabler".loc)
                    }

                } header: {
                    Text("JIT")
                } footer: {
                    Text("lc.settings.JitDesc".loc)
                }
                
                Section{
                    Toggle(isOn: $dynamicColors) {
                        Text("lc.settings.dynamicColors".loc)
                    }
                } header: {
                    Text("lc.settings.interface".loc)
                } footer: {
                    Text("lc.settings.dynamicColors.desc".loc)
                }
                Section{
                    Toggle(isOn: $frameShortIcon) {
                        Text("lc.settings.FrameIcon".loc)
                    }
                } header: {
                    Text("lc.common.miscellaneous".loc)
                } footer: {
                    Text("lc.settings.FrameIconDesc".loc)
                }
                
                Section {
                    Toggle(isOn: $silentSwitchApp) {
                        Text("lc.settings.silentSwitchApp".loc)
                    }
                } footer: {
                    Text("lc.settings.silentSwitchAppDesc".loc)
                }
                
                Section {
                    Toggle(isOn: $silentOpenWebPage) {
                        Text("lc.settings.silentOpenWebPage".loc)
                    }
                } footer: {
                    Text("lc.settings.silentOpenWebPageDesc".loc)
                }
                
                if sharedModel.isHiddenAppUnlocked {
                    Section {
                        Toggle(isOn: $strictHiding) {
                            Text("lc.settings.strictHiding".loc)
                        }
                    } footer: {
                        Text("lc.settings.strictHidingDesc".loc)
                    }
                }
                    
                Section {
                    if sharedModel.multiLCStatus != 2 {
                        Button {
                            moveAppGroupFolderFromPrivateToAppGroup()
                        } label: {
                            Text("lc.settings.appGroupPrivateToShare".loc)
                        }
                        Button {
                            moveAppGroupFolderFromAppGroupToPrivate()
                        } label: {
                            Text("lc.settings.appGroupShareToPrivate".loc)
                        }

                        Button {
                            Task { await moveDanglingFolders() }
                        } label: {
                            Text("lc.settings.moveDanglingFolderOut".loc)
                        }
                        Button(role:.destructive) {
                            Task { await cleanUpUnusedFolders() }
                        } label: {
                            Text("lc.settings.cleanDataFolder".loc)
                        }
                    }

                    Button(role:.destructive) {
                        Task { await removeKeyChain() }
                    } label: {
                        Text("lc.settings.cleanKeychain".loc)
                    }
                }
                
                if sharedModel.developerMode {
                    Section {
                        Toggle(isOn: $injectToLCItelf) {
                            Text("lc.settings.injectLCItself".loc)
                        }
                        Toggle(isOn: $ignoreJITOnLaunch) {
                            Text("Ignore JIT on Launching App")
                        }
                        Toggle(isOn: $doSaparateKeychainWhenCertImported) {
                            Text("Saparate Keychain When Cert is Imported")
                        }
                        Button {
                            export()
                        } label: {
                            Text("Export Cert")
                        }
                        Button {
                            exportMainExecutable()
                        } label: {
                            Text("Export Main Executable")
                        }
                    } header: {
                        Text("Developer Settings")
                    } footer: {
                        Text("lc.settings.injectLCItselfDesc".loc)
                    }
                }
                
                Section {
                    HStack {
                        Image("GitHub")
                        Button("khanhduytran0/LiveContainer") {
                            openGitHub()
                        }
                    }
                    HStack {
                        Image("GitHub")
                        Button("hugeBlack/LiveContainer") {
                            openGitHub2()
                        }
                    }
                    HStack {
                        Image("Twitter")
                        Button("@TranKha50277352") {
                            openTwitter()
                        }
                    }
                } header: {
                    Text("lc.settings.about".loc)
                } footer: {
                    Text("lc.settings.warning".loc)
                }
                
                VStack{
                    Text(LCUtils.getVersionInfo())
                        .foregroundStyle(.gray)
                        .onTapGesture(count: 10) {
                            sharedModel.developerMode = true
                        }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(UIColor.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
            }
            .navigationBarTitle("lc.tabView.settings".loc)
            .onAppear {
                updateSideStorePatchStatus()
            }
            .onForeground {
                updateSideStorePatchStatus()
                sharedModel.updateMultiLCStatus()
            }
            .alert("lc.common.error".loc, isPresented: $errorShow){
            } message: {
                Text(errorInfo)
            }
            .alert("lc.common.success".loc, isPresented: $successShow){
            } message: {
                Text(successInfo)
            }
            .alert("lc.settings.cleanDataFolder".loc, isPresented: $appFolderRemovalAlert.show) {
                if folderRemoveCount > 0 {
                    Button(role: .destructive) {
                        appFolderRemovalAlert.close(result: true)
                    } label: {
                        Text("lc.common.delete".loc)
                    }
                }

                Button("lc.common.cancel".loc, role: .cancel) {
                    appFolderRemovalAlert.close(result: false)
                }
            } message: {
                if folderRemoveCount > 0 {
                    Text("lc.settings.cleanDataFolderConfirm %lld".localizeWithFormat(folderRemoveCount))
                } else {
                    Text("lc.settings.noDataFolderToClean".loc)
                }

            }
            .alert("lc.settings.cleanKeychain".loc, isPresented: $keyChainRemovalAlert.show) {
                Button(role: .destructive) {
                    keyChainRemovalAlert.close(result: true)
                } label: {
                    Text("lc.common.delete".loc)
                }

                Button("lc.common.cancel".loc, role: .cancel) {
                    keyChainRemovalAlert.close(result: false)
                }
            } message: {
                Text("lc.settings.cleanKeychainDesc".loc)
            }
            .alert("lc.settings.patchStore %@".localizeWithFormat(LCUtils.getStoreName()), isPresented: $patchAltStoreAlert.show) {
                Button(role: .destructive) {
                    patchAltStoreAlert.close(result: .autoPath)
                } label: {
                    Text("lc.common.continue".loc)
                }
                if(isSideStore) {
                    Button {
                        patchAltStoreAlert.close(result: .archiveOnly)
                    } label: {
                        Text("lc.settings.patchStoreArchiveOnly".loc)
                    }
                }


                Button("lc.common.cancel".loc, role: .cancel) {
                    patchAltStoreAlert.close(result: .cancel)
                }
            } message: {
                if(isSideStore) {
                    Text("lc.settings.patchStoreDesc %@ %@ %@ %@".localizeWithFormat(storeName, storeName, storeName, storeName) + "\n\n" + "lc.settings.patchStoreMultipleHint".loc)
                } else {
                    Text("lc.settings.patchStoreDesc %@ %@ %@ %@".localizeWithFormat(storeName, storeName, storeName, storeName))
                }

            }
            .alert("lc.settings.multiLCInstall".loc, isPresented: $installLC2Alert.show) {
                Button {
                    installLC2Alert.close(result: .autoPath)
                } label: {
                    Text("lc.common.continue".loc)
                }
                if(isSideStore) {
                    Button {
                        installLC2Alert.close(result: .archiveOnly)
                    } label: {
                        Text("lc.settings.patchStoreArchiveOnly".loc)
                    }
                }
                Button("lc.common.cancel".loc, role: .cancel) {
                    patchAltStoreAlert.close(result: .cancel)
                }
            } message: {
                Text("lc.settings.multiLCInstallAlertDesc %@".localizeWithFormat(storeName))
            }
            .alert("lc.settings.importCertificate".loc, isPresented: $certificateImportAlert.show) {
                Button {
                    certificateImportAlert.close(result: true)
                } label: {
                    Text("lc.common.ok".loc)
                }

                Button("lc.common.cancel".loc, role: .cancel) {
                    certificateImportAlert.close(result: false)
                }
            } message: {
                Text("lc.settings.importCertificateDesc".loc)
            }
            .alert("lc.settings.removeCertificate".loc, isPresented: $certificateRemoveAlert.show) {
                Button(role: .destructive) {
                    certificateRemoveAlert.close(result: true)
                } label: {
                    Text("lc.common.ok".loc)
                }

                Button("lc.common.cancel".loc, role: .cancel) {
                    certificateRemoveAlert.close(result: false)
                }
            } message: {
                Text("lc.settings.removeCertificateDesc".loc)
            }
            .betterFileImporter(isPresented: $certificateImportFileAlert.show, types: [.p12], multiple: false, callback: { fileUrls in
                certificateImportFileAlert.close(result: fileUrls[0])
            }, onDismiss: {
                certificateImportFileAlert.close(result: nil)
            })
            .textFieldAlert(
                isPresented: $certificateImportPasswordAlert.show,
                title: "lc.settings.importCertificateInputPassword".loc,
                text: $certificateImportPasswordAlert.initVal,
                placeholder: "",
                action: { newText in
                    certificateImportPasswordAlert.close(result: newText)
                },
                actionCancel: {_ in
                    certificateImportPasswordAlert.close(result: nil)
                    certificateImportPasswordAlert.show = false
                }
            )
            
            .onChange(of: isSignOnlyOnExpiration) { newValue in
                saveAppGroupItem(key: "LCSignOnlyOnExpiration", val: newValue)
            }
            .onChange(of: silentSwitchApp) { newValue in
                saveItem(key: "LCSwitchAppWithoutAsking", val: newValue)
            }
            .onChange(of: silentOpenWebPage) { newValue in
                saveItem(key: "LCOpenWebPageWithoutAsking", val: newValue)
            }
            .onChange(of: frameShortIcon) { newValue in
                saveItem(key: "LCFrameShortcutIcons", val: newValue)
            }
            .onChange(of: injectToLCItelf) { newValue in
                saveItem(key: "LCLoadTweaksToSelf", val: newValue)
            }
            .onChange(of: ignoreJITOnLaunch) { newValue in
                saveItem(key: "LCIgnoreJITOnLaunch", val: newValue)
            }
            .onChange(of: doSaparateKeychainWhenCertImported) { newValue in
                saveItem(key: "LCSaparateKeychainWhenCertImported", val: newValue)
            }
            .onChange(of: strictHiding) { newValue in
                saveAppGroupItem(key: "LCStrictHiding", val: newValue)
            }
            .onChange(of: deviceUDID) { newValue in
                saveAppGroupItem(key: "LCDeviceUDID", val: newValue)
            }
            .onChange(of: sideJITServerAddress) { newValue in
                saveAppGroupItem(key: "LCSideJITServerAddress", val: newValue)
            }
            .onChange(of: JITEnabler) { newValue in
                saveAppGroupItem(key: "LCJITEnablerType", val: newValue.rawValue)
            }
            .onChange(of: defaultSigner) { newValue in
                saveAppGroupItem(key: "LCDefaultSigner", val: newValue.rawValue)
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
    
    func installAnotherLC() async {
        if !LCUtils.isAppGroupAltStoreLike() {
            errorInfo = "lc.settings.unsupportedInstallMethod".loc
            errorShow = true
            return;
        }
        
        guard let result = await installLC2Alert.open(), result != .cancel else {
            return
        }
        
        do {
            let packedIpaUrl = try LCUtils.archiveIPA(withBundleName: "LiveContainer2")
            if result == .archiveOnly {
                let movedAltStoreIpaUrl = LCPath.docPath.appendingPathComponent("LiveContainer2.ipa")
                try FileManager.default.moveItem(at: packedIpaUrl, to: movedAltStoreIpaUrl)
                successInfo = "lc.settings.multiLCArchiveSuccess".loc
                successShow = true
            } else {
                let storeInstallUrl = String(format: LCUtils.storeInstallURLScheme(), packedIpaUrl.absoluteString)
                await UIApplication.shared.open(URL(string: storeInstallUrl)!)
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func cleanUpUnusedFolders() async {
        
        var folderNameToAppDict : [String:LCAppModel] = [:]
        for app in sharedModel.apps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        for app in sharedModel.hiddenApps {
            for container in app.appInfo.containers {
                folderNameToAppDict[container.folderName] = app;
            }
        }
        
        var foldersToDelete : [String]  = []
        for appDataFolderName in appDataFolderNames {
            if folderNameToAppDict[appDataFolderName] == nil {
                foldersToDelete.append(appDataFolderName)
            }
        }
        folderRemoveCount = foldersToDelete.count
        
        guard let result = await appFolderRemovalAlert.open(), result else {
            return
        }
        do {
            let fm = FileManager()
            for folder in foldersToDelete {
                try fm.removeItem(at: LCPath.dataPath.appendingPathComponent(folder))
                LCUtils.removeAppKeychain(dataUUID: folder)
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
        guard let result = await keyChainRemovalAlert.open(), result else {
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
            for app in sharedModel.apps {
                if !app.appInfo.isShared {
                    continue
                }
                for container in app.appInfo.containers {
                    appDataFoldersInUse.update(with: container.folderName);
                }

                
                if let folder = app.appInfo.tweakFolder {
                    tweakFoldersInUse.update(with: folder);
                }

            }
            
            for app in sharedModel.hiddenApps {
                if !app.appInfo.isShared {
                    continue
                }
                for container in app.appInfo.containers {
                    appDataFoldersInUse.update(with: container.folderName);
                }
                if let folder = app.appInfo.tweakFolder {
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
            successInfo = "lc.settings.moveDanglingFolderComplete %lld %lld".localizeWithFormat(movedDataFolderCount,movedTweakFolderCount)
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func moveAppGroupFolderFromAppGroupToPrivate() {
        let fm = FileManager()
        do {
            if !fm.fileExists(atPath: LCPath.appGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.appGroupPath.path, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: LCPath.lcGroupAppGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.lcGroupAppGroupPath.path, withIntermediateDirectories: true)
            }
            
            let privateFolderContents = try fm.contentsOfDirectory(at: LCPath.appGroupPath, includingPropertiesForKeys: nil)
            let sharedFolderContents = try fm.contentsOfDirectory(at: LCPath.lcGroupAppGroupPath, includingPropertiesForKeys: nil)
            if privateFolderContents.count > 0 {
                errorInfo = "lc.settings.appGroupExistPrivate".loc
                errorShow = true
                return
            }
            for file in sharedFolderContents {
                try fm.moveItem(at: file, to: LCPath.appGroupPath.appendingPathComponent(file.lastPathComponent))
            }
            successInfo = "lc.settings.appGroup.moveSuccess".loc
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func moveAppGroupFolderFromPrivateToAppGroup() {
        let fm = FileManager()
        do {
            if !fm.fileExists(atPath: LCPath.appGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.appGroupPath.path, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: LCPath.lcGroupAppGroupPath.path) {
                try fm.createDirectory(atPath: LCPath.lcGroupAppGroupPath.path, withIntermediateDirectories: true)
            }
            
            let privateFolderContents = try fm.contentsOfDirectory(at: LCPath.appGroupPath, includingPropertiesForKeys: nil)
            let sharedFolderContents = try fm.contentsOfDirectory(at: LCPath.lcGroupAppGroupPath, includingPropertiesForKeys: nil)
            if sharedFolderContents.count > 0 {
                errorInfo = "lc.settings.appGroupExist Shared".loc
                errorShow = true
                return
            }
            for file in privateFolderContents {
                try fm.moveItem(at: file, to: LCPath.lcGroupAppGroupPath.appendingPathComponent(file.lastPathComponent))
            }
            successInfo = "lc.settings.appGroup.moveSuccess".loc
            successShow = true
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func openGitHub() {
        UIApplication.shared.open(URL(string: "https://github.com/khanhduytran0/LiveContainer")!)
    }
    
    func openGitHub2() {
        UIApplication.shared.open(URL(string: "https://github.com/hugeBlack/LiveContainer")!)
    }
    
    func openTwitter() {
        UIApplication.shared.open(URL(string: "https://twitter.com/TranKha50277352")!)
    }
    
    func updateSideStorePatchStatus() {
        let fm = FileManager()
        
        guard let appGroupPath = LCUtils.appGroupPath() else {
            isAltStorePatched = false
            return
        }
        var patchDylibPath : String;
        if (LCUtils.store() == .AltStore) {
            patchDylibPath = appGroupPath.appendingPathComponent("Apps/com.rileytestut.AltStore/App.app/Frameworks/AltStoreTweak.dylib").path
        } else {
            patchDylibPath = appGroupPath.appendingPathComponent("Apps/com.SideStore.SideStore/App.app/Frameworks/AltStoreTweak.dylib").path
        }
        
        if(fm.fileExists(atPath: patchDylibPath)) {
            isAltStorePatched = true
        } else {
            isAltStorePatched = false
        }
    }
    
    func patchAltStore() async {
        guard let result = await patchAltStoreAlert.open(), result != .cancel else {
            return
        }
        
        do {
            let altStoreIpa = try LCUtils.archiveTweakedAltStore()
            let storeInstallUrl = String(format: LCUtils.storeInstallURLScheme(), altStoreIpa.absoluteString)
            if(result == .archiveOnly) {
                let movedAltStoreIpaUrl = LCPath.docPath.appendingPathComponent("Patched\(isSideStore ? "SideStore" : "AltStore").ipa")
                try FileManager.default.moveItem(at: altStoreIpa, to: movedAltStoreIpaUrl)
                successInfo = "lc.settings.patchStoreArchiveSuccess %@ %@".localizeWithFormat(storeName, storeName)
                successShow = true
            } else {
                await UIApplication.shared.open(URL(string: storeInstallUrl)!)
            }
            

        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func export() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 1. Copy embedded.mobileprovision from the main bundle to Documents
        if let embeddedURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") {
            let destinationURL = documentsURL.appendingPathComponent("embedded.mobileprovision")
            do {
                try fileManager.copyItem(at: embeddedURL, to: destinationURL)
                print("Successfully copied embedded.mobileprovision to Documents.")
            } catch {
                print("Error copying embedded.mobileprovision: \(error)")
            }
        } else {
            print("embedded.mobileprovision not found in the main bundle.")
        }
        
        // 2. Read "certData" from UserDefaults and save to cert.p12 in Documents
        if let certData = LCUtils.certificateData() {
            let certFileURL = documentsURL.appendingPathComponent("cert.p12")
            do {
                try certData.write(to: certFileURL)
                print("Successfully wrote certData to cert.p12 in Documents.")
            } catch {
                print("Error writing certData to cert.p12: \(error)")
            }
        } else {
            print("certData not found in UserDefaults.")
        }
        
        // 3. Read "certPassword" from UserDefaults and save to pass.txt in Documents
        if let certPassword = LCUtils.certificatePassword() {
            let passwordFileURL = documentsURL.appendingPathComponent("pass.txt")
            do {
                try certPassword.write(to: passwordFileURL, atomically: true, encoding: .utf8)
                print("Successfully wrote certPassword to pass.txt in Documents.")
            } catch {
                print("Error writing certPassword to pass.txt: \(error)")
            }
        } else {
            print("certPassword not found in UserDefaults.")
        }
    }
    
    func exportMainExecutable() {
        let url = Bundle.main.executableURL!
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
            try fileManager.copyItem(at: url, to: destinationURL)
            print("Successfully copied main executable to Documents.")
        } catch {
            print("Error copying main executable \(error)")
        }
    }
    
    func importCertificate() async {
        guard let doImport = await certificateImportAlert.open(), doImport else {
            return
        }
        guard let certificateURL = await certificateImportFileAlert.open() else {
            return
        }
        guard let certificatePassword = await certificateImportPasswordAlert.open() else {
            return
        }
        let certificateData : Data
        do {
            certificateData = try Data(contentsOf: certificateURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
        
        guard let teamId = LCUtils.getCertTeamId(withKeyData: certificateData, password: certificatePassword) else {
            errorInfo = "lc.settings.invalidCertError".loc
            errorShow = true
            return
        }
        UserDefaults.standard.set(certificatePassword, forKey: "LCCertificatePassword")
        UserDefaults.standard.set(certificateData, forKey: "LCCertificateData")
        UserDefaults.standard.set(teamId, forKey: "LCCertificateTeamId")
        UserDefaults.standard.set(true, forKey: "LCCertificateImported")
        sharedModel.certificateImported = true
    }
    
    func removeCertificate() async {
        guard let doRemove = await certificateRemoveAlert.open(), doRemove else {
            return
        }
        UserDefaults.standard.set(false, forKey: "LCCertificateImported")
        UserDefaults.standard.set(nil, forKey: "LCCertificatePassword")
        UserDefaults.standard.set(nil, forKey: "LCCertificateData")
        UserDefaults.standard.set(nil, forKey: "LCCertificateTeamId")
        sharedModel.certificateImported = false
    }
}
