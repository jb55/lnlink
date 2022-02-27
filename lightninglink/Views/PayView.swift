//
//  PayView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import SwiftUI


struct PayView: View {
    var invoice_str: String
    var amount: InvoiceAmount
    var lnlink: LNLink

    @State var pay_result: Pay?
    @State var error: String?

    @Environment(\.presentationMode) var presentationMode

    init(invoice_str: String, amount: InvoiceAmount, lnlink: LNLink) {
        self.invoice_str = invoice_str
        self.amount = amount
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
        return VStack() {
            Text("Confirm payment")
                .font(.largeTitle)
            Spacer()
            Text("Pay")
            Text("\(render_amount(self.amount))")
                .font(.title)
            Text("\(self.error ?? "")")
                .foregroundColor(Color.red)
            Spacer()
            HStack {
                Button("Cancel") {
                    self.dismiss()
                }
                .font(.title)

                Spacer()

                Button("Confirm") {
                    let res = confirm_payment(bolt11: self.invoice_str, lnlink: self.lnlink)

                    switch res {
                    case .left(let err):
                        self.error = "Error: \(err)"

                    case .right(let pay):
                        print(pay)
                        self.dismiss()
                        NotificationCenter.default.post(name: .sentPayment, object: pay)
                    }
            }
                .font(.title)
            }
        }
        .padding()
    }
}

/*
struct PayView_Previews: PreviewProvider {
    @Binding var invoice: Invoice?

    static var previews: some View {
        PayView(invoice: self.$invoice)
    }
}


*/

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
