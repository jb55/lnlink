//
//  PayView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import SwiftUI
import Combine

public struct Offer {
    let offer: String
    let amount: InvoiceAmount
    let decoded: InvoiceDecode
}

public struct Invoice {
    let invstr: String
    let amount: InvoiceAmount
}

public enum ReadyInvoice {
    case requested(RequestInvoice)
    case direct(Invoice)

    func amount() -> InvoiceAmount {
        switch self {
        case .direct(let inv):
            return inv.amount
        case .requested(let invreq):
            return invreq.amount()
        }
    }
}

public enum RequestInvoice {
    case lnurl(LNUrlPay)
    case offer(Offer)

    func amount() -> InvoiceAmount {
        switch self {
        case .lnurl(let lnurlp):
            return lnurl_pay_invoice_amount(lnurlp)
        case .offer(let offer):
            return offer.amount
        }
    }
}

public struct PayAmount {
    let tip: Int64?
    let amount: Int64

    func total() -> Int64 {
        return amount + (tip ?? 0)
    }
}

public struct FetchInvoiceReq {
    let offer: String
    let pay_amt: PayAmount?
    let amount: InvoiceAmount
    let quantity: Int?
    let timeout: Int?
}

public enum TipSelection {
    case none
    case fifteen
    case twenty
    case twenty_five
}

public enum PayState {
    case initial
    case decoding(LNSocket?, DecodeType)
    case decoded(DecodeType)
    case ready(Invoice)
    case invoice_request(RequestInvoice)
}

struct PayView: View {
    let init_decode_type: DecodeType
    let lnlink: LNLink

    let expiry_timer = Timer.publish(every: 1, on: .main, in: .default).autoconnect()

    @State var pay_result: Pay?
    @State var state: PayState = .initial
    @State var invoice: Decode?
    @State var error: String?
    @State var expiry_percent: Double?
    @State var custom_amount_input: String = ""
    @State var custom_amount_msats: Int64 = 0
    @State var current_tip: TipSelection = .none
    @State var paying: Bool = false

    @Environment(\.presentationMode) var presentationMode

    init(decode: DecodeType, lnlink: LNLink) {
        self.init_decode_type = decode
        self.lnlink = lnlink
    }

    var successView: some View {
        VStack() {
            Text("Payment Success!").font(.largeTitle)
        }
    }

    var failView: some View {
        VStack() {
            Text("Payment Failed").font(.largeTitle)
            Text(self.error!)
        }
    }

