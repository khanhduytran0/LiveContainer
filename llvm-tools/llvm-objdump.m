#import "llvm-objdump.h"

const char *llvm_objdump(int argc, char **argv);

NSString* exec_llvm_objdump(NSString* filePath) {
    char* command[] = {
        "llvm-otool",
        "-L",
        [filePath UTF8String]
    };
    const char *res = llvm_objdump(3, command);
    return [NSString stringWithUTF8String:res];
}