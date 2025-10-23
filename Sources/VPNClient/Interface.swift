// The Swift Programming Language
// https://docs.swift.org/swift-book

import DependenciesMacros
import VpnCoreKit

@DependencyClient
public struct VPNClient: Sendable {
	public typealias Server = VpnCoreKit.ServerInfo
	public var servers: @Sendable () async throws -> [VPNClient.Server] = { [] }
	public var connect: @Sendable (_ server: VPNClient.Server, _ protocol: VPNClient.`Protocol`, _ configuration: VPNClient.Configuration) async throws -> Void = { _, _, _ in }
	public var disconnect: @Sendable () async throws -> Void = { }
	public var reconnect: @Sendable (_ server: VPNClient.Server, _ protocol: VPNClient.`Protocol`, _ configuration: VPNClient.Configuration) async throws -> Void = { _, _, _ in }
	public var status: @Sendable () async -> AsyncStream<VPNClient.Status> = { AsyncStream { _ in } }
}

