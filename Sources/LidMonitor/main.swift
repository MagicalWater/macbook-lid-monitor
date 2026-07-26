import Foundation

do {
    let options = try CLIParser.parse(Array(CommandLine.arguments.dropFirst()))
    let environment = RuntimeEnvironment.current()
    let mode = options.mode == .list ? "list" : "watch"
    print("macbook-lid-monitor \(environment.appVersion) mode=\(mode)")
} catch let error as CLIParseError {
    FileHandle.standardError.write(Data("usage error: \(error)\n".utf8))
    exit(ExitCode.usage.rawValue)
} catch {
    FileHandle.standardError.write(Data("internal error: \(error)\n".utf8))
    exit(ExitCode.internalError.rawValue)
}
