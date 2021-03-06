//
//  CardExpiryTextFieldView.swift
//  PlatformUIKit
//
//  Created by Daniel Huri on 20/03/2020.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

import ToolKit

public final class CardExpiryTextFieldViewModel: TextFieldViewModel {
            
    // MARK: - Setup
    
    public init(hintDisplayType: HintDisplayType = .constant, messageRecorder: MessageRecording) {
        super.init(
            with: .expirationDate,
            hintDisplayType: hintDisplayType,
            validator: TextValidationFactory.Card.expirationDate,
            formatter: TextFormatterFactory.cardExpirationDate,
            messageRecorder: messageRecorder
        )
    }
}
