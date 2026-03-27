//
//  WebView.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - WKWebView внутри SwiftUI.
//  - Общие cookies и сессия.
//  - Role bridge через whoami.
//  - Корректная обработка внутренних, внешних и системных ссылок.
//  - iPad показывает мобильную версию сайта.
//  - Есть нативный loading / timeout / retry, чтобы app не выглядел зависшим.
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
    let command: WebNavigationCommand?
    let locationRevision: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> WebViewController {
        let vc = WebViewController()
        vc.coordinator = context.coordinator
        context.coordinator.hostController = vc

        context.coordinator.setCurrent(apnsToken: apnsToken, deviceId: deviceId, locationRevision: locationRevision)
        context.coordinator.setCommand(command)

        vc.initialURL = url
        vc.initialCommand = command

        return vc
    }

    func updateUIViewController(_ vc: WebViewController, context: Context) {
        vc.coordinator = context.coordinator
        context.coordinator.hostController = vc
        context.coordinator.setCurrent(apnsToken: apnsToken, deviceId: deviceId, locationRevision: locationRevision)
        context.coordinator.setCommand(command)

        if let wv = vc.webView {
            context.coordinator.applyCommandIfNeeded(webView: wv)
            if context.coordinator.didFinishOnce {
                context.coordinator.tryInjectIntoPage(webView: wv, force: false)
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
    private var currentRequestURL: URL?


    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        if #available(iOS 14.0, *) {
            let prefs = WKWebpagePreferences()
            prefs.preferredContentMode = .mobile
            config.defaultWebpagePreferences = prefs
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false

        if UIDevice.current.userInterfaceIdiom == .pad {
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }

        view.addSubview(wv)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            wv.topAnchor.constraint(equalTo: g.topAnchor),
            wv.bottomAnchor.constraint(equalTo: g.bottomAnchor)
        ])

        if let coordinator {
            wv.navigationDelegate = coordinator
            wv.uiDelegate = coordinator
            wv.configuration.userContentController.add(coordinator, name: "SMLWhoami")
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
        loadInitialIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadInitialIfNeeded()
    }

    private func loadInitialIfNeeded() {
        guard let wv = webView, let coordinator else { return }
        guard !didLoadInitial else { return }
        didLoadInitial = true

        let base = initialURL ?? AppConfig.siteURL

        if let cmd = initialCommand {
            coordinator.markCommandHandled(cmd.id)
            if coordinator.shouldOpenExternally(cmd.url) {
                load(url: base, in: wv)
            } else {
                load(url: cmd.url, in: wv)
            }
        } else {
            load(url: base, in: wv)
        }
    }

    fileprivate func load(url: URL, in webView: WKWebView? = nil) {
        guard let wv = webView ?? self.webView else { return }
        currentRequestURL = url
        wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    fileprivate func handleNavigationStart() {
    }

    fileprivate func handleNavigationCommitted() {
    }

    fileprivate func handleNavigationFinished() {
    }

    fileprivate func handleNavigationFailure(message: String) {
        presentLoadError(message: message)
    }

    private func presentLoadError(message: String) {
        if presentedViewController != nil { return }

        let alert = UIAlertController(
            title: "Could not open page",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.retryTapped()
        })

        present(alert, animated: true)
    }

    @objc private func retryTapped() {
        guard let target = currentRequestURL ?? initialURL ?? AppConfig.siteURL as URL? else { return }
        load(url: target)
    }
}

extension WebView {

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

        weak var hostController: WebViewController?

        private var currentToken: String = ""
        private var currentDeviceId: String = ""
        private var currentLocationRevision: Int = 0

        private var lastInjectedToken: String = ""
        private var lastInjectedDeviceId: String = ""
        private var lastInjectedURL: String = ""
        private var lastInjectedLocationRevision: Int = -1""

        private var pendingCommand: WebNavigationCommand?
        private var lastHandledCommandId: UUID?

        fileprivate var didFinishOnce = false

        private let allowedExternalHosts: Set<String> = [
            "google.com",
            "www.google.com",
            "gstatic.com",
            "www.gstatic.com",
            "recaptcha.net",
            "www.recaptcha.net"
        ]

        private var lastCookieSyncAt: TimeInterval = 0
        private let cookieSyncMinInterval: TimeInterval = 1.0

        private var lastWhoamiAt: TimeInterval = 0
        private let whoamiMinInterval: TimeInterval = 1.0

        private let cookieWorkQueue = DispatchQueue.global(qos: .utility)

        func setCurrent(apnsToken: String, deviceId: String, locationRevision: Int) {
            currentToken = apnsToken.trimmingCharacters(in: .whitespacesAndNewlines)
            currentDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
            currentLocationRevision = locationRevision
        }

        func setCommand(_ command: WebNavigationCommand?) {
            pendingCommand = command
        }

