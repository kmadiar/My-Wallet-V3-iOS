//
//  AppFeature.swift
//  Blockchain
//
//  Created by Chris Arriola on 5/9/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation

/// Enumerates app features that can be dynamically configured (e.g. enabled/disabled)
@objc
public enum AppFeature: Int, CaseIterable {
    case biometry
    case swipeToReceive
    case transferFundsFromImportedAddress

    /// Sunriver
    case stellar
    case stellarAirdrop
    case stellarAirdropPopup
    case stellarLargeBacklog

    /// Coinify
    case coinifyEnabled
    case notifyCoinifyUserToKyc

    /// Exchange linking enabled
    case exchangeLinking

    /// Exchange announcement visibility
    case exchangeAnnouncement

    /// The announcments
    case announcements

    /// Is simple buy enabled
    case simpleBuyEnabled
}

extension AppFeature {
    /// The remote key which determines if this feature is enabled or not
    public var remoteEnabledKey: String? {
        switch self {
        case .stellarAirdrop:
            return "ios_sunriver_airdrop_enabled"
        case .notifyCoinifyUserToKyc:
            return "ios_notify_coinify_users_to_kyc"
        case .stellarAirdropPopup:
            return "get_free_xlm_popup"
        case .stellarLargeBacklog:
            return "sunriver_has_large_backlog"
        case .exchangeLinking:
            return "pit_linking_enabled"
        case .exchangeAnnouncement:
            return "pit_show_announcement"
        case .announcements:
            return "announcements"
        case .simpleBuyEnabled:
            return "simple_buy_enabled"
        case .coinifyEnabled:
            return "coinify_enabled"
        case .biometry,
             .stellar,
             .swipeToReceive,
             .transferFundsFromImportedAddress:
            return nil
        }
    }
}
