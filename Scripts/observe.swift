#!/usr/bin/env swift-shell
import Command // @git/acrlc/command
import PathObserver // @git/acrlc/paths

/// A single file observer, useful for scripts
///
/// # Current Limitations
/// - macOS only
/// - doesn't exit when a file is deleted
/// - Parameters:
///  - open: Open the file when observing
///  - updateInterval: Update interval formatted as `numberUnit` or `0.78s`
///  - input: Path of the file to observe
///  - arguments: Command line arguments to run when the file is modified.
///   The sequence `{}` is used a substitution for the input file
/// #### Example
///   ```sh
///   # executing a file in the command line after modifying
///   # -o, opens the file
///   # -u 7.77e7ns, updates every 0.78 seconds
///   # -i input.sh, the input file to observe
///   observe -o -u 7.77e7ns -i input.sh ./{}
///   ```
///
@main
struct Observe: AsyncCommand {
 @Flag
 var open: Bool
 @Flag
 var clear: Bool
 @Option
 var updateInterval: Duration?
 @Option
 var input: File?
 @Inputs
 var arguments: [String] = ["./{}"]

 func main() async {
  guard let input else { exit(2, "input <file> required") }
  guard arguments.notEmpty else { exit(1, "missing input <command>") }
  if open { input.open() }

  let interval =
   updateInterval == nil ? nil : UInt64(updateInterval!.nanoseconds)

  let observer = FileObserver(input, interval: interval)

  let _command = arguments[0]
  let command =
   _command.contains("{}") ?
   _command.replacingOccurrences(of: "{}", with: input.name) :
   _command

  let _arguments = arguments[1...].map { $0 }
  let arguments =
   _arguments.contains(where: { $0.contains("{}") }) ?
   _arguments.map { $0.replacingOccurrences(of: "{}", with: input.path) } :
   _arguments

  func clearOutput() throws {
   try process(command: "clear")
   try process(command: "printf", [#"\e[3J"#])
  }

  func run(initial: Bool = false) async {
   do {
    let completionMarker = "\(">", style: .dim)"
    if initial {
     if clear { try clearOutput() }
     try process(command: command, arguments)
     print(completionMarker)
    }

    try await observer { _, _, _ in
     if clear { try clearOutput() }
     else {
      Shell.clearScrollback()
      print(">>")
     }

     try process(command: command, arguments)
     print(completionMarker)
    }

   } catch {
    let status = error._code
    switch status {
    case 127, 4:
     // 127 No such file or directory / command not found
     // 4 fatalError
     exit(Int32(status))
    default:
     print(
      """
      \(">", color: status == 1 ? .red : .yellow) \
      \(command)\(arguments.joined(separator: .space)) \
      ended with status \(status)
      """
     )
    }
   }
   await run()
  }

  await run(initial: true)
  exit(2, "\nFile no longer exists")
 }
}
