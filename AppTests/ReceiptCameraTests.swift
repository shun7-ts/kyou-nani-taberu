import XCTest
import UIKit
import ImageIO
@testable import KyouNaniTaberu

@MainActor
private final class ControlledCameraPermission: ReceiptCameraPermissionClient {
    var available = true
    var permission = ReceiptCameraPermission.notDetermined
    var answer = true
    var hold = false
    var requests = 0
    var pending: CheckedContinuation<Bool, Never>?
    func request() async -> Bool {
        requests += 1
        if hold { return await withCheckedContinuation { pending = $0 } }
        return answer
    }
    func resolve(_ value: Bool) { let saved = pending; pending = nil; saved?.resume(returning: value) }
}

@MainActor
final class ReceiptCameraTests: XCTestCase {
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }
    func testUnavailableCameraDoesNotAskPermissionOrPresent() async {
        let client = ControlledCameraPermission(); client.available = false
        let camera = ReceiptCameraController(client: client)
        XCTAssertEqual(client.requests, 0)
        await camera.open()
        XCTAssertEqual(client.requests, 0); XCTAssertNil(camera.session); XCTAssertEqual(camera.phase, .idle)
        XCTAssertNotNil(camera.message); XCTAssertFalse(camera.settingsNeeded)
    }
    func testDeniedRestrictedAndDeclinedPermissionsKeepFallbackAvailable() async {
        for status in [ReceiptCameraPermission.denied, .restricted, .notDetermined] {
            let client = ControlledCameraPermission(); client.permission = status; client.answer = false
            let camera = ReceiptCameraController(client: client); await camera.open()
            XCTAssertNil(camera.session); XCTAssertEqual(camera.phase, .idle); XCTAssertNotNil(camera.message)
            XCTAssertEqual(camera.settingsNeeded, status != .restricted)
            XCTAssertEqual(client.requests, status == .notDetermined ? 1 : 0)
        }
    }
    func testPermissionDialogWaitsForActiveBeforePresentation() async throws {
        let client = ControlledCameraPermission(); client.hold = true
        let camera = ReceiptCameraController(client: client)
        let opening = Task { await camera.open() }
        try await eventually { client.pending != nil }
        camera.activityChanged(.inactive); client.resolve(true)
        try await eventually { camera.phase == .waitingForActive }
        XCTAssertNil(camera.session); XCTAssertTrue(camera.preparing)
        camera.activityChanged(.active); await opening.value
        XCTAssertNotNil(camera.session); XCTAssertEqual(camera.phase, .presented)
        camera.cancel(); _ = camera.presentationDidDismiss()
    }
    func testBackgroundAndLatePermissionCannotPresentCamera() async throws {
        let client = ControlledCameraPermission(); client.hold = true
        let camera = ReceiptCameraController(client: client)
        let opening = Task { await camera.open() }
        try await eventually { client.pending != nil }
        camera.activityChanged(.background); client.resolve(true); await opening.value
        camera.activityChanged(.active)
        XCTAssertNil(camera.session); XCTAssertEqual(camera.phase, .idle); XCTAssertNil(camera.takeImage())
    }
    func testCancelReleasesActiveWaitAndDuplicateOpenDoesNotAskTwice() async throws {
        let client = ControlledCameraPermission(); client.hold = true
        let camera = ReceiptCameraController(client: client)
        let opening = Task { await camera.open() }
        try await eventually { client.pending != nil }
        await camera.open(); XCTAssertEqual(client.requests, 1)
        camera.activityChanged(.inactive); client.resolve(true)
        try await eventually { camera.phase == .waitingForActive }
        camera.cancel(); await opening.value; camera.activityChanged(.active)
        XCTAssertNil(camera.session); XCTAssertFalse(camera.preparing)
    }
    func testCapturedImageIsConsumedOnceAndStaleCallbacksCannotReplaceIt() async throws {
        let client = ControlledCameraPermission(); client.permission = .authorized
        let camera = ReceiptCameraController(client: client); await camera.open()
        let session = try XCTUnwrap(camera.session), bytes = Data([1, 2, 3])
        camera.complete(sessionID: UUID(), result: .success(Data([9])))
        XCTAssertEqual(camera.session, session); XCTAssertNil(camera.takeImage())
        camera.complete(sessionID: session.id, result: .success(bytes))
        XCTAssertNil(camera.session); XCTAssertTrue(camera.presentationActive)
        camera.complete(sessionID: session.id, result: .success(Data([9])))
        camera.cancel(sessionID: session.id)
        XCTAssertEqual(camera.presentationDidDismiss(), bytes); XCTAssertNil(camera.takeImage())
        XCTAssertFalse(camera.presentationActive); XCTAssertEqual(client.requests, 0)
        await camera.open(); let next = try XCTUnwrap(camera.session)
        XCTAssertNotEqual(next.id, session.id)
        camera.complete(sessionID: session.id, result: .failure(ReceiptError.invalidImage))
        XCTAssertEqual(camera.session, next); camera.cancel(); _ = camera.presentationDidDismiss()
    }
    func testCaptureErrorAndBackgroundDiscardPendingImage() async throws {
        let client = ControlledCameraPermission(); client.permission = .authorized
        let camera = ReceiptCameraController(client: client); await camera.open()
        let first = try XCTUnwrap(camera.session)
        camera.complete(sessionID: first.id, result: .failure(ReceiptError.invalidImage))
        XCTAssertNil(camera.presentationDidDismiss()); XCTAssertNotNil(camera.message)
        await camera.open(); XCTAssertNil(camera.message)
        let second = try XCTUnwrap(camera.session)
        camera.complete(sessionID: second.id, result: .success(Data([1])))
        camera.activityChanged(.background)
        XCTAssertNil(camera.presentationDidDismiss()); XCTAssertNil(camera.takeImage())
    }
    func testLeavingLiveCameraCancelsAndRejectsLateCaptureWithoutAutoRestart() async throws {
        let client = ControlledCameraPermission(); client.permission = .authorized
        let camera = ReceiptCameraController(client: client); await camera.open()
        let first = try XCTUnwrap(camera.session)
        camera.activityChanged(.inactive)
        XCTAssertNil(camera.session); XCTAssertNotNil(camera.message)
        camera.complete(sessionID: first.id, result: .success(Data([1])))
        XCTAssertNil(camera.presentationDidDismiss()); camera.activityChanged(.active); XCTAssertNil(camera.session)
        await camera.open(); let retry = try XCTUnwrap(camera.session)
        camera.cancel(sessionID: first.id); XCTAssertEqual(camera.session, retry)
        camera.cancel(); _ = camera.presentationDidDismiss()
    }
    func testImageConversionNormalizesOrientationBoundsPixelsAndOmitsMetadata() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 1000), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4000, height: 1000))
        }
        let originalData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(originalData, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(source.cgImage), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.0, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:01 12:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Test camera"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithData(originalData, nil))
        let originalProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary])
        let rotated = try XCTUnwrap(UIImage(data: originalData as Data))
        let data = try ReceiptCameraImage.prepare(rotated)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 750)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 3000)
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let allowedExifKeys: Set<CFString> = [kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension]
        XCTAssertTrue(Set(exif.keys).isSubset(of: allowedExifKeys))
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(tiff[kCGImagePropertyTIFFModel]); XCTAssertNil(tiff[kCGImagePropertyTIFFDateTime])
        XCTAssertLessThan(data.count, 25 * 1024 * 1024)
        XCTAssertThrowsError(try ReceiptCameraImage.prepare(UIImage()))
    }
    func testPreparedReceiptFlowsThroughRealOnDeviceOCR() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 600), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1400, height: 600))
            ("牛乳 1000ml 198円" as NSString).draw(at: CGPoint(x: 80, y: 180), withAttributes: [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black])
        }
        let lines = try await ReceiptOCR.recognize(data: ReceiptCameraImage.prepare(image))
        XCTAssertTrue(lines.joined().contains("牛乳")); XCTAssertTrue(lines.joined().contains("1000"))
        let ingredient = ReceiptIngredient(id: UUID(), name: "牛乳", aliases: [], unit: .milliliter, allowedUnits: [.milliliter], storage: .refrigerated)
        let row = try XCTUnwrap(ReceiptParser.parse(lines, ingredients: [ingredient]).first)
        XCTAssertEqual(row.masterID, ingredient.id); XCTAssertFalse(row.confirmed)
        XCTAssertEqual(Double(row.quantity), 1000); XCTAssertNil(row.expiresAt)
    }
}
