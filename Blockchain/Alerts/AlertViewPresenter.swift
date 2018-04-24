//
//  AlertViewPresenter.swift
//  Blockchain
//
//  Created by Chris Arriola on 4/19/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation

@objc class AlertViewPresenter: NSObject {
    typealias AlertConfirmHandler = ((UIAlertAction) -> Void)

    static let shared = AlertViewPresenter()

    @objc class func sharedInstance() -> AlertViewPresenter { return shared }

    private override init() {
        super.init()
    }

    @objc func checkAndWarnOnJailbrokenPhones() {
        guard UIDevice.current.isUnsafe() else {
            return
        }
        AlertViewPresenter.shared.standardNotify(
            message: LocalizationConstants.warning,
            title: LocalizationConstants.unsafeDeviceWarningMessage
        )
    }

    @objc func showNoInternetConnectionAlert() {
        standardNotify(message: LocalizationConstants.noInternetConnection, title: LocalizationConstants.error) { _ in
            LoadingViewPresenter.shared.hideBusyView()
            // TODO: this should not be in here. Figure out all areas where pin
            // should be reset and explicitly reset pin entry there
            // [self.pinEntryViewController reset];
        }
    }

    @objc func standardNotify(
        message: String,
        title: String = LocalizationConstants.error,
        handler: AlertConfirmHandler? = nil
    ) {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else { return }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: LocalizationConstants.ok, style: .cancel, handler: handler))

            let window = UIApplication.shared.keyWindow
            guard let topMostViewController = window?.rootViewController?.topMostViewController else {
                window?.rootViewController?.present(alert, animated: true)
                return
            }

            if !(topMostViewController is PEPinEntryController) {
                NotificationCenter.default.addObserver(
                    alert,
                    selector: #selector(UIViewController.autoDismiss),
                    name: NSNotification.Name.UIApplicationDidEnterBackground,
                    object: nil
                )
            }

            topMostViewController.present(alert, animated: true)
        }
    }

}
