// swift-tools-version:6.1
/*
 * Copyright 2024, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import PackageDescription

let manifestDirectoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let manifestPath = manifestDirectoryURL.standardizedFileURL.path
let isDependencyCheckout = manifestPath.contains("/.build/checkouts/")
  || manifestPath.contains("/SourcePackages/checkouts/")

func localOrForkDependency(_ repository: String, localPath: String) -> Package.Dependency {
  let resolvedLocalPath = URL(fileURLWithPath: localPath, relativeTo: manifestDirectoryURL)
    .standardizedFileURL
    .path
  if !isDependencyCheckout && FileManager.default.fileExists(atPath: resolvedLocalPath) {
    return .package(path: resolvedLocalPath)
  }

  return .package(url: "https://github.com/1amageek/\(repository).git", branch: "main")
}

let products: [Product] = [
  .library(
    name: "GRPCNIOTransportHTTP2",
    targets: ["GRPCNIOTransportHTTP2"]
  ),
  .library(
    name: "GRPCNIOTransportHTTP2Posix",
    targets: ["GRPCNIOTransportHTTP2Posix"]
  ),
  .library(
    name: "GRPCNIOTransportHTTP2TransportServices",
    targets: ["GRPCNIOTransportHTTP2TransportServices"]
  ),
]

let dependencies: [Package.Dependency] = [
  localOrForkDependency("grpc-swift-2", localPath: "../grpc-swift-2"),
  localOrForkDependency("swift-nio", localPath: "../swift-nio"),
  localOrForkDependency("swift-nio-http2", localPath: "../swift-nio-http2"),
  localOrForkDependency("swift-nio-transport-services", localPath: "../swift-nio-transport-services"),
  localOrForkDependency("swift-nio-ssl", localPath: "../swift-nio-ssl"),
  localOrForkDependency("swift-nio-extras", localPath: "../swift-nio-extras"),
  localOrForkDependency("swift-certificates", localPath: "../swift-certificates"),
  localOrForkDependency("swift-asn1", localPath: "../swift-asn1"),
]

// -------------------------------------------------------------------------------------------------

// This adds some build settings which allow us to map "@available(gRPCSwiftNIOTransport 2.x, *)" to
// the appropriate OS platforms.
let nextMinorVersion = 9
let availabilitySettings: [SwiftSetting] = (0 ... nextMinorVersion).map { minor in
  let name = "gRPCSwiftNIOTransport"
  let version = "2.\(minor)"
  let platforms = "macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"
  let setting = "AvailabilityMacro=\(name) \(version):\(platforms)"
  return .enableExperimentalFeature(setting)
}

let defaultSwiftSettings: [SwiftSetting] =
  availabilitySettings + [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
  ]

let zlibLinkPlatforms: [Platform] = [
  .macOS,
  .macCatalyst,
  .iOS,
  .watchOS,
  .tvOS,
  .visionOS,
  .linux,
  .android,
]

// -------------------------------------------------------------------------------------------------

let targets: [Target] = [
  // C-module for z-lib shims
  .target(
    name: "CGRPCNIOTransportZlib",
    dependencies: [],
    linkerSettings: [
      .linkedLibrary("z", .when(platforms: zlibLinkPlatforms))
    ]
  ),

  // Core module containing shared components for the NIOPosix and NIOTS variants.
  .target(
    name: "GRPCNIOTransportCore",
    dependencies: [
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "NIOCore", package: "swift-nio"),
      .product(name: "NIOHTTP2", package: "swift-nio-http2"),
      .product(name: "NIOExtras", package: "swift-nio-extras"),
      .target(name: "CGRPCNIOTransportZlib"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCNIOTransportCoreTests",
    dependencies: [
      .target(name: "GRPCNIOTransportCore"),
      .product(name: "NIOCore", package: "swift-nio"),
      .product(name: "NIOEmbedded", package: "swift-nio"),
      .product(name: "NIOTestUtils", package: "swift-nio"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // NIOPosix variant of the HTTP/2 transports.
  .target(
    name: "GRPCNIOTransportHTTP2Posix",
    dependencies: [
      .target(name: "GRPCNIOTransportCore"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "NIOPosix", package: "swift-nio"),
      .product(name: "NIOSSL", package: "swift-nio-ssl"),
      .product(name: "X509", package: "swift-certificates"),
      .product(name: "SwiftASN1", package: "swift-asn1"),
      .product(name: "NIOCertificateReloading", package: "swift-nio-extras"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // NIOTransportServices variant of the HTTP/2 transports.
  .target(
    name: "GRPCNIOTransportHTTP2TransportServices",
    dependencies: [
      .target(name: "GRPCNIOTransportCore"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // Umbrella module exporting NIOPosix and NIOTransportServices variants.
  .target(
    name: "GRPCNIOTransportHTTP2",
    dependencies: [
      .target(name: "GRPCNIOTransportHTTP2Posix"),
      .target(name: "GRPCNIOTransportHTTP2TransportServices"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCNIOTransportHTTP2Tests",
    dependencies: [
      .target(name: "GRPCNIOTransportHTTP2"),
      .product(name: "GRPCCore", package: "grpc-swift-2"),
      .product(name: "X509", package: "swift-certificates"),
      .product(name: "NIOSSL", package: "swift-nio-ssl"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
]

let package = Package(
  name: "grpc-swift-nio-transport",
  products: products,
  dependencies: dependencies,
  targets: targets
)
