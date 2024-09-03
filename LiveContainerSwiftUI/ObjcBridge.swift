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
    public static var openUrlStrFunc: ((String) -> Void)?
    
    @objc public static func openWebPage(urlStr: String) {
        if openUrlStrFunc == nil {
            urlStrToOpen = urlStr
        } else {
            openUrlStrFunc!(urlStr)
        }
    }
    
    @objc public static func getRootVC() -> UIViewController {
        let rootView = LCTabView()
        let rootVC = UIHostingController(rootView: rootView)
        return rootVC
    }
}
