# Universal Dylib Compiler

Compile dynamic libraries, tweaks, and frameworks for iOS **without a Mac** using GitHub Actions!

## 🚀 Features

- ✅ Compile Swift dylibs
- ✅ Compile Objective-C dylibs  
- ✅ Compile Theos tweaks
- ✅ Build iOS frameworks
- ✅ Output as `.dylib` or `.deb` package
- ✅ No Mac required!

## 📁 Project Structure

```
your-repo/
├── .github/
│   └── workflows/
│       └── compile.yml
├── src/
│   └── (your source files here)
└── README.md
```

## 🔨 How to Use

### 1. Fork/Use This Template

Click "Use this template" or fork this repository.

### 2. Add Your Source Code

Place your source files in the `src/` folder:

**For Swift dylib:**
```
src/
├── MyFile.swift
└── AnotherFile.swift
```

**For Objective-C dylib:**
```
src/
├── MyClass.h
└── MyClass.m
```

**For Theos tweak:**
```
src/
├── Makefile
├── Tweak.x
└── control
```

### 3. Run the Workflow

1. Go to **Actions** tab
2. Click **"Compile Dynamic Library"**
3. Click **"Run workflow"**
4. Select:
   - **Project Type**: swift-dylib, objc-dylib, theos-tweak, or framework
   - **Output Format**: dylib-only, deb-only, or both
5. Click **"Run workflow"**

### 4. Download Your Compiled Files

Once the workflow completes:
- Go to the workflow run
- Scroll to **Artifacts**
- Download your compiled `.dylib` or `.deb`

## 📝 Examples

### Swift Dylib Example

```swift
// src/MyDylib.swift
import Foundation
import UIKit

@_cdecl("myFunction")
public func myFunction() {
    print("Hello from Swift dylib!")
}

@objc public class MyClass: NSObject {
    @objc public func greet() -> String {
        return "Hello!"
    }
}
```

**To compile:** Select `swift-dylib` as project type

---

### Objective-C Dylib Example

```objc
// src/MyDylib.h
#import <Foundation/Foundation.h>

@interface MyDylib : NSObject
+ (instancetype)sharedInstance;
- (void)sayHello;
@end
```

```objc
// src/MyDylib.m
#import "MyDylib.h"

@implementation MyDylib

+ (instancetype)sharedInstance {
    static MyDylib *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)sayHello {
    NSLog(@"Hello from ObjC dylib!");
}

@end

__attribute__((constructor))
void dylibLoaded(void) {
    [[MyDylib sharedInstance] sayHello];
}
```

**To compile:** Select `objc-dylib` as project type

---

### Theos Tweak Example

```objc
// src/Tweak.x
#import <UIKit/UIKit.h>

%hook UIViewController

- (void)viewDidLoad {
    %orig;
    NSLog(@"[MyTweak] View controller loaded!");
}

%end

%ctor {
    NSLog(@"[MyTweak] Tweak initialized!");
}
```

```makefile
# src/Makefile
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak
MyTweak_FILES = Tweak.x
MyTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
```

```
# src/control
Package: com.example.mytweak
Name: MyTweak
Version: 1.0.0
Architecture: iphoneos-arm64
Description: My awesome tweak
Maintainer: Your Name
Author: Your Name
Section: Tweaks
Depends: mobilesubstrate
```

**To compile:** Select `theos-tweak` as project type

---

## 🎯 Use Cases

- **No Mac?** Compile iOS libraries without Apple hardware
- **CI/CD** Automated builds for your tweaks
- **Quick Testing** Rapid prototyping and iteration
- **Learning** Great for learning iOS development
- **Open Source** Share compilable tweak source code

## ⚙️ Advanced Configuration

### Adding Dependencies

For Swift dylibs with dependencies:
```bash
swiftc -emit-library -o liboutput.dylib *.swift \
  -I /path/to/headers \
  -L /path/to/libraries \
  -l somelib
```

For Objective-C with frameworks:
```bash
clang -dynamiclib -o liboutput.dylib *.m \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics
```

### Custom Build Scripts

Modify `.github/workflows/compile.yml` to add custom build steps!

## 📦 Output Formats

### Dylib Only
- Raw `.dylib` file
- Use with injection tools

### DEB Package
- Packaged `.deb` for Cydia/Sileo
- Ready to install on jailbroken devices
- Includes proper directory structure

### Both
- Get both `.dylib` and `.deb`

## 🔧 Troubleshooting

**Build fails:**
- Check your source code syntax
- Verify all imports are correct
- Make sure file paths are right

**Theos fails:**
- Check Makefile syntax
- Verify control file is valid
- Ensure Tweak.x has no syntax errors

**Dylib crashes:**
- Add proper error handling
- Check memory management
- Test on compatible iOS versions

## 💡 Tips

- Use `@_cdecl` in Swift for C-compatible exports
- Add `__attribute__((constructor))` for init functions
- Test locally first if you have a Mac
- Check GitHub Actions logs for detailed errors

## 📚 Resources

- [Theos Documentation](https://theos.dev)
- [iOS Dylib Development](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/)
- [Swift Interop Guide](https://developer.apple.com/documentation/swift/calling-apis-across-language-boundaries)

## ⚠️ Legal Notice

This tool is for **educational purposes** and **legitimate development** only. Do not use to:
- Pirate paid tweaks/apps
- Violate app TOS
- Distribute malicious code

Always respect intellectual property and user privacy.

## 🤝 Contributing

PRs welcome! Add support for:
- More build systems
- Additional frameworks
- Better error handling
- Documentation improvements

## 📄 License

MIT License - use freely!

---

**Made for developers without Macs 🚀**
