import Shell

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
