//
//  OneSignalIntegration.swift
//  Khutbah Notes AI
//
//  Centralized OneSignal setup and identifier persistence.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import OneSignalFramework

@MainActor
enum OneSignalIntegration {
    private static let appId = "290aa0ce-8c6c-4e7d-84c1-914fbdac66f1" // TODO: replace with your OneSignal App ID
    private static let maxPersistAttempts = 6
    private static let retryDelay: TimeInterval = 1.5
    private static var pendingExternalId: String?
    private static var lastLinkedExternalId: String?
    private static var isConfigured = false
    private static var hasRegisteredClickListener = false
    private static var clickListener: SummaryReadyClickListener?
    
    static func configureIfNeeded() {
        guard !appId.isEmpty, !isConfigured else { return }
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        #else
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #endif
        OneSignal.initialize(appId, withLaunchOptions: nil)
        isConfigured = true
        
        if let pendingExternalId {
            linkCurrentUser(with: pendingExternalId)
        }
    }
    
    static func linkCurrentUser(with userId: String? = Auth.auth().currentUser?.uid) {
        guard !appId.isEmpty else {
            print("OneSignal App ID not set; skipping OneSignal login.")
            return
        }
        
        guard let userId, !userId.isEmpty else {
            print("No user ID available for OneSignal linking.")
            return
        }
        
        guard isConfigured else {
            pendingExternalId = userId
            return
        }
        
        pendingExternalId = userId
        
        if lastLinkedExternalId != userId {
            OneSignal.login(userId)
            lastLinkedExternalId = userId
        }
        
        persistIdentifiersWhenAvailable(for: userId, attempt: 0)
    }

    static func registerNotificationClickHandler() {
        guard !hasRegisteredClickListener else { return }
        hasRegisteredClickListener = true
        let listener = SummaryReadyClickListener()
        clickListener = listener
        OneSignal.Notifications.addClickListener(listener)
    }
    
    private static func persistIdentifiersWhenAvailable(for userId: String, attempt: Int) {
        let onesignalId = OneSignal.User.onesignalId
        let subscriptionId = OneSignal.User.pushSubscription.id
        
        let hasOneSignalId = (onesignalId?.isEmpty == false)
        let hasSubscriptionId = (subscriptionId?.isEmpty == false)
        
        if hasOneSignalId || hasSubscriptionId {
            persistOneSignalIdentifiers(userId: userId, subscriptionId: subscriptionId, onesignalId: onesignalId)
            return
        }
        
        guard attempt < maxPersistAttempts else {
            print("OneSignal identifiers unavailable after retries for user \(userId).")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            persistIdentifiersWhenAvailable(for: userId, attempt: attempt + 1)
        }
    }

    fileprivate static func lectureId(from additionalData: [AnyHashable: Any]?) -> String? {
        guard let additionalData else { return nil }
        if let lectureId = additionalData["lectureId"] as? String,
           !lectureId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lectureId
        }
        if let lectureId = additionalData["lectureId"] as? NSNumber {
            let stringValue = lectureId.stringValue
            return stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : stringValue
        }
        return nil
    }
    
    private static func persistOneSignalIdentifiers(userId: String, subscriptionId: String?, onesignalId: String?) {
        var oneSignalData: [String: Any] = [:]
        
        if let onesignalId, !onesignalId.isEmpty {
            oneSignalData["oneSignalId"] = onesignalId
        }
        
        if let subscriptionId, !subscriptionId.isEmpty {
            oneSignalData["pushSubscriptionId"] = subscriptionId
        }
        
        guard !oneSignalData.isEmpty else { return }
        
        Firestore.firestore().collection("users").document(userId).setData(["oneSignal": oneSignalData], merge: true) { error in
            if let error {
                print("Failed to save OneSignal identifiers to Firestore: \(error.localizedDescription)")
            } else {
                print("Saved OneSignal identifiers for user \(userId)")
            }
        }
    }
}

private final class SummaryReadyClickListener: NSObject, OSNotificationClickListener {
    func onClick(event: OSNotificationClickEvent) {
        let additionalData = event.notification.additionalData
        if let type = additionalData?["type"] as? String,
           type != "summary_ready" {
            return
        }
        guard let lectureId = OneSignalIntegration.lectureId(from: additionalData) else { return }
        DispatchQueue.main.async {
            LectureDeepLinkStore.setPendingLectureId(lectureId)
        }
    }
}
