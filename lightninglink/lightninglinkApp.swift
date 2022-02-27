//
//  lightninglinkApp.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

import SwiftUI

public struct Dashboard {
    public let info: GetInfo
    public let funds: ListFunds

    public static var empty: Dashboard = Dashboard(info: .empty, funds: .empty)
}


func fetch_dashboard(lnlink: LNLink) -> Either<String, Dashboard> {
    let ln = LNSocket()

    guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
        return .left("Connect failed :(")
    }

    let res = rpc_getinfo(ln: ln, token: lnlink.token)
    switch res {
    case .failure(let res_err):
        return .left(res_err.decoded?.message ?? res_err.errorType.localizedDescription.debugDescription )
    case .success(let info):
        let res2 = rpc_listfunds(ln: ln, token: lnlink.token)
        switch res2 {
        case .failure(let err):
            return .left(err.decoded?.message ?? err.description)
        case .success(let funds):
            return .right(Dashboard(info: info, funds: funds))
        }
    }
}

@main
struct lightninglinkApp: App {
    @State var dashboard: Dashboard?
    @State var lnlink: LNLink? = load_lnlink()
    @State var error: String?

    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

func fetch_info(ln: LNSocket, token: String) -> GetInfo {
    switch rpc_getinfo(ln: ln, token: token) {
    case .failure(let err):
        print("fetch_info err: \(err)")
        return .empty

    case .success(let getinfo):
        return getinfo
    }
}

func fetch_funds(ln: LNSocket, token: String) -> ListFunds {
    switch rpc_listfunds(ln: ln, token: token) {
    case .failure(let err):
        print("fetch_funds error: \(err)")
        return .empty
    case .success(let funds):
        return funds
    }
}

func save_lnlink(lnlink: LNLink) {
    UserDefaults.standard.set(lnlink.token, forKey: "lnlink_token")
    UserDefaults.standard.set(lnlink.node_id, forKey: "lnlink_nodeid")
    UserDefaults.standard.set(lnlink.host, forKey: "lnlink_host")
}

func reset_lnlink() {
    UserDefaults.standard.removeObject(forKey: "lnlink_token")
    UserDefaults.standard.removeObject(forKey: "lnlink_nodeid")
    UserDefaults.standard.removeObject(forKey: "lnlink_host")
}

func load_lnlink() -> LNLink? {
    let m_token = UserDefaults.standard.string(forKey: "lnlink_token")
    let m_nodeid = UserDefaults.standard.string(forKey: "lnlink_nodeid")
    let m_host = UserDefaults.standard.string(forKey: "lnlink_host")

    guard let token = m_token else { return nil }
    guard let node_id = m_nodeid else { return nil }
    guard let host = m_host else { return nil }

    return LNLink(token: token, host: host, node_id: node_id)
}
