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

    // Назначение:
    // - Создает coordinator для WKWebView bridge
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // Назначение:
    // - Создает host controller и передает в него начальные данные
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

    // Назначение:
    // - Обновляет текущее состояние bridge и применяет входящие команды навигации
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

    // Назначение:
    // - Создает WKWebView и настраивает его делегаты
    override func viewDidLoad() {
        super.viewDidLoad()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 13.0, *) {
            wv.configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        }

        let _appVer = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 SMLApp-iOS/\(_appVer)"

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
            wv.configuration.userContentController.add(coordinator, name: "smlWidget")
            wv.configuration.userContentController.add(coordinator, name: "smlLiveActivity")
            wv.configuration.userContentController.add(coordinator, name: "smlConsole")
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

    // Назначение:
    // - Повторно проверяет первичную загрузку после появления экрана
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadInitialIfNeeded()
    }

    // Назначение:
    // - Гарантированно загружает стартовую страницу только один раз
    private func loadInitialIfNeeded() {
        guard let wv = webView, let coordinator else { return }
        guard !didLoadInitial else { return }
        didLoadInitial = true

        let base = initialURL ?? URL(string: "https://stmaryslandscaping.ca/")!

        // Use default cache policy so CSS/JS assets are served from WKWebView cache
        // (fast launch). The version-check in checkSiteVersionAndReloadIfNeeded will
        // do a full reloadIgnoringLocalCacheData only when the site version changes.
        if let cmd = initialCommand {
            coordinator.markCommandHandled(cmd.id)
            if coordinator.isExternalURL(cmd.url) {
                wv.load(URLRequest(url: base, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
            } else {
                wv.load(URLRequest(url: cmd.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
            }
        } else {
            wv.load(URLRequest(url: base, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
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
        private var lastInjectedBundleId: String = ""
        private var lastInjectedAppVersion: String = ""
        private var lastInjectedBuildNumber: String = ""
        private var lastInjectedPushEnvironment: String = ""
        private var lastInjectedBiometricEnabled: Bool = false
        private var lastInjectedHasBiometricLogin: Bool = false

        private var pendingCommand: WebNavigationCommand? = nil
        private var lastHandledCommandId: UUID? = nil

        // Pending Live Activity token to register once a webView is attached.
        private var pendingLATokenType: String = ""
        private var pendingLATokenValue: String = ""
        private var pendingLATokenOrderId: String = ""
        private var pendingLATokenSandbox: Bool = false

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

        // Location bridge -- активен только пока открыта страница account-workday
        private var isWatchingLocation: Bool = false
        private weak var locationWebView: WKWebView?

        deinit {
            liveStatusTimer?.invalidate()
            liveStatusTimer = nil
            NotificationCenter.default.removeObserver(self)
            if isWatchingLocation {
                LocationBridge.shared.stopWatching()
            }
        }

        private var lastCookieSyncAt: TimeInterval = 0
        private let cookieSyncMinInterval: TimeInterval = 1.0

        private var lastWhoamiAt: TimeInterval = 0
        private let whoamiMinInterval: TimeInterval = 1.0

        private let cookieWorkQueue = DispatchQueue.global(qos: .utility)

        // Назначение:
        // - Сохраняет текущее состояние app для последующей JS-инъекции
        func setCurrent(apnsToken: String, deviceId: String, biometricEnabled: Bool, hasBiometricLogin: Bool) {
            currentToken = apnsToken.trimmingCharacters(in: .whitespacesAndNewlines)
            currentDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
            currentBiometricEnabled = biometricEnabled
            currentHasBiometricLogin = hasBiometricLogin
        }

        // Назначение:
        // - Принимает внешнюю команду навигации
        func setCommand(_ command: WebNavigationCommand?) {
            pendingCommand = command
        }

        // Назначение:
        // - Помечает команду как уже обработанную
        func markCommandHandled(_ id: UUID) {
            lastHandledCommandId = id
        }

        // Назначение:
        // - Обрабатывает сообщения от JS bridge
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

                return
            }

            if message.name == "smlWidget" {
                if let dict = message.body as? [String: Any] {
                    let role          = (dict["role"]          as? String) ?? "guest"
                    let taskCount     = (dict["taskCount"]     as? Int)    ?? 0
                    let nextTask      = (dict["nextTask"]      as? String) ?? ""
                    let workdayStatus = (dict["workdayStatus"] as? String) ?? "none"
                    let orderTitle    = (dict["orderTitle"]    as? String) ?? ""
                    let orderStatus   = (dict["orderStatus"]   as? String) ?? ""
                    var widgetTasks: [WidgetTask] = []
                    if let rawTasks = dict["tasks"] as? [[String: Any]] {
                        widgetTasks = rawTasks.enumerated().map { i, t in
                            WidgetTask(
                                id:     (t["id"]     as? String) ?? "\(i)",
                                title:  (t["title"]  as? String) ?? "",
                                status: (t["status"] as? String) ?? "pending"
                            )
                        }
                    }
                    var widgetOrders: [WidgetOrder] = []
                    if let rawOrders = dict["orders"] as? [[String: Any]] {
                        widgetOrders = rawOrders.enumerated().map { i, o in
                            WidgetOrder(
                                id:     (o["id"]     as? String) ?? "\(i)",
                                title:  (o["title"]  as? String) ?? "",
                                status: (o["status"] as? String) ?? "pending"
                            )
                        }
                    }
                    NSLog("[Widget] received from JS: tasks=%d role=%@ workday=%@",
                          widgetTasks.count, role, workdayStatus)
                    smlWidgetWrite(
                        role: role,
                        taskCount: taskCount,
                        nextTaskTitle: nextTask,
                        tasks: widgetTasks,
                        orders: widgetOrders,
                        workdayStatus: workdayStatus,
                        orderTitle: orderTitle,
                        orderStatus: orderStatus
                    )
                }
                return
            }

            if message.name == "smlLiveActivity" {
                if #available(iOS 16.2, *) {
                    guard let dict = message.body as? [String: Any] else { return }
                    let action = (dict["action"] as? String) ?? ""
                    NSLog("[LiveActivity] message received: action=\(action) body=\(dict)")
                    let mgr    = SMLLiveActivityManager.shared
                    let wv     = attachedWebView

                    // Set token callback so any activity start/sync reports its push token.
                    // Called from a Task (background thread) - must dispatch to main.
                    mgr.onTokenUpdate = { [weak self] type, token, orderId, isSandbox in
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            if let webView = self.attachedWebView {
                                self.registerLiveActivityToken(webView: webView, type: type, token: token, orderId: orderId, isSandbox: isSandbox)
                            } else {
                                self.pendingLATokenType    = type
                                self.pendingLATokenValue   = token
                                self.pendingLATokenOrderId = orderId
                                self.pendingLATokenSandbox = isSandbox
                            }
                        }
                    }

                    switch action {
                    case "workday.start":
                        let name = (dict["workerName"] as? String) ?? "Worker"
                        mgr.startWorkday(workerName: name)
                    case "workday.sync":
                        let name             = (dict["workerName"]    as? String) ?? "Worker"
                        let adjustedStartRaw = dict["adjustedStart"]
                        let adjustedStartUnix: Double = (adjustedStartRaw as? Double)
                            ?? Double((adjustedStartRaw as? Int) ?? 0)
                        let status           = (dict["status"]         as? String) ?? "open"
                        let pauseStartRaw    = dict["pauseStart"]
                        let pauseStartUnix: Double = (pauseStartRaw as? Double)
                            ?? Double((pauseStartRaw as? Int) ?? 0)
                        mgr.syncWorkday(workerName: name, adjustedStartUnix: adjustedStartUnix, status: status, pauseStartUnix: pauseStartUnix)
                    case "workday.pause":
                        mgr.pauseWorkday()
                    case "workday.resume":
                        let paused = (dict["totalPausedSeconds"] as? Int) ?? 0
                        mgr.resumeWorkday(totalPausedSeconds: paused)
                    case "workday.end":
                        mgr.endWorkday()
                        if let webView = wv {
                            deleteLiveActivityToken(webView: webView, type: "workday", orderId: "")
                        }
                    case "order.start":
                        let orderId     = (dict["orderId"]     as? String) ?? ""
                        let serviceName = (dict["serviceName"] as? String) ?? "Service"
                        let status      = (dict["status"]      as? String) ?? "pending"
                        mgr.startOrder(orderId: orderId, serviceName: serviceName, status: status)
                    case "order.sync":
                        let orderId     = (dict["orderId"]     as? String) ?? ""
                        let serviceName = (dict["serviceName"] as? String) ?? ""
                        let status      = (dict["status"]      as? String) ?? "pending"
                        mgr.syncOrder(orderId: orderId, serviceName: serviceName, status: status)
                    case "order.update":
                        let status = (dict["status"] as? String) ?? "pending"
                        mgr.updateOrder(status: status)
                    case "order.end":
                        let orderId = (dict["orderId"] as? String) ?? ""
                        mgr.endOrder(orderId: orderId)
                        if let webView = wv {
                            deleteLiveActivityToken(webView: webView, type: "order", orderId: orderId)
                        }
                    default: break
                    }
                }
                return
            }

            if message.name == "smlConsole" {
                NSLog("[JS] %@", "\(message.body)")
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

            default:
                break
            }
        }

        // Назначение:
        // - Проверяет, относится ли внешний домен к списку разрешенных исключений
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

        // Назначение:
        // - Определяет, является ли URL внешним относительно основного домена SML
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

        // Назначение:
        // - Применяет отложенную команду перехода в webView
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

        // Назначение:
        // - Решает, разрешать ли навигацию внутри WKWebView
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

        // Назначение:
        // - Перехватывает попытки открыть новое окно и открывает его в текущем webView
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

        // Назначение:
        // - Логирует ошибки обычной навигации
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                return
            }
            print("WEBVIEW didFail:", error.localizedDescription)
        }

        // Назначение:
        // - Логирует ошибки предварительной навигации
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                return
            }
            print("WEBVIEW didFailProvisionalNavigation:", error.localizedDescription)
        }

        // Назначение:
        // - Перезапускает webView после падения web content process
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            print("WEBVIEW process terminated; reloading current page")
            webView.reload()
        }

        // Назначение:
        // - После завершения загрузки синхронизирует bridge, cookies и whoami
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishOnce = true
            NSLog("[didFinish] url=\(webView.url?.absoluteString ?? "nil")")

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }

                self.applyCommandIfNeeded(webView: webView)
                self.tryInjectIntoPage(webView: webView, force: true)
                self.syncCookiesToSharedStorage(webView: webView)
                self.requestWhoamiViaWebView(webView: webView)
                self.maybePersistPendingLoginAfterSuccessfulNavigation(webView: webView)
                self.handleLocationTracking(webView: webView)
                self.requestLiveStatusSync(webView: webView)
                self.lastPageLoadAt = Date().timeIntervalSince1970
                self.startLiveStatusPolling()
                self.registerForegroundObserverIfNeeded()
                self.flushPendingLAToken(webView: webView)
            }
        }

        // Назначение:
        // - Отправляет отложенный push-токен Live Activity, если он был получен до загрузки страницы.
        private func flushPendingLAToken(webView: WKWebView) {
            guard !pendingLATokenValue.isEmpty else { return }
            let type    = pendingLATokenType
            let token   = pendingLATokenValue
            let orderId = pendingLATokenOrderId
            let sandbox = pendingLATokenSandbox
            pendingLATokenType    = ""
            pendingLATokenValue   = ""
            pendingLATokenOrderId = ""
            pendingLATokenSandbox = false
            registerLiveActivityToken(webView: webView, type: type, token: token, orderId: orderId, isSandbox: sandbox)
        }

        // Назначение:
        // - Регистрирует push-токен Live Activity на сервере через JS fetch.
        func registerLiveActivityToken(webView: WKWebView, type: String, token: String, orderId: String, isSandbox: Bool) {
            let host = (webView.url?.host ?? "").lowercased()
            guard host == allowedHost || host.hasSuffix("." + allowedHost) else { return }
            let typeJS    = jsString(type)
            let tokenJS   = jsString(token)
            let orderIdJS = jsString(orderId)
            let sandboxJS = isSandbox ? "true" : "false"
            let js = """
            (function() {
              var isSandbox = (window.SML_APP && window.SML_APP.isSandboxPush === true) ? true : \(sandboxJS);
              fetch('/wp-json/sml/v1/live-activity/token', {
                method: 'POST',
                credentials: 'include',
                cache: 'no-store',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({type: \(typeJS), token: \(tokenJS), order_id: \(orderIdJS), sandbox: isSandbox})
              })
              .then(function(r) { return r.json(); })
              .catch(function(e) {});
            })();
            """
            NSLog("[LiveActivity] registering token type=\(type) sandbox=\(isSandbox)")
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Назначение:
        // - Удаляет push-токен Live Activity с сервера через JS fetch DELETE.
        private func deleteLiveActivityToken(webView: WKWebView, type: String, orderId: String) {
            let host = (webView.url?.host ?? "").lowercased()
            guard host == allowedHost || host.hasSuffix("." + allowedHost) else { return }
            var urlString = "/wp-json/sml/v1/live-activity/token?type=\(type)"
            if !orderId.isEmpty {
                urlString += "&order_id=\(orderId)"
            }
            let js = """
            (function() {
              fetch('\(urlString)', {method: 'DELETE', credentials: 'include', cache: 'no-store'})
              .catch(function(e) {});
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Назначение:
        // - Запрашивает /sml/v1/live-status напрямую через URLSession,
        //   копируя cookies из WKHTTPCookieStore (надёжнее чем JS fetch на iOS 26+).
        private var lastLiveStatusAt: TimeInterval = 0
        private let liveStatusMinInterval: TimeInterval = 10
        private let liveStatusURL = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/live-status")!

        // Background timer: polls live-status every 30 s so the Live Activity ends
        // even when the user stays on the same page without navigating.
        private var liveStatusTimer: Timer?

        // Tracks when the page was last fully loaded, to decide whether a
        // foreground-return should trigger a full reload or just a live-status sync.
        private var lastPageLoadAt: TimeInterval = 0

        // How long the app must be in the background before we do a full reload.
        private let foregroundReloadMinInterval: TimeInterval = 300 // 5 minutes

        private func startLiveStatusPolling() {
            guard liveStatusTimer == nil else { return }
            liveStatusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard let wv = self.attachedWebView else {
                        NSLog("[LiveSync] timer fired - no attached webView, skipping")
                        return
                    }
                    NSLog("[LiveSync] timer fired - requesting sync")
                    self.requestLiveStatusSync(webView: wv)
                }
            }
        }

        private var foregroundObserverRegistered = false

        // Records when the app last went to background so we can calculate
        // how long it was absent before returning to foreground.
        private var lastBackgroundAt: TimeInterval = 0

        private func registerForegroundObserverIfNeeded() {
            guard !foregroundObserverRegistered else { return }
            foregroundObserverRegistered = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }

        @objc private func appDidEnterBackground() {
            lastBackgroundAt = Date().timeIntervalSince1970
        }

        // Prevents double-reload when both time threshold and version change fire together.
        private var foregroundReloadTriggered = false

        // Called when the app returns to foreground.
        // 1. Always syncs live-status (widget + Livestroka).
        // 2. Always checks site version - reloads if version changed on server.
        // 3. Also reloads if app was in background for 5+ minutes (time-based).
        @objc private func appWillEnterForeground() {
            // Immediately refresh the widget via a direct HTTP fetch (no WKWebView needed).
            // This runs before any WebView check so the widget updates even if the WebView
            // is not ready yet (cold start, slow load, etc.).
            SMLBackgroundRefresh.fetchAndWrite()

            guard let wv = attachedWebView else { return }
            let now = Date().timeIntervalSince1970
            foregroundReloadTriggered = false

            // Reset the live-status throttle so the foreground call is never skipped.
            lastLiveStatusAt = 0
            requestLiveStatusSync(webView: wv)

            // Version check: reload only if absent 60+ seconds (avoids disrupting
        // workers who briefly switch apps and come right back).
        let absenceSeconds = lastBackgroundAt > 0 ? (now - lastBackgroundAt) : 0
        checkSiteVersionAndReloadIfNeeded(webView: wv, absenceSeconds: absenceSeconds)

            // Time-based reload: if absent 5+ minutes, reload with default cache policy
            // so CSS/JS are served from WKWebView cache (fast). Only a version change
            // (handled by checkSiteVersionAndReloadIfNeeded above) triggers a full
            // cache-busting reload to pick up new site deployments.
            if lastPageLoadAt > 0 && (now - lastPageLoadAt) >= foregroundReloadMinInterval {
                let host = (wv.url?.host ?? "").lowercased()
                if (host == allowedHost || host.hasSuffix("." + allowedHost)),
                   let currentURL = wv.url {
                    NSLog("[Foreground] reloading page after long background: \(currentURL)")
                    foregroundReloadTriggered = true
                    wv.load(URLRequest(url: currentURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
                }
            }
        }

        // MARK: - Site version check

        private static let appVersionURL  = URL(string: "https://stmaryslandscaping.ca/wp-json/sml/v1/app-version")!
        private static let siteVersionKey = "sml.site.cached_version"

        // Compares the server's current theme version against the last-seen version.
        // Only reloads if the user was in the background for at least 60 seconds -
        // avoids disrupting a worker who briefly switches apps and comes right back.
        private func checkSiteVersionAndReloadIfNeeded(webView: WKWebView, absenceSeconds: TimeInterval) {
            let host = (webView.url?.host ?? "").lowercased()
            guard host == allowedHost || host.hasSuffix("." + allowedHost) else { return }
            guard let currentURL = webView.url else { return }

            var req = URLRequest(
                url: Self.appVersionURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 10
            )
            if let cookies = HTTPCookieStorage.shared.cookies(for: Self.appVersionURL) {
                for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                    req.setValue(value, forHTTPHeaderField: field)
                }
            }

            URLSession.shared.dataTask(with: req) { [weak self, weak webView] data, _, _ in
                guard
                    let self,
                    let data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let newVersion = json["version"] as? String
                else { return }

                let ud            = UserDefaults.standard
                let cachedVersion = ud.string(forKey: Self.siteVersionKey) ?? ""
                let versionChanged = !cachedVersion.isEmpty && cachedVersion != newVersion

                // Always save the current version so the next comparison is accurate.
                if cachedVersion != newVersion {
                    ud.set(newVersion, forKey: Self.siteVersionKey)
                }

                // Only reload if both: version changed AND user was away 60+ seconds.
                guard versionChanged else { return }
                guard absenceSeconds >= 60 else {
                    NSLog("[VersionCheck] site updated %@ -> %@ but absence %.0fs < 60s - reload deferred", cachedVersion, newVersion, absenceSeconds)
                    return
                }

                NSLog("[VersionCheck] site updated %@ -> %@, absence %.0fs >= 60s - reloading", cachedVersion, newVersion, absenceSeconds)
                DispatchQueue.main.async { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    guard !self.foregroundReloadTriggered else {
                        NSLog("[VersionCheck] reload skipped - already triggered this cycle")
                        return
                    }
                    self.foregroundReloadTriggered = true
                    webView.load(URLRequest(
                        url: currentURL,
                        cachePolicy: .reloadIgnoringLocalCacheData,
                        timeoutInterval: 60
                    ))
                }
            }.resume()
        }

        private func requestLiveStatusSync(webView: WKWebView) {
            let host = (webView.url?.host ?? "").lowercased()
            guard host == allowedHost || host.hasSuffix("." + allowedHost) else { return }

            let now = Date().timeIntervalSince1970
            guard now - lastLiveStatusAt >= liveStatusMinInterval else { return }
            lastLiveStatusAt = now
            NSLog("[LiveSync] JS fetch starting")

            // JS fetch работает в контексте WKWebView и автоматически использует сессионные cookies.
            // Результат через smlLiveActivity + smlWidget message handlers.
            // console.log перехватывается через smlConsole handler -> NSLog.
            let js = """
            (function() {
              var log = function(m) {
                try { window.webkit.messageHandlers.smlConsole.postMessage(m); } catch(e) {}
              };
              log('[LiveSync-JS] fetch start');
              fetch('/wp-json/sml/v1/live-status?_t=' + Date.now(), {credentials: 'include', cache: 'no-store'})
                .then(function(r) {
                  log('[LiveSync-JS] status=' + r.status);
                  return r.ok ? r.json() : null;
                })
                .then(function(d) {
                  log('[LiveSync-JS] data=' + JSON.stringify(d));
                  if (!d || !d.authenticated) { log('[LiveSync-JS] not auth'); return; }
                  var b = window.webkit && window.webkit.messageHandlers;
                  if (!b) { log('[LiveSync-JS] no handlers'); return; }

                  if (b.smlWidget) {
                    b.smlWidget.postMessage({
                      role:          d.role,
                      workdayStatus: d.workday_status,
                      orderTitle:    d.order_title  || '',
                      orderStatus:   d.order_status || '',
                      taskCount:     d.task_count   || 0,
                      nextTask:      d.next_task    || '',
                      tasks:         d.tasks        || [],
                      orders:        d.orders       || []
                    });
                  }

                  var ws = d.workday_status;
                  if (ws === 'open' || ws === 'paused') {
                    b.smlLiveActivity.postMessage({
                      action:        'workday.sync',
                      workerName:    d.worker_name     || '',
                      adjustedStart: d.adjusted_start  || 0,
                      pauseStart:    d.pause_start_unix || 0,
                      status:        ws
                    });
                    log('[LiveSync-JS] workday.sync sent ws=' + ws);
                  } else {
                    b.smlLiveActivity.postMessage({ action: 'workday.end' });
                  }

                  var oi = d.order_id || '', os = d.order_status || '';
                  if (oi && os && os !== 'completed' && os !== 'cancelled') {
                    b.smlLiveActivity.postMessage({
                      action: 'order.sync', orderId: oi,
                      serviceName: d.order_title || '', status: os
                    });
                  } else if (os === 'completed' || os === 'cancelled') {
                    b.smlLiveActivity.postMessage({ action: 'order.end', orderId: oi });
                  }
                })
                .catch(function(e) { log('[LiveSync-JS] error: ' + e); });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Назначение:
        // - Запрашивает whoami через JS внутри авторизованной страницы
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

              fetch('/wp-json/sml/v1/whoami', { credentials: 'include' })
                .then(function (response) {
                  return response.json().catch(function () { return null; });
                })
                .then(function (data) {
                  if (!data) { return; }
                  try {
                    data.current_path = (location && location.pathname) ? location.pathname : '';
                    data.href = (location && location.href) ? location.href : '';
                    data.body_class = bodyClass;

                    if (typeof data.authenticated === 'undefined' && typeof data.logged_in === 'undefined') {
                      data.authenticated = authGuess;
                    }

                    window.webkit.messageHandlers.smlWhoami.postMessage(data);
                  } catch (e) {}
                })
                .catch(function () {});
            })();
            """#

            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        // Назначение:
        // - Копирует cookies из WKWebView в shared storage для URLSession fallback
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

        // Назначение:
        // - Инжектит app bridge в страницу и передает в web корректный APNs environment
        func tryInjectIntoPage(webView: WKWebView, force: Bool) {
            let token = currentToken
            let did = currentDeviceId
            let device = did.isEmpty ? "ios-device" : did

            let biometricEnabled = currentBiometricEnabled
            let hasBiometricLogin = currentHasBiometricLogin

            let bundleId = Bundle.main.bundleIdentifier ?? ""
            let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""

            let registrationContext = currentPushRegistrationContext()
            let pushEnvironment = registrationContext.environment
            let distributionChannel = registrationContext.distribution
            let signedEnvironment = registrationContext.signedEnvironment.isEmpty ? pushEnvironment : registrationContext.signedEnvironment
            let provisioningEnvironment = registrationContext.provisioningEnvironment
            let receiptEnvironment = registrationContext.receiptEnvironment
            let isTestFlight = registrationContext.isTestFlight
            let isDebugBuild = registrationContext.isDebugBuild
            let isReleaseBuild = registrationContext.isReleaseBuild
            let usesProductionPush = (pushEnvironment == "production")

            // Persist sandbox flag so SMLLiveActivityManager can read it before the webview loads.
            UserDefaults(suiteName: "group.ca.stmaryslandscaping.app")?
                .set(!usesProductionPush, forKey: "sml_is_sandbox_push")

            let page = webView.url?.absoluteString ?? ""

            if !force {
                if token == lastInjectedToken &&
                    device == lastInjectedDeviceId &&
                    page == lastInjectedURL &&
                    bundleId == lastInjectedBundleId &&
                    appVersion == lastInjectedAppVersion &&
                    buildNumber == lastInjectedBuildNumber &&
                    pushEnvironment == lastInjectedPushEnvironment &&
                    biometricEnabled == lastInjectedBiometricEnabled &&
                    hasBiometricLogin == lastInjectedHasBiometricLogin {
                    return
                }
            }

            lastInjectedToken = token
            lastInjectedDeviceId = device
            lastInjectedURL = page
            lastInjectedBundleId = bundleId
            lastInjectedAppVersion = appVersion
            lastInjectedBuildNumber = buildNumber
            lastInjectedPushEnvironment = pushEnvironment
            lastInjectedBiometricEnabled = biometricEnabled
            lastInjectedHasBiometricLogin = hasBiometricLogin

            let tokenJS = jsString(token)
            let deviceJS = jsString(device)
            let bundleIdJS = jsString(bundleId)
            let appVersionJS = jsString(appVersion)
            let buildNumberJS = jsString(buildNumber)
            let pushEnvironmentJS = jsString(pushEnvironment)
            let distributionChannelJS = jsString(distributionChannel)
            let signedEnvironmentJS = jsString(signedEnvironment)
            let provisioningEnvironmentJS = jsString(provisioningEnvironment)
            let receiptEnvironmentJS = jsString(receiptEnvironment)

            let isTestFlightJS = isTestFlight ? "true" : "false"
            let isDebugBuildJS = isDebugBuild ? "true" : "false"
            let isReleaseBuildJS = isReleaseBuild ? "true" : "false"
            let isProductionPushJS = usesProductionPush ? "true" : "false"
            let isSandboxPushJS = usesProductionPush ? "false" : "true"
            let biometricEnabledJS = biometricEnabled ? "true" : "false"
            let hasBiometricLoginJS = hasBiometricLogin ? "true" : "false"

            let shouldRegister = !token.isEmpty && !device.isEmpty && !bundleId.isEmpty
            let shouldRegisterJS = shouldRegister ? "true" : "false"

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
              window.SML_APP.apnsEnvironment = \(pushEnvironmentJS);
              window.SML_APP.distribution = \(distributionChannelJS);
              window.SML_APP.releaseChannel = \(distributionChannelJS);
              window.SML_APP.signedEnvironment = \(signedEnvironmentJS);
              window.SML_APP.provisioningEnvironment = \(provisioningEnvironmentJS);
              window.SML_APP.receiptEnvironment = \(receiptEnvironmentJS);
              window.SML_APP.isTestFlight = \(isTestFlightJS);
              window.SML_APP.isDebugBuild = \(isDebugBuildJS);
              window.SML_APP.isReleaseBuild = \(isReleaseBuildJS);
              window.SML_APP.isProductionBuild = \(isProductionPushJS);
              window.SML_APP.isSandboxBuild = \(isSandboxPushJS);
              window.SML_APP.isProductionPush = \(isProductionPushJS);
              window.SML_APP.isSandboxPush = \(isSandboxPushJS);
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
                document.documentElement.setAttribute("data-sml-push-environment", \(pushEnvironmentJS));
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
                    pushEnvironment: window.SML_APP.pushEnvironment,
                    apnsEnvironment: window.SML_APP.apnsEnvironment,
                    distribution: window.SML_APP.distribution,
                    signedEnvironment: window.SML_APP.signedEnvironment,
                    provisioningEnvironment: window.SML_APP.provisioningEnvironment,
                    receiptEnvironment: window.SML_APP.receiptEnvironment,
                    isTestFlight: window.SML_APP.isTestFlight,
                    isDebugBuild: window.SML_APP.isDebugBuild,
                    isReleaseBuild: window.SML_APP.isReleaseBuild,
                    isProductionBuild: window.SML_APP.isProductionBuild,
                    isSandboxBuild: window.SML_APP.isSandboxBuild,
                    isProductionPush: window.SML_APP.isProductionPush,
                    isSandboxPush: window.SML_APP.isSandboxPush
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
                        pushEnvironment: window.SML_APP.pushEnvironment,
                        apnsEnvironment: window.SML_APP.apnsEnvironment,
                        distribution: window.SML_APP.distribution,
                        signedEnvironment: window.SML_APP.signedEnvironment,
                        provisioningEnvironment: window.SML_APP.provisioningEnvironment,
                        receiptEnvironment: window.SML_APP.receiptEnvironment,
                        isTestFlight: window.SML_APP.isTestFlight,
                        isDebugBuild: window.SML_APP.isDebugBuild,
                        isReleaseBuild: window.SML_APP.isReleaseBuild,
                        isProductionBuild: window.SML_APP.isProductionBuild,
                        isSandboxBuild: window.SML_APP.isSandboxBuild,
                        isProductionPush: window.SML_APP.isProductionPush,
                        isSandboxPush: window.SML_APP.isSandboxPush
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
              window.SML_PUSH_APNS_ENVIRONMENT = \(pushEnvironmentJS);
              window.SML_PUSH_DISTRIBUTION = \(distributionChannelJS);
              window.SML_PUSH_SIGNED_ENVIRONMENT = \(signedEnvironmentJS);
              window.SML_PUSH_PROVISIONING_ENVIRONMENT = \(provisioningEnvironmentJS);
              window.SML_PUSH_RECEIPT_ENVIRONMENT = \(receiptEnvironmentJS);
              window.SML_PUSH_IS_PRODUCTION = \(isProductionPushJS);
              window.SML_PUSH_IS_SANDBOX = \(isSandboxPushJS);

              try {
                if (!document.getElementById("sml-ios-style")) {
                  var st = document.createElement("style");
                  st.id = "sml-ios-style";
                  st.type = "text/css";
                  st.appendChild(document.createTextNode(\(cssJS)));
                  document.head.appendChild(st);
                }
              } catch (e) {}

              try {
                if (!window.__smlBiometricLoginCaptureBound) {
                  window.__smlBiometricLoginCaptureBound = true;

                  var captureAndSend = function (form) {
                    try {
                      form = form || document.querySelector("form");
                      if (!form) return;

                      var user = form.querySelector('input[name="log"], input[name="username"], input[type="email"], input[type="text"]');
                      var pass = form.querySelector('input[name="pwd"], input[name="password"], input[type="password"]');
                      if (!user || !pass) return;

                      var username = (user.value || "").trim();
                      var password = pass.value || "";
                      if (!username || !password) return;

                      window.webkit.messageHandlers.smlBiometric.postMessage({
                        action: "captureLogin",
                        username: username,
                        password: password
                      });
                    } catch (e) {}
                  };

                  document.addEventListener("submit", function (ev) {
                    captureAndSend(ev.target);
                  }, true);

                  document.addEventListener("click", function (ev) {
                    try {
                      var target = ev.target && ev.target.closest
                        ? ev.target.closest("button[type='submit'], input[type='submit'], .woocommerce-form-login__submit, .button, .btn")
                        : null;
                      if (!target) return;

                      var form = target.form || target.closest("form");
                      captureAndSend(form);
                    } catch (e) {}
                  }, true);
                }
              } catch (e) {}

              if (window.SML_PUSH_REGISTER && \(shouldRegisterJS)) {
                try { window.SML_PUSH_REGISTER(); } catch (e) {}
              }
            })();
            """

            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Назначение:
        // - Возвращает итоговый контекст регистрации push для JS bridge
        private func currentPushRegistrationContext() -> (
            environment: String,
            distribution: String,
            signedEnvironment: String,
            provisioningEnvironment: String,
            receiptEnvironment: String,
            isTestFlight: Bool,
            isDebugBuild: Bool,
            isReleaseBuild: Bool
        ) {
#if targetEnvironment(simulator)
            return (
                environment: "sandbox",
                distribution: "simulator",
                signedEnvironment: "sandbox",
                provisioningEnvironment: "",
                receiptEnvironment: "sandbox",
                isTestFlight: false,
                isDebugBuild: true,
                isReleaseBuild: false
            )
#else
            let provisioningEnvironment = embeddedPushEnvironment() ?? ""
            let receiptEnvironment = receiptPushEnvironment()
            let hasEmbeddedProfile = hasEmbeddedProvisioningProfile()
            let isTestFlight = receiptEnvironment == "sandbox" && !hasEmbeddedProfile

            let resolvedEnvironment = resolvedPushEnvironment(
                provisioningEnvironment: provisioningEnvironment,
                receiptEnvironment: receiptEnvironment,
                hasEmbeddedProfile: hasEmbeddedProfile
            )

            let signedEnvironment = provisioningEnvironment.isEmpty ? resolvedEnvironment : provisioningEnvironment

            let distribution: String
            if isTestFlight {
                distribution = "testflight"
            } else if provisioningEnvironment == "sandbox" {
                distribution = "development"
            } else if provisioningEnvironment == "production" {
                distribution = "adhoc"
            } else if receiptEnvironment == "production" {
                distribution = "appstore"
            } else {
#if DEBUG
                distribution = "xcode"
#else
                distribution = "unknown"
#endif
            }

#if DEBUG
            let isDebugBuild = true
            let isReleaseBuild = false
#else
            let isDebugBuild = false
            let isReleaseBuild = true
#endif

            return (
                environment: resolvedEnvironment,
                distribution: distribution,
                signedEnvironment: signedEnvironment,
                provisioningEnvironment: provisioningEnvironment,
                receiptEnvironment: receiptEnvironment,
                isTestFlight: isTestFlight,
                isDebugBuild: isDebugBuild,
                isReleaseBuild: isReleaseBuild
            )
#endif
        }

        // Назначение:
        // - Нормализует итоговый APNs environment для текущей сборки
        private func resolvedPushEnvironment(
            provisioningEnvironment: String,
            receiptEnvironment: String,
            hasEmbeddedProfile: Bool
        ) -> String {
            if provisioningEnvironment == "production" {
                return "production"
            }

            if provisioningEnvironment == "sandbox" {
                return "sandbox"
            }

            if receiptEnvironment == "production" {
                return "production"
            }

            if receiptEnvironment == "sandbox" && !hasEmbeddedProfile {
                return "production"
            }

#if DEBUG
            return "sandbox"
#else
            return "production"
#endif
        }

        // Назначение:
        // - Определяет окружение receipt
        private func receiptPushEnvironment() -> String {
            guard let receiptURL = Bundle.main.appStoreReceiptURL else {
                return ""
            }

            let lastPath = receiptURL.lastPathComponent.lowercased()
            if lastPath == "sandboxreceipt" {
                return "sandbox"
            }

            if FileManager.default.fileExists(atPath: receiptURL.path) {
                return "production"
            }

            return ""
        }

        // Назначение:
        // - Проверяет наличие embedded provisioning profile
        private func hasEmbeddedProvisioningProfile() -> Bool {
            Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        }

        // Назначение:
        // - Читает aps-environment из embedded provisioning profile
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

        // Назначение:
        // - После успешной авторизации решает, сохранять ли логин для Face ID
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
                return
            }

            guard BiometricAuthManager.shared.canUseBiometrics() else {
                self.pendingCredentialSave = nil
                return
            }

            promptToEnableBiometricLogin(using: pendingCredentialSave)
        }


        // Назначение:
        // - Показывает alert с предложением включить Face ID логин
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
            })

            DispatchQueue.main.async {
                host.present(alert, animated: true)
            }
        }

        // Назначение:
        // - Запускает Face ID авторизацию и автологин на web-странице
        private func promptForBiometricLoginIfNeeded(webView: WKWebView) {
            guard currentBiometricEnabled else { return }
            guard let login = SMCKeychain.readLogin() else { return }

            BiometricAuthManager.shared.authenticate(reason: "Sign in with Face ID") { [weak self, weak webView] success in
                guard let self, let webView, success else { return }
                self.fillAndSubmitLogin(webView: webView, login: login)
            }
        }

        // Назначение:
        // - Подставляет сохраненные креды в форму логина и отправляет ее
        private func fillAndSubmitLogin(webView: WKWebView, login: SMCStoredLogin) {
            let userJS = jsString(login.username)
            let passJS = jsString(login.password)

            let js = """
            (function () {
              try {
                var form = document.querySelector("form");
                var user = document.querySelector('input[name="log"], input[name="username"], input[type="email"], input[type="text"]');
                var pass = document.querySelector('input[name="pwd"], input[name="password"], input[type="password"]');
                if (!user || !pass) return false;
                user.focus();
                user.value = \(userJS);
                user.dispatchEvent(new Event("input", { bubbles: true }));
                user.dispatchEvent(new Event("change", { bubbles: true }));
                pass.focus();
                pass.value = \(passJS);
                pass.dispatchEvent(new Event("input", { bubbles: true }));
                pass.dispatchEvent(new Event("change", { bubbles: true }));
                if (!form) { form = user.form || pass.form; }
                if (form) {
                  form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
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

        // Назначение:
        // - Открывает внешний URL через UIApplication
        private func openExternally(_ url: URL) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }

        // Назначение:
        // - Сравнивает URL без учета fragment
        private func urlsEffectivelyEqual(_ lhs: URL, _ rhs: URL) -> Bool {
            var l = URLComponents(url: lhs, resolvingAgainstBaseURL: false)
            var r = URLComponents(url: rhs, resolvingAgainstBaseURL: false)
            l?.fragment = nil
            r?.fragment = nil
            return l?.string == r?.string
        }

        // MARK: - Location Tracking

        // Назначение:
        // - Включает нативный location tracking на странице account-workday.
        // - Отписывается и останавливает слежку при уходе со страницы.
        private func handleLocationTracking(webView: WKWebView) {
            let path = webView.url?.path ?? ""
            let onWorkdayPage = path.lowercased().contains("account-workday")

            if onWorkdayPage {
                locationWebView = webView
                if !isWatchingLocation {
                    isWatchingLocation = true
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(onLocationUpdate),
                        name: LocationBridge.didUpdateNotification,
                        object: nil
                    )
                }
                LocationBridge.shared.startWatching()
                injectLocation(into: webView)
            } else {
                if isWatchingLocation {
                    isWatchingLocation = false
                    // Remove only the location observer, keep foreground observer.
                    NotificationCenter.default.removeObserver(
                        self,
                        name: LocationBridge.didUpdateNotification,
                        object: nil
                    )
                    locationWebView = nil
                    LocationBridge.shared.stopWatching()
                }
            }
        }

        // Назначение:
        // - Вызывается NotificationCenter при обновлении координат или смене разрешения.
        @objc private func onLocationUpdate() {
            guard let wv = locationWebView else { return }
            injectLocation(into: wv)
        }

        // Назначение:
        // - Инжектирует window.SML_APP.location с актуальными координатами.
        private func injectLocation(into webView: WKWebView) {
            let payload = LocationBridge.shared.jsPayload
            let js = """
            (function(){
              try {
                window.SML_APP = window.SML_APP || {};
                window.SML_APP.location = \(payload);
              } catch(e) {}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Назначение:
        // - Экранирует Swift string для безопасной вставки в JS
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