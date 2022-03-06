//
//  PayView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import SwiftUI
import Combine

public struct ReadyInvoice {
    let invoice: String
    let amount: InvoiceAmount
}

public struct PayAmount {
    let tip: Int64?
    let amount: Int64
}

public struct FetchInvoiceReq {
    let offer: String
    let pay_amt: PayAmount?
    let amount: InvoiceAmount
    let quantity: Int?
}

public enum TipSelection {
    case none
    case fifteen
    case twenty
    case twenty_five
}

public enum PayState {
    case initial
    case decoding(LNSocket?, String)
    case decoded(DecodeType)
    case ready(ReadyInvoice)
    case offer_input(ReadyInvoice, Decode)
}

struct PayView: View {
    let init_decode_type: DecodeType
    let lnlink: LNLink
    let init_invoice_str: String

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

    init(invoice_str: String, decode_type: DecodeType, lnlink: LNLink) {
        self.init_invoice_str = invoice_str
        self.init_decode_type = decode_type
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
        main_view()
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

    func main_view() -> some View {
        return VStack() {
            Text("Confirm Payment")
                .font(.largeTitle)
                .padding()

            if self.expiry_percent != nil {
                ProgressView(value: self.expiry_percent! * 100, total: 100)
                    .accentColor(progress_color())
            }

            if self.invoice != nil {
                let invoice = self.invoice!
                if invoice.description != nil {
                    Text(invoice.description!)
                        .padding()
                }

                if invoice.vendor != nil {
                    Text(invoice.vendor!)
                        .font(.callout)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Middle area
            let ready_invoice = is_ready(state)
            if ready_invoice != nil {
                amount_view_inv(ready_invoice!.amount)
            }
            Text("\(self.error ?? "")")
                .foregroundColor(Color.red)

            if self.paying {
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
                    if should_show_confirmation(ready_invoice?.amount) {
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

    func handle_custom_receive(_ new_val: String) {
        let ok = new_val.allSatisfy { $0 >= "0" && $0 <= "9" }
        if ok {
            self.custom_amount_input = new_val
            let msats = (Int64(new_val) ?? 0) * 1000
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
        guard let amount_msat_str = invoice.amount_msat else {
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

            case .any:
                if self.paying {
                    let amt = self.custom_amount_msats
                    Text("\(render_amount_msats(amt))")
                        .font(.title)
                } else {
                    Form {
                        Section {
                            HStack(alignment: .lastTextBaseline) {
                                TextField("100", text: $custom_amount_input)
                                    .font(.title)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .onReceive(Just(self.custom_amount_input)) {
                                        handle_custom_receive($0)
                                    }
                                Text("sats")
                            }
                        }
                    }
                    .frame(height: 100)
                }

            case .amount(let amt):
                Text("\(render_amount_msats(amt))")
                    .font(.title)
            }
        }
    }

    func confirm_pay(ln: LNSocket?, inv: String, pay_amt: PayAmount?) {
        let res = confirm_payment(ln: ln, lnlink: self.lnlink, bolt11: inv, pay_amt: pay_amt)
        switch res {
        case .left(let err):
            self.paying = false
            self.error = "Error: \(err)"

        case .right(let pay):
            print(pay)
            DispatchQueue.main.async {
                self.dismiss()
                NotificationCenter.default.post(name: .sentPayment, object: pay)
            }
        }
    }

    func get_pay_amount(_ amt: InvoiceAmount) -> PayAmount? {
        switch amt {
        case .min(let min_amt):
            let tip = self.custom_amount_msats
            return PayAmount(tip: tip, amount: min_amt)
        case .any:
            return PayAmount(tip: 0, amount: custom_amount_msats)
        case .amount:
            return nil
        }
    }

    func handle_confirm(ln mln: LNSocket?) {
        switch self.state {
        case .offer_input(let inv, let decoded):
            guard let pay_amt = get_pay_amount(inv.amount) else {
                self.error = "Expected payment amount for bolt12"
                return
            }
            let req = fetchinvoice_req_from_offer(
                offer: decoded,
                offer_str: inv.invoice,
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


        case .ready(let ready_invoice):
            let pay_amt = get_pay_amount(ready_invoice.amount)
            self.paying = true
            DispatchQueue.global(qos: .background).async {
                confirm_pay(ln: mln, inv: ready_invoice.invoice, pay_amt: pay_amt)
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
            case .offer_input:
                break
            case .initial:
                switch_state(.decoding(nil, self.init_invoice_str))
            case .decoding(let ln, let inv):
                DispatchQueue.global(qos: .background).async {
                    self.handle_decode(ln, inv: inv)
                }
            case .decoded:
                break
            }

    }

    func handle_offer(ln: LNSocket, decoded: Decode, inv: String) {
        switch handle_bolt12_offer(ln: ln, decoded: decoded, inv: inv) {
        case .right(let state):
            self.invoice = decoded
            switch_state(state)
        case .left(let err):
            self.error = err
        }
    }

    func handle_decode(_ oldln: LNSocket?, inv: String) {
        let ln = oldln ?? LNSocket()
        if oldln == nil {
            guard ln.connect_and_init(node_id: self.lnlink.node_id, host: self.lnlink.host) else {
                return
            }
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

                self.state = .ready(ReadyInvoice(invoice: inv, amount: amount))
                self.invoice = decoded
                update_expiry_percent()
            } else {
                self.error = "unknown decoded type: \(decoded.type)"
            }
        }

    }

    func update_expiry_percent() {
        guard let invoice = self.invoice else {
            return
        }

        guard let expiry = invoice.expiry else {
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

func fetchinvoice_req_from_offer(offer: Decode, offer_str: String, pay_amt: PayAmount) -> Either<String, FetchInvoiceReq> {

    var qty: Int? = nil
    if offer.quantity_min != nil {
        qty = offer.quantity_min!
    }

    if offer.amount_msat != nil {
        return .right(.init(offer: offer_str, pay_amt: pay_amt, amount: .any, quantity: qty))
    } else {
        let amount: InvoiceAmount = .amount(pay_amt.amount)
        return .right(.init(offer: offer_str, pay_amt: pay_amt, amount: amount, quantity: qty))
    }
}

func parse_msat(_ s: String) -> Int64? {
    let str = s.replacingOccurrences(of: "msat", with: "")
    return Int64(str)
}

public enum Either<L, R> {
    case left(L)
    case right(R)
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
    case .ready(let ready_invoice):
        return ready_invoice
    case .offer_input(let ready_invoice, _):
        return ready_invoice
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
    case .amount(let amt):
        return "\(render_amount_msats(amt))?"
    case .min(let min):
        return "\(render_amount_msats(min))?"
    }
}

func render_amount_msats(_ amount: Int64) -> String {
    if amount < 1000 {
        return "\(amount) msats"
    }

    return "\(amount / 1000) sats"
}

/*
struct PayView_Previews: PreviewProvider {
    @Binding var invoice: Invoice?

    static var previews: some View {
        PayView(invoice: self.$invoice)
    }
}
*/

func handle_bolt12_offer(ln: LNSocket, decoded: Decode, inv: String) -> Either<String, PayState> {
    if decoded.amount_msat != nil {
        guard let min_amt = parse_msat(decoded.amount_msat!) else {
            return .left("Error parsing amount_msat: '\(decoded.amount_msat!)'")
        }
        let ready = ReadyInvoice(invoice: inv, amount: .min(min_amt))
        return .right(.offer_input(ready, decoded))
    } else {
        let ready = ReadyInvoice(invoice: inv, amount: .any)
        return .right(.offer_input(ready, decoded))
    }
}


func should_show_confirm(_ state: PayState) -> Bool {
    switch state {
    case .ready: fallthrough
    case .offer_input:
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
