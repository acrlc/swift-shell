import struct Foundation.Data

extension Data {
 func asciiOutput() -> String {
  guard let output = String(data: self, encoding: .ascii) else {
   return ""
  }

  guard !output.hasSuffix("\n") else {
   let endIndex = output.index(before: output.endIndex)
   return String(output[..<endIndex])
  }

  return output
 }
}
