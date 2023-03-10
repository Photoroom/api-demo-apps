//
//  Collection+Extension.swift
//  DemoAPIApp
//
//  Created by Vincent on 09/03/2023.
//

import Foundation

extension Collection {
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
