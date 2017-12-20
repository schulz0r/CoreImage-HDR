//
//  extensions.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 20.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

extension Array where Element: Equatable{
    func allIs(value: Element) -> Bool {
        return self.reduce(true){$0 && ($1 == value)}
    }
}
