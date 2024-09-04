//
//  LCAppBanner.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

protocol LCAppBannerDelegate {
    func removeApp(app: LCAppInfo)
}

struct LCAppBanner : View {
    @State var appInfo: LCAppInfo
    var delegate: LCAppBannerDelegate
    
    @State var uiIsShared : Bool
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    
    @State private var uiDataFolder : String?
    @State private var uiTweakFolder : String?
    @State private var uiPickerDataFolder : String?
    @State private var uiPickerTweakFolder : String?
    
    @State private var confirmAppRemovalShow = false
    @State private var confirmAppFolderRemovalShow = false
    
    @State private var confirmAppRemoval = false
    @State private var confirmAppFolderRemoval = false
    @State private var appRemovalContinuation : CheckedContinuation<Void, Never>? = nil
    @State private var appFolderRemovalContinuation : CheckedContinuation<Void, Never>? = nil
    
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
    
    @State private var isSingingInProgress = false
    @State private var signProgress = 0.0
    @State private var isAppRunning = false
    
    @State private var observer : NSKeyValueObservation?
    
    init(appInfo: LCAppInfo, delegate: LCAppBannerDelegate, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        _appInfo = State(initialValue: appInfo)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self.delegate = delegate
        _uiDataFolder = State(initialValue: appInfo.getDataUUIDNoAssign())
        _uiTweakFolder = State(initialValue: appInfo.tweakFolder())
        _uiPickerDataFolder = _uiDataFolder
        _uiPickerTweakFolder = _uiTweakFolder
        
        _uiIsShared = State(initialValue: appInfo.isShared)
        
    }
    
    var body: some View {

        HStack {
            HStack {
                Image(uiImage: appInfo.icon())
                    .resizable().resizable().frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width:12, height: 12)))
                    

