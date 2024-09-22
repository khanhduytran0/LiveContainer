//
//  text.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI


@objc public class LCObjcBridge: NSObject {
    private static var urlStrToOpen: String? = nil
    private static var openUrlStrFunc: ((String) async -> Void)?
    private static var bundleToLaunch: String? = nil
    private static var launchAppFunc: ((String) async -> Void)?
    
    public static func setOpenUrlStrFunc(handler: @escaping ((String) async -> Void)){
        self.openUrlStrFunc = handler
        if let urlStrToOpen = self.urlStrToOpen {
            Task { await handler(urlStrToOpen) }
            self.urlStrToOpen = nil
        } else if let urlStr = UserDefaults.standard.string(forKey: "webPageToOpen") {
            UserDefaults.standard.removeObject(forKey: "webPageToOpen")
            Task { await handler(urlStr) }
        }
    }
    
    public static func setLaunchAppFunc(handler: @escaping ((String) async -> Void)){
        self.launchAppFunc = handler
        if let bundleToLaunch = self.bundleToLaunch {
            Task { await handler(bundleToLaunch) }
            self.bundleToLaunch = nil
        }
    }
    
    @objc public static func openWebPage(urlStr: String) {
        if openUrlStrFunc == nil {
            urlStrToOpen = urlStr
        } else {
            Task { await openUrlStrFunc!(urlStr) }
        }
    }

    @objc public static func showMachOFileInfo(filePath: String) -> String {
        return exec_llvm_objdump(filePath)
    }
    
    @objc public static func launchApp(bundleId: String) {
        if launchAppFunc == nil {
            bundleToLaunch = bundleId
        } else {
            Task { await launchAppFunc!(bundleId) }
        }
    }
    
    @objc public static func getRootVC() -> UIViewController {
        let rootView = LCTabView()
        let rootVC = UIHostingController(rootView: rootView)
        return rootVC
    }
}
