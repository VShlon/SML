//  ContentView.swift
//  sml
//
//  Version: 1.0.0
//  Author: Nuvren.com
//
//  Назначение:
//  - SwiftUI TabView для app-меню.
//  - Роли разделены по реальным сценариям сайта.
//  - More открывается как sheet, а не как отдельная вкладка.
//  - Роль обновляет меню без принудительного возврата пользователя на Home.
//  - Добавлена простая биометрическая блокировка по настройке Face ID.
//

import SwiftUI
import UIKit
import LocalAuthentication
import CoreLocation

enum Tab: Hashable {
    case left1
    case left2
    case center
    case right1
    case right2
}




final class LocationState: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationState()

    @Published private(set) var revision: Int = 0
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastUpdateAt: Date?
    private var hasRequestedAuthorization = false
    private var isUpdatingLocation = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func prepareForWorkdayPage() {
        let status = authorizationStatus()
        switch status {
        case .notDetermined:
            if !hasRequestedAuthorization {
                hasRequestedAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationIfNeeded(force: false)
        case .denied:
            presentAlert("Location access is blocked. Enable location access to use Workday at Shop.")
        case .restricted:
            presentAlert("Location access is restricted on this device. Workday at Shop is unavailable.")
        @unknown default:
            break
        }
    }

    func requestLocationIfNeeded(force: Bool) {
        let status = authorizationStatus()
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            prepareForWorkdayPage()
            return
        }

        if !force, let lastUpdateAt, Date().timeIntervalSince(lastUpdateAt) < 20, lastLocation != nil {
            return
        }

        isUpdatingLocation = true
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func bridgePayload() -> [String: Any] {
        let status = authorizationStatus()
        var payload: [String: Any] = [
            "authorization": authorizationLabel(status),
            "available": status == .authorizedAlways || status == .authorizedWhenInUse
        ]

        if let location = lastLocation {
            payload["timestamp"] = Int((lastUpdateAt ?? Date()).timeIntervalSince1970)
            payload["coords"] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy
            ]
        }

        return payload
    }

    private func authorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    private func authorizationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways:
            return "authorized_always"
        case .authorizedWhenInUse:
            return "authorized_when_in_use"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }

    @MainActor
    private func setAlertState(message: String) {
        guard alertMessage != message || !showAlert else {
            return
        }
        alertMessage = message
        showAlert = true
    }

    private func presentAlert(_ message: String) {
        Task { @MainActor in
            self.setAlertState(message: message)
        }
    }

    @MainActor
    private func bumpRevision() {
        revision += 1
    }

    private func markUpdated() {
        Task { @MainActor in
            self.bumpRevision()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            Task {
                self.requestLocationIfNeeded(force: true)
            }
        case .denied:
            presentAlert("Location access is blocked. Enable location access to use Workday at Shop.")
            markUpdated()
        case .restricted:
            presentAlert("Location access is restricted on this device. Workday at Shop is unavailable.")
            markUpdated()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        Task {
            self.lastLocation = location
            self.lastUpdateAt = Date()
            if self.isUpdatingLocation {
                self.isUpdatingLocation = false
                manager.stopUpdatingLocation()
            }
            self.markUpdated()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain && nsError.code == CLError.denied.rawValue {
            presentAlert("Location access is blocked. Enable location access to use Workday at Shop.")
        }
        Task {
            if self.isUpdatingLocation {
                self.isUpdatingLocation = false
                manager.stopUpdatingLocation()
            }
            self.markUpdated()
        }
    }
}

@MainActor
final class AppNavigationState: ObservableObject {

    static let shared = AppNavigationState()

    struct OpenCommand: Equatable {
        let id: UUID
        let url: URL
        let keepCurrentTab: Bool
    }

    @Published var openCommand: OpenCommand?

    private init() {}

    func openInMainWindow(_ url: URL, keepCurrentTab: Bool = true) {
        openCommand = OpenCommand(id: UUID(), url: url, keepCurrentTab: keepCurrentTab)
    }

    func consume(_ command: OpenCommand) {
        if openCommand?.id == command.id {
            openCommand = nil
        }
    }
}

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sml_face_id_enabled") private var biometricLockEnabled: Bool = false

    @State private var selected: Tab = .left1
    @State private var lastNonMoreTab: Tab = .left1
    @State private var showMoreSheet: Bool = false

    @StateObject private var push = PushState.shared
    @StateObject private var roleState = RoleState.shared
    @StateObject private var appNavigation = AppNavigationState.shared
    @StateObject private var locationState = LocationState.shared

    @State private var activatedTabs: Set<Tab> = [.left1]

    @State private var left1Token = UUID()
    @State private var left2Token = UUID()
    @State private var centerToken = UUID()
    @State private var right1Token = UUID()
    @State private var right2Token = UUID()

    @State private var left1Command: WebNavigationCommand? = nil
    @State private var left2Command: WebNavigationCommand? = nil
    @State private var centerCommand: WebNavigationCommand? = nil
    @State private var right1Command: WebNavigationCommand? = nil
    @State private var right2Command: WebNavigationCommand? = nil

    @State private var right2URL: URL = AppConfig.siteURL
    @State private var isRight2HostingPage: Bool = false

    @State private var suppressReloadOnce: Bool = false
    @State private var needsHomeRefreshAfterExternal: Bool = false

    @State private var isAppLocked: Bool = false
    @State private var isUnlockInProgress: Bool = false
    @State private var lockAlertMessage: String = ""
    @State private var showLockAlert: Bool = false
    @State private var hasCompletedFirstActivation: Bool = false

    private let allowedHost = AppConfig.siteHost
    private let brand = AppConfig.brandColor
    private let blackSelected = UIColor.black
    private let blackUnselected = UIColor.black.withAlphaComponent(0.35)

    var body: some View {

        TabView(selection: $selected) {

            ForEach(makeTabs(for: roleState.mode), id: \.tab) { spec in
                tabBody(spec)
                    .tag(spec.tab)
                    .tabItem { tabLabel(spec) }
            }

            moreTabBody()
                .tag(Tab.right2)
                .tabItem {
                    Label { Text("") } icon: { Image(systemName: "ellipsis") }
                        .labelStyle(.iconOnly)
                }
        }
        .background(
            TabBarReselectDetector { didReselect in
                handleTabReselect(didReselect, mode: roleState.mode)
            }
            .frame(width: 0, height: 0)
        )
        .overlay {
            if isAppLocked {
                AppLockOverlay(
                    isWorking: isUnlockInProgress,
                    onUnlock: { requestBiometricUnlockIfNeeded() },
                    onDisable: {
                        biometricLockEnabled = false
                        isAppLocked = false
                    }
                )
            }
        }
        .sheet(isPresented: $showMoreSheet) {
            SMLMoreRootView()
                .preferredColorScheme(.light)
        }
        .alert("Face ID", isPresented: $showLockAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lockAlertMessage)
        }
        .alert("Location", isPresented: $locationState.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(locationState.alertMessage)
        }
        .onAppear {
            activatedTabs.insert(selected)
            roleState.refresh()
            applyTabBarAppearance()
            isAppLocked = false
        }
        .onChange(of: roleState.mode) { _, _ in
            applyTabBarAppearance()
        }
        .onChange(of: selected) { oldTab, newTab in
            activatedTabs.insert(newTab)

            if oldTab == .right2, newTab != .right2, isRight2HostingPage {
                resetRight2ToRoot()
            }

            if newTab == .right2 {
                if isRight2HostingPage {
                    return
                }

                showMoreSheet = true
                suppressReloadOnce = true
                selected = lastNonMoreTab
                return
            }

            lastNonMoreTab = newTab

            if suppressReloadOnce {
                suppressReloadOnce = false
                return
            }

            if shouldResetOnSelect(tab: newTab, mode: roleState.mode) {
                resetTabToRoot(newTab)
            }
        }
        .onReceive(push.$openCommand) { cmd in
            guard let cmd else { return }
            routeFromPush(cmd, mode: roleState.mode)
            push.consumeOpenCommand(cmd)
        }
        .onReceive(appNavigation.$openCommand) { cmd in
            guard let cmd else { return }
            routeFromMainWindowRequest(cmd, mode: roleState.mode)
            appNavigation.consume(cmd)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                roleState.refresh()
                locationState.requestLocationIfNeeded(force: false)
                applyTabBarAppearance()

                if hasCompletedFirstActivation {
                    if biometricLockEnabled, isAppLocked {
                        requestBiometricUnlockIfNeeded()
                    }
                } else {
                    hasCompletedFirstActivation = true
                    isAppLocked = false
                }

                if needsHomeRefreshAfterExternal {
                    needsHomeRefreshAfterExternal = false
                    suppressReloadOnce = true
                    selected = .left1
                    lastNonMoreTab = .left1
                    resetAllTabsToRoot()
                }

            case .inactive, .background:
                if biometricLockEnabled, hasCompletedFirstActivation {
                    isAppLocked = true
                    showMoreSheet = false
                }

            @unknown default:
                break
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Reset policy

    private func shouldResetOnSelect(tab: Tab, mode: RoleState.Mode) -> Bool {
        if tab == .center && (mode == .guest || mode == .client) {
            return false
        }
        return true
    }

    private func shouldResetOnReselect(tab: Tab, mode: RoleState.Mode) -> Bool {
        if (mode == .guest || mode == .client), tab == .center {
            return false
        }

        if tab == .right2 {
            return false
        }

        return true
    }

    // MARK: - Tabs model

    private struct TabSpec {
        let tab: Tab
        let systemImage: String
        let isCenter: Bool
        let url: String
        let token: UUID
        let command: WebNavigationCommand?
    }

    private func makeTabs(for mode: RoleState.Mode) -> [TabSpec] {
        switch mode {

        case .guest, .client:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: AppConfig.url("/").absoluteString, token: left1Token, command: left1Command),

                .init(tab: .left2, systemImage: "leaf", isCenter: false,
                      url: AppConfig.url("/services/").absoluteString, token: left2Token, command: left2Command),

                .init(tab: .center, systemImage: "phone", isCenter: true,
                      url: AppConfig.url("/contact/").absoluteString, token: centerToken, command: centerCommand),

                .init(tab: .right1, systemImage: "photo.on.rectangle", isCenter: false,
                      url: AppConfig.url("/projects/").absoluteString, token: right1Token, command: right1Command),
            ]

        case .worker:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: AppConfig.url("/").absoluteString, token: left1Token, command: left1Command),

                .init(tab: .left2, systemImage: "briefcase", isCenter: false,
                      url: AppConfig.url("/account-workday/").absoluteString, token: left2Token, command: left2Command),

                .init(tab: .center, systemImage: "checklist", isCenter: true,
                      url: AppConfig.url("/tasks-today/").absoluteString, token: centerToken, command: centerCommand),

                .init(tab: .right1, systemImage: "doc.text", isCenter: false,
                      url: AppConfig.url("/account-report/").absoluteString, token: right1Token, command: right1Command),
            ]

        case .accountant:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: AppConfig.url("/").absoluteString, token: left1Token, command: left1Command),

                .init(tab: .left2, systemImage: "doc.text", isCenter: false,
                      url: AppConfig.url("/monthly-billing/").absoluteString, token: left2Token, command: left2Command),

                .init(tab: .center, systemImage: "briefcase", isCenter: true,
                      url: AppConfig.url("/account-workday/").absoluteString, token: centerToken, command: centerCommand),

                .init(tab: .right1, systemImage: "person.3", isCenter: false,
                      url: AppConfig.url("/workers-time/").absoluteString, token: right1Token, command: right1Command),
            ]

        case .administrator, .manager, .owner:
            return [
                .init(tab: .left1, systemImage: "house", isCenter: false,
                      url: AppConfig.url("/").absoluteString, token: left1Token, command: left1Command),

                .init(tab: .left2, systemImage: "plus.circle", isCenter: false,
                      url: AppConfig.url("/create-task/").absoluteString, token: left2Token, command: left2Command),

                .init(tab: .center, systemImage: "square.grid.2x2", isCenter: true,
                      url: AppConfig.url("/workspace/").absoluteString, token: centerToken, command: centerCommand),

                .init(tab: .right1, systemImage: "list.bullet.rectangle", isCenter: false,
                      url: AppConfig.url("/all-tasks/").absoluteString, token: right1Token, command: right1Command),
            ]
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private func tabBody(_ spec: TabSpec) -> some View {
        LazyTabContainer(
            isActivated: activatedTabs.contains(spec.tab),
            url: URL(string: spec.url)!,
            apnsToken: push.apnsToken,
            deviceId: push.deviceId,
            command: spec.command,
            token: spec.token,
            locationRevision: locationState.revision
        )
    }

    @ViewBuilder
    private func moreTabBody() -> some View {
        if isRight2HostingPage {
            LazyTabContainer(
                isActivated: activatedTabs.contains(.right2),
                url: right2URL,
                apnsToken: push.apnsToken,
                deviceId: push.deviceId,
                command: right2Command,
                token: right2Token,
                locationRevision: locationState.revision
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Tab labels

    private func tabLabel(_ spec: TabSpec) -> some View {
        Label { Text("") } icon: {
            tabIcon(systemName: spec.systemImage, isCenter: spec.isCenter)
        }
        .labelStyle(.iconOnly)
    }

    private func tabIcon(systemName: String, isCenter: Bool) -> some View {
        if isCenter,
           let img = UIImage(systemName: systemImageFallback(systemName))?
            .withTintColor(brand, renderingMode: .alwaysOriginal) {
            return Image(uiImage: img)
        }
        return Image(systemName: systemImageFallback(systemName))
    }

    private func systemImageFallback(_ name: String) -> String { name }

    // MARK: - Appearance

    private func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.backgroundEffect = nil
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.12)

        appearance.selectionIndicatorImage = UIImage()
        appearance.selectionIndicatorTintColor = .clear

        let item = UITabBarItemAppearance(style: .stacked)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.clear]
        item.normal.iconColor = blackUnselected
        item.selected.iconColor = blackSelected

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let tabBarProxy = UITabBar.appearance()
        tabBarProxy.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBarProxy.scrollEdgeAppearance = appearance
        }
        tabBarProxy.isTranslucent = false
        tabBarProxy.backgroundColor = .white
    }

    // MARK: - Reselect handler

    private func handleTabReselect(_ tab: Tab, mode: RoleState.Mode) {
        if tab == .right2 {
            showMoreSheet = true
            return
        }

        if shouldResetOnReselect(tab: tab, mode: mode) {
            resetTabToRoot(tab)
        }
    }

    // MARK: - Root reset helpers

    private func resetLeft1ToRoot() { left1Command = nil; left1Token = UUID() }
    private func resetLeft2ToRoot() { left2Command = nil; left2Token = UUID() }
    private func resetCenterToRoot() { centerCommand = nil; centerToken = UUID() }
    private func resetRight1ToRoot() { right1Command = nil; right1Token = UUID() }
    private func resetRight2ToRoot() {
        right2Command = nil
        right2URL = AppConfig.siteURL
        isRight2HostingPage = false
        right2Token = UUID()
    }

    private func resetAllTabsToRoot() {
        resetLeft1ToRoot()
        resetLeft2ToRoot()
        resetCenterToRoot()
        resetRight1ToRoot()
        resetRight2ToRoot()
    }

    private func resetTabToRoot(_ tab: Tab) {
        switch tab {
        case .left1:  resetLeft1ToRoot()
        case .left2:  resetLeft2ToRoot()
        case .center: resetCenterToRoot()
        case .right1: resetRight1ToRoot()
        case .right2: resetRight2ToRoot()
        }
    }

    // MARK: - External URL policy

    private func isExternalURL(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "http" && scheme != "https" { return false }

        let host = (url.host ?? "").lowercased()
        if host.isEmpty { return false }

        if host == allowedHost || host.hasSuffix("." + allowedHost) { return false }
        return true
    }

    private func openExternally(_ url: URL) {
        DispatchQueue.main.async { UIApplication.shared.open(url, options: [:]) }
    }

    // MARK: - Push routing

    private func routeFromPush(_ cmd: PushState.PushOpenCommand, mode: RoleState.Mode) {
        guard let url = cmd.url else { return }
        routeToURL(url, commandId: cmd.id, mode: mode)
    }

    private func routeFromMainWindowRequest(_ cmd: AppNavigationState.OpenCommand, mode: RoleState.Mode) {
        if cmd.keepCurrentTab {
            routeToURLInCurrentTab(cmd.url, commandId: cmd.id)
        } else {
            routeToURLFromMoreMenu(cmd.url, commandId: cmd.id, mode: mode)
        }
    }

    private func routeToURLInCurrentTab(_ url: URL, commandId: UUID) {
        left1Command = nil
        left2Command = nil
        centerCommand = nil
        right1Command = nil

        if showMoreSheet {
            showMoreSheet = false
        }

        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "http" && scheme != "https" {
            openExternally(url)
            return
        }

        if isExternalURL(url) {
            openExternally(url)
            return
        }

        let target: Tab = {
            if selected == .right2 {
                return isRight2HostingPage ? .right2 : lastNonMoreTab
            }
            return selected
        }()

        activatedTabs.insert(target)

        if selected != target {
            suppressReloadOnce = true
            selected = target
        }

        lastNonMoreTab = target

        let nav = WebNavigationCommand(id: commandId, url: url)

        switch target {
        case .left1:
            left1Command = nav
        case .left2:
            left2Command = nav
        case .center:
            centerCommand = nav
        case .right1:
            right1Command = nav
        case .right2:
            right2URL = url
            right2Command = nav
            isRight2HostingPage = true
        }
    }

    private func routeToURLFromMoreMenu(_ url: URL, commandId: UUID, mode: RoleState.Mode) {
        left1Command = nil
        left2Command = nil
        centerCommand = nil
        right1Command = nil
        right2Command = nil

        if showMoreSheet {
            showMoreSheet = false
        }

        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "http" && scheme != "https" {
            openExternally(url)
            return
        }

        if isExternalURL(url) {
            openExternally(url)
            return
        }

        let nav = WebNavigationCommand(id: commandId, url: url)

        activatedTabs.insert(.right2)
        isRight2HostingPage = true
        right2URL = url
        right2Command = nav

        if selected != .right2 {
            suppressReloadOnce = true
            selected = .right2
        }
    }

    private func routeToURL(_ url: URL, commandId: UUID, mode: RoleState.Mode) {
        left1Command = nil
        left2Command = nil
        centerCommand = nil
        right1Command = nil

        if showMoreSheet {
            showMoreSheet = false
        }

        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "http" && scheme != "https" {
            openExternally(url)
            return
        }

        if isExternalURL(url) {
            needsHomeRefreshAfterExternal = true
            suppressReloadOnce = true
            selected = .left1
            lastNonMoreTab = .left1
            openExternally(url)
            return
        }

        let path = url.path.lowercased()
        let target = pushTarget(for: path, mode: mode)

        suppressReloadOnce = true
        selected = target
        lastNonMoreTab = target

        let nav = WebNavigationCommand(id: commandId, url: url)

        switch target {
        case .left1:  left1Command = nav
        case .left2:  left2Command = nav
        case .center: centerCommand = nav
        case .right1: right1Command = nav
        case .right2: break
        }
    }

    private func explicitTabTarget(for path: String, mode: RoleState.Mode) -> Tab? {
        switch mode {
        case .guest, .client:
            if path.contains("/services") { return .left2 }
            if path.contains("/contact") { return .center }
            if path.contains("/projects") { return .right1 }
            return nil

        case .worker:
            if path.contains("/account-workday") { return .left2 }
            if path.contains("/tasks-today") { return .center }
            if path.contains("/account-report") { return .right1 }
            return nil

        case .accountant:
            if path.contains("/monthly-billing") { return .left2 }
            if path.contains("/account-workday") { return .center }
            if path.contains("/workers-time") { return .right1 }
            return nil

        case .administrator, .manager, .owner:
            if path.contains("/create-task") { return .left2 }
            if path.contains("/all-tasks") { return .right1 }
            if path.contains("/workspace") ||
                path.contains("/groups") ||
                path.contains("/all-workers") ||
                path.contains("/all-clients") ||
                path.contains("/client-details") ||
                path.contains("/task-history") ||
                path.contains("/reports") ||
                path.contains("/snow-control") ||
                path.contains("/workers-time") ||
                path.contains("/monthly-billing") ||
                path.contains("/payroll-review") {
                return .center
            }
            return nil
        }
    }

    private func pushTarget(for path: String, mode: RoleState.Mode) -> Tab {
        switch mode {
        case .guest, .client:
            if path.contains("/services") { return .left2 }
            if path.contains("/contact") { return .center }
            if path.contains("/projects") { return .right1 }
            return .left1

        case .worker:
            if path.contains("/account-workday") { return .left2 }
            if path.contains("/tasks-today") { return .center }
            if path.contains("/account-report") { return .right1 }
            return .left1

        case .accountant:
            if path.contains("/monthly-billing") { return .left2 }
            if path.contains("/account-workday") { return .center }
            if path.contains("/workers-time") { return .right1 }
            return .left1

        case .administrator, .manager, .owner:
            if path.contains("/create-task") { return .left2 }
            if path.contains("/all-tasks") { return .right1 }
            if path.contains("/workspace") ||
                path.contains("/groups") ||
                path.contains("/all-workers") ||
                path.contains("/all-clients") ||
                path.contains("/client-details") ||
                path.contains("/task-history") ||
                path.contains("/reports") ||
                path.contains("/snow-control") ||
                path.contains("/workers-time") ||
                path.contains("/monthly-billing") ||
                path.contains("/payroll-review") {
                return .center
            }
            return .left1
        }
    }

    // MARK: - Face ID

    private func requestBiometricUnlockIfNeeded() {
        guard biometricLockEnabled else {
            isAppLocked = false
            return
        }

        guard isAppLocked else { return }
        guard !isUnlockInProgress else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            biometricLockEnabled = false
            isAppLocked = false
            lockAlertMessage = error?.localizedDescription ?? "Face ID is unavailable on this device."
            showLockAlert = true
            return
        }

        isUnlockInProgress = true

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock SML") { success, error in
            DispatchQueue.main.async {
                isUnlockInProgress = false

                if success {
                    isAppLocked = false
                    return
                }

                isAppLocked = true

                let nsError = error as NSError?
                let code = nsError?.code ?? 0
                if code == LAError.userCancel.rawValue || code == LAError.systemCancel.rawValue {
                    return
                }

                lockAlertMessage = error?.localizedDescription ?? "Face ID could not unlock the app."
                showLockAlert = true
            }
        }
    }
}

