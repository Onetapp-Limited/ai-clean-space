import Foundation
import CoreData
import Combine
import Contacts
import CloudKit

@MainActor
class AICleanerContactsViewModel: ObservableObject, ContactViewModelProtocol {
    @Published var contacts: [ContactData] = []
    @Published var systemContacts: [CNContact] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var showingAddContact = false
    @Published var selectedContact: ContactData?
    @Published var errorMessage: String?
    @Published var showingContactPicker = false
    @Published var importedContactsCount = 0
    @Published var showDeleteFromPhoneAlert = false
    @Published var duplicateGroups: [[CNContact]] = []
    
    private var importedCNContacts: [CNContact] = []
    
    private let persistenceManager = ContactsPersistenceManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSearchSubscription()
        loadContacts()
    }
    
    private func setupSearchSubscription() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.filterContacts()
            }
            .store(in: &cancellables)
    }
    
    var filteredContacts: [ContactData] {
        if searchText.isEmpty {
            return contacts.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
        } else {
            return contacts.filter { contact in
                contact.fullName.localizedCaseInsensitiveContains(searchText) ||
                contact.phoneNumber.contains(searchText) ||
                contact.email?.localizedCaseInsensitiveContains(searchText) == true
            }.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
        }
    }
    
    func loadContacts() {
        isLoading = true
        
        // Блокирующая загрузка из хранилища в фоновом потоке
        Task.detached {
            let loadedContacts = self.persistenceManager.loadContacts()
            
            await MainActor.run {
                self.contacts = loadedContacts
                self.isLoading = false
            }
        }
    }
    
    func addContact(_ contactData: ContactData) {
        persistenceManager.addContact(contactData)
        self.contacts.append(contactData)
    }
    
    func updateContact(_ contactData: ContactData) {
        persistenceManager.updateContact(contactData)
        
        if let index = contacts.firstIndex(where: { $0.id == contactData.id }) {
            contacts[index] = contactData
        }
    }
    
    func deleteContact(_ contactData: ContactData) {
        persistenceManager.deleteContact(withId: contactData.id)
        contacts.removeAll { $0.id == contactData.id }
    }
    
    func deleteContacts(_ contactsToDelete: [ContactData]) {
        for contact in contactsToDelete {
            deleteContact(contact)
        }
    }
    
    private func filterContacts() {
        objectWillChange.send()
    }
    
    // MARK: - Contact Import Functions
    
    func importContacts(_ cnContacts: [CNContact]) {
        var importedCount = 0
        var validCNContacts: [CNContact] = []
        
        for cnContact in cnContacts {
            let contactData = ContactImportHelper.convertToContactData(cnContact)
            
            let exists = contacts.contains { existingContact in
                !contactData.phoneNumber.isEmpty &&
                existingContact.phoneNumber == contactData.phoneNumber
            }
            
            if !exists && !contactData.firstName.isEmpty {
                addContact(contactData)
                validCNContacts.append(cnContact)
                importedCount += 1
            }
        }
        
        importedContactsCount = importedCount
        importedCNContacts = validCNContacts
        
        if importedCount > 0 {
            showDeleteFromPhoneAlert = true
            errorMessage = nil
        }
    }
    
    func clearImportedContactsCount() {
        importedContactsCount = 0
    }
    
    func deleteContactsFromPhone() async {
        let success = await ContactImportHelper.deleteContactsFromPhone(self.importedCNContacts)
        
        await MainActor.run {
            if !success {
                self.errorMessage = "Failed to delete contacts from phone"
            }
            
            self.importedCNContacts.removeAll()
            self.showDeleteFromPhoneAlert = false
        }
    }
    
    func cancelDeleteFromPhone() {
        self.importedCNContacts.removeAll()
        self.showDeleteFromPhoneAlert = false
    }
    
    // MARK: - UI Helper Methods
    
    func showAddContact() {
        selectedContact = nil
        showingAddContact = true
    }
    
    func showEditContact(_ contact: ContactData) {
        selectedContact = contact
        showingAddContact = true
    }
    
    func hideAddContact() {
        showingAddContact = false
        selectedContact = nil
    }
    
    func getContactsCount() -> Int {
        return contacts.count
    }
    
    // MARK: - System Contacts Loading
    
    func loadSystemContacts() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Переносим блокирующую CNContactStore.enumerateContacts в фоновый Task
        let result: Result<[CNContact], Error> = await Task.detached {
            let store = CNContactStore()
            let keysToFetch = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactPhoneNumbersKey,
                CNContactEmailAddressesKey,
                CNContactIdentifierKey,
                CNContactOrganizationNameKey,
                CNContactJobTitleKey,
                CNContactPostalAddressesKey,
                CNContactImageDataKey,
                CNContactThumbnailImageDataKey
            ] as [CNKeyDescriptor]
            
            do {
                let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                var loadedContacts: [CNContact] = []
                
                try store.enumerateContacts(with: request) { contact, _ in
                    let hasName = !contact.givenName.isEmpty || !contact.familyName.isEmpty
                    let hasPhone = !contact.phoneNumbers.isEmpty
                    
                    if hasName || hasPhone || !contact.emailAddresses.isEmpty {
                        loadedContacts.append(contact)
                    }
                }
                return .success(loadedContacts)
            } catch {
                return .failure(error)
            }
        }.value
        
        await MainActor.run {
            self.isLoading = false
            switch result {
            case .success(let loadedContacts):
                self.systemContacts = loadedContacts
                self.calculateDuplicateGroups() // Запускаем асинхронное вычисление дубликатов
            case .failure(let error):
                self.errorMessage = "Failed to load contacts: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Duplicate Detection
    
    func calculateDuplicateGroups() {
        guard !systemContacts.isEmpty else {
            self.duplicateGroups = []
            return
        }
        
        let currentSystemContacts = self.systemContacts
        
        Task.detached {
            var groups: [[CNContact]] = []
            var processedContacts = Set<String>()
                        
            for contact in currentSystemContacts {
                guard !processedContacts.contains(contact.identifier) else { continue }
                
                var duplicateGroup: [CNContact] = [contact]
                processedContacts.insert(contact.identifier)
                
                let contactPhones = contact.phoneNumbers.map { self.normalizePhoneNumber($0.value.stringValue) }
                let contactEmails = contact.emailAddresses.map { String($0.value).lowercased() }
                let contactName = self.normalizeContactName(contact)
                
                for otherContact in currentSystemContacts {
                    guard contact.identifier != otherContact.identifier,
                          !processedContacts.contains(otherContact.identifier) else { continue }
                    
                    let otherPhones = otherContact.phoneNumbers.map { self.normalizePhoneNumber($0.value.stringValue) }
                    let otherEmails = otherContact.emailAddresses.map { String($0.value).lowercased() }
                    let otherName = self.normalizeContactName(otherContact)
                    
                    var isDuplicate = false
                    
                    // 1. Phone number match
                    if !contactPhones.isEmpty && !otherPhones.isEmpty {
                        let hasMatchingPhone = contactPhones.contains { phone in
                            otherPhones.contains(phone) && !phone.isEmpty
                        }
                        if hasMatchingPhone { isDuplicate = true }
                    }
                    
                    // 2. Email match
                    if !isDuplicate && !contactEmails.isEmpty && !otherEmails.isEmpty {
                        let hasMatchingEmail = contactEmails.contains { email in
                            otherEmails.contains(email) && !email.isEmpty
                        }
                        if hasMatchingEmail { isDuplicate = true }
                    }
                    
                    // 3. Similar names with common contact method
                    if !isDuplicate {
                        let namesSimilar = self.areNamesSimilar(contactName, otherName)
                        let hasCommonContactMethod = self.hasCommonPhoneOrEmail(
                            phones1: contactPhones, emails1: contactEmails,
                            phones2: otherPhones, emails2: otherEmails
                        )
                        
                        if namesSimilar && hasCommonContactMethod {
                            isDuplicate = true
                        }
                    }
                    
                    if isDuplicate {
                        duplicateGroup.append(otherContact)
                        processedContacts.insert(otherContact.identifier)
                    }
                }
                
                if duplicateGroup.count > 1 {
                    duplicateGroup.sort { contact1, contact2 in
                        let score1 = self.calculateContactCompleteness(contact1)
                        let score2 = self.calculateContactCompleteness(contact2)
                        return score1 > score2
                    }
                    groups.append(duplicateGroup)
                }
            }
            
            await MainActor.run {
                // Обновляем UI-свойство на главном потоке
                self.duplicateGroups = groups.sorted { $0.count > $1.count }
            }
        }
    }
    
    // MARK: - Nonisolated Helper Methods (Безопасно для фоновой работы)
    
    private nonisolated func normalizePhoneNumber(_ phone: String) -> String {
        return phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    }
    
    private nonisolated func normalizeContactName(_ contact: CNContact) -> String {
        let fullName = "\(contact.givenName) \(contact.familyName)".lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return fullName
    }
    
    private nonisolated func areNamesSimilar(_ name1: String, _ name2: String) -> Bool {
        guard !name1.isEmpty && !name2.isEmpty else { return false }
        
        if name1 == name2 { return true }
        
        if name1.contains(name2) || name2.contains(name1) { return true }
        
        // Вызов nonisolated метода
        let similarity = levenshteinDistance(name1, name2)
        let maxLength = max(name1.count, name2.count)
        
        let threshold = max(2, Int(Double(maxLength) * 0.2))
        return similarity <= threshold && maxLength > 3
    }
    
    private nonisolated func hasCommonPhoneOrEmail(phones1: [String], emails1: [String], phones2: [String], emails2: [String]) -> Bool {
        for phone1 in phones1 {
            if !phone1.isEmpty && phones2.contains(phone1) {
                return true
            }
        }
        
        for email1 in emails1 {
            if !email1.isEmpty && emails2.contains(email1) {
                return true
            }
        }
        
        return false
    }
    
    private nonisolated func calculateContactCompleteness(_ contact: CNContact) -> Int {
        var score = 0
        
        if !contact.givenName.isEmpty { score += 2 }
        if !contact.familyName.isEmpty { score += 2 }
        
        score += contact.phoneNumbers.count * 3
        score += contact.emailAddresses.count * 2
        
        if !contact.organizationName.isEmpty { score += 1 }
        if !contact.jobTitle.isEmpty { score += 1 }
        score += contact.postalAddresses.count
        
        return score
    }
    
    private nonisolated func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        
        var distances = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count {
            distances[i][0] = i
        }
        
        for j in 0...b.count {
            distances[0][j] = j
        }
        
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i-1] == b[j-1] {
                    distances[i][j] = distances[i-1][j-1]
                } else {
                    distances[i][j] = min(
                        distances[i-1][j] + 1,
                        distances[i][j-1] + 1,
                        distances[i-1][j-1] + 1
                    )
                }
            }
        }
        
        return distances[a.count][b.count]
    }
    
    // MARK: - Contact Merging
    
    func mergeContacts(_ contactsToMerge: [CNContact]) async -> Bool {
        guard contactsToMerge.count >= 2 else { return false }
        
        if BackupService.shared.isAutoBackupEnabled {
            await performAutoBackup()
        }
        
        let store = CNContactStore()
        let saveRequest = CNSaveRequest()
        
        do {
            let primaryContact = contactsToMerge.max { contact1, contact2 in
                calculateContactCompleteness(contact1) < calculateContactCompleteness(contact2)
            }!
            
            let allKeysToFetch = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactPhoneNumbersKey,
                CNContactEmailAddressesKey,
                CNContactIdentifierKey,
                CNContactOrganizationNameKey,
                CNContactJobTitleKey,
                CNContactPostalAddressesKey,
                CNContactImageDataKey,
                CNContactThumbnailImageDataKey
            ] as [CNKeyDescriptor]
            
            let mutablePrimaryContact = try store.unifiedContact(
                withIdentifier: primaryContact.identifier,
                keysToFetch: allKeysToFetch
            ).mutableCopy() as! CNMutableContact
            
            mergeDataIntoContact(mutablePrimaryContact, from: contactsToMerge)
            
            saveRequest.update(mutablePrimaryContact)
            
            for contact in contactsToMerge {
                if contact.identifier != primaryContact.identifier {
                    let contactToDelete = try store.unifiedContact(
                        withIdentifier: contact.identifier,
                        keysToFetch: [CNContactIdentifierKey] as [CNKeyDescriptor]
                    ).mutableCopy() as! CNMutableContact
                    
                    saveRequest.delete(contactToDelete)
                }
            }
            
            try store.execute(saveRequest)
            return true
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to merge contacts: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    private func mergeDataIntoContact(_ targetContact: CNMutableContact, from contacts: [CNContact]) {
        var allPhones: [CNLabeledValue<CNPhoneNumber>] = []
        var seenPhones = Set<String>()
        
        for phoneValue in targetContact.phoneNumbers {
            let normalizedPhone = normalizePhoneNumber(phoneValue.value.stringValue)
            if !normalizedPhone.isEmpty {
                seenPhones.insert(normalizedPhone)
                allPhones.append(phoneValue)
            }
        }
        
        for contact in contacts {
            if contact.identifier != targetContact.identifier {
                for phoneValue in contact.phoneNumbers {
                    let normalizedPhone = normalizePhoneNumber(phoneValue.value.stringValue)
                    if !normalizedPhone.isEmpty && !seenPhones.contains(normalizedPhone) {
                        seenPhones.insert(normalizedPhone)
                        allPhones.append(phoneValue)
                    }
                }
            }
        }
        targetContact.phoneNumbers = allPhones
        
        var allEmails: [CNLabeledValue<NSString>] = []
        var seenEmails = Set<String>()
        
        for emailValue in targetContact.emailAddresses {
            let normalizedEmail = String(emailValue.value).lowercased()
            if !normalizedEmail.isEmpty {
                seenEmails.insert(normalizedEmail)
                allEmails.append(emailValue)
            }
        }
        
        for contact in contacts {
            if contact.identifier != targetContact.identifier {
                for emailValue in contact.emailAddresses {
                    let normalizedEmail = String(emailValue.value).lowercased()
                    if !normalizedEmail.isEmpty && !seenEmails.contains(normalizedEmail) {
                        seenEmails.insert(normalizedEmail)
                        allEmails.append(emailValue)
                    }
                }
            }
        }
        targetContact.emailAddresses = allEmails
        
        for contact in contacts {
            if contact.identifier != targetContact.identifier {
                if targetContact.organizationName.isEmpty && !contact.organizationName.isEmpty {
                    targetContact.organizationName = contact.organizationName
                }
                if targetContact.jobTitle.isEmpty && !contact.jobTitle.isEmpty {
                    targetContact.jobTitle = contact.jobTitle
                }
            }
        }
        
        var allAddresses: [CNLabeledValue<CNPostalAddress>] = []
        allAddresses.append(contentsOf: targetContact.postalAddresses)
        
        for contact in contacts {
            if contact.identifier != targetContact.identifier {
                allAddresses.append(contentsOf: contact.postalAddresses)
            }
        }
        targetContact.postalAddresses = allAddresses
        
        if targetContact.imageData == nil {
            for contact in contacts {
                if contact.identifier != targetContact.identifier && contact.imageData != nil {
                    targetContact.imageData = contact.imageData
                    break
                }
            }
        }
    }
    
    func mergeContactGroup(_ group: [CNContact], selectedIds: Set<String>) async -> Bool {
        let selectedContacts = group.filter { selectedIds.contains($0.identifier) }
        
        guard selectedContacts.count >= 2 else {
            await MainActor.run {
                errorMessage = "Please select at least 2 contacts to merge"
            }
            return false
        }
        
        return await mergeContacts(selectedContacts)
    }
    
    // MARK: - Contact Deletion
    
    func deleteContacts(_ contactsToDelete: [CNContact]) async -> Bool {
        guard !contactsToDelete.isEmpty else { return false }
        
        let store = CNContactStore()
        let saveRequest = CNSaveRequest()
        
        do {
            for contact in contactsToDelete {
                let contactToDelete = try store.unifiedContact(
                    withIdentifier: contact.identifier,
                    keysToFetch: [CNContactIdentifierKey] as [CNKeyDescriptor]
                ).mutableCopy() as! CNMutableContact
                
                saveRequest.delete(contactToDelete)
            }
            
            try store.execute(saveRequest)
            return true
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete contacts: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    // MARK: - Auto Backup
    
    private func performAutoBackup() async {
        let contactsManager = ContactsPersistenceManager.shared
        let contacts = contactsManager.loadContacts()
        
        guard !contacts.isEmpty else { return }
        
        let iCloudService = iCloudBackupService()
        let success = await iCloudService.backupContacts(contacts)
    }
}
