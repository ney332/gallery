//
//  MoveCamera.swift
//  Gallery
//
//  Created by Lorran on 11/11/26.
//

import RealityKit
import simd

@MainActor

final class MoveCamera{
    private weak var camera: Entity?
    private var overViewTransform: Transform?
    
    init(camera: Entity? = nil, overViewTransform: Transform? = nil) {
        self.camera = camera
        self.overViewTransform = overViewTransform
    }
}