private struct AppLockOverlay: View {
    let isWorking: Bool
    let onUnlock: () -> Void
    let onDisable: () -> Void

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color(uiColor: AppConfig.brandColor))

                VStack(spacing: 6) {
                    Text("Face ID")
                        .font(.title3.weight(.semibold))
                    Text("Unlock the app to continue.")
                        .foregroundStyle(.secondary)
                }

                Button(action: onUnlock) {
                    HStack(spacing: 10) {
                        if isWorking {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isWorking ? "Checking..." : "Unlock")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: AppConfig.brandColor))
                .disabled(isWorking)

                Button("Turn Off Face ID", action: onDisable)
                    .disabled(isWorking)
            }
            .padding(24)
            .frame(maxWidth: 320)
        }
    }
}

// MARK: - UIKit bridge: detect reselect on TabBar

private struct TabBarReselectDetector: UIViewControllerRepresentable {

    let onReselect: (Tab) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        context.coordinator.attach(to: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.attach(to: uiViewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate, UITabBarDelegate {

        private let onReselect: (Tab) -> Void
        private weak var tabBarController: UITabBarController?
        private var currentSelectedIndex: Int?

        init(onReselect: @escaping (Tab) -> Void) {
            self.onReselect = onReselect
        }

        func attach(to vc: UIViewController) {
            guard tabBarController == nil else { return }

            DispatchQueue.main.async { [weak self, weak vc] in
                guard let self, let vc else { return }

                var p: UIViewController? = vc
                while let parent = p?.parent {
                    if let tbc = parent as? UITabBarController {
                        self.tabBarController = tbc
                        tbc.delegate = self
                        tbc.tabBar.delegate = self
                        self.currentSelectedIndex = tbc.selectedIndex
                        return
                    }
                    p = parent
                }
            }
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let idx = tabBar.items?.firstIndex(of: item) else { return }
            if let currentSelectedIndex, currentSelectedIndex == idx {
                onReselect(mapIndexToTab(idx))
            }
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            currentSelectedIndex = tabBarController.selectedIndex
        }

        private func mapIndexToTab(_ idx: Int) -> Tab {
            switch idx {
            case 0: return .left1
            case 1: return .left2
            case 2: return .center
            case 3: return .right1
            default: return .right2
            }
        }
    }
}


private struct LazyTabContainer: View {
    let isActivated: Bool
    let url: URL
    let apnsToken: String
    let deviceId: String
    let command: WebNavigationCommand?
    let token: UUID
    let locationRevision: Int

    var body: some View {
        Group {
            if isActivated {
                WebView(
                    url: url,
                    apnsToken: apnsToken,
                    deviceId: deviceId,
                    command: command,
                    locationRevision: locationRevision
                )
                .id(token)
            } else {
                ZStack {
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
