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
    
    @State private var newFolderShow = false
    @State private var newFolderContent = ""
    @State private var newFolerContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var renameFileShow = false
    @State private var renameFileContent = ""
    @State private var renameFileContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var choosingTweak = false
    
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
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            deleteTweakItem(tweakItem: tweakItem)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                }.onDelete { indexSet in
                    deleteTweakItem(indexSet: indexSet)
                }
            }
            Section {
                VStack{
                    if isRoot {
                        Text("This is the global folder. All tweaks put here will be injected to all guest apps. Create a new folder if you use app-specific tweaks.")
                            .foregroundStyle(.gray)
                            .font(.system(size: 12))
                    } else {
                        Text("This is the app-specific folder. Set the tweak folder and the guest app will pick them up recursively.")
                            .foregroundStyle(.gray)
                            .font(.system(size: 12))
                    }

                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(UIColor.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
            }

        }
        .navigationTitle(baseUrl.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if LCUtils.certificatePassword() != nil {
                    Button {
                        
                    } label: {
                        Label("sign", systemImage: "signature")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                        Label("Import Tweak", systemImage: "square.and.arrow.down")
                    }
                    
                    Button {
                        Task { await createNewFolder() }
                    } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("add", systemImage: "plus")
                }
            }
        }
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
        }
        .textFieldAlert(
            isPresented: $newFolderShow,
            title: "Enter the name of new folder",
            text: $newFolderContent,
            placeholder: "",
            action: { newText in
                self.newFolderContent = newText!
                newFolerContinuation?.resume()
            },
            actionCancel: {_ in
                self.newFolderContent = ""
                newFolerContinuation?.resume()
            }
        )
        .textFieldAlert(
            isPresented: $renameFileShow,
            title: "Enter New Name",
            text: $renameFileContent,
            placeholder: "",
            action: { newText in
                self.renameFileContent = newText!
                renameFileContinuation?.resume()
            },
            actionCancel: {_ in
                self.renameFileContent = ""
                renameFileContinuation?.resume()
            }
        )
        .fileImporter(isPresented: $choosingTweak, allowedContentTypes: [.dylib, .lcFramework, .deb], allowsMultipleSelection: true) { result in
            Task { await startInstallTweak(result) }
        }
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
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
        self.renameFileContent = tweakItem.fileUrl.lastPathComponent
        
        await withCheckedContinuation { c in
            self.renameFileContinuation = c
            self.renameFileShow = true
        }
        
        if self.renameFileContent == "" {
            return
        }
        
        let indexToRename = tweakItems.firstIndex(where: { s in
            return s == tweakItem
        })
        guard let indexToRename = indexToRename else {
            return
        }
        let newUrl = self.baseUrl.appendingPathComponent(self.renameFileContent)
        
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
            tweakFolders.insert(self.renameFileContent, at: indexToRename2)
            
        }
    }
    
    func createNewFolder() async {
        self.newFolderContent = ""
        
        await withCheckedContinuation { c in
            self.newFolerContinuation = c
            self.newFolderShow = true
        }
        
        if self.newFolderContent == "" {
            return
        }
        let fm = FileManager()
        let dest = baseUrl.appendingPathComponent(self.newFolderContent)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        tweakItems.append(LCTweakItem(fileUrl: dest, isFolder: true, isFramework: false, isTweak: false))
        if isRoot {
            tweakFolders.append(self.newFolderContent)
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
                    throw "Cannot open \(fileUrl.lastPathComponent), permission denied."
                }
                if(!fileUrl.isFileURL) {
                    throw "\(fileUrl.absoluteString), is not a file."
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
                let error = await LCUtils.signFilesInFolder(url: tmpDir) { p in
                    
                }
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

    }
}
