//
//  AlertModel.swift
//  PlatformUIKit
//
//  Created by Alex McGregor on 1/24/19.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import UIKit

public struct AlertModel {
    public let image: UIImage?
    public let imageTintColor: UIColor?
    public let headline: String?
    public let body: String?
    public let note: String?
    public let actions: [AlertAction]
    public let dismissable: Bool
    public let style: AlertViewStyle
    
    public init(
        headline: String?,
        body: String?,
        note: String? = nil,
        actions: [AlertAction] = [.defaultDismissal],
        image: UIImage? = nil,
        imageTintColor: UIColor? = nil,
        dismissable: Bool = true,
        style: AlertViewStyle = .default
    ) {
        self.headline = headline
        self.body = body
        self.note = note
        self.actions = actions
        self.image = image
        self.imageTintColor = imageTintColor
        self.dismissable = dismissable
        self.style = style
    }
}

public struct AlertAction {
    public let style: AlertActionStyle
    public let metadata: ActionMetadata?
    
    public init(style: AlertActionStyle, metadata: ActionMetadata? = nil) {
        self.style = style
        self.metadata = metadata
    }
}

public extension AlertAction {
    
    public static let defaultDismissal = AlertAction(style: .dismiss)
    
    var title: String? {
        switch style {
        case .confirm(let title):
            return title
        case .default(let title):
            return title
        case .dismiss:
            return nil
        }
    }
    
}

public enum AlertActionStyle: Equatable {
    public typealias Title = String
    /// Filled in `UIButton` with white text.
    /// It appears _above_ the `default` style button.
    case confirm(Title)
    /// `UIButton` with blue border and blue text.
    /// It appears _below_ the `confirm` style button.
    case `default`(Title)
    /// When the user taps outside of the view to dismiss it.
    case dismiss
}

public extension AlertActionStyle {
    public static func ==(lhs: AlertActionStyle, rhs: AlertActionStyle) -> Bool {
        switch (lhs, rhs) {
        case (.confirm(let left), .confirm(let right)):
            return left == right
        case (.default(let left), .default(let right)):
            return left == right
        case (.dismiss, .dismiss):
            return true
        default:
            return false
        }
    }
}

public enum AlertViewStyle {
    case `default`
    case sheet
}
