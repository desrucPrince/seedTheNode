//
//  OverviewView.swift
//  seedTheNode
//
//  Created by Darrion Johnson on 2/14/26.
//

import SwiftUI

struct OverviewView: View {
    @Environment(NodeService.self) private var node

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Node Status Card
                    GroupBox {
                        HStack {
                            if node.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking...")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Circle()
                                    .fill(node.isOnline ? .green : .red)
                                    .frame(width: 12, height: 12)
                                Text(node.isOnline ? "Online" : "Offline")
                                    .font(.headline)
                                    .foregroundStyle(node.isOnline ? .green : .red)
                            }
                            Spacer()
                            Text(node.hostname)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = node.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } label: {
                        Label("Node Status", systemImage: "server.rack")
                    }

                    // IPFS Info Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            if let ipfs = node.ipfsInfo {
                                InfoRow(
                                    label: "Peer ID",
                                    value: ipfs.peerId.map { String($0.prefix(12)) + "..." } ?? "--"
                                )
                                InfoRow(label: "Version", value: ipfs.agentVersion ?? "--")
                                InfoRow(label: "Peers", value: "\(ipfs.peers)")
                            } else {
                                InfoRow(label: "Peer ID", value: "--")
                                InfoRow(label: "Peers", value: "--")
                            }
                        }
                    } label: {
                        Label("IPFS Node", systemImage: "network")
                    }

                    // Storage Card
                    GroupBox {
                        if let s = node.storage {
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(label: "Total", value: "\(s.totalGB) GB")
                                InfoRow(label: "Free", value: "\(s.freeGB) GB")

                                ProgressView(value: s.usedGB, total: s.totalGB)
                                    .tint(s.freeGB < 10 ? .red : .blue)
                            }
                        } else {
                            InfoRow(label: "Storage", value: "--")
                        }
                    } label: {
                        Label("Storage", systemImage: "internaldrive")
                    }

                    // Quick Stats
                    GroupBox {
                        HStack(spacing: 24) {
                            StatItem(title: "Tracks", value: "\(node.trackCount)")
                            StatItem(title: "Pinned", value: "\(node.trackCount)")
                            StatItem(
                                title: "Peers",
                                value: node.ipfsInfo.map { "\($0.peers)" } ?? "--"
                            )
                        }
                        .frame(maxWidth: .infinity)
                    } label: {
                        Label("Quick Stats", systemImage: "chart.bar")
                    }

                    if let checked = node.lastChecked {
                        Text("Last checked: \(checked.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
            .navigationTitle("SeedTheNode")
            .refreshable {
                await node.checkHealth()
            }
            .task {
                await node.checkHealth()
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontDesign(.monospaced)
        }
        .font(.subheadline)
    }
}

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OverviewView()
        .environment(NodeService())
}
