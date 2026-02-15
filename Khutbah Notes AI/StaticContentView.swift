//
//  StaticContentView.swift
//  Khutbah Notes AI
//

import Foundation
import SwiftUI

enum PlaceholderCopy {
    static let faq = """
    **FAQ**

    **1) What is Khutbah Notes?**
    Khutbah Notes is an iOS app that records uploaded audio and generates a transcript, summary, and key takeaways. Translation is available on demand.

    **2) What do I get for free?**
    Free users receive 60 minutes total of transcription + summarization to try the app.

    **3) What do I get with Premium?**
    Premium includes 500 minutes per month of transcription + summarization. (Translation features, if used, may be processed separately within the app's available options.)

    **4) Do free minutes reset each month?**
    The free tier is a one-time 60-minute allotment. Premium minutes reset monthly.

    **5) What happens if I run out of minutes?**
    If you reach your limit, you won't be able to process additional audio until your Premium minutes reset or you upgrade (if you're on the free tier).

    **6) How does it work?**
    Record in the app. Khutbah Notes processes the audio to create a transcript, then generates a structured summary and key points. Translation is available when you choose it.

    **7) Is the transcript or summary always accurate?**
    Not always. Automated transcription and AI-generated summaries can contain errors - especially with background noise, multiple speakers, accents, or Arabic terms. Please verify anything important.

    **8) Do I need internet access?**
    Yes. Transcription, summarization, and translation require an internet connection.

    **9) Will Arabic translation be in Arabic script?**
    Yes. Arabic and Urdu translations are provided in Arabic and Urdu letters (not transliteration).

    **10) Do you store my audio?**
    Yes. Audio will be stored for up to 30 days, then it may be deleted automatically. You can delete recordings sooner within the app.

    **11) Do you store transcripts and summaries?**
    Yes. Transcripts, summaries, translations, and related metadata are saved to your library so you can revisit them later (until you delete them). Limited backup retention may apply.

    **12) Can I export or share my notes?**
    Yes. You can export and share transcripts and summaries using iOS sharing options. If you share content, it becomes subject to the receiving platform's policies.

    **13) Do you send notifications?**
    If you enable notifications, we may send alerts like "Your summary is ready." You can disable notifications anytime in iOS Settings.

    **14) What analytics do you use?**
    We use Firebase Analytics to understand app usage and improve performance. We do not sell personal information.

    **15) Who processes transcription and summaries?**
    We use third-party AI processing (including OpenAI) to generate transcripts, summaries, and translations as part of the features you request.

    **16) Do I need permission to record at a masjid or event?**
    You are responsible for complying with local laws and venue policies. Some places require explicit permission to record.

    **17) How do subscriptions work?**
    Premium is billed via Apple In-App Purchase. You can manage or cancel in your Apple ID settings. Refunds are handled by Apple under Apple's policies.

    **18) How do I get help?**
    Email support@khutbah-notes.com with your device model, iOS version, and a short description of the issue.
    """

    static let about = """
    Created by a Muslim who struggled to focus and remember Khutbahs, Khutbah Notes helps you capture and remember the reminders that matter. Record a khutbah or lecture and Khutbah Notes turns it into a clean transcript with a structured summary, key takeaways, and optional translations so you can revisit what you learned, share it with family and friends, and reflect throughout the week.

    Our goal is simple: make it easier to retain beneficial knowledge and act on it. Khutbah Notes is a personal companion for listening and reflection and is not a replacement for the speaker, the khutbah, or scholarly guidance.
    """

    static let masjidPartnerships = """
    **Masjid Partnerships**
    We help masjids share khutbahs and summaries with their congregation in a searchable library. Help your community remember and revisit khutbah/lecture takeaways.

    **If your masjid already posts khutbahs online**
    We can add your masjid to our Masjid Channels section and post the khutbah audio/video on our app. We will also create summaries + key points for each khutbah.

    **If your masjid doesn't post khutbahs online**
    An approved community member can record khutbahs on their phone and submit them for publishing with required approvals. We will also create summaries + key points for each khutbah.

    **Permission & takedowns**
    We only publish with permission. If anything needs correction or removal, contact us and we'll respond promptly.

    **Contact**
    [support@khutbah-notes.com](mailto:support@khutbah-notes.com)
    """

