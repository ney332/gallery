//
//  MoveCamera.swift
//  Gallery
//
//  Created by Lorran on 11/11/26.
//

import RealityKit
import simd
import Foundation

@MainActor

final class MoveCamera{
    private weak var camera: Entity?
    
    init(camera: Entity? = nil) {
        self.camera = camera
    }

    func attach(camera: Entity) {
        self.camera = camera
    }

    func move(to position: SIMD3<Float>, lookingAt target: SIMD3<Float>, duration: TimeInterval = 1.2) {
        guard let camera else { return }
        let destination = Entity()
        destination.look(
            at: target,
            from: position,
            upVector: SIMD3<Float>(0, 1, 0),
            relativeTo: nil
        )
        camera.move(
            to: destination.transform,
            relativeTo: nil,
            duration: duration,
            timingFunction: .easeInOut
        )
    }
}