    private func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }

    var body: some View {
        MainView()
    }

    func progress_color() -> Color {
        guard let perc = expiry_percent else {
            return Color.green
        }

        if perc < 0.25 {
            return Color.red
        } else if perc < 0.5 {
            return Color.yellow
        }

        return Color.green
    }

    func MainView() -> some View {
        return VStack {
            Text("Confirm Payment")
                .font(.largeTitle)
                .padding()

            if self.expiry_percent != nil {
                ProgressView(value: self.expiry_percent! * 100, total: 100)
                    .accentColor(progress_color())
            }

            if self.invoice != nil {
                let invoice = self.invoice!
                if invoice.description() != nil {
                    Text(invoice.description()!)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                if invoice.vendor() != nil {
                    Text(invoice.vendor()!)
                        .font(.callout)
                        .foregroundColor(.gray)
                }
            }

            if self.invoice != nil && self.invoice!.thumbnail() != nil {
                self.invoice!.thumbnail()!
                    .resizable()
                    .frame(width: 128, height: 128, alignment: .center)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 4))
                    .padding()
            }

            Spacer()

            // Middle area
            let ready_invoice = is_ready(state)
            if ready_invoice != nil {
                amount_view_inv(ready_invoice!.amount())
            }

            Text("\(self.error ?? "")")
                .foregroundColor(Color.red)

            if self.should_show_progress() {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            Spacer()

            // Bottom area
            if !self.paying {
                HStack {
                    Button("Cancel") {
                        self.dismiss()
                    }
                    .foregroundColor(Color.red)
                    .font(.title)

                    Spacer()
                    if should_show_confirmation(ready_invoice?.amount()) {
                        Button("Confirm") {
                            handle_confirm(ln: nil)
                        }
                        .foregroundColor(Color.green)
                        .font(.title)
                    }
                }
            }
        }
        .padding()
        .onAppear() {
            handle_state_change()
        }
        .onReceive(self.expiry_timer) { _ in
            update_expiry_percent()
        }
    }

    func should_show_confirmation(_ amt: InvoiceAmount?) -> Bool {
        if amt != nil && is_any_amount(amt!) && self.custom_amount_msats == 0 {
            return false
        }
        return should_show_confirm(self.state)
    }

    func should_show_progress() -> Bool {
        return self.paying || (self.error == nil && is_ready(self.state) == nil)
    }

    func handle_custom_receive(_ new_val: String) {
        if new_val == "" {
            self.custom_amount_input = ""
            return
        }

        let ok = new_val.allSatisfy { $0 == "," || ($0 >= "0" && $0 <= "9") }
        if ok {
            let num_fmt = NumberFormatter()
            num_fmt.numberStyle = .decimal

            let filtered = new_val.filter { $0 >= "0" && $0 <= "9" }
            let sats = Int64(filtered) ?? 0
            let msats = sats * 1000
            self.custom_amount_input = num_fmt.string(from: NSNumber(value: sats)) ?? new_val
            self.custom_amount_msats = msats
        }
    }

    func tip_percent(_ tip: TipSelection) {
        if tip == self.current_tip {
            self.current_tip = .none
            self.custom_amount_msats = 0
            return
        }

        self.current_tip = tip
        let percent = tip_value(tip)

        if tip == .none {
            self.custom_amount_msats = 0
            return
        }
        guard let invoice = self.invoice else {
            return
        }
        guard let amount_msat_str = invoice.amount_msat() else {
            return
        }
        guard let amount_msat = parse_msat(amount_msat_str) else {
            return
        }

        self.custom_amount_msats = Int64((Double(amount_msat) * percent))
    }

    func tip_view() -> some View {
        Group {
            Text("Tip?")
            HStack {
                let unsel_c: Color = .primary
                let sel_c: Color = .blue

                Button("15%") {
                    tip_percent(.fifteen)
                }
                .buttonStyle(.bordered)
                .foregroundColor(current_tip == .fifteen ? sel_c: unsel_c)

                Button("20%") {
                    tip_percent(.twenty)
                }
                .buttonStyle(.bordered)
                .foregroundColor(current_tip == .twenty ? sel_c: unsel_c)

                Button("25%") {
                    tip_percent(.twenty_five)
                }
                .buttonStyle(.bordered)
                .foregroundColor(current_tip == .twenty_five ? sel_c: unsel_c)
            }
            .padding()
        }
    }

    func amount_view_inv(_ amt: InvoiceAmount) -> some View {
        Group {
            if self.paying {
                Text("Paying...")
            } else {
                Text("Pay")
            }

            switch amt {
            case .min(let min_amt):
                Text("\(render_amount_msats(min_amt + self.custom_amount_msats))")
                    .font(.title)
                Text("\(render_amount_msats(self.custom_amount_msats)) tipped")
                    .font(.callout)
                    .foregroundColor(.gray)
                if !self.paying {
                    Spacer()
                    tip_view()
                }

            case .range(let min_amt, let max_amt):
                if self.paying {
                    let amt = self.custom_amount_msats
                    Text("\(render_amount_msats(amt))")
                        .font(.title)
                } else {
                    InputView {
                        handle_custom_receive($0)
                        if self.custom_amount_input != "" {
                            if self.custom_amount_msats < min_amt {
                                self.error = "Amount not allowed, must be higher than \(render_amount_msats(min_amt))"
                            } else if self.custom_amount_msats > max_amt {
                                self.error = "Amount not allowed, must be lower than \(render_amount_msats(max_amt))"
                            } else {
                                if self.error != nil && self.error!.starts(with: "Amount not allowed") {
                                    self.error = nil
                                }
                            }
                        }
                    }
                }

            case .any:
                if self.paying {
                    let amt = self.custom_amount_msats
                    Text("\(render_amount_msats(amt))")
                        .font(.title)
                } else {
                    InputView {
                        handle_custom_receive($0)
                    }
                }

            case .amount(let amt):
                Text("\(render_amount_msats(amt))")
                    .font(.title)
            }
        }
    }

    func InputView(onReceive: @escaping (String) -> ()) -> some View {
        // TODO remove from class, pass input binding?
        return Form {
            Section {
                HStack(alignment: .lastTextBaseline) {
                    TextField("10,000", text: $custom_amount_input)
                        .font(.title)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onReceive(Just(self.custom_amount_input)) {
                            onReceive($0)
                        }
                    Text("sats")
                }
            }
        }
        .frame(height: 100)
    }

    func confirm_pay(ln: LNSocket?, inv: String, pay_amt: PayAmount?) {
        let res = confirm_payment(ln: ln, lnlink: self.lnlink, bolt11: inv, pay_amt: pay_amt)
        switch res {
        case .left(let err):
            self.paying = false
            self.error = err

        case .right(let pay):
            print(pay)
            DispatchQueue.main.async {
                self.dismiss()
                NotificationCenter.default.post(name: .sentPayment, object: pay)
            }
        }
    }

    func get_pay_amount(_ amt: InvoiceAmount) -> PayAmount? {
        return get_pay_amount_from_input(amt, input_amount: self.custom_amount_msats)
    }

    func handle_confirm_lnurl(ln mln: LNSocket?, lnurlp: LNUrlPay) {
        let lnurl_amt = lnurl_pay_invoice_amount(lnurlp)
        guard let pay_amt = get_pay_amount(lnurl_amt) else {
            self.error = "Invalid payment amount for lnurl"
            return
        }
        self.paying = true

        lnurl_fetchinvoice(lnurlp: lnurlp, amount: pay_amt.amount) {
            switch $0 {
            case .left(let err):
                self.error = err.reason
                self.paying = false
            case .right(let lnurl_invoice):
                guard let ret_inv = parseInvoiceString(lnurl_invoice.pr) else {
                    self.error = "Invalid lnurl invoice"
                    self.paying = false
                    return
                }
                switch ret_inv {
                case .invoice(let amt, let invstr):
                    if !pay_amount_matches(pay_amt: pay_amt, invoice_amount: amt) {
                        self.error = "Returned lnurl invoice doesn't match expected amount"
                        self.paying = false
                        return
                    }

                    DispatchQueue.global(qos: .background).async {
                        confirm_pay(ln: mln, inv: invstr, pay_amt: nil)
                    }
                case .offer:
                    self.error = "Got an offer from a lnurl pay request? What?"
                    self.paying = false
                    return
                case .lnurl:
                    self.error = "Got another lnurl from an lnurl pay request? What?"
                    self.paying = false
                    return
                }
            }
        }
    }

    func handle_confirm_offer(ln mln: LNSocket?, offer: Offer) {
        guard let pay_amt = get_pay_amount(offer.amount) else {
            self.error = "Expected payment amount for bolt12"
            return
        }
        let req = fetchinvoice_req_from_offer(
            offer: offer.decoded,
            offer_str: offer.offer,
            pay_amt: pay_amt)
        switch req {
        case .left(let err):
            self.error = err
        case .right(let req):
            let token = self.lnlink.token
            self.paying = true
            DispatchQueue.global(qos: .background).async {
                let ln = mln ?? LNSocket()
                if mln == nil {
                    guard ln.connect_and_init(node_id: self.lnlink.node_id, host: self.lnlink.host) else {
                        self.paying = false
                        self.error = "Connection failed when fetching invoice"
                        return
                    }
                }
                switch rpc_fetchinvoice(ln: ln, token: token, req: req) {
                case .failure(let err):
                    self.paying = false
                    self.error = err.description
                case .success(let fetch_invoice):
                    confirm_pay(ln: ln, inv: fetch_invoice.invoice, pay_amt: nil)
                }
            }
        }
    }

    func handle_confirm(ln mln: LNSocket?) {
        switch self.state {
        case .invoice_request(let reqinv):
            switch reqinv {
            case .offer(let offer):
                return handle_confirm_offer(ln: mln, offer: offer)
            case .lnurl(let lnurlp):
                return handle_confirm_lnurl(ln: mln, lnurlp: lnurlp)
            }

        case .ready(let invoice):
            let pay_amt = get_pay_amount(invoice.amount)
            self.paying = true
            DispatchQueue.global(qos: .background).async {
                confirm_pay(ln: mln, inv: invoice.invstr, pay_amt: pay_amt)
            }

        case .initial: fallthrough
        case .decoding: fallthrough
        case .decoded:
            self.error = "Invalid state: \(self.state)"
        }
    }

    func is_tip_selected(_ tip: TipSelection) -> Bool {
        return tip == self.current_tip
    }

    func switch_state(_ state: PayState) {
        self.state = state
        handle_state_change()
    }

    func handle_state_change() {
            switch self.state {
            case .ready:
                break
            case .invoice_request:
                break
            case .initial:
                switch_state(.decoding(nil, self.init_decode_type))
            case .decoding(let ln, let decode):
                DispatchQueue.global(qos: .background).async {
                    self.handle_decode(ln, decode: decode)
                }
            case .decoded:
                break
            }

    }

    func handle_offer(ln: LNSocket, decoded: InvoiceDecode, inv: String) {
        switch handle_bolt12_offer(ln: ln, decoded: decoded, inv: inv) {
        case .right(let state):
            self.invoice = .invoice(decoded)
            switch_state(state)
        case .left(let err):
            self.error = err
        }
    }

    func handle_lnurl_payview(ln: LNSocket?, lnurlp: LNUrlPay) {
        let decode = decode_lnurlp_metadata(lnurlp)
        self.invoice = .lnurlp(decode)

        switch_state(.invoice_request(.lnurl(lnurlp)))
    }

    func handle_decode(_ oldln: LNSocket?, decode: DecodeType) {
        let ln = oldln ?? LNSocket()
        if oldln == nil {
            guard ln.connect_and_init(node_id: self.lnlink.node_id, host: self.lnlink.host) else {
                return
            }
        }

        var inv = ""
        switch decode {
        case .offer(let s):
            inv = s
        case .invoice(_, let s):
            inv = s
        case .lnurl(let lnurl):
            handle_lnurl(lnurl) { lnurl in
                switch lnurl {
                case .payRequest(let pay):
                    self.handle_lnurl_payview(ln: ln, lnurlp: pay)
                    return
                case .none:
                    self.error = "Invalid lnurl"
                }
            }
            return
        }

        switch rpc_decode(ln: ln, token: self.lnlink.token, inv: inv) {
        case .failure(let fail):
            self.error = fail.description
        case .success(let decoded):
            if decoded.type == "bolt12 offer" {
                self.handle_offer(ln: ln, decoded: decoded, inv: inv)

            } else if decoded.type == "bolt11 invoice" || decoded.type == "bolt12 invoice" {
                var amount: InvoiceAmount = .any
                if decoded.amount_msat != nil {
                    guard let amt = parse_msat(decoded.amount_msat!) else {
                        self.error = "invalid msat amount: \(decoded.amount_msat!)"
                        return
                    }

                    amount = .amount(amt)
                }

                self.state = .ready(Invoice(invstr: inv, amount: amount))
                self.invoice = .invoice(decoded)
                update_expiry_percent()
            } else {
                self.error = "unknown decoded type: \(decoded.type)"
            }
        }

    }

    func update_expiry_percent() {
        if case let .invoice(invoice) = self.invoice {
            guard let expiry = get_decode_expiry(invoice) else {
                self.expiry_percent = nil
                return
            }

            guard let created_at = invoice.created_at else {
                self.expiry_percent = nil
                return
            }

            let now = Int64(Date().timeIntervalSince1970)
            let expires_at = created_at + expiry

            guard expiry > 0 else {
                self.expiry_percent = nil
                return
            }

            guard now < expires_at else {
                self.error = "Invoice expired"
                self.expiry_percent = nil
                return
            }

            guard now >= created_at else {
                self.expiry_percent = 1
                return
            }

            let prog = now - created_at
            self.expiry_percent = 1.0 - (Double(prog) / Double(expiry))
        }


    }
}

