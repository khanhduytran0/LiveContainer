//
//  ContentView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct AppReplaceOption : Hashable {
    var isReplace: Bool
    var nameOfFolderToInstall: String
    var appToReplace: LCAppInfo?
}

class ProgressObserver : NSObject {
    var delegate : (_ fraction: Double) -> Void;
    
    init(delegate: @escaping (_: Double) -> Void) {
        self.delegate = delegate
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                                        of object: Any?,
                                           change: [NSKeyValueChangeKey : Any]?,
                                          context: UnsafeMutableRawPointer?) {
        
        if let theKeyPath = keyPath {
            if theKeyPath == "fractionCompleted" {
                let progress = object as! Progress
                self.delegate(progress.fractionCompleted)
            }
        }
        
        
    }
}

struct LCAppListView : View, LCAppBannerDelegate {
    private var docPath: URL
    var bundlePath: URL
    @State var apps: [LCAppInfo]
//    @State var aaa: [String]
    
    // ipa choosing stuff
    @State var choosingIPA = false
    @State var installErrorShow = false
    @State var installErrorInfo = ""
    
    // ipa installing stuff
    @State var installprogressVisible = false
    @State var installProgress: Progress
    @State var installProgressPercentage = 0.0
    
    @State var installReplaceComfirmVisible = false
    @State var installOptions: [AppReplaceOption]
    @State var installOptionChosen: AppReplaceOption?
    @State var installOptionSemaphore = DispatchSemaphore(value: 0)

 
    init() {
        let fm = FileManager()
        self.docPath = fm.urls(for: .documentDirectory, in: .userDomainMask).last!
        self.bundlePath = self.docPath.appendingPathComponent("Applications")
        _installProgress = State(initialValue:  Progress.discreteProgress(totalUnitCount: 100))
        _installOptions = State(initialValue: [])
        _installOptionChosen = State(initialValue: nil)
        
        var tempApps: [LCAppInfo] = []

        do {
            try fm.createDirectory(at: self.bundlePath, withIntermediateDirectories: true)
            let appDirs = try fm.contentsOfDirectory(atPath: self.bundlePath.path)
            for appDir in appDirs {
                if !appDir.hasSuffix(".app") {
                    continue
                }
                let newApp = LCAppInfo(bundlePath: "\(self.bundlePath.path)/\(appDir)")!
                newApp.relativeBundlePath = appDir
                tempApps.append(newApp)
            }
        } catch {
            NSLog("[NMSL] error:\(error)")
        }
        _apps = State(initialValue: tempApps)
    }
    
