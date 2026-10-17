import Darwin
import Foundation
import XCTest
@testable import crona

final class CronaUnixSocketTransportTests: XCTestCase {
    private var server: TestUnixSocketServer!

    override func setUpWithError() throws {
        server = try TestUnixSocketServer()
    }

    override func tearDown() {
        server.shutdown()
        server = nil
    }

    func testUnixSocketTransportThrowsInsteadOfRaisingSIGPIPEWhenDaemonClosesEarly() async throws {
        let server = server!
        Task.detached {
            if let connection = server.acceptConnection(timeout: 2) {
                close(connection)
            }
        }
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path)
        let oversizedRequest = Data(repeating: 0x20, count: 8 * 1024 * 1024)

        do {
            _ = try await transport.send(oversizedRequest)
            XCTFail("Expected the write to fail after the daemon closed the socket.")
        } catch {
            XCTAssertTrue(error is CronaConnectionFailure)
        }
    }

    func testUnixSocketTransportTimesOutWhenDaemonNeverResponds() async throws {
        let server = server!
        Task.detached { server.holdConnection(timeout: 2) }
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path, responseTimeout: 0.2)
        let failed = expectation(description: "request fails with a timeout")

        Task.detached {
            do {
                _ = try await transport.send(Data("{}".utf8))
            } catch {
                failed.fulfill()
            }
        }

        await fulfillment(of: [failed], timeout: 3)
    }

    func testUnixSocketTransportClosesEventStreamSocketWhenConsumerCancels() async throws {
        let server = server!
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path)
        let stream = try await transport.openEventStream(with: Data("{}".utf8))
        let consumer = Task {
            for try await _ in stream {}
        }

        let accepted = await Task.detached { server.acceptConnection(timeout: 2) }.value
        let connection = try XCTUnwrap(accepted)
        defer { close(connection) }
        XCTAssertTrue(server.readRequestLine(from: connection, timeout: 2))

        consumer.cancel()

        let sawEOF = await Task.detached { server.waitForEOF(on: connection, timeout: 2) }.value
        XCTAssertTrue(sawEOF, "Cancelling the consumer should close the daemon socket.")
    }

    func testUnixSocketTransportAssemblesResponseSplitAcrossWrites() async throws {
        let server = server!
        Task.detached {
            guard let connection = server.acceptConnection(timeout: 2) else { return }
            defer { close(connection) }
            _ = server.readRequestLine(from: connection, timeout: 2)
            server.write(#"{"id":1,"res"#, to: connection)
            usleep(50_000)
            server.write(#"ult":true}"# + "\n", to: connection)
        }
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path)

        let response = try await transport.send(Data("{}".utf8))

        XCTAssertEqual(String(decoding: response, as: UTF8.self), #"{"id":1,"result":true}"#)
    }

    func testUnixSocketTransportFailsWhenDaemonClosesMidResponse() async throws {
        let server = server!
        Task.detached {
            guard let connection = server.acceptConnection(timeout: 2) else { return }
            _ = server.readRequestLine(from: connection, timeout: 2)
            server.write(#"{"id":1,"res"#, to: connection)
            close(connection)
        }
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path)

        do {
            let response = try await transport.send(Data("{}".utf8))
            XCTFail("Expected a truncated response to fail, got \(String(decoding: response, as: UTF8.self))")
        } catch {
            XCTAssertTrue(error is CronaConnectionFailure)
        }
    }

    func testUnixSocketTransportFailsWhenDaemonClosesWithoutResponding() async throws {
        let server = server!
        Task.detached {
            guard let connection = server.acceptConnection(timeout: 2) else { return }
            _ = server.readRequestLine(from: connection, timeout: 2)
            close(connection)
        }
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path)

        do {
            _ = try await transport.send(Data("{}".utf8))
            XCTFail("Expected an empty response to fail.")
        } catch {
            XCTAssertTrue(error is CronaConnectionFailure)
        }
    }

    func testUnixSocketTransportSkipsMalformedEventFramesAndKeepsStreaming() async throws {
        let server = server!
        let transport = CronaUnixDomainSocketTransport(endpoint: server.path)
        let stream = try await transport.openEventStream(with: Data("{}".utf8))
        Task.detached {
            guard let connection = server.acceptConnection(timeout: 2) else { return }
            defer { close(connection) }
            _ = server.readRequestLine(from: connection, timeout: 2)
            server.write("not json\n", to: connection)
            server.write(#"{"payload":{}}"# + "\n", to: connection)
            server.write(#"{"type":"timer.st"#, to: connection)
            usleep(50_000)
            server.write(#"arted","payload":{"sessionId":"s1"}}"# + "\n", to: connection)
        }

        var received: [CronaProtocolEvent] = []
        for try await event in stream {
            received.append(event)
        }

        XCTAssertEqual(received.map(\.type), ["timer.started"])
        XCTAssertEqual(received.first?.sessionID, "s1")
    }
}

nonisolated private final class TestUnixSocketServer: @unchecked Sendable {
    let path: String
    private let listenDescriptor: Int32
    private let lock = NSLock()
    private var heldConnections: [Int32] = []

    init() throws {
        path = NSTemporaryDirectory() + "crona-\(UUID().uuidString.prefix(8)).sock"
        listenDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenDescriptor >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            pathBytes.withUnsafeBytes { buffer.copyBytes(from: $0) }
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(listenDescriptor, 4) == 0 else {
            close(listenDescriptor)
            throw POSIXError(.EADDRINUSE)
        }
    }

    func acceptConnection(timeout: TimeInterval) -> Int32? {
        guard waitForReadable(listenDescriptor, timeout: timeout) else { return nil }
        let connection = accept(listenDescriptor, nil, nil)
        return connection >= 0 ? connection : nil
    }

    func holdConnection(timeout: TimeInterval) {
        guard let connection = acceptConnection(timeout: timeout) else { return }
        lock.withLock { heldConnections.append(connection) }
    }

    func readRequestLine(from connection: Int32, timeout: TimeInterval) -> Bool {
        var byte: UInt8 = 0
        while waitForReadable(connection, timeout: timeout), read(connection, &byte, 1) == 1 {
            if byte == 0x0A { return true }
        }
        return false
    }

    func write(_ text: String, to connection: Int32) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(connection, $0.baseAddress, $0.count) }
    }

    func waitForEOF(on connection: Int32, timeout: TimeInterval) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 256)
        while waitForReadable(connection, timeout: timeout) {
            let bytesRead = read(connection, &buffer, buffer.count)
            if bytesRead <= 0 { return true }
        }
        return false
    }

    func shutdown() {
        lock.withLock {
            heldConnections.forEach { close($0) }
            heldConnections.removeAll()
        }
        close(listenDescriptor)
        unlink(path)
    }

    private func waitForReadable(_ descriptor: Int32, timeout: TimeInterval) -> Bool {
        var descriptors = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        return poll(&descriptors, 1, Int32(timeout * 1000)) > 0
    }
}
