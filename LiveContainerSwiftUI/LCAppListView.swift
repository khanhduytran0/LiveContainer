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

struct LCAppListView : View, LCAppBannerDelegate {
    @Binding var apps: [LCAppInfo]
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    
    @State var didAppear = false
    // ipa choosing stuff
    @State var choosingIPA = false
    @State var errorShow = false
    @State var errorInfo = ""
    
    // ipa installing stuff
    @State var installprogressVisible = false
    @State var installProgressPercentage = 0.0
    @State var uiInstallProgressPercentage = 0.0
    @State var installObserver : NSKeyValueObservation?
    
    @State var installReplaceComfirmVisible = false
    @State var installOptions: [AppReplaceOption]
    @State var installOptionChosen: AppReplaceOption?
    @State var installOptionContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State var webViewOpened = false
    @State var webViewURL : URL = URL(string: "https://www.google.com")!
    @State private var webViewUrlInputOpened = false
    @State private var webViewUrlInputContent = ""
    @State private var webViewUrlInputContinuation : CheckedContinuation<Void, Never>? = nil
 
    init(apps: Binding<[LCAppInfo]>, appDataFolderNames: Binding<[String]>, tweakFolderNames: Binding<[String]>) {
        _installOptions = State(initialValue: [])
        _installOptionChosen = State(initialValue: nil)
        _apps = apps
        _appDataFolderNames = appDataFolderNames
        _tweakFolderNames = tweakFolderNames
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(pinnedViews:[.sectionHeaders]) {
                    Section {
                        LazyVStack {
                            ForEach(apps, id: \.self) { app in
                                LCAppBanner(appInfo: app, delegate: self, appDataFolders: $appDataFolderNames, tweakFolders: $tweakFolderNames)
                            }
                            .transition(.scale)
                            
                            if LCUtils.multiLCStatus == 2 {
                                Text("Manage apps in the primary LiveContainer").foregroundStyle(.gray).padding()
                            }
                        }
                        .padding()
                    } header: {
                        GeometryReader{ g in
                            ProgressView(value: uiInstallProgressPercentage)
                                    .labelsHidden()
                                    .opacity(installprogressVisible ? 1 : 0)
                                    .scaleEffect(y: 0.5)
                                    .onChange(of: installProgressPercentage) { newValue in
                                        if newValue > uiInstallProgressPercentage {
                                            withAnimation(.easeIn(duration: 0.3)) {
                                                uiInstallProgressPercentage = newValue
                                            }
                                        } else {
                                            uiInstallProgressPercentage = newValue
                                        }
                                    }
                        }
                    }

                }
                .animation(.easeInOut, value: apps)

            }
            .onAppear {
                if !didAppear {
                    didAppear = true
                    checkIfAppDelegateNeedOpenWebPage()
                }
            }
            
