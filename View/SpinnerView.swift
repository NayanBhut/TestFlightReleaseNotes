//
//  SpinnerView.swift
//  App Store
//
//  Created by Nayan Bhut on 23/04/24.
//

import SwiftUI

struct SpinnerView: View {
    var body: some View {
        ProgressView()
            .transformEffect(CGAffineTransform(scaleX: 0.5, y: 0.5))
            .transformEffect(CGAffineTransform(translationX: 10, y: 10))
    }
}

#Preview {
    SpinnerView()
}
