import AppKit
import XCTest
@testable import crona

@MainActor
final class DaemonConnectionTests: DaemonTestCase {
    func testCleanEventStreamClosureReconnects() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        await waitForIssueCreator { !transport.eventContinuations.isEmpty }
        transport.eventContinuations[0].finish()
        await waitForIssueCreator { transport.eventContinuations.count >= 2 }
        XCTAssertEqual(connection.connectionState, .connected)
    }

    func testDiscoveryResolvesEndpointAndDefaultsTransport() {
        let config = CronaConfig(
            environment: .development,
            daemonLabel: "crona",
            postHogApiKey: nil,
            discoveryFilePath: "/tmp/kernel.json",
            runtimeDirectoryPath: "/tmp",
            defaultSocketPath: "/tmp/default.sock",
            defaultKernelExecutable: "crona-daemon",
            defaultDevKernelExecutable: "crona-daemon-dev"
        )

        let discovery = CronaKernelDiscovery(
            pid: nil,
            transport: nil,
            endpoint: nil,
            socketPath: "/tmp/kernel.sock",
            protocolVersion: nil,
            token: nil,
            startedAt: nil,
            scratchDir: nil,
            env: "production",
            executablePath: nil,
            runningChannel: nil,
            runningIsBeta: nil
        )

        let resolved = discovery.resolved(using: config)

        XCTAssertEqual(resolved?.endpoint, "/tmp/kernel.sock")
        XCTAssertEqual(resolved?.transport, "unix")
        XCTAssertEqual(resolved?.env, .production)
        XCTAssertEqual(resolved?.effectiveSocketPath, "/tmp/kernel.sock")
    }

    func testDaemonLaunchRequestUsesDiscoveryExecutableAndRuntimeOverride() throws {
        let executableURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data(), attributes: [
            .posixPermissions: 0o755
        ])
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let config = CronaConfig(
            environment: .production,
            daemonLabel: "crona",
            postHogApiKey: nil,
            discoveryFilePath: "/tmp/kernel.json",
            runtimeDirectoryPath: "/tmp/runtime",
            defaultSocketPath: "/tmp/kernel.sock",
            defaultKernelExecutable: "crona-daemon",
            defaultDevKernelExecutable: "crona-daemon-dev"
        )
        let runtime = LoadedCronaRuntime(
            config: config,
            discovery: nil
        )
        let discovery = try XCTUnwrap(
            CronaKernelDiscovery(
                pid: nil,
                transport: "unix",
                endpoint: "/tmp/kernel.sock",
                socketPath: "/tmp/kernel.sock",
                protocolVersion: nil,
                token: nil,
                startedAt: nil,
                scratchDir: nil,
                env: "production",
                executablePath: executableURL.path,
                runningChannel: nil,
                runningIsBeta: nil
            ).resolved(using: config)
        )

        let request = try DaemonLaunchService().makeRequest(runtime: runtime, discovery: discovery)

        XCTAssertEqual(request.executableURL, executableURL)
        XCTAssertEqual(request.arguments, [])
        XCTAssertEqual(request.environment["CRONA_HOME"], "/tmp/runtime")
    }

    func testDaemonLaunchRequestUsesEnvForBareExecutableName() throws {
        let executableURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data(), attributes: [
            .posixPermissions: 0o755
        ])
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let executableName = executableURL.lastPathComponent
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let config = CronaConfig(
            environment: .development,
            daemonLabel: "crona",
            postHogApiKey: nil,
            discoveryFilePath: "/tmp/kernel.json",
            runtimeDirectoryPath: "/tmp/runtime-dev",
            defaultSocketPath: "/tmp/kernel.sock",
            defaultKernelExecutable: executableName,
            defaultDevKernelExecutable: executableName
        )
        let runtime = LoadedCronaRuntime(config: config, discovery: nil)
        let discovery = try XCTUnwrap(
            CronaKernelDiscovery(
                pid: nil,
                transport: "unix",
                endpoint: "/tmp/kernel.sock",
                socketPath: "/tmp/kernel.sock",
                protocolVersion: nil,
                token: nil,
                startedAt: nil,
                scratchDir: nil,
                env: "development",
                executablePath: executableName,
                runningChannel: nil,
                runningIsBeta: nil
            ).resolved(using: config)
        )

        let previousPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", executableDirectory, 1)
        defer {
            if let previousPath {
                setenv("PATH", previousPath, 1)
            } else {
                unsetenv("PATH")
            }
        }
        let request = try DaemonLaunchService().makeRequest(runtime: runtime, discovery: discovery)

        XCTAssertEqual(request.executableURL.path, executableURL.path)
        XCTAssertEqual(request.arguments, [])
        XCTAssertEqual(request.environment["CRONA_HOME"], "/tmp/runtime-dev")
    }

    func testDaemonLaunchRequestFallsBackToDefaultExecutableWithoutDiscovery() throws {
        let executableURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data(), attributes: [
            .posixPermissions: 0o755
        ])
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let executableName = executableURL.lastPathComponent
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let config = CronaConfig(
            environment: .production,
            daemonLabel: "crona",
            postHogApiKey: nil,
            discoveryFilePath: "/tmp/kernel.json",
            runtimeDirectoryPath: "/tmp/runtime-prod",
            defaultSocketPath: "/tmp/kernel.sock",
            defaultKernelExecutable: executableName,
            defaultDevKernelExecutable: "crona-daemon-dev"
        )
        let runtime = LoadedCronaRuntime(config: config, discovery: nil)

        let previousPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", executableDirectory, 1)
        defer {
            if let previousPath {
                setenv("PATH", previousPath, 1)
            } else {
                unsetenv("PATH")
            }
        }
        let request = try DaemonLaunchService().makeRequest(runtime: runtime)

        XCTAssertEqual(request.executableURL.path, executableURL.path)
        XCTAssertEqual(request.arguments, [])
        XCTAssertEqual(request.environment["CRONA_HOME"], "/tmp/runtime-prod")
    }

    func testDaemonConnectionLatchesErrorWhenLaunchFailsWithoutDiscovery() async {
        let executableURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data(), attributes: [
            .posixPermissions: 0o755
        ])
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let executableName = executableURL.lastPathComponent
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let previousPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", executableDirectory, 1)
        defer {
            if let previousPath {
                setenv("PATH", previousPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let kernelDiscovery = KernelDiscoveryService(
            configLoader: CronaConfigLoader(
                bundle: TestBundle.info([
                    "CRONA_APP_ENV": "development",
                    "CRONA_DAEMON_LABEL": "crona",
                    "CRONA_RUNTIME_DIR": "/tmp/Crona Dev",
                    "CRONA_KERNEL_EXECUTABLE": executableName,
                    "CRONA_KERNEL_DEV_EXECUTABLE": executableName
                ]),
                environmentProvider: { [:] }
            )
        )
        var launchAttempts = 0
        let service = DaemonConnectionService(
            kernelDiscovery: kernelDiscovery,
            daemonLaunchService: DaemonLaunchService(
                launchHandler: { _ in
                    launchAttempts += 1
                    throw NSError(domain: "DaemonLaunchTests", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Launch failed."
                    ])
                }
            ),
            reconnectInterval: .milliseconds(20),
            postLaunchRetryDelay: .milliseconds(5)
        )

        service.start()
        await settleAsyncTasks()
        try? await Task.sleep(for: .milliseconds(80))
        let attemptsAfterLatch = launchAttempts
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(service.connectionState, .error)
        XCTAssertEqual(service.lastErrorDescription, "Launch failed.")
        XCTAssertEqual(launchAttempts, attemptsAfterLatch)
        XCTAssertEqual(launchAttempts, 1)
        service.stop()
    }

    func testManualReconnectClearsLatchedLaunchErrorAndRetries() async {
        let executableURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data(), attributes: [
            .posixPermissions: 0o755
        ])
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let executableName = executableURL.lastPathComponent
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let previousPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", executableDirectory, 1)
        defer {
            if let previousPath {
                setenv("PATH", previousPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let kernelDiscovery = KernelDiscoveryService(
            configLoader: CronaConfigLoader(
                bundle: TestBundle.info([
                    "CRONA_APP_ENV": "development",
                    "CRONA_DAEMON_LABEL": "crona",
                    "CRONA_RUNTIME_DIR": "/tmp/Crona Dev",
                    "CRONA_KERNEL_EXECUTABLE": executableName,
                    "CRONA_KERNEL_DEV_EXECUTABLE": executableName
                ]),
                environmentProvider: { [:] }
            )
        )
        var launchAttempts = 0
        let service = DaemonConnectionService(
            kernelDiscovery: kernelDiscovery,
            daemonLaunchService: DaemonLaunchService(
                launchHandler: { _ in
                    launchAttempts += 1
                    throw NSError(domain: "DaemonLaunchTests", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Launch failed."
                    ])
                }
            ),
            reconnectInterval: .milliseconds(20),
            postLaunchRetryDelay: .milliseconds(5)
        )

        service.start()
        await settleAsyncTasks()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(service.connectionState, .error)
        XCTAssertEqual(launchAttempts, 1)

        service.manualReconnect()
        await settleAsyncTasks()
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(service.connectionState, .error)
        XCTAssertEqual(launchAttempts, 2)
        service.stop()
    }

    func testConfigLoaderUsesBundleDefaultsForDevelopment() {
        let loader = CronaConfigLoader(
            bundle: TestBundle.info([
                "CRONA_APP_ENV": "development",
                "CRONA_DAEMON_LABEL": "crona",
                "CRONA_RUNTIME_DIR": "/tmp/Crona Dev",
                "CRONA_KERNEL_EXECUTABLE": "crona-daemon",
                "CRONA_KERNEL_DEV_EXECUTABLE": "crona-daemon-dev"
            ]),
            environmentProvider: { [:] }
        )

        let runtime = loader.load()

        XCTAssertEqual(runtime.config.environment, .development)
        XCTAssertEqual(runtime.config.runtimeDirectoryPath, "/tmp/Crona Dev")
        XCTAssertEqual(runtime.config.discoveryFilePath, "/tmp/Crona Dev/kernel.json")
        XCTAssertEqual(runtime.config.defaultSocketPath, "/tmp/Crona Dev/kernel.sock")
    }

    func testConfigLoaderAllowsOnlyCRONA_HOMEOverride() {
        let loader = CronaConfigLoader(
            bundle: TestBundle.info([
                "CRONA_APP_ENV": "production",
                "CRONA_DAEMON_LABEL": "crona",
                "CRONA_RUNTIME_DIR": "/tmp/Crona",
                "CRONA_KERNEL_EXECUTABLE": "crona-daemon",
                "CRONA_KERNEL_DEV_EXECUTABLE": "crona-daemon-dev"
            ]),
            environmentProvider: {
                [
                    "CRONA_HOME": "/tmp/override",
                    "CRONA_DISCOVERY_FILE": "/tmp/ignored/kernel.json",
                    "CRONA_DAEMON_SOCKET_PATH": "/tmp/ignored/kernel.sock"
                ]
            }
        )

        let runtime = loader.load()

        XCTAssertEqual(runtime.config.runtimeDirectoryPath, "/tmp/override")
        XCTAssertEqual(runtime.config.discoveryFilePath, "/tmp/override/kernel.json")
        XCTAssertEqual(runtime.config.defaultSocketPath, "/tmp/override/kernel.sock")
    }

    func testConfigLoaderExpandsRuntimeHomeAtLaunch() {
        let loader = CronaConfigLoader(
            bundle: TestBundle.info([
                "CRONA_APP_ENV": "production",
                "CRONA_DAEMON_LABEL": "crona",
                "CRONA_RUNTIME_DIR": "~/Library/Application Support/Crona",
                "CRONA_KERNEL_EXECUTABLE": "crona-daemon",
                "CRONA_KERNEL_DEV_EXECUTABLE": "crona-daemon-dev"
            ]),
            environmentProvider: { [:] }
        )

        let runtime = loader.load()
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Crona")
            .path

        XCTAssertEqual(runtime.config.runtimeDirectoryPath, expected)
        XCTAssertFalse(runtime.config.runtimeDirectoryPath.contains("~"))
    }
}
