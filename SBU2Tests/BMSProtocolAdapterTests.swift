//
//  BMSProtocolAdapterTests.swift
//  SBU2Tests
//

import Foundation
import Testing
@testable import SBU2

// The same 4-cell pack the protocol tests use.
private let basicInfoFrame: [UInt8] = [
    0xDD, 0x03, 0x00, 0x1B,
    0x05, 0x2D, 0xFE, 0x0C, 0x11, 0xD0, 0x27, 0x10, 0x00, 0x0C, 0x2C, 0x3C,
    0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x20, 0x2D, 0x03, 0x04, 0x02,
    0x0B, 0xA6, 0x0B, 0x88,
    0xFB, 0x81, 0x77,
]

private let cellVoltageFrame: [UInt8] = [
    0xDD, 0x04, 0x00, 0x08,
    0x0C, 0xF8, 0x0C, 0xF3, 0x0C, 0xF6, 0x0C, 0xFA,
    0xFB, 0xED, 0x77,
]

@Suite("JBD adapter")
struct JBDAdapterTests {

    @Test("A poll asks for the readings one command at a time, each expecting its own answer")
    func pollCommands() {
        let commands = JBDAdapter().pollCommands()
        #expect(commands.count == 2)
        // `map` and not `allSatisfy`: the macro lifts its sub-expressions into
        // closures, and a rethrowing call inside one is treated as throwing.
        #expect(commands.map(\.isPoll) == [true, true])
        #expect(commands[0].bytes == JBD.readRequest(.basicInfo))
        #expect(commands[0].expectedRegister == JBD.Register.basicInfo.rawValue)
        #expect(commands[1].bytes == JBD.readRequest(.cellVoltages))
        #expect(commands[1].expectedRegister == JBD.Register.cellVoltages.rawValue)
    }

    @Test("An unprotected pack gets the bracket without a password replay")
    func mosBracketWithoutPassword() {
        let commands = JBDAdapter().mosCommands(charge: false, discharge: true, password: nil)
        #expect(commands.map(\.bytes) == [JBD.openFactoryMode,
                                          JBD.mosControl(charge: false, discharge: true),
                                          JBD.closeFactoryMode])
        // Only the last command survives a rejection, so factory mode is closed again.
        #expect(commands.map(\.isCleanup) == [false, false, true])
    }

    @Test("A protected pack is unlocked first")
    func mosBracketWithPassword() {
        let commands = JBDAdapter().mosCommands(charge: true, discharge: true, password: "123456")
        #expect(commands.count == 4)
        #expect(commands.first?.bytes == JBD.enterPassword("123456"))
    }

    @Test("Clearing the alerts opens factory mode and wipes on the way out")
    func clearAlertsBracket() {
        let commands = JBDAdapter().clearAlertsCommands(password: nil)
        #expect(commands.map(\.bytes) == [JBD.openFactoryMode, JBD.clearErrorCounts])
        // The wipe doubles as the factory-mode close, so it has to survive a refusal
        // of the open the way a plain close does.
        #expect(commands.map(\.isCleanup) == [false, true])
        #expect(commands.last?.expectedRegister == JBD.Register.factoryModeClose.rawValue)
    }

    @Test("A protected pack is unlocked before its alerts are cleared")
    func clearAlertsWithPassword() {
        let commands = JBDAdapter().clearAlertsCommands(password: "123456")
        #expect(commands.count == 3)
        #expect(commands.first?.bytes == JBD.enterPassword("123456"))
    }

    @Test("Clearing the alerts is the close register carrying 0x2828, not 0x0000")
    func clearErrorCountsFrame() {
        #expect(JBD.clearErrorCounts == [0xDD, 0x5A, 0x01, 0x02, 0x28, 0x28, 0xFF, 0xAD, 0x77])
        #expect(JBD.clearErrorCounts != JBD.closeFactoryMode)
    }

    @Test("A malformed password produces no commands at all")
    func malformedPassword() {
        let adapter = JBDAdapter()
        #expect(adapter.createPasswordCommands("12345").isEmpty)
        #expect(adapter.changePasswordCommands(from: "123456", to: "abc").isEmpty)
        #expect(adapter.removePasswordCommands(current: "").isEmpty)
    }

    @Test("Readings are decoded and tagged with the register that answered")
    func decodesReadings() {
        let adapter = JBDAdapter()
        let events = adapter.ingest(Data(basicInfoFrame + cellVoltageFrame))
        #expect(events.count == 2)
        #expect(events[0].register == JBD.Register.basicInfo.rawValue)
        #expect(events[1].register == JBD.Register.cellVoltages.rawValue)

        guard case .basicInfo(let info) = events[0].kind else {
            Issue.record("expected a basic-information event")
            return
        }
        #expect(info.stateOfCharge == 45)

        guard case .cellVoltages(let voltages) = events[1].kind else {
            Issue.record("expected a cell-voltage event")
            return
        }
        #expect(voltages.count == 4)
    }

    @Test("A refused factory-mode write is reported as rejected")
    func factoryModeRejected() {
        let events = JBDAdapter().ingest(Data([0xDD, 0x00, 0x80, 0x00, 0x00, 0x00, 0x77]))
        #expect(events.count == 1)
        #expect(events.first?.kind == .rejected)
    }

    @Test("A refused password is reported separately from a refused write")
    func passwordRejected() {
        let events = JBDAdapter().ingest(Data([0xDD, 0x07, 0x84, 0x00, 0xFF, 0x7C, 0x77]))
        #expect(events.first?.kind == .passwordRejected)
    }

    @Test("A write the pack accepted")
    func writeAccepted() {
        let events = JBDAdapter().ingest(Data([0xDD, 0xE1, 0x00, 0x00, 0x00, 0x00, 0x77]))
        #expect(events.first?.register == JBD.Register.mosControl.rawValue)
        #expect(events.first?.kind == .accepted)
    }

    @Test("reset() drops a half-received answer")
    func resetDropsPartialFrame() {
        let adapter = JBDAdapter()
        #expect(adapter.ingest(Data(basicInfoFrame.prefix(20))).isEmpty)
        adapter.reset()
        #expect(adapter.ingest(Data(cellVoltageFrame)).count == 1)
    }
}

