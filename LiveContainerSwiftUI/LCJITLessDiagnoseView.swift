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
    @State var certLastUpdateDateStr : String? = nil
    
    @State var isJITLessTestInProgress = false
    
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""
    
    let storeName = LCUtils.getStoreName()
    
    var body: some View {
        if loaded {
            Form {
                Section {
                    HStack {
                        Text("lc.jitlessDiag.bundleId".loc)
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "lc.common.unknown".loc)
                            .foregroundStyle(.gray)
                    }
                    HStack {
                        Text("lc.jitlessDiag.appGroupId".loc)
                        Spacer()
                        Text(appGroupId)
                            .foregroundStyle(appGroupId == "Unknown" ? .red : .green)
                    }
                    HStack {
                        Text("lc.jitlessDiag.appGroupAccessible".loc)
                        Spacer()
                        Text(appGroupAccessible ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(appGroupAccessible ? .green : .red)
                    }
                    HStack {
                        Text("lc.jitlessDiag.store".loc)
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
                        Text("lc.jitlessDiag.patchDetected".loc)
                        Spacer()
                        Text(isPatchDetected ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(isPatchDetected ? .green : .red)
                    }
                    
                    HStack {
                        Text("lc.jitlessDiag.certDataFound".loc)
                        Spacer()
                        Text(certificateDataFound ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(certificateDataFound ? .green : .red)
                        
                    }
                    HStack {
                        Text("lc.jitlessDiag.certPassFound".loc)
                        Spacer()
                        Text(certificatePasswordFound ? "lc.common.yes".loc : "lc.common.no".loc)
                            .foregroundStyle(certificatePasswordFound ? .green : .red)
                    }
                    
                    HStack {
                        Text("lc.jitlessDiag.certLastUpdate".loc)
                        Spacer()
                        if let certLastUpdateDateStr {
                            Text(certLastUpdateDateStr)
                                .foregroundStyle(.green)
                        } else {
                            Text("lc.common.unknown".loc)
                                .foregroundStyle(.red)
                        }

                    }
                    
                    Button {
                        testJITLessMode()
                    } label: {
                        Text("lc.settings.testJitLess".loc)
                    }
                    .disabled(isJITLessTestInProgress)
                }
                
                Section {
                    Button {
                        getHelp()
                    } label: {
                        Text("lc.jitlessDiag.getHelp".loc)
                    }
                }

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
            Text("lc.common.loading".loc)
                .onAppear() {
                    onAppear()
                }
        }

    }
    
    func onAppear() {
        appGroupId = LCUtils.appGroupID() ?? "lc.common.unknown".loc
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
    
    func getHelp() {
        UIApplication.shared.open(URL(string: "https://github.com/khanhduytran0/LiveContainer/issues/265#issuecomment-2558409380")!)
    }
}
