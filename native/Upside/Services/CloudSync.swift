import CloudKit
import Foundation
import Observation
import UIKit
import UserNotifications

/// Keeps the budget in iCloud: a backup for you, and one shared budget for
/// the two of you. The whole budget is one record ("Budget") with the data
/// as a file ("payload"). Each phone merges before it saves, so neither
/// overwrites the other (see `BudgetMerge`).
///
/// The owner's budget lives in their private iCloud in a zone named
/// "Budget"; sharing shares that zone. Someone who joins reads and writes
/// the same zone through their shared iCloud database.
@MainActor @Observable
final class CloudSync {
    static let shared = CloudSync()
    static let containerID = "iCloud.com.tejadar1.upside"
    private static let zoneName = "Budget"
    private static let recordName = "budget"

    enum Status: Equatable {
        case off(String)
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status = .off("Not started")
    private(set) var share: CKShare?
    private weak var store: BudgetStore?
    /// Last record from iCloud, kept to save over it (its change tag).
    private var serverRecord: CKRecord?
    private var uploadTask: Task<Void, Never>?
    /// True while a merged copy is being put in place, so it isn't re-uploaded.
    private var applying = false
    private var isPulling = false

    /// Simulators and screenshots have no iCloud account; demo data never syncs.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return !ProcessInfo.processInfo.arguments.contains("-demo")
        #endif
    }

    private var container: CKContainer { CKContainer(identifier: Self.containerID) }

