#import "MCPerfHelper.h"

__attribute__((constructor))
static void initHelper() {
    // Only call initialize; heavy lifting is delayed
    [MCPerfHelper initializeHelper];
}
