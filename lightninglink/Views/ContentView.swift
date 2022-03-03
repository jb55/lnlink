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

    case pay(DecodeType, String)
}

public enum ActiveSheet: Identifiable {
    public var id: String {
        switch self {
        case .qr:
            return "qrcode"
        case .pay:
            return "paysheet"
        }
    }

    case qr
    case pay(DecodeType, String)
}

struct Funds {
    public var onchain_sats: Int64
    public var channel_sats: Int64

    public static var empty = Funds(onchain_sats: 0, channel_sats: 0)

    public static func from_listfunds(fs: ListFunds) -> Funds {
        var onchain_sats: Int64 = 0
        var channel_sats: Int64 = 0

        let channels = fs.channels ?? []
        let outputs = fs.outputs ?? []

        for channel in channels {
            channel_sats += channel.channel_sat
        }

        for output in outputs {
            onchain_sats += output.value
        }

        return Funds(onchain_sats: onchain_sats, channel_sats: channel_sats)
    }
}

let SCAN_TYPES: [AVMetadataObject.ObjectType] = [.qr]

struct ContentView: View {
    @State private var active_sheet: ActiveSheet?
    @State private var active_alert: ActiveAlert?
    @State private var has_alert: Bool
    @State private var last_pay: Pay?
    @State private var dashboard: Dashboard
    @State private var funds: Funds
    @State private var is_reset: Bool = false

    private var lnlink: LNLink

    init(dashboard: Dashboard, lnlink: LNLink) {
        self.dashboard = dashboard
        self.lnlink = lnlink
        self.has_alert = false
        self.funds = Funds.from_listfunds(fs: dashboard.funds)
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

    func main_content() -> some View {
        VStack {
            VStack {
            HStack {
                VStack {
                Text(self.dashboard.info.alias)
                    .font(.title)
                }

                Spacer()

                Button("Reset") {
                    reset_lnlink()
                    self.is_reset = true
                }
            }

            HStack {
                Text("\(self.dashboard.info.msatoshi_fees_collected / 1000) sats earned")
                    .font(.footnote)
                    .foregroundColor(.gray)

                Spacer()
            }
            }
            .padding()

            Spacer()
            Text("\(format_last_pay())")
                .foregroundColor(Color.red)

            Text("\(self.funds.channel_sats) sats")
                .font(.title)
                .padding()

            if self.funds.onchain_sats != 0 {
                Text("\(self.funds.onchain_sats) onchain")
                    .foregroundColor(.gray)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Pay", action: check_pay)
                .font(.title)
                .buttonStyle(.bordered)
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
                        let m_parsed = parseInvoiceString(invstr)
                        guard let parsed = m_parsed else {
                            return
                        }
                        self.active_sheet = .pay(parsed, invstr)

                    case .failure:
                        self.active_sheet = nil
                        return
                    }

                }

            case .pay(let decode_type, let raw):
                PayView(invoice_str: raw, decode_type: decode_type, lnlink: self.lnlink)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sentPayment)) { payment in
            last_pay = payment.object as! Pay
            self.active_sheet = nil
            refresh_funds()
        }

    }

    var body: some View {
        if is_reset {
            SetupView()
        } else {
            main_content()
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


func get_clipboard_invoice() -> (DecodeType, String)? {
    guard let inv = UIPasteboard.general.string else {
        return nil
    }

    guard let amt = parseInvoiceString(inv) else {
        return nil
    }

    return (amt, inv)
}
