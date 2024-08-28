//
//  LCSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCSettingsView: View {
    @State var errorShow = false
    @State var errorInfo = ""
    
    @State var isJitLessEnabled = false
    @State var isAltCertIgnored = false
    @State var frameShortIcon = false
    @State var silentSwitchApp = false
    @State var injectToLCItelf = false
    
    init() {
        _isJitLessEnabled = State(initialValue: LCUtils.certificatePassword() != nil)
        _isAltCertIgnored = State(initialValue: UserDefaults.standard.bool(forKey: "LCIgnoreALTCertificate"))
        _frameShortIcon = State(initialValue: UserDefaults.standard.bool(forKey: "LCFrameShortcutIcons"))
        _silentSwitchApp = State(initialValue: UserDefaults.standard.bool(forKey: "LCSwitchAppWithoutAsking"))
        _injectToLCItelf = State(initialValue: UserDefaults.standard.bool(forKey: "LCLoadTweaksToSelf"))
    }
    
    var body: some View {
        NavigationView {
            Form {
                
                Section{
                    Button {
                        setupJitLess()
                    } label: {
                        if isJitLessEnabled {
                            Text("Renew JIT-less certificate")
                        } else {
                            Text("Setup JIT-less certificate")
                        }
                    }
                    
                } header: {
                    Text("JIT-Less")
                } footer: {
                    Text("JIT-less allows you to use LiveContainer without having to enable JIT. Requires AltStore or SideStore.")
                }
                Section {
                    Toggle(isOn: $isAltCertIgnored) {
                        Text("Ignore ALTCertificate.p12")
                    }
                } footer: {
                    Text("If you see frequent re-sign, enable this option.")
                }
                
                Section{
                    Toggle(isOn: $frameShortIcon) {
                        Text("Frame Short Icon")
                    }
                } header: {
                    Text("Miscellaneous")
                } footer: {
                    Text("Frame shortcut icons with LiveContainer icon.")
                }
                
                Section {
                    Toggle(isOn: $silentSwitchApp) {
                        Text("Switch App Without Asking")
                    }
                } footer: {
                    Text("By default, LiveContainer asks you before switching app. Enable this to switch app immediately. Any unsaved data will be lost.")
                }
                
                Section {
                    Toggle(isOn: $injectToLCItelf) {
                        Text("Load Tewaks to LiveContainer Itself")
                    }
                } footer: {
                    Text("Place your tweaks into the global “Tweaks” folder and LiveContainer will pick them up.")
                }
                
                VStack{
                    Text(LCUtils.getVersionInfo())
                        .foregroundStyle(.gray)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(UIColor.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
            }
            .navigationBarTitle("Settings")
            .alert(isPresented: $errorShow){
                Alert(title: Text("Error"), message: Text(errorInfo))
            }
            
            .onChange(of: isAltCertIgnored) { newValue in
                saveItem(key: "LCIgnoreALTCertificate", val: newValue)
            }
            .onChange(of: silentSwitchApp) { newValue in
                saveItem(key: "LCSwitchAppWithoutAsking", val: newValue)
            }
            .onChange(of: frameShortIcon) { newValue in
                saveItem(key: "LCFrameShortcutIcons", val: newValue)
            }
            .onChange(of: injectToLCItelf) { newValue in
                saveItem(key: "LCLoadTweaksToSelf", val: newValue)
            }
        }
        
    }
    
    func saveItem(key: String, val: Bool) {
        UserDefaults.standard.setValue(val, forKey: key)
    }
    
    func setupJitLess() {
        if !LCUtils.isAppGroupAltStoreLike() {
            errorInfo = "Unsupported installation method. Please use AltStore or SideStore to setup this feature."
            errorShow = true
            return;
        }
        do {
            let packedIpaUrl = try LCUtils.archiveIPA(withSetupMode: true)
            let storeInstallUrl = String(format: LCUtils.storeInstallURLScheme(), packedIpaUrl.absoluteString)
            UIApplication.shared.open(URL(string: storeInstallUrl)!)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    
    }

}
