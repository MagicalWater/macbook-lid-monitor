import Darwin
import LidMonitorCore

exit(LidMonitorDaemonSpikeEntryPoint.run(arguments: Array(CommandLine.arguments.dropFirst())))