    /// The owner's user record name when this phone joined someone's budget.
    var joinedOwner: String? { UserDefaults.standard.string(forKey: "cloudJoinedOwner") }
    var isParticipant: Bool { joinedOwner != nil }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: joinedOwner ?? CKCurrentUserDefaultName)
    }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: Self.recordName, zoneID: zoneID) }
    private var database: CKDatabase { isParticipant ? container.sharedCloudDatabase : container.privateCloudDatabase }

    // MARK: Starting and syncing

    /// An invite tapped before the budget was loaded.
    private var pendingInvite: CKShare.Metadata?

    func start(_ store: BudgetStore) {
        guard Self.isAvailable, !store.isDemo else { return }
        self.store = store
        store.onSave = { [weak self] in self?.scheduleUpload() }
        Task {
            if let invite = pendingInvite {
                pendingInvite = nil
                await accept(invite)
            } else {
                await pull()
            }
        }
    }

    /// Fetch iCloud's copy, merge it in, and send back anything newer here.
    func pull() async {
        // Opening the app can ask twice at once (launch and becoming active).
        guard let store, !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        status = .syncing
        do {
            guard try await container.accountStatus() == .available else {
                status = .off("Sign in to iCloud in Settings to back up your budget.")
                return
            }
            try await ensureZone()
            let record: CKRecord?
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = nil
            }
            if let record, let remote = Self.decode(record) {
                serverRecord = record
                let merged = BudgetMerge.merge(local: store.data, remote: remote, base: Self.loadBase())
                apply(merged)
                Self.saveBase(remote)
                if !Self.equal(merged, remote) { try await upload() } else { status = .synced(Date()) }
            } else {
                try await upload()
            }
            await refreshShare()
        } catch {
            let code = (error as? CKError)?.code
            if isParticipant && (code == .zoneNotFound || code == .userDeletedZone) {
                // The owner stopped sharing: keep this phone's copy as its own.
                await notify(id: "share-ended", title: "Sharing ended",
                             body: "The shared budget was stopped. This iPhone keeps a copy.")
                await becomeOwnBudget()
                return
            }
            if code == .zoneNotFound {
                // iCloud data was deleted; recreate the zone next time.
                UserDefaults.standard.set(false, forKey: "cloudZoneReady")
            }
            status = .failed(Self.describe(error))
        }
    }

    private func scheduleUpload() {
        guard !applying, store != nil else { return }
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            do { try await self.upload() } catch { self.status = .failed(Self.describe(error)) }
        }
    }

    /// Saves this phone's budget. If the other phone saved first, merges
    /// with theirs and tries again.
    private func upload(attempt: Int = 0) async throws {
        guard let store else { return }
        status = .syncing
        let record = serverRecord ?? CKRecord(recordType: "Budget", recordID: recordID)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("budget-\(UUID().uuidString).json")
        try JSONEncoder.upside.encode(store.data).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        record["payload"] = CKAsset(fileURL: file)
        record["version"] = Int64(Date().timeIntervalSince1970)
        do {
            let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [],
                                                              savePolicy: .ifServerRecordUnchanged)
            // Per-record problems come back in the results, not as a thrown error.
            switch saved[record.recordID] {
            case .success(let result)?: serverRecord = result
            case .failure(let error)?: throw error
            case nil: break
            }
            Self.saveBase(store.data)
            status = .synced(Date())
        } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
            guard let theirs = error.serverRecord, let remote = Self.decode(theirs) else { throw error }
            serverRecord = theirs
            apply(BudgetMerge.merge(local: store.data, remote: remote, base: Self.loadBase()))
            Self.saveBase(remote)
            try await upload(attempt: attempt + 1)
        }
    }

    private func apply(_ data: BudgetData) {
        guard let store, !Self.equal(store.data, data) else { return }
        applying = true
        store.data = data
        applying = false
    }

    private func ensureZone() async throws {
        guard !isParticipant, !UserDefaults.standard.bool(forKey: "cloudZoneReady") else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        UserDefaults.standard.set(true, forKey: "cloudZoneReady")
    }

    // MARK: Sharing

    private var shareID: CKRecord.ID { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID) }

    func refreshShare() async {
        share = try? await database.record(for: shareID) as? CKShare
        await noticeNewPeople()
    }

    // MARK: Who has access

    struct Person: Identifiable {
        var id: String
        var name: String
        /// Email or phone, partly hidden: "j•••@gmail.com".
        var contact: String
        var joined: Bool
        var isOwner: Bool
    }

    /// Everyone on the share besides you, joined or still invited.
    var people: [Person] {
        guard let share else { return [] }
        let me = share.currentUserParticipant?.userIdentity.userRecordID?.recordName
        return share.participants.compactMap { p in
            let id = p.userIdentity.userRecordID?.recordName
                ?? p.userIdentity.lookupInfo?.emailAddress ?? p.userIdentity.lookupInfo?.phoneNumber ?? UUID().uuidString
            guard id != me else { return nil }
            let name = p.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            let contact = Self.mask(p.userIdentity.lookupInfo?.emailAddress ?? p.userIdentity.lookupInfo?.phoneNumber ?? "")
            return Person(id: id, name: (name?.isEmpty == false ? name : nil) ?? (contact.isEmpty ? "Someone" : contact),
                          contact: contact, joined: p.acceptanceStatus == .accepted, isOwner: p.role == .owner)
        }
    }

    /// A couples budget has one partner; more than that is worth a look.
    var hasExtraPeople: Bool { !isParticipant && people.filter { !$0.isOwner }.count > 1 }

    /// Tells you when someone joins, and warns if it's more than one person.
    private func noticeNewPeople() async {
        guard !isParticipant else { return }
        let joined = people.filter { $0.joined && !$0.isOwner }
        let known = Set(UserDefaults.standard.stringArray(forKey: "cloudKnownPeople") ?? [])
        let new = joined.filter { !known.contains($0.id) }
        guard !new.isEmpty else { return }
        UserDefaults.standard.set(joined.map(\.id), forKey: "cloudKnownPeople")
        for person in new {
            await notify(id: "joined-\(person.id)", title: "\(person.name) joined your budget",
                         body: "They can see and edit it on their iPhone. Manage access in Settings → iCloud.")
        }
        if joined.count > 1 {
            await notify(id: "extra-\(joined.count)", title: "More than one person has access",
                         body: "Review who can see your budget in Settings → iCloud → Manage.")
        }
    }

    private func notify(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private static func mask(_ contact: String) -> String {
        guard !contact.isEmpty else { return "" }
        if let at = contact.firstIndex(of: "@") {
            return String(contact.prefix(1)) + "•••" + contact[at...]
        }
        let digits = contact.filter(\.isNumber)
        return digits.count >= 4 ? "•••" + digits.suffix(4) : contact
    }

    /// Opens Apple's sharing screen: invite by Messages or Mail, see who
    /// has joined, or stop sharing.
    func presentSharing() async {
        guard !isParticipant else { return }
        do {
            try await upload()
            var current = share
            if current == nil {
                let new = CKShare(recordZoneID: zoneID)
                new[CKShare.SystemFieldKey.title] = "Upside budget" as CKRecordValue
                new.publicPermission = .none
                let (saved, _) = try await database.modifyRecords(saving: [new], deleting: [])
                switch saved[new.recordID] {
                case .success(let record)?: current = record as? CKShare
                case .failure(let error)?: throw error
                case nil: break
                }
            }
            guard let current else { return }
            share = current
            let controller = UICloudSharingController(share: current, container: container)
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            Self.topViewController()?.present(controller, animated: true)
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// Someone tapped an invite: join their budget. This phone's own budget
    /// is replaced by the shared one.
    func accept(_ metadata: CKShare.Metadata) async {
        guard store != nil else { pendingInvite = metadata; return }
        do {
            _ = try await container.accept(metadata)
            UserDefaults.standard.set(metadata.share.recordID.zoneID.ownerName, forKey: "cloudJoinedOwner")
            Self.clearBase()
            serverRecord = nil
            if let record = try? await database.record(for: recordID), let remote = Self.decode(record) {
                serverRecord = record
                apply(remote)
                Self.saveBase(remote)
            }
            status = .synced(Date())
            await refreshShare()
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// Leave a budget someone shared with you; this phone keeps a copy.
    func leave() async {
        guard isParticipant else { return }
        if let share { _ = try? await database.modifyRecords(saving: [], deleting: [share.recordID]) }
        await becomeOwnBudget()
    }

    /// After leaving (or being removed), this phone's copy becomes its own
    /// budget again. Its old private backup from before joining is replaced,
    /// so the merge doesn't bring back pre-sharing data.
    private func becomeOwnBudget() async {
        UserDefaults.standard.removeObject(forKey: "cloudJoinedOwner")
        UserDefaults.standard.removeObject(forKey: "cloudKnownPeople")
        share = nil
        serverRecord = nil
        Self.clearBase()
        _ = try? await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [recordID])
        do { try await ensureZone(); try await upload() } catch { status = .failed(Self.describe(error)) }
    }

    // MARK: Helpers

    private static func decode(_ record: CKRecord) -> BudgetData? {
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.upside.decode(BudgetData.self, from: raw)
    }

    private static func equal(_ a: BudgetData, _ b: BudgetData) -> Bool {
        (try? JSONEncoder.upside.encode(a)) == (try? JSONEncoder.upside.encode(b))
    }

    /// The copy both phones last agreed on, for merging.
    private static var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cloud-base.json")
    }
    private static func loadBase() -> BudgetData? {
        (try? Data(contentsOf: baseURL)).flatMap { try? JSONDecoder.upside.decode(BudgetData.self, from: $0) }
    }
    private static func saveBase(_ data: BudgetData) {
        try? JSONEncoder.upside.encode(data).write(to: baseURL, options: [.atomic, .completeFileProtection])
    }
    private static func clearBase() { try? FileManager.default.removeItem(at: baseURL) }

    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated: return "Sign in to iCloud in Settings to back up your budget."
        case .networkUnavailable, .networkFailure: return "No connection. Upside tries again next time you open it."
        case .quotaExceeded: return "Your iCloud storage is full."
        case .badContainer, .missingEntitlement, .permissionFailure:
            return "iCloud isn't set up for Upside yet (\(ck.code.rawValue))."
        case .serverRejectedRequest, .invalidArguments:
            return "iCloud rejected the save. The Budget record type may not be deployed to Production."
        default: return ck.localizedDescription
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Receives iCloud invites ("Ron invited you to Upside budget").
final class UpsideAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = UpsideSceneDelegate.self
        return config
    }
}

final class UpsideSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata {
            Task { @MainActor in await CloudSync.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await CloudSync.shared.accept(metadata) }
    }
}
