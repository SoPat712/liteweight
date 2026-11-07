//
//  Notification.Name+RestoreFromBackup.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 26.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

let restoreFromBackupDataUserInfoKey = "restoreFromBackupData"
let importHevyCSVDataUserInfoKey = "importHevyCSVData"
let importHevyCSVErrorUserInfoKey = "importHevyCSVError"
let restorePurchasesSuccessUserInfoKey = "restorePurchasesSuccess"
let restorePurchasesErrorUserInfoKey = "restorePurchasesError"

extension Notification.Name {
    static let RestoreFromBackup = Notification.Name("RestoreFromBackup")
    static let ImportHevyCSV = Notification.Name("ImportHevyCSV")
    static let RestorePurchasesComplete = Notification.Name("RestorePurchasesComplete")
}
