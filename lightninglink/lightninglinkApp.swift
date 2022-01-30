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

    init() {
        let ln = LNSocket()
        self.info = ln.testrun() ?? .empty
    }

    var body: some Scene {
        WindowGroup {
            ContentView(info: self.info)
        }
    }
}
