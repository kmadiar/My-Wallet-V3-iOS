//
//  AnnouncementPresenter.swift
//  Blockchain
//
//  Created by Daniel Huri on 18/07/2019.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import RxSwift
import RxCocoa
import PlatformUIKit
import PlatformKit

// TODO: Tests - Create a protocol for tests, and inject protocol dependencies.

/// Describes the announcement visual. Plays as a presenter / provide for announcements,
/// By creating a list of pending announcements, on which subscribers can be informed.
final class AnnouncementPresenter {
    
    // MARK: Services
    
    private let appCoordinator: AppCoordinator
    private let featureConfigurator: FeatureConfiguring
    private let featureFetcher: FeatureFetching
    private let airdropRouter: AirdropRouterAPI
    private let kycCoordinator: KYCCoordinator
    private let exchangeCoordinator: ExchangeCoordinator
    private let wallet: Wallet
    private let kycSettings: KYCSettingsAPI
    private let reactiveWallet: ReactiveWallet
    
    private let interactor: AnnouncementInteracting
    
    // MARK: - Rx

    /// Returns a driver with `.none` as default value for announcement action
    /// Scheduled on be executed on main scheduler, its resources are shared and it remembers the last value.
    var announcement: Driver<AnnouncementDisplayAction> {
        return announcementRelay
            .asDriver()
            .distinctUntilChanged()
    }
    
    private let announcementRelay = BehaviorRelay<AnnouncementDisplayAction>(value: .hide)
    private let disposeBag = DisposeBag()
    
    private var currentAnnouncement: Announcement?
    
    // MARK: - Setup
    
    init(interactor: AnnouncementInteracting = AnnouncementInteractor(),
         featureConfigurator: FeatureConfiguring = AppFeatureConfigurator.shared,
         featureFetcher: FeatureFetching = AppFeatureConfigurator.shared,
         airdropRouter: AirdropRouterAPI = AppCoordinator.shared.airdropRouter,
         appCoordinator: AppCoordinator = .shared,
         exchangeCoordinator: ExchangeCoordinator = .shared,
         kycCoordinator: KYCCoordinator = .shared,
         reactiveWallet: ReactiveWallet = ReactiveWallet(),
         kycSettings: KYCSettingsAPI = KYCSettings.shared,
         wallet: Wallet = WalletManager.shared.wallet) {
        self.interactor = interactor
        self.appCoordinator = appCoordinator
        self.exchangeCoordinator = exchangeCoordinator
        self.kycCoordinator = kycCoordinator
        self.airdropRouter = airdropRouter
        self.reactiveWallet = reactiveWallet
        self.kycSettings = kycSettings
        self.featureConfigurator = featureConfigurator
        self.featureFetcher = featureFetcher
        self.wallet = wallet
        
        announcement
            .asObservable()
            .filter { $0.isHide }
            .mapToVoid()
            .bind(weak: self) { (self) in
                self.currentAnnouncement = nil
            }
            .disposed(by: disposeBag)
    }
    
    /// Refreshes announcements on demand
    func refresh() {
        reactiveWallet
            .waitUntilInitialized
            .bind { [weak self] _ in
                self?.calculate()
            }
            .disposed(by: disposeBag)
    }
    
    private func calculate() {
        let announcementsMetadata: Single<AnnouncementsMetadata> = featureFetcher.fetch(for: .announcements)
        let data: Single<AnnouncementPreliminaryData> = interactor.preliminaryData
        Single
            .zip(announcementsMetadata, data)
            .flatMap(weak: self) { (self, payload) -> Single<AnnouncementDisplayAction> in
                let action = self.resolve(metadata: payload.0, preliminaryData: payload.1)
                return .just(action)
            }
            .catchErrorJustReturn(.hide)
            .asObservable()
            .bind(to: announcementRelay)
            .disposed(by: disposeBag)
    }
    