func fetchinvoice_req_from_offer(offer: InvoiceDecode, offer_str: String, pay_amt: PayAmount) -> Either<String, FetchInvoiceReq> {

    var qty: Int? = nil
    if offer.quantity_min != nil {
        qty = offer.quantity_min!
    }

    // TODO: should we wait longer to fetch an invoice??
    let timeout = 10

    if offer.amount_msat != nil {
        return .right(.init(
            offer: offer_str,
            pay_amt: pay_amt,
            amount: .any,
            quantity: qty,
            timeout: timeout
        ))
    } else {
        let amount: InvoiceAmount = .amount(pay_amt.amount)
        return .right(.init(
            offer: offer_str,
            pay_amt: pay_amt,
            amount: amount,
            quantity: qty,
            timeout: timeout
        ))
    }
}

func parse_msat(_ s: String) -> Int64? {
    let str = s.replacingOccurrences(of: "msat", with: "")
    return Int64(str)
}

public enum Either<L, R> {
    case left(L)
    case right(R)

    func mapError<L2>(mapper: (L) -> L2) -> Either<L2, R> {
        switch self {
        case .left(let l1):
            return .left(mapper(l1))
        case .right(let r):
            return .right(r)
        }
    }
}

func confirm_payment(ln mln: LNSocket?, lnlink: LNLink, bolt11: String, pay_amt: PayAmount?) -> Either<String, Pay> {
    let ln = mln ?? LNSocket()

    if mln == nil {
        guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
            return .left("Failed to connect, please try again!")
        }
    }

    var amount_msat: Int64? = nil
    if pay_amt != nil {
        amount_msat = pay_amt!.amount + (pay_amt!.tip ?? 0)
    }

    let res = rpc_pay(
        ln: ln,
        token: lnlink.token,
        bolt11: bolt11,
        amount_msat: amount_msat)

    switch res {
    case .failure(let req_err):
        // handle error
        let errmsg = req_err.description
        return .left(errmsg)

    case .success(let pay):
        return .right(pay)
    }
}

