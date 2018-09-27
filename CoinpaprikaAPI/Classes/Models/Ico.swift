//
//  Ico.swift
//  Pods
//
//  Created by Dominique Stranz on 27/09/2018.
//

import Foundation

public struct Ico: Decodable, Equatable {
    public let id: String
    public let name: String
    public let symbol: String
    public let isNew: Bool
}