    static let terms = """
    **Terms of Service - Khutbah Notes**

    - **Effective Date:** December 23, 2025
    - **App Name:** Khutbah Notes ("Khutbah Notes," "we," "us," or "our")
    - **Support Contact:** support@khutbah-notes.com

    These Terms of Service ("Terms") govern your access to and use of the Khutbah Notes iOS application and related services (the "Service"). By downloading, accessing, or using the Service, you agree to these Terms.

    If you do not agree, do not use the Service.

    **1) Who We Are**

    Khutbah Notes provides tools to record or upload audio and generate transcripts, summaries, and translations for personal reference and organization.

    **2) Eligibility**

    You must be at least 13 years old (or the minimum age required in your jurisdiction) to use the Service. By using the Service, you represent that you meet this requirement.

    **3) Accounts**

    The Service may use an account identifier (including anonymous identifiers) to associate your content with your device/account. You are responsible for maintaining the confidentiality of your device and any access credentials. You are responsible for all activity that occurs under your account.

    **4) Your Content**

    **A. Content You Provide**
    "User Content" includes audio recordings, uploads, notes, transcripts, summaries, translations, and any other content you submit or generate using the Service.

    **B. Ownership**
    You retain ownership of your User Content. We do not claim ownership of your original recordings or text.

    **C. License to Operate the Service**
    You grant Khutbah Notes a limited, worldwide, non-exclusive, royalty-free license to host, store, process, transmit, and display your User Content only to the extent necessary to operate, maintain, and improve the Service (including creating transcripts, summaries, and translations at your request).

    **D. Responsibility for User Content**
    You are responsible for your User Content and represent that you have all rights needed to provide it, including any necessary permissions from speakers or rights holders.

    **5) Acceptable Use**

    You agree not to:
    - Use the Service to violate any law or regulation
    - Upload or record content you do not have the right to record, use, or share
    - Infringe intellectual property, privacy, or other rights of others
    - Attempt to reverse engineer, interfere with, or disrupt the Service
    - Use the Service to distribute malware or engage in abusive, harmful, or fraudulent behavior
    - Use the Service in a way that imposes an unreasonable load on our infrastructure

    We may suspend or terminate access if we reasonably believe you are violating these Terms.

    **6) AI Features and Limitations**

    The Service may use third-party AI providers (including OpenAI) to process audio and text for transcription, summarization, and translation.

    You understand and agree:
    - Outputs may be inaccurate, incomplete, or contain errors.
    - You are responsible for how you use outputs and for verifying information before relying on it.
    - The Service is a productivity tool and does not replace qualified professional guidance or scholarly authority.

    **7) Audio Storage and Retention**

    Audio recordings and uploads may be stored on our servers for up to 30 days, after which they may be deleted automatically (unless you delete them sooner).

    Transcripts, summaries, translations, and related metadata may be retained as long as you keep them in your library (or until you delete them), subject to limited backup retention.

    **8) Notifications**

    If you opt in to push notifications, we may send notifications related to Service functionality (e.g., "your summary is ready," reminders, or product updates). You can disable notifications at any time in iOS Settings.

    **9) Subscriptions, Payments, and Refunds**

    **A. Apple Billing**
    Paid features may be offered through auto-renewing subscriptions and/or in-app purchases billed via Apple's In-App Purchase system. Prices and billing terms are shown at purchase.

    **B. Renewals & Cancellation**
    Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. You can manage or cancel in Apple ID Settings.

    **C. Refunds**
    Refund requests are handled by Apple under Apple's policies. We do not control Apple's refund decisions.

    **D. Changes**
    We may change subscription offerings, pricing, or features, but changes will apply prospectively and as permitted by Apple's rules and applicable law.

    **10) Third-Party Services**

    The Service relies on third-party providers for certain functionality, such as:
    - Google/Firebase (hosting, storage, analytics)
    - OneSignal (push notifications)
    - OpenAI (AI processing)

    Your use of the Service may be subject to these providers' terms and policies. We are not responsible for third-party services outside our control.

    **11) Intellectual Property**

    The Service, including its software, design, branding, and non-user content, is owned by Khutbah Notes or its licensors and is protected by applicable intellectual property laws. You may not copy, modify, distribute, sell, or lease any part of the Service except as allowed by these Terms.

    **12) Termination**

    You may stop using the Service at any time. We may suspend or terminate your access to the Service if:
    - you violate these Terms,
    - we must do so to comply with law, or
    - we discontinue the Service (in whole or in part).

    Upon termination, your right to use the Service will stop. Some provisions (like disclaimers and limitation of liability) will survive.

    **13) Disclaimers**

    THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE." TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

    WE DO NOT GUARANTEE THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR THAT AI OUTPUTS WILL BE ACCURATE OR COMPLETE.

    **14) Limitation of Liability**

    TO THE MAXIMUM EXTENT PERMITTED BY LAW, KHUTBAH NOTES WILL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF DATA, PROFITS, OR REVENUE, ARISING FROM OR RELATED TO YOUR USE OF THE SERVICE.

    TO THE MAXIMUM EXTENT PERMITTED BY LAW, OUR TOTAL LIABILITY FOR ANY CLAIM RELATED TO THE SERVICE WILL NOT EXCEED THE AMOUNT YOU PAID TO US (IF ANY) FOR THE SERVICE IN THE 12 MONTHS BEFORE THE EVENT GIVING RISE TO THE CLAIM, OR $100, WHICHEVER IS GREATER.

    Some jurisdictions do not allow certain limitations, so some of the above may not apply to you.

    **15) Indemnification**

    You agree to defend, indemnify, and hold harmless Khutbah Notes from and against any claims, liabilities, damages, losses, and expenses (including reasonable attorneys' fees) arising out of or related to:
    - your User Content,
    - your use of the Service,
    - your violation of these Terms, or
    - your violation of any rights of another.

    **16) Changes to These Terms**

    We may update these Terms from time to time. We will update the "Effective Date" above and may provide notice in-app where required. Continued use of the Service after changes become effective means you accept the updated Terms.

    **17) Governing Law**

    These Terms are governed by the laws of [State of California], without regard to conflict of law principles, except where prohibited by applicable law.

    **18) Contact**

    Questions about these Terms? Contact:
    support@khutbah-notes.com
    """

