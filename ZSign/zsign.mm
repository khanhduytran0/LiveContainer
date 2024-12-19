#include "zsign.hpp"
#include "common/common.h"
#include "common/json.h"
#include "openssl.h"
#include "macho.h"
#include "bundle.h"
#include <libgen.h>
#include <dirent.h>
#include <getopt.h>
#include <stdlib.h>

NSString* getTmpDir() {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	return [[[paths objectAtIndex:0] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"tmp"];
}

extern "C" {

bool InjectDyLib(NSString *filePath, NSString *dylibPath, bool weakInject, bool bCreate) {
	ZTimer gtimer;
	@autoreleasepool {
		// Convert NSString to std::string
		std::string filePathStr = [filePath UTF8String];
		std::string dylibPathStr = [dylibPath UTF8String];

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		bool success = machO.InjectDyLib(weakInject, dylibPathStr.c_str(), bCreate);

		machO.Free();

		if (success) {
			gtimer.Print(">>> Dylib injected successfully!");
			return true;
		} else {
			gtimer.Print(">>> Failed to inject dylib.");
			return false;
		}
	}
}

bool ListDylibs(NSString *filePath, NSMutableArray *dylibPathsArray) {
	ZTimer gtimer;
	@autoreleasepool {
		// Convert NSString to std::string
		std::string filePathStr = [filePath UTF8String];

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		std::vector<std::string> dylibPaths = machO.ListDylibs();

		if (!dylibPaths.empty()) {
			gtimer.Print(">>> List of dylibs in the Mach-O file:");
            for (vector<std::string>::iterator it = dylibPaths.begin(); it < dylibPaths.end(); ++it) {
                std::string dylibPath = *it;
				NSString *dylibPathStr = [NSString stringWithUTF8String:dylibPath.c_str()];
				[dylibPathsArray addObject:dylibPathStr];
			}
		} else {
			gtimer.Print(">>> No dylibs found in the Mach-O file.");
		}

		machO.Free();

		return true;
	}
}

bool UninstallDylibs(NSString *filePath, NSArray<NSString *> *dylibPathsArray) {
	ZTimer gtimer;
	@autoreleasepool {
		std::string filePathStr = [filePath UTF8String];
		std::set<std::string> dylibsToRemove;

		for (NSString *dylibPath in dylibPathsArray) {
			dylibsToRemove.insert([dylibPath UTF8String]);
		}

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		machO.RemoveDylib(dylibsToRemove);

		machO.Free();

		gtimer.Print(">>> Dylibs uninstalled successfully!");
		return true;
	}
}



bool ChangeDylibPath(NSString *filePath, NSString *oldPath, NSString *newPath) {
	ZTimer gtimer;
	@autoreleasepool {
		// Convert NSString to std::string
		std::string filePathStr = [filePath UTF8String];
		std::string oldPathStr = [oldPath UTF8String];
		std::string newPathStr = [newPath UTF8String];

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		bool success = machO.ChangeDylibPath(oldPathStr.c_str(), newPathStr.c_str());

		machO.Free();

		if (success) {
			gtimer.Print(">>> Dylib path changed successfully!");
			return true;
		} else {
			gtimer.Print(">>> Failed to change dylib path.");
			return false;
		}
	}
}

NSError* makeErrorFromLog(const std::vector<std::string>& vec) {
    NSMutableString *result = [NSMutableString string];
    
    for (size_t i = 0; i < vec.size(); ++i) {
        // Convert each std::string to NSString
        NSString *str = [NSString stringWithUTF8String:vec[i].c_str()];
        [result appendString:str];
        
        // Append newline if it's not the last element
        if (i != vec.size() - 1) {
            [result appendString:@"\n"];
        }
    }
    
    NSDictionary* userInfo = @{
        NSLocalizedDescriptionKey : result
    };
    return [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:userInfo];
}

ZSignAsset zSignAsset;

void zsign(NSString *appPath,
          NSData *prov,
          NSData *key,
          NSString *pass,
          NSProgress* progress,
          void(^completionHandler)(BOOL success, NSDate* expirationDate, NSError *error)
          )
{
    ZTimer gtimer;
    ZTimer timer;
    timer.Reset();
    
	bool bForce = false;
	bool bWeakInject = false;
	bool bDontGenerateEmbeddedMobileProvision = YES;
	
	string strPassword;

	string strDyLibFile;
	string strOutputFile;

	string strEntitlementsFile;

    const char* strPKeyFileData = (const char*)[key bytes];
    const char* strProvFileData = (const char*)[prov bytes];
	strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
	
	
	string strPath = [appPath cStringUsingEncoding:NSUTF8StringEncoding];
    
    ZLog::logs.clear();

	__block ZSignAsset zSignAsset;
	
    if (!zSignAsset.InitSimple(strPKeyFileData, (int)[key length], strProvFileData, (int)[prov length], strPassword)) {
        completionHandler(NO, nil, makeErrorFromLog(ZLog::logs));
        ZLog::logs.clear();
		return;
	}
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:zSignAsset.expirationDate];
    
	bool bEnableCache = true;
	string strFolder = strPath;
	
	__block ZAppBundle bundle;
	bool success = bundle.ConfigureFolderSign(&zSignAsset, strFolder, "", "", "", strDyLibFile, bForce, bWeakInject, bEnableCache, bDontGenerateEmbeddedMobileProvision);

    if(!success) {
        completionHandler(NO, nil, makeErrorFromLog(ZLog::logs));
        ZLog::logs.clear();
        return;
    }
    
    int filesNeedToSign = bundle.GetSignCount();
    [progress setTotalUnitCount:filesNeedToSign];
    bundle.progressHandler = [&progress] {
        [progress setCompletedUnitCount:progress.completedUnitCount + 1];
    };
    
    


    ZLog::PrintV(">>> Files Need to Sign: \t%d\n", filesNeedToSign);
    bool bRet = bundle.StartSign(bEnableCache);
    timer.PrintResult(bRet, ">>> Signed %s!", bRet ? "OK" : "Failed");
    gtimer.Print(">>> Done.");
    NSError* signError = nil;
    if(!bundle.signFailedFiles.empty()) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithUTF8String:bundle.signFailedFiles.c_str()]
        };
        signError = [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:userInfo];
    }
    
    completionHandler(YES, date, signError);
    ZLog::logs.clear();
    
	return;
}

}
