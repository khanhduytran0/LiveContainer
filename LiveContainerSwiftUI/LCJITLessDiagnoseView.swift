//
//  LCJITLessDiagnose.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/19.
//
import SwiftUI

struct LCJITLessDiagnoseView : View {
    @State var loaded = false
    @State var appGroupId = "Unknown"
    @State var store : Store = .SideStore
    @State var isPatchDetected = false
    @State var certificateDataFound = false
    @State var certificatePasswordFound = false
    @State var appGroupAccessible = false
    @State var certLastUpdateDateStr = "Unknown"
    
    @State var isJITLessTestInProgress = false
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    let storeName = LCUtils.getStoreName()
    
    var body: some View {
        if loaded {
            Form {
                HStack {
                    Text("Bundle Identifier")
                    Spacer()
                    Text(Bundle.main.bundleIdentifier ?? "Unknown")
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("App Group ID")
                    Spacer()
                    Text(appGroupId)
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("App Group Accessible")
                    Spacer()
                    Text(appGroupAccessible ? "YES" : "NO")
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("Store")
                    Spacer()
                    if store == .AltStore {
                        Text("AltStore")
                            .foregroundStyle(.gray)
                    } else {
                        Text("SideStore")
                            .foregroundStyle(.gray)
                    }
                }
                HStack {
                    Text("Patch Detected")
                    Spacer()
                    Text(isPatchDetected ? "YES" : "NO")
                        .foregroundStyle(.gray)
                }
                
                HStack {
                    Text("Certificate Data Found")
                    Spacer()
                    Text(certificateDataFound ? "YES" : "NO")
                        .foregroundStyle(.gray)
                    
                }
                HStack {
                    Text("Certificate Password Found")
                    Spacer()
                    Text(certificatePasswordFound ? "YES" : "NO")
                        .foregroundStyle(.gray)
                }
                
                HStack {
                    Text("Certificate Last Update Date")
                    Spacer()
                    Text(certLastUpdateDateStr)
                        .foregroundStyle(.gray)
                }
                
                Button {
                    testJITLessMode()
                } label: {
                    Text("lc.settings.testJitLess".loc)
                }
                .disabled(isJITLessTestInProgress)
            }
            .navigationTitle("lc.settings.jitlessDiagnose".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onAppear()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                }
            }
            .alert("lc.common.error".loc, isPresented: $errorShow){
            } message: {
                Text(errorInfo)
            }
            .alert("lc.common.success".loc, isPresented: $successShow){
            } message: {
                Text(successInfo)
            }
            
        } else {
            Text("Loading...")
                .onAppear() {
                    onAppear()
                }
        }

    }
    
    func onAppear() {
        appGroupId = LCUtils.appGroupID() ?? "Unknown"
        store = LCUtils.store()
        isPatchDetected = checkIsPatched()
        appGroupAccessible = LCUtils.appGroupPath() != nil
        certificateDataFound = LCUtils.certificateData() != nil
        certificatePasswordFound = LCUtils.certificatePassword() != nil
        if let lastUpdateDate = LCUtils.appGroupUserDefault.object(forKey: "LCCertificateUpdateDate") as? Date {
            let formatter1 = DateFormatter()
            formatter1.dateStyle = .short
            formatter1.timeStyle = .medium
            certLastUpdateDateStr = formatter1.string(from: lastUpdateDate)
        } else {
            certLastUpdateDateStr = "Unknown"
        }
            

        loaded = true
    }
    
    func checkIsPatched() -> Bool {
        let fm = FileManager.default
        guard let appGroupURL = LCUtils.appGroupPath() else {
            return false
        }
        let patchPath : URL
        if LCUtils.store() == .AltStore {
            patchPath = appGroupURL.appendingPathComponent("Apps/com.rileytestut.AltStore/App.app/Frameworks/AltStoreTweak.dylib")
        } else {
            patchPath = appGroupURL.appendingPathComponent("Apps/com.SideStore.SideStore/App.app/Frameworks/AltStoreTweak.dylib")
        }
        return fm.fileExists(atPath: patchPath.path)
    }
    
    func testJITLessMode() {
        if !LCUtils.isAppGroupAltStoreLike() {
            errorInfo = "lc.settings.unsupportedInstallMethod".loc
            errorShow = true
            return;
        }
        
        if !isPatchDetected {
            errorInfo = "lc.settings.error.storeNotPatched %@".localizeWithFormat(storeName)
            errorShow = true
            return;
        }
        isJITLessTestInProgress = true
        LCUtils.validateJITLessSetup(with: Signer(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCDefaultSigner"))!) { success, error in
            if success {
                successInfo = "lc.jitlessSetup.success".loc
                successShow = true
            } else {
                errorInfo = "lc.jitlessSetup.error.testLibLoadFailed %@ %@ %@".localizeWithFormat(storeName, storeName, storeName) + "\n" + (error?.localizedDescription ?? "")
                errorShow = true
            }
            isJITLessTestInProgress = false
        }
    
    }
}
