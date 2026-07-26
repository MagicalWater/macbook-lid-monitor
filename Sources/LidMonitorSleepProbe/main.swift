import Darwin
import LidMonitorCore

exit(LidMonitorSleepProbeEntryPoint.run(arguments: Array(CommandLine.arguments.dropFirst())))
