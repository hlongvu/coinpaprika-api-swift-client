//
//  News.swift
//  CoinpaprikaAPI
//
//  Created by Dominique Stranz on 03/01/2019.
//

import Foundation

/// News
public struct News: Codable, Equatable, CodableModel {
    
    /// News title
    public let title: String
    
    /// News url
    public let url: URL
    
    /// News date
    public let date: Date
    
    enum CodingKeys: String, CodingKey {
        case title
        case url
        case date = "news_date"
    }
    
}