import SwiftUI

struct SkeletonList: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonSongRow()
                    Divider().padding(.leading, 72)
                }
            }
        }
    }
}
