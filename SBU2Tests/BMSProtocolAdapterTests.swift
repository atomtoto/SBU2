//
//  BMSProtocolAdapterTests.swift
//  SBU2Tests
//

import CoreBluetooth
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
        let commands = JBDAdapter().mosCommands(terminal: .charge,
                                                charge: false, discharge: true, password: nil)
        #expect(commands.map(\.bytes) == [JBD.openFactoryMode,
                                          JBD.mosControl(charge: false, discharge: true),
                                          JBD.closeFactoryMode])
        // Only the last command survives a rejection, so factory mode is closed again.
        #expect(commands.map(\.isCleanup) == [false, false, true])
    }

    @Test("Both terminals ride in one write, so which one was touched changes nothing")
    func jbdIgnoresTheTerminal() {
        let adapter = JBDAdapter()
        let viaCharge = adapter.mosCommands(terminal: .charge,
                                            charge: false, discharge: true, password: nil)
        let viaDischarge = adapter.mosCommands(terminal: .discharge,
                                               charge: false, discharge: true, password: nil)
        #expect(viaCharge.map(\.bytes) == viaDischarge.map(\.bytes))
    }

    @Test("A protected pack is unlocked first")
    func mosBracketWithPassword() {
        let commands = JBDAdapter().mosCommands(terminal: .discharge,
                                                charge: true, discharge: true, password: "123456")
        #expect(commands.count == 4)
        #expect(commands.first?.bytes == JBD.enterPassword("123456"))
    }

    @Test("Clearing the alerts is an empty factory bracket that commits on the way out")
    func clearAlertsBracket() {
        let commands = JBDAdapter().clearAlertsCommands(password: nil)
        #expect(commands.map(\.bytes) == [JBD.openFactoryMode, JBD.saveAndCloseFactoryMode])
        // The committing write doubles as the factory-mode close, so it has to survive
        // a refusal of the open the way a plain close does.
        #expect(commands.map(\.isCleanup) == [false, true])
        #expect(commands.last?.expectedRegister == JBD.Register.factoryModeClose.rawValue)
    }

    @Test("A protected pack is unlocked before its alerts are cleared")
    func clearAlertsWithPassword() {
        let commands = JBDAdapter().clearAlertsCommands(password: "123456")
        #expect(commands.count == 3)
        #expect(commands.first?.bytes == JBD.enterPassword("123456"))
    }

    @Test("Committing on exit is the close register carrying 0x2828, not 0x0000")
    func saveAndCloseFrame() {
        #expect(JBD.saveAndCloseFactoryMode == [0xDD, 0x5A, 0x01, 0x02, 0x28, 0x28, 0xFF, 0xAD, 0x77])
        #expect(JBD.saveAndCloseFactoryMode != JBD.closeFactoryMode)
    }

    @Test("A cell calibration writes the millivolts to that cell's own register")
    func cellCalibrationFrame() {
        // 0xB0 is cell 1, and 3300 mV is 0x0CE4.
        #expect(JBD.calibrateCell(index: 0, millivolts: 3300)
                == [0xDD, 0x5A, 0xB0, 0x02, 0x0C, 0xE4, 0xFE, 0x5E, 0x77])
        // Cell 32 is the last one there is a register for.
        #expect(JBD.calibrateCell(index: 31, millivolts: 3300)?[JBD.registerIndex] == 0xCF)
        #expect(JBD.calibrateCell(index: 32, millivolts: 3300) == nil)
    }

    @Test("A temperature calibration writes tenths of a kelvin, the scale readings use")
    func temperatureCalibrationFrame() {
        // 25.05 °C is 2982 tenths of a kelvin, 0x0BA6 — the very bytes the
        // basic-information frame above carries for that same temperature.
        #expect(JBD.calibrateTemperature(index: 0, celsius: 25.05)
                == [0xDD, 0x5A, 0xD0, 0x02, 0x0B, 0xA6, 0xFE, 0x7D, 0x77])
        #expect(JBD.calibrateTemperature(index: 7, celsius: 25)?[JBD.registerIndex] == 0xD7)
        #expect(JBD.calibrateTemperature(index: 8, celsius: 25) == nil)
    }

    @Test("A current calibration writes hundredths of an amp, unsigned either way")
    func currentCalibrationFrames() {
        #expect(JBD.calibrateCurrent(charging: true, amperes: 10)?[JBD.registerIndex] == 0xAE)
        #expect(JBD.calibrateCurrent(charging: false, amperes: 10)?[JBD.registerIndex] == 0xAF)
        // A discharge reads negative on screen; the register takes the magnitude, so
        // a firmware treating the word as unsigned cannot read it as hundreds of amps.
        #expect(JBD.calibrateCurrent(charging: false, amperes: -10)
                == JBD.calibrateCurrent(charging: false, amperes: 10))
        #expect(JBD.calibrateIdleCurrent[JBD.registerIndex] == 0xAD)
    }

    @Test("Only the current gain is committed to EEPROM, as the reference does it")
    func calibrationTerminators() {
        let adapter = JBDAdapter()
        let cell = adapter.calibrationCommands(.cell(index: 0, millivolts: 3300), password: nil)
        #expect(cell.last?.bytes == JBD.closeFactoryMode)

        let charge = adapter.calibrationCommands(.chargeCurrent(amperes: 10), password: nil)
        #expect(charge.last?.bytes == JBD.saveAndCloseFactoryMode)

        // Whatever ends the bracket has to be sent even when the open was refused.
        #expect(cell.last?.isCleanup == true)
        #expect(charge.last?.isCleanup == true)
    }

    @Test("A figure no pack could read never reaches the BMS")
    func implausibleCalibrationsRefused() {
        let adapter = JBDAdapter()
        // A missed decimal point, an empty-looking zero, a nonsense temperature, a
        // current past what the register even holds.
        let refused: [BMSCalibration] = [.cell(index: 0, millivolts: 33000),
                                         .cell(index: 0, millivolts: 0),
                                         .temperature(index: 0, celsius: 900),
                                         .chargeCurrent(amperes: 5000),
                                         .dischargeCurrent(amperes: 0)]
        for calibration in refused {
            #expect(!calibration.isPlausible)
            #expect(adapter.calibrationCommands(calibration, password: nil).isEmpty)
        }
        // And the ones that make sense do go out.
        #expect(BMSCalibration.cell(index: 0, millivolts: 3300).isPlausible)
        #expect(BMSCalibration.idleCurrent.isPlausible)
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

@Suite("Balancing")
struct BalancingTests {

    @Test("A pack that names its balancing cells is described by naming them")
    func namedCells() {
        // JBD's way: which cells, never how much.
        var info = BasicInfo()
        info.balancingCells = [1]
        #expect(info.isBalancing)
        #expect(info.balancingText == "Cell 2")

        info.balancingCells = [1, 4]
        #expect(info.balancingText == "Cells 2, 5")
    }

    @Test("A pack that only says how hard it is working is described that way")
    func currentOnly() {
        // JK's way: how much, never which.
        var info = BasicInfo()
        info.balancerActive = true
        info.balanceCurrent = 0.3
        #expect(info.isBalancing)
        #expect(info.balancingText.hasSuffix("A"))

        // Working but shunting nothing worth printing.
        info.balanceCurrent = 0
        #expect(info.isBalancing)
        #expect(info.balancingText == "Balancing")
    }

    @Test("A pack doing neither says nothing")
    func idle() {
        let info = BasicInfo()
        #expect(!info.isBalancing)
    }
}

@Suite("Protocol registry")
struct BMSProtocolRegistryTests {

    @Test("Every family's service is listed once")
    func identifyingServices() {
        let services = BMSProtocolRegistry.identifyingServices
        #expect(services.count == Set(services).count)
        #expect(services.contains(JBDAdapter.descriptor.profile.service))
    }

    @Test("A device no family recognises is not one of ours")
    func matchesNothing() {
        // The scan is unfiltered, so everything in radio range is offered up. A
        // matcher that answered anything here would fill the list with headphones.
        #expect(BMSProtocolRegistry.match(advertisement: [:], name: nil) == nil)
        #expect(BMSProtocolRegistry.match(advertisement: [:], name: "AirPods Pro") == nil)
        #expect(BMSProtocolRegistry.match(
            advertisement: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "180D")]],
            name: "Heart Rate Monitor") == nil)
    }

    @Test("Naming a family anyway falls back rather than refusing")
    func fallback() {
        let descriptor = BMSProtocolRegistry.descriptor(advertisement: [:], name: nil)
        #expect(descriptor.id == BMSProtocolRegistry.fallback.id)
    }

    @Test("A stored identifier resolves to its family")
    func lookupByID() {
        #expect(BMSProtocolRegistry.descriptor(for: .jbd).id == .jbd)
        #expect(BMSProtocolRegistry.descriptor(for: .jk).id == .jk)
    }

    @Test("Both families are identifiable by their own service")
    func bothIdentifiable() {
        let services = BMSProtocolRegistry.identifyingServices
        #expect(services.contains(JBDAdapter.descriptor.profile.service))
        #expect(services.contains(JKAdapter.descriptor.profile.service))
    }

    @Test("A JBD dongle is recognised by its service and nothing else is taken for one")
    func jbdIsRecognisedStrictly() {
        let jbd = BMSProtocolRegistry.match(
            advertisement: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FF00")]],
            name: nil)
        #expect(jbd?.id == .jbd)

        // This used to be claimed as JBD, back when the scan filter meant anything
        // reaching the matcher was already one. Unfiltered, that same answer would
        // take every device in the building — and would take a JK pack before JK ever
        // saw it.
        #expect(BMSProtocolRegistry.match(advertisement: [:], name: "Some BMS") == nil)
    }

    @Test("A JK pack that lists its service only in the scan response is still found")
    func jkFromOverflow() {
        let overflow = BMSProtocolRegistry.match(
            advertisement: [CBAdvertisementDataOverflowServiceUUIDsKey: [CBUUID(string: "FFE0")]],
            name: nil)
        #expect(overflow?.id == .jk)
    }

    @Test("Each family claims its own and leaves the other alone")
    func familiesDoNotStealEachOther() {
        let jk = BMSProtocolRegistry.descriptor(
            advertisement: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FFE0")]],
            name: "JK-B2A16S")
        #expect(jk.id == .jk)

        let jbd = BMSProtocolRegistry.descriptor(
            advertisement: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FF00")]],
            name: "xiaoxiang BMS")
        #expect(jbd.id == .jbd)
    }

    @Test("A JK pack is recognised by either its service or its name")
    func jkRecognisedEitherWay() {
        // No name in the advertisement, which is common enough.
        let byService = BMSProtocolRegistry.descriptor(
            advertisement: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FFE0")]],
            name: nil)
        #expect(byService.id == .jk)

        // Services in the scan response rather than the advertisement, which is also
        // common — the name is all there is to go on.
        let byName = BMSProtocolRegistry.descriptor(advertisement: [:], name: "JK_PB2A16S15P")
        #expect(byName.id == .jk)
    }

    @Test("JK and JBD talk over different characteristics, and JK over only one")
    func profiles() {
        let jk = JKAdapter.descriptor.profile
        // One characteristic both ways, which the GATT discovery has to allow for.
        #expect(jk.notify == jk.write)

        let jbd = JBDAdapter.descriptor.profile
        #expect(jbd.notify != jbd.write)
        #expect(jk.service != jbd.service)
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
