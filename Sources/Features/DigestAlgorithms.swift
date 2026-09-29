import Foundation
import CommonCrypto

struct MD4Digest {
    private var context = CC_MD4_CTX()
    init() { CC_MD4_Init(&context) }
    mutating func update(_ data: Data) { data.withUnsafeBytes { _ = CC_MD4_Update(&context, $0.baseAddress, CC_LONG($0.count)) } }
    mutating func finalize() -> [UInt8] { var output = [UInt8](repeating: 0, count: 16); CC_MD4_Final(&output, &context); return output }
}

/**
 * Keccak-f[1600] with a 1088-bit rate. SHA3-256 and Keccak-256 use different suffixes.
 * Rotation offsets and round constants: https://keccak.team/keccak_specs_summary.html
 */
struct Keccak256Digest {
    private var state = [UInt64](repeating: 0, count: 25)
    private var position = 0
    private let suffix: UInt64
    init(sha3: Bool) { suffix = sha3 ? 0x06 : 0x01 }
    mutating func update(_ data: Data) {
        for byte in data {
            state[position / 8] ^= UInt64(byte) << (8 * (position % 8))
            position += 1
            if position == 136 { permute(); position = 0 }
        }
    }
    mutating func finalize() -> [UInt8] {
        state[position / 8] ^= suffix << (8 * (position % 8))
        state[16] ^= 0x8000000000000000
        permute()
        return (0..<32).map { UInt8(truncatingIfNeeded: state[$0 / 8] >> (8 * ($0 % 8))) }
    }
    private mutating func permute() {
        let constants: [UInt64] = [0x0000000000000001,0x0000000000008082,0x800000000000808A,0x8000000080008000,
            0x000000000000808B,0x0000000080000001,0x8000000080008081,0x8000000000008009,
            0x000000000000008A,0x0000000000000088,0x0000000080008009,0x000000008000000A,
            0x000000008000808B,0x800000000000008B,0x8000000000008089,0x8000000000008003,
            0x8000000000008002,0x8000000000000080,0x000000000000800A,0x800000008000000A,
            0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008]
        let rotations = [0,1,62,28,27,36,44,6,55,20,3,10,43,25,39,41,45,15,21,8,18,2,61,56,14]
        func rotate(_ word: UInt64, _ count: Int) -> UInt64 { count == 0 ? word : (word << count) | (word >> (64 - count)) }
        var columns = [UInt64](repeating: 0, count: 5), moved = [UInt64](repeating: 0, count: 25)
        for constant in constants {
            for x in 0..<5 { columns[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] }
            for x in 0..<5 {
                let delta = columns[(x + 4) % 5] ^ rotate(columns[(x + 1) % 5], 1)
                for y in 0..<5 { state[x + 5 * y] ^= delta }
            }
            for x in 0..<5 { for y in 0..<5 { moved[y + 5 * ((2 * x + 3 * y) % 5)] = rotate(state[x + 5 * y], rotations[x + 5 * y]) } }
            for x in 0..<5 { for y in 0..<5 { state[x + 5 * y] = moved[x + 5 * y] ^ ((~moved[(x + 1) % 5 + 5 * y]) & moved[(x + 2) % 5 + 5 * y]) } }
            state[0] ^= constant
        }
    }
}
