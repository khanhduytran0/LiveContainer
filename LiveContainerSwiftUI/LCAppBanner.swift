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
    func getDocPath() -> URL
}

struct LCAppBanner : View {
    @State var appInfo: LCAppInfo
    var delegate: LCAppBannerDelegate
    @State var appDataFolders: [String]
    @State var tweakFolders: [String]
    
    @State private var uiDataFolder : String?
    @State private var uiTweakFolder : String?
    @State private var uiPickerDataFolder : String?
    @State private var uiPickerTweakFolder : String?
    
    @State private var confirmAppRemovalShow = false
    @State private var confirmAppFolderRemovalShow = false
    
    @State private var confirmAppRemoval = false
    @State private var confirmAppFolderRemoval = false
    @State private var appRemovalSemaphore = DispatchSemaphore(value: 0)
    @State private var appFolderRemovalSemaphore = DispatchSemaphore(value: 0)
    
    @State private var renameFolderShow = false
    @State private var renameFolderContent = ""
    @State private var renameFolerSemaphore = DispatchSemaphore(value: 0)
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @State private var isSingingInProgress = false
    @State private var signProgress = 0.0
    @State private var isAppRunning = false
    
    @State private var observer : NSKeyValueObservation?
    
    init(appInfo: LCAppInfo, delegate: LCAppBannerDelegate, appDataFolders: [String], tweakFolders: [String]) {
        _appInfo = State(initialValue: appInfo)
        _appDataFolders = State(initialValue: appDataFolders)
        _tweakFolders = State(initialValue: tweakFolders)
        self.delegate = delegate
        _uiDataFolder = State(initialValue: appInfo.getDataUUIDNoAssign())
        _uiTweakFolder = State(initialValue: appInfo.tweakFolder())
        _uiPickerDataFolder = _uiDataFolder
        _uiPickerTweakFolder = _uiTweakFolder
        
    }
    
    var body: some View {

        HStack {
            HStack {
                Image(uiImage: appInfo.icon())
                    .resizable().resizable().frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width:12, height: 12)))
                    

                VStack (alignment: .leading, content: {
                    Text(appInfo.displayName()).font(.system(size: 16)).bold()
                    Text("\(appInfo.version()) - \(appInfo.bundleIdentifier())").font(.system(size: 12)).foregroundColor(Color("FontColor"))
                    Text(uiDataFolder == nil ? "Data folder not created yet" : uiDataFolder!).font(.system(size: 8)).foregroundColor(Color("FontColor"))
                })
            }
            Spacer()
            Button {
                runApp()
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
            Button(role: .destructive) {
                uninstall()
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
            Button {
                // Add to home screen
            } label: {
                Label("Add to home screen", systemImage: "plus.app")
            }
            Menu(content: {
                Button {
                    createFolder()
                } label: {
                    Label("New data folder", systemImage: "plus")
                }
                if uiDataFolder != nil {
                    Button {
                        renameDataFolder()
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
                self.appRemovalSemaphore.signal()
            } label: {
                Text("Uninstall")
            }
            Button("Cancel", role: .cancel) {
                self.confirmAppRemoval = false
                self.appRemovalSemaphore.signal()
            }
        } message: {
            Text("Are you sure you want to uninstall \(appInfo.displayName()!)?")
        }
        .alert("Delete Data Folder", isPresented: $confirmAppFolderRemovalShow) {
            Button(role: .destructive) {
                self.confirmAppFolderRemoval = true
                self.appFolderRemovalSemaphore.signal()
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {
                self.confirmAppFolderRemoval = false
                self.appFolderRemovalSemaphore.signal()
            }
        } message: {
            Text("Do you also want to delete data folder of \(appInfo.displayName()!)? You can keep it for future use.")
        }
        .textFieldAlert(
            isPresented: $renameFolderShow,
            title: "Enter the name of new folder",
            text: $renameFolderContent,
            placeholder: "",
            action: { newText in
                self.renameFolderContent = newText!
                renameFolerSemaphore.signal()
            },
            actionCancel: {_ in 
                self.renameFolderContent = ""
                renameFolerSemaphore.signal()
            }
        )
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
        }

        
    }
    
    func runApp() {
        isAppRunning = true
        DispatchQueue.global().async {
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
        

    }
    
    func setDataFolder(folderName: String?) {
        self.appInfo.setDataUUID(folderName!)
        self.uiDataFolder = folderName
        self.uiPickerDataFolder = folderName
    }
    
    func createFolder() {
        DispatchQueue.global().async {
            self.renameFolderContent = NSUUID().uuidString
            self.renameFolderShow = true
            self.renameFolerSemaphore.wait()
            if self.renameFolderContent == "" {
                return
            }
            let fm = FileManager()
            let dest = self.delegate.getDocPath().appendingPathComponent("Data/Application").appendingPathComponent(self.renameFolderContent)
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
    }
    
    func renameDataFolder() {
        if self.appInfo.getDataUUIDNoAssign() == nil {
            return
        }
        
        DispatchQueue.global().async {
            self.renameFolderContent = self.uiDataFolder == nil ? "" : self.uiDataFolder!
            self.renameFolderShow = true
            self.renameFolerSemaphore.wait()
            if self.renameFolderContent == "" {
                return
            }
            let fm = FileManager()
            let orig = self.delegate.getDocPath().appendingPathComponent("Data/Application").appendingPathComponent(appInfo.getDataUUIDNoAssign())
            let dest = self.delegate.getDocPath().appendingPathComponent("Data/Application").appendingPathComponent(self.renameFolderContent)
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
    }
    
    func setTweakFolder(folderName: String?) {
        self.appInfo.setTweakFolder(folderName)
        self.uiTweakFolder = folderName
        self.uiPickerTweakFolder = folderName
    }
    
    func uninstall() {
        // Add delay because of https://stackoverflow.com/questions/60358948/swiftui-delete-row-in-list-with-context-menu-ui-glitch
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            do {
                self.confirmAppRemovalShow = true;
                self.appRemovalSemaphore.wait()
                if !self.confirmAppRemoval {
                    return
                }
                if self.appInfo.getDataUUIDNoAssign() != nil {
                    self.confirmAppFolderRemovalShow = true;
                    self.appFolderRemovalSemaphore.wait()
                } else {
                    self.confirmAppFolderRemoval = false;
                }

                
                let fm = FileManager()
                try fm.removeItem(atPath: self.appInfo.bundlePath()!)
                self.delegate.removeApp(app: self.appInfo)
                if self.confirmAppFolderRemoval {
                    let fm = FileManager()
                    let dataFolderPath = self.delegate.getDocPath().appendingPathComponent("Data/Application").appendingPathComponent(appInfo.dataUUID()!)
                    try fm.removeItem(at: dataFolderPath)
                }
                
            } catch {
                errorShow = true
                errorInfo = error.localizedDescription

            }
        }
        

    }
}
