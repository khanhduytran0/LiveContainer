//
//  zsign.hpp
//  feather
//
//  Created by HAHALOSAH on 5/22/24.
//

#ifndef zsign_hpp
#define zsign_hpp

#include <stdio.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

bool InjectDyLib(NSString *filePath,
				 NSString *dylibPath,
				 bool weakInject,
				 bool bCreate);

bool ChangeDylibPath(NSString *filePath,
					 NSString *oldPath,
					 NSString *newPath);

bool ListDylibs(NSString *filePath, NSMutableArray *dylibPathsArray);
bool UninstallDylibs(NSString *filePath, NSArray<NSString *> *dylibPathsArray);

void zsign(NSString *appPath,
          NSData *prov,
          NSData *key,
          NSString *pass,
          NSProgress* progress,
          void(^completionHandler)(BOOL success, NSDate* expirationDate, NSError *error)
          );


#ifdef __cplusplus
}
#endif

#endif /* zsign_hpp */
