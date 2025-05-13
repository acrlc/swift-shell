import Core
import Shell
#if canImport(CryptoKit)
import enum CryptoKit.Insecure
#else
import enum Crypto.Insecure
#endif

var silent: Bool = false
var testable: Bool = false
// FIXME: remove not working even when other flags are omitted
/// Update all dependencies and rebuild using the current build folder
var update: Bool = false
/// Remove the build folder and binary from cache
var clean: Bool = false
/// Remove the project folder from cache
var remove: Bool = false
/// Experimental features
var enabled: [String] = .empty
/// Compiler flags / options
var flags: [String] = .empty
/// Toolchain path
var toolchain: String?
var shouldPrint: Bool = false
var shouldOpen: Bool = false
/*
 considering an install or copy function
 static var install: Bool = false
 static var copy: Bool = false
 */
// TODO: add option to prune projects that no longer exist
var arguments = CommandLine.arguments[1...].map { $0 }

let home: Folder = .home
#if os(macOS)
var cacheFolder: Folder {
 get throws {
  try (try? home.subfolder(at: "Developer")) ??
   home.subfolder(at: "Library/Developer")
 }
}
#else
// TODO: determine the correct cache folder
var cacheFolder: Folder { home }
#endif

var cache: Folder {
 get throws {
  try cacheFolder.createSubfolderIfNeeded(at: ".swift.shell.cache")
 }
}

// TODO: bookmark files and change hashed path when necessary
// TODO: map dependencies and check for updates on remote dependencies
// to the project.swift file
// if modified it should rebuild the package file, which adds the dependencies
guard arguments.notEmpty else {
 exit(1, "missing paramters:\n\t[<option> or [-flags]] <filename> <arguments>")
}


