import Foundation

enum SafeText {
    static func terminal(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let n = scalar.value
            return n < 0x20 || (0x7f...0x9f).contains(n) || (0x202a...0x202e).contains(n)
                || (0x2066...0x2069).contains(n) ? Unicode.Scalar(0xfffd)! : scalar
        }))
    }
}
