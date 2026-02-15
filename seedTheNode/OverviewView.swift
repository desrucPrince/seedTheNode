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
                VStack(spacing: 24) {
                    // Hero status indicator
                    StatusHeroView(
                        isOnline: node.isOnline,
                        isLoading: node.isLoading,
                        errorMessage: node.lastError
                    )

                    // Uptime card
                    if node.isOnline, let uptime = node.uptime {
                        UptimeCard(uptime: uptime)
                    }

                    // Stats row
                    HStack(spacing: 12) {
                        StatCard(
                            icon: "music.note",
                            value: "\(node.trackCount)",
                            label: "Tracks",
                            accent: .purple
                        )

                        StorageCard(storage: node.storage)

                        StatCard(
                            icon: "antenna.radiowaves.left.and.right",
                            value: node.ipfsInfo.map { "\($0.peers)" } ?? "--",
                            label: "Peers",
                            accent: .blue
                        )
                    }

                    // Node details (collapsed by default)
                    NodeDetailsSection(node: node)

                    // Last checked
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

// MARK: - Hero Status Indicator

private struct StatusHeroView: View {
    let isOnline: Bool
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            NodeOrbView(isOnline: isOnline, isLoading: isLoading)
                .frame(width: 180, height: 180)

            Text(statusMessage)
                .font(.title3.bold())

            if let error = errorMessage, !isLoading {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var statusMessage: String {
        if isLoading { return "Checking..." }
        return isOnline ? "Your Node is Running" : "Node Offline"
    }
}

// MARK: - Uptime Card

private struct UptimeCard: View {
    let uptime: UptimeInfo

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Uptime")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let system = uptime.systemSeconds {
                    Text(formatUptime(system))
                        .font(.subheadline.bold().monospacedDigit())
                } else if let api = uptime.apiSeconds {
                    Text(formatUptime(api))
                        .font(.subheadline.bold().monospacedDigit())
                } else {
                    Text("--")
                        .font(.subheadline.bold())
                }
            }

            Spacer()

            if let api = uptime.apiSeconds, let system = uptime.systemSeconds, api != system {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("API")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(formatUptime(api))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    var accent: Color = .blue

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(accent)

            Text(value)
                .font(.title2.bold().monospacedDigit())

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Storage Card (with ring gauge)

private struct StorageCard: View {
    let storage: StorageInfo?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: usedFraction)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
            }

            Text(freeLabel)
                .font(.title3.bold().monospacedDigit())

            Text("Free")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var usedFraction: Double {
        guard let s = storage, s.totalGB > 0 else { return 0 }
        return min(1, s.usedGB / s.totalGB)
    }

    private var freeLabel: String {
        guard let s = storage else { return "--" }
        let free = s.freeGB
        if free >= 100 {
            return "\(Int(free))G"
        } else if free >= 10 {
            return String(format: "%.0fG", free)
        } else {
            return String(format: "%.1fG", free)
        }
    }

    private var accentColor: Color {
        guard let s = storage else { return .blue }
        if s.freeGB < 10 { return .red }
        if s.freeGB < 20 { return .orange }
        return .green
    }
}

// MARK: - Node Details (Collapsible)

private struct NodeDetailsSection: View {
    let node: NodeService
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Node Details", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Address", value: node.hostname)

                if let ipfs = node.ipfsInfo {
                    InfoRow(
                        label: "Peer ID",
                        value: ipfs.peerId.map { String($0.prefix(16)) + "..." } ?? "--"
                    )
                    InfoRow(label: "IPFS Version", value: ipfs.agentVersion ?? "--")
                    InfoRow(label: "Peers", value: "\(ipfs.peers)")
                }
            }
            .padding(.top, 8)
        }
        .tint(.secondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - Shared Helpers

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

#Preview {
    OverviewView()
        .environment(NodeService())
}