    var body: some View {
        NavigationView {
            
            ScrollView {
                LazyVStack(pinnedViews:[.sectionHeaders]) {
                    Section {
                        LazyVStack {
                            ForEach(apps, id: \.self) { app in
                                LCAppBanner(appInfo: app, delegate: self)
                            }
                            .transition(.scale)
                        }
                        .padding()
                    } header: {
                        GeometryReader{ g in
                            ProgressView(value: installProgressPercentage)
                                    .labelsHidden()
                                    .opacity(installprogressVisible ? 1 : 0)
                        }
                    }

                }
                .animation(.easeInOut, value: apps)

            }
            
            
            .navigationTitle("My Apps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add", systemImage: "plus", action: {
                        if choosingIPA {
                            choosingIPA = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                                choosingIPA = true
                            })
                        } else {
                            choosingIPA = true
                        }

                        
                    })
                }
            }

            
        }
        
        .alert(isPresented: $installErrorShow){
            Alert(title: Text("Installation Failed"), message: Text(installErrorInfo))
        }
        .fileImporter(isPresented: $choosingIPA, allowedContentTypes: [UTType(filenameExtension: "ipa")!]) { result in
            startInstallApp(result)

        }
        .alert("Installation", isPresented: $installReplaceComfirmVisible) {
            ForEach(installOptions, id: \.self) { installOption in
                Button(role: installOption.isReplace ? .destructive : nil, action: {
                    self.installOptionChosen = installOption
                    self.installOptionSemaphore.signal()
                }, label: {
                    Text(installOption.isReplace ? installOption.nameOfFolderToInstall : "Install as new")
                })
            
            }
            Button(role: .cancel, action: {
                self.installOptionChosen = nil
                self.installOptionSemaphore.signal()
            }, label: {
                Text("Abort Installation")
            })
        } message: {
            Text("There is an existing application with the same bundle identifier. Replace one or install as new.")
        }

    }
    

    
    func startInstallApp(_ result:Result<URL, any Error>) {
        DispatchQueue.global().async {
            do {
                let fileUrl = try result.get()
                self.installprogressVisible = true
                try installIpaFile(fileUrl)
            } catch {
                installErrorInfo = error.localizedDescription
                installErrorShow = true
                self.installprogressVisible = false
            }
        }

    }
    
    func onInstallProgress(_ fraction : Double) {
        self.installProgressPercentage = fraction
    }
    
    
    func installIpaFile(_ url:URL) throws {
        if(!url.startAccessingSecurityScopedResource()) {
            throw "Failed to access IPA";
        }
        let fm = FileManager()
        
        self.installProgress = Progress.discreteProgress(totalUnitCount: 100)
        self.installProgressPercentage = 0.0
        let progressObserver = ProgressObserver(delegate: onInstallProgress)
        self.installProgress.addObserver(progressObserver, forKeyPath: "fractionCompleted", context: nil)
        let decompressProgress = Progress.discreteProgress(totalUnitCount: 100)
        self.installProgress.addChild(decompressProgress, withPendingUnitCount: 80)
        
        // decompress
        extract(url.path, fm.temporaryDirectory.path, decompressProgress)
        url.stopAccessingSecurityScopedResource()
        
        let payloadPath = fm.temporaryDirectory.appendingPathComponent("Payload")
        let payloadContents = try fm.contentsOfDirectory(atPath: payloadPath.path)
        if payloadContents.count < 1 || !payloadContents[0].hasSuffix(".app") {
            throw "App bundle not found"
        }
        let appBundleName = payloadContents[0]
        let appFolderPath = payloadPath.appendingPathComponent(appBundleName)
        
        guard let newAppInfo = LCAppInfo(bundlePath: appFolderPath.path) else {
            throw "Failed to read app's Info.plist."
        }

        var appRelativePath = "\(newAppInfo.bundleIdentifier()!).app"
        var outputFolder = self.bundlePath.appendingPathComponent(appRelativePath)
        var appToReplace : LCAppInfo? = nil
        // Folder exist! show alert for user to choose which bundle to replace
        let sameBundleIdApp = self.apps.filter { app in
            return app.bundleIdentifier()! == newAppInfo.bundleIdentifier()
        }
        if fm.fileExists(atPath: outputFolder.path) || sameBundleIdApp.count > 0 {
            appRelativePath = "\(newAppInfo.bundleIdentifier()!)_\(CFAbsoluteTimeGetCurrent()).app"
            
            self.installOptions = [AppReplaceOption(isReplace: false, nameOfFolderToInstall: appRelativePath)]
            
            for app in sameBundleIdApp {
                self.installOptions.append(AppReplaceOption(isReplace: true, nameOfFolderToInstall: app.relativeBundlePath, appToReplace: app))
            }
            self.installReplaceComfirmVisible = true
            self.installOptionSemaphore.wait()
            
            // user cancelled
            guard let installOptionChosen = self.installOptionChosen else {
                self.installprogressVisible = false
                try fm.removeItem(at: payloadPath)
                return
            }
            
            outputFolder = self.bundlePath.appendingPathComponent(installOptionChosen.nameOfFolderToInstall)
            appToReplace = installOptionChosen.appToReplace
            if installOptionChosen.isReplace {
                try fm.removeItem(at: outputFolder)
                self.apps.removeAll { appNow in
                    return appNow.relativeBundlePath == installOptionChosen.nameOfFolderToInstall
                }
            }
        }
        // Move it!
        try fm.moveItem(at: appFolderPath, to: outputFolder)
        let finalNewApp = LCAppInfo(bundlePath: outputFolder.path)
        finalNewApp?.relativeBundlePath = appRelativePath
        
        // patch it
        let patchResult = finalNewApp?.patchExec()
        if patchResult != nil && patchResult != "SignNeeded" {
            throw patchResult!;
        }
        if patchResult == "SignNeeded" {
            // sign it
            let signSemaphore = DispatchSemaphore(value: 0)
            var error : Error? = nil
            var success = false
            let signProgress = LCUtils.signAppBundle(outputFolder) { success1, error1 in
                error = error1
                success = success1
                signSemaphore.signal()
            }
            self.installProgress.addChild(signProgress!, withPendingUnitCount: 20)
            signSemaphore.wait()
            
            if let error = error {
                finalNewApp?.signCleanUp(withSuccessStatus: false)
                throw error
            }
            finalNewApp?.signCleanUp(withSuccessStatus: success)
            if !success {
                throw "Unknow error occurred"
            }

            
        }
        // set data folder to the folder of the chosen app
        if let appToReplace = appToReplace {
            finalNewApp?.setDataUUID(appToReplace.getDataUUIDNoAssign())
        }
        self.apps.append(finalNewApp!)
        self.installprogressVisible = false
    }
    
    func removeApp(app: LCAppInfo) {
        self.apps.removeAll { now in
            return app == now
        }
    }
    
    func getDocPath() -> URL {
        return self.docPath
    }
    
}

#Preview {
    LCAppListView()
}
