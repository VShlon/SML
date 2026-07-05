//
//  SocialLoginManager.swift
//  SML
//
//  Handles native social login:
//  - Apple: ASAuthorizationController (native Sign In with Apple)
//  - Google / Facebook: ASWebAuthenticationSession with prefersEphemeralWebBrowserSession = false
//
//  After web OAuth the manager exchanges a one-time key via URLSession, transfers the
//  resulting auth cookies from HTTPCookieStorage.shared to WKWebView, then loads /account/.
//
//  After Apple native auth the identity token is sent to /wp-json/sml/v1/app-social-login.
//

import Foundation
import AuthenticationServices
import UIKit
import WebKit

enum SocialLoginResult {
    case success(userId: Int, role: String)
    case failure(String)
    case cancelled
}

final class SocialLoginManager: NSObject {

    static let shared = SocialLoginManager()

    private let siteBase = "https://stmaryslandscaping.ca"

    private weak var presentingViewController: UIViewController?
    private weak var webView: WKWebView?
    private var onComplete: ((SocialLoginResult) -> Void)?

    private var appleAuthController: ASAuthorizationController?
    private var webAuthSession: ASWebAuthenticationSession?

    // Used by loginLink(apple) to pass the link token into the Apple delegate callback.
    private var pendingLinkToken: String?

    private override init() {}

    func login(provider: String,
               from vc: UIViewController,
               webView: WKWebView,
               completion: @escaping (SocialLoginResult) -> Void) {
        self.presentingViewController = vc
        self.webView = webView
        self.onComplete = completion

        switch provider {
        case "apple":    loginWithApple()
        case "google":   loginWithWebOAuth(provider: "google")
        case "facebook": loginWithWebOAuth(provider: "facebook")
        default:
            completion(.failure("Unknown provider: \(provider)"))
        }
    }

    // MARK: - Link social provider to existing account (from account-details page)

    func loginLink(provider: String,
                   from vc: UIViewController,
                   webView: WKWebView,
                   completion: @escaping (SocialLoginResult) -> Void) {
        self.presentingViewController = vc
        self.webView = webView
        self.onComplete = completion

        // Copy WKWebView auth cookies to HTTPCookieStorage.shared so URLSession
        // can authenticate the link-token request against WordPress.
        copyWKCookiesToShared(webView: webView) { [weak self] in
            guard let self else { return }
            self.fetchLinkToken(provider: provider) { [weak self] token in
                guard let self else { return }
                guard let token else {
                    self.finish(.failure("Could not get link token. Make sure you are signed in."))
                    return
                }
                if provider == "apple" {
                    self.pendingLinkToken = token
                    DispatchQueue.main.async { self.loginWithApple() }
                } else {
                    self.startLinkOAuth(provider: provider, linkToken: token)
                }
            }
        }
    }

    // Copy cookies from WKWebView's isolated store into HTTPCookieStorage.shared
    // so subsequent URLSession requests carry the WordPress auth cookie.
    private func copyWKCookiesToShared(webView: WKWebView, completion: @escaping () -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.lowercased().contains("stmaryslandscaping") {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    // POST admin-ajax.php?action=sml_get_link_token using the WordPress auth cookie
    // (already in HTTPCookieStorage.shared from copyWKCookiesToShared).
    private func fetchLinkToken(provider: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(siteBase)/wp-admin/admin-ajax.php") else {
            completion(nil); return
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = provider.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider
        req.httpBody = "action=sml_get_link_token&provider=\(encoded)".data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success,
                  let inner = json["data"] as? [String: Any],
                  let token = inner["token"] as? String else {
                completion(nil); return
            }
            completion(token)
        }.resume()
    }

    // Launch ASWebAuthenticationSession for Google/Facebook link flow.
    // Server's sml_social_start() reads link_token, sets intent=link + link_uid cookie,
    // and sml_social_link_to_current_user() redirects to sml://auth-link?provider=PROVIDER.
    private func startLinkOAuth(provider: String, linkToken: String) {
        let encodedRedirect = "sml://auth-link".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "sml://auth-link"
        let encodedToken = linkToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? linkToken
        let startURLString = "\(siteBase)/auth/\(provider)/start/?redirect_to=\(encodedRedirect)&link_token=\(encodedToken)"
        guard let authURL = URL(string: startURLString) else {
            finish(.failure("Invalid link auth URL for \(provider)"))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "sml") { [weak self] callbackURL, error in
                guard let self else { return }
                if let error = error as? ASWebAuthenticationSessionError {
                    self.finish(error.code == .canceledLogin ? .cancelled : .failure(error.localizedDescription))
                    return
                }
                if let error { self.finish(.failure(error.localizedDescription)); return }
                // Reload account-details so the Connected accounts section refreshes.
                let reloadURL = URL(string: "\(self.siteBase)/account-details/")
                DispatchQueue.main.async { [weak self] in
                    if let url = reloadURL { self?.webView?.load(URLRequest(url: url)) }
                }
                self.finish(.success(userId: 0, role: ""))
            }
            session.presentationContextProvider = self
            // Link flow uses an ephemeral session so Facebook/Google don't try to
            // reuse an existing Safari authorization and hit a state conflict.
            session.prefersEphemeralWebBrowserSession = true
            self.webAuthSession = session
            session.start()
        }
    }

