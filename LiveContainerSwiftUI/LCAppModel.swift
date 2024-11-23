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
        self.isSigningInProgress = false
        if let signError {
            throw signError
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
}
