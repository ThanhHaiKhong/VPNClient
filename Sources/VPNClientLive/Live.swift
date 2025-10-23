//
//  Live.swift
//  VPNClient
//
//  Created by Thanh Hai Khong on 22/10/25.
//

import Dependencies
import VPNClient

extension VPNClient: DependencyKey {
	public static let liveValue: VPNClient = {
		let vpnActor = VPNActor()

		return VPNClient(
			servers: {
				try await vpnActor.servers()
			},
			connect: { server, protocolType, configuration in
				try await vpnActor.connect(
					to: server,
					using: protocolType,
					configuration: configuration
				)
			},
			disconnect: {
				try await vpnActor.disconnect()
			},
			reconnect: { server, protocolType, configuration in
				try await vpnActor.reconnect(
					to: server,
					using: protocolType,
					configuration: configuration
				)
			},
			status: {
				AsyncStream { continuation in
					Task {
						let stream = await vpnActor.statusStream()
						for await status in stream {
							continuation.yield(status)
						}
						continuation.finish()
					}
				}
			}
		)
	}()
}
