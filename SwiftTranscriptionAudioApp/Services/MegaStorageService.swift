import Foundation
import MEGASdk

/// A thin wrapper around MEGA's iOS SDK that performs authentication,
/// uploads audio files, and produces streaming URLs for remote playback.
@MainActor
final class MegaStorageService: NSObject {
    struct Configuration {
        let appKey: String
        let userAgent: String
        let email: String
        let password: String
        let parentHandle: MEGAHandle?

        init(appKey: String,
             userAgent: String,
             email: String,
             password: String,
             parentHandle: MEGAHandle? = nil) {
            self.appKey = appKey
            self.userAgent = userAgent
            self.email = email
            self.password = password
            self.parentHandle = parentHandle
        }

        /// Attempts to read configuration values from the app's `Info.plist` file.
        /// This expects keys named `MEGAAppKey`, `MEGAUserAgent`, `MEGAEmail`, and `MEGAPassword`.
        init?(bundle: Bundle = .main) {
            guard let appKey = bundle.object(forInfoDictionaryKey: "MEGAAppKey") as? String,
                  let userAgent = bundle.object(forInfoDictionaryKey: "MEGAUserAgent") as? String,
                  let email = bundle.object(forInfoDictionaryKey: "MEGAEmail") as? String,
                  let password = bundle.object(forInfoDictionaryKey: "MEGAPassword") as? String else {
                return nil
            }

            let parentHandleString = bundle.object(forInfoDictionaryKey: "MEGAParentHandle") as? String
            let parentHandle = parentHandleString.flatMap { UInt64($0) }

            self.init(appKey: appKey,
                      userAgent: userAgent,
                      email: email,
                      password: password,
                      parentHandle: parentHandle)
        }
    }

    struct UploadResult {
        let handle: MEGAHandle
        let size: Int64
    }

    enum ServiceError: Error, LocalizedError {
        case configurationMissing
        case unableToAuthenticate
        case unableToLocateParentNode
        case uploadFailed(MEGAErrorType)
        case requestFailed(MEGAErrorType)
        case streamingLinkUnavailable
        case invalidStreamingURL(String)

        var errorDescription: String? {
            switch self {
            case .configurationMissing:
                return "Missing MEGA configuration."
            case .unableToAuthenticate:
                return "Unable to authenticate with MEGA."
            case .unableToLocateParentNode:
                return "Unable to locate the destination folder in MEGA."
            case .uploadFailed(let errorType):
                return "Failed to upload audio to MEGA (\(errorType))."
            case .requestFailed(let errorType):
                return "MEGA request failed (\(errorType))."
            case .streamingLinkUnavailable:
                return "Streaming link was not returned by MEGA."
            case .invalidStreamingURL(let urlString):
                return "Received an invalid streaming URL: \(urlString)."
            }
        }
    }

    private final class RequestContinuationDelegate: NSObject, MEGARequestDelegate {
        private let completion: (Result<MEGARequest, ServiceError>) -> Void

        init(completion: @escaping (Result<MEGARequest, ServiceError>) -> Void) {
            self.completion = completion
        }

        func onRequestFinish(_ api: MEGASdk, request: MEGARequest, error: MEGAError) {
            if error.type == .apiOk {
                completion(.success(request))
            } else {
                completion(.failure(.requestFailed(error.type)))
            }
        }
    }

    private final class TransferContinuationDelegate: NSObject, MEGATransferDelegate {
        private let completion: (Result<MEGATransfer, ServiceError>) -> Void

        init(completion: @escaping (Result<MEGATransfer, ServiceError>) -> Void) {
            self.completion = completion
        }

        func onTransferFinish(_ api: MEGASdk, transfer: MEGATransfer, error: MEGAError) {
            if error.type == .apiOk {
                completion(.success(transfer))
            } else {
                completion(.failure(.uploadFailed(error.type)))
            }
        }
    }

    private let sdk: MEGASdk
    private let configuration: Configuration
    private var requestDelegates: [RequestContinuationDelegate] = []
    private var transferDelegates: [TransferContinuationDelegate] = []
    private var hasFetchedNodes = false

    init(configuration: Configuration) {
        self.configuration = configuration
        self.sdk = MEGASdkManager.sharedMEGASdk(withAppKey: configuration.appKey,
                                                userAgent: configuration.userAgent)
        super.init()
    }

    static func makeDefault(bundle: Bundle = .main) -> MegaStorageService? {
        guard let configuration = Configuration(bundle: bundle) else { return nil }
        return MegaStorageService(configuration: configuration)
    }

    func authenticateIfNeeded() async throws {
        if sdk.isLoggedIn() == 0 {
            try await performRequest { delegate in
                sdk.login(configuration.email, password: configuration.password, delegate: delegate)
            }
        }

        if !hasFetchedNodes {
            try await performRequest { delegate in
                sdk.fetchNodes(delegate)
            }
            hasFetchedNodes = true
        }
    }

    func uploadAudio(from fileURL: URL, fileName: String? = nil) async throws -> UploadResult {
        try await authenticateIfNeeded()

        guard let parentNode = configuration.parentHandle.flatMap({ sdk.node(forHandle: $0) }) ?? sdk.rootNode else {
            throw ServiceError.unableToLocateParentNode
        }

        let transfer = try await performTransfer { delegate in
            sdk.startUploadNode(fileURL.path,
                                parent: parentNode,
                                fileName: fileName ?? fileURL.lastPathComponent,
                                appData: nil,
                                isSourceTemporary: false,
                                startFirst: true,
                                cancelToken: nil,
                                delegate: delegate)
        }

        return UploadResult(handle: transfer.nodeHandle, size: transfer.size?.int64Value ?? 0)
    }

    func streamingURL(for handle: MEGAHandle) async throws -> URL {
        try await authenticateIfNeeded()

        if !sdk.isHTTPServerRunning() {
            sdk.httpServerStart()
            sdk.httpServerEnableFilesServe(true)
        }

        guard let node = sdk.node(forHandle: handle),
              let link = sdk.httpServerGetLocalLink(with: node) else {
            throw ServiceError.streamingLinkUnavailable
        }

        guard let url = URL(string: link) else {
            throw ServiceError.invalidStreamingURL(link)
        }

        return url
    }

    private func performRequest(_ action: (MEGARequestDelegate) -> Void) async throws -> MEGARequest {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = RequestContinuationDelegate { result in
                self.requestDelegates.removeAll { $0 === delegate }
                continuation.resume(with: result)
            }
            requestDelegates.append(delegate)
            action(delegate)
        }
    }

    private func performTransfer(_ action: (MEGATransferDelegate) -> Void) async throws -> MEGATransfer {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = TransferContinuationDelegate { result in
                self.transferDelegates.removeAll { $0 === delegate }
                continuation.resume(with: result)
            }
            transferDelegates.append(delegate)
            action(delegate)
        }
    }
}

extension MegaStorageService: @unchecked Sendable {}
