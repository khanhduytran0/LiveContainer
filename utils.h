#import <Foundation/Foundation.h>
#include <objc/runtime.h>

NSString *appError;

const char **_CFGetProgname(void);
const char **_CFGetProcessPath(void);
int _NSGetExecutablePath(char* buf, uint32_t* bufsize);

void init_bypassDyldLibValidation();

uint64_t aarch64_emulate_adrp(uint32_t instruction, uint64_t pc);
bool aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm);
uint64_t aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc);
uint64_t aarch64_emulate_adrp_ldr(uint32_t instruction, uint32_t ldrInstruction, uint64_t pc);
