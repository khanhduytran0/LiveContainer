# LiveContainer
Run iOS app without actually installing it!
- Allows you to install unlimited apps (10 apps limit of free developer account do not apply here!), have multiple versions of an app installed and multiple data containers.
- When JIT is available, codesign is entirely bypassed, no need to sign your apps before installing. Otherwise, app will be signed with the same certificate used by LiveContainer.

## Compatibility
Unfortunately, not all apps work in LiveContainer, so we have a [compatibility list](https://github.com/khanhduytran0/LiveContainer/labels/compatibility) to tell if there is apps that have issues. If they aren't on this list, then it's likely going run. However, if it doesn't work, please make an [issue](https://github.com/khanhduytran0/LiveContainer/issues/new/choose) about it.

## Building
```
export THEOS=/path/to/theos
git submodule update --init --recursive
make package
```

## Project structure
### Main executable
- Core of LiveContainer
- Contains the logic of setting up guest environment and loading guest app.
- If no app is selected, it loads LiveContainerUI.

### LiveContainerUI
- LiveContainer's default implementation of app manager, tweak manager and settings UI. 
- If you're making a mod loader, you can provide your own.

### TweakLoader
- A simple tweak injector, which loads CydiaSubstrate and load tweaks.
- Injected to every app you install in LiveContainer.

## Usage
Requires AltStore or SideStore
- Build from source or get prebuilt ipa in [the Actions tab](https://github.com/khanhduytran0/LiveContainer/actions)
- Open LiveContainer, tap the plus icon in the upper right hand corner and select IPA files to install.
- Choose the app you want to open in the next launch.

### With JIT (requires SideStore)
- Tap the play icon, it will jump to SideStore and exit.
- In SideStore, hold down LiveContainer and tap `Enable JIT`. If you have SideStore build supporting JIT URL scheme, it jumps back to LiveContainer with JIT enabled and the guest app is ready to use.

### Without JIT
> [!NOTE]
> You need to setup JIT-less mode once. This can be done by pressing "Setup JIT-less" and following instructions.

- Tap the play icon, it will attempt to restart LiveContainer with guest app loaded.

### Installing external tweaks
LiveContainer comes with its own TweakLoader, which automatically load CydiaSubstrate and tweaks. TweakLoader is injected to every app you install. You can override `TweakLoader.dylib` symlink with your own implementation if you wish.

.dylib files in `Tweaks` folder are global, they are loaded to all apps. You can create app-specific tweaks folder and switch between them instantly.

To install tweaks, you can use the built-in tweak manager in LiveContainer, which will automatically sign tweaks as you import. Otherwise, you can manually add them and then use the tweak manager to sign them.

## How does it work?

### Patching guest executable
- Patch `__PAGEZERO` segment:
  + Change `vmaddr` to `0xFFFFC000` (`0x100000000 - 0x4000`)
  + Change `vmsize` to `0x4000`
- Change `MH_EXECUTE` to `MH_DYLIB`.
- Inject a load command to load `TweakLoader.dylib`

### Patching `@executable_path`
- Call `_NSGetExecutablePath` with an invalid buffer pointer input -> SIGSEGV
- Do some [magic stuff](https://github.com/khanhduytran0/LiveContainer/blob/5ef1e6a/main.m#L74-L115) to overwrite the contents of executable_path.

### Patching `NSBundle.mainBundle`
- This property is overwritten with the guest app's bundle.

### Bypassing Library Validation
- JIT is optional to bypass codesigning. In JIT-less mode, all executables are signed so this does not apply.
- Derived from [Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)

### dlopening the executable
- Call `dlopen` with the guest app's executable
- TweakLoader loads all tweaks in the selected folder
- Find the entry point
- Jump to the entry point
- The guest app's entry point calls `UIApplicationMain` and start up like any other iOS apps.

## Limitations
- Entitlements from the guest app are not applied to the host app. This isn't a big deal since sideloaded apps requires only basic entitlements.
- App Permissions are globally applied.
- Guest app containers are not sandboxed. This means one guest app can access other guest apps' data.
- Only one guest app can run at a time. This is much more like 3 apps limit where you have to disable an app to run another (switching between app in LiveContainer is instant).
- Remote push notification might not work. ~~If you have a paid developer account then you don't even have to use LiveContainer~~
- Querying custom URL schemes might not work(?)
- File picker might be broken for unknown reasons.

## TODO
- Isolate Keychain per app
- Use ChOma instead of custom MachO parser

## License
[Apache License 2.0](https://github.com/khanhduytran0/LiveContainer/blob/main/LICENSE)

## Credits
- [xpn's blogpost: Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)
- [LinusHenze's CFastFind](https://github.com/pinauten/PatchfinderUtils/blob/master/Sources/CFastFind/CFastFind.c): [MIT license](https://github.com/pinauten/PatchfinderUtils/blob/master/LICENSE)
- [fishhook](https://github.com/facebook/fishhook): [BSD 3-Clause license](https://github.com/facebook/fishhook/blob/main/LICENSE)
- [MBRoundProgressView](https://gist.github.com/saturngod/1224648)
- @haxi0 for icon
- @Vishram1123 for the initial shortcut implementation.
