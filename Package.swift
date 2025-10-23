// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VPNClient",
	platforms: [
		.iOS(.v15), .macOS(.v15)
	],
    products: [
		.singleTargetLibrary("VPNClient"),
		.singleTargetLibrary("VPNClientLive"),
    ],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", branch: "main"),
		.package(url: "https://github.com/ThanhHaiKhong/SuperVPNKit.git", branch: "master")
	],
    targets: [
        .target(
            name: "VPNClient",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "SuperVPNKit", package: "SuperVPNKit"),
			]
        ),
		.target(
			name: "VPNClientLive",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
				.product(name: "SuperVPNKit", package: "SuperVPNKit"),
				"VPNClient",
			]
		),
    ]
)

extension Product {
	static func singleTargetLibrary(_ name: String) -> Product {
		return .library(name: name, targets: [name])
	}
}
