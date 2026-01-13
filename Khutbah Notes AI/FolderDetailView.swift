import SwiftUI

struct FolderDetailView: View {
    let folder: Folder
    let lectures: [Lecture]
    @Binding var selectedTab: Int
    var onRename: (Lecture) -> Void
    var onMove: (Lecture) -> Void
    var onDelete: (Lecture) -> Void
    var onAddLecture: () -> Void
    var onRenameFolder: (Folder) -> Void
    var onDeleteFolder: (Folder) -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if lectures.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No lectures in this folder")
                            .font(Theme.titleFont)
                        Text("Use the three dots on a lecture to move it here.")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.mutedText)
                        Button(action: onAddLecture) {
                            Text("Add Khutbah/Lecture")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .cornerRadius(14)
                    .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                } else {
                    VStack(spacing: 12) {
                        ForEach(lectures) { lecture in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    LectureDetailView(
                                        lecture: lecture,
                                        selectedRootTab: $selectedTab
                                    )
                                } label: {
                                    LectureCardView(lecture: lecture)
                                }
                                .buttonStyle(.plain)
                                
                                Menu {
                                    Button("Rename") { onRename(lecture) }
                                    Button("Move to Folder") { onMove(lecture) }
                                    Button(role: .destructive) {
                                        onDelete(lecture)
                                    } label: {
                                        Text("Delete")
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Theme.mutedText)
                                        .padding(10)
                                        .background(Color.white.opacity(0.92))
                                        .clipShape(Circle())
                                        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                                }
                                .padding(.trailing, 12)
                                .padding(.top, 12)
                            }
                        }
                        
                        Button(action: onAddLecture) {
                            Text("Add Khutbah/Lecture")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Rename") { onRenameFolder(folder) }
                    Button(role: .destructive) {
                        onDeleteFolder(folder)
                    } label: {
                        Text("Delete")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.mutedText)
                }
            }
        }
    }
}
