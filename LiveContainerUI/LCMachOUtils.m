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
    struct dylib_command *dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (void *)header+header->sizeofcmds);
    dylib->cmd = cmd;
    dylib->cmdsize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(name) + 1, 8);
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

void LCPatchExecSlice(const char *path, struct mach_header_64 *header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);

    // Literally convert an executable to a dylib
    if (header->magic == MH_MAGIC_64) {
        //assert(header->flags & MH_PIE);
        header->filetype = MH_DYLIB;
        header->flags |= MH_NO_REEXPORTED_DYLIBS;
        header->flags &= ~MH_PIE;
    }

    BOOL hasDylibCommand = NO,
         hasLoaderCommand = NO;
    const char *tweakLoaderPath = "@loader_path/../../Tweaks/TweakLoader.dylib";
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_ID_DYLIB) {
            hasDylibCommand = YES;
        } else if(command->cmd == LC_LOAD_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)command;
            char *dylibName = (void *)dylib + dylib->dylib.name.offset;
            if (!strncmp(dylibName, tweakLoaderPath, strlen(tweakLoaderPath))) {
                hasLoaderCommand = YES;
            }
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    if (!hasDylibCommand) {
        insertDylibCommand(LC_ID_DYLIB, path, header);
    }
    if (!hasLoaderCommand) {
        insertDylibCommand(LC_LOAD_DYLIB, tweakLoaderPath, header);
    }

    // Patch __PAGEZERO to map just a single zero page, fixing "out of address space"
    struct segment_command_64 *seg = (struct segment_command_64 *)imageHeaderPtr;
    assert(seg->cmd == LC_SEGMENT_64);
    if (seg->vmaddr == 0) {
        assert(seg->vmsize == 0x100000000);
        seg->vmaddr = 0x100000000 - 0x4000;
        seg->vmsize = 0x4000;
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
    } else if (magic == MH_MAGIC_64) {
        callback(path, (struct mach_header_64 *)map);
    } else if (magic == MH_MAGIC) {
        return @"32-bit app is not supported";
    } else {
        //return @"Not a Mach-O file";
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
