//
//  ContentView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

import SwiftUI

extension Notification.Name {
    static var sentPayment: Notification.Name {
        return Notification.Name("did send payment")
    }
}

enum ActiveSheet: Identifiable {
    var id: String {
        switch self {
        case .qr:
            return "qrcode"
        case .pay:
            return "paysheet"
        }
    }

    case qr
    case pay(Invoice, String)
}

struct Funds {
    public var onchain_sats: Int64
    public var channel_sats: Int64

    public static var empty = Funds(onchain_sats: 0, channel_sats: 0)

    public static func from_listfunds(fs: ListFunds) -> Funds {
        var onchain_sats: Int64 = 0
        var channel_sats: Int64 = 0

        for channel in fs.channels {
            channel_sats += channel.channel_sat
        }

        for output in fs.outputs {
            onchain_sats += output.value
        }

        return Funds(onchain_sats: onchain_sats, channel_sats: channel_sats)
    }
}

struct ContentView: View {
    @State private var info: GetInfo
    @State private var activeSheet: ActiveSheet?
    @State private var last_pay: Pay?
    @State private var funds: Funds

    private var ln: LNSocket
    private var token: String

    init(info: GetInfo, ln: LNSocket, token: String, funds: ListFunds) {
        self.info = info
        self.ln = ln
        self.token = token
        self.funds = Funds.from_listfunds(fs: funds)
    }

    func refresh_funds() {
        let funds = fetch_funds(ln: self.ln, token: self.token)
        self.funds = Funds.from_listfunds(fs: funds)
    }

    func format_last_pay() -> String {
        guard let pay = last_pay else {
            return ""
        }

        if (pay.msatoshi >= 1000) {
            let sats = pay.msatoshi / 1000
            let fee = (pay.msatoshi_sent - pay.msatoshi) / 1000
            return "-\(sats) sats (\(fee) sats fee)"
        }

        return "-\(pay.msatoshi) msats (\(pay.msatoshi_sent) msats sent)"
    }

    var body: some View {
        VStack {
            Group {
                Text(self.info.alias)
                    .font(.largeTitle)
                    .padding()
                Text("\(self.info.num_active_channels) active channels")
                Text("\(self.info.msatoshi_fees_collected / 1000) sats collected in fees")
                }
            Spacer()
            Text("\(format_last_pay())")
                .foregroundColor(Color.red)

            Text("\(self.funds.channel_sats) sats")
                .font(.title)
                .padding()
            Text("\(self.funds.onchain_sats) onchain")
            Spacer()
            HStack {
                Spacer()
                Button("Pay",
                       action: { self.activeSheet = .qr })
                .font(.title)
                .padding()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .qr:
                QRScanner() { code in
                    var invstr: String = code
                    if code.starts(with: "lightning:") {
                        let index = code.index(code.startIndex, offsetBy: 10)
                        invstr = String(code[index...])
                    }
                    let m_parsed = parseInvoice(invstr)
                    guard let parsed = m_parsed else {
                        return
                    }
                    self.activeSheet = .pay(parsed, invstr)
                }

            case .pay(let inv, let raw):
                PayView(invoice_str: raw, invoice: inv, ln: self.ln, token: self.token)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:  .sentPayment)) { payment in
            last_pay = payment.object as! Pay
            refresh_funds()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let ln = LNSocket()
        Group {
            ContentView(info: .empty, ln: ln, token: "", funds: .empty)
        }
    }
}
