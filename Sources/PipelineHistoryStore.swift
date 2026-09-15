import Foundation
import CoreData

final class PipelineHistoryStore {
    let container: NSPersistentContainer
    private let isStoreLoaded: Bool

    /// Production initializer. Builds an on-disk SQLite store in
    /// Application Support (or falls back to an in-memory store when
    /// the on-disk store cannot be loaded).
    convenience init() {
        let model = Self.makeModel()
        let container = NSPersistentContainer(name: "PipelineHistory", managedObjectModel: model)

        var storeURL: URL?
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appName = AppName.displayName
            let baseURL = appSupport.appendingPathComponent(appName, isDirectory: true)
            try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            storeURL = baseURL.appendingPathComponent("PipelineHistory.sqlite")
        }

        if let storeURL {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
        } else {
            container.persistentStoreDescriptions = [NSPersistentStoreDescription()]
        }

        var loaded = Self.loadPersistentStoresSynchronously(container: container) == nil
        if !loaded, let storeURL {
            print("[PipelineHistoryStore] Failed to load persistent store at \(storeURL.path). Attempting recovery.")
            Self.destroySQLiteStoreFiles(at: storeURL)

            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                try? coordinator.remove(store)
            }

            let recoveryDescription = NSPersistentStoreDescription(url: storeURL)
            recoveryDescription.shouldMigrateStoreAutomatically = true
            recoveryDescription.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [recoveryDescription]

