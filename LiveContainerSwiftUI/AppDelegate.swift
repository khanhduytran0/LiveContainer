import UIKit
import SwiftUI

@objc class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
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
    
    private static func openWebPage(urlStr: String) {
        if openUrlStrFunc == nil {
            urlStrToOpen = urlStr
        } else {
            Task { await openUrlStrFunc!(urlStr) }
        }
    }
    
    private static func launchApp(bundleId: String) {
        if launchAppFunc == nil {
            bundleToLaunch = bundleId
        } else {
            Task { await launchAppFunc!(bundleId) }
        }
    }
    
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        let contentView = LCTabView()
        window.rootViewController = UIHostingController(rootView: contentView)
        window.makeKeyAndVisible()
        return true
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        if url.host == "open-web-page" {
            if let urlComponent = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItem = urlComponent.queryItems?.first {
                if queryItem.value?.isEmpty ?? true {
                    return true
                }
                
                if let decodedData = Data(base64Encoded: queryItem.value ?? ""),
                   let decodedUrl = String(data: decodedData, encoding: .utf8) {
                    AppDelegate.openWebPage(urlStr: decodedUrl)
                }
            }
        } else if url.host == "livecontainer-launch" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "bundle-name", let bundleId = queryItem.value {
                        AppDelegate.launchApp(bundleId: bundleId)
                        break
                    }
                }
            }
        }
        
        return false
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Fix launching app if user opens JIT waiting dialog and kills the app. Won't trigger normally.
        UserDefaults.standard.removeObject(forKey: "selected")
        
        if (UserDefaults.standard.object(forKey: "LCLastLanguages") != nil) {
            // recover livecontainer's own language
            UserDefaults.standard.set(UserDefaults.standard.object(forKey: "LCLastLanguages"), forKey: "AppleLanguages")
            UserDefaults.standard.removeObject(forKey: "LCLastLanguages")
        }
    }
    
}
