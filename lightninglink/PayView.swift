//
//  PayView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import SwiftUI

func render_amount(_ amount: Int64) -> String {
    if amount < 1000 {
        return "\(amount) msats"
    }

    return "\(amount / 1000) sats"
}

struct PayView: View {
    var invoice_str: String
    var amount: Int64
    var lnlink: LNLink
    @State var pay_result: Pay?
    @State var error: String?

    @Environment(\.presentationMode) var presentationMode

    init(invoice_str: String, amount: Int64, lnlink: LNLink) {
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
            Text("\(render_amount(self.amount))?")
                .font(.title)
            Text("\(self.error ?? "")")
            Spacer()
            HStack {
                Button("Cancel") {
                    self.dismiss()
                }
                .font(.title)

                Spacer()

                Button("Confirm") {
                    // do a fresh connection for each payment
                    let ln = LNSocket()

                    guard ln.connect_and_init(node_id: self.lnlink.node_id, host: self.lnlink.host) else {
                        self.error = "Failed to connect, please try again!"
                        return
                    }

                    let res = rpc_pay(
                        ln: ln,
                        token: lnlink.token,
                        bolt11: self.invoice_str,
                        amount_msat: nil)

                    switch res {
                    case .failure(let req_err):
                        // handle error
                        self.error = req_err.description

                    case .success(let pay):
                        self.error = nil
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
