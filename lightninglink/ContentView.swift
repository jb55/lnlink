//
//  ContentView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

import SwiftUI

struct ContentView: View {
    @State private var info: GetInfo

    init(info: GetInfo) {
        self.info = info
    }

    var body: some View {
        let _self = self
        VStack {
            Text(self.info.alias)
            Text("\(self.info.num_active_channels) active channels")
            Text("\(self.info.msatoshi_fees_collected / 1000) sats collected in fees")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(info: .empty)
        }
    }
}
