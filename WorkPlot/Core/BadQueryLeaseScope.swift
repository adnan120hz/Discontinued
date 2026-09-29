//
//  BadQueryLeaseScope.swift
//  WorkPlot
//
//  Standardizes the short-lived lease pattern for direct bad_query paths:
//  acquire -> run one operation -> invalidate, even when the body throws.
//

import Foundation

enum BadQueryLeaseError: LocalizedError {
    case acquisitionFailed(String?)

    var errorDescription: String? {
        switch self {
        case .acquisitionFailed(let detail):
            String(
                format: "bad_query lease failed: %@",
                detail ?? "unknown error"
            )
        }
    }
}

enum BadQueryLeaseScope {
    /// Acquires a short-lived sandbox extension for exactly one operation and
    /// guarantees release when `body` returns or throws, so no token leaks
    /// across operations. Long-lived usage stays in GestaltAccess, which
    /// revalidates its lease on every connect().
    static func withLease<T>(forPath path: String, _ body: () throws -> T) throws -> T {
        let handle = try BadQuery.consume(path: path)
        defer { handle.release() }
        return try body()
    }

    /// Short-lived lease for `/var/mobile/Library/Caches` via the class-12
    /// geod route. The dialer-theme backend (iOS 26) — explicit, never AirLift.
    static func withLibraryCachesLease<T>(_ body: () throws -> T) throws -> T {
        let handle = try BadQuery.consumeLibraryCaches()
        defer { handle.release() }
        return try body()
    }

    /// Short-lived lease for an app's data container via the class-2 route
    /// with the app's real bundle identifier. The App Data backend.
    static func withAppContainerLease<T>(bundleId: String, _ body: () throws -> T) throws -> T {
        let handle = try BadQuery.consumeAppContainer(bundleId: bundleId)
        defer { handle.release() }
        return try body()
    }
}
