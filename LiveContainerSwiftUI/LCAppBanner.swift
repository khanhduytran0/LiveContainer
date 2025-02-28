//
//  LCAppBanner.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

protocol LCAppBannerDelegate {
    func removeApp(app: LCAppModel)
    func installMdm(data: Data)
    func openNavigationView(view: AnyView)
}

struct LCAppBanner : View {
    @State var appInfo: LCAppInfo
    var delegate: LCAppBannerDelegate
    
    @ObservedObject var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    
    @StateObject private var appRemovalAlert = YesNoHelper()
    @StateObject private var appFolderRemovalAlert = YesNoHelper()
    @StateObject private var jitAlert = YesNoHelper()
    
    @State private var saveIconExporterShow = false
    @State private var saveIconFile : ImageDocument?
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @AppStorage("dynamicColors") var dynamicColors = true
    @State private var mainColor : Color
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(appModel: LCAppModel, delegate: LCAppBannerDelegate, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        _appInfo = State(initialValue: appModel.appInfo)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self.delegate = delegate
        
        _model = ObservedObject(wrappedValue: appModel)
        _mainColor = State(initialValue: Color.clear)
        _mainColor = State(initialValue: extractMainHueColor())
    }
    @State private var mainHueColor: CGFloat? = nil
    
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
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8))
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                        if model.uiIsJITNeeded {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("JITBadgeColor"))
                                )
                        }
                        if model.uiIs32bit {
                            Text("32")
                                .font(.system(size: 8))
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("32BitBadgeColor"))
                                )
                        }
                        if model.uiIsLocked && !model.uiIsHidden {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                    }

                    Text("\(appInfo.version()) - \(appInfo.bundleIdentifier())").font(.system(size: 12)).foregroundColor(dynamicColors ? mainColor : Color("FontColor"))
                    Text(model.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc).font(.system(size: 8)).foregroundColor(dynamicColors ? mainColor : Color("FontColor"))
                })
            }
            Spacer()
            Button {
                Task{ await runApp() }
            } label: {
                if !model.isSigningInProgress {
                    Text("lc.appBanner.run".loc).bold().foregroundColor(.white)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
            .buttonStyle(BasicButtonStyle())
            .padding()
            .frame(idealWidth: 70)
            .frame(height: 32)
            .fixedSize()
            .background(GeometryReader { g in
                if !model.isSigningInProgress {
                    Capsule().fill(dynamicColors ? mainColor : Color("FontColor"))
                } else {
                    let w = g.size.width
                    let h = g.size.height
                    Capsule()
                        .fill(dynamicColors ? mainColor : Color("FontColor")).opacity(0.2)
                    Circle()
                        .fill(dynamicColors ? mainColor : Color("FontColor"))
                        .frame(width: w * 2, height: w * 2)
                        .offset(x: (model.signProgress - 2) * w, y: h/2-w)
                }

            })
            .clipShape(Capsule())
            .disabled(model.isAppRunning)
            
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerSize: CGSize(width:22, height: 22)).fill(dynamicColors ? mainColor.opacity(0.5) : Color("AppBannerBG")))
        .onAppear() {
            handleOnAppear()
        }
        
        .fileExporter(
            isPresented: $saveIconExporterShow,
            document: saveIconFile,
            contentType: .image,
            defaultFilename: "\(appInfo.displayName()!) Icon.png",
            onCompletion: { result in
            
        })
        .contextMenu{
            if model.uiContainers.count > 1 {
                Picker(selection: $model.uiSelectedContainer , label: Text("Containers")) {
                    ForEach(model.uiContainers, id:\.self) { container in
                        Text(container.name).tag(container)
                    }
                }
            }

            
            Section(appInfo.relativeBundlePath) {
                if #available(iOS 16.0, *){
                    
                } else {
                    Text(appInfo.relativeBundlePath)
                }
                if !model.uiIsShared {
                    if let container = model.uiSelectedContainer {
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
        
        .alert("lc.appBanner.confirmUninstallTitle".loc, isPresented: $appRemovalAlert.show) {
            Button(role: .destructive) {
                appRemovalAlert.close(result: true)
            } label: {
                Text("lc.appBanner.uninstall".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                appRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmUninstallMsg %@".localizeWithFormat(appInfo.displayName()!))
        }
        .alert("lc.appBanner.deleteDataTitle".loc, isPresented: $appFolderRemovalAlert.show) {
            Button(role: .destructive) {
                appFolderRemovalAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.no".loc, role: .cancel) {
                appFolderRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.deleteDataMsg \(appInfo.displayName()!)")
        }
        .sheet(isPresented: $jitAlert.show, onDismiss: {
            jitAlert.close(result: false)
        }) {
            JITEnablingModal
        }
        
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        
    }
    
    var JITEnablingModal : some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    Text("lc.appBanner.waitForJitMsg".loc)
                        .padding(.vertical)
                        .id(0)
                    
                    HStack {
                        Text(model.jitLog)
                            .font(.system(size: 12).monospaced())
                            .fixedSize(horizontal: false, vertical: false)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .onAppear {
                    proxy.scrollTo(0)
                }
            }
            .navigationTitle("lc.appBanner.waitForJitTitle".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("lc.common.cancel".loc, role: .cancel) {
                        jitAlert.close(result: false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        jitAlert.close(result: true)
                    } label: {
                        Text("lc.appBanner.jitLaunchNow".loc)
                    }
                }
            }
        }
    }
    
    func handleOnAppear() {
        model.jitAlert = jitAlert
    }
    
    func runApp() async {
        if appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                if !(try await LCUtils.authenticateUser()) {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
                return
            }
        }

        do {
            try await model.runApp()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    
    func openSettings() {
        delegate.openNavigationView(view: AnyView(LCAppSettingsView(model: model, appDataFolders: $appDataFolders, tweakFolders: $tweakFolders)))
    }
    
    
    func openDataFolder() {
        let url = URL(string:"shareddocuments://\(LCPath.docPath.path)/Data/Application/\(model.uiSelectedContainer!.folderName)")
        UIApplication.shared.open(url!)
    }
    

    
    func uninstall() async {
        do {
            if let result = await appRemovalAlert.open(), !result {
                return
            }
            
            var doRemoveAppFolder = false
            let containers = appInfo.containers
            if !containers.isEmpty {
                if let result = await appFolderRemovalAlert.open() {
                    doRemoveAppFolder = result
                }
                
            }
            
            let fm = FileManager()
            try fm.removeItem(atPath: self.appInfo.bundlePath()!)
            self.delegate.removeApp(app: self.model)
            if doRemoveAppFolder {
                for container in containers {
                    let dataUUID = container.folderName
                    let dataFolderPath = LCPath.dataPath.appendingPathComponent(dataUUID)
                    try fm.removeItem(at: dataFolderPath)
                    LCUtils.removeAppKeychain(dataUUID: dataUUID)
                    
                    DispatchQueue.main.async {
                        self.appDataFolders.removeAll(where: { f in
                            return f == dataUUID
                        })
                    }
                }
            }
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    
    func copyLaunchUrl() {
        if let fn = model.uiSelectedContainer?.folderName {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)&container-folder-name=\(fn)"
        } else {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)"
        }
        
    }
    
    func openSafariViewToCreateAppClip() {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: appInfo.generateWebClipConfig(withContainerId: model.uiSelectedContainer?.folderName)!, format: .xml, options: 0)
            delegate.installMdm(data: data)
        } catch  {
            errorShow = true
            errorInfo = error.localizedDescription
        }

    }
    
    func saveIcon() {
        let img = appInfo.generateLiveContainerWrappedIcon()!
        self.saveIconFile = ImageDocument(uiImage: img)
        self.saveIconExporterShow = true
    }
    
    func extractMainHueColor() -> Color {
        if let cachedColor = appInfo.cachedColor {
            return Color(uiColor: cachedColor)
        }
        guard let cgImage = appInfo.icon().cgImage else { return Color.clear }

        let width = 1
        let height = 1
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 4)
        
        guard let context = CGContext(data: &pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return Color.clear
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let red = CGFloat(pixelData[0]) / 255.0
        let green = CGFloat(pixelData[1]) / 255.0
        let blue = CGFloat(pixelData[2]) / 255.0
        
        let averageColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        if brightness < 0.1 && saturation < 0.1 {
            return Color.red
        }
        
        if brightness < 0.3 {
            brightness = 0.3
        }
        
        let ans = Color(hue: hue, saturation: saturation, brightness: brightness)
        appInfo.cachedColor = UIColor(ans)
        
        return ans
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }

}


struct LCAppSkeletonBanner: View {
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 8)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 70, height: 32)
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.gray.opacity(0.1)))
    }
    
}

