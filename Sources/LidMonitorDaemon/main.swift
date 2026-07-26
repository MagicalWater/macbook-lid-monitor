import Darwin
import LidMonitorCore

exit(LidMonitorProductionDaemonEntryPoint.run(arguments: Array(CommandLine.arguments.dropFirst())))
