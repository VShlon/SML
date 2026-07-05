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
