// Example Swift Dylib
// Place your Swift source files in the src/ folder

import Foundation
import UIKit

@_cdecl("myFunction")
public func myFunction() {
    print("Hello from dylib!")
}

@objc public class MyClass: NSObject {
    @objc public func greet() -> String {
        return "Hello from Swift dylib!"
    }
    
    @objc public func showAlert() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            let alert = UIAlertController(title: "Dylib", message: "Hello from compiled dylib!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            rootViewController.present(alert, animated: true)
        }
    }
}

// Constructor - runs when dylib is loaded
@_cdecl("dylibInit")
public func dylibInit() {
    print("Dylib initialized!")
}
