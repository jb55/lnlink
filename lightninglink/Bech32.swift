//  Copyright (c) 2017 Alex Bosworth
//  Copyright (c) 2017 Pieter Wuille
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation

extension String {
  func lastIndex(of string: String) -> Int? {
    guard let range = self.range(of: string, options: .backwards) else { return nil }

    return self.distance(from: startIndex, to: range.lowerBound)
  }
}

let CHARSET = byteConvert(string: "qpzry9x8gf2tvdw0s3jn54khce6mua7l")
let GENERATOR = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

func polymod(_ values: [Int]) -> Int {
  return values.reduce(1) { chk, value in
    let top = chk >> 25

    return (Int()..<5).reduce((chk & 0x1ffffff) << 5 ^ value) { chk, i in
      guard (top >> i) & 1 > Int() else { return chk }

      return chk ^ GENERATOR[i]
    }
  }
}

func hrpExpand(_ hrp: [UInt8]) -> [UInt8] {
  return (Int()..<hrp.count).map { hrp[$0] >> 5 } + [UInt8()] + (Int()..<hrp.count).map { hrp[$0] & 31 }
}

func verifyChecksum(hrp: [UInt8], data: [UInt8]) -> Bool {
  return polymod((hrpExpand(hrp) + data).map { Int($0) }) == 1
}

func createChecksum(hrp: [UInt8], data: [UInt8]) -> [UInt8] {
  let values = (hrpExpand(hrp) + data + Array(repeating: UInt8(), count: 6)).map { Int($0) }
  let mod: Int = polymod(values) ^ 1

  return (Int()..<6).map { (mod >> (5 * (5 - $0))) & 31 }.map { UInt8($0) }
}

func byteConvert(string: String) -> [UInt8] {
  return string.map { String($0).unicodeScalars.first?.value }.flatMap { $0 }.map { UInt8($0) }
}

func stringConvert(bytes: [UInt8]) -> String {
  return bytes.reduce(String(), { $0 + String(format: "%c", $1)})
}

func encode(hrp: [UInt8], data: [UInt8]) -> String {
  let checksum = createChecksum(hrp: hrp, data: data)

  return stringConvert(bytes: hrp) + "1" + stringConvert(bytes: (data + checksum).map { CHARSET[Int($0)] })
}

enum DecodeBech32Error: Error {
  case caseMixing
  case inconsistentHrp
  case invalidAddress
  case invalidBits
  case invalidCharacter(String)
  case invalidChecksum
  case invalidPayToHashLength
  case invalidVersion
  case missingSeparator
  case missingVersion

  var localizedDescription: String {
    switch self {
    case .caseMixing:
      return "Mixed case characters are not allowed"

    case .inconsistentHrp:
      return "Internally inconsistent HRP"

    case .invalidAddress:
      return "Address is not a valid type"

    case .invalidBits:
      return "Bits are not valid"

    case .invalidCharacter(let char):
      return "Character \"\(char)\" is not valid"

    case .invalidChecksum:
      return "Checksum failed to verify data"

    case .invalidPayToHashLength:
      return "Unknown hash length for encoded output payload hash"

    case .invalidVersion:
      return "Invalid version number"

    case .missingSeparator:
      return "Missing address data separator"

    case .missingVersion:
      return "Missing address version"
    }
  }
}

public func decodeBech32(bechString: String) throws -> (hrp: [UInt8], data: [UInt8]) {
  let bechBytes = byteConvert(string: bechString)

  guard !(bechBytes.contains() { $0 < 33 && $0 > 126 }) else { throw DecodeBech32Error.invalidCharacter(bechString) }

  let hasLower = bechBytes.contains() { $0 >= 97 && $0 <= 122 }
  let hasUpper = bechBytes.contains() { $0 >= 65 && $0 <= 90 }

  if hasLower && hasUpper { throw DecodeBech32Error.caseMixing }

  let bechString = bechString.lowercased()

  guard let pos = bechString.lastIndex(of: "1") else { throw DecodeBech32Error.missingSeparator }

  if pos < 1 || pos + 7 > bechString.count {
    throw DecodeBech32Error.missingSeparator
  }

  let bechStringBytes = byteConvert(string: bechString)
  let hrp = byteConvert(string: bechString.substring(to: bechString.index(bechString.startIndex, offsetBy: pos)))

  let data: [UInt8] = try ((pos + 1)..<bechStringBytes.count).map { i in
      guard let d = CHARSET.firstIndex(of: bechStringBytes[i]) else {
      throw DecodeBech32Error.invalidCharacter(stringConvert(bytes: [bechStringBytes[i]]))
    }

    return UInt8(d)
  }

  guard verifyChecksum(hrp: hrp, data: data) else { throw DecodeBech32Error.invalidChecksum }

  return (hrp: hrp, data: Array(data[Int()..<data.count - 6]))
}

func convertbits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) throws -> [UInt8] {
  var acc = Int()
  var bits = UInt8()
  let maxv = (1 << toBits) - 1

  let converted: [[Int]] = try data.map { value in
    if (value < 0 || (UInt8(Int(value) >> fromBits)) != 0) {
      throw DecodeBech32Error.invalidCharacter(stringConvert(bytes: [value]))
    }

    acc = (acc << fromBits) | Int(value)
    bits += UInt8(fromBits)

    var values = [Int]()

    while bits >= UInt8(toBits) {
      bits -= UInt8(toBits)
      values += [(acc >> Int(bits)) & maxv]
    }

    return values
  }

  let padding = pad && bits > UInt8() ? [acc << (toBits - Int(bits)) & maxv] : []

  if !pad && (bits >= UInt8(fromBits) || acc << (toBits - Int(bits)) & maxv > Int()) {
    throw DecodeBech32Error.invalidBits
  }

  return ((converted.flatMap { $0 }) + padding).map { UInt8($0) }
}

