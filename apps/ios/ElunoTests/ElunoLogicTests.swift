import XCTest

// Compiled directly with Protocol.swift and TransferLogic.swift, so these run without the app or signing.

private let pin = String(repeating: "ab", count: 32)

private func invitationText(v: Int = 1, endpoints: [String] = ["https://192.168.1.20:4443"], fingerprint: String = pin, code: String = "123456", expiresAt: Double = 4_000_000_000_000) throws -> String {
    let invite = Invitation(v: v, endpoints: endpoints, fingerprint: fingerprint, code: code, expiresAt: expiresAt)
    let encoded = try JSONEncoder().encode(invite).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "eluno://pair?data=\(encoded)"
}

final class InvitationTests: XCTestCase {
    func testAcceptsAValidInvitation() throws {
        let invite = try Invitation.parse(try invitationText())
        XCTAssertEqual(invite.code, "123456")
        XCTAssertEqual(invite.endpoints, ["https://192.168.1.20:4443"])
    }

    func testRefusesAnythingThatIsNotAnElunoInvitation() {
        for text in ["https://example.com/pair", "eluno://other?data=e30", "eluno://pair", "not a url at all", ""] {
            XCTAssertThrowsError(try Invitation.parse(text), text)
        }
    }

    func testDamagedPayloadGetsAnActionableMessage() {
        XCTAssertThrowsError(try Invitation.parse("eluno://pair?data=!!!!")) { error in
            XCTAssertTrue(error.localizedDescription.contains("damaged"))
        }
    }

    func testExpiredInvitationSaysToGetAFreshCode() throws {
        let text = try invitationText(expiresAt: 1_000)
        XCTAssertThrowsError(try Invitation.parse(text)) { error in
            XCTAssertEqual(error.localizedDescription, Invitation.expiredMessage)
        }
    }

    func testAnInvitationCanExpireAfterItWasScanned() throws {
        let invite = try Invitation.parse(try invitationText(expiresAt: 2_000_000), now: Date(timeIntervalSince1970: 1_000))
        XCTAssertFalse(invite.isExpired(now: Date(timeIntervalSince1970: 1_999)))
        XCTAssertTrue(invite.isExpired(now: Date(timeIntervalSince1970: 2_000)))
    }

    func testRefusesAnUnsupportedVersionAndBadFields() throws {
        for text in [
            try invitationText(v: 2),
            try invitationText(fingerprint: "abc"),
            try invitationText(code: "12345"),
            try invitationText(endpoints: [])
        ] {
            XCTAssertThrowsError(try Invitation.parse(text))
        }
    }
}

final class EndpointTests: XCTestCase {
    func testAcceptsOnlyHTTPSPrivateIPv4WithAPort() throws {
        for endpoint in ["https://10.0.0.5:4443", "https://172.16.0.1:1", "https://172.31.255.254:65535", "https://192.168.0.1:443"] {
            XCTAssertNoThrow(try Endpoint.validate(endpoint), endpoint)
        }
    }

    func testRefusesEverythingElse() {
        let refused = [
            "http://192.168.1.2:80", "https://192.168.1.2", "https://8.8.8.8:443", "https://172.32.0.1:443",
            "https://127.0.0.1:443", "https://localhost:443", "https://example.com:443", "https://192.168.1.2:443/path",
            "https://192.168.1.2:443?x=1", "https://user:pass@192.168.1.2:443", "https://192.168.01.2:443", "https://192.168.1:443"
        ]
        for endpoint in refused { XCTAssertThrowsError(try Endpoint.validate(endpoint), endpoint) }
    }
}

final class HealthTests: XCTestCase {
    private func report(protocol version: Int = 1, chunk: Int = 262_144, modules: [[String: Any]] = [["id": "transfers", "version": 1], ["id": "save-copy", "version": 1]]) -> [String: Any] {
        ["product": "Eluno", "protocol": version, "chunkBytes": chunk, "modules": modules]
    }

    func testReportsCapabilities() throws {
        let health = try CoordinatorHealth(report())
        XCTAssertTrue(health.supportsCopies)
        XCTAssertTrue(health.supportsSaveCopy)
    }

    func testAnOlderCoordinatorConnectsWithoutOfferingCopies() throws {
        XCTAssertFalse(try CoordinatorHealth(report(modules: [["id": "media", "version": 1]])).supportsCopies)
    }

    func testAnUnknownTransferVersionIsNotOffered() throws {
        XCTAssertFalse(try CoordinatorHealth(report(modules: [["id": "transfers", "version": 2]])).supportsCopies)
    }

    func testRefusesIncompatibleCoordinatorsBeforeRegistering() {
        XCTAssertThrowsError(try CoordinatorHealth(["product": "Other", "protocol": 1, "chunkBytes": 262_144]))
        XCTAssertThrowsError(try CoordinatorHealth(report(protocol: 2)))
        XCTAssertThrowsError(try CoordinatorHealth(report(chunk: 1024)))
        XCTAssertThrowsError(try CoordinatorHealth([:]))
    }
}

