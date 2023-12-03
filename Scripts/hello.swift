#!/usr/bin/env swift-shell

// MARK: Prints the "Hello" app with command line arguments as `str`
let str = CommandLine.arguments.dropFirst().joined(separator: " ")
print("Hello\(str.isEmpty ? "" : ", \(str)")!")
