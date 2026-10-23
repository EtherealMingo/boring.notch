//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import Foundation
import SwiftUI


public class BoringAnimations {
    @Published var notchStyle: Style = .notch
    
    init() {
        self.notchStyle = .notch
    }
    
    var animation: Animation {
        // No springs: the notch must move with plain easing, never overshoot.
        Animation.easeInOut(duration: 0.4)
    }
    
    // TODO: Move all animations to this file
    
}
