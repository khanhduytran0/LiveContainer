//
//  JIT.m
//  LiveContainer
//
//  Created by s s on 2025/3/16.
//

@import Foundation;
#include "utils.h"
#import "Localization.h"

extern void LCShowAlert(NSString* message);

void LCSendJITRequest(pid_t pid, void (^completionHandler)(NSString *message, BOOL success, NSError *error)) {
    NSString* serverAddress = [NSUserDefaults.lcSharedDefaults stringForKey:@"LCSideJITServerAddress"];
    if(!serverAddress || serverAddress.length == 0) {
        serverAddress = @"http://[fd00::]:9172";
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@/attach/%d", serverAddress, pid];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completionHandler(nil, NO, error);
            return;
        }
        
        if (data) {
            NSError *jsonError = nil;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                completionHandler(nil, NO, jsonError);
                return;
            }
            
            NSString *message = jsonResponse[@"message"];
            BOOL success = [jsonResponse[@"success"] boolValue];
            completionHandler(message, success, nil);
        } else {
            completionHandler(nil, NO, [NSError errorWithDomain:@"ResponseError" code:0 userInfo:@{NSLocalizedDescriptionKey: @"No data received"}]);
        }
    }];

    [task resume];
}

void LCAcquireJIT(void) {
    int pid = getpid();
    LCSendJITRequest(pid, ^(NSString *message, BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(success) {
                LCShowAlert(@"lc.guestTweak.jitSuccess".loc);
            } else if (message) {
                LCShowAlert([@"lc.guestTweak.jitError %@" localizeWithFormat:message]);
            } else if (error) {
                LCShowAlert([@"lc.guestTweak.jitError %@" localizeWithFormat:error.localizedDescription]);
            } else {
                LCShowAlert([@"lc.guestTweak.jitError %@" localizeWithFormat:@"An unknown error occurred."]);
            }
        });

    });
    
}
