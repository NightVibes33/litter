//
//  em_proxy.swift
//  SideStore
//
//  Created by Jackson Coxson on 10/26/22.
//
//  bridge for em_proxy static lib similar to minimuxer.swift
//

import Foundation

public func start_em_proxy(bind_addr: String) {
    let host = NSString(string: bind_addr)
    let host_pointer = UnsafeMutablePointer<CChar>(mutating: host.utf8String)
    let _ = start_emotional_damage(host_pointer)
}

public func stop_em_proxy() {
    stop_emotional_damage()
}
