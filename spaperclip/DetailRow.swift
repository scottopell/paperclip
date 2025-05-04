//
//  DetailRow.swift
//  spaperclip
//
//  Created by Scott Opell on 5/4/25.
//
import SwiftUI

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
