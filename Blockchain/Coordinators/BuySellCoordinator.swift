//
//  BuySellCoordinator.swift
//  Blockchain
//
//  Created by kevinwu on 6/6/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation
import SafariServices
import RxSwift
import ToolKit
import PlatformKit
import PlatformUIKit

@objc class BuySellCoordinator: NSObject, Coordinator {
    @objc static let shared = BuySellCoordinator()

    @objc private(set) var buyBitcoinViewController: BuyBitcoinViewController?

    private let walletManager: WalletManager

    private let walletService: WalletService
    private let loadingViewPresenter: LoadingViewPresenting
    private let coinifyAuthenticator = KYCCoinifyAuthenticator()
    private let coinifyAccountRepository: CoinifyAccountRepositoryAPI
    private var kycObserver: NSObjectProtocol?

    private let disposables = CompositeDisposable()
    private var disposable: Disposable?

    private enum BuySellError: Error {
        case unsupportedCountry(code: String)
        case noKYCMetadata
        case emptyCoinifyMetadata
        case `default`
    }

    private init(
        walletManager: WalletManager = WalletManager.shared,
        walletService: WalletService = WalletService.shared,
        loadingViewPresenter: LoadingViewPresenting = LoadingViewPresenter.shared,
        repository: CoinifyAccountRepositoryAPI = CoinifyAccountRepository(bridge: WalletManager.shared.wallet)
    ) {
        self.walletManager = walletManager
        self.walletService = walletService
        self.loadingViewPresenter = loadingViewPresenter
        self.coinifyAccountRepository = CoinifyAccountRepository(bridge: walletManager.wallet)
        super.init()
        self.walletManager.buySellDelegate = self
    }

