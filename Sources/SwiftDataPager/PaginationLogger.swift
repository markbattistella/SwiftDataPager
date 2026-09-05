//
// Project: SwiftDataPager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import SimpleLogger

/// Configuration options for enabling or disabling pagination logging.
public enum PaginationLoggerConfig {

  /// Disables all logging.
  case none

  /// Enables default debug/error logging using `SimpleLogger`.
  case `default`

  /// Allows a custom logger implementation conforming to `PaginationLogger`.
  case custom(any PaginationLogger)
}

/// A protocol defining logging behaviour for pagination events.
///
/// You can provide custom implementations to control how and where logs are sent.
public protocol PaginationLogger {

  /// Logs general (non-error) messages. Use for debug, flow, or info logs.
  func log(_ message: @autoclosure () -> String)

  /// Logs error-specific messages.
  func error(_ message: @autoclosure () -> String)
}

/// A no-op logger that disables all logging.
///
/// Useful in production or unit tests where log output is not needed.
public struct SilentPaginationLogger: PaginationLogger {
  public init() {}

  public func log(_ message: @autoclosure () -> String) {}
  public func error(_ message: @autoclosure () -> String) {}
}

/// A default logger that routes pagination messages through a `SimpleLogger`.
///
/// Uses `.swiftData` as the log category by default. Logs both debug and error messages.
public struct DefaultPaginationLogger: PaginationLogger {
  private let logger: SimpleLogger

  /// - Parameter category: The `SimpleLogger` category pagination events are logged under.
  ///   Defaults to `.swiftData`.
  public init(category: LoggerCategory = .swiftData) {
    self.logger = SimpleLogger(category: category)
  }

  public func log(_ message: @autoclosure () -> String) {
    let value = message()
    logger.debug("\(value)")
  }

  public func error(_ message: @autoclosure () -> String) {
    let value = message()
    logger.error("\(value)")
  }
}
