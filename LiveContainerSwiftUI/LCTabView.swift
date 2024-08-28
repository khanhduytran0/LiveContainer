//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCTabView: View {
    @State var errorShow = false
    @State var errorInfo = ""
    
    var body: some View {
        TabView {
            LCAppListView()
                .tabItem {
                    Label("Apps", systemImage: "square.stack.3d.up.fill")
                }
            LCSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .alert(isPresented: $errorShow){
            Alert(title: Text("Error"), message: Text(errorInfo))
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



#Preview {
    LCTabView()
}
