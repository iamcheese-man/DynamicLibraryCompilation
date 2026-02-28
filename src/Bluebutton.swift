// Tweak.swift
// Simple Swift Tweak - Adds a button to every view controller

import Foundation
import UIKit
import ObjectiveC

extension UIViewController {
    @objc dynamic func swizzled_viewDidAppear(_ animated: Bool) {
        self.swizzled_viewDidAppear(animated)
        
        // Create a button
        let tweakButton = UIButton(type: .system)
        tweakButton.setTitle("Tweaked! 🎉", for: .normal)
        tweakButton.backgroundColor = .systemBlue
        tweakButton.setTitleColor(.white, for: .normal)
        tweakButton.layer.cornerRadius = 10
        tweakButton.translatesAutoresizingMaskIntoConstraints = false
        tweakButton.addTarget(self, action: #selector(tweakButtonTapped), for: .touchUpInside)
        
        self.view.addSubview(tweakButton)
        
        NSLayoutConstraint.activate([
            tweakButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            tweakButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            tweakButton.widthAnchor.constraint(equalToConstant: 150),
            tweakButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    @objc func tweakButtonTapped() {
        let alert = UIAlertController(title: "Hello!", message: "Swift tweak button tapped!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }
}

func swizzle() {
    let original = #selector(UIViewController.viewDidAppear(_:))
    let swizzled = #selector(UIViewController.swizzled_viewDidAppear(_:))
    
    guard let originalMethod = class_getInstanceMethod(UIViewController.self, original),
          let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzled) else {
        return
    }
    
    method_exchangeImplementations(originalMethod, swizzledMethod)
}

@_cdecl("swift_tweak_init")
public func initTweak() {
    NSLog("[Tweak] Loading...")
    swizzle()
    NSLog("[Tweak] Loaded!")
}
