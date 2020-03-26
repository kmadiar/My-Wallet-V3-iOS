//
//  SettingsRouter.swift
//  Blockchain
//
//  Created by AlexM on 12/12/19.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import PlatformKit
import PlatformUIKit
import RxSwift
import RxRelay
import RxCocoa
import SafariServices
import ToolKit

final class SettingsRouter: SettingsRouterAPI {
    
    typealias AnalyticsEvent = AnalyticsEvents.Settings
    typealias CellType = SettingsScreenPresenter.Section.CellType
    
    let actionRelay = PublishRelay<SettingsScreenAction>()
    let previousRelay = PublishRelay<Void>()
    
    // MARK: - Routers
    
    private lazy var updateMobileRouter: UpdateMobileRouter = {
        return UpdateMobileRouter(navigationControllerAPI: navigationControllerAPI)
    }()
    
    private lazy var backupRouterAPI: BackupRouterAPI = {
        return BackupFundsSettingsRouter(navigationControllerAPI: navigationControllerAPI)
    }()
    
    // MARK: - Private
    
    private let guidRepositoryAPI: GuidRepositoryAPI
    private let analyticsRecording: AnalyticsEventRecording
    private let alertPresenter: AlertViewPresenter
    private unowned let currencyRouting: CurrencyRouting
    private unowned let tabSwapping: TabSwapping
    
    weak var navigationControllerAPI: NavigationControllerAPI?
    weak var topMostViewControllerProvider: TopMostViewControllerProviding!
    
    private let disposeBag = DisposeBag()
    
    init(wallet: Wallet = WalletManager.shared.wallet,
         guidRepositoryAPI: GuidRepositoryAPI = WalletManager.shared.repository,
         analyticsRecording: AnalyticsEventRecording = AnalyticsEventRecorder.shared,
         topMostViewControllerProvider: TopMostViewControllerProviding = UIApplication.shared,
         alertPresenter: AlertViewPresenter = AlertViewPresenter.shared,
         currencyRouting: CurrencyRouting,
         tabSwapping: TabSwapping) {
        self.alertPresenter = alertPresenter
        self.topMostViewControllerProvider = topMostViewControllerProvider
        self.analyticsRecording = analyticsRecording
        self.currencyRouting = currencyRouting
        self.tabSwapping = tabSwapping
        self.guidRepositoryAPI = guidRepositoryAPI
        
        previousRelay
            .bind(weak: self) { (self) in
                self.dismiss()
            }
            .disposed(by: disposeBag)
        
        actionRelay
            .bind(weak: self) { (self, action) in
                self.handle(action: action)
            }
            .disposed(by: disposeBag)
    }
    
    func presentSettings() {
        let interactor = SettingsScreenInteractor()
        let presenter = SettingsScreenPresenter(interactor: interactor, router: self)
        let controller = SettingsViewController(presenter: presenter)
        present(viewController: controller, using: .modalOverTopMost)
    }
    
    func presentSettingsAndThen(handle action: SettingsScreenAction) {
        // TODO: Deep Linking
        presentSettings()
    }
    
    func dismiss() {
        guard let navController = navigationControllerAPI else { return }
        if navController.viewControllersCount > 1 {
            navController.popViewController(animated: true)
        } else {
            navController.dismiss(animated: true, completion: nil)
            navigationControllerAPI = nil
        }
    }
    
