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
    @State private var confirmAppRemovalShow = false
    @State private var confirmAppFolderRemovalShow = false
    
    var delegate: LCAppBannerDelegate
    @State var confirmAppRemoval = false
    @State var confirmAppFolderRemoval = false
    @State var appRemovalSemaphore = DispatchSemaphore(value: 0)
    @State var appFolderRemovalSemaphore = DispatchSemaphore(value: 0)
    @State var errorShow = false
    @State var errorInfo = ""
    
    var body: some View {

        HStack {
            HStack {
                Image(uiImage: appInfo.icon())
                    .resizable().resizable().frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width:12, height: 12)))
                    

                VStack (alignment: .leading, content: {
                    Text(appInfo.displayName()).font(.system(size: 16)).bold()
                    Text("\(appInfo.version()) - \(appInfo.bundleIdentifier())").font(.system(size: 12)).foregroundColor(Color("FontColor"))
                    Text(appInfo.dataUUID()).font(.system(size: 8)).foregroundColor(Color("FontColor"))
                })
            }
            Spacer()
            Button {
                runApp()
            } label: {
                Text("Run").bold().foregroundColor(.white)
            }
            .padding()
            .frame(height: 32)
            .background(Capsule().fill(Color("FontColor")))
            
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerSize: CGSize(width:22, height: 22)).fill(Color("AppBannerBG")))
        
        
        .contextMenu {
            Button(role: .destructive) {
                uninstall()
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
            Button {
                // Open Maps and center it on this item.
            } label: {
                Label("Show in Maps", systemImage: "mappin")
            }
        }
        
        
        .alert("Confirm Uninstallation", isPresented: $confirmAppRemovalShow) {
            Button(role: .destructive) {
                self.confirmAppRemoval = true
                self.appRemovalSemaphore.signal()
            } label: {
                Text("Uninstall")
            }
            Button("Cancel", role: .cancel) {
                self.confirmAppRemoval = true
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
                self.confirmAppFolderRemoval = true
                self.appFolderRemovalSemaphore.signal()
            }
        } message: {
            Text("Do you also want to delete data folder of \(appInfo.displayName()!)? You can keep it for future use.")
        }

        
    }
    
    func runApp() {
        UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        LCUtils.launchToGuestApp()
    }
    
    func uninstall() {
        DispatchQueue.global().async {
            do {
                self.confirmAppRemovalShow = true;
                self.appRemovalSemaphore.wait()
                if !self.confirmAppRemoval {
                    return
                }
                
                self.confirmAppFolderRemovalShow = true;
                self.appFolderRemovalSemaphore.wait()
                
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
