import SwiftUI

struct SafeStorageView: View {
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var safeStorageManager: SafeStorageManager
    @FocusState private var isSearchFocused: Bool
    @State private var showPhotosView: Bool = false
    @State private var showVideosView: Bool = false
    @State private var showContactsView: Bool = false
    @State private var showDocumentsView: Bool = false
    @Binding var isPaywallPresented: Bool

    // Simplified recent files logic
    private var recentFiles: [SafeStorageFile] {
        var files: [SafeStorageFile] = []
        
        // Add recent photos
        let recentPhotos = safeStorageManager.getRecentPhotos(limit: 2)
        files.append(contentsOf: recentPhotos.map { photo in
            SafeStorageFile(
                name: photo.fileName,
                icon: "photo.fill"
            )
        })
        
        return Array(files.prefix(5)) // Limit to 5 items max
    }
    
    // Dynamic categories based on storage counts
    private var categories: [SafeStorageCategory] {
        let photosCount = safeStorageManager.getPhotosCount()
        let documentsCount = safeStorageManager.getDocumentsCount()
        let videosCount = safeStorageManager.getVideosCount()
        let contactsCount = safeStorageManager.getContactsCount()
        
        return [
            SafeStorageCategory(
                title: "Docs",
                count: documentsCount == 0 ? "No files" : "\(documentsCount) \(documentsCount == 1 ? "file" : "files")",
                icon: "folder.fill",
                color: Color.purple
            ),
            SafeStorageCategory(
                title: "Photos",
                count: photosCount == 0 ? "No files" : "\(photosCount) \(photosCount == 1 ? "file" : "files")",
                icon: "photo.fill",
                color: Color.pink
            ),
            SafeStorageCategory(
                title: "Videos",
                count: videosCount == 0 ? "No files" : "\(videosCount) \(videosCount == 1 ? "file" : "files")",
                icon: "video.fill",
                color: Color.blue
            ),
            SafeStorageCategory(
                title: "Contacts",
                count: contactsCount == 0 ? "No items" : "\(contactsCount) \(contactsCount == 1 ? "item" : "items")",
                icon: "person.fill",
                color: Color.green
            )
        ]
    }
    
    private func getDocumentIcon(for fileExtension: String?) -> String {
        guard let ext = fileExtension?.lowercased() else { return "doc.fill" }
        
        switch ext {
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "rectangle.fill.on.rectangle.fill"
        default:
            return "doc.fill"
        }
    }
    
    var body: some View {
        ZStack {
            // Gradient Background - New Design
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    
                    // Header
                    headerView()
                    
                    // Search bar
                    searchBar()
                    
                    // Category cards
                    categoryCardsView()
                    
                    // Last added section
                    lastAddedSection()
                    
                    // Dynamic bottom spacing based on search state
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .background(Color(UIColor.systemGray6))
        .navigationBarHidden(true)
        .onTapGesture {
            isSearchFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showPhotosView) {
            MainPhotosView()
        }
        .fullScreenCover(isPresented: $showVideosView) {
            VideosView()
                .environmentObject(safeStorageManager)
        }
        .fullScreenCover(isPresented: $showContactsView) {
            AICleanerSafeContactsView()
        }
        .fullScreenCover(isPresented: $showDocumentsView) {
            DocListView()
                .environmentObject(safeStorageManager)
        }
    }
    
    // MARK: - Subviews
    
    private func headerView() -> some View {
        HStack {
            Text("Safe Storage")
                .font(.largeTitle.bold())
                .foregroundColor(.black)
            Spacer()
        }
    }
    
    private func searchBar() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search your files...", text: $searchText)
                .foregroundColor(.black)
                .accentColor(.gray)
                .font(.body)
                .focused($isSearchFocused)
            
            if isSearchFocused && !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
    }
    
    private func categoryCardsView() -> some View {
        VStack(spacing: 16) {
            ForEach(categories) { category in
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: category.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(category.color)
                        .frame(width: 48, height: 48)
                        .background(category.color.opacity(0.1))
                        .cornerRadius(12)
                    
                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.headline.bold())
                            .foregroundColor(.black)
                        
                        Text(category.count)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer() // Pushes the content to the left
                    
                    // Chevron icon
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
                .onTapGesture {
                    if category.title == "Docs" {
                        showDocumentsView = true
                    } else if category.title == "Photos" {
                        showPhotosView = true
                    } else if category.title == "Videos" {
                        showVideosView = true
                    } else if category.title == "Contacts" {
                        showContactsView = true
                    }
                }
            }
        }
    }
    
    private func lastAddedSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Last Added")
                    .font(.title2.bold())
                    .foregroundColor(.black)
                Spacer()
            }
            
            if recentFiles.isEmpty {
                Text("No recent files added.")
                    .foregroundColor(.gray)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentFiles.enumerated()), id: \.offset) { index, file in
                        fileRow(file: file)
                        
                        if index < recentFiles.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
            }
        }
    }
    
    private func fileRow(file: SafeStorageFile) -> some View {
        HStack(spacing: 16) {
            Image(systemName: file.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 36, height: 36)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
            
            Text(file.name)
                .font(.body)
                .foregroundColor(.black)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
}