    static let privacy = """
    **Privacy Policy - Khutbah Notes**

    - **Effective Date:** December 23, 2025
    - **App Name:** Khutbah Notes ("Khutbah Notes," "we," "us," or "our")
    - **Support Contact:** support@khutbah-notes.com

    This Privacy Policy explains how Khutbah Notes collects, uses, shares, and protects information when you use our iOS application and related services (the "Service").

    **1) What We Collect**

    We collect information you provide or generate while using the Service:

    **A. Audio & Content You Submit**
    - Audio recordings you create in-app or audio files you upload
    - Transcripts generated from audio
    - Summaries, key points, translations, titles, tags, and other derived outputs you generate in-app
    - Any notes or text you choose to enter

    **B. Account & Identifiers**
    - A unique user identifier (including an anonymous identifier) to associate your content with your device/account

    **C. Usage & Device Data (Analytics)**
    We use Firebase Analytics to understand how users interact with the Service. Firebase Analytics may collect:
    - App interactions and events (e.g., feature usage, session duration, screen views)
    - Device and app information (e.g., device model, iOS version, app version, language/region)
    - Approximate location inferred from IP address (as provided by analytics tooling)
    - Identifiers used for analytics/measurement (handled according to your device settings and Apple's policies)

    **D. Push Notification Data**
    If you enable push notifications, OneSignal may collect and process:
    - A push notification token and device identifiers needed to deliver notifications
    - Notification interaction data (e.g., delivered/opened events)
    - Basic device and app information for delivery and performance
    - IP address (commonly used for routing and security)

    **E. Purchases & Subscription Data**
    - Subscription status/entitlements (e.g., whether you have Pro access)
    - Purchase metadata we receive from our subscription infrastructure
    - We do not receive your full payment card details - payments are processed by Apple

    **2) How We Use Information**

    We use information to:
    - Provide core features (recording, transcription, summarization, translation, saving, exporting)
    - Store and organize your content in your library
    - Send notifications you opt into (e.g., "summary ready" alerts)
    - Maintain and improve performance, reliability, and user experience
    - Understand usage trends and improve the Service (analytics)
    - Provide customer support and respond to requests
    - Process subscriptions and confirm access to premium features
    - Help prevent fraud, abuse, and security incidents
    - Comply with legal obligations and enforce our terms

    **3) How AI Processing Works (Transcription/Summarization/Translation)**

    To provide transcription, summarization, and translation, we may send audio and/or text to third-party AI processors. Currently, this includes:
    - OpenAI (for transcription, summarization, and/or translation)

    **What may be shared with the AI processor:**
    - Audio files (or portions necessary to transcribe)
    - Transcript text, summary text, or translation text (as needed for the feature you request)

    We send only what is necessary to provide the feature and operate the Service.

    **4) How We Share Information**

    We do not sell your personal information.

    We share information only in these situations:

    **A. Service Providers (Processors)**
    We use trusted vendors to host data and run app functionality, including:
    - Google/Firebase (e.g., Firebase services such as hosting/database/storage and Firebase Analytics for usage analytics)
    - OneSignal (push notification delivery and related analytics such as opens/deliveries)
    - OpenAI (AI processing for transcription/summarization/translation)

    These providers are authorized to process data only to perform services for us.

    **B. Legal / Safety**
    We may disclose information if required by law or if we believe it is necessary to comply with legal process or protect the rights, safety, and security of users or the public.

    **C. Business Changes**
    If we are involved in a merger, acquisition, financing, reorganization, or sale of assets, information may be transferred as part of that transaction.

    **5) Data Retention**
    - Audio files: We store audio for up to 30 days, after which it may be deleted from our systems unless you delete it sooner.
    - Transcripts, summaries, translations, and metadata: We retain these as long as you keep them in your library (or until you delete them), unless a longer retention period is required by law or for legitimate business needs (e.g., limited backups).
    - Analytics & notification logs: Retention is governed by our provider configurations and may be retained for a period of time for reporting, security, and troubleshooting.

    **6) Your Choices & Controls**

    **A. Delete Content**
    You can delete recordings, transcripts, summaries, and other items from within the app. Deletion may take a short time to propagate, and residual copies may persist briefly in backups.

    **B. Export & Share**
    You can export and share content using iOS share features. Anything you share with third parties is governed by their policies.

    **C. Push Notifications**
    You can enable/disable notifications at any time in iOS Settings - Notifications - Khutbah Notes. Disabling notifications stops OneSignal from delivering push notifications to your device.

    **D. Analytics**
    Depending on your device settings and Apple policies, you may have controls that limit certain tracking/measurement behaviors. (For example, you can review privacy settings on your device.)

    **7) Security**

    We use reasonable administrative, technical, and physical safeguards designed to protect information. However, no method of transmission or storage is 100% secure, and we cannot guarantee absolute security.

    **8) Children's Privacy**

    Khutbah Notes is not intended for children under 13 (or the minimum age required in your jurisdiction). We do not knowingly collect personal information from children. If you believe a child has provided personal information, contact us at support@khutbah-notes.com.

    **9) International Data Transfers**

    If you access the Service from outside the United States, your information may be processed and stored in the United States or other countries where our service providers operate. By using the Service, you understand that your information may be transferred to countries with different data protection laws.

    **10) Your Privacy Rights (General)**

    Depending on where you live, you may have rights to request access, deletion, or correction of your information, or to object to certain processing. To make a request, contact support@khutbah-notes.com. We may ask you to verify your request.

    **11) Third-Party Links & Services**

    The Service may integrate with third-party services (e.g., Apple purchase flow) or allow sharing via third-party apps. Their privacy practices are governed by their own policies.

    **12) Changes to This Policy**

    We may update this Privacy Policy from time to time. We will update the "Effective Date" above and may provide additional notice in-app where required. Continued use of the Service after changes become effective means you accept the updated policy.

    **13) Contact Us**

    If you have questions about this Privacy Policy or our privacy practices, contact:
    support@khutbah-notes.com
    """
}