            loaded = Self.loadPersistentStoresSynchronously(container: container) == nil
        }
        if !loaded {
            print("[PipelineHistoryStore] Failed to recover persistent store. Falling back to in-memory history.")
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                try? coordinator.remove(store)
            }
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            loaded = Self.loadPersistentStoresSynchronously(container: container) == nil
        }

        self.init(container: container, isStoreLoaded: loaded)
    }

    /// Testable initializer backed by an arbitrary
    /// `NSPersistentContainer`. Tests use this with a temporary
    /// SQLite store on disk or with an in-memory store description
    /// so they can exercise real persistence semantics without
    /// touching the production Application Support directory.
    init(container: NSPersistentContainer, isStoreLoaded: Bool) {
        self.container = container
        self.isStoreLoaded = isStoreLoaded
    }

    /// Convenience initializer that builds a fresh in-memory
    /// `PipelineHistoryStore`. Tests use this so they never read
    /// real pipeline history or user audio.
    static func inMemory() -> PipelineHistoryStore {
        let model = PipelineHistoryStore.makeModel()
        let container = NSPersistentContainer(name: "PipelineHistoryTest", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let loaded = PipelineHistoryStore.loadPersistentStoresSynchronously(container: container) == nil
        return PipelineHistoryStore(container: container, isStoreLoaded: loaded)
    }

    /// Convenience initializer that builds a fresh on-disk
    /// `PipelineHistoryStore` rooted at the supplied URL. Tests use
    /// this to assert that persisted state survives an
    /// init/load/relaunch cycle without touching real audio.
    static func temporaryOnDisk(at storeURL: URL) -> PipelineHistoryStore {
        let model = PipelineHistoryStore.makeModel()
        let container = NSPersistentContainer(name: "PipelineHistoryTest", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        let loaded = PipelineHistoryStore.loadPersistentStoresSynchronously(container: container) == nil
        return PipelineHistoryStore(container: container, isStoreLoaded: loaded)
    }

    func loadAllHistory() -> [PipelineHistoryItem] {
        guard isStoreLoaded else { return [] }
        var result: [PipelineHistoryItem] = []
        container.viewContext.performAndWait {
            let request = pipelineHistoryRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            guard let entities = try? container.viewContext.fetch(request) else { return }
            result = entities.map(Self.makeHistoryItem(from:))
        }
        return result
    }

    @discardableResult
    func append(_ item: PipelineHistoryItem, maxCount: Int) throws -> [String] {
        guard isStoreLoaded else { return [] }
        try insert(item)
        return try trim(to: maxCount)
    }

    func update(_ item: PipelineHistoryItem) throws {
        guard isStoreLoaded else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                Self.writeEntity(entity, from: item)
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    /// Delete a single history row by its Processing Attempt id.
    /// Returns the row's `audioFileName` only when no remaining row
    /// in the store still references that WAV — the caller uses the
    /// returned name to physically delete the on-disk audio file.
    /// When at least one other retained row references the same
    /// audio, returns nil so the WAV is kept for the remaining
    /// Processing Attempt(s).
    func delete(id: UUID) throws -> String? {
        guard isStoreLoaded else { return nil }

        var returnedFileName: String?
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                let fileName = entity.audioFileName
                container.viewContext.delete(entity)
                try saveContext()
                if let fileName, !fileName.isEmpty,
                   Self.hasRemainingReferences(toAudioFileName: fileName, excludingID: id, in: container.viewContext) == false {
                    returnedFileName = fileName
                }
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return returnedFileName
    }

    /// Delete every row. Returns the unique set of
    /// `audioFileName`s referenced by the removed rows so the caller
    /// can physically delete each WAV exactly once.
    func clearAll() throws -> [String] {
        guard isStoreLoaded else { return [] }

        var collected: [String] = []
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
                guard let entities = try? container.viewContext.fetch(request) else { return }
                for entity in entities {
                    if let name = entity.audioFileName, !name.isEmpty {
                        collected.append(name)
                    }
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        // Deduplicate so the caller deletes each WAV exactly once.
        return Self.deduplicatePreservingOrder(collected)
    }

    /// Trim to the most recent `maxCount` rows by timestamp. Returns
    /// the unique set of `audioFileName`s whose last reference was
    /// dropped by this trim so the caller can physically delete each
    /// WAV exactly once. An audio filename whose reference is still
    /// held by a retained row is not returned.
    func trim(to maxCount: Int) throws -> [String] {
        guard isStoreLoaded else { return [] }
        guard maxCount > 0 else {
            return try clearAll()
        }

        var collected: [String] = []
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
                guard let entities = try? container.viewContext.fetch(request), entities.count > maxCount else { return }
                let dropped = entities[maxCount...]
                // Pre-compute the set of audio filenames that are
                // referenced by at least one RETAINED row. These
                // filenames must never be returned for deletion even
                // if every dropped row also references them.
                var stillReferenced: Set<String> = []
                for entity in entities[..<maxCount] {
                    if let name = entity.audioFileName, !name.isEmpty {
                        stillReferenced.insert(name)
                    }
                }
                // Walk the dropped slice; for each row, surface the
                // audio filename only when no retained row still
                // references it. Deduplicate at the end so a WAV
                // shared by multiple dropped rows returns once.
                for entity in dropped {
                    if let name = entity.audioFileName, !name.isEmpty,
                       !stillReferenced.contains(name) {
                        collected.append(name)
                    }
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return Self.deduplicatePreservingOrder(collected)
    }

    private func insert(_ item: PipelineHistoryItem) throws {
        guard isStoreLoaded else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let context = container.viewContext
                let entity = PipelineHistoryEntry(context: context)
                Self.writeEntity(entity, from: item)
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    /// Count retained rows that reference the supplied audio file
    /// name, optionally excluding one row id. Used by `delete(id:)`
    /// to decide whether the WAV is safe to physically delete.
    private static func hasRemainingReferences(
        toAudioFileName name: String,
        excludingID: UUID?,
        in context: NSManagedObjectContext
    ) -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PipelineHistoryEntry")
        var predicates: [NSPredicate] = [
            NSPredicate(format: "audioFileName == %@", name)
        ]
        if let excludingID {
            predicates.append(NSPredicate(format: "id != %@", excludingID as CVarArg))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.resultType = .countResultType
        let count: Int
        do {
            count = try context.count(for: request)
        } catch {
            // If the count query fails, err on the side of safety:
            // report that references remain so the caller does NOT
            // delete the audio file. The row was already removed from
            // the store; the audio becomes orphaned but safe.
            return true
        }
        return count > 0
    }

    /// Deduplicate an array of strings while preserving the order
    /// in which each value first appears.
    private static func deduplicatePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    /// Write one `PipelineHistoryItem`'s fields onto the supplied
    /// managed object. Used by both `insert` and `update` so the
    /// field set stays in lockstep across write paths.
    private static func writeEntity(_ entity: PipelineHistoryEntry, from item: PipelineHistoryItem) {
        entity.id = item.id
        entity.intent = item.intent.rawValue
        entity.selectedText = item.selectedText
        entity.capturedSelection = item.capturedSelection
        entity.timestamp = item.timestamp
        entity.rawTranscript = item.rawTranscript
        entity.postProcessedTranscript = item.postProcessedTranscript
        entity.postProcessingPrompt = item.postProcessingPrompt
        entity.systemPrompt = item.systemPrompt
        entity.contextSummary = item.contextSummary
        entity.contextSystemPrompt = item.contextSystemPrompt
        entity.contextPrompt = item.contextPrompt
        entity.contextScreenshotDataURL = item.contextScreenshotDataURL
        entity.contextScreenshotStatus = item.contextScreenshotStatus
        entity.postProcessingStatus = item.postProcessingStatus
        entity.debugStatus = item.debugStatus
        entity.customVocabulary = item.customVocabulary
        entity.audioFileName = item.audioFileName
        entity.contextAppName = item.contextAppName
        entity.contextBundleIdentifier = item.contextBundleIdentifier
        entity.contextWindowTitle = item.contextWindowTitle
        entity.recordingID = item.recordingID
        entity.captureTime = item.captureTime
        entity.originalProfileID = item.originalProfileID
        entity.originalProfileName = item.originalProfileName
        entity.originalInputLanguageCode = item.originalInputLanguageCode
        entity.processingProfileID = item.processingProfileID
        entity.processingProfileName = item.processingProfileName
        entity.processingInputLanguageCode = item.processingInputLanguageCode
    }

    private func saveContext() throws {
        guard container.viewContext.hasChanges else { return }
        do {
            try container.viewContext.save()
        } catch {
            container.viewContext.rollback()
            throw error
        }
    }

    private func pipelineHistoryRequest() -> NSFetchRequest<PipelineHistoryEntry> {
        NSFetchRequest<PipelineHistoryEntry>(entityName: "PipelineHistoryEntry")
    }

    // Safe: loadPersistentStores calls back on a private queue, not the calling thread.
    private static func loadPersistentStoresSynchronously(container: NSPersistentContainer) -> Error? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var capturedError: Error?
        var remainingCompletions = max(1, container.persistentStoreDescriptions.count)

        container.loadPersistentStores { _, error in
            lock.lock()
            if capturedError == nil, let error {
                capturedError = error
            }
            remainingCompletions -= 1
            let shouldSignal = remainingCompletions <= 0
            lock.unlock()

            if shouldSignal {
                semaphore.signal()
            }
        }

        semaphore.wait()
        return capturedError
    }

    private static func destroySQLiteStoreFiles(at storeURL: URL) {
        let basePath = storeURL.path
        let fileManager = FileManager.default
        for path in [basePath, basePath + "-wal", basePath + "-shm"] {
            try? fileManager.removeItem(atPath: path)
        }
    }

    /// Build a `PipelineHistoryItem` from a managed object, applying
    /// the legacy migration rules: rows persisted before Physical
    /// Recording identity existed fall back to the entry's own `id`
    /// / `timestamp` so every retained row is reachable through a
    /// stable identity without destructive rewriting.
    private static func makeHistoryItem(from entity: PipelineHistoryEntry) -> PipelineHistoryItem {
        let timestamp = entity.timestamp ?? Date()
        return PipelineHistoryItem(
            intent: PipelineHistoryItemIntent(rawValue: entity.intent ?? "") ?? .dictation,
            selectedText: entity.selectedText,
            capturedSelection: entity.capturedSelection,
            id: entity.id,
            timestamp: timestamp,
            rawTranscript: entity.rawTranscript ?? "",
            postProcessedTranscript: entity.postProcessedTranscript ?? "",
            postProcessingPrompt: entity.postProcessingPrompt,
            systemPrompt: entity.systemPrompt,
            contextSummary: entity.contextSummary ?? "",
            contextSystemPrompt: entity.contextSystemPrompt,
            contextPrompt: entity.contextPrompt,
            contextScreenshotDataURL: entity.contextScreenshotDataURL,
            contextScreenshotStatus: entity.contextScreenshotStatus ?? "available (image)",
            postProcessingStatus: entity.postProcessingStatus ?? "",
            debugStatus: entity.debugStatus ?? "",
            customVocabulary: entity.customVocabulary ?? "",
            audioFileName: entity.audioFileName,
            contextAppName: entity.contextAppName,
            contextBundleIdentifier: entity.contextBundleIdentifier,
            contextWindowTitle: entity.contextWindowTitle,
            recordingID: entity.recordingID,
            captureTime: entity.captureTime,
            originalProfileID: entity.originalProfileID,
            originalProfileName: entity.originalProfileName,
            originalInputLanguageCode: entity.originalInputLanguageCode,
            processingProfileID: entity.processingProfileID,
            processingProfileName: entity.processingProfileName,
            processingInputLanguageCode: entity.processingInputLanguageCode
        )
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PipelineHistoryEntry"
        entity.managedObjectClassName = NSStringFromClass(PipelineHistoryEntry.self)

        entity.properties = [
            makeAttribute(name: "intent", type: .stringAttributeType, isOptional: true, defaultValue: "dictation"),
            makeAttribute(name: "selectedText", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "capturedSelection", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "id", type: .UUIDAttributeType, isOptional: false),
            makeAttribute(name: "timestamp", type: .dateAttributeType, isOptional: false),
            makeAttribute(name: "rawTranscript", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "postProcessedTranscript", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "postProcessingPrompt", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "systemPrompt", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextSummary", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "contextSystemPrompt", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextPrompt", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextScreenshotDataURL", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextScreenshotStatus", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "postProcessingStatus", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "debugStatus", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "customVocabulary", type: .stringAttributeType, isOptional: false),
            makeAttribute(name: "audioFileName", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextAppName", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextBundleIdentifier", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "contextWindowTitle", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "recordingID", type: .UUIDAttributeType, isOptional: true),
            makeAttribute(name: "captureTime", type: .dateAttributeType, isOptional: true),
            makeAttribute(name: "originalProfileID", type: .UUIDAttributeType, isOptional: true),
            makeAttribute(name: "originalProfileName", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "originalInputLanguageCode", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "processingProfileID", type: .UUIDAttributeType, isOptional: true),
            makeAttribute(name: "processingProfileName", type: .stringAttributeType, isOptional: true),
            makeAttribute(name: "processingInputLanguageCode", type: .stringAttributeType, isOptional: true)
        ]

        model.entities = [entity]
        return model
    }

    private static func makeAttribute(
        name: String,
        type: NSAttributeType,
        isOptional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }
}

/// Recoverable error returned by `PipelineHistoryStore.eligibility(...)`
/// when a retried Processing Attempt cannot resume because the on-disk
/// WAV is missing, the row no longer exists, or the row never recorded
/// audio. The caller surfaces these to the user as friendly retry
/// failures and must never mutate history in response.
enum HistoryEligibilityError: Error, Equatable {
    case itemNotFound
    case noAudioReference
    case missingAudioFile(fileName: String)
}

extension PipelineHistoryStore {
    /// Check whether the supplied item id can be safely retried.
    /// Returns nil when the row exists, references a saved WAV, and
    /// the WAV is on disk. Returns a typed `HistoryEligibilityError`
    /// otherwise. The retained history is never mutated by this
    /// call; the caller surfaces the error to the user as a
    /// recoverable retry failure.
    func eligibility(forRetryingID itemID: UUID, audioStorageDirectory: URL) -> HistoryEligibilityError? {
        let items = loadAllHistory()
        guard let item = items.first(where: { $0.id == itemID }) else {
            return .itemNotFound
        }
        guard let audioFileName = item.audioFileName, !audioFileName.isEmpty else {
            return .noAudioReference
        }
        let audioURL = audioStorageDirectory.appendingPathComponent(audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return .missingAudioFile(fileName: audioFileName)
        }
        return nil
    }
}

@objc(PipelineHistoryEntry)
final class PipelineHistoryEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var intent: String?
    @NSManaged var selectedText: String?
    @NSManaged var capturedSelection: String?
    @NSManaged var timestamp: Date?
    @NSManaged var rawTranscript: String?
    @NSManaged var postProcessedTranscript: String?
    @NSManaged var postProcessingPrompt: String?
    @NSManaged var systemPrompt: String?
    @NSManaged var contextSummary: String?
    @NSManaged var contextSystemPrompt: String?
    @NSManaged var contextPrompt: String?
    @NSManaged var contextScreenshotDataURL: String?
    @NSManaged var contextScreenshotStatus: String?
    @NSManaged var postProcessingStatus: String?
    @NSManaged var debugStatus: String?
    @NSManaged var customVocabulary: String?
    @NSManaged var audioFileName: String?
    @NSManaged var contextAppName: String?
    @NSManaged var contextBundleIdentifier: String?
    @NSManaged var contextWindowTitle: String?
    @NSManaged var recordingID: UUID?
    @NSManaged var captureTime: Date?
    @NSManaged var originalProfileID: UUID?
    @NSManaged var originalProfileName: String?
    @NSManaged var originalInputLanguageCode: String?
    @NSManaged var processingProfileID: UUID?
    @NSManaged var processingProfileName: String?
    @NSManaged var processingInputLanguageCode: String?
}
