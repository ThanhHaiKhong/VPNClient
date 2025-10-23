//
//  Mocks.swift
//  VPNClient
//
//  Created by Thanh Hai Khong on 22/10/25.
//

import Dependencies

extension DependencyValues {
	public var vpnClient: VPNClient {
		get { self[VPNClient.self] }
		set { self[VPNClient.self] = newValue }
	}
}

extension VPNClient: TestDependencyKey {
	public static var testValue: VPNClient {
		VPNClient()
	}
	
	public static var previewValue: VPNClient {
		VPNClient()
	}
}
