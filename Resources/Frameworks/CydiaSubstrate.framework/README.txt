Extracted from http://apt.saurik.com/debs/mobilesubstrate_0.9.6301_iphoneos-arm.deb
$ lipo -thin arm64 -output CydiaSubstrate CydiaSubstrate
$ install_name_tool -id @rpath/CydiaSubstrate.framework/CydiaSubstrate CydiaSubstrate