    /// Resolves the first valid announcement according by the provided types and preloiminary data
    private func resolve(metadata: AnnouncementsMetadata,
                         preliminaryData: AnnouncementPreliminaryData) -> AnnouncementDisplayAction {
        for type in metadata.order {
            let announcement: Announcement
            switch type {
            case .blockstackAirdropReceived:
                announcement = receivedBlockstackAirdrop(
                    hasReceivedBlockstackAirdrop: preliminaryData.hasReceivedBlockstackAirdrop
                )
            case .blockstackAirdropRegisteredMini:
                announcement = airdropRegisterd(user: preliminaryData.user)
            case .verifyEmail:
                announcement = verifyEmail(user: preliminaryData.user)
            case .walletIntro:
                announcement = walletIntro(reappearanceTimeInterval: metadata.interval)
            case .twoFA:
                announcement = twoFA(data: preliminaryData, reappearanceTimeInterval: metadata.interval)
            case .backupFunds:
                announcement = backupFunds(reappearanceTimeInterval: metadata.interval)
            case .buyBitcoin:
                announcement = buyBitcoin(
                    reappearanceTimeInterval: metadata.interval,
                    isSimpleBuyFlow: preliminaryData.isSimpleBuyFlow
                )
            case .transferBitcoin:
                announcement = transferBitcoin(
                    isKycSupported: preliminaryData.isKycSupported,
                    reappearanceTimeInterval: metadata.interval
                )
            case .kycAirdrop:
                announcement = kycAirdrop(
                    user: preliminaryData.user,
                    tiers: preliminaryData.tiers,
                    isKycSupported: preliminaryData.isKycSupported,
                    reappearanceTimeInterval: metadata.interval
                )
            case .verifyIdentity:
                announcement = verifyIdentity(using: preliminaryData.user)
            case .swap:
                announcement = swap(using: preliminaryData, reappearanceTimeInterval: metadata.interval)
            case .coinifyKyc:
                announcement = coinifyKyc(tiers: preliminaryData.tiers, reappearanceTimeInterval: metadata.interval)
            case .exchangeLinking:
                announcement = exchangeLinking(user: preliminaryData.user)
            case .bitpay:
                announcement = bitpay
            case .pax:
                announcement = pax(hasPaxTransactions: preliminaryData.hasPaxTransactions)
            case .resubmitDocuments:
                announcement = resubmitDocuments(user: preliminaryData.user)
            case .simpleBuyPendingTransaction:
                announcement = simpleBuyPendingTransaction(
                    hasPendingTransactionFor: preliminaryData.pendingSimpleBuyOrderAssetType
                )
            case .simpleBuyKYCIncomplete:
                announcement = simpleBuyFinishSignup(
                    tiers: preliminaryData.tiers,
                    hasIncompleteBuyFlow: preliminaryData.hasIncompleteBuyFlow
                )
            }
            // Return the first different announcement that should show
            if announcement.shouldShow {
                if currentAnnouncement?.type != announcement.type {
                    currentAnnouncement = announcement
                    return .show(announcement.viewModel)
                } else { // Announcement is currently displaying
                    return .none
                }
            }
        }
        // None of the types were resolved into a displayable announcement
        return .none
    }
    
    // MARK: - Accessors
    
    /// Hides whichever announcement is now displaying
    private func hideAnnouncement() {
        announcementRelay.accept(.hide)
    }
}

// MARK: - Computes announcements

extension AnnouncementPresenter {

    /// Computes email verification announcement
    private func verifyEmail(user: NabuUser) -> Announcement {
        return VerifyEmailAnnouncement(
            isEmailVerified: user.email.verified,
            action: UIApplication.shared.openMailApplication
          )
    }

    /// Computes Simple Buy Pending Transaction Announcement
    private func simpleBuyPendingTransaction(hasPendingTransactionFor assetType: CryptoCurrency?) -> Announcement {
        return SimpleBuyPendingTransactionAnnouncement(
            hasPendingTransactionFor: assetType,
            action: { [weak self] in
                guard let self = self else { return }
                self.hideAnnouncement()
                self.appCoordinator.handleBuyCrypto(simpleBuy: true)
            }
        )
    }
    