func encode(hrp: [UInt8], version: UInt8, program: [UInt8]) throws -> String {
  let address = try encode(hrp: hrp, data: [version] + convertbits(data: program, fromBits: 8, toBits: 5, pad: true))

  // Confirm encoded address parses without error
  let _ = try decodeAddress(hrp: hrp, address: address)

  return address
}

func decodeAddress(hrp: [UInt8], address: String) throws -> (version: UInt8, program: [UInt8]) {
  let decoded = try decodeBech32(bechString: address)

  // Confirm decoded address matches expected type
  guard stringConvert(bytes: decoded.hrp) == stringConvert(bytes: hrp) else { throw DecodeBech32Error.inconsistentHrp }

  // Confirm version byte is present
  guard let versionByte = decoded.data.first else { throw DecodeBech32Error.missingVersion }

  // Confirm version byte is within the acceptable range
  guard !decoded.data.isEmpty && versionByte <= 16 else { throw DecodeBech32Error.invalidVersion }

  let program = try convertbits(data: Array(decoded.data[1..<decoded.data.count]), fromBits: 5, toBits: 8, pad: false)

  // Confirm program is a valid length
  guard program.count > 1 && program.count < 41 else { throw DecodeBech32Error.invalidAddress }

  if versionByte == UInt8() {
    // Confirm program is a known byte length (20 for pkhash, 32 for scripthash)
    guard program.count == 20 || program.count == 32 else { throw DecodeBech32Error.invalidPayToHashLength }
  }

  return (version: versionByte, program: program)
}

func segwitScriptPubKey(version: UInt8, program: [UInt8]) -> [UInt8] {
  return [version > UInt8() ? version + 0x50 : UInt8(), UInt8(program.count)] + program
}


/*
class TestBech32: XCTestCase {
  func testInvalidAddresses() {
    let INVALID_ADDRESS = [
      "tc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty",
      "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5",
      "BC13W508D6QEJXTDG4Y5R3ZARVARY0C5XW7KN40WF2",
      "bc1rw5uspcuh",
      "bc10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5rljs90",
      "BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P",
      "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7",
      "tb1pw508d6qejxtdg4y5r3zarqfsj6c3",
      "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv",
    ]

    INVALID_ADDRESS.forEach { test in
      ["bc", "tb"].forEach { type in
        do {
          let _ = try decodeAddress(hrp: byteConvert(string: type), address: test)

          XCTFail("Expected invalid address: \(test)")
        } catch {
          return
        }
      }
    }
  }

  func testChecksums() {
    let VALID_CHECKSUM: [String] = [
      "A12UEL5L",
      "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
      "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
      "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
      "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w"
    ]

    do {
      try VALID_CHECKSUM.forEach { test in
        let _ = try decodeBech32(bechString: test)
      }
    } catch {
      XCTFail(error.localizedDescription)
    }
  }

  func testValidAddresses() {
    let VALID_BC_ADDRESSES: [String: (decoded: [UInt8], type: String)] = [
      "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4": (
        decoded: [
          0x00, 0x14, 0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54,
          0x94, 0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6
        ],
        type: "bc"
      ),

      "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7": (
        decoded: [
          0x00, 0x20, 0x18, 0x63, 0x14, 0x3c, 0x14, 0xc5, 0x16, 0x68, 0x04,
          0xbd, 0x19, 0x20, 0x33, 0x56, 0xda, 0x13, 0x6c, 0x98, 0x56, 0x78,
          0xcd, 0x4d, 0x27, 0xa1, 0xb8, 0xc6, 0x32, 0x96, 0x04, 0x90, 0x32,
          0x62
        ],
        type: "tb"
      ),

      "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7k7grplx": (
        decoded: [
          0x51, 0x28, 0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54,
          0x94, 0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6,
          0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54, 0x94, 0x1c,
          0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6
        ],
        type: "bc"
      ),

      "BC1SW50QA3JX3S": (decoded: [0x60, 0x02, 0x75, 0x1e], type: "bc"),

      "bc1zw508d6qejxtdg4y5r3zarvaryvg6kdaj": (
        decoded: [
          0x52, 0x10, 0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54,
          0x94, 0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23
        ],
        type: "bc"
      ),

      "tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy": (
        decoded: [
          0x00, 0x20, 0x00, 0x00, 0x00, 0xc4, 0xa5, 0xca, 0xd4, 0x62, 0x21,
          0xb2, 0xa1, 0x87, 0x90, 0x5e, 0x52, 0x66, 0x36, 0x2b, 0x99, 0xd5,
          0xe9, 0x1c, 0x6c, 0xe2, 0x4d, 0x16, 0x5d, 0xab, 0x93, 0xe8, 0x64,
          0x33
        ],
        type: "tb"
      )
    ]

    do {
      try VALID_BC_ADDRESSES.forEach { address, result in
        let scriptPubKey = result.decoded
        let hrp = byteConvert(string: result.type)

        let ret = try decodeAddress(hrp: hrp, address: address)

        let output = segwitScriptPubKey(version: ret.version, program: ret.program)

        XCTAssertEqual(output, scriptPubKey)

        let recreated = try encode(hrp: hrp, version: ret.version, program: ret.program).lowercased()

        XCTAssertEqual(recreated, address.lowercased())
      }
    } catch {
      XCTFail(error.localizedDescription)
    }
  }
}

 */
