//
//  ReceiveView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-25.
//

import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import Combine

struct QRData {
    let img: Image
    let data: String
}

struct ReceiveView: View {
    @State private var loading: Bool = true
    @State private var qr_data: QRData? = nil
    @State private var description: String = ""
    @State private var issuer: String = ""
    @State private var amount: Int64? = nil
    @State private var amount_str: String = ""
    @State private var making: Bool = false
    @State private var is_offer: Bool = false
    @FocusState private var is_kb_focused: Bool
    @Binding var rate: ExchangeRate?

    let lnlink: LNLink

    @Environment(\.presentationMode) var presentationMode

    var form: some View {
            ProgressView()
                .progressViewStyle(.circular)
    }

    func invoice_details_form() -> some View {
        Group {
            Form {
                Section(header: Text("Invoice Details")) {
                    Toggle("Offer (bolt12)", isOn: $is_offer)
                        .padding()

                    TextField("Description", text: $description)
                        .font(.body)
                        .focused($is_kb_focused)
                        .padding()

                    if self.is_offer {
                        TextField("Issuer", text: $issuer)
                            .font(.body)
                            .focused($is_kb_focused)
                            .padding()
                    }

                    AmountInput(text: $amount_str, placeholder: "any") { parsed in
                        if let str = parsed.msats_str {
                            self.amount_str = str
                        }
                        if let msats = parsed.msats {
                            self.amount = msats
                        }
                    }
                    .padding()
                    .focused($is_kb_focused)
                }
            }
            .frame(height: 350)

            if self.amount_str != "", let msats = self.amount {
                if let rate = self.rate {
                    Text("\(msats_to_fiat(msats: msats, xr: rate))")
                        .foregroundColor(.gray)
                }
            }
        }
    }

    var body: some View {
        VStack {
            Text("Receive payment")
                .font(.title)

            Spacer()

            if let qr = self.qr_data {
                QRCodeView(qr: qr)
            } else {
                if making {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    invoice_details_form()
                }
            }

            Spacer()

            HStack {
                if !is_kb_focused {
                    Button("Back") {
                        dismiss()
                    }
                } else {
                    Button("Close") {
                        close_keyboard()
                    }
                }

                Spacer()

                if !self.making && self.qr_data == nil {
                    Button("Receive") {
                        self.making = true
                        make_invoice(lnlink: lnlink, expiry: "12h", description: self.description, amount: self.amount, issuer: self.issuer, is_offer: self.is_offer) { res in
                            switch res {
                            case .failure:
                                self.making = false
                                break
                            case .success(let invres):
                                let upper = invres.uppercased()
                                let img = generate_qr(from: upper)
                                self.making = false
                                self.qr_data = QRData(img: img, data: upper)
                            }
                        }
                    }
                    .font(.title)
                }
            }
        }
        .padding()
    }

    private func close_keyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
    }

    private func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }

}


func generate_qr(from string: String) -> Image {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()

    filter.message = Data(string.uppercased().utf8)
    if let output_img = filter.outputImage {
        if let cgimg = context.createCGImage(output_img, from: output_img.extent) {
            let uiimg = UIImage(cgImage: cgimg)
            return Image(uiImage: uiimg).interpolation(.none)
        }
    }

    let uiimg = UIImage(systemName: "xmark.circle") ?? UIImage()
    return Image(uiImage: uiimg)
}

func make_invoice(lnlink: LNLink, expiry: String, description: String?, amount: Int64?, issuer: String?, is_offer: Bool, callback: @escaping (RequestRes<String>) -> ()) {
    let ln = LNSocket()

    ln.genkey()
    guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
        return
    }

    DispatchQueue.global(qos: .background).async {
        var amt: InvoiceAmount = .any
        if let a = amount {
            amt = .amount(a)
        }

        let desc = description ?? "lnlink invoice"
        let expiry = "12h"
        if is_offer {
            let res = rpc_offer(ln: ln, token: lnlink.token, amount: amt, description: desc, issuer: issuer)
            callback(res.map{ $0.bolt12 })
        } else {
            let res = rpc_invoice(ln: ln, token: lnlink.token, amount: amt, description: desc, expiry: expiry)
            callback(res.map{ $0.bolt11 })
        }
    }
}

struct QRCodeView: View {
    let qr: QRData
    @State var copied: Bool = false

    var body: some View {
        Group {
            qr.img
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .onTapGesture {
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    UIPasteboard.general.string = self.qr.data
                    copied = true
                }

            Text("\(!copied ? "Tap QR to copy invoice" : "Copied!")")
                .font(.subheadline)
                .foregroundColor(.gray)

        }

    }
}
