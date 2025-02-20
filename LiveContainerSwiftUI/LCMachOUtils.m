@import Darwin;
@import Foundation;
@import MachO;
#import "LCUtils.h"

static uint32_t rnd32(uint32_t v, uint32_t r) {
    r--;
    return (v + r) & ~r;
}

static void insertDylibCommand(uint32_t cmd, const char *path, struct mach_header_64 *header) {
    const char *name = cmd==LC_ID_DYLIB ? basename((char *)path) : path;
    struct dylib_command *dylib;
    size_t cmdsize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(name) + 1, 8);
    if (cmd == LC_ID_DYLIB) {
        // Make this the first load command on the list (like dylibify does), or some UE3 games may break
        dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (uintptr_t)header);
        memmove((void *)((uintptr_t)dylib + cmdsize), (void *)dylib, header->sizeofcmds);
        bzero(dylib, cmdsize);
    } else {
        dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (void *)header+header->sizeofcmds);
    }
    dylib->cmd = cmd;
    dylib->cmdsize = cmdsize;
    dylib->dylib.name.offset = sizeof(struct dylib_command);
    dylib->dylib.compatibility_version = 0x10000;
    dylib->dylib.current_version = 0x10000;
    dylib->dylib.timestamp = 2;
    strncpy((void *)dylib + dylib->dylib.name.offset, name, strlen(name));
    header->ncmds++;
    header->sizeofcmds += dylib->cmdsize;
}

static void insertRPathCommand(const char *path, struct mach_header_64 *header) {
    struct rpath_command *rpath = (struct rpath_command *)(sizeof(struct mach_header_64) + (void *)header+header->sizeofcmds);
    rpath->cmd = LC_RPATH;
    rpath->cmdsize = sizeof(struct rpath_command) + rnd32((uint32_t)strlen(path) + 1, 8);
    rpath->path.offset = sizeof(struct rpath_command);
    strncpy((void *)rpath + rpath->path.offset, path, strlen(path));
    header->ncmds++;
    header->sizeofcmds += rpath->cmdsize;
}

void LCPatchAddRPath(const char *path, struct mach_header_64 *header) {
    insertRPathCommand("@executable_path/../../Tweaks", header);
    insertRPathCommand("@loader_path", header);
}

void LCPatchExecSlice(const char *path, struct mach_header_64 *header, bool doInject) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);

    // Literally convert an executable to a dylib
    if (header->magic == MH_MAGIC_64) {
        //assert(header->flags & MH_PIE);
        header->filetype = MH_DYLIB;
        header->flags |= MH_NO_REEXPORTED_DYLIBS;
        header->flags &= ~MH_PIE;
    }

    // Patch __PAGEZERO to map just a single zero page, fixing "out of address space"
    struct segment_command_64 *seg = (struct segment_command_64 *)imageHeaderPtr;
    assert(seg->cmd == LC_SEGMENT_64 || seg->cmd == LC_ID_DYLIB);
    if (seg->cmd == LC_SEGMENT_64 && seg->vmaddr == 0) {
        assert(seg->vmsize == 0x100000000);
        seg->vmaddr = 0x100000000 - 0x4000;
        seg->vmsize = 0x4000;
    }

    BOOL hasDylibCommand = NO;
    struct dylib_command * dylibLoaderCommand = 0;
    const char *tweakLoaderPath = "@loader_path/../../Tweaks/TweakLoader.dylib";
    const char *libCppPath = "/usr/lib/libc++.1.dylib";
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_ID_DYLIB) {
            hasDylibCommand = YES;
        } else if(command->cmd == LC_LOAD_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)command;
            char *dylibName = (void *)dylib + dylib->dylib.name.offset;
            if (!strncmp(dylibName, tweakLoaderPath, strlen(tweakLoaderPath))) {
                dylibLoaderCommand = dylib;
            }
        } else if(command->cmd == 0x114514) {
            dylibLoaderCommand = (struct dylib_command *)command;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }

    // Add LC_LOAD_DYLIB first, since LC_ID_DYLIB will change overall offsets
    if (dylibLoaderCommand) {
        dylibLoaderCommand->cmd = doInject ? LC_LOAD_DYLIB : 0x114514;
        strcpy((void *)dylibLoaderCommand + dylibLoaderCommand->dylib.name.offset, doInject ? tweakLoaderPath : libCppPath);
    } else {
        insertDylibCommand(doInject ? LC_LOAD_DYLIB : 0x114514, doInject ? tweakLoaderPath : libCppPath, header);
    }
    if (!hasDylibCommand) {
        insertDylibCommand(LC_ID_DYLIB, path, header);
    }
}

