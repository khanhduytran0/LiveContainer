//
//  LCAppBanner.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCAppBanner : View {
    var appInfo: LCAppInfo
    
    
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
            Button {
                // Add this item to a list of favorites.
            } label: {
                Label("Add to Favorites", systemImage: "heart")
            }
            Button {
                // Open Maps and center it on this item.
            } label: {
                Label("Show in Maps", systemImage: "mappin")
            }
        }

        
    }
    
    func runApp() {
        UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        LCUtils.launchToGuestApp()
    }
}
