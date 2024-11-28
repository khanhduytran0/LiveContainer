import Foundation

protocol LCAppModelDelegate {
    func closeNavigationView()
    func changeAppVisibility(app : LCAppModel)
}

class LCAppModel: ObservableObject, Hashable {
    
    @Published var appInfo : LCAppInfo
    
    @Published var isAppRunning = false
    @Published var isSigningInProgress = false
    @Published var signProgress = 0.0
    private var observer : NSKeyValueObservation?
    
    @Published var uiIsJITNeeded : Bool
    @Published var uiIsHidden : Bool
    @Published var uiIsLocked : Bool
    @Published var uiIsShared : Bool
    @Published var uiDataFolder : String?
    @Published var uiTweakFolder : String?
    @Published var uiDoSymlinkInbox : Bool
    @Published var uiBypassAssertBarrierOnQueue : Bool
    @Published var uiSigner : Signer
    @Published var uiSelectedLanguage : String
    @Published var supportedLanaguages : [String]?
    
    var jitAlert : YesNoHelper? = nil
    
    var delegate : LCAppModelDelegate?
    
    init(appInfo : LCAppInfo, delegate: LCAppModelDelegate? = nil) {
        self.appInfo = appInfo
        self.delegate = delegate

        if !appInfo.isLocked && appInfo.isHidden {
            appInfo.isLocked = true
        }
        
        self.uiIsJITNeeded = appInfo.isJITNeeded
        self.uiIsHidden = appInfo.isHidden
        self.uiIsLocked = appInfo.isLocked
        self.uiIsShared = appInfo.isShared
        self.uiSelectedLanguage = appInfo.selectedLanguage ?? ""
        self.uiDataFolder = appInfo.getDataUUIDNoAssign()
        self.uiTweakFolder = appInfo.tweakFolder()
        self.uiDoSymlinkInbox = appInfo.doSymlinkInbox
        self.uiBypassAssertBarrierOnQueue = appInfo.bypassAssertBarrierOnQueue
        self.uiSigner = appInfo.signer
    }
    
    static func == (lhs: LCAppModel, rhs: LCAppModel) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    func runApp() async throws{
        if isAppRunning {
            return
        }
        
        if let runningLC = LCUtils.getAppRunningLCScheme(bundleId: self.appInfo.relativeBundlePath) {
            let openURL = URL(string: "\(runningLC)://livecontainer-launch?bundle-name=\(self.appInfo.relativeBundlePath!)")!
            if await UIApplication.shared.canOpenURL(openURL) {
                await UIApplication.shared.open(openURL)
                return
            }
        }
        isAppRunning = true
        defer {
            isAppRunning = false
        }
        try await signApp(force: false)
        
        UserDefaults.standard.set(self.appInfo.relativeBundlePath, forKey: "selected")
        if let selectedLanguage = self.appInfo.selectedLanguage {
            // save livecontainer's own language
            UserDefaults.standard.set(UserDefaults.standard.object(forKey: "AppleLanguages"), forKey:"LCLastLanguages")
            // set user selected language
            UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
        }
        
        if appInfo.isJITNeeded {
            await self.jitLaunch()
        } else {
            LCUtils.launchToGuestApp()
        }

        isAppRunning = false
        
    }
    
    func forceResign() async throws {
        if isAppRunning {
            return
        }
        isAppRunning = true
        defer {
            DispatchQueue.main.async {
                self.isAppRunning = false
            }

        }
        try await signApp(force: true)
    }
    
    func signApp(force: Bool = false) async throws {
        var signError : String? = nil
        defer {
            DispatchQueue.main.async {
                self.isSigningInProgress = false
            }
        }
        
        await withCheckedContinuation({ c in
            appInfo.patchExecAndSignIfNeed(completionHandler: { error in
                signError = error;
                c.resume()
            }, progressHandler: { signProgress in
                guard let signProgress else {
                    return
                }
                self.isSigningInProgress = true
                self.observer = signProgress.observe(\.fractionCompleted) { p, v in
                    DispatchQueue.main.async {
                        self.signProgress = signProgress.fractionCompleted
                    }
                }
            }, forceSign: force)
        })
        if let signError {
            throw signError
        }
        
        // sign its tweak
        guard let tweakFolder = appInfo.tweakFolder() else {
            return
        }
        
        let tweakFolderUrl : URL
        if(appInfo.isShared) {
            tweakFolderUrl = LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder)
        } else {
            tweakFolderUrl = LCPath.tweakPath.appendingPathComponent(tweakFolder)
        }
        try await LCUtils.signTweaks(tweakFolderUrl: tweakFolderUrl, force: force, signer: self.appInfo.signer) { p in
            DispatchQueue.main.async {
                self.isSigningInProgress = true
            }
        }
        
        // sign global tweak
        try await LCUtils.signTweaks(tweakFolderUrl: LCPath.tweakPath, force: force, signer: self.appInfo.signer) { p in
            DispatchQueue.main.async {
                self.isSigningInProgress = true
            }
        }
        
        
    }
    
    func jitLaunch() async {
        LCUtils.askForJIT()

        guard let result = await jitAlert?.open(), result else {
            UserDefaults.standard.removeObject(forKey: "selected")
            return
        }
        LCUtils.launchToGuestApp()

    }

    func setLocked(newLockState: Bool) async {
        // if locked state in appinfo already match with the new state, we just the change
        if appInfo.isLocked == newLockState {
            return
        }
        
        if newLockState {
            appInfo.isLocked = true
        } else {
            // authenticate before cancelling locked state
            do {
                let result = try await LCUtils.authenticateUser()
                if !result {
                    uiIsLocked = true
                    return
                }
            } catch {
                uiIsLocked = true
                return
            }
            
            // auth pass, we need to cancel app's lock and hidden state
            appInfo.isLocked = false
            if appInfo.isHidden {
                await toggleHidden()
            }
        }
    }
    
    func toggleHidden() async {
        delegate?.closeNavigationView()
        if appInfo.isHidden {
            appInfo.isHidden = false
            uiIsHidden = false
        } else {
            appInfo.isHidden = true
            uiIsHidden = true
        }
        delegate?.changeAppVisibility(app: self)
    }
    
    func loadSupportedLanguages() throws {
        let fm = FileManager.default
        if supportedLanaguages != nil {
            return
        }
        supportedLanaguages = []
        let fileURLs = try fm.contentsOfDirectory(at: URL(fileURLWithPath: appInfo.bundlePath()!) , includingPropertiesForKeys: nil)
        for fileURL in fileURLs {
            let attributes = try fm.attributesOfItem(atPath: fileURL.path)
            let fileType = attributes[.type] as? FileAttributeType
            if(fileType == .typeDirectory && fileURL.lastPathComponent.hasSuffix(".lproj")) {
                supportedLanaguages?.append(fileURL.deletingPathExtension().lastPathComponent)
            }
        }
        
    }
}
