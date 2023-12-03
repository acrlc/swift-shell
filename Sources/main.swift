import Shell
import Core
#if os(Windows) || os(Linux)
import enum Crypto.Insecure
#else
import enum CryptoKit.Insecure
#endif

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
/*
 considering an install or copy function
 static var install: Bool = false
 static var copy: Bool = false
 */
// TODO: add option to prune projects that no longer exist
var arguments = CommandLine.arguments[1...].map { $0 }

let home: Folder = .home
var developer: Folder {
 get throws {
  try (try? home.subfolder(at: "Developer")) ??
   home.subfolder(at: "Library/Developer")
 }
}

var cache: Folder {
 get throws {
  guard let derivedData = try? developer.subfolder(at: "Xcode/DerivedData")
  else {
   return try developer.createSubfolderIfNeeded(at: ".swift.shell.cache")
  }
  return derivedData
 }
}

// TODO: bookmark files and change hashed path when necessary
// TODO: map dependencies and check for updates on remote dependencies
// to the project.swift file
// if modified it should rebuild the package file, which adds the dependencies
guard arguments.notEmpty else {
 exit(1, "missing paramters:\n\t[<option> or [-flags]] <filename> <arguments>")
}

parse()

let input = arguments.removeFirst()
let file = try File(path: input).withRealPath()

let hashedPath = file.path.lowercased().hash(with: Insecure.MD5.self)

let scriptName = file.name
let name = file.nameExcludingExtension
let libraryName = name.uppercaseFirst
let binaryName = name.lowercaseFirst
let buildFolder = "\(binaryName)-\(hashedPath)"
let project = try? cache.subfolder(at: buildFolder)
let executable = (testable ? binaryName + "-testable" : binaryName)

try check(project, file, binaryName, executable)

let modified = file.modificationDate ?? .now

if let project,
   project.containsFile(at: "Package.swift"),
   project.containsFile(at: executable),
   let interval =
   try? TimeInterval(project.file(at: ".modified").readAsString()),
   // check modification interval
   modified == Date(timeIntervalSinceReferenceDate: interval) {
 do {
  let path = project.path + executable
  try exec(path, with: arguments)
 }
 catch { throw error }
}
else { try initialize() }

// MARK: - Functions
func parse() {
 if arguments[0].hasPrefix("-"), arguments.count > 1 {
  // FIXME: edge case where "-" can be used as an input
  // by checking when a flag is set, then asserting
  // so the first argument (which could be a filename) isn't removed
  let argument = arguments.removeFirst().drop(while: { $0 == "-" })

  func enableFeatures() -> [String] {
   guard arguments.count > 1 else { return .empty }
   return arguments
    .removeFirst()
    .split(separator: .comma)
    .joined(separator: .space)
    .split(separator: .space)
    .map(String.init)
  }

  switch argument {
  case "clean": clean = true
  case "remove": remove = true
  case "testable": testable = true
  case "update": update = true
  case "enable": enabled = enableFeatures()
  default:
   // FIXME: ensure arguments pass sanity test
   for char in argument {
    switch char {
    case "c": clean = true
    case "r": remove = true
    case "t": testable = true
    case "u": update = true
    case "e": enabled = enableFeatures()
    default: exit(1, "unknown flag at character: \(char)")
    }
   }
  }
 }
}

func check(
 _ project: Folder?,
 _ file: File,
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
   guard let targets = folder.subfolders.recursive.map(
    where: { !$0.isSymbolicLink && $0.name == (testable ? "debug" : "release") }
   )
   else { return }
   for folder in targets.uniqued(on: \.path) {
    do {
     try folder.delete()
     print("removed \(folder.name) build folder from cache")
     deleted = true
    }
    catch { continue }
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
  }
  catch { exit(error) }
 } else if update {
  guard let project else { return }

  let tag = try project.overwrite(at: ".modified")
  try tag.write(Date.now.timeIntervalSinceReferenceDate.description)
 }
}