final class PairingFailureTests: XCTestCase {
    func testACoordinatorRefusalIsFinalButALostConnectionIsNot() {
        XCTAssertTrue(PairingFailure.isFinal(ElunoError("gone", status: 404)))
        XCTAssertTrue(PairingFailure.isFinal(ElunoError("busy", status: 429)))
        XCTAssertTrue(PairingFailure.isFinal(ElunoError("old", kind: .incompatible)))
        XCTAssertFalse(PairingFailure.isFinal(ElunoError("stale address", status: 403)))
        XCTAssertFalse(PairingFailure.isFinal(ElunoError("lost", kind: .unreachable)))
        XCTAssertFalse(PairingFailure.isFinal(ElunoError("pin", kind: .identityChanged)))
    }

    func testAnExpiredCodeGetsTheFreshCodeMessage() {
        XCTAssertEqual(PairingFailure.message(forFinal: ElunoError("Code expired", status: 404)), Invitation.expiredMessage)
        XCTAssertEqual(PairingFailure.message(forFinal: ElunoError("This session is full.", status: 409)), "This session is full.")
    }

    func testAWrongIdentityOutranksOtherFailures() {
        let lost = ElunoError("lost", kind: .unreachable), denied = ElunoError("denied", kind: .localNetwork), pinned = ElunoError("pin", kind: .identityChanged)
        XCTAssertEqual(PairingFailure.summary([lost, pinned, denied]), PairingFailure.identityMessage)
        XCTAssertEqual(PairingFailure.summary([lost, denied]), PairingFailure.localNetworkMessage)
        XCTAssertEqual(PairingFailure.summary([lost]), PairingFailure.unreachableMessage)
        XCTAssertEqual(PairingFailure.summary([]), PairingFailure.unreachableMessage)
    }

    func testOnlyUnrecoverableErrorsEndASession() {
        XCTAssertTrue(PairingFailure.endsSession(ElunoError("unknown device", status: 401)))
        XCTAssertTrue(PairingFailure.endsSession(ElunoError("pin", kind: .identityChanged)))
        XCTAssertTrue(PairingFailure.endsSession(ElunoError("closed", kind: .disconnected)))
        XCTAssertFalse(PairingFailure.endsSession(ElunoError("wifi", kind: .unreachable)))
        XCTAssertFalse(PairingFailure.endsSession(URLError(.timedOut)))
    }
}

final class ContentRangeTests: XCTestCase {
    func testParsesTheCoordinatorForm() {
        XCTAssertEqual(ContentRange(header: "bytes 10-19/100")?.start, 10)
        XCTAssertEqual(ContentRange(header: "bytes 10-19/100")?.end, 19)
        XCTAssertEqual(ContentRange(header: "bytes 10-19/100")?.total, 100)
        for header in ["bytes */100", "bytes 5-4/100", "bytes 0-100/100", "items 0-1/2", "bytes 0-1", "", "bytes -1-1/2"] {
            XCTAssertNil(ContentRange(header: header), header)
        }
    }

    func testAcceptsOnlyAnExactBoundedResponse() {
        XCTAssertTrue(ContentRange.verifies(status: 206, header: "bytes 10-19/100", bodyCount: 10, requested: 10...19, total: 100))
        XCTAssertFalse(ContentRange.verifies(status: 200, header: "bytes 10-19/100", bodyCount: 10, requested: 10...19, total: 100), "a 200 ignored the range")
        XCTAssertFalse(ContentRange.verifies(status: 206, header: nil, bodyCount: 10, requested: 10...19, total: 100), "no range header")
        XCTAssertFalse(ContentRange.verifies(status: 206, header: "bytes 0-9/100", bodyCount: 10, requested: 10...19, total: 100), "wrong bytes")
        XCTAssertFalse(ContentRange.verifies(status: 206, header: "bytes 10-19/101", bodyCount: 10, requested: 10...19, total: 100), "source changed size")
        XCTAssertFalse(ContentRange.verifies(status: 206, header: "bytes 10-19/100", bodyCount: 9, requested: 10...19, total: 100), "short body")
    }
}

final class ReconcilerTests: XCTestCase {
    func testCompletionOfAPublishedCopyIsAnAcknowledgementNotACancellation() {
        XCTAssertEqual(TransferReconciler.decide(published: true, status: "completed"), .acknowledged)
    }

    func testLiveTransfersAreLeftAlone() {
        for status in ["offered", "receiving", "paused"] {
            XCTAssertEqual(TransferReconciler.decide(published: false, status: status), .keepWorking, status)
            XCTAssertEqual(TransferReconciler.decide(published: true, status: status), .keepWorking, status)
        }
    }

    func testAPublishedCopySurvivesTheTransferEnding() {
        for status in ["cancelled", "declined", nil] as [String?] {
            XCTAssertEqual(TransferReconciler.decide(published: true, status: status), .keepPublishedCopy)
        }
    }

    func testUnpublishedWorkIsDiscardedWhenTheTransferEnds() {
        for status in ["cancelled", "declined", "completed", nil] as [String?] {
            XCTAssertEqual(TransferReconciler.decide(published: false, status: status), .discardIncomplete)
        }
    }
}

