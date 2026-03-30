//
//  WebView.swift
//  SML
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - WKWebView внутри SwiftUI
//  - Общие cookies/сессия (.default)
//  - ROLE BRIDGE: whoami -> RoleState
//  - Cookie sync fallback -> RoleState.refresh()
//  - Inject apnsToken + deviceId
//  - External links blocked, кроме разрешенных хостов для reCAPTCHA
//  - Native Face ID кнопка на login page в app версии
//

import SwiftUI
import WebKit
import UIKit

struct WebNavigationCommand: Equatable {
    let id: UUID
    let url: URL
}

struct WebView: UIViewControllerRepresentable {

    let url: URL
    let apnsToken: String
    let deviceId: String
    let biometricEnabled: Bool
    let hasBiometricLogin: Bool
    let command: WebNavigationCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> WebViewController {
        let vc = WebViewController()
        vc.coordinator = context.coordinator
        context.coordinator.hostViewController = vc

        context.coordinator.setCurrent(
            apnsToken: apnsToken,
            deviceId: deviceId,
            biometricEnabled: biometricEnabled,
            hasBiometricLogin: hasBiometricLogin
        )
        context.coordinator.setCommand(command)

        vc.initialURL = url
        vc.initialCommand = command

        return vc
    }

    func updateUIViewController(_ vc: WebViewController, context: Context) {
        context.coordinator.setCurrent(
            apnsToken: apnsToken,
            deviceId: deviceId,
            biometricEnabled: biometricEnabled,
            hasBiometricLogin: hasBiometricLogin
        )
        context.coordinator.setCommand(command)

        if let wv = vc.webView {
            context.coordinator.applyCommandIfNeeded(webView: wv)
            if context.coordinator.didFinishOnce {
                context.coordinator.tryInjectIntoPage(webView: wv, force: false)
                context.coordinator.refreshNativeFaceIDButton(webView: wv)
            }
        }
    }
}

final class WebViewController: UIViewController {

    fileprivate var webView: WKWebView?
    fileprivate weak var coordinator: WebView.Coordinator?

    fileprivate var initialURL: URL?
    fileprivate var initialCommand: WebNavigationCommand?

    private var didLoadInitial = false

    private var faceIDButton: UIButton?
    private var faceIDTrailingConstraint: NSLayoutConstraint?
    private var faceIDBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 13.0, *) {
            wv.configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        }

        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 SMLApp-iOS/1.0"

        view.addSubview(wv)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            wv.topAnchor.constraint(equalTo: g.topAnchor),
            wv.bottomAnchor.constraint(equalTo: g.bottomAnchor),
        ])

        if let coordinator {
            coordinator.hostViewController = self
            coordinator.attachedWebView = wv
            wv.navigationDelegate = coordinator
            wv.uiDelegate = coordinator
            wv.configuration.userContentController.add(coordinator, name: "smlWhoami")
            wv.configuration.userContentController.add(coordinator, name: "smlBiometric")
        }

        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.contentInset = .zero
        wv.scrollView.scrollIndicatorInsets = .zero
        if #available(iOS 15.0, *) {
            wv.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        }

        wv.isOpaque = false
        wv.backgroundColor = .systemBackground
        wv.scrollView.backgroundColor = .systemBackground

        self.webView = wv

        setupFaceIDButton()
        loadInitialIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadInitialIfNeeded()
    }

    private func setupFaceIDButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.isEnabled = false
        button.alpha = 0

        if let image = UIImage(systemName: "faceid") {
            button.setImage(image, for: .normal)
        } else {
            button.setTitle("Face ID", for: .normal)
        }

        button.tintColor = UIColor.systemBlue
        button.backgroundColor = UIColor.white
        button.layer.cornerRadius = 28
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.18).cgColor
        button.layer.shadowOpacity = 1
        button.layer.shadowRadius = 10
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.addTarget(self, action: #selector(didTapFaceIDButton), for: .touchUpInside)

        view.addSubview(button)

        let trailing = button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        let bottom = button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)

        NSLayoutConstraint.activate([
            trailing,
            bottom,
            button.widthAnchor.constraint(equalToConstant: 56),
            button.heightAnchor.constraint(equalToConstant: 56)
        ])

        faceIDTrailingConstraint = trailing
        faceIDBottomConstraint = bottom
        faceIDButton = button
    }

    @objc
    private func didTapFaceIDButton() {
        coordinator?.triggerBiometricFromNativeUI()
    }

    fileprivate func setFaceIDButtonVisible(_ visible: Bool, enabled: Bool) {
        guard let button = faceIDButton else { return }

        button.isEnabled = enabled
        button.isHidden = !visible

        UIView.animate(withDuration: 0.18) {
            button.alpha = visible ? 1 : 0
        }
    }

    fileprivate func positionFaceIDButton(x: CGFloat, y: CGFloat) {
        guard let trailing = faceIDTrailingConstraint, let bottom = faceIDBottomConstraint else { return }
        trailing.constant = x
        bottom.constant = y
        view.layoutIfNeeded()
    }

    private func loadInitialIfNeeded() {
        guard let wv = webView, let coordinator else { return }
        guard !didLoadInitial else { return }
        didLoadInitial = true

        let base = initialURL ?? URL(string: "https://stmaryslandscaping.ca/")!

        if let cmd = initialCommand {
            coordinator.markCommandHandled(cmd.id)
            if coordinator.isExternalURL(cmd.url) {
                wv.load(URLRequest(url: base))
            } else {
                wv.load(URLRequest(url: cmd.url))
            }
        } else {
            wv.load(URLRequest(url: base))
        }
    }
}

