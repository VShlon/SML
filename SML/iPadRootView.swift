//
//  iPadRootView.swift
//  SML
//
//  Native iPad layout: NavigationSplitView with branded sidebar + WebView detail.
//  Replaces the tab bar on iPad (regular horizontal size class).
//

import SwiftUI

// MARK: - Sidebar item model

struct SidebarItem: Identifiable, Hashable {
    let id: Tab
    let icon: String
    let label: String
    let url: String
}

// MARK: - iPad root

struct iPadRootView: View {

    @StateObject private var push      = PushState.shared
    @StateObject private var roleState = RoleState.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedItem: SidebarItem?
    @State private var tokens: [Tab: UUID]               = defaultTokens()
    @State private var commands: [Tab: WebNavigationCommand?] = [:]
    @State private var showMoreSheet   = false
    @State private var mainWindowPage: MainWindowPage?   = nil
    @State private var suppressReload  = false
    @State private var needsHomeRefreshAfterExternal = false

    private let brand = Color(red: 67 / 255.0, green: 130 / 255.0, blue: 57 / 255.0)

    private static func defaultTokens() -> [Tab: UUID] {
        [.left1: UUID(), .left2: UUID(), .center: UUID(), .right1: UUID()]
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.prominentDetail)
        .tint(brand)
        .onAppear {
            roleState.refresh()
            let items = sidebarItems(for: roleState.mode)
            if selectedItem == nil { selectedItem = items.first }
        }
        .onChange(of: roleState.mode) { _, _ in
            let items = sidebarItems(for: roleState.mode)
            tokens = Self.defaultTokens()
            selectedItem = items.first
        }
        .onOpenURL { url in
            handleWidgetURL(url)
        }
        .onReceive(push.$openCommand) { cmd in
            guard let cmd else { return }
            handlePushCommand(cmd)
            push.consumeOpenCommand(cmd)
        }
        .onReceive(NotificationCenter.default.publisher(for: .smlPresentMainWindowPage)) { note in
            guard
                let info  = note.userInfo,
                let title = info["title"] as? String,
                let url   = info["url"]   as? URL
            else { return }
            showMoreSheet  = false
            mainWindowPage = MainWindowPage(title: title, url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .smlSwitchTab)) { note in
            guard
                let rawValue = note.userInfo?["tab"] as? String,
                let tab = Tab(rawValue: rawValue)
            else { return }
            let items = sidebarItems(for: roleState.mode)
            if let item = items.first(where: { $0.id == tab }) {
                selectedItem = item
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                roleState.refresh()
                if needsHomeRefreshAfterExternal {
                    needsHomeRefreshAfterExternal = false
                    tokens = Self.defaultTokens()
                    selectedItem = sidebarItems(for: roleState.mode).first
                }
            }
        }
        .sheet(isPresented: $showMoreSheet) {
            SMLMoreRootView().preferredColorScheme(.light)
        }
        .fullScreenCover(item: $mainWindowPage) { page in
            MainWindowWebScreen(title: page.title, url: page.url)
                .preferredColorScheme(.light)
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {

            // Branded header
            VStack(spacing: 4) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Nav list
            List(selection: $selectedItem) {
                Section {
                    ForEach(sidebarItems(for: roleState.mode)) { item in
                        Label(item.label, systemImage: item.icon)
                            .tag(item)
                    }
                }

                Section {
                    Button {
                        showMoreSheet = true
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Role footer
            roleFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .navigationTitle("")
        .navigationBarHidden(true)
    }

    // Role badge at the bottom of the sidebar
    private var roleFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: roleIcon(roleState.mode))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(brand)

            VStack(alignment: .leading, spacing: 1) {
                Text(roleName(roleState.mode))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("St. Marys Landscaping")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        let item = selectedItem ?? sidebarItems(for: roleState.mode).first

        if item?.id == .left1 && roleState.mode == .guest {
            NativeGuestHomeView()
                .ignoresSafeArea(edges: .top)
        } else if item?.id == .left1 && roleState.mode == .client {
            NativeClientHomeView()
                .ignoresSafeArea(edges: .top)
        } else if let item, let url = URL(string: item.url) {
            WebView(
                url: url,
                apnsToken:        push.apnsToken,
                deviceId:         push.deviceId,
                biometricEnabled: push.biometricEnabled,
                hasBiometricLogin: push.hasBiometricLogin,
                command:          commands[item.id] ?? nil
            )
            .id(tokens[item.id] ?? UUID())
            .ignoresSafeArea()
        } else {
            Color.white.ignoresSafeArea()
        }
    }

    // MARK: - Sidebar items per role (mirrors iPhone tabs)

    private func sidebarItems(for mode: RoleState.Mode) -> [SidebarItem] {
        switch mode {
        case .guest:
            return [
                .init(id: .left1,  icon: "house",                   label: "Home",        url: "https://stmaryslandscaping.ca/"),
                .init(id: .left2,  icon: "person",                  label: "Sign In",     url: "https://stmaryslandscaping.ca/account/"),
                .init(id: .center, icon: "paperplane",              label: "Get a Quote", url: "https://stmaryslandscaping.ca/new-request/"),
                .init(id: .right1, icon: "leaf",                    label: "Services",    url: "https://stmaryslandscaping.ca/services/"),
            ]
        case .client:
            return [
                .init(id: .left1,  icon: "house",                   label: "Home",        url: "https://stmaryslandscaping.ca/"),
                .init(id: .left2,  icon: "list.bullet.clipboard",   label: "My Requests", url: "https://stmaryslandscaping.ca/my-requests/"),
                .init(id: .center, icon: "paperplane",              label: "New Request", url: "https://stmaryslandscaping.ca/new-request/"),
                .init(id: .right1, icon: "person.crop.circle",      label: "Account",     url: "https://stmaryslandscaping.ca/account/"),
            ]
        case .worker:
            return [
                .init(id: .left1,  icon: "house",                   label: "Home",        url: "https://stmaryslandscaping.ca/"),
                .init(id: .left2,  icon: "calendar",                label: "Workday",     url: "https://stmaryslandscaping.ca/account-workday/"),
                .init(id: .center, icon: "checklist",               label: "Tasks Today", url: "https://stmaryslandscaping.ca/tasks-today/"),
                .init(id: .right1, icon: "exclamationmark.bubble",  label: "Report",      url: "https://stmaryslandscaping.ca/account-report/"),
            ]
        case .accountant:
            return [
                .init(id: .left1,  icon: "house",                   label: "Home",           url: "https://stmaryslandscaping.ca/"),
                .init(id: .left2,  icon: "calendar.badge.clock",    label: "Monthly Billing", url: "https://stmaryslandscaping.ca/monthly-billing/"),
                .init(id: .center, icon: "briefcase",               label: "Workday",         url: "https://stmaryslandscaping.ca/account-workday/"),
                .init(id: .right1, icon: "dollarsign.square",       label: "Payroll Review",  url: "https://stmaryslandscaping.ca/payroll-review/"),
            ]
        case .admin:
            return [
                .init(id: .left1,  icon: "house",                   label: "Home",        url: "https://stmaryslandscaping.ca/"),
                .init(id: .left2,  icon: "plus.square",             label: "Create Task", url: "https://stmaryslandscaping.ca/create-task/"),
                .init(id: .center, icon: "rectangle.3.group",       label: "Workspace",   url: "https://stmaryslandscaping.ca/workspace/"),
                .init(id: .right1, icon: "tray.full",               label: "All Tasks",   url: "https://stmaryslandscaping.ca/all-tasks/"),
            ]
        case .owner:
            return [
                .init(id: .left1,  icon: "person.crop.circle",      label: "Account",     url: "https://stmaryslandscaping.ca/account/"),
                .init(id: .left2,  icon: "plus.square",             label: "Create Task", url: "https://stmaryslandscaping.ca/create-task/"),
                .init(id: .center, icon: "briefcase",               label: "Workday",     url: "https://stmaryslandscaping.ca/account-workday/"),
                .init(id: .right1, icon: "tray.full",               label: "All Tasks",   url: "https://stmaryslandscaping.ca/all-tasks/"),
            ]
        case .menager:
            return [
                .init(id: .left1,  icon: "house",                   label: "Home",        url: "https://stmaryslandscaping.ca/"),
                .init(id: .left2,  icon: "plus.square",             label: "Create Task", url: "https://stmaryslandscaping.ca/create-task/"),
                .init(id: .center, icon: "briefcase",               label: "Workday",     url: "https://stmaryslandscaping.ca/account-workday/"),
                .init(id: .right1, icon: "tray.full",               label: "All Tasks",   url: "https://stmaryslandscaping.ca/all-tasks/"),
            ]
        }
    }

    // MARK: - Widget deep link routing (mirrors ContentView logic)

    private func handleWidgetURL(_ url: URL) {
        guard url.scheme == "sml" else { return }
        let items = sidebarItems(for: roleState.mode)
        let host  = url.host ?? ""

        let targetTab = widgetTab(for: host, mode: roleState.mode)
        if let item = items.first(where: { $0.id == targetTab }) {
            selectedItem = item
        }
    }

    private func widgetTab(for host: String, mode: RoleState.Mode) -> Tab {
        switch host {
        case "home":        return .left1
        case "tasks-today": return mode == .worker ? .center : .left1
        case "workday":
            switch mode {
            case .worker:                       return .left2
            case .accountant, .owner, .menager: return .center
            default:                            return .left1
            }
        case "workspace":   return mode == .admin ? .center : .left1
        case "all-tasks":
            switch mode {
            case .admin, .owner, .menager: return .right1
            default:                       return .left1
            }
        case "create":
            switch mode {
            case .admin, .owner, .menager: return .left2
            default:                       return .left1
            }
        case "billing":     return mode == .accountant ? .left2 : .left1
        case "payroll":     return mode == .accountant ? .right1 : .left1
        case "report":      return mode == .worker ? .right1 : .left1
        case "requests":    return mode == .client ? .left2 : .left1
        case "account":
            switch mode {
            case .client: return .right1
            case .owner:  return .left1
            default:      return .left1
            }
        case "quote":       return (mode == .guest || mode == .client) ? .center : .left1
        case "services":    return mode == .guest ? .right1 : .left1
        default:            return .left1
        }
    }

    // MARK: - Push routing

    private func handlePushCommand(_ cmd: PushState.PushOpenCommand) {
        guard let url = cmd.url else { return }

        let path  = url.path.lowercased()
        let items = sidebarItems(for: roleState.mode)

        let targetTab = pushTab(for: path, mode: roleState.mode)
        if let item = items.first(where: { $0.id == targetTab }) {
            commands[item.id] = WebNavigationCommand(id: cmd.id, url: url)
            selectedItem = item
        }
    }

    private func pushTab(for path: String, mode: RoleState.Mode) -> Tab {
        switch mode {
        case .worker:
            if path.contains("/account-workday") { return .left2 }
            if path.contains("/tasks-today")     { return .center }
            if path.contains("/account-report")  { return .right1 }
        case .accountant:
            if path.contains("/monthly-billing") { return .left2 }
            if path.contains("/account-workday") { return .center }
            if path.contains("/payroll-review")  { return .right1 }
        case .admin, .owner, .menager:
            if path.contains("/create-task")     { return .left2 }
            if path.contains("/workspace")       { return .center }
            if path.contains("/all-tasks")       { return .right1 }
            if path.contains("/account-workday") { return .center }
        case .client:
            if path.contains("/my-requests")     { return .left2 }
            if path.contains("/new-request")     { return .center }
            if path.contains("/account")         { return .right1 }
        default: break
        }
        return .left1
    }

    // MARK: - Helpers

    private func roleIcon(_ mode: RoleState.Mode) -> String {
        switch mode {
        case .guest:      return "person"
        case .client:     return "house"
        case .worker:     return "hammer"
        case .accountant: return "dollarsign.circle"
        case .admin:      return "shield"
        case .owner:      return "crown"
        case .menager:    return "person.2"
        }
    }

    private func roleName(_ mode: RoleState.Mode) -> String {
        switch mode {
        case .guest:      return "Guest"
        case .client:     return "Client"
        case .worker:     return "Worker"
        case .accountant: return "Accountant"
        case .admin:      return "Administrator"
        case .owner:      return "Owner"
        case .menager:    return "Manager"
        }
    }
}

// MARK: - Shared helper types (used by both iPad and iPhone views)

struct MainWindowPage: Identifiable {
    let id   = UUID()
    let title: String
    let url:   URL
}

struct MainWindowWebScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var push = PushState.shared

    let title: String
    let url:   URL

    var body: some View {
        NavigationStack {
            WebView(
                url: url,
                apnsToken:         push.apnsToken,
                deviceId:          push.deviceId,
                biometricEnabled:  push.biometricEnabled,
                hasBiometricLogin: push.hasBiometricLogin,
                command: nil
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
