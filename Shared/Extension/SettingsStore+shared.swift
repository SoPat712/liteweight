//
//  SettingsStore+shared.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 07.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

extension SettingsStore {
    static let shared = SettingsStore(userDefaults: UserDefaults.appGroup)
}