        func markCommandHandled(_ id: UUID) {
            lastHandledCommandId = id
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "SMLWhoami" else { return }

            let payload = makeSafeBridgePayload(from: message.body)
            Task { @MainActor in
                RoleState.shared.setRoleFromBridge(payload: payload)
            }
        }

        private func makeSafeBridgePayload(from value: Any?) -> Any? {
            switch value {
            case nil:
                return nil

            case let string as String:
                return String(string)

            case let number as NSNumber:
                return number

            case _ as NSNull:
                return NSNull()

            case let array as [Any]:
                return array.map { makeSafeBridgePayload(from: $0) as Any }

            case let dict as [String: Any]:
                var safe: [String: Any] = [:]
                for (key, value) in dict {
                    safe[key] = makeSafeBridgePayload(from: value)
                }
                return safe

            case let dict as NSDictionary:
                var safe: [String: Any] = [:]
                for case let (key as NSString, value) in dict {
                    safe[String(key)] = makeSafeBridgePayload(from: value)
                }
                return safe

            default:
                return String(describing: value!)
            }
        }

        private func isAllowedExternalHost(_ host: String) -> Bool {
            if allowedExternalHosts.contains(host) { return true }
            return allowedExternalHosts.contains(where: { host.hasSuffix("." + $0) })
        }

        func isExternalURL(_ url: URL) -> Bool {
            let scheme = (url.scheme ?? "").lowercased()
            guard scheme == "http" || scheme == "https" else { return false }

            let host = (url.host ?? "").lowercased()
            guard !host.isEmpty else { return false }

            if AppConfig.isInternalHost(host) { return false }
            if isAllowedExternalHost(host) { return false }

            return true
        }

        func shouldOpenExternally(_ url: URL) -> Bool {
            let scheme = (url.scheme ?? "").lowercased()

            if scheme == "tel" || scheme == "mailto" || scheme == "sms" || scheme == "maps" {
                return true
            }

            if scheme == "http" || scheme == "https" {
                return isExternalURL(url)
            }

            return UIApplication.shared.canOpenURL(url)
        }

