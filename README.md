#### Run code and execute tests, quickly and without opening a package or project
### Install
using [swift-install](https://github.com/acrlc/swift-install)
```sh
cd swift-shell && swift install
```
using make
```sh
cd swift-shell && make
```

### Usage
```
swift-shell (or swift shell)

example: 
	swift-shell <options> <filename> <arguments>
	
options:
	-t, --testable: 
		run with debug configuration and allow @testable imports
	-u, --update: 
		rebuild manually, without modifying the input
	-c, --clean: 
		remove the build folder and binaries associated with the input
	-r, --remove: 
		remove the input project from cache
	-e, --enable <feature1,feature2>:
		enable experimental features separated by a comma without spaces
notes: 	
	only supports a single option name or combined flags
	using combined flags -u and -c will remove the project from cache
	create a symbolic link if you would like to use swift-sh or swift sh
	
cache: derived data folder or ~/library/developer/.swift.shell.cache
```

#### Known limitations 
- There can only be one combined flag, because it would limit the ability to read input arguments

#### Feature overview
- Package imports with git support and environment variable expansion
- Options for debugging, clearing and updating from cache
- Ability to support experimental features with the `enable` option

### Basic Examples
#### Run a command
Create a swift file with the following contents
```swift
#!/usr/bin/env swift-shell 
// tip: `swift` can expand `swift shell` to be read as `swift-shell`

let str = "Hello, World!"
print(str) // hey, something just happened
```
Then allow the file to be executed or run `swift-shell <filename>`
```sh
chmod +x hello.swift
./hello.swift
```
#### Import dependencies
Add URL dependency
```swift
import Shell // @git/acrlc/shell
// @git or @github expands to https://github.com/acrlc/shell
```
URL dependency with branch specified
```swift
import Shell // @git:main/acrlc/shell
// sets the branch to main, which is the default
```
Add path dependency
```swift
import AsyncAlgorithms // ~/path/to/apple/swift-async-algorithms
import Other // $main/path/to/other/package
import Package // ..
```
