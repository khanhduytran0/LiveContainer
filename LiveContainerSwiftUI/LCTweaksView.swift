//
//  LCTweaksView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

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
            ForEach($tweakItems, id:\.self) { tweakItem in
                let tweakItem = tweakItem.wrappedValue
                if tweakItem.isFramework {
                    if #available(iOS 17.0, *) {
                        Label(tweakItem.fileUrl.lastPathComponent, systemImage: "duffle.bag.fill")
                    } else {
                        Label(tweakItem.fileUrl.lastPathComponent, systemImage: "shippingbox.fill")
                    }
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
            }.onDelete { indexSet in
                deleteTweakItem(indexSet: indexSet)
            }
        }
        .navigationTitle(baseUrl.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    
                } label: {
                    Label("sign", systemImage: "signature")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await createNewFolder() }
                    } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        
                    } label: {
                        Label("Import Tweak", systemImage: "square.and.arrow.down")
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
}

struct LCTweaksView: View {
    @Binding var tweakFolders : [String]
    
    var body: some View {
        NavigationView {
            LCTweakFolderView(baseUrl: LCPath.tweakPath, isRoot: true, tweakFolders: $tweakFolders)
        }

    }
}
