//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCTabView: View {
    @State var apps: [LCAppInfo]
    @State var appDataFolderNames: [String]
    @State var tweakFolderNames: [String]
    
    @State var errorShow = false
    @State var errorInfo = ""
    
    init() {
        let fm = FileManager()
        var tempAppDataFolderNames : [String] = []
        var tempTweakFolderNames : [String] = []
        
        var tempApps: [LCAppInfo] = []

        do {
            // load apps
            try fm.createDirectory(at: LCPath.bundlePath, withIntermediateDirectories: true)
            let appDirs = try fm.contentsOfDirectory(atPath: LCPath.bundlePath.path)
            for appDir in appDirs {
                if !appDir.hasSuffix(".app") {
                    continue
                }
                let newApp = LCAppInfo(bundlePath: "\(LCPath.bundlePath.path)/\(appDir)")!
                newApp.relativeBundlePath = appDir
                tempApps.append(newApp)
            }
            // load document folders
            try fm.createDirectory(at: LCPath.dataPath, withIntermediateDirectories: true)
            let dataDirs = try fm.contentsOfDirectory(atPath: LCPath.dataPath.path)
            for dataDir in dataDirs {
                let dataDirUrl = LCPath.dataPath.appendingPathComponent(dataDir)
                if !dataDirUrl.hasDirectoryPath {
                    continue
                }
                tempAppDataFolderNames.append(dataDir)
            }
            
            // load tweak folders
            try fm.createDirectory(at: LCPath.tweakPath, withIntermediateDirectories: true)
            let tweakDirs = try fm.contentsOfDirectory(atPath: LCPath.tweakPath.path)
            for tweakDir in tweakDirs {
                let tweakDirUrl = LCPath.tweakPath.appendingPathComponent(tweakDir)
                if !tweakDirUrl.hasDirectoryPath {
                    continue
                }
                tempTweakFolderNames.append(tweakDir)
            }
        } catch {
            NSLog("[LC] error:\(error)")
        }
        _apps = State(initialValue: tempApps)
        _appDataFolderNames = State(initialValue: tempAppDataFolderNames)
        _tweakFolderNames = State(initialValue: tempTweakFolderNames)
    }
    
    var body: some View {
        TabView {
            LCAppListView(apps: $apps, appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                .tabItem {
                    Label("Apps", systemImage: "square.stack.3d.up.fill")
                }
            LCTweaksView(tweakFolders: $tweakFolderNames)
                .tabItem{
                    Label("Tweaks", systemImage: "wrench.and.screwdriver")
                }
            
            LCSettingsView(apps: $apps, appDataFolderNames: $appDataFolderNames)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .alert(isPresented: $errorShow){
            Alert(title: Text("Error"), message: Text(errorInfo))
        }.onAppear() {
            checkLastLaunchError()
        }
    }
    
    func checkLastLaunchError() {
        guard let errorStr = UserDefaults.standard.string(forKey: "error") else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        errorShow = true
    }
}