    func start() {
        disposable = walletService.walletOptions
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { walletOptions in
                guard let rootURL = walletOptions.mobile?.walletRoot else {
                    Logger.shared.warning("Error with wallet options response when starting buy sell webview")
                    return
                }
                self.initializeWebView(rootURL: rootURL)
            }, onError: { _ in
                Logger.shared.error("Error getting wallet options to start buy sell webview")
            })
    }

    private func initializeWebView(rootURL: String?) {
        buyBitcoinViewController = BuyBitcoinViewController(rootURL: rootURL)
    }

    // MARK: Public

    @objc func showBuyBitcoinView() {
        // If Tier Two pending, show the status page.
        // If they're verified but we haven't created a coinify user,
        // we have to create that and update Nabu and metadata.
        loadingViewPresenter.show(with: LocalizationConstants.loading)
        let disposable = tierTwoTierState()
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .do(onDispose: { [weak self] in
                self?.loadingViewPresenter.hide()
            })
            .subscribe(
                onSuccess: { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .none:
                        self.showVerificationAlert()
                    case .pending,
                         .rejected:
                        KYCCoordinator.shared.start()
                    case .verified:
                        self.startCoinifyAndSyncIfSupported()
                    }
                },
                onError: { error in
                    Logger.shared.error("Failed to get user: \(error.localizedDescription)")
                })
        disposables.insertWithDiscardableResult(disposable)
    }

    // MARK: Coinify & Nabu

    private func startCoinifyAndSyncIfSupported() {
        let disposable = userCountrySupportsCoinify()
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .subscribe(
                onCompleted: { [unowned self] in
                    self.createAndSyncCoinifyMetadataIfNeeded()
                },
                onError: { [unowned self] error in
                    switch error as? BuySellError {
                    case .unsupportedCountry(code: let code):
                        self.showCountryNotSupportedAlert(code)
                    default:
                        break
                    }
                })
        disposables.insertWithDiscardableResult(disposable)
    }

    private func createAndSyncCoinifyMetadataIfNeeded() {
        let disposable = self.createAndSyncCoinifyMetadata()
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .flatMapCompletable {
                return self.syncCoinifyMetadataWithNabuIfNeeded($0)
            }
            .subscribe(onCompleted: { [weak self] in
                self?.loadingViewPresenter.hide()
                DispatchQueue.main.async {
                    self?.routeToBuyBitcoinViewController()
                }
            }, onError: { [weak self] error in
                self?.loadingViewPresenter.hide()
            })
        self.disposables.insertWithDiscardableResult(disposable)
    }

    private func createAndSyncCoinifyMetadata() -> Single<CoinifyMetadata> {
        return coinifyAccountRepository.coinifyMetadata().ifEmpty(
            switchTo: coinifyAuthenticator.createCoinifyTrader()
            ).flatMap {
                return self.coinifyAccountRepository.save(
                    accountID: $0.traderIdentifier,
                    token: $0.offlineToken
                ).andThen(Single.just($0))
        }
    }

    private func syncCoinifyMetadataWithNabuIfNeeded(_ metadata: CoinifyMetadata) -> Completable {
        let user = BlockchainDataRepository.shared.nabuUser
            .take(1)
            .asSingle()
        return user.flatMapCompletable {
            if let tags = $0.tags, tags.coinify == true {
                return Completable.empty()
            } else {
                return self.coinifyAuthenticator.updateCoinifyIdentifer(
                    metadata.traderIdentifier
                )
            }
        }
    }

    private func userCountrySupportsCoinify() -> Completable {
        return BlockchainDataRepository.shared.nabuUser.take(1).asSingle().flatMapCompletable { user -> Completable in
            guard let address = user.address else { return Completable.error(BuySellError.noKYCMetadata) }
            return self.countrySupportedByCoinify(address.countryCode)
        }
    }

    private func countrySupportedByCoinify(_ countryCode: String) -> Completable {
        return walletService.walletOptions.flatMapCompletable { value -> Completable in
            guard let coinify = value.coinifyMetadata else { return Completable.error(BuySellError.emptyCoinifyMetadata) }
            let countrySupported = coinify.countries.contains(where: { $0.lowercased() == countryCode.lowercased() })
            switch countrySupported {
            case true:
                return Completable.empty()
            case false:
                return Completable.error(BuySellError.unsupportedCountry(code: countryCode))
            }
        }
    }

    // MARK: Alert

    private func showVerificationAlert() {
        guard let tosURL = URL(string: "https://coinify.com/legal/") else { return }
        guard BlockchainSettings.sharedAppInstance().didAcceptCoinifyTOS == false else {
            KYCCoordinator.shared.startFrom(.tier2)
            return
        }
        let beginNow = AlertAction(style: .confirm(LocalizationConstants.AnnouncementCards.CoinifyKyc.ctaButton))
        let termsOfService = AlertAction(
            style: .default(LocalizationConstants.tos),
            metadata: ActionMetadata.url(tosURL)
        )
        let alert = AlertModel(
            headline: LocalizationConstants.AnnouncementCards.CoinifyKyc.title,
            body: LocalizationConstants.AnnouncementCards.CoinifyKyc.description,
            note: LocalizationConstants.BuySell.buySellAgreement,
            actions: [beginNow, termsOfService],
            image: #imageLiteral(resourceName: "Icon-Information"),
            style: .sheet
        )
        let alertView = AlertView.make(with: alert) { action in
            switch action.style {
            case .confirm:
                BlockchainSettings.sharedAppInstance().didAcceptCoinifyTOS = true
                KYCCoordinator.shared.startFrom(.tier2)
            case .default:
                guard case let .url(value)? = action.metadata else { return }
                guard let controller = AppCoordinator.shared.tabControllerManager.tabViewController else { return }
                let viewController = SFSafariViewController(url: value)
                viewController.modalPresentationStyle = .overFullScreen
                controller.present(viewController, animated: true, completion: nil)
            case .dismiss:
                break
            }
        }
        alertView.show()
    }

    private func showCountryNotSupportedAlert(_ countryCode: String) {
        let ok = AlertAction(style: .default(LocalizationConstants.okString))
        let alert = AlertModel(
            headline: String(format: LocalizationConstants.KYC.comingSoonToX, countryCode.uppercased()),
            body: String(format: LocalizationConstants.KYC.unsupportedCountryDescription, countryCode.uppercased()),
            actions: [ok],
            style: .sheet
        )
        let alertView = AlertView.make(with: alert, completion: nil)
        alertView.show()
    }

    // MARK: Helpers

    private func tierTwoTierState() -> Single<KYC.Tier.State> {
        return BlockchainDataRepository.shared.tiers
            .take(1)
            .asSingle()
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .flatMap({ (tiersResponse) -> Single<KYC.Tier.State> in
                guard let tier = tiersResponse.tiers.first(where: { $0.tier == .tier2 }) else {
                    return Single.just(.none)
                }
                return Single.just(tier.state)
            })
    }

    private func routeToBuyBitcoinViewController() {
        loadingViewPresenter.show(with: LocalizationConstants.loading)
        guard let buyBitcoinViewController = buyBitcoinViewController else {
            Logger.shared.warning("buyBitcoinViewController not yet initialized")
            return
        }

        guard
            let loginDataDict = walletManager.wallet.executeJSSynchronous("MyWalletPhone.getWebViewLoginData()").toDictionary()
            else {
                Logger.shared.warning("loginData from wallet is empty")
                return
        }

        guard let walletJson = loginDataDict["walletJson"] as? String else {
            Logger.shared.warning("walletJson is nil")
            return
        }

        guard let externalJson = loginDataDict["externalJson"] is NSNull ? "" : loginDataDict["externalJson"] as? String else {
            Logger.shared.warning("externalJson is nil")
            return
        }

        guard let magicHash = loginDataDict["magicHash"] is NSNull ? "" : loginDataDict["magicHash"] as? String else {
            Logger.shared.warning("magicHash is nil")
            return
        }

        /// This isn't great but, `frontendInitialized` actually takes a few seconds to
        /// occur. When you present this screen, dismiss it, and the re-present it, `frontendInitialized`
        /// may not have happened just yet and `teardown` may still be in flight.
        /// This is to mitigate an issue where an `unauthorized` error occurs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.loadingViewPresenter.hide()
            buyBitcoinViewController.login(
                withJson: walletJson,
                externalJson: externalJson,
                magicHash: magicHash,
                password: self.walletManager.legacyRepository.legacyPassword
            )
            buyBitcoinViewController.delegate = self.walletManager.wallet

            let navigationController = BuyBitcoinNavigationController(
                rootViewController: buyBitcoinViewController,
                title: LocalizationConstants.SideMenu.buySellBitcoin
            )
            navigationController.modalPresentationStyle = .fullScreen
            UIApplication.shared.keyWindow?.rootViewController?.topMostViewController?.present(
                navigationController,
                animated: true
            )
        }
    }
}

extension BuySellCoordinator: WalletBuySellDelegate {

    func didCompleteTrade(with hash: String, date: String) {
        let actions = [UIAlertAction(title: LocalizationConstants.okString, style: .cancel, handler: nil),
                       UIAlertAction(title: LocalizationConstants.BuySell.viewDetails, style: .default, handler: { _ in
                        AppCoordinator.shared.tabControllerManager.showTransactionDetail(forHash: hash)
                       })]
        AlertViewPresenter.shared.standardNotify(message: String(format: LocalizationConstants.BuySell.tradeCompletedDetailArg, date),
                                                 title: LocalizationConstants.BuySell.tradeCompleted,
                                                 actions: actions)
    }

    func showCompletedTrade(tradeHash: String) {
        AppCoordinator.shared.closeSideMenu()
        AppCoordinator.shared.tabControllerManager.showTransactions(animated: true)
        AppCoordinator.shared.tabControllerManager.showTransactionDetail(forHash: tradeHash)
    }
}
