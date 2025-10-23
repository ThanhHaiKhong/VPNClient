//
//  Actor.swift
//  VPNClient
//
//  Created by Thanh Hai Khong on 23/10/25.
//

import VPNClient
import SuperVPNKit
import VpnCoreKit
import Foundation

public actor VPNActor: Sendable {
	private var manager: VPNManager?

	public init() {
		// Manager will be lazily initialized on first use
	}

	private func getManager() async -> VPNManager {
		if let manager = manager {
			return manager
		}
		let newManager = await VPNManager()
		manager = newManager
		return newManager
	}

	public func servers() async throws -> [VPNClient.Server] {
		let manager = await getManager()
		return try await manager.servers()
	}

	public func connect(
		to server: VPNClient.Server,
		using protocol: VPNClient.`Protocol`,
		configuration: VPNClient.Configuration
	) async throws {
		let manager = await getManager()
		try await manager.connect(
			to: server,
			using: `protocol`,
			configuration: configuration
		)
	}

	public func disconnect() async throws {
		let manager = await getManager()
		try await manager.disconnect()
	}

	public func reconnect(
		to server: VPNClient.Server,
		using protocol: VPNClient.`Protocol`,
		configuration: VPNClient.Configuration
	) async throws {
		let manager = await getManager()
		try await manager.reconnect(
			to: server,
			using: `protocol`,
			configuration: configuration
		)
	}

	public func statusStream() async -> AsyncStream<VPNClient.Status> {
		let manager = await getManager()
		return await manager.statusStream()
	}
}

@MainActor
final internal class VPNManager: @unchecked Sendable {
	private let vpnAPI = VpnCoreKit.VpnAPI.shared
	private var status: VPNClient.Status = .idle {
		didSet {
			// Notify all active continuations
			for wrapper in statusContinuations {
				wrapper.continuation.yield(status)
			}
		}
	}

	private class ContinuationWrapper {
		let id = UUID()
		let continuation: AsyncStream<VPNClient.Status>.Continuation

		init(continuation: AsyncStream<VPNClient.Status>.Continuation) {
			self.continuation = continuation
		}
	}

	private var statusContinuations: [ContinuationWrapper] = []
	private var currentProvider: (any VPNProvider & Sendable)?

	init() {

	}
	
	func servers() async throws -> [VPNClient.Server] {
		status = .loadingServers
		let result = await vpnAPI.getServers()
		switch result {
		case .success(let servers):
			// Return to connection status or idle
			if currentProvider != nil {
				// Keep current connection status
			} else {
				status = .idle
			}
			return servers
		case .failure(let vpnAPIError):
			status = .idle
			throw VPNClient.Error.apiError(vpnAPIError)
		}
	}
	
	func statusStream() -> AsyncStream<VPNClient.Status> {
		AsyncStream { continuation in
			// Yield the current status immediately
			continuation.yield(self.status)

			// Wrap and add to the list of continuations
			let wrapper = ContinuationWrapper(continuation: continuation)
			self.statusContinuations.append(wrapper)

			continuation.onTermination = { [weak self, id = wrapper.id] _ in
				Task { @MainActor in
					guard let self = self else { return }
					// Remove this continuation from the list by ID
					self.statusContinuations.removeAll { $0.id == id }
				}
			}
		}
	}
	
	func connect(
		to server: VPNClient.Server,
		using protocol: VPNClient.`Protocol`,
		configuration: VPNClient.Configuration
	) async throws {
		status = .connection(.connecting(server: server, protocol: `protocol`))

		do {
			let serverConfiguration = try await self.serverConfiguration(
				serverID: server.id,
				protocol: `protocol`
			)
			let provider = createProvider(with: `protocol`, configuration: configuration)
			currentProvider = provider

			try await provider.loadConfiguration()
			try await provider.connect(with: serverConfiguration)

			status = .connection(.connected(server: server, protocol: `protocol`))
		} catch {
			status = .connection(.failed(error: error.localizedDescription, lastServer: server))
			throw error
		}
	}

	func disconnect() async throws {
		guard let provider = currentProvider else {
			throw VPNClient.Error.configurationNotFound
		}

		status = .connection(.disconnecting)

		do {
			try await provider.disconnect()
			currentProvider = nil
			status = .connection(.disconnected)
		} catch {
			// Even if disconnect fails, clear the provider
			currentProvider = nil
			status = .connection(.disconnected)
			throw error
		}
	}

	func reconnect(
		to server: VPNClient.Server,
		using protocol: VPNClient.`Protocol`,
		configuration: VPNClient.Configuration
	) async throws {
		status = .connection(.reconnecting(server: server, protocol: `protocol`))

		do {
			// Disconnect current provider if exists
			if let provider = currentProvider {
				try? await provider.disconnect()
			}

			let serverConfiguration = try await self.serverConfiguration(
				serverID: server.id,
				protocol: `protocol`
			)
			let provider = createProvider(with: `protocol`, configuration: configuration)
			currentProvider = provider

			try await provider.loadConfiguration()
			try await provider.connect(with: serverConfiguration)

			status = .connection(.connected(server: server, protocol: `protocol`))
		} catch {
			status = .connection(.failed(error: error.localizedDescription, lastServer: server))
			throw error
		}
	}

	private func createProvider(
		with protocol: VPNClient.`Protocol`,
		configuration: VPNClient.Configuration
	) -> any VPNProvider & Sendable {
		if `protocol`.rawValue == String.openvpn {
			guard let appGroup = configuration.appGroup,
				  let bundleIdentifier = configuration.bundleIdentifier else {
				fatalError("OpenVPN requires appGroup and bundleIdentifier in configuration")
			}
			return OpenVPNProvider(appGroup: appGroup, bundleIdentifier: bundleIdentifier)
		} else if `protocol`.rawValue == String.ikev2 {
			return IKEv2Provider()
		} else {
			fatalError("Unsupported protocol: \(`protocol`.rawValue)")
		}
	}
	
	private func serverConfiguration(
		serverID: String,
		protocol: VPNClient.`Protocol`
	) async throws -> VpnCoreKit.ServerConfiguration {
		let result = await vpnAPI.getConfiguration(serverId: serverID, protocol: `protocol`.rawValue)
		switch result {
		case .success(let configuration):
			return configuration
		case .failure(let vpnAPIError):
			throw VPNClient.Error.apiError(vpnAPIError)
		}
	}
}

extension VpnCoreKit.ServerInfo: @unchecked @retroactive Sendable {

}

extension VpnCoreKit.ServerConfiguration: @unchecked @retroactive Sendable {

}

extension VpnCoreKit.VpnAPI: @unchecked @retroactive Sendable {

}

extension SuperVPNKit.OpenVPNProvider: @unchecked @retroactive Sendable {

}

extension SuperVPNKit.IKEv2Provider: @unchecked @retroactive Sendable {

}