do {
 parse()
 
 let input = arguments.removeFirst()
 let file = try File(path: input).withRealPath()

 let hashedPath = Insecure.MD5.hash(data: Data(file.path.lowercased().utf8))
  .compactMap { String(format: "%02x", $0) }
  .joined()

 let scriptName = file.name
 let name = file.nameExcludingExtension
 let libraryName = name.uppercaseFirst
 let binaryName = name.lowercaseFirst
 let buildFolder = "\(binaryName)-\(hashedPath)"
 let project = try? cache.subfolder(at: buildFolder)
 let executable = (testable ? binaryName + "-testable" : binaryName)

 try check(project, file, binaryName, executable)

 let modified = file.modificationDate ?? .now

 if
  let project,
  project.containsFile(at: "Package.swift"),
  project.containsFile(at: executable),
  let interval =
  try? TimeInterval(project.file(at: ".modified").readAsString()),
  // check modification interval
  modified == Date(timeIntervalSinceReferenceDate: interval) {
  if shouldOpen {
   #if os(macOS)
   try! project.file(at: "Package.swift").open()
   exit(0)
   #else
   exit(1, "unable to open package on this operating system")
   #endif
  }

  let path = project.path + executable

  if shouldPrint {
   print(path)
  }

  try execv(path, arguments)
 } else { try initialize() }

// MARK: - Functions
 func parse() {
  if arguments[0].hasPrefix("-"), arguments.count > 1 {
   // FIXME: edge case where "-" can be used as an input
   // by checking when a flag is set, then asserting
   // so the first argument (which could be a filename) isn't removed
   let argument = arguments.removeFirst().drop(while: { $0 == "-" })

   func splitInput() -> [String] {
    guard arguments.count > 1 else { return .empty }
    return arguments
     .removeFirst()
     .split(separator: .comma)
     .joined(separator: .space)
     .split(separator: .space)
     .map(String.init)
   }

   switch argument {
   case "silent": silent = true
   case "testable": testable = true
   case "enable": enabled = splitInput()
   case "flags": flags = splitInput()
   case "toolchain": toolchain = arguments.removeFirst()
   case "clean": clean = true
   case "remove": remove = true
   case "update": update = true
   case "open": shouldOpen = true
   case "print": shouldPrint = true
   default:
    // FIXME: ensure arguments pass sanity test
    for char in argument {
     switch char {
     case "s": silent = true
     case "t": testable = true
     case "e": enabled = splitInput()
     case "f": flags = splitInput()
     case "v": toolchain = arguments.removeFirst()
     case "c": clean = true
     case "r": remove = true
     case "u": update = true
     case "o": shouldOpen = true
     case "p": shouldPrint = true
     default:
      exit(1, "unknown option: \(argument)")
     }
    }
   }
  }
 }

 func check(
  _ project: Folder?,
  _: File,
  _ binaryName: String,
  _ executable: String
 ) throws {
  // FIXME: `clean` argument doesn't pass after cleaning
  if clean, !update {
   guard let project else {
    print("nothing to do for \(binaryName)")
    exit(0)
   }

   let tag = try project.overwrite(at: ".modified")
   try tag.write(Date.now.timeIntervalSinceReferenceDate.description)

   var deleted = false
   // TODO: remove specific build folder
   if let folder = try? project.subfolder(named: ".build") {
    guard
     let targets = folder.subfolders.recursive.map(
      where: { !$0.isSymbolicLink && $0.name == (testable ? "debug" : "release")
      }
     )
    else { return }
    for folder in targets.uniqued(on: \.path) {
     do {
      try folder.delete()
      print("removed \(folder.name) build folder from cache")
      deleted = true
     } catch { continue }
    }
   }

   if let binary = try? project.file(named: executable) {
    try binary.delete()
    print("removed \(executable) from cache")
    deleted = true
   }

   if deleted { print("cleaned \(binaryName)") } else {
    print("nothing to do for \(binaryName)")
   }

   exit(0)
  } else if remove || clean && update {
   guard let project else {
    print("nothing to remove for \(binaryName)")
    exit(0)
   }

   do {
    try project.delete()
    print("removed \(binaryName) from cache")
    exit(0)
   } catch { exit(error) }
  } else if update {
   guard let project else { return }

   let tag = try project.overwrite(at: ".modified")
   try tag.write(Date.now.timeIntervalSinceReferenceDate.description)
  }
 }
 
 func initialize() throws {
  // the working directory, which changes after parsing the file
  // so it's stored here to be ran with the executable
  let initial = Folder.current

  let (codes, dependencies) = try file.parse(testing: testable)
  var manifest: String = .manifest(with: dependencies, libraryName, binaryName)

  if enabled.notEmpty || flags.notEmpty {
   manifest.append(
    """
    \nlet target = \
    package.targets.first(where: { $0.name == \"\(binaryName)\" })!
    target.swiftSettings = []
    """
   )
  }

  if enabled.notEmpty {
   manifest.append(
    """
    \ntarget.swiftSettings! += [
    \(
     enabled.map { "  .enableExperimentalFeature(\"\($0)\")" }
      .joined(separator: .comma + .newline)
    )
    ]
    """
   )
  }

  if flags.notEmpty {
   manifest.append(
    """
    \ntarget.swiftSettings! += [
     .unsafeFlags([
    \(flags.map { "  \"-\($0)\"" }.joined(separator: .comma + .newline))
     ])
    ]
    """
   )
  }

  let project = try cache.createSubfolderIfNeeded(at: buildFolder)

  // MARK: - Process script
  do {
   let package = try project.overwrite(at: "Package.swift")
   try package.write(manifest)

   //  try project.overwrite(at: mainPath)
   try project.overwrite(at: "main.swift", contents: codes.data(using: .utf8)!)
   // try process(.ln, with: "-fsn", file.path, project.path + mainPath)

   let tag = try project.overwrite(at: ".modified")
   try tag.write(modified.timeIntervalSinceReferenceDate.description)

   if shouldOpen {
    #if os(macOS)
    package.open()
    exit(0)
    #else
    exit(1, "unable to open package on this operating system")
    #endif
   }

   // MARK: - Build and run script
   let command = ["build"] + ["--product", binaryName]

   let defaults =
    testable ? .empty : ["-c", "release"] + ["-Xcc", "-Ofast", "-Xswiftc", "-O"]
   var arguments = command + defaults

   if let toolchain {
    arguments += ["--toolchain", toolchain]
   }

   // set current directory to use with swift
   project.set()

   if silent {
    // TODO: output errors, some don't carry because I'm not reading stderr
    do {
     try processOutput(.swift, with: arguments)
    } catch let error as ShellError {
     print(error.outputData.asciiOutput())
     throw _POSIXError.termination(error.terminationStatus)
    } catch {
     throw error
    }
   } else {
    try process(.swift, with: arguments)
   }

   let outputArguments = arguments + ["--show-bin-path"]
   let binPath = try processOutput(.swift, with: outputArguments)

   let binFolder = try Folder(path: binPath)
   guard let binary = try? binFolder.file(at: binaryName) else { return }

   try binary.rename(to: executable)

   if let prev = try? project.file(at: executable) {
    try prev.delete()
   }

   try binary.move(to: project)

  } catch let error as _POSIXError {
   // remove expired executable so it can be rebuilt
   if let binary = try? project.file(at: executable) { try binary.delete() }

   exit(error.status)
  } catch { exit(error) }

  let path = project.path + executable

  initial.set()
  if shouldPrint {
   print(path)
  } else {
   // execute script with input file.swift removed
   try execv(path, arguments)
  }
 }
} catch {
 exit(error)
}

// MARK: - Extensions
extension String {
 @inlinable
 static func manifest(
  with dependencies: [(product: String, package: String)],
  _ libraryName: String, _ binaryName: String
 ) -> Self {
  // parse file and add dependencies to the package file
  // compile for operating system and get supported platform versions
  #if os(macOS)
  let platform =
   ".macOS(\"\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)\")"
  return
   """
   // swift-tools-version:5.9
   import PackageDescription

   let package = Package(
   name: "\(libraryName)", platforms: [\(platform)],
   dependencies: [
   \(dependencies.map { " " + $0.package }.joined(separator: .comma + .newline))
   ],
   targets: [
   .executableTarget(
      name: "\(binaryName)",
      dependencies: [
   \(
    dependencies.map { "    " + $0.product }
     .joined(separator: .comma + .newline)
   )
      ],
      path: "."
     )
    ]
   )
   """
  #else
  return
   """
   // swift-tools-version:5.9
   import PackageDescription

   let package = Package(
   name: "\(libraryName)",
   dependencies: [
   \(dependencies.map { " " + $0.package }.joined(separator: .comma + .newline))
   ],
   targets: [
   .executableTarget(
      name: "\(binaryName)",
      dependencies: [
   \(
    dependencies.map { "    " + $0.product }
     .joined(separator: .comma + .newline)
   )
      ],
      path: "."
     )
    ]
   )
   """
  #endif
 }
}
