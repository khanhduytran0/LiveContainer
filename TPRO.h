// by khanhduytran0
#define _COMM_PAGE_START_ADDRESS (0x0000000FFFFFC000ULL)
//#define _COMM_PAGE_TPRO_SUPPORT (_COMM_PAGE_START_ADDRESS + ????)
#define _COMM_PAGE_TPRO_WRITE_ENABLE (_COMM_PAGE_START_ADDRESS + 0x0D0)
//#define _COMM_PAGE_TPRO_WRITE_DISABLE (_COMM_PAGE_START_ADDRESS + 0x0D8)

static inline bool os_thread_self_restrict_tpro_to_rw() {
    if (!*(uint64_t*)_COMM_PAGE_TPRO_WRITE_ENABLE) {
        // Doesn't have TPRO, skip this
        return false;
    }
    __asm__ __volatile__ (
        "mov x0, %0\n"
        "ldr x0, [x0]\n"
        "msr s3_6_c15_c1_5, x0\n"
        "isb sy\n"
        :: "r" (_COMM_PAGE_TPRO_WRITE_ENABLE)
       : "memory", "x0"
    );
    return true;
}

/*
inline uint64_t sprr_read() {
    uint64_t v;
    __asm__ __volatile__(
        "isb sy\n"
        "mrs %0, s3_6_c15_c1_5\n"
        : "=r"(v)::"memory");
    return v;
}
*/
