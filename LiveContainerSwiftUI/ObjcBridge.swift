//
//  text.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI


@objc public class LCObjcBridge: NSObject {
    @objc public static func getRootVC() -> UIViewController {
        let rootView = LCTabView()
        let rootVC = UIHostingController(rootView: rootView)
        return rootVC
    }
}
