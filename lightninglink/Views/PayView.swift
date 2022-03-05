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

public struct FetchInvoiceReq {
    let offer: String
    let amount: InvoiceAmount
    let quantity: Int?
}

public enum PayState {
    case initial
    case decoding(LNSocket?, String)
    case decoded(DecodeType)
    case fetch_invoice(LNSocket, FetchInvoiceReq)
    case ready(ReadyInvoice)
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
            if self.invoice != nil {
                Text("Confirm Payment")
                    .font(.largeTitle)
                    .padding()
            } else {
                Text("Fetching invoice")
                    .font(.largeTitle)
                    .padding()
            }

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

            let ready_invoice = is_ready(state)
            if ready_invoice != nil {
                amount_view_inv(ready_invoice!.amount)
            }

            Text("\(self.error ?? "")")
                .foregroundColor(Color.red)
            Spacer()
            HStack {
                Button("Cancel") {
                    self.dismiss()
                }
                .foregroundColor(Color.red)
                .font(.title)

                Spacer()

                confirm_button(ready_invoice)
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

    func confirm_button(_ ready_invoice: ReadyInvoice?) -> some View {
        Group {
            if ready_invoice != nil {
                Button("Confirm") {
                    let res = confirm_payment(bolt11: ready_invoice!.invoice, lnlink: self.lnlink)

                    switch res {
                    case .left(let err):
                        self.error = "Error: \(err)"

                    case .right(let pay):
                        print(pay)
                        self.dismiss()
                        NotificationCenter.default.post(name: .sentPayment, object: pay)
                    }
                }
                .foregroundColor(Color.green)
                .font(.title)
            }
        }
    }

    func switch_state(_ state: PayState) {
        self.state = state
        handle_state_change()
    }

    func handle_state_change() {
            switch self.state {
            case .ready:
                break
            case .initial:
                switch_state(.decoding(nil, self.init_invoice_str))
            case .decoding(let ln, let inv):
                DispatchQueue.global(qos: .background).async {
                    self.handle_decode(ln, inv: inv)
                }
            case .fetch_invoice(let ln, let req):
                DispatchQueue.global(qos: .background).async {
                    self.handle_fetch_invoice(ln: ln, req: req)
                }
            case .decoded:
                break
            }

    }

    func handle_fetch_invoice(ln: LNSocket, req: FetchInvoiceReq) {
        switch rpc_fetchinvoice(ln: ln, token: self.lnlink.token, req: req) {
        case .failure(let err):
            self.error = err.description
        case .success(let fetch_invoice):
            switch_state(.decoding(ln, fetch_invoice.invoice))
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
                // TODO: handle custom amounts for offers
                let amt: Int64? = 10000
                let req = fetchinvoice_req_from_offer(offer: decoded, offer_str: inv, amount: amt)
                switch req {
                case .left(let err):
                    self.error = err
                case .right(let req):
                    switch_state(.fetch_invoice(ln, req))
                }
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

func fetchinvoice_req_from_offer(offer: Decode, offer_str: String, amount: Int64?) -> Either<String, FetchInvoiceReq> {

    var qty: Int? = nil
    if offer.quantity_min != nil {
        qty = offer.quantity_min!
    }

    if offer.amount_msat != nil {
        return .right(FetchInvoiceReq(offer: offer_str, amount: .any, quantity: qty))
    } else {
        guard let amt = amount else {
            return .left("Amount required for offer")
        }

        return .right(FetchInvoiceReq(offer: offer_str, amount: .amount(amt), quantity: qty))
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

func confirm_payment(bolt11: String, lnlink: LNLink) -> Either<String, Pay> {
    // do a fresh connection for each payment
    let ln = LNSocket()

    guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
        return .left("Failed to connect, please try again!")
    }

    let res = rpc_pay(
        ln: ln,
        token: lnlink.token,
        bolt11: bolt11,
        amount_msat: nil)

    switch res {
    case .failure(let req_err):
        // handle error
        let errmsg = req_err.description
        return .left(errmsg)

    case .success(let pay):
        return .right(pay)
    }
}

func amount_view(_ state: PayState) -> some View {
    Group {
    }
}

func is_ready(_ state: PayState) -> ReadyInvoice? {
    switch state {
    case .ready(let ready_invoice):
        return ready_invoice
    case .fetch_invoice: fallthrough
    case .initial: fallthrough
    case .decoding: fallthrough
    case .decoded:
        return nil
    }
}

func amount_view_inv(_ amt: InvoiceAmount) -> some View {
    Group {
        switch amt {
        case .any:
            Text("Custom amounts not supported yet :(")
        case .amount(let amt):
            Text("Pay")
            Text("\(render_amount_msats(amt))")
                .font(.title)
        }
    }
}

func render_amount(_ amt: InvoiceAmount) -> String {
    switch amt {
    case .any:
        return "Enter amount"
    case .amount(let amt):
        return "\(render_amount_msats(amt))?"
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
