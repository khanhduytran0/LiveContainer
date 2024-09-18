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
    func changeAppVisibility(app: LCAppInfo)
    func installMdm(data: Data)
    func openNavigationView(view: AnyView)
    func closeNavigationView()
}

struct LCAppBanner : View, LCAppSettingDelegate {
    @State var appInfo: LCAppInfo
    var delegate: LCAppBannerDelegate
    
    @StateObject var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    
    
    @State private var confirmAppRemovalShow = false
    @State private var confirmAppFolderRemovalShow = false
    
    @State private var confirmAppRemoval = false
    @State private var confirmAppFolderRemoval = false
    @State private var appRemovalContinuation : CheckedContinuation<Void, Never>? = nil
    @State private var appFolderRemovalContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var enablingJITShow = false
    @State private var confirmEnablingJIT = false
    @State private var confirmEnablingJITContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var saveIconExporterShow = false
    @State private var saveIconFile : ImageDocument?
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @State private var isSingingInProgress = false
    @State private var signProgress = 0.0
    
    @State private var observer : NSKeyValueObservation?
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(appInfo: LCAppInfo, delegate: LCAppBannerDelegate, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        _appInfo = State(initialValue: appInfo)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self.delegate = delegate
        
        _model = StateObject(wrappedValue: LCAppModel(appInfo: appInfo))
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
                        if model.uiIsShared {
                            Text("lc.appBanner.shared".loc).font(.system(size: 8)).bold().padding(2)
                                .frame(width: 50, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                        if model.uiIsJITNeeded {
                            Text("JIT").font(.system(size: 8)).bold().padding(2)
                                .frame(width: 30, height:16)
                                .background(
                                    Capsule().fill(Color("JITBadgeColor"))
                                )
                        }
                    }

                    Text("\(appInfo.version()) - \(appInfo.bundleIdentifier())").font(.system(size: 12)).foregroundColor(Color("FontColor"))
                    Text(LocalizedStringKey(model.uiDataFolder == nil ? "lc.appBanner.noDataFolder".loc : model.uiDataFolder!)).font(.system(size: 8)).foregroundColor(Color("FontColor"))
                })
            }
            Spacer()
            Button {
                Task{ await runApp() }
            } label: {
                if !isSingingInProgress {
                    Text("lc.appBanner.run".loc).bold().foregroundColor(.white)
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
            .disabled(model.isAppRunning)
            
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerSize: CGSize(width:22, height: 22)).fill(Color("AppBannerBG")))
        
        .fileExporter(
            isPresented: $saveIconExporterShow,
            document: saveIconFile,
            contentType: .image,
            defaultFilename: "\(appInfo.displayName()!) Icon.png",
            onCompletion: { result in
            
        })
        .contextMenu{
            Section(appInfo.relativeBundlePath) {
                if #available(iOS 16.0, *){
                    
                } else {
                    Text(appInfo.relativeBundlePath)
                }
                if !model.uiIsShared {
                    if model.uiDataFolder != nil {
                        Button {
                            openDataFolder()
                        } label: {
                            Label("lc.appBanner.openDataFolder".loc, systemImage: "folder")
                        }
                    }
                }
                
                Menu {
                    Button {
                        openSafariViewToCreateAppClip()
                    } label: {
                        Label("lc.appBanner.createAppClip".loc, systemImage: "appclip")
                    }
                    Button {
                        copyLaunchUrl()
                    } label: {
                        Label("lc.appBanner.copyLaunchUrl".loc, systemImage: "link")
                    }
                    Button {
                        saveIcon()
                    } label: {
                        Label("lc.appBanner.saveAppIcon".loc, systemImage: "square.and.arrow.down")
                    }


                } label: {
                    Label("lc.appBanner.addToHomeScreen".loc, systemImage: "plus.app")
                }
                
                Button {
                    openSettings()
                } label: {
                    Label("lc.tabView.settings".loc, systemImage: "gear")
                }

                
                if !model.uiIsShared {
                    Button(role: .destructive) {
                         Task{ await uninstall() }
                    } label: {
                        Label("lc.appBanner.uninstall".loc, systemImage: "trash")
                    }
                    
                }

            }
            
            


        }

        .onChange(of: sharedModel.bundleIdToLaunch, perform: { newValue in
            Task { await handleURLSchemeLaunch() }
        })
        
        .onAppear() {
            Task { await handleURLSchemeLaunch() }
        }
        
        .alert("lc.appBanner.confirmUninstallTitle".loc, isPresented: $confirmAppRemovalShow) {
            Button(role: .destructive) {
                self.confirmAppRemoval = true
                self.appRemovalContinuation?.resume()
            } label: {
                Text("lc.appBanner.uninstall".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.confirmAppRemoval = false
                self.appRemovalContinuation?.resume()
            }
        } message: {
            Text("lc.appBanner.confirmUninstallMsg %@".localizeWithFormat(appInfo.displayName()!))
        }
        .alert("lc.appBanner.deleteDataTitle".loc, isPresented: $confirmAppFolderRemovalShow) {
            Button(role: .destructive) {
                self.confirmAppFolderRemoval = true
                self.appFolderRemovalContinuation?.resume()
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.confirmAppFolderRemoval = false
                self.appFolderRemovalContinuation?.resume()
            }
        } message: {
            Text("lc.appBanner.deleteDataMsg \(appInfo.displayName()!)")
        }
        .alert("lc.appBanner.waitForJitTitle".loc, isPresented: $enablingJITShow) {
            Button {
                self.confirmEnablingJIT = true
                self.confirmEnablingJITContinuation?.resume()
            } label: {
                Text("lc.appBanner.jitLaunchNow".loc)
            }
            Button("lc.common.cancel", role: .cancel) {
                self.confirmEnablingJIT = false
                self.confirmEnablingJITContinuation?.resume()
            }
        } message: {
            Text("lc.appBanner.waitForJitMsg".loc)
        }
        
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        
    }
    
    func handleURLSchemeLaunch() async {
        if self.appInfo.relativeBundlePath == sharedModel.bundleIdToLaunch {
            await runApp()
        }
    }
    
    func runApp() async {
        if let runningLC = LCUtils.getAppRunningLCScheme(bundleId: self.appInfo.relativeBundlePath) {
            let openURL = URL(string: "\(runningLC)://livecontainer-launch?bundle-name=\(self.appInfo.relativeBundlePath!)")!
            if UIApplication.shared.canOpenURL(openURL) {
                await UIApplication.shared.open(openURL)
                return
            }
        }
        model.isAppRunning = true

        var signError : String? = nil
        await withCheckedContinuation({ c in
            appInfo.patchExecAndSignIfNeed(completionHandler: { error in
                signError = error;
                c.resume()
            }, progressHandler: { signProgress in
                guard let signProgress else {
                    return
                }
                self.isSingingInProgress = true
                self.observer = signProgress.observe(\.fractionCompleted) { p, v in
                    DispatchQueue.main.async {
                        self.signProgress = signProgress.fractionCompleted
                    }
                }
            }, forceSign: false)
        })
        self.isSingingInProgress = false
        if let signError {
            errorInfo = signError
            errorShow = true
            model.isAppRunning = false
            return
        }
        
        UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        if appInfo.isJITNeeded {
            await self.jitLaunch()
        } else {
            LCUtils.launchToGuestApp()
        }

        model.isAppRunning = false
        
    }
    
    func openSettings() {
        delegate.openNavigationView(view: AnyView(LCAppSettingsView(model: model, appDataFolders: $appDataFolders, tweakFolders: $tweakFolders, delegate: self)))
    }
    
    func forceResign() async {
        if model.isAppRunning {
            return
        }
        
        model.isAppRunning = true
        var signError : String? = nil
        await withCheckedContinuation({ c in
            appInfo.patchExecAndSignIfNeed(completionHandler: { error in
                signError = error;
                c.resume()
            }, progressHandler: { signProgress in
                guard let signProgress else {
                    return
                }
                self.isSingingInProgress = true
                self.observer = signProgress.observe(\.fractionCompleted) { p, v in
                    DispatchQueue.main.async {
                        self.signProgress = signProgress.fractionCompleted
                    }
                }
            }, forceSign: true)
        })
        self.isSingingInProgress = false
        if let signError {
            errorInfo = signError
            errorShow = true
            model.isAppRunning = false
            return
        }
        model.isAppRunning = false
    }
    
    
    
    func openDataFolder() {
        let url = URL(string:"shareddocuments://\(LCPath.docPath.path)/Data/Application/\(appInfo.dataUUID()!)")
        UIApplication.shared.open(url!)
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
    
    func jitLaunch() async {
        LCUtils.askForJIT()

        await withCheckedContinuation { c in
            self.confirmEnablingJITContinuation = c
            enablingJITShow = true
        }
        if confirmEnablingJIT {
            LCUtils.launchToGuestApp()
        } else {
            UserDefaults.standard.removeObject(forKey: "selected")
        }
    }
    
    func copyLaunchUrl() {
        UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)"
    }
    
    func openSafariViewToCreateAppClip() {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: appInfo.generateWebClipConfig()!, format: .xml, options: 0)
            delegate.installMdm(data: data)
        } catch  {
            errorShow = true
            errorInfo = error.localizedDescription
        }

    }
    
    func toggleHidden() async {
        delegate.closeNavigationView()
        if appInfo.isHidden {
            appInfo.isHidden = false
            model.uiIsHidden = false
        } else {
            appInfo.isHidden = true
            model.uiIsHidden = true
        }
        delegate.changeAppVisibility(app: appInfo)
    }
    
    func saveIcon() {
        let img = appInfo.icon()!
        self.saveIconFile = ImageDocument(uiImage: img)
        self.saveIconExporterShow = true
    }
    
    
}
