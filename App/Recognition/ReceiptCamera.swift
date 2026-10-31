import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

enum ReceiptCameraPermission { case notDetermined, authorized, denied, restricted }
enum ReceiptCameraActivity { case active, inactive, background }
struct ReceiptCameraSession: Identifiable, Equatable { let id: UUID }

@MainActor
protocol ReceiptCameraPermissionClient {
    var available: Bool { get }
    var permission: ReceiptCameraPermission { get }
    func request() async -> Bool
}

@MainActor
private struct SystemReceiptCameraPermissionClient: ReceiptCameraPermissionClient {
    var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    var permission: ReceiptCameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }
    func request() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}

@MainActor
final class ReceiptCameraController: ObservableObject {
    enum Phase { case idle, permission, waitingForActive, presented }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var session: ReceiptCameraSession?
    @Published private(set) var message: String?
    @Published private(set) var settingsNeeded = false
    private(set) var presentationActive = false
    var preparing: Bool { phase == .permission || phase == .waitingForActive }
    private let client: any ReceiptCameraPermissionClient
    private var activity = ReceiptCameraActivity.active
    private var generation = UUID()
    private var activation: CheckedContinuation<Bool, Never>?
    private var capturedData: Data?

    init(client: (any ReceiptCameraPermissionClient)? = nil) {
        self.client = client ?? SystemReceiptCameraPermissionClient()
    }
    func open() async {
        guard phase == .idle, !presentationActive, activity == .active else { return }
        cancel(); message = nil; settingsNeeded = false
        let token = generation
        guard client.available else {
            message = "この端末ではカメラを利用できません。写真を選ぶか、手入力で続けてください。"; return
        }
        phase = .permission
        switch client.permission {
        case .authorized: break
        case .denied:
            denied(); return
        case .restricted:
            cancel(); message = "カメラの利用が制限されています。写真を選ぶか、手入力で続けてください。"; return
        case .notDetermined:
            let allowed = await client.request()
            guard token == generation else { return }
            guard allowed else { denied(); return }
        }
        if activity != .active {
            guard activity != .background else { cancel(); return }
            phase = .waitingForActive
            let resumed = await withCheckedContinuation { activation = $0 }
            guard resumed, token == generation else { return }
        }
        guard token == generation, activity == .active, client.available else { cancel(); return }
        presentationActive = true; phase = .presented; session = ReceiptCameraSession(id: token)
    }
    private func denied() {
        cancel(); settingsNeeded = true
        message = "カメラが許可されていません。写真を選ぶか手入力で続けられます。許可はiPhoneの設定で変更できます。"
    }
    func activityChanged(_ activity: ReceiptCameraActivity) {
        self.activity = activity
        switch activity {
        case .active:
            let pending = activation; activation = nil; pending?.resume(returning: true)
        case .inactive:
            if phase == .presented { cancel(); message = "撮影を中止しました。もう一度撮影するか写真を選んでください。" }
        case .background:
            cancel()
        }
    }
    func complete(sessionID: UUID, result: Result<Data, Error>) {
        guard session?.id == sessionID, generation == sessionID, phase == .presented else { return }
        generation = UUID(); session = nil; phase = .idle
        switch result {
        case .success(let data): capturedData = data
        case .failure: capturedData = nil; message = "写真を取得できませんでした。もう一度撮影するか写真を選んでください。"
        }
    }
    func cancel(sessionID: UUID) {
        guard session?.id == sessionID else { return }
        cancel()
    }
    func takeImage() -> Data? {
        defer { capturedData = nil }
        return capturedData
    }
    func presentationDidDismiss() -> Data? {
        presentationActive = false
        return takeImage()
    }
    func cancel() {
        generation = UUID(); session = nil; phase = .idle; capturedData = nil
        let pending = activation; activation = nil; pending?.resume(returning: false)
    }
}