            .navigationTitle("My Apps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if LCUtils.multiLCStatus != 2 {
                        if !installprogressVisible {
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
                        } else {
                            ProgressView().progressViewStyle(.circular)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Open Link", systemImage: "link", action: {
                        Task { await onOpenWebViewTapped() }
                    })
                }
            }

            
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert(isPresented: $errorShow){
            Alert(title: Text("Error"), message: Text(errorInfo))
        }
        .fileImporter(isPresented: $choosingIPA, allowedContentTypes: [.ipa]) { result in
            Task { await startInstallApp(result) }
        }
        .alert("Installation", isPresented: $installReplaceComfirmVisible) {
            ForEach(installOptions, id: \.self) { installOption in
                Button(role: installOption.isReplace ? .destructive : nil, action: {
                    self.installOptionChosen = installOption
                    self.installOptionContinuation?.resume()
                }, label: {
                    Text(installOption.isReplace ? installOption.nameOfFolderToInstall : "Install as new")
                })
            
            }
            Button(role: .cancel, action: {
                self.installOptionChosen = nil
                self.installOptionContinuation?.resume()
            }, label: {
                Text("Abort Installation")
            })
        } message: {
            Text("There is an existing application with the same bundle identifier. Replace one or install as new.")
        }
        .textFieldAlert(
            isPresented: $webViewUrlInputOpened,
            title: "Enter Url or Url Scheme",
            text: $webViewUrlInputContent,
            placeholder: "scheme://",
            action: { newText in
                self.webViewUrlInputContent = newText!
                webViewUrlInputContinuation?.resume()
            },
            actionCancel: {_ in
                self.webViewUrlInputContent = ""
                webViewUrlInputContinuation?.resume()
            }
        )
        .fullScreenCover(isPresented: $webViewOpened) {
            LCWebView(url: $webViewURL, apps: $apps, isPresent: $webViewOpened)
        }

    }
    
    func onOpenWebViewTapped() async {
        await withCheckedContinuation { c in
            webViewUrlInputOpened = true
            webViewUrlInputContinuation = c
        }
            if webViewUrlInputContent == "" {
                return
            }
            openWebView(urlString: webViewUrlInputContent)
            webViewUrlInputContent = ""
        
    }
    
    func checkIfAppDelegateNeedOpenWebPage() {
        LCObjcBridge.openUrlStrFunc = openWebView;
        if LCObjcBridge.urlStrToOpen != nil {
            self.openWebView(urlString: LCObjcBridge.urlStrToOpen!)
            LCObjcBridge.urlStrToOpen = nil
        } else if let urlStr = UserDefaults.standard.string(forKey: "webPageToOpen") {
            UserDefaults.standard.removeObject(forKey: "webPageToOpen")
            self.openWebView(urlString: urlStr)
        }
    }
    
    func openWebView(urlString: String) {
        guard var urlToOpen = URLComponents(string: urlString), urlToOpen.url != nil else {
            errorInfo = "The input url is invalid. Please check and try again"
            errorShow = true
            webViewUrlInputContent = ""
            return
        }
        webViewUrlInputContent = ""
        if urlToOpen.scheme == nil || urlToOpen.scheme! == "" {
            urlToOpen.scheme = "https"
        }
        if urlToOpen.scheme != "https" && urlToOpen.scheme != "http" {
            var appToLaunch : LCAppInfo? = nil
            appLoop: 
            for app in apps {
                if let schemes = app.urlSchemes() {
                    for scheme in schemes {
                        if let scheme = scheme as? String, scheme == urlToOpen.scheme {
                            appToLaunch = app
                            break appLoop
                        }
                    }
                }
            }
            guard let appToLaunch = appToLaunch else {
                errorInfo = "Scheme \"\(urlToOpen.scheme!)\" cannot be opened by any app installed in LiveContainer."
                errorShow = true
                return
            }
            
            UserDefaults.standard.setValue(appToLaunch.relativeBundlePath!, forKey: "selected")
            UserDefaults.standard.setValue(urlToOpen.url!.absoluteString, forKey: "launchAppUrlScheme")
            LCUtils.launchToGuestApp()
            
            return
        }
        webViewURL = urlToOpen.url!
        if webViewOpened {
            webViewOpened = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                webViewOpened = true
            })
        } else {
            webViewOpened = true
        }
    }


    
    func startInstallApp(_ result:Result<URL, any Error>) async {
        do {
            let fileUrl = try result.get()
            self.installprogressVisible = true
            try await installIpaFile(fileUrl)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            self.installprogressVisible = false
        }
    }
    
    
    func installIpaFile(_ url:URL) async throws {
        if(!url.startAccessingSecurityScopedResource()) {
            throw "Failed to access IPA";
        }
        let fm = FileManager()
        
        let installProgress = Progress.discreteProgress(totalUnitCount: 100)
        self.installProgressPercentage = 0.0
        self.installObserver = installProgress.observe(\.fractionCompleted) { p, v in
            self.installProgressPercentage = p.fractionCompleted
        }
        let decompressProgress = Progress.discreteProgress(totalUnitCount: 100)
        installProgress.addChild(decompressProgress, withPendingUnitCount: 80)
        let payloadPath = fm.temporaryDirectory.appendingPathComponent("Payload")
        if fm.fileExists(atPath: payloadPath.path) {
            try fm.removeItem(at: payloadPath)
        }
        
        // decompress
        extract(url.path, fm.temporaryDirectory.path, decompressProgress)
        url.stopAccessingSecurityScopedResource()
        
        let payloadContents = try fm.contentsOfDirectory(atPath: payloadPath.path)
        var appBundleName : String? = nil
        for fileName in payloadContents {
            if fileName.hasSuffix(".app") {
                appBundleName = fileName
                break
            }
        }
        guard let appBundleName = appBundleName else {
            throw "App bundle not found"
        }

        let appFolderPath = payloadPath.appendingPathComponent(appBundleName)
        
        guard let newAppInfo = LCAppInfo(bundlePath: appFolderPath.path) else {
            throw "Failed to read app's Info.plist."
        }

        var appRelativePath = "\(newAppInfo.bundleIdentifier()!).app"
        var outputFolder = LCPath.bundlePath.appendingPathComponent(appRelativePath)
        var appToReplace : LCAppInfo? = nil
        // Folder exist! show alert for user to choose which bundle to replace
        let sameBundleIdApp = self.apps.filter { app in
            return app.bundleIdentifier()! == newAppInfo.bundleIdentifier()
        }
        if fm.fileExists(atPath: outputFolder.path) || sameBundleIdApp.count > 0 {
            appRelativePath = "\(newAppInfo.bundleIdentifier()!)_\(Int(CFAbsoluteTimeGetCurrent())).app"
            
            self.installOptions = [AppReplaceOption(isReplace: false, nameOfFolderToInstall: appRelativePath)]
            
            for app in sameBundleIdApp {
                self.installOptions.append(AppReplaceOption(isReplace: true, nameOfFolderToInstall: app.relativeBundlePath, appToReplace: app))
            }

            await withCheckedContinuation { c in
                self.installOptionContinuation = c
                self.installReplaceComfirmVisible = true
            }
            
            
            // user cancelled
            guard let installOptionChosen = self.installOptionChosen else {
                self.installprogressVisible = false
                try fm.removeItem(at: payloadPath)
                return
            }
            
            outputFolder = LCPath.bundlePath.appendingPathComponent(installOptionChosen.nameOfFolderToInstall)
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
            var error : Error? = nil
            var success = false
            await withCheckedContinuation { c in
                let signProgress = LCUtils.signAppBundle(outputFolder) { success1, error1 in
                    error = error1
                    success = success1
                    c.resume()
                }
                installProgress.addChild(signProgress!, withPendingUnitCount: 20)
            }
            
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
        DispatchQueue.main.async {
            self.apps.removeAll { now in
                return app == now
            }
        }
    }
}
