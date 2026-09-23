import Testing

struct SimulatorServiceTests {
    @Test func explainsUnauthorizedPush() {
        let output = """
        An error was encountered processing the command (domain=UNErrorDomain, code=2003):
        Simulator device failed to complete the requested operation.
        Underlying error (domain=UNErrorDomain, code=2003):
        \tRepository could not save notification. Source is not authorized.
        """

        #expect(SimulatorService.conciseMessage(output).hasPrefix("The app isn’t allowed to show notifications."))
    }

    @Test func keepsTheInnermostUnderlyingError() {
        let output = """
        An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):
        Unable to lookup in current state: Shutdown
        Underlying error (domain=NSPOSIXErrorDomain, code=22):
        \tInvalid argument
        """

        #expect(SimulatorService.conciseMessage(output) == "Invalid argument")
    }

    @Test func extractsTheReasonFromACrash() {
        let output = """
        *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'Invalid domain=nil'
        *** First throw call stack:
        (
        \t0   CoreFoundation   0x00000001840ae8c0 __exceptionPreprocess + 176
        )
        """

        #expect(SimulatorService.conciseMessage(output) == "simctl crashed: Invalid domain=nil")
    }

    @Test func shortensPlainOutput() {
        #expect(SimulatorService.conciseMessage("one\ntwo") == "one\ntwo")
        #expect(SimulatorService.conciseMessage("1\n2\n3\n4\n5") == "1\n2\n3…")
    }
}