extension WebView {

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

        private var currentToken: String = ""
        private var currentDeviceId: String = ""
        private var currentBiometricEnabled: Bool = SMCBiometricSettings.shared.isEnabled
        private var currentHasBiometricLogin: Bool = SMCKeychain.hasLogin()
        private var pendingCredentialSave: SMCStoredLogin? = nil

        private var lastInjectedToken: String = ""
        private var lastInjectedDeviceId: String = ""
        private var lastInjectedURL: String = ""

        private var pendingCommand: WebNavigationCommand? = nil
        private var lastHandledCommandId: UUID? = nil

        fileprivate var didFinishOnce: Bool = false

        private let allowedHost = "stmaryslandscaping.ca"

        private let allowedExternalHosts: Set<String> = [
            "google.com",
            "www.google.com",
            "gstatic.com",
            "www.gstatic.com",
            "recaptcha.net",
            "www.recaptcha.net"
        ]

        weak var attachedWebView: WKWebView?
        weak var hostViewController: WebViewController?

        private var lastCookieSyncAt: TimeInterval = 0
        private let cookieSyncMinInterval: TimeInterval = 1.0

        private var lastWhoamiAt: TimeInterval = 0
        private let whoamiMinInterval: TimeInterval = 1.0

        private let cookieWorkQueue = DispatchQueue.global(qos: .utility)

        func setCurrent(apnsToken: String, deviceId: String, biometricEnabled: Bool, hasBiometricLogin: Bool) {
            currentToken = apnsToken.trimmingCharacters(in: .whitespacesAndNewlines)
            currentDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
            currentBiometricEnabled = biometricEnabled
            currentHasBiometricLogin = hasBiometricLogin

            if let webView = attachedWebView {
                refreshNativeFaceIDButton(webView: webView)
            } else {
                updateNativeFaceIDButton(visible: false, enabled: false)
            }
        }

        func setCommand(_ command: WebNavigationCommand?) {
            pendingCommand = command
        }

        func markCommandHandled(_ id: UUID) {
            lastHandledCommandId = id
        }

        func triggerBiometricFromNativeUI() {
            guard let webView = attachedWebView else { return }
            promptForBiometricLoginIfNeeded(webView: webView)
        }

