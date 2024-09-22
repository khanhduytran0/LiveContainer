//
//  LCTweaksView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LCTweakItem : Hashable {
    let fileUrl: URL
    let isFolder: Bool
    let isFramework: Bool
    let isTweak: Bool
}

struct LCTweakFolderView : View {
    @State var baseUrl : URL
    @State var tweakItems : [LCTweakItem]
    private var isRoot : Bool
    @Binding var tweakFolders : [String]
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    @StateObject private var newFolderInput = InputHelper()
    
    @StateObject private var renameFileInput = InputHelper()
    
    @State private var choosingTweak = false
    
    @State private var isTweakSigning = false

    @State private var llvmOtoolOutsShow = false
    private var llvmOtoolOuts = ""
    
    init(baseUrl: URL, isRoot: Bool = false, tweakFolders: Binding<[String]>) {
        _baseUrl = State(initialValue: baseUrl)
        _tweakFolders = tweakFolders
        self.isRoot = isRoot
        var tmpTweakItems : [LCTweakItem] = []
        let fm = FileManager()
        do {
            let files = try fm.contentsOfDirectory(atPath: baseUrl.path)
            for fileName in files {
                let fileUrl = baseUrl.appendingPathComponent(fileName)
                var isFolder : ObjCBool = false
                fm.fileExists(atPath: fileUrl.path, isDirectory: &isFolder)
                let isFramework = isFolder.boolValue && fileUrl.lastPathComponent.hasSuffix(".framework")
                let isTweak = !isFolder.boolValue && fileUrl.lastPathComponent.hasSuffix(".dylib")
                tmpTweakItems.append(LCTweakItem(fileUrl: fileUrl, isFolder: isFolder.boolValue, isFramework: isFramework, isTweak: isTweak))
            }
            _tweakItems = State(initialValue: tmpTweakItems)
        } catch {
            NSLog("[LC] failed to load tweaks \(error.localizedDescription)")
            _errorShow = State(initialValue: true)
            _errorInfo = State(initialValue: error.localizedDescription)
            _tweakItems = State(initialValue: [])
        }

    }
    
