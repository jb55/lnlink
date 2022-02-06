//
//  PayView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-02-05.
//

import SwiftUI

struct PayView: View {
    var invoice_str: String
    var invoice: Invoice
    var ln: LNSocket
    var token: String
    @State var pay_result: Pay?
    @State var error: String?

    @Environment(\.presentationMode) var presentationMode

    init(invoice_str: String, invoice: Invoice, ln: LNSocket, token: String) {
        self.invoice_str = invoice_str
        self.invoice = invoice
        self.ln = ln
        self.token = token
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
            Text("\(self.invoice.amount()) msats?")
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
                    let res = rpc_pay(
                        ln: self.ln,
                        token: self.token,
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
