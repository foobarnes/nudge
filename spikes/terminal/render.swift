// Spike 3: minimal ActionTemplate shell rendering per the spec (env-var injection design).
// usage: swift render.swift <template> <title> <url>  -> prints path of a 0700-dir script
import Foundation

func sq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

let args = CommandLine.arguments
let (template, title, url) = (args[1], args[2], args[3])
let values = ["TITLE": title, "URL": url, "REPO": "acme/api", "OWNER": "acme", "NAME": "api",
              "NUMBER": "4211", "BRANCH": "fix-refresh"]
var body = template
for key in values.keys { body = body.replacingOccurrences(of: "{\(key.lowercased())}", with: "${NUDGE_PR_\(key)}") }

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-spike-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
var script = "trap 'rm -f \"$0\"' EXIT\n"
for (k, v) in values.sorted(by: { $0.key < $1.key }) { script += "export NUDGE_PR_\(k)=\(sq(v))\n" }
script += body + "\n"
let file = dir.appendingPathComponent("action.zsh")
try script.write(to: file, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
print(file.path)