                VStack (alignment: .leading, content: {
                    HStack {
                        Text(appInfo.displayName()).font(.system(size: 16)).bold()
                        if uiIsShared {
                            Text("SHARED").font(.system(size: 8)).bold().padding(2)
                                .frame(width: 50, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                    }

                    Text("\(appInfo.version()) - \(appInfo.bundleIdentifier())").font(.system(size: 12)).foregroundColor(Color("FontColor"))
                    Text(uiDataFolder == nil ? "Data folder not created yet" : uiDataFolder!).font(.system(size: 8)).foregroundColor(Color("FontColor"))
                })
            }
            Spacer()
            Button {
                Task{ await runApp() }
            } label: {
                if !isSingingInProgress {
                    Text("Run").bold().foregroundColor(.white)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
            .padding()
            .frame(idealWidth: 70)
            .frame(height: 32)
            .fixedSize()
            .background(GeometryReader { g in
                if !isSingingInProgress {
                    Capsule().fill(Color("FontColor"))
                } else {
                    let w = g.size.width
                    let h = g.size.height
                    Capsule()
                        .fill(Color("FontColor")).opacity(0.2)
                    Circle()
                        .fill(Color("FontColor"))
                        .frame(width: w * 2, height: w * 2)
                        .offset(x: (signProgress - 2) * w, y: h/2-w)
                }

            })
            .clipShape(Capsule())
            .disabled(isAppRunning)
            
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerSize: CGSize(width:22, height: 22)).fill(Color("AppBannerBG")))
        
        
        .contextMenu{
            Text(appInfo.relativeBundlePath)
            if !uiIsShared {
                Button(role: .destructive) {
                     Task{ await uninstall() }
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                Button {
                    Task { await moveToAppGroup()}
                } label: {
                    Label("Convert to Shared App", systemImage: "arrowshape.turn.up.left")
                }
                Menu(content: {
                    Button {
                        Task{ await createFolder() }
                    } label: {
                        Label("New data folder", systemImage: "plus")
                    }
                    if uiDataFolder != nil {
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
                }, label: {
                    Label("Change Data Folder", systemImage: "folder.badge.questionmark")
                })
                
                Menu(content: {
                    Picker(selection: $uiPickerTweakFolder , label: Text("")) {
                        Label("None", systemImage: "nosign").tag(Optional<String>(nil))
                        ForEach(tweakFolders, id:\.self) { folderName in
                            Text(folderName).tag(Optional(folderName))
                        }
                    }
                }, label: {
                    Label("Change Tweak Folder", systemImage: "gear")
                })
            } else {
                Button {
                    Task { await movePrivateDoc() }
                } label: {
                    Label("Convert to Private App", systemImage: "arrowshape.turn.up.left")
                }
            }

        }
        .onChange(of: uiPickerDataFolder, perform: { newValue in
            if newValue != uiDataFolder {
                setDataFolder(folderName: newValue)
            }
        })
        .onChange(of: uiPickerTweakFolder, perform: { newValue in
            if newValue != uiTweakFolder {
                setTweakFolder(folderName: newValue)
            }
        })
        
        .alert("Confirm Uninstallation", isPresented: $confirmAppRemovalShow) {
            Button(role: .destructive) {
                self.confirmAppRemoval = true
                self.appRemovalContinuation?.resume()
            } label: {
                Text("Uninstall")
            }
            Button("Cancel", role: .cancel) {
                self.confirmAppRemoval = false
                self.appRemovalContinuation?.resume()
            }
        } message: {
            Text("Are you sure you want to uninstall \(appInfo.displayName()!)?")
        }
        .alert("Delete Data Folder", isPresented: $confirmAppFolderRemovalShow) {
            Button(role: .destructive) {
                self.confirmAppFolderRemoval = true
                self.appFolderRemovalContinuation?.resume()
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {
                self.confirmAppFolderRemoval = false
                self.appFolderRemovalContinuation?.resume()
            }
        } message: {
            Text("Do you also want to delete data folder of \(appInfo.displayName()!)? You can keep it for future use.")
        }
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
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
        }

        
    }
    
    func runApp() async {
        if let runningLC = LCUtils.getAppRunningLCScheme(bundleId: self.appInfo.relativeBundlePath) {
            let openURL = URL(string: "\(runningLC)://livecontainer-launch?bundle-name=\(self.appInfo.relativeBundlePath!)")!
            if await UIApplication.shared.canOpenURL(openURL) {
                await UIApplication.shared.open(openURL)
                return
            }
        }
        isAppRunning = true

        let patchInfo = appInfo.patchExec()
        if patchInfo == "SignNeeded" {
            let bundlePath = URL(fileURLWithPath: appInfo.bundlePath())
            let signProgress = LCUtils.signAppBundle(bundlePath) { success, error in
                self.appInfo.signCleanUp(withSuccessStatus: success)
                self.isSingingInProgress = false
                if success {
                    self.isSingingInProgress = false
                    UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
                    LCUtils.launchToGuestApp()
                } else {
                    errorInfo = error != nil ? error!.localizedDescription : "Signing failed with unknown error"
                    errorShow = true
                }
            }
            guard let signProgress = signProgress else {
                errorInfo = "Failed to initiate signing!"
                errorShow = true
                self.isAppRunning = false
                return
            }
            self.isSingingInProgress = true
            self.observer = signProgress.observe(\.fractionCompleted) { p, v in
                self.signProgress = signProgress.fractionCompleted
            }
        } else if patchInfo != nil {
            errorInfo = patchInfo!
            errorShow = true
            self.isAppRunning = false
            return
        } else {
            UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
            LCUtils.launchToGuestApp()
        }
        self.isAppRunning = false
        
    }
    
    func setDataFolder(folderName: String?) {
        self.appInfo.setDataUUID(folderName!)
        self.uiDataFolder = folderName
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
        
        self.renameFolderContent = self.uiDataFolder == nil ? "" : self.uiDataFolder!
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
        self.uiTweakFolder = folderName
        self.uiPickerTweakFolder = folderName
    }
    
    func uninstall() async {
        do {
            await withCheckedContinuation { c in
                self.appRemovalContinuation = c
                self.confirmAppRemovalShow = true;
            }
            
            if !self.confirmAppRemoval {
                return
            }
            if self.appInfo.getDataUUIDNoAssign() != nil {
                self.confirmAppFolderRemovalShow = true;
                await withCheckedContinuation { c in
                    self.appFolderRemovalContinuation = c
                    self.confirmAppFolderRemovalShow = true;
                }
            } else {
                self.confirmAppFolderRemoval = false;
            }
            
            
            let fm = FileManager()
            try fm.removeItem(atPath: self.appInfo.bundlePath()!)
            self.delegate.removeApp(app: self.appInfo)
            if self.confirmAppFolderRemoval {
                let dataUUID = appInfo.dataUUID()!
                let dataFolderPath = LCPath.dataPath.appendingPathComponent(dataUUID)
                try fm.removeItem(at: dataFolderPath)
                
                DispatchQueue.main.async {
                    self.appDataFolders.removeAll(where: { f in
                        return f == dataUUID
                    })
                }
            }
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
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
            uiIsShared = true
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func movePrivateDoc() async {
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
                uiDataFolder = dataFolder
                uiPickerDataFolder = dataFolder
            }
            if let tweakFolder = appInfo.tweakFolder(), tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.tweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.append(tweakFolder)
                uiTweakFolder = tweakFolder
                uiPickerTweakFolder = tweakFolder
            }
            appInfo.setBundlePath(LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = false
            uiIsShared = false
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
        }
        
    }
        

    
}
