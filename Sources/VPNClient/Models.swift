//
//  Models.swift
//  VPNClient
//
//  Created by Thanh Hai Khong on 22/10/25.
//

@preconcurrency import VpnCoreKit
import SuperVPNKit
import SwiftUI

// MARK: - Configuration

extension VPNClient {
	public struct Configuration: Sendable {
		public let appGroup: String?
		public let bundleIdentifier: String?

		public init(
			appGroup: String? = nil,
			bundleIdentifier: String? = nil
		) {
			self.appGroup = appGroup
			self.bundleIdentifier = bundleIdentifier
		}

		// Configuration required for OpenVPN
		public static func openVPN(
			appGroup: String,
			bundleIdentifier: String
		) -> Configuration {
			Configuration(
				appGroup: appGroup,
				bundleIdentifier: bundleIdentifier
			)
		}

		// Configuration for IKEv2 (no additional parameters needed)
		public static let ikev2 = Configuration()

		// Configuration for WireGuard (can be extended later)
		public static let wireGuard = Configuration()
	}
}

// MARK: - Protocol

extension VPNClient {
	public struct `Protocol`: Sendable, RawRepresentable, Identifiable, Equatable {
		public typealias RawValue = String
		public let name: String
		public let rawValue: RawValue
		public var id: RawValue { rawValue }
		
		public init(rawValue: RawValue) {
			self.name = rawValue
			self.rawValue = rawValue
		}
		
		public init(
			name: String,
			rawValue: RawValue
		) {
			self.name = name
			self.rawValue = rawValue
		}
		
		public static let openVPN = Protocol(name: "OpenVPN", rawValue: String.openvpn)
		public static let ikev2 = Protocol(name: "IKEv2", rawValue: String.ikev2)
		public static let wireGuard = Protocol(name: "WireGuard", rawValue: "WIREGUARD")
	}
}

// MARK: - Connection Status

extension VPNClient {
	// Represents the current state of the VPN connection lifecycle
	public enum ConnectionStatus: Sendable, Equatable {
		case disconnected // Not connected, ready to connect
		case connecting(server: VPNClient.Server, protocol: VPNClient.`Protocol`) // Attempting to establish connection to a server
		case connected(server: VPNClient.Server, protocol: VPNClient.`Protocol`) // Successfully connected to a server
		case disconnecting // In the process of disconnecting
		case reconnecting(server: VPNClient.Server, protocol: VPNClient.`Protocol`) // Attempting to reconnect after connection loss
		case failed(error: String, lastServer: VPNClient.Server?) // Connection failed with error details

		public var title: String {
			switch self {
			case .disconnected:
				return "Disconnected"
			case .connecting(let server, _):
				return "Connecting to \(server.name)..."
			case .connected(let server, _):
				return "Connected to \(server.name)"
			case .disconnecting:
				return "Disconnecting..."
			case .reconnecting(let server, _):
				return "Reconnecting to \(server.name)..."
			case .failed(_, let server):
				if let server = server {
					return "Failed: \(server.name)"
				}
				return "Connection Failed"
			}
		}

		public var color: Color {
			switch self {
			case .disconnected:
				return .gray
			case .connecting, .reconnecting:
				return .orange
			case .connected:
				return .green
			case .disconnecting:
				return .yellow
			case .failed:
				return .red
			}
		}

		public var isConnected: Bool {
			if case .connected = self {
				return true
			}
			return false
		}

		public var isConnecting: Bool {
			switch self {
			case .connecting, .reconnecting:
				return true
			default:
				return false
			}
		}

		public var currentServer: VPNClient.Server? {
			switch self {
			case .connecting(let server, _),
				 .connected(let server, _),
				 .reconnecting(let server, _):
				return server
			case .failed(_, let server):
				return server
			case .disconnected, .disconnecting:
				return nil
			}
		}

		public var currentProtocol: VPNClient.`Protocol`? {
			switch self {
			case .connecting(_, let protocolType),
				 .connected(_, let protocolType),
				 .reconnecting(_, let protocolType):
				return protocolType
			case .disconnected, .disconnecting, .failed:
				return nil
			}
		}
	}
}

// MARK: - Overall Status

extension VPNClient {
	// Represents the overall state of the VPN client, including UI and connection states
	public enum Status: Sendable, Equatable {
		case idle // Initial state
		case loadingServers // Loading server list from API
		case connection(ConnectionStatus) // Connection-related status

		public var title: String {
			switch self {
			case .idle:
				return "Ready"
			case .loadingServers:
				return "Loading Servers..."
			case .connection(let connectionStatus):
				return connectionStatus.title
			}
		}

		public var color: Color {
			switch self {
			case .idle:
				return .blue
			case .loadingServers:
				return .blue
			case .connection(let connectionStatus):
				return connectionStatus.color
			}
		}

		public var isConnected: Bool {
			if case .connection(let connectionStatus) = self {
				return connectionStatus.isConnected
			}
			return false
		}

		public var isConnecting: Bool {
			if case .connection(let connectionStatus) = self {
				return connectionStatus.isConnecting
			}
			return false
		}

		public var connectionStatus: ConnectionStatus? {
			if case .connection(let connectionStatus) = self {
				return connectionStatus
			}
			return nil
		}

		public var currentServer: VPNClient.Server? {
			connectionStatus?.currentServer
		}

		public var currentProtocol: VPNClient.`Protocol`? {
			connectionStatus?.currentProtocol
		}
	}
}

// MARK: - VPNError

extension VPNClient {
	public enum `Error`: LocalizedError, Sendable, Swift.Error {
		case configurationNotFound
		case connectionFailed(reason: String)
		case disconnectionFailed(reason: String)
		case apiError(VpnAPIError)
		
		public var errorDescription: String? {
			switch self {
			case .configurationNotFound:
				return "VPN configuration not found."
			case .connectionFailed(let reason):
				return "Connection failed: \(reason)"
			case .disconnectionFailed(let reason):
				return "Disconnection failed: \(reason)"
			case .apiError(let apiError):
				return apiError.errorDescription
			}
		}
	}
}
