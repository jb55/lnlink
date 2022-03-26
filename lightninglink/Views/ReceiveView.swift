//
//  ReceiveView.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-25.
//

import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @State private var loading: Bool = true
    @State private var qr: Image? = nil
    @State private var qr_data: String? = nil

    let lnlink: LNLink

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Text("Receive payment")
                .font(.title)

            Spacer()

            if let qr = self.qr {
                qr
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .onTapGesture {
                        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                        UIPasteboard.general.string = self.qr_data
                    }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            Spacer()

            HStack {
                Button("Back") {
                    dismiss()
                }
                Spacer()
            }
        }
        .padding()
        .onAppear() {
            make_invoice(lnlink: lnlink, expiry: "12h") { res in
                switch res {
                case .failure:
                    break
                case .success(let invres):
                    self.qr = generate_qr(from: invres.bolt11)
                    self.qr_data = invres.bolt11
                }
            }
        }
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

func make_invoice(lnlink: LNLink, expiry: String, callback: @escaping (RequestRes<InvoiceRes>) -> ()) {
    let ln = LNSocket()

    ln.genkey()
    guard ln.connect_and_init(node_id: lnlink.node_id, host: lnlink.host) else {
        return
    }

    DispatchQueue.global(qos: .background).async {
        let res = rpc_invoice(ln: ln, token: lnlink.token, amount: .any, description: "lnlink invoice", expiry: "12h")
        callback(res)
    }
}