/// Normalize orientation, bound pixel size and discard camera metadata without writing a file.
@MainActor
enum ReceiptCameraImage {
    static func prepare(_ image: UIImage) throws -> Data {
        var width = CGFloat(image.cgImage?.width ?? 0), height = CGFloat(image.cgImage?.height ?? 0)
        if image.cgImage == nil { width = image.size.width * image.scale; height = image.size.height * image.scale }
        switch image.imageOrientation {
        case .left, .right, .leftMirrored, .rightMirrored: swap(&width, &height)
        default: break
        }
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw ReceiptError.invalidImage }
        let factor = min(1, 3000 / max(width, height))
        let size = CGSize(width: max(1, floor(width * factor)), height: max(1, floor(height * factor)))
        return try autoreleasepool {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let data = normalized.jpegData(compressionQuality: 0.9) else { throw ReceiptError.invalidImage }
            guard data.count <= 25 * 1024 * 1024 else { throw ReceiptError.tooLarge }
            return data
        }
    }
}

struct ReceiptCameraPicker: UIViewControllerRepresentable {
    let sessionID: UUID
    let completed: (UUID, Result<Data, Error>) -> Void
    let cancelled: (UUID) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIViewController {
        // Check again immediately before setting sourceType, which raises an exception if unavailable.
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let picker = UIImagePickerController()
            picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo; picker.allowsEditing = false
            picker.delegate = context.coordinator
            return picker
        } else {
            Task { @MainActor in context.coordinator.fail() }
            return UIViewController()
        }
    }
    func updateUIViewController(_ picker: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ picker: UIViewController, coordinator: Coordinator) {
        coordinator.finished = true; (picker as? UIImagePickerController)?.delegate = nil
    }
    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ReceiptCameraPicker
        var finished = false
        init(parent: ReceiptCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !finished else { return }; finished = true
            let result = Result { () throws -> Data in
                guard let image = info[.originalImage] as? UIImage else { throw ReceiptError.invalidImage }
                return try ReceiptCameraImage.prepare(image)
            }
            parent.completed(parent.sessionID, result)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !finished else { return }; finished = true; parent.cancelled(parent.sessionID)
        }
        func fail() {
            guard !finished else { return }; finished = true
            parent.completed(parent.sessionID, .failure(ReceiptError.invalidImage))
        }
    }
}

/// These fixtures are reachable only in the isolated UI-test mode; they never open a real camera.
enum ReceiptCameraTesting {
    static var fixture: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-camera-fixture") }
    static var denied: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-camera-denied") }
    @MainActor static func controller() -> ReceiptCameraController {
        ReceiptCameraController(client: fixture || denied ? Client(denied: denied) : nil)
    }
    @MainActor private struct Client: ReceiptCameraPermissionClient {
        let denied: Bool
        var available: Bool { true }
        var permission: ReceiptCameraPermission { denied ? .denied : .authorized }
        func request() async -> Bool { !denied }
    }
}

struct ReceiptCameraFixtureView: View {
    let sessionID: UUID
    let completed: (UUID, Result<Data, Error>) -> Void
    let cancelled: (UUID) -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("カメラのテスト用画像").font(AppFont.headline)
                Text("マイク・カメラ・写真ライブラリを利用しません。")
                Button("テスト画像を撮影") {
                    completed(sessionID, Result {
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        let image = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 1600), format: format).image { context in
                            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1400, height: 1600))
                            let lines = ["スーパー牛乳 町田店", "TEL 03-1234-5678", "東京都新宿区ねぎ町1丁目2番3号",
                                "2026年10月10日 17:30", "牛乳 1000ml 198円", "小計 198円", "合計 198円",
                                "卵 6個 98円", "ご来店ありがとうございます"]
                            for (index, line) in lines.enumerated() {
                                (line as NSString).draw(at: CGPoint(x: 80, y: 100 + index * 150), withAttributes: [.font: UIFont.systemFont(ofSize: 54), .foregroundColor: UIColor.black])
                            }
                        }
                        return try ReceiptCameraImage.prepare(image)
                    })
                }.accessibilityIdentifier("camera-fixture-capture")
                Button("撮影をキャンセル") { cancelled(sessionID) }.accessibilityIdentifier("camera-fixture-cancel")
            }.padding().navigationTitle("レシートを撮影")
        }
    }
}
