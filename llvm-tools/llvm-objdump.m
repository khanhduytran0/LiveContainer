#import "llvm-objdump.h"

const char *llvm_objdump(int argc, char **argv);

void exec_llvm_objdump(filePath: NSString*) {
    char* res[] = {
        "llvm-otool",
        "-L",
        [file_path UTF8String]
    };
    const char *res = llvm_objdump(3, res);
    return [NSString stringWithUTF8String:res];
}