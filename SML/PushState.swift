//
//  PushState.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - Источник правды для APNS token + deviceId
//  - При тапе по push: парсит payload (userInfo["sml"]) и публикует openCommand
//  Fix (external links):
//  - Ничего не ломаем: PushState по-прежнему строит URL
//  - Внешние ссылки НЕ блокируем тут (это делает WebView, чтобы не подменять Home)
//


import Foundation
import UIKit

final class PushState: ObservableObject {

    static let shared = PushState()

    @Published private(set) var apnsToken: String = ""
    @Published private(set) var deviceId: String = ""

    struct PushOpenCommand {
        let id: UUID
        let type: String
        let event: String
        let url: URL?
        let meta: [String: Any]
    }

    @Published var openCommand: PushOpenCommand?

    private let base = AppConfig.siteURL
    private let tokenKey = "sml.apns.token"
    private let deviceIdKey = "sml.device.id"

    private init() {
        let defaults = UserDefaults.standard
        let storedDeviceId = defaults.string(forKey: deviceIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let resolvedDeviceId = !storedDeviceId.isEmpty ? storedDeviceId : (!fallbackDeviceId.isEmpty ? fallbackDeviceId : "ios-device")

        deviceId = resolvedDeviceId
        defaults.set(resolvedDeviceId, forKey: deviceIdKey)

        let storedToken = defaults.string(forKey: tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedToken.isEmpty {
            apnsToken = storedToken
        }
    }

    func setApnsToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UserDefaults.standard.set(t, forKey: tokenKey)
        guard apnsToken != t else { return }
        apnsToken = t
    }

    func consumeOpenCommand(_ cmd: PushOpenCommand) {
        if openCommand?.id == cmd.id {
            openCommand = nil
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        let sml = extractDict(userInfo["sml"])
        let type = (extractString(sml["type"]) ?? "custom").trimmingCharacters(in: .whitespacesAndNewlines)
        let event = (extractString(sml["event"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let deeplinkStr = extractString(sml["deeplink"])
        let meta = extractDict(sml["meta"])

        let url = buildURL(deeplink: deeplinkStr, type: type, meta: meta)

        openCommand = PushOpenCommand(
            id: UUID(),
            type: type,
            event: event,
            url: url,
            meta: meta
        )
    }

    private func buildURL(deeplink: String?, type: String, meta: [String: Any]) -> URL? {
        let s = (deeplink ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !s.isEmpty {
            if s.lowercased().hasPrefix("https://") || s.lowercased().hasPrefix("http://") {
                return URL(string: s)
            }

            if s.lowercased().hasPrefix("sml://") {
                let rest = String(s.dropFirst("sml://".count))
                let path = rest.hasPrefix("/") ? rest : "/" + rest
                return URL(string: path, relativeTo: base)?.absoluteURL
            }

            if s.hasPrefix("/") {
                return URL(string: s, relativeTo: base)?.absoluteURL
            }

            return URL(string: "/" + s, relativeTo: base)?.absoluteURL
        }

        let t = type.lowercased()

        if t == "requests" {
            if let oid = extractInt(meta["order_id"]), oid > 0 {
                return AppConfig.url("/account/?order_id=\(oid)")
            }
            return AppConfig.url("/account/")
        }

        if t == "invoices" {
            if let iid = extractInt(meta["invoice_id"]), iid > 0 {
                return AppConfig.url("/account-invoices/?invoice_id=\(iid)")
            }
            return AppConfig.url("/account-invoices/")
        }

        return AppConfig.url("/account/")
    }

    private func extractDict(_ value: Any?) -> [String: Any] {
        if let d = value as? [String: Any] { return d }
        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in d {
                if let ks = k as? String {
                    out[ks] = v
                }
            }
            return out
        }
        return [:]
    }

    private func extractString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func extractInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
}
