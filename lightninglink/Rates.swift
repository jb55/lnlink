//
//  Rates.swift
//  lightninglink
//
//  Created by William Casarin on 2022-03-24.
//

import Foundation

enum Currency: String {
    case USD
    case CAD
}

enum StringNum: Decodable {
    case string(String)
    case number(Double)

    init (from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let str = try? value.decode(String.self) {
            self = .string(str)
            return
        }

        self = .number(try value.decode(Double.self))
    }
}

struct ExchangeRate {
    let currency: Currency
    let rate: Double
}

func get_exchange_rate(for_cur: Currency, cb: @escaping (ExchangeRate?) -> ()) {
    let url = URL(string: "https://api-pub.bitfinex.com/v2/tickers?symbols=tBTC\(for_cur)")!
    let task = URLSession.shared.dataTask(with: url) { (mdata, response, error) in
        guard let data = mdata else {
            cb(nil)
            return
        }

        guard let rate = decode_bitfinex_exchange_rate(data) else {
            cb(nil)
            return
        }

        cb(ExchangeRate(currency: for_cur, rate: rate))
    }

    task.resume()
}

func decode_bitfinex_exchange_rate(_ data: Data) -> Double? {
    guard let container: Array<Array<StringNum>> = decode_data(data) else {
        return nil
    }

    guard container.count >= 1 && container[0].count >= 2 else {
        return nil
    }

    switch container[0][1] {
    case .string:
        return nil
    case .number(let xr):
        return Double(xr)
    }
}

