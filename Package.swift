// swift-tools-version:5.5
import PackageDescription

let package = Package(
 name: "swift-shell",
 platforms: [.macOS(.v12)],
 products: [.executable(name: "swift-shell", targets: ["swift-shell"])],
 dependencies: [
  .package(url: "https://github.com/acrlc/shell.git", branch: "main")
 ],
 targets: [
  .executableTarget(
   name: "swift-shell",
   dependencies: [.product(name: "Shell", package: "shell")],
   path: "Sources"
  )
 ]
)

#if os(Linux) || os(Windows)
// add OpenCombine for framewords that depend on Combine functionality
package.dependencies.append(
 .package(url: "https://github.com/apple/swift-crypto.git", from: "3.1.0")
)
for target in package.targets {
 if target.name == "swift-shell" {
  target.dependencies += [
   .product(
    name: "Crypto",
    package: "swift-crypto",
    condition: .when(platforms: [.windows, .linux, .wasi])
   )
  ]
  break
 }
}
#endif
