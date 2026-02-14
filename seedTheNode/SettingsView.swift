//
//  SettingsView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(NodeService.self) private var node

    var body: some View {
        NavigationStack {
            List {
                Section("Node") {
                    InfoRow(label: "Address", value: node.hostname)
                    InfoRow(label: "API Port", value: "\(node.port)")
                    InfoRow(label: "API URL", value: node.baseURL)
                    InfoRow(label: "Status", value: node.isOnline ? "Connected" : "Disconnected")
                }

                Section("IPFS") {
                    if let ipfs = node.ipfsInfo {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peer ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ipfs.peerId ?? "Unknown")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .textSelection(.enabled)
                        }
                        InfoRow(label: "Version", value: ipfs.agentVersion ?? "--")
                        InfoRow(label: "Peers", value: "\(ipfs.peers)")
                    } else {
                        InfoRow(label: "Status", value: "Not connected")
                    }
                }

                Section("App") {
                    InfoRow(label: "Version", value: "0.1.0")
                    InfoRow(label: "Build", value: "1")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(NodeService())
}
