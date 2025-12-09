//
//  VersionChip.swift
//  App Store
//
//  Created by Nayan Bhut on 09/12/25.
//

import SwiftUI

struct VersionChip: View {
    let version: PreReleaseVersionsModel
    let isSelected: Bool
    
    var body: some View {
        Text(version.version ?? "Unknown")
            .font(.system(.body, design: .monospaced))
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
    }
}
