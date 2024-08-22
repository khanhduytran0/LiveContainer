//
//  ContentView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI

struct LCAppListView : View {
    var docPath: URL
    var bundlePath: URL
    var apps: [LCAppInfo]
    
    init() {
        NSLog("[NMSL] App list init!")
        let fm = FileManager()
        self.docPath = fm.urls(for: .documentDirectory, in: .userDomainMask).last!
        self.bundlePath = self.docPath.appendingPathComponent("Applications")
        do {
            try fm.createDirectory(at: self.bundlePath, withIntermediateDirectories: true)
            let appDirs = try fm.contentsOfDirectory(atPath: self.bundlePath.path)
            self.apps = []
            for appDir in appDirs {
                if !appDir.hasSuffix(".app") {
                    continue
                }
                var newApp = LCAppInfo(bundlePath: "\(self.bundlePath.path)/\(appDir)")!
                newApp.relativeBundlePath = appDir
                self.apps.append(newApp)
            }
        } catch {
            self.apps = []
            NSLog("[NMSL] error:\(error)")
        }
        
    }
        
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    ForEach(apps, id: \.self) { app in
                        LCAppBanner(appInfo: app)
                    }
                }
                .padding()
            }
            
            
            .navigationTitle("My Apps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add", systemImage: "plus", action: {
                        
                    })
                }
            }

            
        }
    }
}

#Preview {
    LCAppListView()
}
