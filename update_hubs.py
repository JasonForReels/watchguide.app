import re

def update_file(filepath, bg_color, logo_code):
    with open(filepath, 'r') as f:
        content = f.read()

    # Find the start of `var body: some View {`
    match = re.search(r'    var body: some View \{', content)
    if not match:
        print(f"Could not find body in {filepath}")
        return

    # Find the start of `private func loadContent() async {`
    match_load = re.search(r'    // MARK: - Data Loading\s+private func loadContent\(\) async \{', content)
    if not match_load:
        match_load = re.search(r'    private func loadContent\(\) async \{', content)

    if not match_load:
        print(f"Could not find loadContent in {filepath}")
        return

    start_idx = match.start()
    end_idx = match_load.start()

    new_body = f"""    var body: some View {{
        Group {{
            if loading {{
                ZStack {{
                    {bg_color}.ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.2)
                }}
            }} else {{
                ImmersiveHubLayout(
                    items: movies,
                    logo: {logo_code},
                    backgroundColor: {bg_color},
                    selectedItem: $selectedItem
                )
            }}
        }}
        .task {{ await loadContent() }}
    }}

"""
    new_content = content[:start_idx] + new_body + content[end_idx:]
    
    # We no longer need selectedTab, horizontalSizeClass, dismiss from Environment in the main view 
    # since ImmersiveHubLayout handles them if needed. But ImmersiveHubLayout needs `selectedItem`, which is a `@Binding`.
    # Let's remove selectedTab since it's unused now.
    new_content = re.sub(r'\s*@State private var selectedTab.*?//.*?\n', '\n', new_content)
    new_content = re.sub(r'\s*private var displayedItems[\s\S]*?\}\n', '', new_content)
    new_content = re.sub(r'\s*private var columns[\s\S]*?\}\n', '', new_content)
    new_content = re.sub(r'\s*@Environment\(\\\.dismiss\).*?\n', '\n', new_content)
    new_content = re.sub(r'\s*@Environment\(\\\.horizontalSizeClass\).*?\n', '\n', new_content)

    with open(filepath, 'w') as f:
        f.write(new_content)
    print(f"Updated {filepath}")

# Update Pixar
update_file(
    'WatchGuide-MovieandTVtracker/Views/PixarHubView.swift',
    'Color(red: 0.05, green: 0.1, blue: 0.3)',
    'Image("Pixar").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(.white)'
)

# Update DC
update_file(
    'WatchGuide-MovieandTVtracker/Views/DCHubView.swift',
    'Color(red: 0.02, green: 0.05, blue: 0.2)', # Darker blue for DC matches 'Color.black' but slightly blue
    'Image("DC Comics").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(.white)'
)

# Update Marvel
update_file(
    'WatchGuide-MovieandTVtracker/Views/MarvelHubView.swift',
    'Color(red: 0.05, green: 0.0, blue: 0.0)',
    'Image("Marvel Studios").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(.white)'
)

