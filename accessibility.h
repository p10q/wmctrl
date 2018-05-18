#ifndef __utils_h__
#define __utils_h__

inline bool
CheckAccessibilityPrivileges()
{
    const void *Keys[] = { kAXTrustedCheckOptionPrompt };
    const void *Values[] = { kCFBooleanTrue };

    CFDictionaryRef Options = CFDictionaryCreate(kCFAllocatorDefault,
                                                 Keys,
                                                 Values,
                                                 sizeof(Keys) / sizeof(*Keys),
                                                 &kCFCopyStringDictionaryKeyCallBacks,
                                                 &kCFTypeDictionaryValueCallBacks);

    bool Result = AXIsProcessTrustedWithOptions(Options);
    CFRelease(Options);

    return Result;
}


inline AXUIElementRef
SystemWideElement()
{
    local_persist AXUIElementRef Element;
    local_persist dispatch_once_t Token;

    dispatch_once(&Token, ^{
        Element = AXUIElementCreateSystemWide();
    });

    return Element;
}

#endif
