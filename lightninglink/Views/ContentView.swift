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

    static var reset: Notification.Name {
        return Notification.Name("reset lnlink")
    }

    static var donate: Notification.Name {
        return Notification.Name("donate")
    }
}

enum ActiveAlert: Identifiable {
    var id: String {
        switch self {
        case .pay:
            return "pay"
        }
    }

    case pay(LNScanResult)
}

public enum ActiveSheet: Identifiable {
    public var id: String {
        switch self {
        case .receive:
            return "receive"
        case .qr:
            return "qrcode"
        case .pay:
            return "paysheet"
        }
    }

    case qr
    case receive
    case pay(DecodeType)
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
    @State private var active_sheet: ActiveSheet? = nil
    @State private var active_alert: ActiveAlert? = nil
    @State private var has_alert: Bool = false
    @State private var last_pay: Pay?
    @State private var funds: Funds = .empty
    @State private var is_reset: Bool = false
    @State private var scan_invoice: String? = nil
    @State private var rate: ExchangeRate?

    private let dashboard: Dashboard
    private let lnlink: LNLink
    private let init_scan_invoice: String?

    init(dashboard: Dashboard, lnlink: LNLink, scan_invoice: String?) {
        self.dashboard = dashboard
        self.init_scan_invoice = scan_invoice
        self.lnlink = lnlink
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

        let fee = pay.msatoshi_sent - pay.msatoshi
        return "-\(render_amount_msats(pay.msatoshi)) (\(render_amount_msats(fee)) fee)"
    }

    func receive_pay() {
        self.active_sheet = .receive
    }

    func check_pay() {
        guard let decode = get_clipboard_invoice() else {
            self.active_sheet = .qr
            self.has_alert = false
            return
        }

        self.active_sheet = nil
        self.active_alert = .pay(decode)
        self.has_alert = true
    }

    func main_content() -> some View {
        NavigationView {
        VStack {
            VStack {
                HStack {
                    VStack {
                    Text(self.dashboard.info.alias)
                        .font(.title)
                    }

                    Spacer()

                    NavigationLink(destination: SettingsView()) {
                        Label("", systemImage: "gear")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }

                HStack {
                    Text("\(self.dashboard.info.msatoshi_fees_collected / 1000) sats earned")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    Spacer()
                }
            }

            Spacer()
            Text("\(format_last_pay())")
                .foregroundColor(Color.red)

            amount_view(self.funds.channel_sats * 1000, rate: self.rate)

            if self.funds.onchain_sats != 0 {
                Text("\(self.funds.onchain_sats) onchain")
                    .foregroundColor(.gray)
            }

            Spacer()

            HStack {
                Button(action: receive_pay) {
                    Label("", systemImage: "arrow.down.circle")
                }
                .font(.largeTitle)

                Spacer()

                Button(action: check_pay) {
                    Label("", systemImage: "qrcode.viewfinder")
                }
                .font(.largeTitle)
            }
        }
        .padding()
        .alert("Use invoice in clipboard?", isPresented: $has_alert, presenting: active_alert) { alert in
            Button("Use QR") {
                self.has_alert = false
                self.active_sheet = .qr
            }
            Button("Yes") {
                self.has_alert = false
                self.active_alert = nil
                switch alert {
                case .pay(let scanres):
                    handle_scan_result(scanres)
                }
            }
        }
        .sheet(item: $active_sheet) { sheet in
            switch sheet {
            case .qr:
                CodeScannerView(codeTypes: SCAN_TYPES) { res in
                    switch res {
                    case .success(let scan_res):
                        handle_scan(scan_res.string)

                    case .failure:
                        self.active_sheet = nil
                        return
                    }

                }

            case .receive:
                ReceiveView(rate: $rate, lnlink: lnlink)

            case .pay(let decode):
                PayView(decode: decode, lnlink: self.lnlink, rate: self.rate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sentPayment)) { payment in
            last_pay = payment.object as? Pay
            self.active_sheet = nil
            refresh_funds()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reset)) { _ in
            self.is_reset = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .donate)) { _ in
            let offer: DecodeType = .offer("lno1pfsycnjvd9hxkgrfwvsxvun9v5s8xmmxw3mkzun9yysyyateypkk2grpyrcflrd6ypek7gzfyp3kzm3qvdhkuarfde6k2grd0ysxzmrrda5x7mrfwdkj6en4v4kx2epqvdhkg6twvusxzerkv4h8gatjv4eju9q2d3hxc6twdvhxzursrcs08sggen2ndwzjdpqlpfw9sgfth8n9sjs7kjfssrnurnp5lqk66u0sgr32zxwrh0kmxnvmt5hyn0my534209573mp9ck5ekvywvugm5x3kq8ztex8yumafeft0arh6dke04jqgckmdzekqxegxzhecl23lurrj")
            self.active_sheet = .pay(offer)
        }
        .onOpenURL() { url in
            handle_scan(url.absoluteString)
        }
        .onAppear() {
            get_exchange_rate(for_cur: .USD) {
                self.rate = $0
            }
            refresh_funds()
            if init_scan_invoice != nil {
                handle_scan(init_scan_invoice!)
                scan_invoice = nil
            }
        }
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarHidden(true)

        }

    }

    func handle_scan_result(_ scanres: LNScanResult) {
        switch scanres {
        case .lightning(let decode):
            self.active_sheet = .pay(decode)
        case .lnlink:
            print("got a lnlink, not an invoice")
            // TODO: report that this is an lnlink, not an invoice
        case .lnurl(let lnurl):
            let decode: DecodeType = .lnurl(lnurl)
            self.active_sheet = .pay(decode)
        }
    }

    func handle_scan(_ str: String) {
        switch handle_qrcode(str) {
        case .left(let err):
            print("scan error: \(err)")
        case .right(let scanres):
            handle_scan_result(scanres)
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


func get_clipboard_invoice() -> LNScanResult? {
    guard let inv = UIPasteboard.general.string else {
        return nil
    }

    switch handle_qrcode(inv) {
    case .left:
        return nil
    case .right(let scanres):
        return scanres
    }
}
