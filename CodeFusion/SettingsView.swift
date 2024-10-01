//
//  SettingsView.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-09-30.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("pathOption") private var pathOptionRawValue: String = "full"
    @EnvironmentObject var exclusionManager: ExclusionManager  // Access ExclusionManager from environment

    @State private var newExcludedItem: String = ""  // For adding new items

    var body: some View {
        TabView {
            // General settings tab
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            // Exclusions tab
            ExclusionsSettingsView()
                .tabItem {
                    Label("Exclusions", systemImage: "minus.circle")
                }
        }
        .frame(width: 500, height: 300) // Adjust the size as needed
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("pathOption") private var pathOptionRawValue: String = "full"

    var body: some View {
        Form {
            // Path option picker
            Picker("Path Display", selection: $pathOptionRawValue) {
                Text("Full Path").tag("full")
                Text("Relative Path").tag("relative")
            }
            .padding()
        }
        .padding()
    }
}

struct ExclusionsSettingsView: View {
    @EnvironmentObject var exclusionManager: ExclusionManager
    @State private var newExcludedItem: String = ""  // For adding new items

    var body: some View {
        Form {
            // Dynamic list of excluded items
            Section(header: Text("Excluded Items")) {
                List {
                    ForEach(exclusionManager.excludedItems, id: \.self) { item in
                        HStack {
                            Text(item)
                            Spacer()
                            Button(action: {
                                removeExcludedItem(item)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onDelete(perform: deleteExcludedItem)
                }

                // TextField to add new exclusion
                HStack {
                    TextField("Add new excluded item", text: $newExcludedItem)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button(action: addNewExcludedItem) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .disabled(newExcludedItem.isEmpty)
                }
                .padding(.top)
            }

            Text("Examples: .git, *.entitlements, *.xcassets")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .padding()
    }

    private func addNewExcludedItem() {
        let trimmedItem = newExcludedItem.trimmingCharacters(in: .whitespaces)
        guard !trimmedItem.isEmpty, !exclusionManager.excludedItems.contains(trimmedItem) else { return }
        exclusionManager.addExcludedItem(trimmedItem)
        newExcludedItem = ""  // Reset the input field
    }

    private func removeExcludedItem(_ item: String) {
        exclusionManager.removeExcludedItem(item)
    }

    private func deleteExcludedItem(at offsets: IndexSet) {
        offsets.forEach { index in
            let item = exclusionManager.excludedItems[index]
            removeExcludedItem(item)
        }
    }
}