final class FileNameTests: XCTestCase {
    func testPathsAndControlCharactersCannotEscapeTheFolder() {
        XCTAssertEqual(FileNames.inboxName("../../etc/passwd"), "Eluno-_.._etc_passwd")
        XCTAssertFalse(FileNames.inboxName("a/b\\c:d\ne").contains("/"))
        XCTAssertFalse(FileNames.inboxName("a/b\\c:d\ne").contains("\n"))
    }

    func testHiddenNamesBecomeVisibleAndCantCollideWithMarkers() {
        XCTAssertEqual(FileNames.inboxName(".eluno.part"), "Eluno-eluno.part")
        XCTAssertEqual(FileNames.inboxName(".photo.jpg"), "Eluno-photo.jpg")
        for name in ["", ".", "..", "   "] { XCTAssertEqual(FileNames.inboxName(name), "Eluno-file", name) }
    }

    func testLongNamesKeepTheirExtensionAndFitTheLimits() {
        let long = FileNames.inboxName(String(repeating: "a", count: 300) + ".mp4")
        XCTAssertTrue(long.hasSuffix(".mp4"))
        XCTAssertLessThanOrEqual(long.utf16.count, Wire.maxNameUnits)
    }

    func testMultibyteNamesFitTheFileSystemWithoutSplittingCharacters() {
        let long = FileNames.inboxName(String(repeating: "😀", count: 100) + ".jpg")
        XCTAssertTrue(long.hasSuffix(".jpg"))
        XCTAssertLessThanOrEqual(long.utf8.count, 240)
        XCTAssertLessThanOrEqual(long.utf16.count, Wire.maxNameUnits)
        XCTAssertTrue(long.dropLast(4).allSatisfy { $0 == "😀" })
    }
}

final class ImportRuleTests: XCTestCase {
    func testAppliesThePhotoCapExactly() {
        XCTAssertNoThrow(try ImportRules.validate(name: "a.png", type: "image/png", size: Wire.maxPhotoBytes))
        XCTAssertThrowsError(try ImportRules.validate(name: "a.png", type: "image/png", size: Wire.maxPhotoBytes + 1))
    }

    func testVideosAndOtherFilesHaveNoPhotoCap() {
        XCTAssertNoThrow(try ImportRules.validate(name: "a.mp4", type: "video/mp4", size: Wire.maxPhotoBytes * 10))
        XCTAssertNoThrow(try ImportRules.validate(name: "a.zip", type: "application/zip", size: Wire.maxPhotoBytes * 10))
    }

    func testRefusesEmptyItems() {
        XCTAssertThrowsError(try ImportRules.validate(name: "a.mp4", type: "video/mp4", size: 0))
    }
}

final class MediaFormatTests: XCTestCase {
    func testOnlyH264AACInMP4IsClaimedAsInteroperable() {
        XCTAssertTrue(MediaFormat.video(mime: "video/mp4", videoCodecs: ["avc1"], audioCodecs: ["aac "]).interoperable)
        XCTAssertTrue(MediaFormat.video(mime: "video/mp4", videoCodecs: ["avc1"], audioCodecs: []).interoperable)
        XCTAssertFalse(MediaFormat.video(mime: "video/quicktime", videoCodecs: ["avc1"], audioCodecs: ["aac "]).interoperable, "MOV container")
        XCTAssertFalse(MediaFormat.video(mime: "video/mp4", videoCodecs: ["hvc1"], audioCodecs: ["aac "]).interoperable, "HEVC")
        XCTAssertFalse(MediaFormat.video(mime: "video/mp4", videoCodecs: ["avc1"], audioCodecs: ["ac-3"]).interoperable, "other audio")
        XCTAssertFalse(MediaFormat.video(mime: "video/mp4", videoCodecs: [], audioCodecs: []).interoperable, "unreadable")
    }

    func testSummaryDescribesWhatWasActuallyReturned() {
        XCTAssertEqual(MediaFormat.video(mime: "video/quicktime", videoCodecs: ["hvc1"], audioCodecs: ["aac "]).summary, "HEVC/AAC MOV")
        XCTAssertEqual(MediaFormat.video(mime: "video/mp4", videoCodecs: ["avc1"], audioCodecs: []).summary, "H.264 MP4")
    }

    func testOnlyJPEGAndPNGPhotosAreClaimedAsInteroperable() {
        XCTAssertTrue(MediaFormat.image(mime: "image/jpeg").interoperable)
        XCTAssertTrue(MediaFormat.image(mime: "image/png").interoperable)
        XCTAssertFalse(MediaFormat.image(mime: "image/heic").interoperable)
        XCTAssertFalse(MediaFormat.image(mime: "image/webp").interoperable)
    }
}

final class ImportTokenTests: XCTestCase {
    func testEachImportIsCancelledIndependently() {
        let first = ImportToken(), second = ImportToken()
        first.cancel()
        XCTAssertTrue(first.isCancelled)
        XCTAssertFalse(second.isCancelled)
    }
}