    /// Computes Simple Buy Finish Signup Announcement
    private func simpleBuyFinishSignup(tiers: KYC.UserTiers,
                                       hasIncompleteBuyFlow: Bool) -> Announcement {
        return SimpleBuyFinishSignupAnnouncement(
            canCompleteTier2: tiers.canCompleteTier2,
            hasIncompleteBuyFlow: hasIncompleteBuyFlow,
            action: { [weak self] in
                guard let self = self else { return }
                self.hideAnnouncement()
                self.appCoordinator.handleBuyCrypto(simpleBuy: true)
            }
        )
    }

    // Computes Wallet Intro card announcement
    private func walletIntro(reappearanceTimeInterval: TimeInterval) -> Announcement {
        return WalletIntroAnnouncement(
            reappearanceTimeInterval: reappearanceTimeInterval,
            action: { [weak self] in
               guard let self = self else { return }
               self.hideAnnouncement()
               self.appCoordinator.tabControllerManager.tabViewController.setupIntroduction()
            },
            dismiss: hideAnnouncement
        )
    }
    
    // Computes kyc airdrop announcement
    private func kycAirdrop(user: NabuUser,
                            tiers: KYC.UserTiers,
                            isKycSupported: Bool,
                            reappearanceTimeInterval: TimeInterval) -> Announcement {
        return KycAirdropAnnouncement(
            canCompleteTier2: tiers.canCompleteTier2,
            isKycSupported: isKycSupported,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: { [weak self] in
                guard let self = self else { return }
                let tier = user.tiers?.selected ?? .tier1
                self.kycCoordinator.start(from: self.appCoordinator.tabControllerManager, tier: tier)
            }
        )
    }
    
    // Computes transfer in bitcoin announcement
    private func transferBitcoin(isKycSupported: Bool, reappearanceTimeInterval: TimeInterval) -> Announcement {
        return TransferInCryptoAnnouncement(
            isKycSupported: isKycSupported,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: { [weak self] in
               guard let self = self else { return }
               self.hideAnnouncement()
               self.appCoordinator.switchTabToReceive()
            }
        )
    }
    
    /// Computes identity verification card announcement
    private func verifyIdentity(using user: NabuUser) -> Announcement {
        return VerifyIdentityAnnouncement(
            user: user,
            isCompletingKyc: kycSettings.isCompletingKyc,
            dismiss: hideAnnouncement,
            action: { [weak self] in
                guard let self = self else { return }
                let tier = user.tiers?.selected ?? .tier1
                self.kycCoordinator.start(from: self.appCoordinator.tabControllerManager, tier: tier)
            }
        )
    }
    
    /// Computes Bitpay announcement
    private var bitpay: Announcement {
        return BitpayAnnouncement(dismiss: hideAnnouncement)
    }
    
    /// Computes Wallet-Exchange linking announcement
    private func exchangeLinking(user: NabuUser) -> Announcement {
        let isFeatureEnabled = featureConfigurator.configuration(for: .exchangeAnnouncement).isEnabled
        let shouldShowExchangeAnnouncement = isFeatureEnabled && !user.hasLinkedExchangeAccount
        return ExchangeLinkingAnnouncement(
            shouldShowExchangeAnnouncement: shouldShowExchangeAnnouncement,
            dismiss: hideAnnouncement,
            action: exchangeCoordinator.start
        )
    }
        
    /// Computes an airdrop received card announcement
    private func receivedBlockstackAirdrop(hasReceivedBlockstackAirdrop: Bool) -> Announcement {
        return BlockstackAirdropReceivedAnnouncement(
            hasReceivedBlockstackAirdrop: hasReceivedBlockstackAirdrop,
            dismiss: hideAnnouncement,
            action: { [weak self] in
                self?.airdropRouter.presentAirdropStatusScreen(
                    for: .blockstack,
                    presentationType: .modalOverTopMost
                )
            }
        )
    }
    
