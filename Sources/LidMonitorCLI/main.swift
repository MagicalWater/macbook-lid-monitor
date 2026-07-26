import Darwin
import LidMonitorCore

exit(LidMonitorCLIEntryPoint.run(arguments: Array(CommandLine.arguments.dropFirst())))