func is_ready(_ state: PayState) -> ReadyInvoice? {
    switch state {
    case .ready(let invoice):
        return .direct(invoice)
    case .invoice_request(let invreq):
        return .requested(invreq)
    case .initial: fallthrough
    case .decoding: fallthrough
    case .decoded:
        return nil
    }
}


func render_amount(_ amt: InvoiceAmount) -> String {
    switch amt {
    case .any:
        return "Enter amount"
    case .range(let min_amt, let max_amt):
        return "\(render_amount_msats(min_amt)) to \(render_amount_msats(max_amt))"
    case .amount(let amt):
        return "\(render_amount_msats(amt))?"
    case .min(let min):
        return "\(render_amount_msats(min))?"
    }
}

func render_amount_msats(_ amount: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal

    if amount < 1000 {
        let amt_str = formatter.string(from: NSNumber(value: amount))!
        return "\(amt_str) msats"
    }

    let amt_str = formatter.string(from: NSNumber(value: amount / 1000))!
    return "\(amt_str) sats"
}

/*
struct PayView_Previews: PreviewProvider {
    @Binding var invoice: Invoice?

    static var previews: some View {
        PayView(invoice: self.$invoice)
    }
}
*/

func handle_bolt12_offer(ln: LNSocket, decoded: InvoiceDecode, inv: String) -> Either<String, PayState> {
    if decoded.amount_msat != nil {
        guard let min_amt = parse_msat(decoded.amount_msat!) else {
            return .left("Error parsing amount_msat: '\(decoded.amount_msat!)'")
        }
        let offer = Offer(offer: inv, amount: .min(min_amt), decoded: decoded)
        return .right(.invoice_request(.offer(offer)))
    } else {
        let offer = Offer(offer: inv, amount: .any, decoded: decoded)
        return .right(.invoice_request(.offer(offer)))
    }
}


