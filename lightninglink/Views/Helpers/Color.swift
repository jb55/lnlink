//
//  Color.swift
//  lightninglink
//
//  Created by Honk on 1/3/23.
//

import SwiftUI

extension Color {
    init?(hexString: String) {
        let r, g, b: CGFloat

        var hexColor = hexString

        if hexColor.hasPrefix("#") {
            let start = hexColor.index(hexColor.startIndex, offsetBy: 1)
            hexColor = String(hexColor[start...])
        }

        if hexColor.count == 6 {
            let scanner = Scanner(string: hexColor)
            var hexNumber: UInt64 = 0

            if scanner.scanHexInt64(&hexNumber) {
                r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
                g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
                b = CGFloat(hexNumber & 0x0000ff) / 255

                self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
                return
            }
        }

        return nil
    }
}



