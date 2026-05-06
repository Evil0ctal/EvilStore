// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

/// search tab. layout matches the wireframe in the maintainer's design notes:
/// search bar at top, list of apps, country selector top-right.
struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    countryMenu
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("search the app store", text: $vm.term)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: vm.term) { newValue in
                    vm.termChanged(newValue)
                }
            if !vm.term.isEmpty {
                Button {
                    vm.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - country menu

    private var countryMenu: some View {
        Menu {
            ForEach(CountryCatalog.popular, id: \.code) { c in
                Button {
                    vm.country = c.code
                    if vm.term.count >= 2 { vm.termChanged(vm.term) }
                } label: {
                    if vm.country == c.code {
                        Label(c.name, systemImage: "checkmark")
                    } else {
                        Text(c.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(vm.country)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
        }
    }

    // MARK: - content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            idleView
        case .searching:
            VStack {
                Spacer()
                ProgressView("searching")
                    .foregroundColor(.secondary)
                Spacer()
            }
        case .loaded:
            if vm.results.isEmpty {
                noResultsView
            } else {
                resultsList
            }
        case let .failed(message):
            errorView(message)
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("─ no results ─")
                .foregroundColor(.secondary)
            Text("type a name or bundle id to search\nstorefront: \(vm.country)")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.footnote)
            Spacer()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("nothing matched \"\(vm.term)\" in \(vm.country)")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("retry") { vm.termChanged(vm.term) }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            Spacer()
        }
    }

    private var resultsList: some View {
        List(vm.results) { app in
            SearchResultRow(app: app)
        }
        .listStyle(PlainListStyle())
    }
}

private struct SearchResultRow: View {
    let app: App

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(url: app.artworkURL)
                .frame(width: 56, height: 56)
                .cornerRadius(12)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                Text(app.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(app.version)
                    Text("·")
                    Text(app.formattedPrice)
                    if let g = app.primaryGenre {
                        Text("·")
                        Text(g).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ArtworkView: View {
    let url: URL?
    @State private var data: Data?
    @State private var loadedFor: URL?

    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.18))
                    .overlay(
                        Image(systemName: "app")
                            .foregroundColor(.secondary)
                    )
            }
        }
        .onAppear { kick() }
        .onChange(of: url) { _ in
            data = nil
            loadedFor = nil
            kick()
        }
    }

    private func kick() {
        guard let url, loadedFor != url else { return }
        loadedFor = url
        Task {
            do {
                let (bytes, _) = try await URLSession.shared.data(from: url)
                await MainActor.run { data = bytes }
            } catch {
                // intentionally silent — artwork is decorative
            }
        }
    }
}

#if DEBUG
struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView()
            .preferredColorScheme(.dark)
    }
}
#endif
