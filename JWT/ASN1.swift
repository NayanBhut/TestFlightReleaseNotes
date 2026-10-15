//
//  ASN1.swift
//  AppStoreConnect-Swift-SDK
//
//  Created by Antoine van der Lee on 08/11/2018.
//

import Foundation

public typealias ASN1 = Data

private indirect enum ASN1Element {
    case seq(elements: [ASN1Element])
    case integer(int: Int)
    case bytes(data: Data)
    case constructed(tag: Int, elem: ASN1Element)
    case unknown
}

extension ASN1 {
    public func toECKeyData() throws -> ECKeyData {
        let (result, _) = toASN1Element()

        guard case let ASN1Element.seq(elements: es) = result,
            es.count > 2,
            case let ASN1Element.bytes(data: privateOctest) = es[2] else {
                throw JWT.Error.invalidASN1
        }

        let (octest, _) = privateOctest.toASN1Element()
        guard case let ASN1Element.seq(elements: seq) = octest,
            seq.count > 3,
            case let ASN1Element.bytes(data: privateKeyData) = seq[1],
            case let ASN1Element.constructed(tag: _, elem: publicElement) = seq[3],
            case let ASN1Element.bytes(data: publicKeyData) = publicElement else {
                throw JWT.Error.invalidASN1
        }

        let keyData = (publicKeyData.drop(while: { $0 == 0x00}) + privateKeyData)
        return keyData
    }

    // SecKeyCreateSignature seems to sometimes return a leading zero; strip it out
    private func dropLeadingBytes() -> Data {
        if self.count == 33 {
            return self.dropFirst()
        }
        return self
    }

    /// Convert an ASN.1 format EC signature returned by commoncrypto into a raw 64bit signature
    public func toRawSignature() throws -> Data {
        let (result, _) = self.toASN1Element()

        guard case let ASN1Element.seq(elements: es) = result,
            es.count > 1,
            case let ASN1Element.bytes(data: sigR) = es[0],
            case let ASN1Element.bytes(data: sigS) = es[1] else {
                throw JWT.Error.invalidASN1
        }

        let rawSig = sigR.dropLeadingBytes() + sigS.dropLeadingBytes()
        return rawSig
    }

    /// Declared byte length of the value that starts at `offset` after
    /// the tag, and how many bytes the length field itself takes. Returns
    /// nil when the length bytes or the value would run past `count` —
    /// the callers treat that as a format error, never subscript blindly
    /// (Swift out-of-bounds traps are fatal, and the onboarding `try?`
    /// can't catch one — BUG_SWEEP #2).
    private func readLength() -> (Int, Int)? {
        guard count >= 2 else { return nil }
        if self[0] & 0x80 == 0x00 { // short form
            return (Int(self[0]), 1)
        }
        let lenghOfLength = Int(self[0] & 0x7F)
        guard lenghOfLength > 0, lenghOfLength <= MemoryLayout<Int>.size, 1 + lenghOfLength <= count else { return nil }
        var result: Int = 0
        for i in 1..<(1 + lenghOfLength) {
            let byte = Int(self[i])
            guard result <= (Int.max - byte) / 256 else { return nil }
            result = 256 * result + byte
        }
        guard result <= count - 1 - lenghOfLength else { return nil }
        return (result, 1 + lenghOfLength)
    }

    private func toASN1Element() -> (ASN1Element, Int) {
        guard self.count >= 2 else {
            // format error
            return (.unknown, self.count)
        }

        switch self[0] {
        case 0x30: // sequence
            guard let (length, lengthOfLength) = self.advanced(by: 1).readLength() else {
                return (.unknown, self.count)
            }
            var result: [ASN1Element] = []
            var subdata = self.advanced(by: 1 + lengthOfLength)
            var alreadyRead = 0

            while alreadyRead < length {
                let (e, l) = subdata.toASN1Element()
                guard l > 0 else { break } // malformed child — don't spin
                result.append(e)
                subdata = subdata.count > l ? subdata.advanced(by: l) : Data()
                alreadyRead += l
            }
            return (.seq(elements: result), 1 + lengthOfLength + length)

        case 0x02: // integer
            guard let (length, lengthOfLength) = self.advanced(by: 1).readLength() else {
                return (.unknown, self.count)
            }
            if length < 8 {
                var result: Int = 0
                let subdata = self.advanced(by: 1 + lengthOfLength)
                // ignore negative case
                for i in 0..<length {
                    result = 256 * result + Int(subdata[i])
                }
                return (.integer(int: result), 1 + lengthOfLength + length)
            }
            // number is too large to fit in Int; return the bytes
            return (.bytes(data: self.subdata(in: (1 + lengthOfLength) ..< (1 + lengthOfLength + length))), 1 + lengthOfLength + length)

        case let s where (s & 0xe0) == 0xa0: // constructed
            let tag = Int(s & 0x1f)
            guard let (length, lengthOfLength) = self.advanced(by: 1).readLength() else {
                return (.unknown, self.count)
            }
            let subdata = self.advanced(by: 1 + lengthOfLength)
            let (e, _) = subdata.toASN1Element()
            return (.constructed(tag: tag, elem: e), 1 + lengthOfLength + length)

        default: // octet string
            guard let (length, lengthOfLength) = self.advanced(by: 1).readLength() else {
                return (.unknown, self.count)
            }
            return (.bytes(data: self.subdata(in: (1 + lengthOfLength) ..< (1 + lengthOfLength + length))), 1 + lengthOfLength + length)
        }
    }
}
