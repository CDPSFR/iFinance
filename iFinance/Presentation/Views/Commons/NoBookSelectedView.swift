//
//  NoBookSelectedView.swift
//  iFinance
//
//  Created by charles.du.portal on 28/12/2025.
//



import SwiftUI

struct NoBookSelectedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucun livre sélectionné")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("Créez ou sélectionnez un livre pour commencer")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Section en cours de développement")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
