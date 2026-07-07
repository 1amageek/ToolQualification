import Foundation
import ToolQualificationCLICore

@main
struct ToolQualificationCLIEntry {
    static func main() {
        let exitCode = ToolQualificationCLI.run(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        Foundation.exit(exitCode)
    }
}