NSString *LCParseMachO(const char *path, LCParseMachOCallback callback) {
    int fd = open(path, O_RDWR, (mode_t)0600);
    struct stat s;
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
    }

    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        // Find compatible slice
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                callback(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)));
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_MAGIC) {
        callback(path, (struct mach_header_64 *)map);
    } else {
        return @"Not a Mach-O file";
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return nil;
}

void LCChangeExecUUID(struct mach_header_64 *header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_UUID) {
            struct uuid_command *uuidCmd = (struct uuid_command *)command;
            // let's add the first byte by 1
            uuidCmd->uuid[0] += 1;
            break;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
}

void LCPatchAltStore(const char *path, struct mach_header_64 *header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    const char *tweakPath = "@rpath/AltStoreTweak.dylib";
    BOOL
         hasLoaderCommand = NO;
    
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_LOAD_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)command;
            char *dylibName = (void *)dylib + dylib->dylib.name.offset;
            if (!strncmp(dylibName, tweakPath, strlen(tweakPath))) {
                hasLoaderCommand = YES;
            }
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }

    if (!hasLoaderCommand) {

        insertDylibCommand(LC_LOAD_DYLIB, tweakPath, header);
    }
}

struct code_signature_command {
    uint32_t    cmd;
    uint32_t    cmdsize;
    uint32_t    dataoff;
    uint32_t    datasize;
};

// from zsign
struct ui_CS_BlobIndex {
    uint32_t type;                    /* type of entry */
    uint32_t offset;                /* offset of entry */
};

struct ui_CS_SuperBlob {
    uint32_t magic;                    /* magic number */
    uint32_t length;                /* total length of SuperBlob */
    uint32_t count;                    /* number of index entries following */
    //CS_BlobIndex index[];            /* (count) entries */
    /* followed by Blobs in no particular order as indicated by offsets in index */
};

struct ui_CS_blob {
    uint32_t magic;
    uint32_t length;
};


NSString* getLCEntitlementXML(void) {
    struct mach_header_64* header = dlsym(RTLD_MAIN_ONLY, MH_EXECUTE_SYM);
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    struct code_signature_command* codeSignCommand = 0;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_CODE_SIGNATURE) {
            codeSignCommand = (struct code_signature_command*)command;
            break;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    if(!codeSignCommand) {
        return @"Unable to find LC_CODE_SIGNATURE command.";
    }
    struct ui_CS_SuperBlob* blob = (void*)header + codeSignCommand->dataoff;
    if(blob->magic != OSSwapInt32(0xfade0cc0)) {
        return [NSString stringWithFormat:@"CodeSign blob magic mismatch %8x.", blob->magic];
        return nil;
    }
    struct ui_CS_BlobIndex* entitlementBlobIndex = 0;
    struct ui_CS_BlobIndex* nowIndex = (void*)blob + sizeof(struct ui_CS_SuperBlob);
    for(int i = 0; i < OSSwapInt32(blob->count); i++) {
        if(OSSwapInt32(nowIndex->type) == 5) {
            entitlementBlobIndex = nowIndex;
            break;
        }
        nowIndex = (void*)nowIndex + sizeof(struct ui_CS_BlobIndex);
    }
    if(entitlementBlobIndex == 0) {
        NSLog(@"[LC] entitlement blob index not found.");
        return 0;
    }
    struct ui_CS_blob* entitlementBlob = (void*)blob + OSSwapInt32(entitlementBlobIndex->offset);
    if(entitlementBlob->magic != OSSwapInt32(0xfade7171)) {
        return [NSString stringWithFormat:@"EntitlementBlob magic mismatch %8x.", blob->magic];
        return nil;
    };
    int32_t xmlLength = OSSwapInt32(entitlementBlob->length) - sizeof(struct ui_CS_blob);
    void* xmlPtr = (void*)entitlementBlob + sizeof(struct ui_CS_blob);
    
    // entitlement xml in executable don't have \0 so we have to copy it first
    char* xmlString = malloc(xmlLength + 1);
    memcpy(xmlString, xmlPtr, xmlLength);
    xmlString[xmlLength] = 0;

    NSString* ans = [NSString stringWithUTF8String:xmlString];
    free(xmlString);
    return ans;
}
