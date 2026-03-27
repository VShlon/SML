//
//  AppConfig.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//

import Foundation
import UIKit
import SwiftUI

enum AppConfig {
    static let appName = "St. Marys Landscaping"
    static let shortName = "SML"

    static let siteHost = "stmaryslandscaping.ca"
    static let siteURL = URL(string: "https://stmaryslandscaping.ca")!
    static let whoamiURL = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/whoami")!

    static let phoneDisplay = "519-284-3111"
    static let phoneDigits = "5192843111"
    static let email = "info@stmaryslandscaping.ca"

    static let instagramURL = URL(string: "https://www.instagram.com/stmaryslandscaping/")!
    static let facebookURL = URL(string: "https://www.facebook.com/sml.canada")!

    static let brandColor = UIColor(red: 67/255.0, green: 130/255.0, blue: 57/255.0, alpha: 1.0) // #438239
    static let brandColorSwiftUI = Color(uiColor: brandColor)

    static let bundleId = Bundle.main.bundleIdentifier ?? ""
    static let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    static let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""

    static var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func url(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(string: path, relativeTo: siteURL)!.absoluteURL
        }
        return URL(string: "/" + path, relativeTo: siteURL)!.absoluteURL
    }

    static func isInternalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == siteHost || h.hasSuffix("." + siteHost)
    }
}
