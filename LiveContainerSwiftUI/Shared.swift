//
//  Shared.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/22.
//

import SwiftUI

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}
