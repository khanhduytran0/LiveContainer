@import Foundation;

 __attribute__((constructor))
static void TestJITLessConstructor() {
    NSLog(@"JIT-less test succeed");
    setenv("LC_JITLESS_TEST_LOADED", "1", 1);
}
