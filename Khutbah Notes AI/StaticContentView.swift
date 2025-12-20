//
//  StaticContentView.swift
//  Khutbah Notes AI
//

import SwiftUI

enum PlaceholderCopy {
    static let faq = """
    Add your FAQ here.

    You can replace this with a list of questions and answers, or link to a help center.
    """

    static let about = """
    Add your About content here.

    Share the mission, who it is for, and how you handle recordings.
    """

    static let terms = """
    Add your Terms of Service here.

    Include usage rules, subscription terms, and limitations.
    """

    static let privacy = """
    Add your Privacy Policy here.

    Describe what data you collect, how it's used, and how users can request deletion.
    """
}

struct StaticContentView: View {
    let title: String
    let bodyText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(bodyText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Theme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle(title)
        .background(Theme.background.ignoresSafeArea())
    }
}
