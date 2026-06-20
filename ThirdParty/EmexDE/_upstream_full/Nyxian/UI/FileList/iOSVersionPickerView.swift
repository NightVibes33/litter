/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import UIKit
import MobileDevelopmentKit

fileprivate var _NXSDK: MDKSDK? = nil
fileprivate var NXSDK: MDKSDK? {
    get {
        if(_NXSDK == nil) {
            _NXSDK = MDKSDK(forDirectoryURL: NXBootstrap.shared().sdkURL)
        }
        return _NXSDK
    }
}

fileprivate var _NXOSVersionSupportedBuildVersions: [String] = []
var NXOSVersionSupportedBuildVersions: [String] {
    get {
        if !_NXOSVersionSupportedBuildVersions.isEmpty {
            return _NXOSVersionSupportedBuildVersions
        }
        
        if let sdk = NXSDK,
           let supportedVersions = sdk.supportedVersions {
            for version in supportedVersions {
                _NXOSVersionSupportedBuildVersions.append(version.versionString)
            }
            return _NXOSVersionSupportedBuildVersions
        }
        
        return ["26.5"]
    }
}

class IOSVersionPickerViewController: UIThemedViewController, UIPickerViewDelegate, UIPickerViewDataSource {

    var selectedVersion: String
    var onVersionSelected: ((String) -> Void)?

    private let pickerView = UIPickerView()

    private let pickerTitle: String

    init(title: String, selectedVersion: String) {
        let osVersion: MDKOSVersion = MDKOSVersion(versionString: selectedVersion) ?? MDKOSVersion(versionString: NXOSVersionSupportedBuildVersions.last!)!
        self.pickerTitle = title
        self.selectedVersion = osVersion.versionString
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = pickerTitle
        
        pickerView.delegate = self
        pickerView.dataSource = self
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pickerView)
        
        let idx = NXOSVersionSupportedBuildVersions.firstIndex(of: selectedVersion) ?? NXOSVersionSupportedBuildVersions.count - 1
        pickerView.selectRow(idx, inComponent: 0, animated: false)
        
        NSLayoutConstraint.activate([
            pickerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        NXOSVersionSupportedBuildVersions.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        "iOS \(NXOSVersionSupportedBuildVersions[row])"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedVersion = NXOSVersionSupportedBuildVersions[row]
        onVersionSelected?(selectedVersion)
    }
}