    // MARK: - Apple (native ASAuthorizationController)

    private func loginWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
        appleAuthController = controller
    }

    // MARK: - Google / Facebook (ASWebAuthenticationSession)

    private func loginWithWebOAuth(provider: String) {
        let encoded = "sml://auth".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "sml://auth"
        let startURLString = "\(siteBase)/auth/\(provider)/start/?redirect_to=\(encoded)"
        guard let authURL = URL(string: startURLString) else {
            finish(.failure("Invalid auth URL for \(provider)"))
            return
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "sml") { [weak self] callbackURL, error in
            guard let self else { return }
            if let error = error as? ASWebAuthenticationSessionError {
                self.finish(error.code == .canceledLogin ? .cancelled : .failure(error.localizedDescription))
                return
            }
            if let error { self.finish(.failure(error.localizedDescription)); return }
            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let key = components.queryItems?.first(where: { $0.name == "key" })?.value,
                  !key.isEmpty else {
                self.finish(.failure("No login key received"))
                return
            }
            self.exchangeKeyForSession(key: key)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    // MARK: - Key exchange (Google / Facebook)

    private func exchangeKeyForSession(key: String) {
        guard let url = URL(string: "\(siteBase)/wp-json/sml/v1/app-login?key=\(key)") else {
            finish(.failure("Invalid key exchange URL"))
            return
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            if let error { self.finish(.failure(error.localizedDescription)); return }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok else {
                let msg = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["error"] as? String
                self.finish(.failure(msg ?? "Key exchange failed"))
                return
            }

            let userId = json["user_id"] as? Int ?? 0
            let role   = json["role"]    as? String ?? "subscriber"

            self.transferCookiesToWebView {
                self.finish(.success(userId: userId, role: role))
            }
        }.resume()
    }

    // MARK: - Apple native token -> server

    private func sendAppleTokenToServer(token: String, name: String?) {
        // If pendingLinkToken is set, this is a link-account call, not a login.
        if let linkToken = pendingLinkToken {
            pendingLinkToken = nil
            linkAppleAccount(appleToken: token, linkToken: linkToken)
            return
        }

        guard let url = URL(string: "\(siteBase)/wp-json/sml/v1/app-social-login") else {
            finish(.failure("Invalid API URL"))
            return
        }

        var body: [String: String] = ["provider": "apple", "token": token]
        if let name, !name.isEmpty { body["name"] = name }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            if let error { self.finish(.failure(error.localizedDescription)); return }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok else {
                let errMsg = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["message"] as? String
                self.finish(.failure(errMsg ?? "Server error"))
                return
            }

            let userId = json["user_id"] as? Int ?? 0
            let role   = json["role"]    as? String ?? "subscriber"

            self.transferCookiesToWebView {
                self.finish(.success(userId: userId, role: role))
            }
        }.resume()
    }

    // MARK: - Apple link account

    private func linkAppleAccount(appleToken: String, linkToken: String) {
        guard let url = URL(string: "\(siteBase)/wp-json/sml/v1/app-link-apple") else {
            finish(.failure("Invalid Apple link URL"))
            return
        }

        let body: [String: String] = ["token": appleToken, "link_token": linkToken]

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            if let error { self.finish(.failure(error.localizedDescription)); return }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok else {
                let msg = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["message"] as? String
                self.finish(.failure(msg ?? "Apple link failed"))
                return
            }

            let reloadURL = URL(string: "\(self.siteBase)/account-details/")
            DispatchQueue.main.async { [weak self] in
                if let url = reloadURL { self?.webView?.load(URLRequest(url: url)) }
            }
            self.finish(.success(userId: 0, role: ""))
        }.resume()
    }

    // MARK: - Cookie transfer

    private func transferCookiesToWebView(then done: @escaping () -> Void) {
        guard let webView else { done(); return }
        let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
        let cookieStore   = webView.configuration.websiteDataStore.httpCookieStore
        let group         = DispatchGroup()
        for cookie in sharedCookies where cookie.domain.lowercased().contains("stmaryslandscaping") {
            group.enter()
            DispatchQueue.main.async {
                cookieStore.setCookie(cookie) { group.leave() }
            }
        }
        group.notify(queue: .main) { [weak webView] in
            if let url = URL(string: "https://stmaryslandscaping.ca/account/") {
                webView?.load(URLRequest(url: url))
            }
            done()
        }
    }

    // MARK: - Finish

    private func finish(_ result: SocialLoginResult) {
        DispatchQueue.main.async { [weak self] in
            self?.onComplete?(result)
            self?.onComplete = nil
        }
    }
}

// MARK: - Apple delegate

extension SocialLoginManager: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finish(.failure("Apple: could not read identity token"))
            return
        }
        var fullName = ""
        if let nameComp = credential.fullName {
            let parts = [nameComp.givenName, nameComp.familyName].compactMap { $0 }
            fullName = parts.joined(separator: " ")
        }
        sendAppleTokenToServer(token: token, name: fullName.isEmpty ? nil : fullName)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        finish(nsError.code == ASAuthorizationError.canceled.rawValue ? .cancelled : .failure(error.localizedDescription))
    }
}

extension SocialLoginManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentingViewController?.view.window ?? UIWindow()
    }
}

extension SocialLoginManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentingViewController?.view.window ?? UIWindow()
    }
}
