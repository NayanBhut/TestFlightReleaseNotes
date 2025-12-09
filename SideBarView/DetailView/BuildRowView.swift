//
//  BuildRowView.swift
//  App Store
//
//  Created by Nayan Bhut on 09/12/25.
//

import SwiftUI

struct BuildRowView: View {
    let buildId: String
    let version: String
    let uploadedDate: String
    let processingState: String
    let isExpired: Bool
    let whatsNew: String
    let localizationId: String?
    let selectedVersionString: String
    let formatDate: (String?) -> String
    let formatCustomDate: (String) -> String?
    let getBuildStatus: (String, Bool) -> (String, Color)
    let onTextChange: (String) -> Void
    let onUpdate: () -> Void
    let isUpdating: Bool
    
    @State private var whatsNewText: String = ""
    @State private var hasChanges: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(selectedVersionString)(\(version))")
                    .font(.headline)
                
                Text(formatDate(uploadedDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                let status = getBuildStatus(processingState, isExpired)
                Text(status.0)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.1.opacity(0.2))
                    .foregroundColor(status.1)
                    .cornerRadius(4)
                
                if let customDate = formatCustomDate(uploadedDate) {
                    Text(customDate)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Update") {
                        onUpdate()
                        hasChanges = false
                    }
                    .disabled(!hasChanges || whatsNewText.isEmpty)
                }
            }
            
            TextEditor(text: $whatsNewText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasChanges ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: hasChanges ? 2 : 1)
                )
                .scrollContentBackground(.hidden)
                .onChange(of: whatsNewText) { newValue in
                    hasChanges = newValue != whatsNew
                    onTextChange(newValue)
                }
                .onAppear {
                    whatsNewText = whatsNew
                    hasChanges = false
                }
        }
        .padding(.vertical, 4)
    }
}
