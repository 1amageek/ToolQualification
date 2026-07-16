import Foundation
import ToolQualificationCLICore

@main
struct ToolQualificationCLIEntry {
    static func main() async {
        let exitCode = await ToolQualificationCLI.run(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        Foundation.exit(exitCode)
    }
}