        func refreshNativeFaceIDButton(webView: WKWebView) {
            let urlString = webView.url?.absoluteString.lowercased() ?? ""
            let path = webView.url?.path.lowercased() ?? ""
            let looksLikeLogin = path.contains("/login") || urlString.contains("wp-login") || urlString.contains("/account")

            let canShow =
                looksLikeLogin &&
                currentBiometricEnabled &&
                currentHasBiometricLogin &&
                BiometricAuthManager.shared.canUseBiometrics()

            updateNativeFaceIDButton(visible: canShow, enabled: canShow)

            if canShow {
                layoutNativeFaceIDButton(on: webView, enabled: true)
            }
        }

        private func updateNativeFaceIDButton(visible: Bool, enabled: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.hostViewController?.setFaceIDButtonVisible(visible, enabled: enabled)
            }
        }

        private func layoutNativeFaceIDButton(on webView: WKWebView, enabled: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.hostViewController?.positionFaceIDButton(x: -16, y: -20)
                self?.hostViewController?.setFaceIDButtonVisible(enabled, enabled: enabled)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "smlWhoami" {
                if let dict = message.body as? [String: Any] {
                    let role = ((dict["role"] as? String) ?? "").lowercased()
                    let authenticated =
                        (dict["authenticated"] as? Bool) == true ||
                        (dict["logged_in"] as? Bool) == true

                    let isAuthorizedPayload = authenticated || (!role.isEmpty && role != "guest")

                    if isAuthorizedPayload, currentBiometricEnabled, let pendingCredentialSave {
                        _ = SMCKeychain.save(login: pendingCredentialSave)
                        self.pendingCredentialSave = nil
                        self.currentHasBiometricLogin = true
                        DispatchQueue.main.async {
                            PushState.shared.refreshBiometricState()
                        }
                    }

                    DispatchQueue.main.async {
                        RoleState.shared.setRoleFromBridge(payload: dict)
                    }
                } else if let s = message.body as? String {
                    DispatchQueue.main.async {
                        RoleState.shared.setRoleFromBridge(role: s)
                    }
                }

                if let webView = attachedWebView {
                    refreshNativeFaceIDButton(webView: webView)
                }

                return
            }

            guard message.name == "smlBiometric" else { return }
            guard let dict = message.body as? [String: Any], let action = dict["action"] as? String else { return }

            switch action {
            case "captureLogin":
                let username = ((dict["username"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let password = (dict["password"] as? String) ?? ""
                guard !username.isEmpty, !password.isEmpty else { return }
                pendingCredentialSave = SMCStoredLogin(username: username, password: password)

            case "trigger":
                guard let webView = attachedWebView else { return }
                promptForBiometricLoginIfNeeded(webView: webView)

            case "clear":
                pendingCredentialSave = nil
                SMCKeychain.deleteLogin()
                currentHasBiometricLogin = false
                DispatchQueue.main.async {
                    PushState.shared.refreshBiometricState()
                }
                updateNativeFaceIDButton(visible: false, enabled: false)

            default:
                break
            }
        }

        private func isAllowedExternalHost(_ host: String) -> Bool {
            if allowedExternalHosts.contains(host) {
                return true
            }

            for h in allowedExternalHosts {
                if host.hasSuffix("." + h) {
                    return true
                }
            }

            return false
        }

        func isExternalURL(_ url: URL) -> Bool {
            let scheme = (url.scheme ?? "").lowercased()
            if scheme != "http" && scheme != "https" {
                return false
            }

            let host = (url.host ?? "").lowercased()
            if host.isEmpty {
                return false
            }

            if host == allowedHost || host.hasSuffix("." + allowedHost) {
                return false
            }

            if isAllowedExternalHost(host) {
                return false
            }

            return true
        }

        func applyCommandIfNeeded(webView: WKWebView) {
            guard let cmd = pendingCommand else { return }
            if lastHandledCommandId == cmd.id { return }

            lastHandledCommandId = cmd.id
            pendingCommand = nil

            if isExternalURL(cmd.url) {
                openExternally(cmd.url)
                return
            }

            if let current = webView.url, urlsEffectivelyEqual(current, cmd.url) {
                return
            }

            webView.load(URLRequest(url: cmd.url))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let u = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = (u.scheme ?? "").lowercased()

            if scheme == "tel" || scheme == "mailto" || scheme == "sms" || scheme == "facetime" || scheme == "facetime-audio" {
                openExternally(u)
                decisionHandler(.cancel)
                return
            }

            if scheme != "http" && scheme != "https" {
                decisionHandler(.allow)
                return
            }

            if isExternalURL(u) {
                if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                    openExternally(u)
                    decisionHandler(.cancel)
                    return
                }

                decisionHandler(.allow)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let u = navigationAction.request.url else {
                return nil
            }

            let scheme = (u.scheme ?? "").lowercased()

            if scheme == "tel" || scheme == "mailto" || scheme == "sms" || scheme == "facetime" || scheme == "facetime-audio" {
                openExternally(u)
                return nil
            }

            if isExternalURL(u) {
                openExternally(u)
                return nil
            }

            attachedWebView?.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                return
            }
            print("WEBVIEW didFail:", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                return
            }
            print("WEBVIEW didFailProvisionalNavigation:", error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            print("WEBVIEW process terminated; reloading current page")
            webView.reload()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishOnce = true

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }

                self.applyCommandIfNeeded(webView: webView)
                self.tryInjectIntoPage(webView: webView, force: true)
                self.syncCookiesToSharedStorage(webView: webView)
                self.requestWhoamiViaWebView(webView: webView)
                self.injectBiometricUIIfNeeded(webView: webView)
                self.maybePersistPendingLoginAfterSuccessfulNavigation(webView: webView)
                self.refreshNativeFaceIDButton(webView: webView)
            }
        }

        private func requestWhoamiViaWebView(webView: WKWebView) {
            let now = Date().timeIntervalSince1970
            if now - lastWhoamiAt < whoamiMinInterval {
                return
            }
            lastWhoamiAt = now

            guard let currentURL = webView.url else {
                return
            }

            let host = (currentURL.host ?? "").lowercased()
            if !(host == allowedHost || host.hasSuffix("." + allowedHost)) {
                return
            }

            let script = #"""
            (function () {
              var bodyClass = '';
              try {
                bodyClass = document.body ? (document.body.className || '') : '';
              } catch (e) {}

              var authGuess = false;
              try {
                authGuess =
                  /(^|\s)logged-in(\s|$)/.test(bodyClass) ||
                  !!document.querySelector('a[href*="logout"], a[href*="log-out"], a[href*="my-account"]');
              } catch (e) {}

              function postFallback() {
                try {
                  window.webkit.messageHandlers.smlWhoami.postMessage({
                    authenticated: authGuess,
                    current_path: (location && location.pathname) ? location.pathname : '',
                    href: (location && location.href) ? location.href : '',
                    body_class: bodyClass
                  });
                } catch (e) {}
              }

              try {
                fetch('/wp-json/sml/v1/whoami', { credentials: 'include' })
                  .then(function (response) {
                    return response.json().catch(function () { return {}; });
                  })
                  .then(function (data) {
                    try {
                      data = data || {};
                      data.current_path = (location && location.pathname) ? location.pathname : '';
                      data.href = (location && location.href) ? location.href : '';
                      data.body_class = bodyClass;

                      if (typeof data.authenticated === 'undefined' && typeof data.logged_in === 'undefined') {
                        data.authenticated = authGuess;
                      }

                      window.webkit.messageHandlers.smlWhoami.postMessage(data);
                    } catch (e) {
                      postFallback();
                    }
                  })
                  .catch(function () {
                    postFallback();
                  });
              } catch (e) {
                postFallback();
              }
            })();
            """#

            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func syncCookiesToSharedStorage(webView: WKWebView) {
            let now = Date().timeIntervalSince1970
            if now - lastCookieSyncAt < cookieSyncMinInterval {
                return
            }
            lastCookieSyncAt = now

            guard let currentURL = webView.url else {
                return
            }

            let host = (currentURL.host ?? "").lowercased()
            if !(host == allowedHost || host.hasSuffix("." + allowedHost)) {
                return
            }

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }

                self.cookieWorkQueue.async {
                    let shared = HTTPCookieStorage.shared
                    for c in cookies {
                        let d = c.domain.lowercased()
                        if d == self.allowedHost || d.hasSuffix("." + self.allowedHost) || self.allowedHost.hasSuffix(d) {
                            shared.setCookie(c)
                        }
                    }

                    DispatchQueue.main.async {
                        RoleState.shared.refresh()
                    }
                }
            }
        }

        func tryInjectIntoPage(webView: WKWebView, force: Bool) {
            let token = currentToken
            let did = currentDeviceId
            let device = did.isEmpty ? "ios-device" : did
            let biometricEnabled = currentBiometricEnabled
            let hasBiometricLogin = currentHasBiometricLogin
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
            let pushEnvironment = currentPushEnvironment()

            let page = webView.url?.absoluteString ?? ""

            if !force {
                if token == lastInjectedToken && device == lastInjectedDeviceId && page == lastInjectedURL {
                    return
                }
            }

            lastInjectedToken = token
            lastInjectedDeviceId = device
            lastInjectedURL = page

            let tokenJS = jsString(token)
            let deviceJS = jsString(device)
            let bundleIdJS = jsString(bundleId)
            let appVersionJS = jsString(appVersion)
            let buildNumberJS = jsString(buildNumber)
            let pushEnvironmentJS = jsString(pushEnvironment)
            let biometricEnabledJS = biometricEnabled ? "true" : "false"
            let hasBiometricLoginJS = hasBiometricLogin ? "true" : "false"

            let css = """
            input, textarea, [contenteditable="true"] { caret-color: #438239 !important; }
            """
            let cssJS = jsString(css)

            let js = """
            (function () {
              window.SML_APP = window.SML_APP || {};
              window.SML_APP.apnsToken = \(tokenJS);
              window.SML_APP.deviceId = \(deviceJS);
              window.SML_APP.bundleId = \(bundleIdJS);
              window.SML_APP.appVersion = \(appVersionJS);
              window.SML_APP.buildNumber = \(buildNumberJS);
              window.SML_APP.pushEnvironment = \(pushEnvironmentJS);
              window.SML_APP.isApp = true;
              window.SML_APP.platform = "ios";
              window.SML_APP.biometricEnabled = \(biometricEnabledJS);
              window.SML_APP.hasBiometricLogin = \(hasBiometricLoginJS);
              window.SML_APP.triggerBiometricLogin = function () {
                try { window.webkit.messageHandlers.smlBiometric.postMessage({ action: 'trigger' }); } catch (e) {}
              };
              window.SML_APP.clearBiometricLogin = function () {
                try { window.webkit.messageHandlers.smlBiometric.postMessage({ action: 'clear' }); } catch (e) {}
              };
              window.SML_APP.__injectedAt = Date.now();

              try {
                document.documentElement.setAttribute("data-sml-app", "1");
                document.documentElement.setAttribute("data-sml-platform", "ios");
              } catch (e) {}

              try {
                window.dispatchEvent(new CustomEvent("sml:app-ready", {
                  detail: {
                    platform: "ios",
                    biometricEnabled: window.SML_APP.biometricEnabled,
                    hasBiometricLogin: window.SML_APP.hasBiometricLogin,
                    bundleId: window.SML_APP.bundleId,
                    appVersion: window.SML_APP.appVersion,
                    buildNumber: window.SML_APP.buildNumber,
                    pushEnvironment: window.SML_APP.pushEnvironment
                  }
                }));
              } catch (e) {}

              try {
                setTimeout(function () {
                  try {
                    window.dispatchEvent(new CustomEvent("sml:app-ready", {
                      detail: {
                        platform: "ios",
                        biometricEnabled: window.SML_APP.biometricEnabled,
                        hasBiometricLogin: window.SML_APP.hasBiometricLogin,
                        bundleId: window.SML_APP.bundleId,
                        appVersion: window.SML_APP.appVersion,
                        buildNumber: window.SML_APP.buildNumber,
                        pushEnvironment: window.SML_APP.pushEnvironment
                      }
                    }));
                  } catch (e2) {}
                }, 150);
              } catch (e) {}

              window.SML_PUSH_TOKEN = \(tokenJS);
              window.SML_PUSH_DEVICE_ID = \(deviceJS);
              window.SML_PUSH_BUNDLE_ID = \(bundleIdJS);
              window.SML_PUSH_APP_VERSION = \(appVersionJS);
              window.SML_PUSH_BUILD_NUMBER = \(buildNumberJS);
              window.SML_PUSH_ENVIRONMENT = \(pushEnvironmentJS);

              try {
                if (!document.getElementById('sml-ios-style')) {
                  var st = document.createElement('style');
                  st.id = 'sml-ios-style';
                  st.type = 'text/css';
                  st.appendChild(document.createTextNode(\(cssJS)));
                  document.head.appendChild(st);
                }
              } catch (e) {}

              try {
                if (!window.__smlBiometricLoginCaptureBound) {
                  window.__smlBiometricLoginCaptureBound = true;

                  var captureAndSend = function (form) {
                    try {
                      form = form || document.querySelector('form');
                      if (!form) return;

                      var user = form.querySelector('input[name="log"], input[name="username"], input[type="email"], input[type="text"]');
                      var pass = form.querySelector('input[name="pwd"], input[name="password"], input[type="password"]');
                      if (!user || !pass) return;

                      var username = (user.value || '').trim();
                      var password = pass.value || '';
                      if (!username || !password) return;

                      window.webkit.messageHandlers.smlBiometric.postMessage({
                        action: 'captureLogin',
                        username: username,
                        password: password
                      });
                    } catch (e) {}
                  };

                  document.addEventListener('submit', function (ev) {
                    captureAndSend(ev.target);
                  }, true);

                  document.addEventListener('click', function (ev) {
                    try {
                      var target = ev.target && ev.target.closest
                        ? ev.target.closest('button[type="submit"], input[type="submit"], .woocommerce-form-login__submit, .button, .btn')
                        : null;
                      if (!target) return;

                      var form = target.form || target.closest('form');
                      captureAndSend(form);
                    } catch (e) {}
                  }, true);
                }
              } catch (e) {}

              if (window.SML_PUSH_REGISTER) {
                try { window.SML_PUSH_REGISTER(); } catch (e) {}
              }
            })();
            """

            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func currentPushEnvironment() -> String {
#if targetEnvironment(simulator)
            return "sandbox"
#else
            if let raw = embeddedPushEnvironment() {
                return raw == "production" ? "production" : "sandbox"
            }
#if DEBUG
            return "sandbox"
#else
            return "production"
#endif
#endif
        }

        private func embeddedPushEnvironment() -> String? {
            guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
                return nil
            }

            guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .ascii) else {
                return nil
            }

            let startTag = "<plist"
            let endTag = "</plist>"

            guard let startRange = content.range(of: startTag), let endRange = content.range(of: endTag) else {
                return nil
            }

            let plistText = String(content[startRange.lowerBound..<endRange.upperBound])
            guard let plistData = plistText.data(using: .utf8) else {
                return nil
            }

            guard
                let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
                let root = object as? [String: Any],
                let entitlements = root["Entitlements"] as? [String: Any],
                let value = entitlements["aps-environment"] as? String
            else {
                return nil
            }

            let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if raw == "production" {
                return "production"
            }
            if raw == "development" || raw == "sandbox" {
                return "sandbox"
            }
            return nil
        }

        private func injectBiometricUIIfNeeded(webView: WKWebView) {
            tryInjectIntoPage(webView: webView, force: true)
            refreshNativeFaceIDButton(webView: webView)
        }

        private func maybePersistPendingLoginAfterSuccessfulNavigation(webView: WKWebView) {
            guard let pendingCredentialSave else { return }

            let urlString = webView.url?.absoluteString.lowercased() ?? ""
            let path = webView.url?.path.lowercased() ?? ""
            let looksLikeLogin = path.contains("/login") || urlString.contains("wp-login")
            if looksLikeLogin {
                return
            }

            if currentBiometricEnabled {
                _ = SMCKeychain.save(login: pendingCredentialSave)
                self.pendingCredentialSave = nil
                currentHasBiometricLogin = true
                DispatchQueue.main.async {
                    PushState.shared.refreshBiometricState()
                }
                refreshNativeFaceIDButton(webView: webView)
                return
            }

            guard BiometricAuthManager.shared.canUseBiometrics() else {
                self.pendingCredentialSave = nil
                return
            }

            promptToEnableBiometricLogin(using: pendingCredentialSave)
        }

        private func promptToEnableBiometricLogin(using login: SMCStoredLogin) {
            guard let host = hostViewController else { return }
            guard host.presentedViewController == nil else { return }

            let alert = UIAlertController(
                title: "Use Face ID?",
                message: "Save this login so you can sign in faster next time with Face ID.",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { [weak self] _ in
                self?.pendingCredentialSave = nil
            })

            alert.addAction(UIAlertAction(title: "Use Face ID", style: .default) { [weak self] _ in
                guard let self else { return }
                _ = SMCKeychain.save(login: login)
                self.pendingCredentialSave = nil
                self.currentBiometricEnabled = true
                self.currentHasBiometricLogin = true
                DispatchQueue.main.async {
                    PushState.shared.setBiometricEnabled(true)
                    PushState.shared.refreshBiometricState()
                }
                if let webView = self.attachedWebView {
                    self.refreshNativeFaceIDButton(webView: webView)
                }
            })

            DispatchQueue.main.async {
                host.present(alert, animated: true)
            }
        }

        private func promptForBiometricLoginIfNeeded(webView: WKWebView) {
            guard currentBiometricEnabled else { return }
            guard let login = SMCKeychain.readLogin() else { return }

            BiometricAuthManager.shared.authenticate(reason: "Sign in with Face ID") { [weak self, weak webView] success in
                guard let self, let webView, success else { return }
                self.fillAndSubmitLogin(webView: webView, login: login)
            }
        }

        private func fillAndSubmitLogin(webView: WKWebView, login: SMCStoredLogin) {
            let userJS = jsString(login.username)
            let passJS = jsString(login.password)

            let js = """
            (function () {
              try {
                var form = document.querySelector('form');
                var user = document.querySelector('input[name="log"], input[name="username"], input[type="email"], input[type="text"]');
                var pass = document.querySelector('input[name="pwd"], input[name="password"], input[type="password"]');
                if (!user || !pass) return false;
                user.focus();
                user.value = \(userJS);
                user.dispatchEvent(new Event('input', { bubbles: true }));
                user.dispatchEvent(new Event('change', { bubbles: true }));
                pass.focus();
                pass.value = \(passJS);
                pass.dispatchEvent(new Event('input', { bubbles: true }));
                pass.dispatchEvent(new Event('change', { bubbles: true }));
                if (!form) { form = user.form || pass.form; }
                if (form) {
                  form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                  form.submit();
                  return true;
                }
                var btn = document.querySelector('button[type="submit"], input[type="submit"]');
                if (btn) {
                  btn.click();
                  return true;
                }
                return false;
              } catch (e) {
                return false;
              }
            })();
            """

            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func openExternally(_ url: URL) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }

        private func urlsEffectivelyEqual(_ lhs: URL, _ rhs: URL) -> Bool {
            var l = URLComponents(url: lhs, resolvingAgainstBaseURL: false)
            var r = URLComponents(url: rhs, resolvingAgainstBaseURL: false)
            l?.fragment = nil
            r?.fragment = nil
            return l?.string == r?.string
        }

        private func jsString(_ value: String) -> String {
            guard
                let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
                var str = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }

            if str.count >= 4, str.hasPrefix("["), str.hasSuffix("]") {
                str.removeFirst()
                str.removeLast()
                return str
            }

            return "\"\""
        }
    }
}
