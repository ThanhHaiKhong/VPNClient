// The Swift Programming Language
// https://docs.swift.org/swift-book

import DependenciesMacros
import VpnCoreKit

@DependencyClient
public struct VPNClient: Sendable {

	// MARK: - Server Management

	/// Fetch available VPN servers from the API
	public var servers: @Sendable () async throws -> [VPNClient.Server] = { [] }

	// MARK: - Connection Control

	/// Connect to a VPN server with specified protocol and configuration
	public var connect: @Sendable (_ server: VPNClient.Server, _ protocol: VPNClient.`Protocol`, _ configuration: VPNClient.Configuration) async throws -> Void = { _, _, _ in }

	/// Disconnect from the current VPN connection
	public var disconnect: @Sendable () async throws -> Void = { }

	/// Reconnect to a VPN server (useful for connection drops or switching servers)
	public var reconnect: @Sendable (_ server: VPNClient.Server, _ protocol: VPNClient.`Protocol`, _ configuration: VPNClient.Configuration) async throws -> Void = { _, _, _ in }

	// MARK: - Status Monitoring

	/// Stream of VPN status updates
	public var status: @Sendable () async -> AsyncStream<VPNClient.Status> = { AsyncStream { _ in } }

	/// Get current connection status synchronously (non-streaming)
	public var currentStatus: @Sendable () async -> VPNClient.Status = { .idle }

	/// Check if currently connected to any server
	public var isConnected: @Sendable () async -> Bool = { false }

	// MARK: - Connection Info

	/// Get currently connected server (if any)
	public var currentServer: @Sendable () async -> VPNClient.Server? = { nil }

	/// Get currently used protocol (if connected)
	public var currentProtocol: @Sendable () async -> VPNClient.`Protocol`? = { nil }

	// MARK: - Network Statistics (Optional for future)

	/// Get connection statistics (bytes sent/received, connection duration, etc.)
	public var connectionStats: @Sendable () async -> VPNClient.ConnectionStats? = { nil }
}

