import Paths
import Shell

extension File {
 // MARK: - Dependencies
 func parse(testing: Bool) throws
  -> (String, [(product: String, package: String)]) {
  // switch to script root because there could be path based dependencies
  parent.unsafelyUnwrapped.set()

  let codes = try readAsString()
  // trim leading whitespace and remove shebang
  var dependencies: [(product: String, package: String)] = .empty
  var lines = codes.split(separator: .newline, omittingEmptySubsequences: false)

  guard !lines.isEmpty else { return (codes, []) }
  let endIndex = lines.endIndex
  var index: Int = .zero

  if lines[0].hasPrefix("#!") {
   // TODO: parse this line to include additional arguments
   // ...
   // maintain line consistency, so the file can be debugged from terminal
   lines[0] = "//"
   index += 1
  }

  while index < endIndex {
   defer { index += 1 }
   var line: Substring.SubSequence {
    get { lines[index] }
    set { lines[index] = newValue }
   }

   guard !line.isEmpty else { continue }

   var commentIndices: Range<Substring.SubSequence.Index>? {
    if
     let first = line.firstIndex(of: "/"),
     let nextIndex =
     line.index(first, offsetBy: 1, limitedBy: line.endIndex),
     line[nextIndex] == "/" {
     return first ..< nextIndex
    }
    return nil
   }

   func dependency() -> (product: String, package: String)? {
    guard let commentIndices else { return nil }
    let importPrefix = line[..<commentIndices.lowerBound]
    // import name
    let name = importPrefix.split(separator: .space).last.unsafelyUnwrapped
    // possible source
    let source =
     line[commentIndices.upperBound ..< line.endIndex]
      .dropFirst().drop(while: \.isWhitespace)

    // return path based dependency
    func path() throws -> (product: String, package: String)? {
     let folder = try Folder(path: source.expandingVariables)

     line.removeSubrange(commentIndices.lowerBound...)

     let packageName = folder.name
     return (
      packageName == name
       ? "\"\(name)\""
       : ".product(name: \"\(name)\", package: \"\(packageName)\")",
      ".package(path: \"\(folder.path)\")"
     )
    }

    // TODO: include version detection
    func url() throws -> (product: String, package: String)? {
     var splits = source.dropFirst().split(separator: "/")
     guard !splits.isEmpty else { return nil }
     let prefix = splits.removeFirst()

     let (domain, branch): (Substring, String?) = {
      if prefix.contains(":") {
       let count = prefix.count(for: ":")
       assert(
        count == 1, "invalid domain, must follow the format <domain:branch>"
       )
       var domainSplit = prefix.split(separator: ":")

       while splits.count > 2 {
        domainSplit.append(splits.removeFirst())
       }
       return (domainSplit[0], domainSplit[1...].joined(separator: "/"))
      } else {
       return (prefix, nil)
      }
     }()

     let path = splits.joined(separator: "/")
     let urlString =
      "https://\(domain == "git" ? "github" : domain).com/\(path)"
     let url = try URL(string: urlString).throwing()

     line.removeSubrange(commentIndices.lowerBound...)

     let packageName = url.lastPathComponent
     return (
      packageName == name
       ? "\"\(name)\""
       : ".product(name: \"\(name)\", package: \"\(packageName)\")",
      ".package(url: \"\(urlString)\", branch: \"\(branch ?? "main")\")"
     )
    }

    do {
     if source.hasPrefix("@") {
      return try url()
     } else {
      return try path()
     }
    } catch {
     exit(2, "\(importPrefix.dropLast()): missing package: \(source)")
    }
   }

   // sort according to import specification
   // TODO: add dependency according to import scope
   if line.hasPrefix("import ") {
    guard let dependency = dependency() else { continue }
    dependencies.append(dependency)
   } else if line.hasPrefix("@testable import ") {
    guard testing else {
     exit(
      2,
      """
      @testable import not allowed, not built for testing
      \tplease use flag -t or --testable to enable
      """
     )
    }

    guard let dependency = dependency() else { continue }
    dependencies.append(dependency)
   } else if line.hasPrefix("@_exported import ") {
    guard let dependency = dependency() else { continue }
    dependencies.append(dependency)
   }
  }

  return (lines.joined(separator: .newline), dependencies)
 }
}

// MARK: - Real Path
// adapted from https://www.github.com/mxcl/Path.swift
#if !os(Linux)
import func Darwin.realpath
let _realpath = Darwin.realpath
#else
import func Glibc.realpath
let _realpath = Glibc.realpath
#endif

extension PathRepresentable {
 /// Recursively resolves symlinks in this path.
 func withRealPath() throws -> Self {
  guard let rv = _realpath(path, nil) else {
   throw CocoaError.error(.fileNoSuchFile)
  }
  defer { free(rv) }
  guard let rvv = String(validatingUTF8: rv) else {
   throw CocoaError.error(.fileReadUnknownStringEncoding)
  }

  // “Removing an initial component of “/private/var/automount”,
  // “/var/automount”,
  // or “/private” from the path, if the result still indicates an existing file
  // or
  // directory (checked by consulting the file system).”
  // ^^ we do this to not conflict with the results that other Apple APIs give
  // which is necessary if we are to have equality checks work reliably
  let rvvv = (rvv as NSString).standardizingPath

  return try Self(path: rvvv)
 }
}