        private func openExternally(_ url: URL) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:])
            }
        }

        func applyCommandIfNeeded(webView: WKWebView) {
            guard let cmd = pendingCommand else { return }
            guard lastHandledCommandId != cmd.id else { return }

            lastHandledCommandId = cmd.id

            if shouldOpenExternally(cmd.url) { return }

            hostController?.load(url: cmd.url, in: webView)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            guard let u = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if shouldOpenExternally(u), navigationAction.navigationType == .linkActivated {
                openExternally(u)
                decisionHandler(.cancel)
                return
            }

            let scheme = (u.scheme ?? "").lowercased()
            if scheme != "http" && scheme != "https" && UIApplication.shared.canOpenURL(u) {
                openExternally(u)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {

            guard navigationAction.targetFrame == nil else { return nil }
            guard let u = navigationAction.request.url else { return nil }

            if shouldOpenExternally(u) {
                openExternally(u)
            } else {
                hostController?.load(url: u, in: webView)
            }

            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            hostController?.handleNavigationStart()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            hostController?.handleNavigationCommitted()
        }

        private func pageRequiresNativeLocation(_ webView: WKWebView) -> Bool {
            let path = webView.url?.path.lowercased() ?? ""
            return path.contains("/account-workday")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishOnce = true
            hostController?.handleNavigationFinished()

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }

                if self.pageRequiresNativeLocation(webView) {
                    LocationState.shared.prepareForWorkdayPage()
                }

                self.applyCommandIfNeeded(webView: webView)
                self.tryInjectIntoPage(webView: webView, force: true)
                self.requestWhoamiViaWebView(webView: webView)
                self.syncCookiesToSharedStorage(webView: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            hostController?.handleNavigationFailure(message: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            hostController?.handleNavigationFailure(message: error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            hostController?.handleNavigationFailure(message: "The page process stopped. Tap Retry.")
        }

        private func requestWhoamiViaWebView(webView: WKWebView) {
            let now = Date().timeIntervalSince1970
            if now - lastWhoamiAt < whoamiMinInterval { return }
            lastWhoamiAt = now

            guard let host = webView.url?.host?.lowercased(), AppConfig.isInternalHost(host) else { return }

            let js = """
            (function () {
              function safeText(selector) {
                try {
                  var node = document.querySelector(selector);
                  return node && node.textContent ? node.textContent.trim() : '';
                } catch (e) {
                  return '';
                }
              }

              function collectDomPayload() {
                var body = document.body;
                var classes = body ? body.className : '';
                var loggedIn = body ? body.classList.contains('logged-in') : false;
                var roleCandidates = [
                  safeText('.sml-account-sidebar__eyebrow'),
                  safeText('.sml-account-badge'),
                  safeText('.sml-account-sidebar__meta'),
                  safeText('.sml-account-eyebrow')
                ].filter(function (value) { return !!value; });

                return {
                  role_source: 'dom',
                  role_candidates: roleCandidates,
                  role_label: roleCandidates.length ? roleCandidates[0] : '',
                  body_class: classes,
                  loggedIn: loggedIn,
                  path: window.location.pathname || '',
                  href: window.location.href || ''
                };
              }

              function send(payload) {
                try { window.webkit.messageHandlers.SMLWhoami.postMessage(payload); } catch (e) {}
              }

              var domPayload = collectDomPayload();

              try {
                fetch('/wp-json/sml/v1/whoami', { credentials: 'include' })
                  .then(function (r) {
                    if (!r.ok) { throw new Error('HTTP ' + r.status); }
                    return r.json();
                  })
                  .then(function (d) {
                    if (d && typeof d === 'object') {
                      d.role_source = 'whoami';
                      send(d);
                    } else {
                      send({ role: String(d || ''), role_source: 'whoami' });
                    }
                    send(domPayload);
                  })
                  .catch(function () {
                    send(domPayload);
                  });
              } catch (e) {
                send(domPayload);
              }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func syncCookiesToSharedStorage(webView: WKWebView) {
            let now = Date().timeIntervalSince1970
            if now - lastCookieSyncAt < cookieSyncMinInterval { return }
            lastCookieSyncAt = now

            guard let host = webView.url?.host?.lowercased(), AppConfig.isInternalHost(host) else { return }

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                guard !cookies.isEmpty else { return }

                self.cookieWorkQueue.async {
                    let shared = HTTPCookieStorage.shared
                    for cookie in cookies {
                        let domain = cookie.domain.lowercased()
                        if AppConfig.isInternalHost(domain) || AppConfig.siteHost.hasSuffix(domain) {
                            shared.setCookie(cookie)
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
            guard !token.isEmpty else { return }

            let device = currentDeviceId.isEmpty ? "ios-device" : currentDeviceId
            let page = webView.url?.absoluteString ?? ""

            let locationPayload = LocationState.shared.bridgePayload()
            let locationRevision = currentLocationRevision

            if !force &&
                token == lastInjectedToken &&
                device == lastInjectedDeviceId &&
                page == lastInjectedURL &&
                locationRevision == lastInjectedLocationRevision {
                return
            }

            lastInjectedToken = token
            lastInjectedDeviceId = device
            lastInjectedURL = page
            lastInjectedLocationRevision = locationRevision

            let tokenJS = jsString(token)
            let deviceJS = jsString(device)
            let bundleIdJS = jsString(AppConfig.bundleId)
            let appVersionJS = jsString(AppConfig.appVersion)
            let buildNumberJS = jsString(AppConfig.buildNumber)
            let environmentJS = jsString(AppConfig.pushEnvironment)
            let locationJS = jsObjectString(locationPayload)
            let cssJS = jsString("input, textarea, [contenteditable=\"true\"] { caret-color: #438239 !important; }")

            let js = """
            (function () {
              window.SML_APP = window.SML_APP || {};
              window.SML_APP.apnsToken = \(tokenJS);
              window.SML_APP.deviceId  = \(deviceJS);
              window.SML_APP.bundleId = \(bundleIdJS);
              window.SML_APP.appVersion = \(appVersionJS);
              window.SML_APP.buildNumber = \(buildNumberJS);
              window.SML_APP.pushEnvironment = \(environmentJS);
              window.SML_APP.location = \(locationJS);
              window.SML_APP.__injectedAt = Date.now();

              window.SML_LOCATION = \(locationJS);
              window.SML_PUSH_TOKEN = \(tokenJS);
              window.SML_PUSH_DEVICE_ID = \(deviceJS);

              try {
                if (!document.getElementById('sml-ios-style')) {
                  var st = document.createElement('style');
                  st.id = 'sml-ios-style';
                  st.type = 'text/css';
                  st.appendChild(document.createTextNode(\(cssJS)));
                  document.head.appendChild(st);
                }
              } catch (e) {}

              function tryRegister() {
                if (window.SML_PUSH_REGISTER) {
                  try { window.SML_PUSH_REGISTER(false); } catch (e) {}
                  return true;
                }
                return false;
              }

              if (!tryRegister()) {
                setTimeout(tryRegister, 500);
                setTimeout(tryRegister, 1500);
                setTimeout(tryRegister, 3000);
              }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func jsString(_ value: String) -> String {
            guard
                let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
                var str = String(data: data, encoding: .utf8)
            else { return "\"\"" }

            if str.hasPrefix("[") && str.hasSuffix("]") {
                str.removeFirst()
                str.removeLast()
            }
            return str
        }

        private func jsObjectString(_ value: Any) -> String {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: []),
                  let str = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return str
        }
    }
}
