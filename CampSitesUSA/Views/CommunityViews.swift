import SwiftUI
import SwiftData
import AuthenticationServices

/// "From other campers" on the site card: the weighted score, how many ratings are verified, recent
/// tags with their age, and the latest ratings. Always shows how the score is worked out.
struct CommunityRatingsSection: View {
    let site: Site
    /// Loaded by the site card (shared with the Safety section).
    let data: SiteCommunity?
    let failed: Bool
    var reload: () async -> Void = {}
    @Environment(CommunityAccount.self) private var account
    @State private var showAll = false
    @State private var reporting: CommunityRating?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("From other campers", icon: "star")
            if let data {
                if data.summary.count == 0 {
                    Text("No shared ratings yet. Stay here and rate it to be the first.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    summary(data.summary)
                    // Safety tags have their own place in the Safety section.
                    let general = data.recentTags.filter { !SafetyTag.isSafety($0.tag) }
                    if !general.isEmpty { tags(general) }
                    ForEach(showAll ? data.ratings : Array(data.ratings.prefix(3))) { r in
                        CommunityRatingRow(rating: r)
                            .contextMenu {
                                if account.isSignedIn && !r.mine {
                                    Button("Report", systemImage: "flag") { reporting = r }
                                }
                            }
                    }
                    if data.ratings.count > 3 {
                        Button(showAll ? "Show fewer" : "Show all \(data.ratings.count)") {
                            withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() }
                        }
                        .font(.subheadline.weight(.semibold)).tint(.sunset)
                    }
                    Text("Score weighs on-site (verified) ratings double and newer stays more than old ones.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if failed {
                Text("Couldn't load shared ratings right now.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading ratings from other campers…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Report this rating?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                            titleVisibility: .visible, presenting: reporting) { r in
            ForEach(["Spam or ad", "Offensive", "Not about this site", "Looks fake"], id: \.self) { reason in
                Button(reason) { Task { if await account.report(r, reason: reason) { await reload() } } }
            }
        } message: { _ in
            Text("Ratings reported by several campers are hidden.")
        }
    }

    private func summary(_ s: CommunitySummary) -> some View {
        HStack(spacing: 12) {
            if let score = s.score {
                Text(score.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.sunset)
            }
            VStack(alignment: .leading, spacing: 3) {
                StarRatingView(rating: s.score ?? 0, size: .subheadline)
                HStack(spacing: 4) {
                    Text("\(s.count) camper\(s.count == 1 ? "" : "s")")
                    if s.verifiedCount > 0 {
                        Text("·")
                        Label("\(s.verifiedCount) verified", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.meadow)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Recent tags with how long ago someone last said it: "Rough road · 2 weeks ago".
    private func tags(_ tags: [RecentTag]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(tags.prefix(6), id: \.tag) { t in
                HStack(spacing: 4) {
                    Text(t.tag).fontWeight(.semibold)
                    if let d = RatingsAPI.day(t.latest) { Text("· \(Self.age(d))").foregroundStyle(.secondary) }
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((t.tag == "Rough road" || t.tag == "Crowded" ? Color.canyon : Color.sunset).opacity(0.12), in: .capsule)
            }
        }
    }

    static func age(_ d: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<14: return "\(days) days ago"
        case ..<60: return "\(days / 7) weeks ago"
        case ..<365: return "\(days / 30) months ago"
        default: return days < 730 ? "a year ago" : "\(days / 365) years ago"
        }
    }
}

private struct CommunityRatingRow: View {
    let rating: CommunityRating

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StarRatingView(rating: Double(rating.rating))
                if rating.verified {
                    Label("Verified visit", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Color.meadow)
                }
                if rating.mine {
                    Text("You").font(.caption2.weight(.bold)).foregroundStyle(Color.dusk)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.dusk.opacity(0.12), in: .capsule)
                }
                Spacer()
                if let d = rating.date { Text(CommunityRatingsSection.age(d)).font(.caption).foregroundStyle(.secondary) }
            }
            if !rating.tags.isEmpty {
                Text(rating.tags.joined(separator: " · ")).font(.caption.weight(.medium)).foregroundStyle(Color.sunset)
            }
            if let c = rating.carrier, let s = rating.signal {
                Label("\(c): \(CellSignal.levels[max(0, min(3, s))])", systemImage: CellSignal.bars(s))
                    .font(.caption).foregroundStyle(CellSignal.color(s))
            }
            if !rating.note.isEmpty { Text(rating.note).font(.subheadline) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Sign in with Apple, styled for the current appearance. Only Apple's user id is used; no name or email.
struct ShareRatingsSignIn: View {
    @Environment(CommunityAccount.self) private var account
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var working = false

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []  // no name, no email
        } onCompletion: { result in
            working = true
            Task {
                await account.completeSignIn(result, context: context)
                working = false
            }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 48)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .disabled(working)
        .overlay { if working { ProgressView().tint(.white) } }
    }
}

/// Settings › Shared ratings.
struct CommunityAccountSection: View {
    @Environment(CommunityAccount.self) private var account
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        @Bindable var account = account
        Section {
            if account.isSignedIn {
                Label("Signed in with Apple", systemImage: "checkmark.seal.fill").foregroundStyle(Color.meadow)
                Toggle("Share my ratings", isOn: $account.shareRatings)
                    .tint(.meadow)
                    .onChange(of: account.shareRatings) { _, on in if on { Task { await account.sync(context: context) } } }
                if account.syncing {
                    HStack { ProgressView(); Text("Sharing your ratings…").foregroundStyle(.secondary) }
                }
                Button("Sign out") { account.signOut() }
                Button("Delete account and shared ratings", role: .destructive) { confirmDelete = true }
                    .disabled(deleting)
            } else {
                ShareRatingsSignIn()
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            if let error = account.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.berry)
            }
        } header: {
            Text("Shared ratings")
        } footer: {
            Text("Sign in to share your ratings with other campers. They appear without your name, and ezcamp never sees your email. Ratings logged on-site are marked verified.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                deleting = true
                Task {
                    _ = await account.deleteAccount(context: context)
                    deleting = false
                }
            }
        } message: {
            Text("This removes every rating you shared from ezcamp' server. Your ratings stay on this iPhone.")
        }
    }
}