@Suite("Protocol registry")
struct BMSProtocolRegistryTests {

    @Test("Every family is scanned for, each service listed once")
    func scanServices() {
        let services = BMSProtocolRegistry.scanServices
        #expect(services.count == Set(services).count)
        #expect(services.contains(JBDAdapter.descriptor.profile.service))
    }

    @Test("An unrecognised advertisement falls back rather than dropping the device")
    func fallback() {
        let descriptor = BMSProtocolRegistry.descriptor(advertisement: [:], name: nil)
        #expect(descriptor.id == BMSProtocolRegistry.fallback.id)
    }

    @Test("A stored identifier resolves to its family")
    func lookupByID() {
        #expect(BMSProtocolRegistry.descriptor(for: .jbd).id == .jbd)
    }
}

@Suite("Stream recovery")
struct FrameAssemblerRecoveryTests {

    private let start = Date(timeIntervalSince1970: 1_000)

    @Test("A truncated answer is abandoned instead of blocking every later one")
    func staleFrameIsDropped() {
        var assembler = FrameAssembler()
        // A chunk lost on a weak link: the header promises bytes that never arrive.
        #expect(assembler.append(Data(basicInfoFrame.prefix(20)), at: start).isEmpty)

        let later = start.addingTimeInterval(FrameAssembler.staleAfter + 0.1)
        #expect(assembler.append(Data(cellVoltageFrame), at: later) == [cellVoltageFrame])
    }

    @Test("A frame still arriving is not abandoned")
    func partialFrameWithinDeadlineSurvives() {
        var assembler = FrameAssembler()
        #expect(assembler.append(Data(basicInfoFrame.prefix(20)), at: start).isEmpty)

        let soon = start.addingTimeInterval(0.2)
        #expect(assembler.append(Data(basicInfoFrame.dropFirst(20)), at: soon) == [basicInfoFrame])
    }
}