    private func handle(action: SettingsScreenAction) {
        switch action {
        case .showURL(let url):
            let controller = SFSafariViewController(url: url)
            present(viewController: controller)
        case .launchChangePassword:
            let interactor = ChangePasswordScreenInteractor()
            let presenter = ChangePasswordScreenPresenter(previousAPI: self, interactor: interactor)
            let controller = ChangePasswordViewController(presenter: presenter)
            present(viewController: controller)
        case .showAppStore:
            UIApplication.shared.openAppStore()
        case .showBackupScreen:
            backupRouterAPI.start()
        case .showChangePinScreen:
            AuthenticationCoordinator.shared.changePin()
        case .showCurrencySelectionScreen:
            let settingsService = UserInformationServiceProvider.default.settings
            settingsService
                .fiatCurrency
                .observeOn(MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] currency in
                    self?.showFiatCurrencySelectionScreen(selectedCurrency: currency)
                })
                .disposed(by: disposeBag)
        case .launchWebLogin:
            let presenter = WebLoginScreenPresenter(service: WebLoginQRCodeService())
            let viewController = WebLoginScreenViewController(presenter: presenter)
            viewController.modalPresentationStyle = .overFullScreen
            present(viewController: viewController)
        case .promptGuidCopy:
            guidRepositoryAPI.guid
                .map(weak: self) { (self, value) -> String in
                    return value ?? ""
                }
                .observeOn(MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] guid in
                    guard let self = self else { return }
                    let alert = UIAlertController(title: LocalizationConstants.AddressAndKeyImport.copyWalletId,
                                                  message: LocalizationConstants.AddressAndKeyImport.copyWarning,
                                                  preferredStyle: .actionSheet)
                    let copyAction = UIAlertAction(
                        title: LocalizationConstants.AddressAndKeyImport.copyCTA,
                        style: .destructive,
                        handler: { [weak self] _ in
                            guard let self = self else { return }
                            self.analyticsRecording.record(event: AnalyticsEvent.settingsWalletIdCopied)
                            UIPasteboard.general.string = guid
                        }
                    )
                    let cancelAction = UIAlertAction(title: LocalizationConstants.cancel, style: .cancel, handler: nil)
                    alert.addAction(cancelAction)
                    alert.addAction(copyAction)
                    guard let navController = self.navigationControllerAPI as? UINavigationController else { return }
                    navController.present(alert, animated: true)
                })
                .disposed(by: disposeBag)
            
        case .launchKYC:
            guard let navController = navigationControllerAPI as? UINavigationController else { return }
            KYCTiersViewController.routeToTiers(
                fromViewController: navController
            ).disposed(by: disposeBag)
        case .launchPIT:
            guard let supportURL = URL(string: Constants.Url.exchangeSupport) else { return }
            let startPITCoordinator = { [weak self] in
                guard let self = self else { return }
                guard let navController = self.navigationControllerAPI as? UINavigationController else { return }
                ExchangeCoordinator.shared.start(from: navController)
            }
            let launchPIT = AlertAction(
                style: .confirm(LocalizationConstants.Exchange.Launch.launchExchange),
                metadata: .block(startPITCoordinator)
            )
            let contactSupport = AlertAction(
                style: .default(LocalizationConstants.Exchange.Launch.contactSupport),
                metadata: .url(supportURL)
            )
            let model = AlertModel(
                headline: LocalizationConstants.Exchange.title,
                body: nil,
                actions: [launchPIT, contactSupport],
                image: #imageLiteral(resourceName: "exchange-icon-small"),
                dismissable: true,
                style: .sheet
            )
            let alert = AlertView.make(with: model) { [weak self] action in
                guard let self = self else { return }
                guard let metadata = action.metadata else { return }
                switch metadata {
                case .block(let block):
                    block()
                case .url(let support):
                    let controller = SFSafariViewController(url: support)
                    self.present(viewController: controller)
                case .dismiss,
                     .pop,
                     .payload:
                    break
                }
            }
            alert.show()
        case .showUpdateEmailScreen:
            let interactor = UpdateEmailScreenInteractor()
            let presenter = UpdateEmailScreenPresenter(emailScreenInteractor: interactor)
            let controller = UpdateEmailScreenViewController(presenter: presenter)
            present(viewController: controller)
        case .showUpdateMobileScreen:
            updateMobileRouter.start()
        case .none:
            break
        }
    }
    
    private func showFiatCurrencySelectionScreen(selectedCurrency: FiatCurrency) {
        let selectionService = FiatCurrencySelectionService(defaultSelectedData: selectedCurrency)
        let interactor = SelectionScreenInteractor(service: selectionService)
        let presenter = SelectionScreenPresenter(
            title: LocalizationConstants.localCurrency,
            interactor: interactor
        )
        let viewController = SelectionScreenViewController(presenter: presenter)
        if #available(iOS 13.0, *) {
            viewController.isModalInPresentation = true
        }
        present(viewController: viewController)
        
        interactor.selectedIdOnDismissal
            .map { FiatCurrency(code: $0)! }
            .flatMap { currency in
                UserInformationServiceProvider.default.settings
                    .update(
                        currency: currency,
                        context: .settings
                    )
                    .andThen(Single.just(currency))
            }
            .observeOn(MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] currency in
                    guard let self = self else { return }
                    /// TODO: Remove this and `fiatCurrencySelected` once `ReceiveBTC` and
                    /// `SendBTC` are replaced with Swift implementations.
                    NotificationCenter.default.post(name: .fiatCurrencySelected, object: nil)
                    self.analyticsRecording.record(
                        event: AnalyticsEvents.Settings.settingsCurrencySelected(currency: currency.code)
                    )
                },
                onError: { [weak self] _ in
                    guard let self = self else { return }
                    self.alertPresenter.standardError(
                        message: LocalizationConstants.GeneralError.loadingData
                    )
                }
            )
            .disposed(by: disposeBag)
    }
}
