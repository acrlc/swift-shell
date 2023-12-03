extension String {
 var lowercaseFirst: String {
  var copy = self
  return Self(copy.removeFirst().lowercased() + copy)
 }

 var uppercaseFirst: String {
  var copy = self
  return Self(copy.removeFirst().uppercased() + copy)
 }
}
