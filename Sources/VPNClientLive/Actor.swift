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
import NetworkExtension

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

	public func currentStatus() async -> VPNClient.Status {
		let manager = await getManager()
		return await manager.currentStatus()
	}

	public func isConnected() async -> Bool {
		let manager = await getManager()
		return await manager.isConnected()
	}

	public func currentServer() async -> VPNClient.Server? {
		let manager = await getManager()
		return await manager.currentServer()
	}

	public func currentProtocol() async -> VPNClient.`Protocol`? {
		let manager = await getManager()
		return await manager.currentProtocol()
	}

	public func connectionStats() async -> AsyncStream<VPNClient.ConnectionStats> {
		let manager = await getManager()
		return await manager.connectionStatsStream()
	}
}

@MainActor
final internal class VPNManager: @unchecked Sendable {
	private let vpnAPI = VpnCoreKit.VpnAPI.shared
	private var status: VPNClient.Status = .idle {
		didSet {
			for wrapper in statusContinuations {
				#if DEBUG
				print("\n====================================================================")
				print(" - VPN_CLIENT_YIELDING_STATUS: \(status)")
				print("====================================================================")
				#endif
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
	private var currentProvider: (any SuperVPNKit.VPNProvider & Sendable)?
	private var currentConnectionInfo: (server: VPNClient.Server, protocol: VPNClient.`Protocol`)?
	private var connectionStartTime: Date?
	private let appGroupIdentifier = "group.C77T3ALUS5.com.orlproducts.vpnpro"
	private let bundleIdentifier = "com.orlproducts.vpnpro.extension"

	init() {
		// Sync with system VPN status on initialization
		Task { @MainActor in
			await self.syncWithSystemStatus()
		}
	}
	
	func servers() async throws -> [VPNClient.Server] {
		status = .loading(.servers)
		let result = await vpnAPI.getServers()
		switch result {
		case .success(let servers):
			status = .loading(.loadedServers(count: servers.count))
			return servers
		case .failure(let vpnAPIError):
			let errorMessage = vpnAPIError.localizedDescription
			status = .loading(.failedServers(error: errorMessage))
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

			currentConnectionInfo = (server, `protocol`)
			connectionStartTime = Date()
			status = .connection(.connected(server: server, protocol: `protocol`))
		} catch {
			currentConnectionInfo = nil
			connectionStartTime = nil
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
			currentConnectionInfo = nil
			connectionStartTime = nil
			status = .connection(.disconnected)
		} catch {
			// Even if disconnect fails, clear the provider
			currentProvider = nil
			currentConnectionInfo = nil
			connectionStartTime = nil
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

			currentConnectionInfo = (server, `protocol`)
			connectionStartTime = Date()
			status = .connection(.connected(server: server, protocol: `protocol`))
		} catch {
			currentConnectionInfo = nil
			connectionStartTime = nil
			status = .connection(.failed(error: error.localizedDescription, lastServer: server))
			throw error
		}
	}

	func currentStatus() async -> VPNClient.Status {
		status
	}

	func isConnected() async -> Bool {
		status.isConnected
	}

	func currentServer() async -> VPNClient.Server? {
		currentConnectionInfo?.server
	}

	func currentProtocol() async -> VPNClient.`Protocol`? {
		currentConnectionInfo?.protocol
	}

	func connectionStatsStream() -> AsyncStream<VPNClient.ConnectionStats> {
		AsyncStream { continuation in
			#if DEBUG
			print("📊 [VPNManager] connectionStatsStream created")
			#endif

			let task = Task { @MainActor in
				// Update interval: 1 second for smooth real-time updates
				let updateInterval: UInt64 = 1_000_000_000 // 1 second in nanoseconds

				#if DEBUG
				print("📊 [VPNManager] Starting stats stream loop")
				#endif

				while !Task.isCancelled {
					#if DEBUG
					print("📊 [VPNManager] Stats stream tick - connectionStartTime: \(self.connectionStartTime != nil), currentProvider: \(self.currentProvider != nil), isConnected: \(self.status.isConnected)")
					#endif

					// Only yield stats if we're connected
					if let startTime = self.connectionStartTime,
					   let provider = self.currentProvider,
					   self.status.isConnected {

						#if DEBUG
						print("📊 [VPNManager] All conditions met, calling getDataCount()")
						#endif

						let dataCount = provider.getDataCount()

						#if DEBUG
						if let dataCount = dataCount {
							print("📊 [VPNManager] Data count from provider: received=\(dataCount.received), sent=\(dataCount.sent)")
						} else {
							print("⚠️ [VPNManager] Data count is nil - provider.getDataCount() returned nil")
						}
						#endif

						let bytesSent = dataCount?.sent ?? 0
						let bytesReceived = dataCount?.received ?? 0

						let stats = VPNClient.ConnectionStats(
							bytesSent: bytesSent,
							bytesReceived: bytesReceived,
							connectedAt: startTime
						)

						#if DEBUG
						print("📊 [VPNManager] Yielding stats: sent=\(bytesSent), received=\(bytesReceived)")
						#endif

						continuation.yield(stats)
					} else {
						#if DEBUG
						print("⚠️ [VPNManager] Conditions not met - skipping stats update")
						#endif
					}

					// Wait before next update
					try? await Task.sleep(nanoseconds: updateInterval)
				}
			}

			continuation.onTermination = { _ in
				#if DEBUG
				print("📊 [VPNManager] Stats stream terminated")
				#endif
				task.cancel()
			}
		}
	}

	// MARK: - System Status Sync

	private func syncWithSystemStatus() async {
		#if DEBUG
		print("🔄 [VPNManager] Syncing with system VPN status...")
		#endif

		do {
			// Load all VPN managers from system preferences
			let managers = try await NETunnelProviderManager.loadAllFromPreferences()

			// Find our VPN manager by bundle identifier
			guard let vpnManager = managers.first(where: { manager in
				guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
				return proto.providerBundleIdentifier == bundleIdentifier
			}) else {
				#if DEBUG
				print("ℹ️ [VPNManager] No VPN configuration found, setting status to disconnected")
				#endif
				status = .connection(.disconnected)
				return
			}

			let connectionStatus = vpnManager.connection.status

			#if DEBUG
			print("📱 [VPNManager] System VPN Status: \(connectionStatus.rawValue)")
			#endif

			// Try to retrieve last connected server info
			let serverInfo = retrieveLastConnectedServer()

			// Map NEVPNStatus to VPNClient.Status
			switch connectionStatus {
			case .connected:
				if let serverInfo = serverInfo {
					#if DEBUG
					print("✅ [VPNManager] VPN is connected to \(serverInfo.server.name)")
					#endif

					// Create provider to maintain connection info
					let configuration = VPNClient.Configuration(
						appGroup: appGroupIdentifier,
						bundleIdentifier: bundleIdentifier
					)
					currentProvider = createProvider(with: serverInfo.protocol, configuration: configuration)
					currentConnectionInfo = (serverInfo.server, serverInfo.protocol)

					// Estimate connection start time (or retrieve if saved)
					connectionStartTime = vpnManager.connection.connectedDate ?? Date()

					status = .connection(.connected(server: serverInfo.server, protocol: serverInfo.protocol))
				} else {
					#if DEBUG
					print("⚠️ [VPNManager] VPN is connected but no server info found")
					#endif
					status = .connection(.disconnected)
				}

			case .connecting:
				if let serverInfo = serverInfo {
					#if DEBUG
					print("🔄 [VPNManager] VPN is connecting to \(serverInfo.server.name)")
					#endif
					status = .connection(.connecting(server: serverInfo.server, protocol: serverInfo.protocol))
				} else {
					status = .connection(.disconnected)
				}

			case .reasserting:
				if let serverInfo = serverInfo {
					#if DEBUG
					print("🔄 [VPNManager] VPN is reconnecting to \(serverInfo.server.name)")
					#endif
					status = .connection(.reconnecting(server: serverInfo.server, protocol: serverInfo.protocol))
				} else {
					status = .connection(.disconnected)
				}

			case .disconnecting:
				#if DEBUG
				print("🔄 [VPNManager] VPN is disconnecting")
				#endif
				status = .connection(.disconnecting)

			case .disconnected, .invalid:
				#if DEBUG
				print("❌ [VPNManager] VPN is disconnected")
				#endif
				status = .connection(.disconnected)

			@unknown default:
				#if DEBUG
				print("⚠️ [VPNManager] Unknown VPN status")
				#endif
				status = .connection(.disconnected)
			}
		} catch {
			#if DEBUG
			print("❌ [VPNManager] Failed to load VPN preferences: \(error.localizedDescription)")
			#endif
			status = .idle
		}
	}

	private func retrieveLastConnectedServer() -> (server: VPNClient.Server, protocol: VPNClient.`Protocol`)? {
		guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
			#if DEBUG
			print("❌ [VPNManager] Failed to access shared UserDefaults")
			#endif
			return nil
		}

		guard let encodedData = sharedDefaults.data(forKey: "current_server_details") else {
			#if DEBUG
			print("ℹ️ [VPNManager] No saved server details found")
			#endif
			return nil
		}

		guard let serverDetails = try? JSONDecoder().decode([String: String].self, from: encodedData) else {
			#if DEBUG
			print("❌ [VPNManager] Failed to decode server details")
			#endif
			return nil
		}

		guard let serverID = serverDetails["id"],
			  let serverName = serverDetails["name"],
			  let countryCode = serverDetails["countryCode"],
			  let quality = serverDetails["quality"] else {
			#if DEBUG
			print("❌ [VPNManager] Incomplete server details")
			#endif
			return nil
		}

		// Reconstruct server object
		let server = VPNClient.Server(
			id: serverID,
			name: serverName,
			countryCode: countryCode,
			quality: quality,
			protocols: [String.openvpn, String.ikev2] // Default protocols
		)

		// Retrieve protocol from saved details, default to OpenVPN if not found
		let protocolRawValue = serverDetails["protocol"] ?? String.openvpn
		let protocolType: VPNClient.`Protocol`

		// Match the raw value to the correct protocol type
		switch protocolRawValue {
		case String.openvpn:
			protocolType = .openVPN
		case String.ikev2:
			protocolType = .ikev2
		default:
			protocolType = .openVPN // Default to OpenVPN
		}

		#if DEBUG
		print("✅ [VPNManager] Retrieved server info: \(serverName), protocol: \(protocolType.name)")
		#endif

		return (server, protocolType)
	}

	private func createProvider(
		with protocol: VPNClient.`Protocol`,
		configuration: VPNClient.Configuration
	) -> any SuperVPNKit.VPNProvider & Sendable {
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

extension VpnCoreKit.ServerConfiguration: @unchecked @retroactive Sendable {

}

extension VpnCoreKit.VpnAPI: @unchecked @retroactive Sendable {

}

extension SuperVPNKit.OpenVPNProvider: @unchecked @retroactive Sendable {

}

extension SuperVPNKit.IKEv2Provider: @unchecked @retroactive Sendable {

}