struct StaticContentView: View {
    let title: String
    let bodyText: String
    private struct ContentLine: Identifiable {
        enum Kind {
            case spacer
            case paragraph
            case bullet
        }

        let id = UUID()
        let kind: Kind
        let text: AttributedString?
    }

    private var contentLines: [ContentLine] {
        Self.parseContentLines(from: bodyText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(contentLines) { line in
                    lineView(for: line)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle(title)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private func lineView(for line: ContentLine) -> some View {
        switch line.kind {
        case .spacer:
            Color.clear
                .frame(height: 10)
        case .paragraph:
            if let text = line.text {
                Text(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Theme.mutedText)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .bullet:
            if let text = line.text {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Theme.mutedText)
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Theme.mutedText)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func parseContentLines(from text: String) -> [ContentLine] {
        let normalized = normalizedMarkdown(text)
        let lines = normalized.components(separatedBy: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        return lines.map { rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return ContentLine(kind: .spacer, text: nil)
            }

            if trimmed.hasPrefix("- ") {
                let content = String(trimmed.dropFirst(2))
                let attributed = (try? AttributedString(markdown: content, options: options)) ?? AttributedString(content)
                return ContentLine(kind: .bullet, text: attributed)
            }

            let attributed = (try? AttributedString(markdown: trimmed, options: options)) ?? AttributedString(trimmed)
            return ContentLine(kind: .paragraph, text: attributed)
        }
    }

    private static func normalizedMarkdown(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedNewlines.components(separatedBy: "\n")
        let indentation = lines.compactMap { line -> Int? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return line.prefix { $0 == " " || $0 == "\t" }.count
        }.min() ?? 0

        let cleanedLines = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "" }
            guard indentation > 0 else { return line }
            var result = line
            var removeCount = indentation
            while removeCount > 0, let first = result.first, first == " " || first == "\t" {
                result.removeFirst()
                removeCount -= 1
            }
            return result
        }

        return cleanedLines.joined(separator: "\n")
    }
}
