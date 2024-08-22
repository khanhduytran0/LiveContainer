//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCTabView: View {
    var body: some View {
        TabView {
            LCAppListView()
                .tabItem {
                    Label("Apps", systemImage: "square.stack.3d.up.fill")
                }
            

        }
    }
}



#Preview {
    LCTabView()
}
