# LiveContainer
Run unsigned iOS app without actually installing it!
- Allows you to install unlimited apps (10 apps limit of free developer account do not apply here!)
- Codesigning is entirely bypassed (requires JIT), no need to sign your apps before installing.

## How does it work?

### Patching `__PAGEZERO` segment
- Changed vmaddr to `0xFFFFC000` (`0x100000000 - 0x4000`)
- Changed vmsize to `0x4000`

### Patching `NSBundle.mainBundle`
- This property is overwritten with the live app's bundle.

### Patching `@executable_path`
- Call `_dyld_get_image_name(0)` to g et image name pointer.
- Search the pointer in memory and replace with our pointer (can't overwrite its content because it's shorter).

### Bypassing Library Validation
- Derived from [Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)
- JIT is required to bypass codesigning.

### dlopening the executable
- Call `dlopen` with the live app's executable
- Find the entry point
- Jump to the entry point
- The live app's entry point calls `UIApplicationMain` and start up like any other iOS apps.

## Limitations
- Only tested on iOS 14, so some patches might not work on other versions.
- Entitlements from the live app are not applied to the host app. This isn't a big deal since sideloaded apps requires only basic entitlements.
- arm64e is untested. It is recommended to use arm64 binary.
- Only one live app can run at a time. This is much more like 3 apps limit where you have to disable an app to run another (switching between app in LiveContainer is instant).
- Remote push notification might not work. ~~If you have a paid developer account then you don't even have to use LiveContainer~~
- Querying URL schemes might not work(?)

## TODO
- Handle fat binary
- Isolating `NSFileManager.defaultManager` and `NSUserDefaults.userDefaults`
- Auto lock orientation
- Simulate App Group(?)
- More(?)

## License
[Apache License 2.0](https://github.com/khanhduytran0/LiveContainer/blob/main/LICENSE)

## Credits
- [xpnsec's blogpost: Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)
- [LinusHenze's CFastFind](https://github.com/pinauten/PatchfinderUtils/blob/master/Sources/CFastFind/CFastFind.c): [MIT license](https://github.com/pinauten/PatchfinderUtils/blob/master/LICENSE)
