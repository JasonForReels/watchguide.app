import re

filepath = 'WatchGuide-MovieandTVtracker/Views/BrowseView.swift'
with open(filepath, 'r') as f:
    content = f.read()

# I will replace the entirety of `struct DisneyHubSheet` up to `private func loadContent() async {`
pattern = r"struct DisneyHubSheet: View \{[\s\S]*?private func loadContent\(\) async \{"
match = re.search(pattern, content)

if match:
    new_code = """struct DisneyHubSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\\.dismiss) private var dismiss
    @State private var movies: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    Color(red: 0.05, green: 0.1, blue: 0.4).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.2)
                }
            } else if let errorMessage {
                ZStack {
                    Color(red: 0.05, green: 0.1, blue: 0.4).ignoresSafeArea()
                    Text(errorMessage).foregroundColor(.white)
                }
            } else {
                ImmersiveHubLayout(
                    items: movies,
                    logo: Image("Walt Disney Pictures").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundColor(.white),
                    backgroundColor: Color(red: 0.05, green: 0.1, blue: 0.4),
                    selectedItem: $selectedItem
                )
            }
        }
        .task { await loadContent() }
    }

    private func loadContent() async {"""
    
    content = content[:match.start()] + new_code + content[match.end():]
    with open(filepath, 'w') as f:
        f.write(content)
    print("Fixed DisneyHubSheet")
else:
    print("Pattern not found!")