    private func airdropRegisterd(user: NabuUser) -> Announcement {
        return AirdropRegisteredAnnouncementMini(
            router: airdropRouter,
            airdropRegistered: user.isBlockstackAirdropRegistered
        )
    }
    
    /// Computes PAX card announcement
    private func pax(hasPaxTransactions: Bool) -> Announcement {
        return PAXAnnouncement(
            hasTransactions: hasPaxTransactions,
            dismiss: hideAnnouncement,
            action: appCoordinator.switchTabToSwap
        )
    }
    
    /// Computes Buy BTC announcement
    private func buyBitcoin(reappearanceTimeInterval: TimeInterval, isSimpleBuyFlow: Bool) -> Announcement {
        let isCoinifyEnabled = featureConfigurator.configuration(for: .coinifyEnabled).isEnabled
        let isEnabled = (isSimpleBuyFlow && !wallet.isBitcoinWalletFunded)
            || (isCoinifyEnabled && wallet.isBuyEnabled() && !wallet.isBitcoinWalletFunded)
        return BuyBitcoinAnnouncement(
            isEnabled: isEnabled,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: { [weak appCoordinator] in
                appCoordinator?.handleBuyCrypto(simpleBuy: isSimpleBuyFlow)
            }
        )
    }

    /// Computes Swap card announcement
    private func swap(using data: AnnouncementPreliminaryData,
                      reappearanceTimeInterval: TimeInterval) -> Announcement {
        return SwapAnnouncement(
            hasTrades: data.hasTrades,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: appCoordinator.switchTabToSwap
        )
    }

    // TODO: `wallet.getTotalActiveBalance()` is wrong because it doesn't deduce the state of all asset
    // accounts. only BTC is included. therefore, we should have a service that does it.
    // TICKET: IOS-2503 - iOS Wallet Networking | Replace JS network calls with native
    
    /// Computes Backup Funds (recovery phrase)
    private func backupFunds(reappearanceTimeInterval: TimeInterval) -> Announcement {
        let shouldBackupFunds = !wallet.isRecoveryPhraseVerified() && wallet.isBitcoinWalletFunded
        return BackupFundsAnnouncement(
            shouldBackupFunds: shouldBackupFunds,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: appCoordinator.showBackupView
        )
    }
    
    /// Computes 2FA announcement
    private func twoFA(data: AnnouncementPreliminaryData, reappearanceTimeInterval: TimeInterval) -> Announcement {
        let shouldEnable2FA = !data.hasTwoFA && wallet.isBitcoinWalletFunded
        return Enable2FAAnnouncement(
            shouldEnable2FA: shouldEnable2FA,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: { [weak self] in
                self?.appCoordinator.showSettingsView()
            }
        )
    }
    
    /// Computes Coinify KYC alert announcement
    private func coinifyKyc(tiers: KYC.UserTiers,
                            reappearanceTimeInterval: TimeInterval) -> Announcement {
        let coinifyFeatureFlag = featureConfigurator.configuration(for: .coinifyEnabled)
        let coinifyConfig = featureConfigurator.configuration(for: .notifyCoinifyUserToKyc)
        
        let approve = { [weak self] in
            let rootVC = UIApplication.shared.keyWindow!.rootViewController!
            self?.kycCoordinator.start(from: rootVC, tier: .tier2)
        }

        return CoinifyKycAnnouncement(
            configuration: coinifyConfig,
            isCoinifyEnabled: coinifyFeatureFlag.isEnabled,
            tiers: tiers,
            wallet: wallet,
            reappearanceTimeInterval: reappearanceTimeInterval,
            dismiss: hideAnnouncement,
            action: approve
        )
    }
    
    /// Computes Upload Documents card announcement
    private func resubmitDocuments(user: NabuUser) -> Announcement {
        return ResubmitDocumentsAnnouncement(
            user: user,
            dismiss: hideAnnouncement,
            action: { [weak self] in
                guard let self = self else { return }
                let tier = user.tiers?.selected ?? .tier1
                self.kycCoordinator.start(from: self.appCoordinator.tabControllerManager, tier: tier)
            }
        )
    }
}
