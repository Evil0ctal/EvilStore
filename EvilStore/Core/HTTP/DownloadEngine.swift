// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// streams an .ipa from an apple-signed URL to a destination on disk and
/// reports progress via an AsyncStream of (bytes, total). uses
/// URLSessionDownloadTask + a delegate so we stay on the ios 14 baseline
/// (URLSession.bytes is ios 15+).
final class DownloadEngine {
    enum Event {
        case progress(bytes: Int64, total: Int64)
        case finished(URL)
        case failed(Swift.Error)
    }

    enum Error: Swift.Error {
        case http(status: Int)
        case writeFailed
        case cancelled
    }

    func stream(
        from url: URL,
        to destination: URL,
        token: TaskCancellationToken? = nil
    ) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let delegate = StreamDelegate(destination: destination, continuation: continuation)
            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
            let task = session.downloadTask(with: url)
            delegate.task = task
            if let token {
                token.onCancel { [weak task, weak session] in
                    task?.cancel()
                    session?.invalidateAndCancel()
                }
            }
            continuation.onTermination = { [weak task, weak session] _ in
                task?.cancel()
                session?.invalidateAndCancel()
            }
            task.resume()
        }
    }
}

/// `Sendable` cancel flag passed into stream(); also fires registered cleanup
/// closures on cancel so the delegate-based engine can tear down its session.
final class TaskCancellationToken: @unchecked Sendable {
    private var cancelled = false
    private var handlers: [() -> Void] = []
    private let lock = NSLock()

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let snapshot = handlers
        handlers.removeAll()
        lock.unlock()
        for handler in snapshot {
            handler()
        }
    }

    func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        let alreadyCancelled = cancelled
        if !alreadyCancelled {
            handlers.append(handler)
        }
        lock.unlock()
        if alreadyCancelled { handler() }
    }
}

// MARK: - delegate

private final class StreamDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let continuation: AsyncStream<DownloadEngine.Event>.Continuation
    weak var task: URLSessionDownloadTask?
    private var finished = false

    init(destination: URL, continuation: AsyncStream<DownloadEngine.Event>.Continuation) {
        self.destination = destination
        self.continuation = continuation
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        continuation.yield(
            .progress(bytes: totalBytesWritten, total: totalBytesExpectedToWrite)
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // we are inside the delegate queue; URLSession deletes `location` when this
        // method returns, so move synchronously.
        let fm = FileManager.default
        do {
            let parent = destination.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
        } catch {
            finished = true
            continuation.yield(.failed(error))
            continuation.finish()
            session.finishTasksAndInvalidate()
            return
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Swift.Error?
    ) {
        guard !finished else {
            session.finishTasksAndInvalidate()
            return
        }
        finished = true

        if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            continuation.yield(.failed(DownloadEngine.Error.http(status: httpResponse.statusCode)))
            continuation.finish()
            session.finishTasksAndInvalidate()
            return
        }

        if let error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                continuation.yield(.failed(DownloadEngine.Error.cancelled))
            } else {
                continuation.yield(.failed(error))
            }
            continuation.finish()
            session.finishTasksAndInvalidate()
            return
        }

        continuation.yield(.finished(destination))
        continuation.finish()
        session.finishTasksAndInvalidate()
    }
}
