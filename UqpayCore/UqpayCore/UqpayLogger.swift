//
//  UqpayLogger.swift
//  UqpayCore
//
//  Created by UQPAY on 10/09/2025.
//

import Foundation
import os.log

/// Log levels for UQPAY SDK logging
public enum UqpayLogLevel: Int, Comparable, CustomStringConvertible {
    /// Verbose logging - includes all details
    case verbose = 0
    /// Debug information
    case debug = 1
    /// Informational messages
    case info = 2
    /// Warning messages
    case warning = 3
    /// Error messages
    case error = 4
    /// No logging
    case none = 5
    
    public var description: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .none: return "NONE"
        }
    }
    
    public static func < (lhs: UqpayLogLevel, rhs: UqpayLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Logger for UQPAY SDK with configurable output and filtering
public final class UqpayLogger {
    
    // MARK: - Singleton
    
    /// Shared logger instance
    public static let shared = UqpayLogger()
    
    // MARK: - Properties
    
    /// Current log level - only messages at this level or higher will be logged
    public var logLevel: UqpayLogLevel = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()
    
    /// Enable or disable logging
    public var isEnabled: Bool = true
    
    /// Custom log handler for capturing logs
    /// Parameters: (level, message, file, function, line)
    public var logHandler: ((UqpayLogLevel, String, String, String, Int) -> Void)?
    
    /// Enable verbose logging (convenience property)
    public var enableVerboseLogging: Bool {
        get { logLevel == .verbose }
        set { logLevel = newValue ? .verbose : .info }
    }
    
    /// Private OSLog instance for system logging
    private let osLog: OSLog
    
    /// Date formatter for log timestamps
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Queue for thread-safe logging
    private let logQueue = DispatchQueue(label: "com.uqpay.sdk.logger", qos: .utility)
    
    // MARK: - Initialization
    
    private init() {
        self.osLog = OSLog(subsystem: "com.uqpay.sdk", category: "UqpaySDK")
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a verbose message
    public func verbose(_ message: String,
                       file: String = #file,
                       function: String = #function,
                       line: Int = #line) {
        log(level: .verbose, message: message, file: file, function: function, line: line)
    }
    
    /// Log a debug message
    public func debug(_ message: String,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    /// Log an info message
    public func info(_ message: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    public func warning(_ message: String,
                       file: String = #file,
                       function: String = #function,
                       line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    /// Log an error message
    public func error(_ message: String,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    /// Log an error with associated Error object
    public func logError(_ error: Error,
                        message: String? = nil,
                        file: String = #file,
                        function: String = #function,
                        line: Int = #line) {
        let errorMessage = message ?? error.localizedDescription
        let fullMessage = "\(errorMessage) - Error: \(error)"
        log(level: .error, message: fullMessage, file: file, function: function, line: line)
    }
    
    // MARK: - Private Methods
    
    private func log(level: UqpayLogLevel,
                    message: String,
                    file: String,
                    function: String,
                    line: Int) {
        
        // Check if logging is enabled and level is appropriate
        guard isEnabled, level >= logLevel, level != .none else { return }
        
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Extract filename from path
            let filename = (file as NSString).lastPathComponent
            
            // Call custom log handler if set
            self.logHandler?(level, message, filename, function, line)
            
            // Format the log message
            let timestamp = self.dateFormatter.string(from: Date())
            let formattedMessage = "[\(timestamp)] [UQPAY] [\(level)] \(filename):\(line) - \(function) - \(message)"
            
            // Log to console in debug mode
            #if DEBUG
            print(formattedMessage)
            #endif
            
            // Log to system log
            self.logToSystem(level: level, message: message)
        }
    }
    
    private func logToSystem(level: UqpayLogLevel, message: String) {
        let osLogType: OSLogType
        
        switch level {
        case .verbose, .debug:
            osLogType = .debug
        case .info:
            osLogType = .info
        case .warning:
            osLogType = .default
        case .error:
            osLogType = .error
        case .none:
            return
        }
        
        // Private (Apple's own default for dynamic strings): a payment SDK's
        // log lines must not be readable off a customer's device by anyone
        // with a cable and Console.app. DEBUG builds still print in full, and
        // the merchant's `logHandler` receives every message unredacted.
        os_log("%{private}@", log: osLog, type: osLogType, message)
    }
    
    // MARK: - Utility Methods
    
    /// Log API request
    public func logAPIRequest(method: String, path: String, parameters: [String: Any]? = nil) {
        var message = "API Request: \(method) \(path)"
        if let parameters = parameters, !parameters.isEmpty {
            message += " - Parameters: \(parameters)"
        }
        debug(message)
    }
    
    /// Log API response
    public func logAPIResponse(path: String, statusCode: Int, response: Any? = nil) {
        var message = "API Response: \(path) - Status: \(statusCode)"
        if let response = response {
            message += " - Response: \(response)"
        }
        debug(message)
    }
    
    /// Log API error
    public func logAPIError(path: String, error: Error) {
        logError(error, message: "API Error: \(path)")
    }
    
    /// Log payment event
    public func logPaymentEvent(_ event: String, details: [String: Any]? = nil) {
        var message = "Payment Event: \(event)"
        if let details = details, !details.isEmpty {
            message += " - Details: \(details)"
        }
        info(message)
    }
    
    /// Log configuration change
    public func logConfiguration(_ message: String) {
        info("Configuration: \(message)")
    }
    
    /// Reset logger to default settings
    public func reset() {
        logQueue.sync {
            self.logLevel = {
                #if DEBUG
                return .debug
                #else
                return .warning
                #endif
            }()
            self.isEnabled = true
            self.logHandler = nil
        }
    }
}

// MARK: - Convenience Extensions

public extension UqpayLogger {
    /// Log method entry (for tracing)
    func enter(file: String = #file, function: String = #function, line: Int = #line) {
        verbose("Entering \(function)", file: file, function: function, line: line)
    }
    
    /// Log method exit (for tracing)
    func exit(file: String = #file, function: String = #function, line: Int = #line) {
        verbose("Exiting \(function)", file: file, function: function, line: line)
    }
    
    /// Log a measurement/metric
    func metric(_ name: String, value: Any, file: String = #file, function: String = #function, line: Int = #line) {
        debug("Metric: \(name) = \(value)", file: file, function: function, line: line)
    }
}