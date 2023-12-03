#!/usr/bin/env swift-shell
import Shell // @git/codeAcrylic/shell

// MARK: Prints out all 256 colors if supported by the terminal
let range = 0 ..< 16 as Range<UInt8>
for i in range {
 for j in range {
  let code = i * 16 + j
  echo(code, color: .extended(code), terminator: .tab)
 }
}

print()
