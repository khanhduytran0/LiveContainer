//
//  text.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI


@objc public class LCObjcBridge: NSObject {
    public static var urlStrToOpen: String? = nil
    public static var openUrlStrFunc: ((String) async -> Void)?
    
    @objc public static func openWebPage(urlStr: String) {
        if openUrlStrFunc == nil {
            urlStrToOpen = urlStr
        } else {
            Task { await openUrlStrFunc!(urlStr) }
        }
    }
    
    @objc public static func launchApp(bundleId: String) {
        DataManager.shared.model.bundleIdToLaunch = bundleId
    }
    
    @objc public static func getRootVC() -> UIViewController {
        let rootView = LCTabView()
        let rootVC = UIHostingController(rootView: rootView)
        return rootVC
    }
}
