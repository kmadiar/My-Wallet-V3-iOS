//
//  LocalizationConstants+DigitPad.swift
//  PlatformUIKit
//
//  Created by Daniel Huri on 21/01/2020.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

extension LocalizationConstants.Accessibility {
    public struct DigitPad {
        public static let faceId = NSLocalizedString(
            "Face-ID authentication",
            comment: "Accessiblity label for face id biometrics authentication"
        )
        
        public static let touchId = NSLocalizedString(
            "Touch-ID authentication",
            comment: "Accessiblity label for touch id biometrics authentication"
        )
        
        public static let backspace = NSLocalizedString(
            "Backspace",
            comment: "Accessiblity label for backspace button"
        )
    }
}