func should_show_confirm(_ state: PayState) -> Bool {
    switch state {
    case .ready: fallthrough
    case .invoice_request:
        return true

    case .decoded: fallthrough
    case .initial: fallthrough
    case .decoding:
        return false
    }
}


func tip_value(_ tip: TipSelection) -> Double {
    switch tip {
    case .none: return 0
    case .fifteen: return 0.15
    case .twenty: return 0.2
    case .twenty_five: return 0.25
    }
}

func is_any_amount(_ amt: InvoiceAmount) -> Bool {
    switch amt {
    case .any:
        return true
    default:
        return false
    }
}

func lnurl_pay_invoice_amount(_ lnurlp: LNUrlPay) -> InvoiceAmount {
    let min_amt = Int64(lnurlp.minSendable ?? 1)
    let max_amt = Int64(lnurlp.maxSendable ?? 2100000000000000000)
    return .range(min_amt, max_amt)
}

func get_pay_amount_from_input(_ amt: InvoiceAmount, input_amount: Int64) -> PayAmount? {
    switch amt {
    case .min(let min_amt):
        return PayAmount(tip: input_amount, amount: min_amt)
    case .range:
        return PayAmount(tip: 0, amount: input_amount)
    case .any:
        return PayAmount(tip: 0, amount: input_amount)
    case .amount:
        return nil
    }
}


func pay_amount_matches(pay_amt: PayAmount, invoice_amount: InvoiceAmount) -> Bool
{
    switch invoice_amount {
    case .amount(let amt):
        if pay_amt.total() == amt {
            return true
        }
    case .range(let min_amt, let max_amt):
        if pay_amt.total() < min_amt {
            return false
        }

        if pay_amt.total() > max_amt {
            return false
        }

        return true
    case .min(let min):
        if pay_amt.total() < min {
            return false
        }

        return true

    case .any:

        return true
    }

    return false
}

