//
//  lightninglinkApp.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

import SwiftUI

@main
struct lightninglinkApp: App {
    var info: GetInfo = .empty
    var funds: ListFunds = .empty
    var lnlink: LNLink

    init() {
        self.ln = LNSocket()
        self.token = ""
        let node_id = "03f3c108ccd536b8526841f0a5c58212bb9e6584a1eb493080e7c1cc34f82dad71"
        let host = "24.84.152.187"
        let lnlink = LNLink(token: token, host: host, node_id: node_id)
        self.lnlink = lnlink

        guard ln.connect_and_init(node_id: node_id, host: host) else {
            return
        }

        self.info = fetch_info(ln: ln, token: token)
        self.funds = fetch_funds(ln: ln, token: token)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(info: self.info, lnlink: self.lnlink, funds: self.funds)
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
