//
//  ContentView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

import SwiftUI
import AVFoundation

extension Notification.Name {
    static var sentPayment: Notification.Name {
        return Notification.Name("did send payment")
    }
}

enum ActiveAlert: Identifiable {
    var id: String {
        switch self {
        case .pay:
            return "pay"
        }
    }

    case pay(InvoiceAmount, String)
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
    case pay(InvoiceAmount, String)
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

let SCAN_TYPES: [AVMetadataObject.ObjectType] = [.qr]

struct ContentView: View {
    @State private var info: GetInfo
    @State private var active_sheet: ActiveSheet?
    @State private var active_alert: ActiveAlert?
    @State private var has_alert: Bool
    @State private var last_pay: Pay?
    @State private var funds: Funds

    private var lnlink: LNLink

    init(info: GetInfo, lnlink: LNLink, funds: ListFunds) {
        self.info = info
        self.lnlink = lnlink
        self.has_alert = false
        self.funds = Funds.from_listfunds(fs: funds)
    }

    func refresh_funds() {
        let ln = LNSocket()
        guard ln.connect_and_init(node_id: self.lnlink.node_id, host: self.lnlink.host) else {
            return
        }
        let funds = fetch_funds(ln: ln, token: lnlink.token)
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

    func check_pay() {
        guard let (amt, inv) = get_clipboard_invoice() else {
            self.active_sheet = .qr
            self.has_alert = false
            return
        }

        self.active_sheet = nil
        self.active_alert = .pay(amt, inv)
        self.has_alert = true
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
                Button("Pay", action: check_pay)
                .font(.title)
                .padding()
            }
        }
        .alert("Use invoice in clipboard?", isPresented: $has_alert, presenting: active_alert) { alert in
            Button("Use QR") {
                self.has_alert = false
                self.active_sheet = .qr
            }
            Button("Yes") {
                self.has_alert = false
                self.active_alert = nil
                switch alert {
                case .pay(let amt, let inv):
                    self.active_sheet = .pay(amt, inv)
                }
            }
        }
        .sheet(item: $active_sheet) { sheet in
            switch sheet {
            case .qr:
                CodeScannerView(codeTypes: SCAN_TYPES) { res in
                    switch res {
                    case .success(let scan_res):
                        let code = scan_res.string
                        var invstr: String = code
                        if code.starts(with: "lightning:") {
                            let index = code.index(code.startIndex, offsetBy: 10)
                            invstr = String(code[index...])
                        }
                        let m_parsed = parseInvoiceAmount(invstr)
                        guard let parsed = m_parsed else {
                            return
                        }
                        self.active_sheet = .pay(parsed, invstr)

                    case .failure:
                        self.active_sheet = nil
                        return
                    }

                }

            case .pay(let amt, let raw):
                PayView(invoice_str: raw, amount: amt, lnlink: self.lnlink)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sentPayment)) { payment in
            last_pay = payment.object as! Pay
            self.active_sheet = nil
            refresh_funds()
        }
    }
}

/*
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(info: .empty, lnlink: ln, token: "", funds: .empty)
        }
    }
}
 */


func get_clipboard_invoice() -> (InvoiceAmount, String)? {
    guard let inv = UIPasteboard.general.string else {
        return nil
    }

    guard let amt = parseInvoiceAmount(inv) else {
        return nil
    }

    return (amt, inv)
}
