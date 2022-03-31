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
    @State private var amount: Int64? = nil
    @State private var amount_str: String = ""
    @State private var making: Bool = false
    @FocusState private var is_kb_focused: Bool
    @Binding var rate: ExchangeRate?

    let lnlink: LNLink

    @Environment(\.presentationMode) var presentationMode

    var form: some View {
            ProgressView()
                .progressViewStyle(.circular)
    }

    var body: some View {
        VStack {
            Text("Receive payment")
                .font(.title)

            Spacer()

            if let qr = self.qr_data {
                qrcode_view(qr)
            } else {
                if making {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Form {
                        TextField("Description", text: $description)
                            .font(.body)
                            .focused($is_kb_focused)

                        Section {
                            AmountInput(text: $amount_str, placeholder: "any") { parsed in
                                if let str = parsed.msats_str {
                                    self.amount_str = str
                                }
                                if let msats = parsed.msats {
                                    self.amount = msats
                                }
                            }
                            .focused($is_kb_focused)

                        }

                    }
                    .frame(height: 200)

                    if self.amount_str != "", let msats = self.amount {
                        if let rate = self.rate {
                            Text("\(msats_to_fiat(msats: msats, xr: rate))")
                                .foregroundColor(.gray)
                        }
                    }

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
                        make_invoice(lnlink: lnlink, expiry: "12h", description: self.description, amount: self.amount) { res in
                            self.making = false
                            switch res {
                            case .failure:
                                break
                            case .success(let invres):
                                let img = generate_qr(from: invres.bolt11)
                                self.qr_data = QRData(img: img, data: invres.bolt11)
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

func make_invoice(lnlink: LNLink, expiry: String, description: String?, amount: Int64?, callback: @escaping (RequestRes<InvoiceRes>) -> ()) {
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
        let res = rpc_invoice(ln: ln, token: lnlink.token, amount: amt, description:  description ?? "lnlink invoice", expiry: "12h")
        callback(res)
    }
}

func qrcode_view(_ qrd: QRData) -> some View {
    qrd.img
        .resizable()
        .scaledToFit()
        .frame(width: 300, height: 300)
        .onTapGesture {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            UIPasteboard.general.string = qrd.data
        }
}