    var body: some View {
        List {
            Section {
                ForEach($tweakItems, id:\.self) { tweakItem in
                    let tweakItem = tweakItem.wrappedValue
                    VStack {
                        if tweakItem.isFramework {
                            Label(tweakItem.fileUrl.lastPathComponent, systemImage: "shippingbox.fill")
                        } else if tweakItem.isFolder {
                            NavigationLink {
                                LCTweakFolderView(baseUrl: tweakItem.fileUrl, isRoot: false, tweakFolders: $tweakFolders)
                            } label: {
                                Label(tweakItem.fileUrl.lastPathComponent, systemImage: "folder.fill")
                            }
                        } else if tweakItem.isTweak {
                            Label(tweakItem.fileUrl.lastPathComponent, systemImage: "building.columns.fill")
                        } else {
                            Label(tweakItem.fileUrl.lastPathComponent, systemImage: "document.fill")
                        }
                    }
                    .contextMenu {
                        Button {
                            Task { await renameTweakItem(tweakItem: tweakItem)}
                        } label: {
                            Label("lc.common.rename".loc, systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            deleteTweakItem(tweakItem: tweakItem)
                        } label: {
                            Label("lc.common.delete".loc, systemImage: "trash")
                        }
                    }

                }.onDelete { indexSet in
                    deleteTweakItem(indexSet: indexSet)
                }
            }
            Section {
                VStack{
                    if isRoot {
                        Text("lc.tweakView.globalFolderDesc".loc)
                            .foregroundStyle(.gray)
                            .font(.system(size: 12))
                    } else {
                        Text("lc.tweakView.appFolderDesc".loc)
                            .foregroundStyle(.gray)
                            .font(.system(size: 12))
                    }

                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(UIColor.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
            }

        }
        .navigationTitle(isRoot ? "lc.tabView.tweaks".loc : baseUrl.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning && LCUtils.certificatePassword() != nil {
                    Button(action: fixCydiaSubstratePath) {
                        Label("fixCSP".loc, systemImage: "pencil.and.outline")
                    }
                }

            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning && LCUtils.certificatePassword() != nil {
                    Button {
                        Task { await signAllTweaks() }
                    } label: {
                        Label("sign".loc, systemImage: "signature")
                    }
                }

            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isTweakSigning {
                    Menu {
                        Button {
                            if choosingTweak {
                                choosingTweak = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                                    choosingTweak = true
                                })
                            } else {
                                choosingTweak = true
                            }
                        } label: {
                            Label("lc.tweakView.importTweak".loc, systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            Task { await createNewFolder() }
                        } label: {
                            Label("lc.tweakView.newFolder".loc, systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("add", systemImage: "plus")
                    }
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
        }
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .alert("llvm-otool", isPresented: $llvmOtoolOutsShow) {
            Button("lc.common.ok".loc, action: {
                llvmOtoolOutsShow = false
            })
        } message: {
            Text(llvmOtoolOuts)
        }
        .textFieldAlert(
            isPresented: $newFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $newFolderInput.initVal,
            placeholder: "",
            action: { newText in
                newFolderInput.close(result: newText)
            },
            actionCancel: {_ in
                newFolderInput.close(result: "")
            }
        )
        .textFieldAlert(
            isPresented: $renameFileInput.show,
            title: "lc.common.enterNewName".loc,
            text: $renameFileInput.initVal,
            placeholder: "",
            action: { newText in
                renameFileInput.close(result: newText)
            },
            actionCancel: {_ in
                renameFileInput.close(result: "")
            }
        )
        .fileImporter(isPresented: $choosingTweak, allowedContentTypes: [.dylib, .lcFramework, .deb], allowsMultipleSelection: true) { result in
            Task { await startInstallTweak(result) }
        }
    }
    
    func deleteTweakItem(indexSet: IndexSet) {
        var indexToRemove : [Int] = []
        let fm = FileManager()
        do {
            for i in indexSet {
                let tweakItem = tweakItems[i]
                try fm.removeItem(at: tweakItem.fileUrl)
                indexToRemove.append(i)
            }
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        if isRoot {
            for iToRemove in indexToRemove {
                tweakFolders.removeAll(where: { s in
                    return s == tweakItems[iToRemove].fileUrl.lastPathComponent
                })
            }
        }

        tweakItems.remove(atOffsets: IndexSet(indexToRemove))
    }
    
    func deleteTweakItem(tweakItem: LCTweakItem) {
        var indexToRemove : Int?
        let fm = FileManager()
        do {

            try fm.removeItem(at: tweakItem.fileUrl)
            indexToRemove = tweakItems.firstIndex(where: { s in
                return s == tweakItem
            })
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        guard let indexToRemove = indexToRemove else {
            return
        }
        tweakItems.remove(at: indexToRemove)
        if isRoot {
            tweakFolders.removeAll(where: { s in
                return s == tweakItem.fileUrl.lastPathComponent
            })
        }
    }
    
    func renameTweakItem(tweakItem: LCTweakItem) async {
        guard let newName = await renameFileInput.open(initVal: tweakItem.fileUrl.lastPathComponent), newName != "" else {
            return
        }
        
        let indexToRename = tweakItems.firstIndex(where: { s in
            return s == tweakItem
        })
        guard let indexToRename = indexToRename else {
            return
        }
        let newUrl = self.baseUrl.appendingPathComponent(newName)
        
        let fm = FileManager()
        do {
            try fm.moveItem(at: tweakItem.fileUrl, to: newUrl)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        tweakItems.remove(at: indexToRename)
        let newTweakItem = LCTweakItem(fileUrl: newUrl, isFolder: tweakItem.isFolder, isFramework: tweakItem.isFramework, isTweak: tweakItem.isTweak)
        tweakItems.insert(newTweakItem, at: indexToRename)
        
        if isRoot {
            let indexToRename2 = tweakFolders.firstIndex(of: tweakItem.fileUrl.lastPathComponent)
            guard let indexToRename2 = indexToRename2 else {
                return
            }
            tweakFolders.remove(at: indexToRename2)
            tweakFolders.insert(newName, at: indexToRename2)
            
        }
    }

    mutating func fixCydiaSubstratePath() {
        llvmOtoolOutsShow = true
        llvmOtoolOuts = ""
        for item in tweakItems {
            if !llvmOtoolOuts.isEmpty {
                llvmOtoolOuts += "\n"
            }
            llvmOtoolOuts += item.fileUrl.lastPathComponent
            llvmOtoolOuts += ":\n"
            llvmOtoolOuts += LCObjcBridge.showMachOFileInfo(filePath: item.fileUrl.absoluteString) 
        }
    }
    
    func signAllTweaks() async {
        do {
            let fm = FileManager()
            let tmpDir = fm.temporaryDirectory.appendingPathComponent("TweakTmp")
            if fm.fileExists(atPath: tmpDir.path) {
                try fm.removeItem(at: tmpDir)
            }
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            
            var tmpPaths : [URL] = []
            // copy items to tmp folders
            for item in tweakItems {
                let tmpPath = tmpDir.appendingPathComponent(item.fileUrl.lastPathComponent)
                tmpPaths.append(tmpPath)
                try fm.copyItem(at: item.fileUrl, to: tmpPath)
            }
            
            if (LCUtils.certificatePassword() != nil) {
                // if in jit-less mode, we need to sign
                isTweakSigning = true
                let error = await LCUtils.signFilesInFolder(url: tmpDir) { p in
                    
                }
                isTweakSigning = false
                if let error = error {
                    throw error
                }
            }
            
            for tmpFile in tmpPaths {
                let toPath = self.baseUrl.appendingPathComponent(tmpFile.lastPathComponent)
                // remove original item and move the signed ones back
                if fm.fileExists(atPath: toPath.path) {
                    try fm.removeItem(at: toPath)
                    try fm.moveItem(at: tmpFile, to: toPath)
                }
            }
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }
    
    func createNewFolder() async {
        guard let newName = await renameFileInput.open(), newName != "" else {
            return
        }
        let fm = FileManager()
        let dest = baseUrl.appendingPathComponent(newName)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        tweakItems.append(LCTweakItem(fileUrl: dest, isFolder: true, isFramework: false, isTweak: false))
        if isRoot {
            tweakFolders.append(newName)
        }
    }
    
    func startInstallTweak(_ result: Result<[URL], any Error>) async {
        do {
            let fm = FileManager()
            let urls = try result.get()
            var tmpPaths : [URL] = []
            // copy selected tweaks to tmp dir first
            let tmpDir = fm.temporaryDirectory.appendingPathComponent("TweakTmp")
            if fm.fileExists(atPath: tmpDir.path) {
                try fm.removeItem(at: tmpDir)
            }
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            
            for fileUrl in urls {
                // handle deb file
                if(!fileUrl.startAccessingSecurityScopedResource()) {
                    throw "lc.tweakView.permissionDenied %@".localizeWithFormat(fileUrl.lastPathComponent)
                }
                if(!fileUrl.isFileURL) {
                    throw "lc.tweakView.notFileError %@".localizeWithFormat(fileUrl.lastPathComponent)
                }
                let toPath = tmpDir.appendingPathComponent(fileUrl.lastPathComponent)
                try fm.copyItem(at: fileUrl, to: toPath)
                tmpPaths.append(toPath)
                LCParseMachO((toPath.path as NSString).utf8String) { path, header in
                    LCPatchAddRPath(path, header);
                }
                fileUrl.stopAccessingSecurityScopedResource()
            }
            
            if (LCUtils.certificatePassword() != nil) {
                // if in jit-less mode, we need to sign
                isTweakSigning = true
                let error = await LCUtils.signFilesInFolder(url: tmpDir) { p in
                    
                }
                isTweakSigning = false
                if let error = error {
                    throw error
                }
            }


            for tmpFile in tmpPaths {
                let toPath = self.baseUrl.appendingPathComponent(tmpFile.lastPathComponent)
                try fm.moveItem(at: tmpFile, to: toPath)

                let isFramework = toPath.lastPathComponent.hasSuffix(".framework")
                let isTweak = toPath.lastPathComponent.hasSuffix(".dylib")
                self.tweakItems.append(LCTweakItem(fileUrl: toPath, isFolder: false, isFramework: isFramework, isTweak: isTweak))
            }
            
            // clean up
            try fm.removeItem(at: tmpDir)
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true            
            return
        }


        
    }
}

struct LCTweaksView: View {
    @Binding var tweakFolders : [String]
    
    var body: some View {
        NavigationView {
            LCTweakFolderView(baseUrl: LCPath.tweakPath, isRoot: true, tweakFolders: $tweakFolders)
        }
        .navigationViewStyle(StackNavigationViewStyle())

    }
}
