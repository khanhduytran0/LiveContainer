//
//  Shared.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/22.
//

import SwiftUI
import UniformTypeIdentifiers

struct LCPath {
    public static let docPath = {
        let fm = FileManager()
        return fm.urls(for: .documentDirectory, in: .userDomainMask).last!
    }()
    public static let bundlePath = docPath.appendingPathComponent("Applications")
    public static let dataPath = docPath.appendingPathComponent("Data/Application")
    public static let tweakPath = docPath.appendingPathComponent("Tweaks")
    
    public static let lcGroupDocPath = {
        let fm = FileManager()
        // it seems that Apple don't want to create one for us, so we just borrow our Store's
        if let appGroupPathUrl = LCUtils.appGroupPath() {
            return appGroupPathUrl.appendingPathComponent("LiveContainer")
        } else if let appGroupPathUrl =
                    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.SideStore.SideStore") {
            return appGroupPathUrl.appendingPathComponent("LiveContainer")
        } else {
            return docPath
        }
    }()
    public static let lcGroupBundlePath = lcGroupDocPath.appendingPathComponent("Applications")
    public static let lcGroupDataPath = lcGroupDocPath.appendingPathComponent("Data/Application")
    public static let lcGroupTweakPath = lcGroupDocPath.appendingPathComponent("Tweaks")
    
    public static func ensureAppGroupPaths() throws {
        let fm = FileManager()
        if !fm.fileExists(atPath: LCPath.lcGroupBundlePath.path) {
            try fm.createDirectory(at: LCPath.lcGroupBundlePath, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: LCPath.lcGroupDataPath.path) {
            try fm.createDirectory(at: LCPath.lcGroupDataPath, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: LCPath.lcGroupTweakPath.path) {
            try fm.createDirectory(at: LCPath.lcGroupTweakPath, withIntermediateDirectories: true)
        }
    }
}

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa")!
    static let dylib = UTType(filenameExtension: "dylib")!
    static let deb = UTType(filenameExtension: "deb")!
    static let lcFramework = UTType(filenameExtension: "framework", conformingTo: .package)!
}

// https://stackoverflow.com/questions/56726663/how-to-add-a-textfield-to-alert-in-swiftui
extension View {

    public func textFieldAlert(
        isPresented: Binding<Bool>,
        title: String,
        text: Binding<String>,
        placeholder: String = "",
        action: @escaping (String?) -> Void,
        actionCancel: @escaping (String?) -> Void
    ) -> some View {
        self.modifier(TextFieldAlertModifier(isPresented: isPresented, title: title, text: text, placeholder: placeholder, action: action, actionCancel: actionCancel))
    }
    
}

public struct TextFieldAlertModifier: ViewModifier {

    @State private var alertController: UIAlertController?

    @Binding var isPresented: Bool

    let title: String
    let text: Binding<String>
    let placeholder: String
    let action: (String?) -> Void
    let actionCancel: (String?) -> Void

    public func body(content: Content) -> some View {
        content.onChange(of: isPresented) { isPresented in
            if isPresented, alertController == nil {
                let alertController = makeAlertController()
                self.alertController = alertController
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    return
                }
                scene.windows.first?.rootViewController?.present(alertController, animated: true)
            } else if !isPresented, let alertController = alertController {
                alertController.dismiss(animated: true)
                self.alertController = nil
            }
        }
    }

    private func makeAlertController() -> UIAlertController {
        let controller = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        controller.addTextField {
            $0.placeholder = self.placeholder
            $0.text = self.text.wrappedValue
            $0.clearButtonMode = .always
        }
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.actionCancel(nil)
            shutdown()
        })
        controller.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.action(controller.textFields?.first?.text)
            shutdown()
        })
        return controller
    }

    private func shutdown() {
        isPresented = false
        alertController = nil
    }

}

struct SiteAssociationDetailItem : Codable {
    var appID: String?
    var appIDs: [String]?
    
    func getBundleIds() -> [String] {
        var ans : [String] = []
        // get rid of developer id
        if let appID = appID, appID.count > 11 {
            let index = appID.index(appID.startIndex, offsetBy: 11)
            let modifiedString = String(appID[index...])
            ans.append(modifiedString)
        }
        if let appIDs = appIDs {
            for appID in appIDs {
                if appID.count > 11 {
                    let index = appID.index(appID.startIndex, offsetBy: 11)
                    let modifiedString = String(appID[index...])
                    ans.append(modifiedString)
                }
            }
        }
        return ans
    }
}

struct AppLinks : Codable {
    var details : [SiteAssociationDetailItem]?
}

struct SiteAssociation : Codable {
    var applinks: AppLinks?
}

extension LCUtils {
    public static func signFilesInFolder(url: URL, onProgressCreated: (Progress) -> Void) async -> String? {
        let fm = FileManager()
        var ans : String? = nil
        let codesignPath = url.appendingPathComponent("_CodeSignature")
        let provisionPath = url.appendingPathComponent("embedded.mobileprovision")
        let tmpExecPath = url.appendingPathComponent("LiveContainer.tmp")
        let tmpInfoPath = url.appendingPathComponent("Info.plist")
        var info = Bundle.main.infoDictionary!;
        info["CFBundleExecutable"] = "LiveContainer.tmp";
        let nsInfo = info as NSDictionary
        nsInfo.write(to: tmpInfoPath, atomically: true)
        do {
            try fm.copyItem(at: Bundle.main.executableURL!, to: tmpExecPath)
        } catch {
            return nil
        }
        
        await withCheckedContinuation { c in
            let progress = LCUtils.signAppBundle(url) { success, error in
                do {
                    if let error = error {
                        ans = error.localizedDescription
                    }
                    try fm.removeItem(at: codesignPath)
                    try fm.removeItem(at: provisionPath)
                    try fm.removeItem(at: tmpExecPath)
                    try fm.removeItem(at: tmpInfoPath)
                } catch {
                    ans = error.localizedDescription
                }
                c.resume()
            }
            guard let progress = progress else {
                ans = "Failed to initiate bundle signing."
                c.resume()
                return
            }
            onProgressCreated(progress)
        }
        return ans

    }
}
